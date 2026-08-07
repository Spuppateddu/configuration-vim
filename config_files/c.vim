" C / C++ settings.
" The autocmds live in one augroup at the bottom, so re-sourcing replaces them.

" `K` falls back to the man page when clangd has no hover. ftplugin/man.vim also
" installs a global <Leader>K, eating keymap.vim's — hence the save/restore.
let s:leader_k = maparg('<leader>K', 'n', 0, 1)
runtime! ftplugin/man.vim
if !empty(s:leader_k)
  call mapset('n', 0, s:leader_k)
endif
unlet s:leader_k

" Syntax tweaks for the bundled c.vim highlighter:
" recognise GNU extensions, and don't flag C99 compound literals as errors.
let g:c_gnu = 1
let g:c_no_curly_error = 1

" ── Building ────────────────────────────────────────────────────────────────
" Compiler output goes into the quickfix list, so ]q jumps straight to the bad
" line. Vim's default 'errorformat' already understands gcc output.

" Quote a path for 'makeprg'. Two layers: shellescape() stops `a;id.c` running
" `id`, and escape() stops Vim splicing a `%` in the name (:h cmdline-special).
function! s:Shellarg(path) abort
  return escape(shellescape(a:path), '%#')
endfunction

" Prefer the project's Makefile, searching upward from the file itself. Absolute
" names are baked in quoted: with `%` left for Vim, `a;touch pwned.c` ran `touch`.
function! s:SetMakeprg() abort
  let l:here = expand('%:p:h')
  let l:mk = findfile('Makefile', l:here . ';')
  if empty(l:mk)
    let l:mk = findfile('makefile', l:here . ';')
  endif
  if !empty(l:mk)
    let &l:makeprg = 'make -C ' . s:Shellarg(fnamemodify(l:mk, ':p:h'))
  else
    let l:cc = &filetype ==# 'cpp' ? 'g++' : 'gcc'
    let &l:makeprg = l:cc . ' -Wall -Wextra -g -o '
          \ . s:Shellarg(expand('%:p:r')) . ' ' . s:Shellarg(expand('%:p'))
  endif
endfunction

" 'makeprg' ready for system(): minus the `\%` escaping, which only exists to
" survive Vim's own expansion pass and would reach the shell as backslashes.
function! s:BuildCommand() abort
  return substitute(&l:makeprg, '\\\([%#]\)', '\1', 'g')
endfunction

" Compile, opening quickfix only if the build failed. system(), not `:make`:
" that pipes through 'shellpipe', so v:shell_error is tee's and always 0.
function! s:Build() abort
  update
  let l:output = system(s:BuildCommand())
  let l:failed = v:shell_error
  cgetexpr l:output
  let l:notes = len(filter(getqflist(), 'v:val.valid'))
  if l:failed
    copen
    echohl ErrorMsg | echo 'Build failed — ' . l:notes . ' message(s)' | echohl NONE
  else
    cclose
    echo l:notes ? 'Build OK — ' . l:notes . ' warning(s), :copen to see them' : 'Build OK'
  endif
  return !l:failed
endfunction

" Compile and, if that worked, run the binary in a terminal split so you can see
" its output and still type into scanf() and friends.
function! s:BuildAndRun() abort
  if !s:Build()
    return
  endif
  let l:bin = expand('%:p:r')
  if !executable(l:bin)
    echohl ErrorMsg
    echo 'Nothing to run at ' . fnamemodify(l:bin, ':t') . ' — check the Makefile target name'
    echohl NONE
    return
  endif
  execute 'botright terminal ++rows=15 ' . fnameescape(l:bin)
endfunction

" Everything a C/C++ buffer gets, in one function behind one autocmd so the
" settings can't drift apart — same reasoning as the grouped indent.vim autocmd.
function! s:CBufferSetup() abort
  " No indent settings here: vim ships no ftplugin/c.vim to override, so vimrc's
  " global 4-space expandtab already applies (unlike php and python).

  " Let `gf` and `[i` follow #include paths into the system headers.
  setlocal path+=/usr/include,/usr/local/include,include,src

  setlocal keywordprg=:Man

  call s:SetMakeprg()

  " Jump between foo.c and foo.h. Guarded because the <nowait> it needs against
  " gitgutter's <leader>h would otherwise swallow three working keys.
  if VimLangEnabled('c')
    nnoremap <buffer> <silent><nowait> <leader>h
          \ :CocCommand clangd.switchSourceHeader<CR>
  endif

  " Not <leader>r: coc takes <leader>re, so a build there would be a leaf
  " sharing its prefix and stall for 'timeoutlen' on every press.
  nnoremap <buffer> <silent> <leader>b :call <SID>Build()<CR>
  nnoremap <buffer> <silent> <leader>x :call <SID>BuildAndRun()<CR>
endfunction

augroup CFiletype
  autocmd!
  " No 'h'/'hpp' needed — vim gives .h the filetype 'c' and .hpp 'cpp'.
  autocmd FileType c,cpp call s:CBufferSetup()

  " The filename is baked into 'makeprg', so `:saveas other.c` has to rebuild it
  " or you keep compiling the old name. BufFilePost is the hook for a rename.
  autocmd BufFilePost *.c,*.cc,*.cpp,*.cxx,*.h,*.hpp call s:SetMakeprg()
augroup END

" Quickfix navigation. Global, since the list is — handy for any compiler.
" <leader>qc rather than a bare <leader>q, which prefixes coc's <leader>qf.
nnoremap <silent> ]q :cnext<CR>
nnoremap <silent> [q :cprevious<CR>
nnoremap <silent> <leader>qc :cclose<CR>
