" Colours. Every override goes through a ColorScheme autocmd, not a bare
" :highlight, so it survives the scheme being re-applied (airline does that).
set background=dark

" 24-bit colour. Inside tmux the terminfo advertises no RGB capability, so the
" two sequences must be spelled out by hand (:h xterm-true-color).
if has('termguicolors')
  let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
  let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  set termguicolors
endif

augroup ColorTweaks
  autocmd!
  " Transparent background — let the terminal's own background show through.
  autocmd ColorScheme * highlight Normal      ctermbg=NONE guibg=NONE
  autocmd ColorScheme * highlight NonText     ctermbg=NONE guibg=NONE
  autocmd ColorScheme * highlight LineNr      ctermbg=NONE guibg=NONE
  autocmd ColorScheme * highlight FoldColumn  ctermbg=NONE guibg=NONE
  autocmd ColorScheme * highlight EndOfBuffer ctermbg=NONE guibg=NONE

  autocmd ColorScheme * highlight Visual    cterm=reverse gui=reverse
  autocmd ColorScheme * highlight IncSearch gui=underline,bold guifg=Cyan guibg=Red3

  " Blanks the syntax 'Error' group: the highlighters' guesses about what's
  " invalid are wrong often enough to be noise. Real errors come from coc.
  autocmd ColorScheme * highlight Error     NONE

  autocmd ColorScheme * highlight SpellBad   guifg=#ff0055 gui=bold
  autocmd ColorScheme * highlight SpellCap   guifg=#ffff00 gui=bold
  autocmd ColorScheme * highlight SpellLocal guifg=#00ffff gui=bold
  autocmd ColorScheme * highlight SpellRare  guifg=#cc00ff gui=bold

  " coc.nvim diagnostics — deliberately loud.
  autocmd ColorScheme * highlight CocErrorHighlight   guifg=#ff0055 gui=bold
  autocmd ColorScheme * highlight CocWarningHighlight guifg=#ffff00 gui=bold
  autocmd ColorScheme * highlight CocInfoHighlight    guifg=#ff9900 gui=bold
  autocmd ColorScheme * highlight CocHintHighlight    guifg=#cc00ff gui=bold
augroup END

" silent!: on a fresh clone gruvbox isn't installed yet, and E185 would open the
" very launch you run :PlugInstall from on a "Press ENTER" prompt.
silent! colorscheme gruvbox
