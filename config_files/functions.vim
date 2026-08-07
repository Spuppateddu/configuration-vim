" Helper functions, called from the autocmds and mappings elsewhere.

" Filetypes where trailing whitespace carries meaning: two spaces are a hard
" break in markdown, and stripping it in a .patch can stop the patch applying.
let s:keep_trailing_ws = ['markdown', 'diff', 'patch', 'mail', 'gitsendemail']

" 'binary' is the guard that costs data if missed: a `vim -b` buffer looks
" ordinary, so a plain `:w` silently deleted every 0x20 before a newline.
function! VimTrimWhitespace() abort
  if !&modifiable || &buftype !=# '' || &binary
    return
  endif
  if index(s:keep_trailing_ws, &filetype) < 0
    let l:save = winsaveview()
    keeppatterns %s/\s\+$//e
    call winrestview(l:save)
  endif
endfunction

" Cursorline belongs in the window you're in, and only if it holds a real file.
" See the ActiveWindowCursorline augroup for why both branches are needed.
function! VimSyncCursorline() abort
  if &buftype ==# ''
    setlocal cursorline
  else
    setlocal nocursorline
  endif
endfunction

" Toggle line numbers — mapped to <leader>tn in keymap.vim. setlocal, not set:
" a global `set` also changed what every window opened afterwards inherited.
function! VimToggleNumbers() abort
  if &number || &relativenumber
    setlocal nonumber norelativenumber
  else
    setlocal number
  endif
endfunction
