-- main/plugins/harpoon.lua

return {
    "ThePrimeagen/harpoon",
    config = function()
        local harpoon = require("harpoon")

        -- Headless Neovim smoke runs trigger VimLeave autocmds.
        -- Harpoon's default `save_on_change = true` can attempt to JSON-encode
        -- non-serializable function references during that exit path.
        --
        -- Disabling saving avoids that failure mode while keeping the UI usable.
        harpoon.setup({
            global_settings = {
                save_on_change = false,
                save_on_toggle = false,
            },
        })
    end,
}
