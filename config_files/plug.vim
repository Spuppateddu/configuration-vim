" vim-plug plugin list. :PlugInstall after editing, :PlugClean to remove.
" NOTE: coc extensions do NOT belong here — see g:coc_global_extensions.

call plug#begin()

" ── Core ────────────────────────────────────────────────────────────────────
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'preservim/nerdtree'
Plug 'preservim/nerdcommenter'
Plug 'christoomey/vim-tmux-navigator'
Plug 'simeji/winresizer'
Plug 'mg979/vim-visual-multi'
Plug 'vim-airline/vim-airline'

" Clipboard over SSH/tmux via OSC 52 — this vim has no +clipboard.
Plug 'ojroques/vim-oscyank'

" ── Git ─────────────────────────────────────────────────────────────────────
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'

" ── Languages ───────────────────────────────────────────────────────────────
" Syntax/indent only; the language servers are coc extensions. Everything past
" markdown follows g:vim_languages — re-run ./install.sh to change it.

" vim-markdown folds every section by default, which hides most of the file.
" Set here rather than after plug#end(), since the plugin reads it on load.
let g:vim_markdown_folding_disabled = 1
Plug 'preservim/vim-markdown'

" PHP — Blade is Laravel's template language, and vim has no syntax for it.
if VimLangEnabled('php')
  Plug 'jwalton512/vim-blade'
endif

" JavaScript — the bundled syntax stops at ES5 and knows nothing about JSX.
if VimLangEnabled('javascript')
  Plug 'pangloss/vim-javascript'
  Plug 'maxmellon/vim-jsx-pretty'
endif

" ── Colorscheme ─────────────────────────────────────────────────────────────
Plug 'morhetz/gruvbox'

call plug#end()
