" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"  Comments in vimscript start with a double quote (").
"  `set foo`   enables
"  `set nofoo` disables
"  `set foo?`  queries
"  `set foo!`  toggles
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼

" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                                          BASELINE
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Disable vi-compatibility mode.
set nocompatible

" Enable filetype detection, filetype-specific plugins, and filetype-specific
" indent rules. This one line drives most of Vim's "it just knows" behavior.
filetype plugin indent on

" Turn on syntax highlighting.
syntax enable

" UTF-8 everywhere.
" encoding = internal representation
" fileencoding = what gets written to disk
set encoding=utf-8
set fileencoding=utf-8

" Let backspace work the way every other editor does
set backspace=indent,eol,start

" Allow modified buffers to be hidden instead of forcing a write.
set hidden

" Reload the file if it changed on disk and you haven't modified it in Vim.
set autoread

" Ask "Save changes?" instead of erroring out on :q with unsaved work.
set confirm

" Command history depth (default is 50).
set history=1000

" Enable mouse support in all modes.
set mouse=a

" Use the system clipboard for unnamed yank/paste, so `yy` in Vim and Cmd-V in
" another app agree. Requires a Vim built with +clipboard.
"   Check :  vim --version | grep clipboard   (want +clipboard, not -clipboard)
"   macOS system vim is often -clipboard; `brew install vim` fixes it.
" On Linux, `unnamedplus` targets the CTRL-V clipboard; `unnamed` targets
" the middle-click primary selection. Setting both is a reasonable default.
if has('clipboard')
  if has('unnamedplus')
    set clipboard=unnamed,unnamedplus
  else
    set clipboard=unnamed
  endif
endif


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                                    USER INTERFACE
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Line numbers. `number` + `relativenumber` gives "hybrid" numbering: the
" cursor line shows its absolute number, others show distance — so 8k / 12dd
" style motions become countable at a glance.
set number
set relativenumber

" Subtly highlight the line the cursor is on.
set cursorline

" Always reserve sign column so linter/git gutters don't shove text sideways
" when a sign appears and disappears.
if has('patch-8.1.1564')
  set signcolumn=yes
endif

" Keep this many lines of context above/below the cursor while scrolling, and
" this many columns left/right when scrolling sideways with nowrap.
set scrolloff=10
set sidescrolloff=10

" Don't hard-wrap long lines; when a line does wrap visually, break at word
" boundaries and indent the continuation so wrapped code stays readable.
set nowrap
set linebreak
set breakindent

" Show partial command you're typing (bottom right) and the cursor position.
set showcmd
set ruler

" Always show the status line, even with a single window.
set laststatus=2

" Tab-completion in the : command line — show a menu, complete to the longest
" unambiguous match first, then cycle. `:` then start typing a command and
" use Tab to show command options.
set wildmenu
set wildmode=longest:full,full
set wildignorecase

" Don't offer these in file completion.
set wildignore+=*.o,*.pyc,*.class,*/node_modules/*,*/.git/*,*.swp

" Show invisible characters (toggleable below with <Leader>l). Whitespace bugs
" in Makefiles and YAML stop being mysterious once you can see them.
set list
set listchars=tab:▸\ ,trail:·,extends:❯,precedes:❮,nbsp:␣

" Draw a soft column guide at 100 chars as a style reminder.
" People will argue over this. 80, 88, 100 and 120 are common.
set colorcolumn=100

" Highlight the matching bracket briefly when you type the closing one.
set showmatch
set matchtime=2

" Don't beep or flash. Remove both lines if you actually want the bell.
" set noerrorbells
" set novisualbell
" set t_vb=
set belloff=all

" Show a few lines of context around the last line of a wrapped display, and
" render the last line even if it doesn't fit entirely.
set display+=lastline

" Shorter messages; don't show the intro screen.
set shortmess+=I


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                                            SEARCH
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Case-insensitive search by default, BUT case-sensitive the moment you type an
" uppercase letter. `ignorecase` alone is a trap; the pair is what you want.
set ignorecase
set smartcase

" Jump to matches as you type the pattern, and highlight all matches.
set incsearch
set hlsearch

" Restart the search at the top when you hit the bottom (default on; explicit here).
set wrapscan

" Use ripgrep for :grep if it's installed — dramatically faster than the default.
if executable('rg')
  set grepprg=rg\ --vimgrep\ --smart-case
  set grepformat=%f:%l:%c:%m
endif


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                          INDENTATION & FORMATTING
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Insert spaces when you press Tab.
set expandtab

" tabstop     — how wide an existing literal tab character renders
" softtabstop — how many columns Tab/Backspace move in insert mode
" shiftwidth  — how many columns >> << and autoindent shift
" Keeping all three equal avoids a whole category of confusing behavior.
set tabstop=4
set softtabstop=4
set shiftwidth=4

" Round indent operations to a multiple of shiftwidth.
set shiftround

" Copy the previous line's indent on <CR>, and add extra indent after `{`, etc.
" Note : for languages with a real indent plugin (Python, Go, HTML...), the
" filetype indent rules loaded above take precedence over smartindent.
set autoindent
set smartindent

" Automatic formatting rules (see :help fo-table):
"   j — remove the comment leader when joining commented lines
"   r — continue the comment leader when you press Enter in insert mode
"   c — auto-wrap comments to textwidth
"   q — allow gq to format comments
"   Removing 't' and 'o' keeps Vim from hard-wrapping your code or continuing
"   comments when you press o/O, which most people find surprising.
set formatoptions+=j
set formatoptions+=rcq
set formatoptions-=t
set formatoptions-=o

" Per-language indentation overrides. Two spaces is the community norm for
" these; adjust to your preferences.
augroup indent_by_filetype
  autocmd!
  autocmd FileType yaml,json,html,css,scss,javascript,typescript,vue,sh,bash,lua,ruby
        \ setlocal tabstop=2 softtabstop=2 shiftwidth=2
  autocmd FileType make setlocal noexpandtab   " Makefiles REQUIRE real tabs
  autocmd FileType gitcommit setlocal textwidth=72 spell
  autocmd FileType markdown setlocal wrap linebreak spell textwidth=0
augroup END


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                             FILES, BACKUPS & UNDO
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Persistent undo: undo history survives closing and reopening the file.
if has('persistent_undo')
  let s:undodir = expand('~/.vim/undo')
  if !isdirectory(s:undodir)
    call mkdir(s:undodir, 'p', 0700)
  endif
  let &undodir = s:undodir
  set undofile
  set undolevels=1000
endif

" Keep swap and backup files, but corral them out of your project directories.
" (If you'd rather have none at all: set noswapfile / set nobackup.)
let s:swapdir = expand('~/.vim/swap')
if !isdirectory(s:swapdir) | call mkdir(s:swapdir, 'p', 0700) | endif
let &directory = s:swapdir . '//'   " trailing // = encode full path in the name

let s:backupdir = expand('~/.vim/backup')
if !isdirectory(s:backupdir) | call mkdir(s:backupdir, 'p', 0700) | endif
let &backupdir = s:backupdir . '//'
set backup
set writebackup

" Write the backup by copying, then overwriting the original. Preserves inodes,
" symlinks, and file ownership — important when editing files under /etc.
set backupcopy=yes

" Remember marks, registers, and the jumplist between sessions.
" '100 = marks for 100 files, <50 = 50 lines per register, s10 = 10KB max item,
" h = don't restore hlsearch state on startup.
set viminfo='100,<50,s10,h

" Reopen a file at the line you were on. The guard skips commit messages, where
" you always want to start at the top.
augroup restore_cursor
  autocmd!
  autocmd BufReadPost *
        \ if line("'\"") > 0 && line("'\"") <= line("$") && &filetype !~# 'commit'
        \ |   execute 'normal! g`"'
        \ | endif
augroup END

" Strip trailing whitespace on save, preserving cursor position.
" Comment this out if you work in repos where that would create noisy diffs.
augroup strip_trailing_ws
  autocmd!
  autocmd BufWritePre * let s:view = winsaveview() | keeppatterns %s/\s\+$//e | call winrestview(s:view)
augroup END


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                     WINDOWS, SPLITS & PERFORMANCE
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" New splits open below and to the right — matches how most people read.
set splitbelow
set splitright

" Don't redraw during macros and scripts. Makes heavy macros visibly faster.
set lazyredraw
set ttyfast

" Faster response for plugins that key off CursorHold (git gutters, LSP hints).
" Also controls how long before the swap file is written.
set updatetime=300

" How long Vim waits for a mapping sequence to complete (mappings vs. key codes).
" 500ms keeps <Leader> chords comfortable without a sluggish <Esc>.
set timeout
set timeoutlen=500
set ttimeoutlen=10


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                                      KEY MAPPINGS
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Convention: use `nnoremap` / `inoremap` (non-recursive) rather than `nmap`,
" so your mapping can't be re-interpreted by another mapping. Reserve plain
" `map` for cases where recursion is intentional.

" Leader key: Space is the modern consensus (large, unused, both thumbs).
" Set it before any <Leader> mapping is defined.
let mapleader = ' '
let maplocalleader = ','

" Space is now the leader, so make sure it doesn't also move the cursor.
nnoremap <Space> <Nop>

" --- Search ---
" Clear search highlighting. `:noh` doesn't disable hlsearch, it just clears the
" current highlight until the next search — exactly what you want.
nnoremap <silent> <Leader><Space> :nohlsearch<CR>

" Keep the cursor centered when jumping through search results.
nnoremap n nzzzv
nnoremap N Nzzzv

" --- Files & buffers ---
nnoremap <Leader>w :write<CR>
nnoremap <Leader>q :quit<CR>
nnoremap <Leader>e :edit<Space>
nnoremap <Leader>b :buffers<CR>:buffer<Space>
nnoremap <Tab>     :bnext<CR>
nnoremap <S-Tab>   :bprevious<CR>
nnoremap <Leader>d :bdelete<CR>

" Write a file you opened without sudo. `tee` runs as root and writes for you.
cnoremap w!! execute 'silent! write !sudo tee % >/dev/null' <Bar> edit!

" --- Window navigation ---
" Ctrl + h/j/k/l instead of Ctrl-w then h/j/k/l.
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Resize splits with <Leader> + arrow keys.
" NOTE: do NOT map bare <Up>/<Down>/<Left>/<Right> here — that steals the arrow
" keys from normal-mode cursor movement, which breaks them for anyone who
" reaches for them (and for anyone you hand this config to).
nnoremap <silent> <Leader><Up>    :resize   +2<CR>
nnoremap <silent> <Leader><Down>  :resize   -2<CR>
nnoremap <silent> <Leader><Left>  :vertical resize -2<CR>
nnoremap <silent> <Leader><Right> :vertical resize +2<CR>

" --- Editing ---
" Stay in visual mode after shifting, so you can indent repeatedly.
vnoremap < <gv
vnoremap > >gv

" Move the selected lines up/down and re-indent.
vnoremap J :move '>+1<CR>gv=gv
vnoremap K :move '<-2<CR>gv=gv

" Paste over a selection without clobbering your register with the deleted text.
xnoremap <Leader>p "_dP

" Move by visual line when a line is wrapped — but only when no count is given,
" so 5j still jumps 5 real lines (important for relativenumber).
nnoremap <expr> j v:count == 0 ? 'gj' : 'j'
nnoremap <expr> k v:count == 0 ? 'gk' : 'k'

" Break the undo sequence at these points, so one `u` doesn't erase a whole
" paragraph you typed without leaving insert mode.
inoremap , ,<C-g>u
inoremap . .<C-g>u
inoremap ! !<C-g>u
inoremap ? ?<C-g>u

" --- Toggles ---
nnoremap <silent> <Leader>l :set list!<CR>
nnoremap <silent> <Leader>n :set relativenumber!<CR>
nnoremap <silent> <Leader>s :setlocal spell!<CR>

" Toggle paste mode. Rarely needed on Vim 8.2+ in a terminal that supports
" bracketed paste, but invaluable when auto-indent mangles a pasted block.
" ('pastetoggle' is deprecated and gone in recent Vim, hence the guard.)
if exists('&pastetoggle')
  set pastetoggle=<F2>
endif

" --- Netrw (Vim's built-in file explorer) ---
nnoremap <Leader>f :Explore<CR>
let g:netrw_banner    = 0    " hide the help banner
let g:netrw_liststyle = 3    " tree view
let g:netrw_winsize   = 25   " open at 25% width when used as a sidebar

" (Removed: a "highlight on yank" autocmd. That's a Neovim feature
" (vim.highlight.on_yank) with no clean equivalent in plain Vim — the usual
" ports drop you into visual mode after every yank. If you want it, use the
" machakann/vim-highlightedyank plugin rather than hand-rolling it.)


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                         TRUE COLOR  (prerequisite for catppuccin)
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" 24-bit color must be on or catppuccin will fall back to an approximation and
" look muddy. Requirements: a true-color terminal (iTerm2, Kitty, WezTerm,
" Alacritty, Ghostty, Windows Terminal, GNOME Terminal) and Vim 8.0+.
"
" Verify your terminal:  printf '\e[38;2;255;100;0mTRUECOLOR\e[0m\n'
"   → orange text means yes; muddy red means no.

if has('termguicolors')
  " Inside tmux/screen, Vim needs to be told the escape sequences for setting
  " RGB foreground (t_8f) and background (t_8b). Without these two lines,
  " termguicolors inside tmux produces wrong or absent colors.
  if empty($TMUX) == 0 || &term =~# '^screen'
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  endif
  set termguicolors
endif

" Tell Vim your terminal has a dark background so it picks readable defaults
" (and so mocha/macchiato/frappé render correctly). Use 'light' for latte.
set background=dark


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                    PLUGINS  (optional — everything above works with zero plugins)
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Two ways to install; pick one.
"
" -- Option A: vim-plug ------------------------------------------------------
"   curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
"     https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
"   Then uncomment the block below and run :PlugInstall
"
" -- Option B: native packages (Vim 8+, no plugin manager, just git) ---------
"   mkdir -p ~/.vim/pack/plugins/start
"   git clone https://github.com/catppuccin/vim ~/.vim/pack/plugins/start/catppuccin
"   Vim loads anything under pack/*/start/ automatically. Update with git pull.
"   This is my preference for a teaching machine: nothing to explain, nothing
"   to break, and `git pull` is the whole upgrade story.

" if filereadable(expand('~/.vim/autoload/plug.vim'))
"   call plug#begin('~/.vim/plugged')
"
"     " --- Theme ---
"     Plug 'catppuccin/vim', { 'as': 'catppuccin' }
"
"     " --- Status line (lightweight, has first-class catppuccin support) ---
"     Plug 'itchyny/lightline.vim'
"
"     " --- Widely-respected, low-friction quality-of-life plugins ---
"     Plug 'tpope/vim-sensible'      " defaults everyone agrees on (overlaps this file)
"     Plug 'tpope/vim-surround'      " cs"' ds( ysiw] — change/delete/add surroundings
"     Plug 'tpope/vim-commentary'    " gcc / gc{motion} to toggle comments
"     Plug 'tpope/vim-repeat'        " make . repeat plugin actions too
"     Plug 'tpope/vim-fugitive'      " :Git — the definitive git wrapper
"     Plug 'tpope/vim-unimpaired'    " ]q [q ]b [b — paired bracket mappings
"     Plug 'airblade/vim-gitgutter'  " git diff signs in the gutter
"     Plug 'jiangmiao/auto-pairs'    " auto-close brackets and quotes
"     Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
"     Plug 'junegunn/fzf.vim'        " :Files :Rg :Buffers — fuzzy everything
"
"   call plug#end()
" endif

" fzf mappings (only meaningful if fzf.vim is installed)
if exists(':Files')
  nnoremap <Leader>ff :Files<CR>
  nnoremap <Leader>fg :Rg<CR>
  nnoremap <Leader>fb :Buffers<CR>
endif


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                                  CATPPUCCIN THEME
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Catppuccin ships four flavors. Pick one:
"
"   catppuccin_latte       — light, warm       (pair with: set background=light)
"   catppuccin_frappe      — dark, low contrast, cool
"   catppuccin_macchiato   — dark, medium contrast
"   catppuccin_mocha       — dark, highest contrast  ← the popular default
"
" Optional knobs, set BEFORE :colorscheme:
"
"   g:catppuccin_flavour        — used by some ports; harmless to set
"   let g:airline_theme         — if you use vim-airline instead of lightline
"
" Transparency: if you want your terminal's own background/blur to show
" through, clear the Normal background after the colorscheme loads (see below).

" Load the theme.
"
" WHY THIS ISN'T GUARDED WITH globpath(&runtimepath, ...):
"   Vim 8 packages under ~/.vim/pack/*/start/ are NOT added to 'runtimepath'
"   until AFTER the vimrc finishes being sourced (:help packload-two-steps).
"   So while the vimrc is running, globpath() cannot see the catppuccin colors
"   directory and any check based on it always fails.
"
"   :colorscheme does not have that problem — it searches 'runtimepath' AND
"   the 'packpath' start/ and opt/ directories directly. So just call it.
"
" `silent!` swallows the E185 error if the plugin isn't installed yet, and
" g:colors_name tells us afterwards whether it actually took.
silent! colorscheme catppuccin_mocha

if !exists('g:colors_name') || g:colors_name !=# 'catppuccin_mocha'
  " Reasonable dark fallbacks shipped with Vim itself.
  silent! colorscheme habamax          " Vim 8.2.3550+
  if !exists('g:colors_name')
    silent! colorscheme desert         " available essentially everywhere
  endif
endif

" ⎼⎼⎼⎼ Optional: transparent background ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Uncomment to let the terminal background show through. Must run AFTER the
" colorscheme, hence the ColorScheme autocmd so it survives :colorscheme calls.
" augroup catppuccin_transparent
"   autocmd!
"   autocmd ColorScheme * highlight Normal     guibg=NONE ctermbg=NONE
"   autocmd ColorScheme * highlight NonText    guibg=NONE ctermbg=NONE
"   autocmd ColorScheme * highlight SignColumn guibg=NONE ctermbg=NONE
"   autocmd ColorScheme * highlight EndOfBuffer guibg=NONE ctermbg=NONE
" augroup END

" ⎼⎼⎼⎼ Optional: soften the cursorline / colorcolumn  ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Catppuccin's defaults are good, but if the cursorline reads too strongly,
" override it here (surface0 in mocha is #313244).
" highlight CursorLine   guibg=#313244
" highlight ColorColumn  guibg=#313244

" ⎼⎼⎼⎼ Status line ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" If lightline is installed, use the matching catppuccin theme so the status
" line doesn't clash with the buffer.
let g:lightline = {
      \ 'colorscheme': 'catppuccin_mocha',
      \ 'active': {
      \   'left':  [ [ 'mode', 'paste' ],
      \              [ 'gitbranch', 'readonly', 'filename', 'modified' ] ],
      \   'right': [ [ 'lineinfo' ], [ 'percent' ],
      \              [ 'fileformat', 'fileencoding', 'filetype' ] ]
      \ },
      \ 'component_function': { 'gitbranch': 'FugitiveHead' },
      \ }

" With lightline showing the mode, Vim's own "-- INSERT --" is redundant.
if exists('g:loaded_lightline')
  set noshowmode
endif

" If you prefer vim-airline instead of lightline, use this and delete the
" g:lightline block above:
"   let g:airline_theme = 'catppuccin_mocha'
"   let g:airline_powerline_fonts = 1      " requires a Nerd Font

" ⎼⎼⎼⎼ No-plugin status line ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" A decent status line using only builtins, in case you skip lightline.
" Uncomment to use.
" set statusline=
" set statusline+=\ %f                      " relative path
" set statusline+=\ %m%r                    " modified / readonly flags
" set statusline+=%=                        " right-align everything after this
" set statusline+=\ %y                      " filetype
" set statusline+=\ %{&fileencoding?&fileencoding:&encoding}
" set statusline+=\ [%{&fileformat}]
" set statusline+=\ %l:%c                   " line:column
" set statusline+=\ %p%%\                   " percent through file


" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                                   LOCAL OVERRIDES
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
" Keep machine-specific settings (work laptop vs. lab box) out of version
" control by putting them in ~/.vimrc.local. Sourced last so it wins.
if filereadable(expand('~/.vimrc.local'))
  source ~/.vimrc.local
endif

" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
"                                                                                               END
" ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼

