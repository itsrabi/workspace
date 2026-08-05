-- main/plugins/web-devicons.lua

return {
    "nvim-tree/nvim-web-devicons",
    config = function()
        -- Some plugins optionally use icons; require eagerly to surface errors early.
        require("nvim-web-devicons")
    end,
}
