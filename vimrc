" ~/.vim/vimrc — entry point, loaded by `runtime vimrc` from ~/.vimrc.
" See README.md for install instructions.

set nocompatible
syntax on
filetype plugin indent on

" Where this repo lives; everything resolves against it, so the config also runs
" from a worktree. Global because coc.vim needs it for the cSpell dictionary.
let g:vim_root = expand('<sfile>:p:h')

" ── Files & buffers ─────────────────────────────────────────────────────────
set hidden
set nobackup nowritebackup noswapfile

" Undo survives closing the file — the only fallback, given noswapfile. It writes
" every buffer's text to disk, hence 0700 and the opt-outs in autocmds.vim.
set undofile
let &undodir = g:vim_root . '/undo//'
" silent!, because a read-only checkout throws E739 and stops every launch at a
" "Press ENTER"; the isdirectory() below then turns 'undofile' off instead.
if !isdirectory(g:vim_root . '/undo')
  silent! call mkdir(g:vim_root . '/undo', 'p', 0700)
endif
" Re-asserted on every start: mkdir's mode only applies at creation, so an undo/
" that already existed kept looser permissions for ever.
if isdirectory(g:vim_root . '/undo')
  call setfperm(g:vim_root . '/undo', 'rwx------')
else
  set noundofile
endif

" Registers and the ':'/'/' histories are dropped: vim's defaults wrote yanked
" and searched-for secrets into ~/.viminfo, which outlives the file. Marks stay.
set viminfo='100,<0,s0,:0,/0,h

" Re-read files changed outside vim. FocusGained stats every buffer (vim has been
" away); BufEnter only <abuf>, since a bare checktime there is per-switch waste.
set autoread
augroup AutoReload
  autocmd!
  autocmd FocusGained * silent! checktime
  autocmd BufEnter    * silent! checktime <abuf>
augroup END

" Off: otherwise any repo you clone runs its own .vimrc. 'secure' is no fix — it
" blocks the ex commands, not system()/writefile(), and vim has no trust prompt.
set noexrc

" Same reason: a modeline lets a cloned file reconfigure your editor, and
" modeline parsing has produced that class of bug before (CVE-2019-12735).
set nomodeline

" ── Search ──────────────────────────────────────────────────────────────────
set incsearch hlsearch
set ignorecase smartcase

" ── Indentation ─────────────────────────────────────────────────────────────
" Per-language overrides live in indent.vim and c.vim.
set smartindent
set expandtab
set tabstop=4 softtabstop=4 shiftwidth=4

" ── Display ─────────────────────────────────────────────────────────────────
set number numberwidth=1
set nowrap
set cursorline
set colorcolumn=100
set signcolumn=yes
set laststatus=2
set cmdheight=1
set noerrorbells
set guicursor=
set encoding=UTF-8

" Low enough that j/k move the cursor instead of scrolling and redrawing.
set scrolloff=8

" Don't syntax-highlight past this column: minified JS/CSS and bundled JSON are
" single enormous lines, and opening one locks vim up without this.
set synmaxcol=300

" Don't redraw mid-macro — only once it finishes.
set lazyredraw

" Let vim pick the faster regex engine per pattern. Forcing the NFA engine
" (re=2) is the slow path for the JS/JSX/PHP/Blade syntax files.
set re=0

" ── Cursor ──────────────────────────────────────────────────────────────────
" alacritty's cnorm (t_ve) stops the blink before showing the cursor, so the
" blink died on vim's first redraw. Drop that half, keep the show-cursor half.
let &t_ve = substitute(&t_ve, "\<Esc>\\[?12l", '', 'g')

" ── Timeouts ────────────────────────────────────────────────────────────────
" Mapping timeout stays generous, but key *codes* must resolve fast: without
" ttimeoutlen, <Esc> inherits timeoutlen and takes a full second to register.
set timeout timeoutlen=500
set ttimeout ttimeoutlen=10

" Drives CursorHold, and so how quickly gitgutter and coc react.
set updatetime=300

" ── Language support ────────────────────────────────────────────────────────
" Which languages this install carries plugins and servers for. install.sh asks
" and writes the answer here; a missing file means nobody chose, so all are on.
let s:cfg = g:vim_root . '/config_files/'
if filereadable(s:cfg . 'languages.vim')
  execute 'source' fnameescape(s:cfg . 'languages.vim')
endif
" That file is hand-editable, and a string there would fail further down in
" index() — naming plug.vim rather than the file actually broken.
if exists('g:vim_languages') && type(g:vim_languages) != v:t_list
  echohl WarningMsg
  echomsg 'languages.vim: g:vim_languages must be a list, e.g. [''php'']'
        \ . ' — ignoring it, all languages enabled.'
  echohl NONE
  unlet g:vim_languages
endif
" Same set as ALL_LANGS in install.sh, spelled twice because bash and Vimscript
" cannot share one — a language added there has to be added here too.
let g:vim_languages = get(g:, 'vim_languages', ['php', 'javascript', 'python', 'c'])

" Global: plug.vim and coc.vim are separate scripts, and both have to ask.
function! VimLangEnabled(lang) abort
  return index(g:vim_languages, a:lang) >= 0
endfunction

" ── Modules ─────────────────────────────────────────────────────────────────
" Order matters: keymap sets <leader> before any plugin reads it, then plug
" defines what the rest configures. Unguarded — a missing one is a broken clone.
for s:mod in ['keymap', 'plug', 'coc', 'indent', 'c', 'colorscheme',
      \        'functions', 'autocmds', 'airline']
  execute 'source' fnameescape(s:cfg . s:mod . '.vim')
endfor
" 'secrets' is the one genuinely optional module: untracked, holds licence keys.
if filereadable(s:cfg . 'secrets.vim')
  execute 'source' fnameescape(s:cfg . 'secrets.vim')
endif

" The cSpell dictionary is gitignored, so create an empty one on a fresh clone.
" silent! because an unwritable checkout is not worth stopping a launch over.
if !filereadable(g:vim_root . '/cspell-words.txt')
  silent! call writefile([], g:vim_root . '/cspell-words.txt')
endif
" Locked down and re-asserted every start: writefile() honours the umask, and
" cSpell appends private project and client names here (README section 4).
if filereadable(g:vim_root . '/cspell-words.txt')
  call setfperm(g:vim_root . '/cspell-words.txt', 'rw-------')
endif
