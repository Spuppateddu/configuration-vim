" coc.nvim — completion, diagnostics and LSP.
" 'updatetime' and 'signcolumn', which coc's README asks for, are set in vimrc.

" Point the cSpell dictionary at *this* checkout. coc-settings.json can only
" spell an absolute ~/.vim, so from a worktree vim and cSpell used two paths.
augroup CocDictionary
  autocmd!
  autocmd User CocNvimInit call coc#config('cSpell.dictionaryDefinitions',
        \ [{'name': 'project-words',
        \   'path': g:vim_root . '/cspell-words.txt',
        \   'addWords': v:true}])
augroup END

" Is coc on disk? On a fresh clone it is not, and what calls into it unasked
" (<expr> maps, K, CursorHold) threw E117 on every keystroke.
let s:coc_ready = has_key(g:plugs, 'coc.nvim')
      \ && isdirectory(g:plugs['coc.nvim'].dir)

" Script-local because both are coc's README boilerplate verbatim: a global
" CheckBackspace() is what every other config that copied that page also defines.
function! s:CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

function! s:ShowDocumentation() abort
  if CocAction('hasProvider', 'hover')
    call CocActionAsync('doHover')
  else
    call feedkeys('K', 'in')
  endif
endfunction

if s:coc_ready
  inoremap <silent><expr> <TAB>
        \ coc#pum#visible() ? coc#pum#next(1) :
        \ <SID>CheckBackspace() ? "\<Tab>" :
        \ coc#refresh()
  inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

  " <C-g>u starts a new undo block before the newline, so `u` takes back the
  " line rather than the whole insert since the last <Esc>.
  inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
                                \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

  if has('nvim')
    inoremap <silent><expr> <c-space> coc#refresh()
  else
    inoremap <silent><expr> <c-@> coc#refresh()
  endif

  " Without coc, K stays vim's keywordprg — in C the man page c.vim points at.
  nnoremap <silent> K :call <SID>ShowDocumentation()<CR>
endif

nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Language servers, and the filetypes `gq` routes through them — one 'when' per
" block keeps the two in step. Do NOT also list any of these in plug.vim.
let s:coc_spec = [
      \ {'when': v:true,
      \  'ext':  ['coc-marketplace', 'coc-json', 'coc-sqlfluff',
      \           'coc-highlight', 'coc-spell-checker', 'coc-cspell-dicts'],
      \  'gq':   ['json', 'jsonc', 'sql']},
      \ {'when': VimLangEnabled('javascript'),
      \  'ext':  ['coc-tsserver', 'coc-eslint'],
      \  'gq':   ['javascript', 'javascriptreact', 'typescript', 'typescriptreact']},
      \ {'when': VimLangEnabled('php'),
      \  'ext':  ['@yaegassy/coc-intelephense', 'coc-blade'],
      \  'gq':   ['php', 'blade']},
      \ {'when': VimLangEnabled('python'),
      \  'ext':  ['coc-pyright'],
      \  'gq':   ['python']},
      \ {'when': VimLangEnabled('c'),
      \  'ext':  ['coc-clangd'],
      \  'gq':   ['c', 'cpp']},
      \ {'when': VimLangEnabled('javascript') || VimLangEnabled('php'),
      \  'ext':  ['coc-css', '@yaegassy/coc-tailwindcss3', 'coc-prettier'],
      \  'gq':   ['css', 'scss', 'html', 'yaml']},
      \ ]

let g:coc_global_extensions = []
let s:coc_gq = []
for s:block in s:coc_spec
  if s:block.when
    let g:coc_global_extensions += s:block.ext
    let s:coc_gq += s:block.gq
  endif
endfor
unlet s:block

" Behind s:coc_ready — `silent` suppresses messages, not errors, so a clone with
" no coc raised E117 every 300ms of idle.
augroup CocSetup
  autocmd!
  if s:coc_ready
    autocmd CursorHold * silent call CocActionAsync('highlight')
    execute 'autocmd FileType' join(s:coc_gq, ',')
          \ "setl formatexpr=CocAction('formatSelected')"
    autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
  endif
  " SCSS treats @-rules as part of a keyword for completion. Harmless without
  " coc, so it stays outside the guard.
  autocmd FileType scss setl iskeyword+=@-@
augroup END

" Code actions. coc's README also maps normal-mode <leader>a and <leader>r,
" which stall as prefixes of these — visual-mode only here. See "Keys" in README.
xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>ac <Plug>(coc-codeaction-cursor)
nmap <leader>as <Plug>(coc-codeaction-source)

" With the other code actions, not on <leader>cl — that's nerdcommenter's.
nmap <leader>al <Plug>(coc-codelens-action)

nmap <leader>qf <Plug>(coc-fix-current)

" Refactor. See above for why there's no normal-mode <leader>r.
nmap <silent> <leader>re <Plug>(coc-codeaction-refactor)
xmap <silent> <leader>r  <Plug>(coc-codeaction-refactor-selected)

" Function and class text objects. Silently inert on a server that doesn't
" implement 'textDocument/documentSymbol'.
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
omap ic <Plug>(coc-classobj-i)
xmap ac <Plug>(coc-classobj-a)
omap ac <Plug>(coc-classobj-a)

" Expand the selection to the next enclosing range. On <leader>s, not coc's
" <C-s>: that is XOFF, and without `stty -ixon` it never reaches vim at all.
nmap <silent> <leader>s <Plug>(coc-range-select)
xmap <silent> <leader>s <Plug>(coc-range-select)

command! -nargs=0 Format :call CocActionAsync('format')
command! -nargs=? Fold   :call CocAction('fold', <f-args>)
command! -nargs=0 OR     :call CocActionAsync('runCommand', 'editor.action.organizeImport')

" NOTE: no `set statusline` here, despite coc's README. airline owns it and
" surfaces coc's status through its 'coc' extension — see airline.vim.

" CocList, under a <leader>l ("list") prefix. coc's README puts these on bare
" <space>a/c/e/o/s/j/k/p, each claiming a whole namespace. See "Keys" in README.
nnoremap <silent><nowait> <leader>ld :<C-u>CocList diagnostics<CR>
nnoremap <silent><nowait> <leader>le :<C-u>CocList extensions<CR>
nnoremap <silent><nowait> <leader>lc :<C-u>CocList commands<CR>
nnoremap <silent><nowait> <leader>lo :<C-u>CocList outline<CR>
nnoremap <silent><nowait> <leader>ls :<C-u>CocList -I symbols<CR>
nnoremap <silent><nowait> <leader>lj :<C-u>CocNext<CR>
nnoremap <silent><nowait> <leader>lk :<C-u>CocPrev<CR>
nnoremap <silent><nowait> <leader>lp :<C-u>CocListResume<CR>
