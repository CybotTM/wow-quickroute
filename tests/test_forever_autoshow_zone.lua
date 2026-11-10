-------------------------------------------------------------------------------
-- test_forever_autoshow_zone.lua
-- Runs only with QR_TEST_FLAVOR=forever: auto-destination opens the window only
-- for another zone, on the Forever client. Same cases as
-- test_autoshow_zone.lua, from autoshow_cases.lua.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "autoshow_cases.lua"))(T, QR, MockWoW, "forever")
