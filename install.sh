#!/usr/bin/env bash
# Install/update everything this vim config needs, then wire the repo in:
# system deps + yarn, point ~/.vimrc at ./vimrc, install plugins headlessly.
#
# Supported platforms — these two only:
#   • Ubuntu 26.04 LTS  (apt)
#   • macOS             (Homebrew)
#
# Idempotent — safe to re-run any time. Orchestrators (e.g.
# best-linux-environment) clone/update this repo and just call ./install.sh;
# this script owns every vim-specific step, the orchestrator knows nothing.
#
# Usage: ./install.sh [--dry-run]     (also honours DRY_RUN=true/1/yes from the env)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fail closed on anything unrecognised. This script rewrites ~/.vimrc, so a
# mistyped `--dryrun` silently running the real thing is not an acceptable
# outcome — it has to stop rather than guess.
usage() {
    cat <<'USAGE'
Usage: ./install.sh [--dry-run] [--languages=LIST] [-h|--help]

  --dry-run         Print what would be installed and changed, touching
                    nothing. Also honoured in the environment as DRY_RUN, which
                    takes true/1/yes or false/0/no — anything else is an error.
  --languages=LIST  Skip the questions: a comma-separated list of php,
                    javascript, python, c — or 'all', or 'none'. This is the
                    full set you want, so anything missing from it is REMOVED.
  -h, --help        Show this message.

With no --languages and a terminal to ask on, the script asks about each
language, offering to keep the ones you already have. With no terminal (CI, or
an orchestrator calling this script) it keeps whatever was chosen last time, and
installs all of them only when nothing has been chosen yet.

Dropping a language deletes the plugins it brought and its language server from
~/.config/coc/extensions. Only ever those: anything you installed yourself is
left alone, as are system packages — clangd stays installed for whatever else
uses it.
USAGE
}
LANG_OPT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=true; shift ;;
        --languages=*)  LANG_OPT="${1#--languages=}"
                        # An empty value is rejected rather than ignored. "" is
                        # also what "flag absent" looks like below, so letting it
                        # through would make `--languages=` — a plausible slip
                        # for `--languages=none` — mean "ask", or on a machine
                        # with no terminal "install all four": the opposite of
                        # what was typed, silently.
                        if [[ -z "$LANG_OPT" ]]; then
                            printf 'install.sh: --languages= needs a value, e.g. --languages=none\n\n' >&2
                            usage >&2
                            exit 2
                        fi
                        shift ;;
        --languages)    printf 'install.sh: --languages needs a value, e.g. --languages=php,c\n\n' >&2
                        usage >&2
                        exit 2 ;;
        -h|--help)      usage; exit 0 ;;
        *)              printf 'install.sh: unknown option: %s\n\n' "$1" >&2
                        usage >&2
                        exit 2 ;;
    esac
done
# Normalised once, and fails closed on anything else — same rule as the flag
# parser above, and for the same reason. Every check below is `== true`, so an
# unnormalised DRY_RUN=1 read as false and ran the real thing: sudo apt-get
# install, ~/.vimrc rewritten, and purge_orphans' rm -rf over plugged/ and
# ~/.config/coc/extensions. `1` and `yes` are the two commonest spellings of a
# boolean env var, and the usage text advertises this variable without saying
# the value has to be the literal word `true`, so the flag would have done the
# exact opposite of what was asked, silently.
case "${DRY_RUN:-false}" in
    true|TRUE|True|1|yes|YES|y)  DRY_RUN=true ;;
    false|FALSE|False|0|no|NO|n) DRY_RUN=false ;;
    *)  printf 'install.sh: DRY_RUN must be true or false (got: %s)\n\n' "$DRY_RUN" >&2
        usage >&2
        exit 2 ;;
esac

# ── Self-contained helpers (no external lib — this repo installs alone) ──────
if [[ -t 1 ]]; then
    C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
    C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi
# warn() writes to stderr, so its colours follow fd 2 — otherwise redirecting
# just one of the two streams to a file fills it with escape codes.
if [[ -t 2 ]]; then
    C_YELLOW=$'\033[1;33m'; C_OFF2=$'\033[0m'
else
    C_YELLOW=''; C_OFF2=''
fi
step()  { printf '%s▸%s %s\n' "$C_BLUE"  "$C_OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip()  { printf '%s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
# To stderr, unlike the others: warnings and the hard-stop messages below are
# the reason to read a saved log, and `./install.sh >log` should not bury them.
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF2" "$*" >&2; }
title() { printf '\n%s══ %s ══%s\n' "$C_BOLD" "$*" "$C_OFF"; }
run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s %s\n' "$C_DIM" "$C_OFF" "$*"
    else
        "$@"
    fi
}
has_cmd() { command -v "$1" >/dev/null 2>&1; }
# Of the names in $2…, the ones that actually have a directory under $1, as a
# space-separated list. Callers test it with -n and iterate it unquoted, which
# is why it is a string rather than an array: macOS ships bash 3.2 (see the note
# on ALL_LANGS below).
dirs_present() {
    local parent="$1" name out=""
    shift
    for name in $*; do
        [[ -d "$parent/$name" ]] && out="${out:+$out }$name"
    done
    printf '%s' "$out"
}
# Temp files go through one directory and one trap: a second `trap … EXIT`
# silently replaces the first, leaking whatever the earlier one was there to
# clean up. Hence also cleanup() rather than an inline `rm -rf` — everything
# that has to happen on the way out hangs off this one handler.
#
# A directory rather than a registry of paths, because every caller is
# `x="$(tmpfile …)"` — a command substitution, so it runs in a subshell, and
# bookkeeping done in a subshell is thrown away with it. Naming the files keeps
# tmpfile() stateless; the `: >` reaches the real filesystem, so callers get a
# file that already exists rather than one vim has to create before it can be
# read back.
TMPDIR_SELF="$(mktemp -d)"

# Set while languages.vim holds the momentary all-four write that snapshot_config
# needs (see the CFG_ALL block below), and cleared once the real selection is
# back. Without this an interrupt in that window leaves the file claiming all
# four — which the next unattended run reads as a deliberate answer and
# reinstalls every language server from, silently undoing an explicit
# --languages=c.
LANG_FILE_DIRTY=false

# Set when a package install failed and the run carried on regardless (see
# apt_ensure/brew_ensure below). Everything past the package step — wiring
# ~/.vimrc, the plugins, the cleanup — needs nothing from the package manager,
# so a held dpkg lock is no reason to lose it. But the run is not a clean one
# either, and an orchestrator reads the exit status rather than the output, so
# the last lines of this script turn this back into a non-zero exit.
INSTALL_DEGRADED=false
cleanup() {
    if [[ "$LANG_FILE_DIRTY" == true ]]; then
        LANG_FILE_DIRTY=false        # idempotent: EXIT may follow another trap
        write_langs "$SELECTED" quiet || true
    fi
    rm -rf "$TMPDIR_SELF"
}
# EXIT alone, with no INT/TERM/HUP handlers alongside it: bash runs an EXIT trap
# when a script dies from any of those, so Ctrl-C is covered and separate traps
# for them would only run cleanup twice.
#
# SIGKILL is the one that isn't covered, since it runs no handler at all. Should
# it land in the window, the file is left saying all four — the same thing a
# missing file means, so the next run reads it as "nobody has chosen yet".
trap cleanup EXIT
tmpfile() {
    local f="$TMPDIR_SELF/$1"
    : > "$f"
    printf '%s' "$f"
}
# Empty when this is already root, so the calls below run the package manager
# directly. `sudo` is not a given on a machine you are root on — a container
# image usually has no such package — and expanded unquoted an empty $SUDO
# vanishes rather than becoming an empty first argument.
SUDO=sudo
[[ "$EUID" -eq 0 ]] && SUDO=""

# Whether the apt calls below can actually elevate. Two things have to hold, and
# only the second used to be checked.
#
# There has to be a way to elevate at all: root needs none, and a non-root shell
# with no sudo installed has none. That is the case a terminal on stdin used to
# answer on its own — so in a root container this said yes, `apt-get update` fell
# into its `|| warn`, and the `apt-get install` on the next line then died at 127
# under `set -e`, taking the plugin install and everything after it with it. A
# missing sudo now routes into the same graceful skip a non-interactive run gets.
#
# And it has to work without asking: sudo only elevates here with a terminal for
# the password prompt, or with credentials already cached. Boot and cron runs
# must never hang waiting for one.
can_sudo() {
    [[ -z "$SUDO" ]] && return 0
    has_cmd sudo || return 1
    [[ -t 0 ]] || sudo -n true 2>/dev/null
}
apt_ensure() {
    local pkg missing=()
    for pkg in "$@"; do dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
    [[ ${#missing[@]} -eq 0 ]] && { skip "apt: nothing to install (${*})."; return 0; }
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would install:%s %s\n' "$C_DIM" "$C_OFF" "${missing[*]}"; return 0
    fi
    if ! can_sudo; then
        # Both halves of can_sudo() named, since the fix differs: install sudo,
        # or run this from a terminal / with credentials already cached.
        if has_cmd sudo; then
            warn "sudo unavailable (non-interactive) — skipped apt install: ${missing[*]}"
        else
            warn "sudo is not installed and this is not root — skipped apt install: ${missing[*]}"
        fi
        return 0
    fi
    step "apt: installing ${missing[*]}"
    # $SUDO unquoted: empty as root, where it has to disappear entirely rather
    # than become an empty first argument to apt-get.
    $SUDO apt-get update -qq || warn "apt update reported errors — continuing."
    # Tolerated, like the update above and every other failure in this script.
    # This runs under `set -e` as a plain statement, so an unguarded apt-get
    # took the whole install down with it: no ~/.vimrc, no plugins, no cleanup —
    # none of which needs apt at all. The failures are ordinary ones, too, and
    # the likeliest of them lands on exactly the run nobody is watching:
    # unattended-upgrades holding the dpkg lock during a boot-time run, an
    # unreachable mirror, a package renamed in a later release, or a mistyped
    # sudo password (can_sudo() answers yes on a terminal without checking that
    # sudo actually works).
    if ! $SUDO apt-get install -y "${missing[@]}"; then
        warn "apt install failed: ${missing[*]} — continuing without them."
        warn "Re-run ./install.sh once apt is free; everything else is applied now."
        INSTALL_DEGRADED=true
    fi
}
brew_ensure() {
    local pkg missing=()
    for pkg in "$@"; do brew list --formula "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
    [[ ${#missing[@]} -eq 0 ]] && { skip "brew: nothing to install (${*})."; return 0; }
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would install:%s %s\n' "$C_DIM" "$C_OFF" "${missing[*]}"; return 0
    fi
    step "brew: installing ${missing[*]}"
    # Tolerated for the reason spelled out in apt_ensure() above — same shape,
    # same cost if it aborts: everything after the package step needs nothing
    # from brew.
    if ! brew install "${missing[@]}"; then
        warn "brew install failed: ${missing[*]} — continuing without them."
        warn "Re-run ./install.sh once brew works; everything else is applied now."
        INSTALL_DEGRADED=true
    fi
}
# Idempotently make sure $line is in $file. Two modes:
#   replace — this script owns the whole file (~/.vimrc); anything already
#             there is backed up first.
#   append  — the file belongs to the user (a shell profile); add to the end.
ensure_line() {
    local line="$1" file="$2" mode="${3:-append}"
    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        skip "$file already has it."
        return
    fi
    # The message is phrased from DRY_RUN rather than the copy being left to
    # run(): "backing up to …" printed unconditionally described a backup that
    # --dry-run never makes, which is the one claim a dry run must not get wrong.
    if [[ "$mode" == replace && -s "$file" ]]; then
        local backup="$file.backup.$$"
        if [[ "$DRY_RUN" == true ]]; then
            warn "$file exists — would back it up to $backup"
        else
            warn "$file exists — backing up to $backup"
            cp "$file" "$backup"
        fi
    fi
    # A redirect follows a symlink, so `> "$file"` on a ~/.vimrc symlinked into a
    # dotfiles repo — which is how anyone who would install this config keeps
    # theirs — rewrote the file at the far end, in a repo this script was never
    # pointed at. Nothing was lost, since the backup above is a plain copy of the
    # contents, but the first you heard of it was an unexplained modified file in
    # `git status` somewhere else. The link is replaced instead; said out loud,
    # because breaking it is a change to how the user's dotfiles are wired.
    #
    # Only in replace mode. Append mode edits a file that belongs to the user — a
    # shell profile, quite reasonably symlinked — and there the far end is exactly
    # where the line should go.
    #
    # Phrased from DRY_RUN, like the backup message above: a dry run has to
    # describe this, and must not claim to have done it.
    if [[ "$mode" == replace && -L "$file" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            warn "$file is a symlink to $(readlink "$file") — would replace the link, not its target."
        else
            warn "$file is a symlink to $(readlink "$file") — replacing the link, not its target."
        fi
    fi
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would %s:%s %s → %s\n' \
            "$C_DIM" "$([[ "$mode" == replace ]] && echo write || echo append)" \
            "$C_OFF" "$line" "$file"
        return
    fi
    if [[ "$mode" == replace ]]; then
        # rm first, so the write lands on the path itself rather than through it.
        # Also clears a dangling link, which -f and -s above both read as absent.
        rm -f "$file"
        printf '%s\n' "$line" > "$file"
        ok "wired $file"
    else
        printf '\n%s\n' "$line" >> "$file"
        ok "appended to $file — open a new terminal for it to take effect."
    fi
}
# Which file a PATH export belongs in depends on the login shell — writing to
# ~/.zshrc for a bash user puts it somewhere that shell never reads. Empty
# output means "not a shell we know", and the caller falls back to telling the
# user the line to add by hand.
shell_profile() {
    case "$(basename -- "${SHELL:-}")" in
        zsh)  printf '%s' "$HOME/.zshrc" ;;
        bash) printf '%s' "$HOME/.bash_profile" ;;
        *)    printf '' ;;
    esac
}

# ── Language support ─────────────────────────────────────────────────────────
# Which languages get plugins is a choice, not a constant: each one costs a
# language server of tens to hundreds of megabytes plus a node process per open
# buffer, so a machine you only write C on has no reason to carry intelephense
# and tsserver. The answer is written to config_files/languages.vim, which vimrc
# sources before plug.vim and coc.vim — those two declare a language's plugins
# only if it is named there.
#
# Re-running is how you change your mind in either direction: the questions
# offer to keep what is already installed, so a bare Enter never drops anything,
# but an explicit "n" removes the language and everything it brought (see
# purge_orphans below).
#
# Plain string lists, not arrays: macOS ships bash 3.2, which has no
# associative arrays, and this script has to run there unchanged.
#
# ALL_LANGS is spelled a second time as the fallback in vimrc's
# `get(g:, 'vim_languages', […])`, which is what a clone with no languages.vim
# gets — bash and Vimscript have no way to share one list, so the two are kept in
# step by hand. A fifth language means touching, here: this line, lang_label(),
# lang_brings() and the `case` in the --languages parser; then vimrc's fallback,
# plug.vim, coc.vim and the table in README section 4. Miss the vimrc one and a
# fresh clone silently omits the language while the README says it has all of
# them.
LANG_FILE="$REPO/config_files/languages.vim"
ALL_LANGS="php javascript python c"

lang_label() {
    case "$1" in
        php)        printf 'PHP — Laravel, Blade templates' ;;
        javascript) printf 'JavaScript / TypeScript — React, Next.js, Tailwind' ;;
        python)     printf 'Python' ;;
        c)          printf 'C' ;;
    esac
}
# What choosing it actually pulls in, so the questions aren't a leap of faith.
# Prettier, CSS and Tailwind are listed under both web languages because either
# one is enough to install them — see the block in config_files/coc.vim.
lang_brings() {
    case "$1" in
        php)        printf 'intelephense, blade syntax, prettier, css, tailwind' ;;
        javascript) printf 'tsserver, eslint, jsx syntax, prettier, css, tailwind' ;;
        python)     printf 'pyright' ;;
        c)          printf 'clangd (system package) + coc-clangd' ;;
    esac
}
# SELECTED is what this run ends up with, PREVIOUS what the last one left.
# Both are space-padded on both sides when tested, so that 'c' never matches
# inside 'javascript'.
has_lang() { case " $SELECTED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
was_lang() { case " $PREVIOUS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
add_lang()  { has_lang "$1" || SELECTED="${SELECTED:+$SELECTED }$1"; }
# Alphabetical and de-duplicated, so re-runs that change nothing rewrite the
# same bytes and the file never drifts into two spellings of one selection.
sorted_langs() { [[ -n "$SELECTED" ]] && printf '%s\n' $SELECTED | sort -u; }
# 'all' and 'none' each state the whole set on their own, so combining either
# with a language name is a contradiction rather than a shorthand. $1 is the
# word, $2 how many were given.
#
# Fail closed rather than resolve it, like the unknown-name case in the parser
# below: this flag *removes* whatever it leaves out, so a misread costs plugins
# and a language server. Resolving silently also picked a winner by list order —
# php,none and none,php disagreed — which is no answer at all.
lang_alone() {
    if [[ "$2" -gt 1 ]]; then
        warn "--languages=${LANG_OPT}: '$1' is the whole list — it can't be combined with language names."
        warn "Use --languages=$1 on its own, or name the languages you want."
        warn "Nothing was changed."
        exit 2
    fi
}
# Read the previous answers back. Grepped for the one line that matters rather
# than sourced — this is a vim script, and its comments quote language names too.
# Both quote styles, since the file's header invites hand-editing.
#
# Then narrowed to the [...] itself before the names are picked out. Isolating
# the line is not enough: the same header invites hand-editing, and `let
# g:vim_languages = ['c']  " dropped 'php' in March` read back as `c php` —
# which, since --languages removes whatever it leaves out, is a selection nobody
# chose either way round. The two negated classes anchor on the *first* bracket
# pair, so a `[php]` inside that trailing comment can't be the one matched
# either; a greedy `.*\[` would have taken the last.
#
# Three distinct answers, and the third is why this returns a *status* as well
# as a list. No file at all means *all four*, matching vimrc's own fallback, so
# it reports the state the editor is really in. A file whose list is genuinely
# empty — `= []`, which is exactly what --languages=none writes — returns 0 with
# nothing on stdout, an empty previous selection. And a file with no readable
# `let g:vim_languages = [...]` line in it at all returns 1, which is neither of
# those and must not be flattened into the second.
#
# It used to be, and the cost was not a cosmetic misreading. The unattended
# branch below takes the file's mere existence as an answer somebody gave, so an
# unparsable line became an empty SELECTED and purge_orphans() then deleted every
# language plugin and every language server — on the run nobody is watching,
# reporting nothing as dropped, because REMOVED is computed from the same empty
# list. Two edits the file's own header invites reached that: an indented `let`,
# and a name spelled with a capital.
#
# Hence also the widened patterns. Leading whitespace is allowed, and names are
# matched in either case and folded down. POSIX classes and \{1,\} rather than
# \s and +: BSD grep on macOS has neither.
#
# The 'LIST:' prefix is a sentinel, for the same reason the snapshots above
# carry one. sed prints an empty line for `= []` and nothing at all for a line
# it cannot match, and command substitution strips the newline that told those
# two apart — so without a prefix to test, "the list is empty" and "there is no
# list here" arrive as the same empty string, which is the conflation this whole
# note is about.
#
# '|| true' is load-bearing: an unmatched grep exits 1, pipefail propagates it,
# and the assignment would trip set -e.
read_langs() {
    if [[ ! -f "$LANG_FILE" ]]; then
        printf '%s' "$ALL_LANGS"
        return 0
    fi
    local inner
    inner="$(grep -m1 '^[[:space:]]*let[[:space:]]\{1,\}g:vim_languages' "$LANG_FILE" 2>/dev/null |
        sed -n 's/^[^[]*\[\([^]]*\)\].*/LIST:\1/p')" || true
    [[ -z "$inner" ]] && return 1
    printf '%s' "${inner#LIST:}" |
        grep -o "['\"][A-Za-z]\{1,\}['\"]" | tr -d "'\"" |
        tr '[:upper:]' '[:lower:]' | tr '\n' ' ' || true
    return 0
}
# $1 is the language list to write; $2 'quiet' suppresses the confirmation, for
# the momentary all-four write that snapshot_config needs below.
write_langs() {
    local langs="$1" quiet="${2:-}" list="" l
    for l in $(printf '%s\n' $langs | LC_ALL=C sort -u); do list="$list, '$l'"; done
    list="[${list#, }]"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s %s → %s\n' \
            "$C_DIM" "$C_OFF" "let g:vim_languages = $list" "$LANG_FILE"
        return
    fi
    cat > "$LANG_FILE" <<VIMLANG
" Which languages this vim has support installed for. GENERATED by ./install.sh
" and untracked; re-run it to change the list, or clear leftovers yourself.
let g:vim_languages = $list
VIMLANG
    [[ "$quiet" == quiet ]] || ok "wrote $LANG_FILE"
}

# Everything the config declares right now: where vim-plug keeps its plugins,
# plugin directory names, and coc extensions, one per line, tagged. Read out of
# vim itself rather than parsed out of plug.vim and coc.vim, so which plugins
# belong to which language is written down in exactly one place and this can
# never disagree with it.
#
# PLUGHOME is read out for the same reason rather than assumed to be
# "$REPO/plugged". plug#begin() is called with no argument, so vim-plug resolves
# it as `split(&rtp, ',')[0] . '/plugged'` — always ~/.vim/plugged, wherever this
# checkout happens to be. From a worktree or a test checkout (which vimrc
# supports on purpose — see g:vim_root there) "$REPO/plugged" is a directory that
# does not exist, so the plugin half of purge_orphans() quietly removed nothing
# while the coc half reported success.
#
# -u the repo's vimrc rather than ~/.vimrc: this runs before ~/.vimrc is wired,
# and the answer must come from the checkout being installed either way.
#
# The leading 'snapshot' line is a sentinel, for the same reason the plugin
# check further down writes 'checked': without it an empty file is ambiguous.
# It means both "vim never got this far" and "the config declares nothing" —
# and since purge_orphans() below works by diffing two of these, the second
# reading turns into "delete everything". Both readings are reachable: the vim
# run is deliberately swallowed with `|| true`, so a vim that is killed, or a
# vimrc that errors before coc.vim is sourced (leaving g:coc_global_extensions
# undefined, so the writefile() itself throws), lands here either way.
#
# The output path reaches vim in the environment rather than spliced into the
# +cmd. It comes from mktemp -d, which honours $TMPDIR, and a single quote
# anywhere in that path closed the Vimscript string and handed the rest of this
# line to vim as commands to run. $VIMSNAP_OUT is vim reading an environment
# variable, so the path is data and never parsed as source — the same reason the
# package.json rewrite in purge_orphans() passes its arguments that way.
snapshot_config() {
    VIMSNAP_OUT="$1" vim -es -u "$REPO/vimrc" +"call writefile(['snapshot', 'PLUGHOME:' . get(g:, 'plug_home', '')] + map(sort(keys(g:plugs)), '\"PLUG:\" . v:val') + map(copy(g:coc_global_extensions), '\"COC:\" . v:val'), \$VIMSNAP_OUT)" +qall >/dev/null 2>&1 || true
}
snapshot_ok() { [[ "$(head -n 1 "$1" 2>/dev/null)" == snapshot ]]; }
# Where vim-plug puts plugins, per the snapshot. Falls back to the old
# assumption if the line is missing or empty — an older snapshot, or a
# plug#begin() that bailed before setting g:plug_home.
snapshot_plug_home() {
    local home
    home="$(grep -m1 '^PLUGHOME:' "$1" 2>/dev/null | sed 's/^PLUGHOME://')" || true
    printf '%s' "${home:-$REPO/plugged}"
}

# Where coc keeps its extensions. Same resolution order coc uses, so a
# COC_DATA_HOME or XDG_CONFIG_HOME pointing elsewhere is honoured rather than
# leaving this script deleting from a directory nobody reads.
coc_ext_root() {
    printf '%s' "${COC_DATA_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/coc}/extensions"
}

# Delete anything installed for a language that is not selected any more.
#
# Driven by what is on disk against what the config declares now — not by what
# the previous run happened to record. History-based cleanup can only fix the
# transition it witnessed, so anything installed before this list existed, or by
# a run that died halfway, stayed for ever. State-based cleanup converges on the
# right answer from wherever it starts, which also means every re-run tidies up.
#
# $1 is a snapshot of the config pointed at all four languages — everything it
# could ever declare — and $2 the same config as the user just chose it. The
# difference is what a language brings, so extensions and plugins you installed
# by hand are never in it: the config declares those under no selection at all.
purge_orphans() {
    local before="$1" after="$2" name dir root plug_home gone_plugs orphans purged stale left

    # Nothing is deleted until both snapshots are known to be complete — see the
    # sentinel note on snapshot_config() above.
    #
    # The two directions are not symmetrical. A missing 'after' is the dangerous
    # one: the diff would attribute every plugin and every language server to a
    # language nobody selected, and this function would then remove the lot. It
    # gets a warning. A missing 'before' only means nothing can be attributed to
    # a language at all, so the diff is empty and nothing is removed — which is
    # also the normal state on a fresh box, where vim is installed a few steps
    # after that first snapshot is taken. That one just says so quietly.
    if ! snapshot_ok "$after"; then
        warn "Could not read what the config declares — vim exited early."
        warn "Nothing was removed. Re-run ./install.sh once vim starts cleanly."
        return 0
    fi
    if ! snapshot_ok "$before"; then
        skip "Nothing to clean up (the full plugin list could not be read)."
        return 0
    fi

    # LC_ALL=C throughout: comm compares bytes, while sort in a UTF-8 locale
    # collates by dictionary rules that ignore punctuation — so
    # '@yaegassy/coc-intelephense' lands either side of 'coc-blade' depending on
    # which is asked, and comm then bails with "file 1 is not in sorted order".
    gone_plugs="$(LC_ALL=C comm -23 <(grep '^PLUG:' "$before" | sed 's/^PLUG://' | LC_ALL=C sort -u) \
                                    <(grep '^PLUG:' "$after"  | sed 's/^PLUG://' | LC_ALL=C sort -u))"
    orphans="$(LC_ALL=C comm -23 <(grep '^COC:' "$before" | sed 's/^COC://' | LC_ALL=C sort -u) \
                                 <(grep '^COC:' "$after"  | sed 's/^COC://' | LC_ALL=C sort -u))"

    # Plugins. Deleted by name, rather than by handing the job to PlugClean!.
    #
    # PlugClean! is vim-plug's non-interactive clean, and it removes *every*
    # directory under plugged/ that the config does not declare — not just the
    # ones named above. So a plugin you cloned in there by hand, which no
    # language owns and this script never installed, went with them. That is the
    # one thing the language cleanup promises not to touch: it is driven by a
    # diff precisely so that it only ever removes what the four languages bring.
    #
    # Deleting the listed directories does exactly what PlugClean does to them —
    # vim-plug keeps no index, a plugin is the directory — and costs no vim
    # start, so there is also no log to keep or explain.
    #
    # 'after' rather than 'before' for the plugin home: it is the snapshot
    # already required to be complete above, and both are written by the same vim
    # anyway.
    plug_home="$(snapshot_plug_home "$after")"
    stale="$(dirs_present "$plug_home" $gone_plugs)"
    if [[ -n "$stale" ]]; then
        step "Removing plugins: $stale"
        for name in $stale; do
            # Guarded rather than trusted, exactly like the coc block below:
            # $name comes from the config, but this is an rm -rf and a stray
            # empty value would aim it at plugged/ itself.
            if [[ -n "$name" && -d "$plug_home/$name" ]]; then
                rm -rf "$plug_home/$name"
            fi
        done
        left="$(dirs_present "$plug_home" $stale)"
        # One outcome or the other. Warning that a plugin is still on disk and
        # then reporting success in the next line said both at once.
        if [[ -n "$left" ]]; then
            warn "These plugins are still on disk: $left"
            warn "Remove them by hand, or run :PlugClean inside vim to finish."
        else
            ok "plugins removed."
        fi
    fi

    # Language servers. coc has no headless uninstall worth relying on — its
    # :CocUninstall only exists once the node service is up, which `vim -es`
    # does not wait for — so this does what coc's own uninstall does: drop the
    # dependency, then delete the directory.
    #
    # package.json first, deliberately. coc reinstalls anything still listed
    # there on the next launch, so deleting only the directory would quietly
    # undo itself; delisting first means an interrupted run leaves at worst an
    # unreferenced directory, which nothing loads.
    #
    # That rewrite goes to a sibling file and is renamed over the original,
    # rather than written in place. writeFileSync truncates before it writes, so
    # an interrupt in that window (Ctrl-C, a full disk) leaves a half-written
    # package.json — and coc then fails to load *every* extension, not just the
    # ones being dropped, until someone repairs it by hand. rename() inside one
    # directory is atomic, so the file is only ever the old one or the new one.
    if [[ -n "$orphans" ]]; then
        root="$(coc_ext_root)"
        purged="$(dirs_present "$root/node_modules" $orphans)"
        if [[ -z "$purged" ]]; then
            skip "coc: no language servers to remove."
        else
            step "Removing language servers: $purged"
            if [[ -f "$root/package.json" ]] && has_cmd node; then
                COC_PKG="$root/package.json" COC_NAMES="$purged" node -e '
                    const fs = require("fs");
                    const file = process.env.COC_PKG;
                    const names = process.env.COC_NAMES.split(" ").filter(Boolean);
                    const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
                    for (const name of names) {
                        if (pkg.dependencies) delete pkg.dependencies[name];
                    }
                    const tmp = file + ".install-sh.tmp";
                    fs.writeFileSync(tmp, JSON.stringify(pkg, null, 2) + "\n");
                    fs.renameSync(tmp, file);
                ' || warn "Could not update ${root}/package.json — coc may reinstall these."
            else
                warn "No ${root}/package.json (or no node) — coc may reinstall these."
            fi
            for name in $purged; do
                dir="$root/node_modules/$name"
                # Guarded rather than trusted: $name comes from the config, but
                # this is an rm -rf and a stray empty value would aim it at
                # node_modules itself.
                if [[ -n "$name" && -d "$dir" ]]; then
                    rm -rf "$dir"
                    # A scoped name (@yaegassy/coc-intelephense) leaves its
                    # scope directory behind. rmdir, not rm -rf: it removes the
                    # leftover and refuses if another extension still lives there.
                    case "$name" in
                        */*) rmdir "$(dirname "$dir")" 2>/dev/null || true ;;
                    esac
                fi
            done
            ok "language servers removed (freed $(printf '%s' "$purged" | wc -w | tr -d ' ') extension(s))."
            # For the caller: what actually went, not what was merely deselected.
            PURGED_EXT="$purged"
        fi
    fi
}

# ── Platform ─────────────────────────────────────────────────────────────────
# Ubuntu 26.04 LTS and macOS are the two supported targets. Anything else is a
# hard stop rather than a best-effort guess: the package names differ per
# distro, and a half-installed toolchain fails later in ways that look like
# config bugs.
PLATFORM=unsupported
OS_LABEL="$(uname -s)"
case "$(uname -s)" in
    Darwin)
        PLATFORM=macos
        OS_LABEL="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
        ;;
    Linux)
        if [[ -r /etc/os-release ]]; then
            # shellcheck disable=SC1091
            # Trailing newline matters: without it `read` returns non-zero at
            # EOF and `set -e` kills the script here.
            read -r distro_id distro_ver < <(
                . /etc/os-release && printf '%s %s\n' "${ID:-}" "${VERSION_ID:-}"
            )
            OS_LABEL="${distro_id:-linux} ${distro_ver:-}"
            [[ "$distro_id" == ubuntu ]] && PLATFORM=ubuntu
        fi
        ;;
esac

if [[ "$PLATFORM" == unsupported ]]; then
    warn "Unsupported platform: ${OS_LABEL}."
    warn "This config installs on Ubuntu 26.04 LTS and macOS only."
    exit 1
fi
if [[ "$PLATFORM" == ubuntu && "${distro_ver:-}" != "26.04" ]]; then
    warn "Targeted at Ubuntu 26.04 LTS; found ${distro_ver:-unknown} — continuing, package names may differ."
fi

# ── This checkout has to be reachable as ~/.vim ───────────────────────────────
# Everything this script installs is loaded *through* that path: 'runtime vimrc'
# resolves via vim's runtimepath, which includes ~/.vim and not this directory;
# so does the autoload/plug.vim that plug#begin() needs, and coc reads its
# settings from ~/.vim/coc-settings.json.
#
# Where it lands, not what it is spelled: ~/.vim is legitimately a symlink to a
# checkout somewhere else — that is how best-linux-environment wires it, cloning
# to ~/linux-configuration/vim and linking — and comparing the two path *strings*
# called that broken and warned about it on every boot.
#
# Fatal rather than a warning, and here rather than down with the install: a run
# that gets past this point writes languages.vim, rewrites ~/.vimrc and starts
# vim four times, and with the link missing none of it is ever loaded. That run
# used to end on "✓ Vim ready" and exit 0, so both the reader and an orchestrator
# checking the status were told a dead install had worked.
VIM_HOME_REAL="$(cd -P "$HOME/.vim" 2>/dev/null && pwd -P || true)"
REPO_REAL="$(cd -P "$REPO" && pwd -P)"
if [[ "$VIM_HOME_REAL" != "$REPO_REAL" ]]; then
    warn "This checkout is not reachable as ~/.vim, so nothing it installs would load."
    warn "  this repo: $REPO_REAL"
    warn "  ~/.vim:    ${VIM_HOME_REAL:-does not exist}"
    warn "Link it, then re-run:"
    warn "    ln -s \"$REPO_REAL\" \"$HOME/.vim\""
    exit 1
fi

# ── Choose the languages ─────────────────────────────────────────────────────
# Runs before the package install, which needs the answer: clangd is only worth
# fetching if C is in it.
title "Language support"
# An unreadable languages.vim is not an empty one — see the note on read_langs().
# "We cannot tell" is answered the same way a missing file is, with all four,
# and that is the safe direction rather than merely the conservative one:
# purge_orphans() works off what is actually on disk, so over-stating what was
# installed can only ever leave something in place, while under-stating it
# deletes. The interactive branch below then offers each language as [Y/n], so a
# bare Enter still keeps what you have — which is what the file's header and
# README section 4 promise anyone who hand-edits it.
if PREVIOUS="$(read_langs)"; then
    LANG_UNREADABLE=false
else
    LANG_UNREADABLE=true
    PREVIOUS="$ALL_LANGS"
    warn "Could not read a language list from $LANG_FILE."
    warn "Assuming every language is installed, so nothing is deleted by mistake."
    warn "Fix its 'let g:vim_languages = [...]' line, or re-run with --languages=… to set it outright."
fi
PREVIOUS="${PREVIOUS% }"            # read_langs leaves a trailing space
SELECTED=""                         # rebuilt from this run's answers

if [[ -n "$LANG_OPT" ]]; then
    # The flag states the whole set you want, so it removes as well as adds —
    # anything it leaves out is dropped. A bad name is fatal: `--languages=pyhton`
    # that quietly installed nothing would look identical to one that worked,
    # and with removal in play it would also throw away everything else.
    #
    # Normalised into a variable rather than expanded straight into the `for`,
    # because lang_alone() needs to know how many words were given — see there
    # for why mixing 'all' or 'none' with a name is rejected rather than resolved.
    LANG_WORDS="$(printf '%s' "$LANG_OPT" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"
    LANG_COUNT="$(printf '%s' "$LANG_WORDS" | wc -w | tr -d ' ')"
    for lang in $LANG_WORDS; do
        case "$lang" in
            all)  lang_alone all "$LANG_COUNT"
                  for l in $ALL_LANGS; do add_lang "$l"; done ;;
            none) lang_alone none "$LANG_COUNT" ;;
            php|javascript|python|c) add_lang "$lang" ;;
            *)    warn "Unknown language: ${lang}"
                  warn "--languages takes: php, javascript, python, c — or all, or none."
                  warn "Nothing was changed."
                  exit 2 ;;
        esac
    done
    step "Languages set by --languages=${LANG_OPT}"
elif [[ ! -t 0 ]]; then
    # No terminal to ask on: CI, or an orchestrator like best-linux-environment
    # running this unattended.
    #
    # An existing languages.vim is an answer somebody already gave, so it is
    # kept rather than overruled. Installing all four regardless would undo a
    # deliberate `--languages=c` — three language servers and coc-clangd
    # reinstalled, hundreds of megabytes — and since orchestrators call this
    # script on every update, that is the normal path rather than an edge case:
    # the choice would stick only until something else ran the installer.
    #
    # With no file there is no answer to keep, so a fresh unattended box still
    # gets the complete editor, the same as this script always gave it. Nothing
    # is removed either way here beyond what purge_orphans() reconciles, since
    # nobody is present to have asked for it.
    if [[ "$LANG_UNREADABLE" == true ]]; then
        # PREVIOUS is already all four here (see above). Said separately from the
        # branch below because "keeping the languages already chosen" would be a
        # claim about a choice this run could not read — and that message printing
        # over a list that had silently become empty is how the deletion below
        # used to go unnoticed.
        for l in $PREVIOUS; do add_lang "$l"; done
        step "Nothing to prompt on (no terminal) — the language list is unreadable, so every language is kept."
    elif [[ -f "$LANG_FILE" ]]; then
        for l in $PREVIOUS; do add_lang "$l"; done
        step "Nothing to prompt on (no terminal) — keeping the languages already chosen."
    else
        for l in $ALL_LANGS; do add_lang "$l"; done
        step "Nothing to prompt on (no terminal) — no previous answer, installing every language."
    fi
else
    printf '  %sPick the languages you want support for.%s\n' "$C_BOLD" "$C_OFF"
    printf '  Everything else — file search, git, spell-check, the keymaps — is\n'
    printf '  installed either way, and you can re-run this any time to change\n'
    printf '  your mind. Enter keeps things as they are.\n\n'
    for l in $ALL_LANGS; do
        reply=""
        if was_lang "$l"; then
            # Default yes, so Enter keeps what you have: dropping a language
            # deletes plugins and a language server, and that should take an
            # explicit "n" rather than a tired Enter.
            read -r -p "  $(lang_label "$l") [Y/n] " reply || reply=""
            case "$reply" in
                [nN]|[nN][oO]) printf '    %s-%s %s%s%s\n' \
                    "$C_YELLOW" "$C_OFF" "$C_DIM" "will be removed" "$C_OFF" ;;
                *) add_lang "$l" ;;
            esac
        else
            read -r -p "  $(lang_label "$l") [y/N] " reply || reply=""
            case "$reply" in
                [yY]|[yY][eE][sS])
                    add_lang "$l"
                    printf '    %s+%s %s%s%s\n' \
                        "$C_GREEN" "$C_OFF" "$C_DIM" "$(lang_brings "$l")" "$C_OFF" ;;
            esac
        fi
    done
    printf '\n'
fi

# What changed, in both directions — a re-run should say plainly what it is
# about to do, especially when it is about to delete something.
ADDED=""
REMOVED=""
for l in $ALL_LANGS; do
    if has_lang "$l" && ! was_lang "$l"; then ADDED="${ADDED:+$ADDED }$l"; fi
    if was_lang "$l" && ! has_lang "$l"; then REMOVED="${REMOVED:+$REMOVED }$l"; fi
done
if [[ -z "$SELECTED" ]]; then
    warn "No languages selected — the core plugins only."
else
    summary="$(sorted_langs | tr '\n' ' ')"
    ok "Languages: ${summary% }"
fi
[[ -n "$ADDED"   ]] && ok "Adding: $ADDED"
[[ -n "$REMOVED" ]] && warn "Dropping: $REMOVED — anything already installed for them is deleted below."

# The answer goes to disk here, before anything is installed. Deliberately
# before: it is what the user just said, it is what vimrc reads on the next
# launch, and a package install that dies half way should not be able to lose
# it. The all-four snapshot that drives the cleanup needs vim on PATH, so it
# waits until after the install below.
write_langs "$SELECTED"

# ── Install ──────────────────────────────────────────────────────────────────
title "Vim (${OS_LABEL})"
# That this checkout is reachable as ~/.vim was settled before the language
# questions — see the block under the platform check above.

# clangd is the C/C++ language server, and the one language here that needs a
# system package at all — the servers for PHP, JavaScript and Python are coc
# extensions, which coc fetches itself on first launch. coc-clangd is only a
# thin client: without this binary on PATH, completion, diagnostics and
# <leader>h (switch source/header) in config_files/c.vim all silently do
# nothing. So it is installed only when C was chosen above.
#
# These two lists are the source of truth. README.md section 1 repeats them for
# anyone installing by hand — update it alongside any change here.
if [[ "$PLATFORM" == ubuntu ]]; then
    apt_ensure vim git nodejs npm ripgrep silversearcher-ag
    if has_lang c; then
        apt_ensure clangd
    else
        skip "clangd not needed (C support not installed)."
    fi

    # yarn (global) — a few plugins build with it.
    #
    # --ignore-scripts, because this is an `npm install` running as root: without
    # it npm executes the package's own preinstall/postinstall hooks with those
    # privileges, which is third-party code deciding what to do on your machine
    # as root. yarn's is `node ./preinstall.js` and is advisory — it warns about
    # unrecommended install methods and is already wrapped in `|| true` upstream
    # — so skipping it changes nothing about the install, and the flag holds if
    # a future version adds a hook that is not advisory.
    if has_cmd yarn; then
        skip "yarn already installed."
    elif can_sudo; then
        step "Installing yarn (global, via npm)"
        # $SUDO unquoted, for the reason given in apt_ensure(): empty as root,
        # where it has to disappear rather than become an argument to run().
        run $SUDO npm install -g --ignore-scripts yarn
        # Gated, like the backup message in ensure_line() above: run() prints
        # "would run" under --dry-run, so an unconditional line here reported an
        # install that never happened — the one claim a dry run must not get
        # wrong.
        [[ "$DRY_RUN" == true ]] || ok "yarn installed."
    else
        # Only reachable as a non-root user — can_sudo() is true outright for
        # root — so `sudo` is the right thing to suggest either way here.
        warn "Cannot elevate (no sudo, or no terminal to prompt on) — install yarn later:"
        warn "    sudo npm install -g --ignore-scripts yarn"
    fi
else
    if ! has_cmd brew; then
        warn "Homebrew not found. Install it from https://brew.sh, then re-run this script."
        exit 1
    fi
    # yarn is a formula here, so no 'sudo npm -g'. llvm carries clangd, so it
    # goes the way clangd does on Ubuntu — only when C was chosen. It is a large
    # formula, and nothing else in this config touches it.
    brew_ensure vim git node yarn ripgrep the_silver_searcher

    if ! has_lang c; then
        skip "llvm/clangd not needed (C support not installed)."
    else
        brew_ensure llvm

        # llvm is keg-only: brew deliberately leaves it out of PATH because macOS
        # ships its own clang. Without this export, clangd is installed but
        # unfindable.
        #
        # Appended rather than prepended, on purpose. The formula also carries
        # clang, clang++ and ld, so putting its bin/ first would quietly replace
        # Xcode's toolchain as the default compiler in every shell — which is the
        # very thing keg-only is meant to prevent. macOS ships no clangd of its own
        # on PATH, so the tail is enough to find it, with nothing shadowed.
        if llvm_bin="$(brew --prefix llvm 2>/dev/null)/bin"; then
            llvm_export="export PATH=\"\$PATH:$llvm_bin\""
            profile="$(shell_profile)"
            if [[ -n "$profile" ]]; then
                ensure_line "$llvm_export" "$profile" append
            else
                warn "Unrecognised login shell (${SHELL:-unset}) — add this to your shell profile by hand:"
                warn "    $llvm_export"
            fi
            # Also for the rest of this script, so the clangd check below sees it.
            export PATH="$PATH:$llvm_bin"
        else
            warn "Could not resolve 'brew --prefix llvm' — put its bin/ on PATH by hand for clangd."
        fi
    fi
fi

# Everything this config could ever declare, read by pointing it at all four for
# the length of one vim startup. Diffed later against what it declares for the
# actual selection, that is exactly the set of plugins and language servers the
# four languages own — and nothing else, so whatever you installed by hand is
# outside it and safe.
#
# Here rather than up with the questions, which is where it used to sit: this
# shells out to vim, and vim is installed a few lines above. On a box that did
# not have it yet the snapshot came back empty, purge_orphans() correctly refused
# to delete anything from a list it could not read, and the whole cleanup was
# therefore inert on exactly the run that sets the machine up. Nothing is lost
# by waiting — the answer itself is already on disk, written before the install.
#
# Three writes rather than one: the list has to be on disk for vim to read it,
# the mapping from language to plugins lives in plug.vim and coc.vim where it
# should, and the real selection has to go back afterwards. LANG_FILE_DIRTY
# covers the gap — see cleanup() above for what dying in it would otherwise cost.
CFG_ALL=""
if [[ "$DRY_RUN" != true ]]; then
    CFG_ALL="$(tmpfile cfg-all)"
    LANG_FILE_DIRTY=true
    write_langs "$ALL_LANGS" quiet
    snapshot_config "$CFG_ALL"
    write_langs "$SELECTED" quiet
    LANG_FILE_DIRTY=false
fi

# Point ~/.vimrc at this repo (vim-plug is bundled in autoload/plug.vim).
ensure_line "runtime vimrc" "$HOME/.vimrc" replace

# Install plugins headlessly (vim -es needs no TTY).
if [[ "$DRY_RUN" == true ]]; then
    printf '%s  would run:%s vim +PlugInstall +qall (headless)\n' "$C_DIM" "$C_OFF"
    if [[ -n "$REMOVED" ]]; then
        printf '%s  would remove:%s the plugins and language servers for %s\n' \
            "$C_DIM" "$C_OFF" "$REMOVED"
    fi
    # purge_orphans() below runs unconditionally and compares against what is on
    # disk, so a real run also clears what an earlier or half-finished one left
    # behind — including when this run drops no language at all and the line
    # above therefore says nothing. Naming what would go needs the two vim
    # snapshots a dry run deliberately skips, so this says that it happens rather
    # than what it removes: the alternative is silence, which reads as "nothing
    # to delete". Same rule as the backup message in ensure_line(), the yarn line
    # and the clangd check — a dry run must not under-describe what it would do.
    printf '%s  would also:%s remove any plugin or language server left behind by\n' \
        "$C_DIM" "$C_OFF"
    printf '              an earlier run for a language that is not selected now\n'
else
    step "Installing vim plugins (headless — first run takes a minute)"
    # Logged rather than sent to /dev/null: a failure here is usually a network
    # error or a git clone refusing, and the message saying which is the whole
    # point. Without it the warning below is the only trace and says nothing.
    PLUG_LOG="$REPO/.plug-install.log"
    PLUG_MISSING="$(tmpfile plug-missing)"

    # `vim -es` exits 0 whether or not the clones worked, and in silent Ex mode
    # vim-plug's own "x plugin" / "Finished. N error(s)." lines are never
    # rendered, so neither the exit status nor the log can be trusted to say.
    # Ask vim-plug directly instead: g:plugs maps every declared plugin to the
    # directory it should live in, so anything without one did not install.
    vim -es -u "$HOME/.vimrc" +'PlugInstall --sync' +qall >"$PLUG_LOG" 2>&1 || true

    # A second vim rather than one more '+cmd' on the line above: PlugInstall
    # swallows everything queued after it, so the check never ran and every
    # install looked like a failure. A fresh vim has g:plugs populated by
    # plug#end() at startup, which is all this needs.
    #
    # The leading 'checked' line is a sentinel. Without it an empty file is
    # ambiguous — it means both "every plugin is present" and "vim died before
    # it got this far", and the second must not be reported as success.
    #
    # The path goes through the environment, for the reason spelled out above
    # snapshot_config().
    VIMSNAP_OUT="$PLUG_MISSING" vim -es -u "$HOME/.vimrc" \
        +"call writefile(['checked'] + sort(keys(filter(copy(g:plugs), '!isdirectory(v:val.dir)'))), \$VIMSNAP_OUT)" \
        +qall >>"$PLUG_LOG" 2>&1 || true

    if [[ "$(head -n 1 "$PLUG_MISSING")" != checked ]]; then
        warn "Could not verify the plugin install — vim exited early."
        warn "See $PLUG_LOG, then open vim and run :PlugInstall."
    elif [[ "$(wc -l < "$PLUG_MISSING")" -gt 1 ]]; then
        warn "These plugins did not install:$(tail -n +2 "$PLUG_MISSING" | tr '\n' ' ')"
        warn "See $PLUG_LOG, then open vim and run :PlugInstall."
    else
        ok "vim plugins installed."
        rm -f "$PLUG_LOG"
    fi

    # Then take away anything installed for a language that is no longer
    # selected. Unconditional, not gated on this run having dropped one: it is a
    # comparison against what is on disk, so it also clears what an earlier run
    # left behind, and costs one vim start when there is nothing to do.
    CFG_WANTED="$(tmpfile cfg-wanted)"
    snapshot_config "$CFG_WANTED"
    purge_orphans "$CFG_ALL" "$CFG_WANTED"

    # The system packages stay. clangd is a general C toolchain component —
    # other editors and build tooling use it, apt may have pulled it in as a
    # dependency of something else, and removing it needs sudo. Saying so is
    # better than either deleting it or leaving it unmentioned.
    #
    # Said only on the run that actually removes coc-clangd, not every time C is
    # off: a line repeating itself on every re-run is one you stop reading.
    if [[ " ${PURGED_EXT:-} " == *" coc-clangd "* ]] && has_cmd clangd; then
        if [[ "$PLATFORM" == macos ]]; then
            skip "llvm left installed — 'brew uninstall llvm' if nothing else needs it."
        else
            skip "clangd left installed — 'sudo apt remove clangd' if nothing else needs it."
        fi
    fi
fi

# Reload: nothing to live-reload — vim reads the config on next launch.
# Inside a running vim: ':source $MYVIMRC'.
skip "Vim loads the config on next launch."
# Not under --dry-run. Nothing was installed, so has_cmd here reports the state
# of a machine the script deliberately left alone — and on a box without clangd
# that printed "would install: clangd" and "clangd not on PATH … will be inert"
# in the same run, which is the flag contradicting itself. Same rule as the
# backup message in ensure_line() and the yarn line above: a dry run must not
# claim an outcome it never produced.
if [[ "$DRY_RUN" != true ]] && has_lang c && ! has_cmd clangd; then
    if [[ "$PLATFORM" == macos ]]; then
        warn "clangd not on PATH — open a new terminal (${profile:-your shell profile} needs a fresh shell)."
    else
        warn "clangd not on PATH — C/C++ completion and diagnostics will be inert."
    fi
fi
if [[ -n "$SELECTED" ]]; then
    # Trailing space from tr, so this reads "…for c php on first launch".
    ok "Vim ready. coc installs the servers for $(sorted_langs | tr '\n' ' ')on first launch (:CocList extensions)."
else
    ok "Vim ready — core plugins only, no language support installed."
fi
skip "Changed languages? Re-run ./install.sh — it adds and removes to match your answers."

# Last, so a degraded run still does everything it can before saying so. The
# status is what an orchestrator reads, and "some packages are missing" must not
# reach it as success — see INSTALL_DEGRADED at the top of this script.
if [[ "$INSTALL_DEGRADED" == true ]]; then
    warn "Finished, but some system packages could not be installed (see above)."
    exit 1
fi
