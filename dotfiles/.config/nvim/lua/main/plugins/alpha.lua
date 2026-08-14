-- alpha.lua
--
-- Alpha provides a customizable startup dashboard for Neovim.
-- It offers quick access to common actions such as opening files,
-- searching text, editing configuration, and quitting.

-- main/plugins/alpha.lua

return {
    "goolord/alpha-nvim",
    lazy = false,
    priority = 1000,

    config = function()
        local ok, alpha = pcall(require, "alpha")
        if not ok then
            return
        end

        local dashboard = require("alpha.themes.dashboard")

        local v = vim.version()
        local version_str = string.format(
            "v%d.%d.%d",
            v.major,
            v.minor,
            v.patch
        )

        dashboard.section.header.val = {
            "",
            "███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗",
            "████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║",
            "██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║",
            "██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║",
            "██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║",
            "╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝",
            "",
            version_str,
            "",
            "────────────────────────────────────────────────────",
        }

        dashboard.section.buttons.val = {
            dashboard.button(
                "f",
                "Find Files",
                "<cmd>lua require('fzf-lua').files()<cr>"
            ),
            dashboard.button(
                "r",
                "Recent Files",
                "<cmd>lua require('fzf-lua').oldfiles()<cr>"
            ),
            dashboard.button(
                "g",
                "Live Grep",
                "<cmd>lua require('fzf-lua').live_grep()<cr>"
            ),
            dashboard.button(
                "h",
                "Health Check",
                "<cmd>checkhealth<cr>"
            ),
            dashboard.button(
                "c",
                "Config",
                "<cmd>edit ~/.config/nvim/init.lua<cr>"
            ),
            dashboard.button(
                "q",
                "Quit",
                "<cmd>qa<cr>"
            ),
        }

        dashboard.section.footer.val = {
            "",
            "────────────────────────────────────────────────────",
        }

        -- Make footer use the same highlight group as the header.
        dashboard.section.footer.opts.hl =
            dashboard.section.header.opts.hl

        alpha.setup(dashboard.config)
    end,
}
