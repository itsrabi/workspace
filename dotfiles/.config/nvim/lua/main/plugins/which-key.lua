return {
    "folke/which-key.nvim",
    config = function()
        local ok, which_key = pcall(require, "which-key")
        if not ok then
            return
        end

        vim.o.timeout = true
        vim.o.timeoutlen = 300

        which_key.setup({
            win = {
                border = "single",
            },
        })
    end,
}
