" Mappings. <leader> is Space, and must be set before any plugin loads — which
" is why this file is sourced first from vimrc.
let mapleader = " "

" ── Buffers ─────────────────────────────────────────────────────────────────
" Not on <C-v>/<C-m>/<C-g>: blockwise visual, Enter, and file-info — all things
" vim needs and none of which have a substitute.
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> <leader>D :bd<CR>

" ── Windows ─────────────────────────────────────────────────────────────────
nnoremap <leader>vp :vsplit<CR>
nnoremap <leader>vo :split<CR>

" ── Editing ─────────────────────────────────────────────────────────────────
" Makes `j` a prefix in insert mode, so a `j` you stop typing after waits a
" 'timeoutlen'. Kept: mid-word the next keystroke resolves it instantly.
inoremap jj <ESC>

" Insert an empty checkbox, for notes.
nnoremap <leader>K i- [ ] <Esc>F]la

nnoremap <leader>w :noh<CR>

nnoremap <silent> <leader>tn :call VimToggleNumbers()<CR>

" Auto-close pairs, <expr> so they can read the character under the cursor. The
" two below read whole *characters* — a byte index breaks on `perché`.
function! s:CharAfter() abort
  return matchstr(getline('.'), '\%' . col('.') . 'c.')
endfunction

function! s:CharBefore() abort
  return matchstr(getline('.'), '.\%' . col('.') . 'c')
endfunction

" <C-g>U keeps the insert unbroken across the cursor move (:h i_CTRL-G_U).
" Without it `.` replays only what came after the bracket: `x(y` → `x(yy)`.
function! s:Pair(open, close) abort
  return a:open . a:close . "\<C-g>U\<Left>"
endfunction

" Typing a closing bracket steps over the one already there.
function! s:Close(char) abort
  return s:CharAfter() ==# a:char ? "\<C-g>U\<Right>" : a:char
endfunction

" A quote pairs only in open space — '\k', not '\w', since Vim's '\w' is
" ASCII-only. Vimscript `"` is exempt: a comment is opened and never closed.
function! s:Quote(char) abort
  if a:char ==# '"' && &filetype ==# 'vim'
    return a:char
  endif
  if s:CharAfter() ==# a:char
    return "\<C-g>U\<Right>"
  endif
  if s:CharBefore() =~# '\k' || s:CharAfter() =~# '\k'
    return a:char
  endif
  return a:char . a:char . "\<C-g>U\<Left>"
endfunction

inoremap <expr> ( <SID>Pair('(', ')')
inoremap <expr> [ <SID>Pair('[', ']')
inoremap <expr> { <SID>Pair('{', '}')
inoremap <expr> ) <SID>Close(')')
inoremap <expr> ] <SID>Close(']')
inoremap <expr> } <SID>Close('}')
inoremap <expr> " <SID>Quote('"')
inoremap <expr> ' <SID>Quote("'")

" ── Clipboard ───────────────────────────────────────────────────────────────
" This vim is built without +clipboard, so "+ does not exist. OSC 52 asks the
" terminal instead, which also works over SSH and inside tmux.
nmap <leader>y  <Plug>OSCYankOperator
nmap <leader>yy <leader>y_
xmap <leader>y  <Plug>OSCYankVisual

" ── Search: fzf ─────────────────────────────────────────────────────────────
nnoremap <leader>fi :Files<CR>
nnoremap <leader>fo :Ag<CR>
nnoremap <leader>fp :AgAll<CR>

" The same two searches over the highlighted text, no prompt. <C-u> drops the
" '<,'> range vim inserts; s:AgVisual re-selects with gv instead.
xnoremap <leader>fo :<C-u>call <SID>AgVisual('')<CR>
xnoremap <leader>fp :<C-u>call <SID>AgVisual(' -U')<CR>

" Declared once, since rg and ag spell their ignore flags differently. Only what
" is junk in *every* project — both match files too, not just directories.
let s:ignore_dirs = ['.git', 'node_modules']

" '--glob "!node_modules"', not '!node_modules/*': a ripgrep glob containing '/'
" is anchored to the root, so that form walked into packages/*/node_modules.
let s:file_source = 'rg --files --hidden --follow '
      \ . join(map(copy(s:ignore_dirs), '''--glob "!'' . v:val . ''"'''), ' ')

" '--column' is not optional: fzf.vim takes a numeric third field as the column,
" so `docker-compose.yml:12:  8080:8080` parsed as column 8080.
let s:grep_source = 'ag --nocolor --column --hidden '
      \ . join(map(copy(s:ignore_dirs), '''--ignore '' . v:val'), ' ')

" '--nth 4..' filters on the matched text, not the file:line:col prefix.
" '--exact' because fuzzy match scatters the query as loose letters.
function! s:GrepOptions() abort
  return fzf#vim#with_preview({'options': '--delimiter : --nth 4.. --exact'})
endfunction

" Files by name, via ripgrep. Delegates to fzf#vim#files so `:Files src/`,
" multi-select and the ctrl-t/x/v actions keep working.
command! -bang -nargs=? -complete=dir Files
    \ call fzf#vim#files(<q-args>, fzf#vim#with_preview({
    \   'source': s:file_source,
    \   'options': '--exact'
    \ }), <bang>0)

" Regex project search, prompting when bare so ag matches and only hits reach
" fzf. '--' and shellescape() because the term reaches a shell.
function! s:Ag(term, bang, flags) abort
  let l:prompt = empty(a:flags) ? 'Search: ' : 'Search (with ignored): '
  let l:term = empty(a:term) ? input(l:prompt) : a:term
  redraw
  if empty(l:term)
    return
  endif
  call fzf#vim#grep(s:grep_source . a:flags . ' -- ' . shellescape(l:term),
        \ s:GrepOptions(), a:bang)
endfunction
command! -bang -nargs=* Ag    call s:Ag(<q-args>, <bang>0, '')

" The same search reaching into gitignored files. '-U', not '-u': -u also drops
" the binary and --ignore skipping, flooding results with .git objects.
command! -bang -nargs=* AgAll call s:Ag(<q-args>, <bang>0, ' -U')

" Search whatever is highlighted. First line only, since ag matches one line at
" a time; escape() because ag reads the term as a regex, and `$foo` is literal.
function! s:AgVisual(flags) abort
  " Unnamed restored last: "xy repoints @" at x, so putting back only x eats it.
  let l:save_x = getreginfo('x')
  let l:save_unnamed = getreginfo('"')
  normal! gv"xy
  let l:lines = split(getreg('x'), "\n")
  call setreg('x', l:save_x)
  call setreg('"', l:save_unnamed)
  if empty(l:lines) || empty(trim(l:lines[0]))
    return
  endif
  call s:Ag(escape(l:lines[0], '\.*+?()[]{}^$|'), 0, a:flags)
endfunction

" ── File tree: NERDTree ─────────────────────────────────────────────────────
let g:NERDTreeShowHidden = 1
let g:NERDTreeQuitOnOpen = 1

" NERDTree renders lazily, so `r` (refresh) is fed in after the toggle — but
" only in the tree, or the queued `r` is eaten by the file buffer's next key.
function! s:NERDTreeRefreshed(cmd) abort
  execute a:cmd
  if &filetype ==# 'nerdtree'
    call feedkeys('r')
  endif
endfunction

" The muscle-memory keys. They cost the tag-stack pop and a one-line scroll,
" neither much of a loss: go-to-definition is coc's `gd`, and <C-o> goes back.
nnoremap <silent> <C-t> :call <SID>NERDTreeRefreshed('NERDTreeToggle')<CR>
nnoremap <silent> <C-y> :call <SID>NERDTreeRefreshed('NERDTreeFind')<CR>

" Same two on <leader>, for when <C-t>/<C-y> are swallowed by a multiplexer.
nnoremap <silent> <leader>n :call <SID>NERDTreeRefreshed('NERDTreeToggle')<CR>
nnoremap <silent> <leader>N :call <SID>NERDTreeRefreshed('NERDTreeFind')<CR>

" ── Formatting ──────────────────────────────────────────────────────────────
" :Format is coc's formatter (see coc.vim), which routes through prettier for
" the filetypes coc-prettier claims.
nnoremap <Leader>tu :Format<CR>
