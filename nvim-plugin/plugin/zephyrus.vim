" Zephyrus Command Center - Neovim Plugin Loader
" Connects to the zephd FastAPI daemon for task/agent management.

if exists('g:loaded_zephyrus') | finish | endif
let g:loaded_zephyrus = 1

" User commands
command! ZephTasks     lua require('zephyrus').task_board()
command! ZephAgents    lua require('zephyrus').agent_panel()
command! ZephDashboard lua require('zephyrus').dashboard()
command! ZephPush      lua require('zephyrus').push_task()
command! ZephRefresh   lua require('zephyrus').refresh()
command! ZephStatus    lua vim.notify(require('zephyrus').status_line())

command! -nargs=1 ZephDiff   lua require('zephyrus').review_diff(<f-args>)
command! -nargs=1 ZephMerge  lua require('zephyrus').merge_task(<f-args>)
command! -nargs=1 ZephReject lua require('zephyrus').reject_task(<f-args>)

" Auto-setup with defaults if the user hasn't called setup() manually.
" This runs after VimEnter so lazy-loaded plugin managers can override it.
augroup ZephyrusAutoSetup
  autocmd!
  autocmd VimEnter * ++once lua pcall(function()
        \ local z = require('zephyrus')
        \ if not z._setup_done then
        \   z.setup()
        \   z._setup_done = true
        \ end
        \ end)
augroup END
