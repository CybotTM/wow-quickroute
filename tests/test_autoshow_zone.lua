-------------------------------------------------------------------------------
-- test_autoshow_zone.lua
-- Auto-destination opens the window only for another zone, on the retail
-- client. The cases live in autoshow_cases.lua and run on Forever too
-- (test_forever_autoshow_zone.lua).
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "autoshow_cases.lua"))(T, QR, MockWoW, "retail")
