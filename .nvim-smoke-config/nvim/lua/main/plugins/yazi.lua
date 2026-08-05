return {
    "mikavilpas/yazi.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    config = function()
        local ok, yazi = pcall(require, "yazi")
        if not ok then
            return
        end

        yazi.setup({
            open_file_function = function(chosen_file, _, _)
                if vim.fn.isdirectory(chosen_file) == 1 then
                    pcall(
                        vim.cmd,
                        "Oil " .. vim.fn.fnameescape(chosen_file)
                    )
                else
                    pcall(
                        vim.cmd,
                        "edit " .. vim.fn.fnameescape(chosen_file)
                    )
                end
            end,
        })
    end,
}
