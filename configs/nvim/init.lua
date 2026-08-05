-- configs/nvim/init.lua
--
-- Neovim entrypoint for this repository's default configuration.
--
-- Responsibilities:
--   - Set leader keys.
--   - Import the rest of the configuration from `lua/main/*`.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("main")
