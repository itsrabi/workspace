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
                "vimdoc",
                "python",
                "bash",
                "markdown",
                "markdown_inline",
                "json",
		"yaml",
		"html",
		"javascript",
		"typescript",
		"tsx",
		"css",
		"dockerfile",
            },
            auto_install = true,
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false,
            },
	    indent = { 
	        enable = true, 
	    },
        })
    end,
}
