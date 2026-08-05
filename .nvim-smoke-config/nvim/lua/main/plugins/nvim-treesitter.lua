return {
    "nvim-treesitter/nvim-treesitter",
    config = function()
        local ok, configs = pcall(require, "nvim-treesitter.configs")
        if not ok then
            return
        end

        configs.setup({
            ensure_installed = {
                "lua",
                "vim",
                "python",
                "bash",
                "markdown",
                "markdown_inline",
                "json",
            },
            auto_install = true,
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false,
            },
        })
    end,
}
