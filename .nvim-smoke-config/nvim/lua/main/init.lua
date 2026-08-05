-- main/init.lua
--
-- Imports the core config and the plugin loader.

require("main.core")
require("main.lazy")

-- Apply theme after plugins are installed/available.
require("main.core.theme")
