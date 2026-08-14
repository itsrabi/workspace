-- main/plugins/colorschemes.lua
--
-- Registry of supported colorschemes.
--
-- Entries should include the colorscheme name used with:
--   :colorscheme <name>

return {
    tokyo_night = {
        key = "tokyo_night",
        label = "Tokyo Night",
        scheme = "tokyonight-night",
        plugin = "folke/tokyonight.nvim",
    },

    catppuccin = {
        key = "catppuccin",
        label = "Catppuccin (Mocha)",
        scheme = "catppuccin-mocha",
        plugin = "catppuccin/nvim",
    },
}
