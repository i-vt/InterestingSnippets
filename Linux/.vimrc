" -------------------------
" General Quality of Life
" -------------------------
set nocompatible           " Avoid legacy Vi quirks
set encoding=utf-8         " Ensure proper encoding
set fileencoding=utf-8     " Default file encoding

" -------------------------
" UI Enhancements
" -------------------------
set number                 " Show line numbers
set relativenumber         " Relative line numbers for easier navigation
set cursorline             " Highlight the current line
set showcmd                " Show partial commands
set showmatch              " Highlight matching brackets
set wildmenu               " Tab-complete commands in status line
set laststatus=2           " Always show status line

" -------------------------
" Tabs & Indentation
" -------------------------
set expandtab              " Use spaces instead of tabs
set tabstop=4              " Number of spaces per tab
set shiftwidth=4           " Indent size
set autoindent             " Maintain indent from previous line
set smartindent            " Smarter auto-indent
set smarttab               " Tab respects 'tabstop' and 'shiftwidth'

" -------------------------
" Search
" -------------------------
set hlsearch               " Highlight matches
set incsearch              " Show matches as you type
set ignorecase             " Ignore case in search
set smartcase              " ...unless you type uppercase
highlight Search ctermfg=Yellow ctermbg=NONE guifg=Yellow guibg=NONE

" -------------------------
" Editing
" -------------------------
set backspace=indent,eol,start   " Fix backspace
set clipboard=unnamedplus        " Use system clipboard
set wrap                         " Wrap long lines
set linebreak                    " Wrap at word boundaries

" -------------------------
" Performance & Warnings
" -------------------------
set shortmess+=FA          " Suppress swap warnings + 'press enter'
set updatetime=300         " Faster updates (good for plugins)

" -------------------------
" Mouse & Navigation
" -------------------------
set mouse=a                " Enable mouse
set scrolloff=5            " Keep 5 lines visible when scrolling
set sidescrolloff=5        " Same for horizontal scroll

" -------------------------
" Visual Tweaks
" -------------------------
set termguicolors          " True color support
set colorcolumn=100        " Highlight column 80 for code style
