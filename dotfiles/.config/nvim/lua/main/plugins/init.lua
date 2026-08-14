-- main/plugins/init.lua
--
-- Auto-discover plugin spec modules.
--
-- Convention: each *.lua file in this directory (except ignored helpers)
-- should `return` a Lazy.nvim-style plugin spec OR a list of specs.

local specs = {}

-- Where Neovim installed this repo-owned config (for example $HOME/.config/nvim).
local plugin_dir = vim.fn.stdpath("config") .. "/lua/main/plugins"

-- Ignore non-plugin-spec helpers.
local ignore = {
    colorschemes = true,
}

-- globpath(..., ..., nosuf, list) -> list of full paths
local files = vim.fn.globpath(plugin_dir, "*.lua", false, true)
table.sort(files)

for _, file in ipairs(files) do
    local mod = vim.fn.fnamemodify(file, ":t:r")
    if mod and mod ~= "init" and not ignore[mod] then
        local ok, spec = pcall(require, "main.plugins." .. mod)
        if ok and spec ~= nil then
            -- specs may be a single spec table or a list of spec tables.
            -- Heuristic: list-of-specs have spec[1] as a table; single specs have spec[1] as repo string.
            if type(spec) == "table" and type(spec[1]) == "table" then
                vim.list_extend(specs, spec)
            else
                table.insert(specs, spec)
            end
        end
    end
end

return specs
