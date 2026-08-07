" Autocommands that apply everywhere. Functions they call live in functions.vim.
" Every group is wrapped in augroup + `autocmd!`, so re-sourcing doesn't stack.

" Strip trailing whitespace on save.
augroup TrimOnWrite
  autocmd!
  autocmd BufWritePre * call VimTrimWhitespace()
augroup END

" Cursor line only in the focused window, and only in real file ones — NERDTree
" and quickfix draw their own. BufWinEnter: at WinEnter 'buftype' is still stale.
augroup ActiveWindowCursorline
  autocmd!
  autocmd WinEnter,BufWinEnter * call VimSyncCursorline()
  autocmd WinLeave * setlocal nocursorline
augroup END

" No undo history for files holding secrets: 'undofile' (see vimrc) leaves the
" old value of a rotated key on disk long after the file itself loses it.
augroup NoUndoForSecrets
  autocmd!
  autocmd BufReadPre,BufNewFile,BufFilePost
        \ *.env,*.env.*,.env,.env.*,.envrc,secrets.vim,
        \.npmrc,.pypirc,.netrc,.pgpass,credentials,.git-credentials,.htpasswd,
        \*.pem,*.key,*.p8,*.p12,*.pfx,*.jks,*.kdbx,*.ovpn,*.asc,*.gpg,
        \*id_rsa*,*id_ed25519*,*id_ecdsa*,*id_dsa*,
        \*.tfvars,terraform.tfstate*
        \ setlocal noundofile
augroup END
