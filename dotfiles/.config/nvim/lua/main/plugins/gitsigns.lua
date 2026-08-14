return {
    "lewis6991/gitsigns.nvim",
    config = function()
        local ok, gitsigns = pcall(require, "gitsigns")
        if not ok then
            return
        end

        gitsigns.setup({})
    end,
}
