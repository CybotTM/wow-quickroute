-------------------------------------------------------------------------------
-- test_forever_save_reminder.lua
-- Runs only with QR_TEST_FLAVOR=forever: the save reminder on the Forever
-- client. Same cases as test_save_reminder.lua, from reminder_cases.lua.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "reminder_cases.lua"))(T, QR, MockWoW, "forever")
