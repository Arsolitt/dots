--  _   _                  _                 _
-- | | | |_   _ _ __  _ __| | __ _ _ __   __| |
-- | |_| | | | | '_ \| '__| |/ _` | '_ \ / _` |
-- |  _  | |_| | |_) | |  | | (_| | | | | (_| |
-- |_| |_|\__, | .__/|_|  |_|\__,_|_| |_|\__,_|
--        |___/|_|
--
-- -----------------------------------------------------

-- DMI chassis types 8/9/10/14 = portable (laptop, notebook, convertible);
-- anything else (this desktop reports 3) loads the desktop module.
local function is_laptop()
    local f = io.open("/sys/class/dmi/id/chassis_type")
    if not f then
        return false
    end
    local t = tonumber(f:read("*l"))
    f:close()
    return t == 8 or t == 9 or t == 10 or t == 14
end

require("conf/windowrules")
require("conf/keyboard")
require("conf/windows")
require("conf/layouts")
require("conf/decorations")
require("conf/misc")
require("conf/binds")
require("conf/environment")
require("conf/autostart")

if is_laptop() then
    require("conf/laptop")
else
    require("conf/desktop")
end
