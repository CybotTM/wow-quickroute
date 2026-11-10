-------------------------------------------------------------------------------
-- test_survey_choice.lua
-- The zone survey's default and the player's choice on the retail client. The
-- cases live in survey_choice_cases.lua and run on Forever too
-- (test_forever_survey_choice.lua).
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "survey_choice_cases.lua"))(T, QR, MockWoW, "retail")
