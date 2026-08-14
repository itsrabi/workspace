return {
    "stevearc/conform.nvim",
    config = function()
        local ok, conform = pcall(require, "conform")
        if not ok then
            return
        end

        conform.setup({
            default_format_opts = {
                lsp_format = "fallback",
            },
            formatters_by_ft = {},
        })

        vim.api.nvim_create_user_command(
            "Format",
            function(args)
                local ok_c, conform_mod = pcall(require, "conform")
                if not ok_c then
                    vim.notify(
                        "conform.nvim is not available",
                        vim.log.levels.ERROR
                    )
                    return
                end

                local range = nil
                if args.count ~= -1 then
                    local end_line = vim.api.nvim_buf_get_lines(
                        0,
                        args.line2 - 1,
                        args.line2,
                        true
                    )[1]

                    range = {
                        start = { args.line1, 0 },
                        ["end"] = { args.line2, end_line:len() },
                    }
                end

                conform_mod.format({
                    async = true,
                    lsp_format = "fallback",
                    range = range,
                })
            end,
            {
                desc = "Format file/selection with conform.nvim",
                range = true,
            }
        )
    end,
}
