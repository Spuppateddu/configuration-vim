" Per-language indentation. The global default (4 spaces) is set in vimrc.
" Wrapped in an augroup so re-sourcing the config doesn't stack duplicates.
augroup IndentByFiletype
  autocmd!
  " Web front-end conventions are 2 spaces. One autocmd rather than two with
  " identical bodies, so the two filetype groups can't drift apart.
  autocmd FileType javascript,javascriptreact,typescript,typescriptreact,
        \css,scss,html,json,jsonc,yaml
        \ setlocal shiftwidth=2 softtabstop=2 tabstop=2 expandtab

  " PHP (PSR-12) and Python (PEP 8) are both 4 — vimrc's default already, but
  " $VIMRUNTIME/ftplugin/python.vim sets these itself and runs first.
  autocmd FileType php,blade,python
        \ setlocal shiftwidth=4 softtabstop=4 tabstop=4 expandtab
augroup END
