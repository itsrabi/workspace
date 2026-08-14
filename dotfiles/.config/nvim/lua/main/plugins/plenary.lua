-- main/plugins/plenary.lua

return {
    "nvim-lua/plenary.nvim",
    config = function()
        -- Plenary provides shared Lua utilities used by other plugins.
        -- Requiring `plenary.path` eagerly ensures the module is available.
        require("plenary.path")
    end,
}
