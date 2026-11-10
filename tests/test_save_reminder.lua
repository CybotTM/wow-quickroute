-------------------------------------------------------------------------------
-- test_save_reminder.lua
-- The save reminder on the retail client. The cases live in reminder_cases.lua
-- and run on Forever too (test_forever_save_reminder.lua).
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "reminder_cases.lua"))(T, QR, MockWoW, "retail")
