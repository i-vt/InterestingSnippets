Configuring VIM (~/.vimrc) 

Could be further extended by installing plugins or moving onto nvim. This base config is usually enough for me to do most of my work tho.


```
" Fix glitches with arrows & a few other quality of life things
set nocompatible

" Set line numbering
set number

" Replace tab with 4x spaces
set expandtab
set tabstop=4
set shiftwidth=4

" Auto indent
set autoindent

" Wrap lines
set wrap

" Highlight search results in a different color
highlight Search ctermfg=Yellow ctermbg=NONE guifg=Yellow guibg=NONE

" Disable swap warning + 'press enter to continue'
set shortmess+=FA

" Enable mouse
set mouse=a
```
