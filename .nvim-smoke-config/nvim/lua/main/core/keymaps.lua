-- main/core/keymaps.lua
--
-- Repo-owned core keymaps.
--
-- Loaded by `main.core`.

-- Harpoon ----------------------------------------------------------

vim.keymap.set("n", "<leader>h", function()
	require("harpoon.ui").toggle_quick_menu()
end, { desc = "Harpoon: toggle quick menu" })

vim.keymap.set("n", "<leader>H", function()
	require("harpoon.mark").add_file()
end, { desc = "Harpoon: add file" })

-- FZF --------------------------------------------------------------

local function fzf_available()
	return vim.fn.executable("fzf") == 1 and vim.fn.executable("rg") == 1 and vim.fn.executable("fd") == 1
end

local function in_interactive_term()
	local term = vim.fn.getenv("TERM")
	return term ~= nil and term ~= ""
end

local function run_fzf(fn, desc)
	if not fzf_available() then
		vim.notify((desc or "FZF") .. ": fzf/rg/fd not available", vim.log.levels.ERROR)
		return
	end

	-- Avoid hanging/headless errors in CI smoke; on a real TTY TERM is set.
	if not in_interactive_term() then
		vim.notify((desc or "FZF") .. ": requires an interactive terminal", vim.log.levels.WARN)
		return
	end

	local ok, err = pcall(fn)
	if not ok then
		vim.notify((desc or "FZF") .. ": " .. tostring(err), vim.log.levels.ERROR)
	end
end

vim.keymap.set("n", "<leader><space>", function()
	run_fzf(function()
		require("fzf-lua").files()
	end, "FZF: find files")
end, { desc = "FZF: find files" })

vim.keymap.set("n", "<leader>/", function()
	run_fzf(function()
		require("fzf-lua").live_grep()
	end, "FZF: search text")
end, { desc = "FZF: search text" })

vim.keymap.set("n", "<leader>fb", function()
	run_fzf(function()
		require("fzf-lua").buffers()
	end, "FZF: buffers")
end, { desc = "FZF: buffers" })

vim.keymap.set("n", "<leader>fg", function()
	run_fzf(function()
		require("fzf-lua").git_files()
	end, "FZF: git files")
end, { desc = "FZF: git files" })

vim.keymap.set("n", "<leader>fr", function()
	run_fzf(function()
		require("fzf-lua").oldfiles()
	end, "FZF: recent files")
end, { desc = "FZF: recent files" })

-- Explorer ---------------------------------------------------------

vim.keymap.set("n", "<leader>e", function()
	require("snacks").explorer.open()
end, { desc = "Snacks: toggle file explorer" })

-- Oil --------------------------------------------------------------

vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })

vim.keymap.set("n", "<leader>-", function()
	require("oil").toggle_float()
end, { desc = "Oil: toggle float" })

-- Move line up/down (Alt-j / Alt-k) ------------------------------

vim.keymap.set("n", "<M-j>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
vim.keymap.set("n", "<M-k>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
vim.keymap.set("v", "<M-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "<M-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- yazi ------------------------------------------------------------

vim.keymap.set("n", "\\", function()
	require("yazi").yazi()
end, { desc = "Yazi: open" })

-- Scratch ---------------------------------------------------------

vim.api.nvim_create_user_command("Scratch", function()
	vim.cmd("enew")
	vim.bo.buftype = "nofile"
	vim.bo.bufhidden = "hide"
	vim.bo.swapfile = false
end, { desc = "Scratch: open scratch buffer" })

-- undotree --------------------------------------------------------
vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle, { desc = "Toggle UndoTree" })

-- vim-fugitive (Git) ----------------------------------------------
vim.keymap.set("n", "<leader>gg", vim.cmd.Git, { desc = "Git status" })

vim.keymap.set("n", "<leader>gc", function()
	vim.cmd("Git commit")
end, { desc = "Git commit" })

vim.keymap.set("n", "<leader>gp", function()
	vim.cmd("Git push")
end, { desc = "Git push" })

vim.keymap.set("n", "<leader>gl", function()
	vim.cmd("Git log --oneline --graph --decorate")
end, { desc = "Git log" })

vim.keymap.set("n", "<leader>gb", function()
	vim.cmd("Git blame")
end, { desc = "Git blame" })

vim.keymap.set("n", "<leader>gd", vim.cmd.Gvdiffsplit, { desc = "Git diff" })
