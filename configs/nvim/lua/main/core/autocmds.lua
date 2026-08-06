-- autocmds.lua
--
-- Autocommands define event-driven editor behaviour.
--
-- Neovim emits events as you work (startup, opening files,
-- saving buffers, yanking text, switching windows, etc.).
-- This file centralizes custom actions that should run
-- automatically when those events occur.
--
-- Examples:
--   - Highlight yanked text
--   - Restore cursor position when reopening files
--   - Format on save
--   - Adjust editor behaviour for specific file types
--   - Refresh UI elements when buffers change
--
-- Keep general editor settings in `options.lua`,
-- keybindings in `keymaps.lua`,
-- and event-driven behaviour in this file.


-- Highlight text on yank
vim.api.nvim_set_hl(0, "YankHighlight", {
    bg = "#bb9af7",
    fg = "#1a1b26",
})

vim.api.nvim_create_autocmd("TextYankPost", {
    desc = "Highlight yanked text",
    group = vim.api.nvim_create_augroup("highlight-yank", {
        clear = true,
    }),
    callback = function()
        vim.hl.on_yank({
            higroup = "IncSearch",
            timeout = 200,
        })
    end,
})

-- Disable line numbers on alpha dashboard buffer
vim.api.nvim_create_autocmd("FileType", {
    desc = "Disable gutters on Alpha dashboard",
    pattern = "alpha",
    callback = function()
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
        vim.opt_local.signcolumn = "no"
        vim.opt_local.statuscolumn = ""
    end,
})
