call plug#begin('~/local/share/nvim/plugged')
	Plug 'vifm/vifm.vim'    
	Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
	Plug 'vim-airline/vim-airline'
	Plug 'airblade/vim-gitgutter'
    Plug 'jreybert/vimagit' 
	Plug 'itchyny/lightline.vim' 



call plug#end()
syntax on
set mouse=a
set nospell spelllang=en_us
source ~/.vimrc
