-- main/core/theme.lua

local themes = require("main.plugins.colorschemes")

-- Choose with:
--   :lua vim.g.ompi_theme = "tokyo_night"  (example)
-- Defaults to tokyo night.
local desired_key = vim.g.ompi_theme or "tokyo_night"
local theme = themes[desired_key] or themes.tokyo_night

-- Best-effort: theme plugins may still be initializing during startup.
local ok, err = pcall(vim.cmd, "colorscheme " .. theme.scheme)
if not ok then
    vim.schedule(function()
        pcall(vim.cmd, "colorscheme " .. theme.scheme)
    end)

    vim.notify(
        string.format(
            "Theme load failed (%s -> %s): %s",
            tostring(desired_key),
            tostring(theme.scheme),
            tostring(err)
        ),
        vim.log.levels.WARN
    )
end
