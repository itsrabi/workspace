-- main/plugins/snacks.lua

return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
        notify = { enabled = false },
        explorer = {
            replace_netrw = false,
        },
    },
}
