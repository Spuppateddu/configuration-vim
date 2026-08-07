" vim-airline. It owns 'statusline' and 'tabline' — nothing else should set them.

" Named outright: unset, airline globs the runtimepath for a theme matching
" 'colors_name' on every scheme load. Has to stay in step with colorscheme.vim.
let g:airline_theme = 'gruvbox'

" Cache the highlight-group lookups airline builds its sections from — roughly
" 1500 synIDattr() calls before the first draw. Invalidated on ColorScheme.
let g:airline_highlighting_cache = 1

let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#left_sep = ' '
let g:airline#extensions#tabline#left_alt_sep = '|'
let g:airline#extensions#tabline#formatter = 'unique_tail'

" Without this list airline loads every extension it can detect. 'branch' backs
" section_b and 'coc' the diagnostic counts; without them those go silently empty.
let g:airline_extensions = ['branch', 'tabline', 'coc']

" Global because it is named inside a '%{...}', which the statusline evaluates
" from no script context. `Vim` prefix as in functions.vim.
function! VimGetcwdTail() abort
  return fnamemodify(getcwd(), ':t')
endfunction

function! s:AirlineInit() abort
  let g:airline_section_a = airline#section#create(['mode'])
  let g:airline_section_b = airline#section#create(['branch'])
  let g:airline_section_c = airline#section#create(['%f'])
  " '%{...}', not a direct call: the section has to be re-evaluated on every
  " redraw, or it shows whatever directory vim started in, forever.
  let g:airline_section_x = airline#section#create(['%{VimGetcwdTail()}'])
  " Blank on purpose — the 'coc' extension puts its counts in
  " section_error/section_warning, which are separate from these two.
  let g:airline_section_y = airline#section#create([])
  let g:airline_section_z = airline#section#create([])
endfunction

" Not 'VimEnter': airline's own s:init() runs there and wins, discarding every
" assignment above. AirlineAfterInit is after init, before the first draw.
augroup AirlineSections
  autocmd!
  autocmd User AirlineAfterInit call <SID>AirlineInit()
augroup END
