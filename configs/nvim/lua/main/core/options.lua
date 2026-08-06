-- options.lua
--
-- Editor-wide option defaults.
--
-- This file contains persistent Neovim settings that control editor
-- behaviour, appearance, navigation, numbering, undo history, and
-- other core functionality.
--
-- Keep event-driven logic in `autocmds.lua`,
-- keybindings in `keymaps.lua`,
-- plugin configuration in `plugins/*.lua`,
-- and general editor settings in this file.

-- use system clipboard for all yank, delete, change and paste operations.
-- use windows clipboard (calls powershell).
vim.g.clipboard = {
    name = "WindowsClipboard",
    copy = {
        ["+"] = "clip.exe",
        ["*"] = "clip.exe",
    },
    paste = {
        ["+"] = {
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "Get-Clipboard",
        },
        ["*"] = {
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "Get-Clipboard",
        },
    },
    cache_enabled = 0,
}

vim.opt.clipboard = "unnamedplus"

-- line numbers and relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"

vim.api.nvim_set_hl(0, "AbsoluteLineNr", {
	fg = "#6c7086",
})

vim.api.nvim_set_hl(0, "RelativeLineNr", {
	fg = "#45475a",
})

vim.opt.statuscolumn = table.concat({
	"%#AbsoluteLineNr#",
	"%=%{v:lnum}",
	" ",
	"%#RelativeLineNr#",
	"%{v:relnum == 0 ? '' : v:relnum}",
	" ",
})

-- persistant undo for undotree
vim.opt.undofile = true
