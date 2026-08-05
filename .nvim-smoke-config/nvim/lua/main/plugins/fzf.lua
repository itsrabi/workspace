-- main/plugins/fzf.lua

return {
    "ibhagwan/fzf-lua",
    config = function()
        local fzf = require("fzf-lua")

        fzf.setup({
            files = {
                hidden = true,
                follow = true,
                no_ignore = false,
            },
            grep = {
                hidden = true,
            },
        })
    end,
}
