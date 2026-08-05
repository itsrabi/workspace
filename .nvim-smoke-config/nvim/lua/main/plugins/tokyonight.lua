-- main/plugins/tokyonight.lua

return {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        local ok, tokyonight = pcall(require, "tokyonight")
        if not ok then
            return
        end

        tokyonight.setup({
            styles = {
                comments = { italic = true },
            },
        })
    end,
}
