return {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
    },
    config = function()
        local ok, render_markdown = pcall(require, "render-markdown")
        if not ok then
            return
        end

        render_markdown.setup({})
    end,
}
