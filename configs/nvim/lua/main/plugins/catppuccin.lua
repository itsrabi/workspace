-- main/plugins/catppuccin.lua

return {
    "catppuccin/nvim",
    lazy = false,
    priority = 1000,
    config = function()
        local ok, catppuccin = pcall(require, "catppuccin")
        if not ok then
            return
        end

        catppuccin.setup({
            flavour = "mocha",
        })
    end,
}
