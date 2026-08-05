-- main/lazy.lua
--
-- Repo-owned plugin installation + configuration loader.
--
-- This intentionally uses Neovim's built-in `vim.pack.add` for deterministic
-- startup behavior in headless CI/smoke environments.

local function spec_repo(spec)
    if type(spec) == "string" then
        return spec
    end
    if type(spec) ~= "table" then
        return nil
    end

    -- Lazy.nvim-style: { "owner/name", ... }
    if type(spec[1]) == "string" then
        return spec[1]
    end

    -- Alternative fields for future flexibility.
    if type(spec.repo) == "string" then
        return spec.repo
    end
    if type(spec.src) == "string" then
        return spec.src
    end

    return nil
end

local function repo_to_src(repo)
    if repo:match("^https?://") then
        return repo
    end
    return "https://github.com/" .. repo
end

local specs = require("main.plugins")

local pack_plugins = {}
local pack_opt_names = {}
local seen = {}

local function add_pack_repo(repo)
    local src = repo_to_src(repo)
    if seen[src] then
        return
    end
    seen[src] = true

    table.insert(pack_plugins, { src = src })

    -- Directory name under `pack/*/opt/` is the repo name suffix.
    local name = repo:match("[^/]+$")
    if name then
        table.insert(pack_opt_names, name)
    end
end

local function dep_repo(dep)
    if type(dep) == "string" then
        return dep
    end
    if type(dep) ~= "table" then
        return nil
    end

    -- Lazy.nvim-style: { "owner/name", ... }
    if type(dep[1]) == "string" then
        return dep[1]
    end

    if type(dep.repo) == "string" then
        return dep.repo
    end
    if type(dep.src) == "string" then
        return dep.src
    end

    return nil
end

for _, spec in ipairs(specs) do
    local repo = spec_repo(spec)
    if repo then
        add_pack_repo(repo)
    end

    if type(spec) == "table" and type(spec.dependencies) == "table" then
        for _, dep in ipairs(spec.dependencies) do
            local depRef = dep_repo(dep)
            if depRef then
                add_pack_repo(depRef)
            end
        end
    end
end

vim.pack.add(pack_plugins, {
    confirm = false,
    load = true,
})

-- Best-effort: ensure runtimepath is populated even if the `load=true`
-- behavior changes across Neovim versions.
for _, name in ipairs(pack_opt_names) do
    pcall(vim.cmd, "packadd! " .. name)
end

for _, spec in ipairs(specs) do
    if type(spec) == "table" and type(spec.config) == "function" then
        spec.config()
    end
end
