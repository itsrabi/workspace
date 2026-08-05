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

vim.keymap.set("n", "<leader><space>", function()
    require("fzf-lua").files()
end, { desc = "FZF: find files" })

vim.keymap.set("n", "<leader>/", function()
    require("fzf-lua").live_grep()
end, { desc = "FZF: search text" })

vim.keymap.set("n", "<leader>fb", function()
    require("fzf-lua").buffers()
end, { desc = "FZF: buffers" })

vim.keymap.set("n", "<leader>fg", function()
    require("fzf-lua").git_files()
end, { desc = "FZF: git files" })

vim.keymap.set("n", "<leader>fr", function()
    require("fzf-lua").oldfiles()
end, { desc = "FZF: recent files" })

-- Explorer ---------------------------------------------------------

vim.keymap.set("n", "<leader>e", "<cmd>Explore<cr>", {
    desc = "Open file explorer",
})
