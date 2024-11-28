Configuring VIM (~/.vimrc) 

Could be further extended by installing plugins or moving onto nvim. This base config is usually enough for me to do most of my work tho.


```
" Fix glitches with arrows & a few other quality of life things
set nocompatible

" Set line numbering
set number

" Replace tab with 2x spaces
set expandtab
set tabstop=2
set shiftwidth=2

" Syntax hilight
syntax enable

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

" Create backups (don't forget to mkdir -p  ~/.vim/swaps)
set directory=~/.vim/swaps/
set updatecount=100
```
