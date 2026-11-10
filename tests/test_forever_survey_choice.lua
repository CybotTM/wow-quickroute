-------------------------------------------------------------------------------
-- test_forever_survey_choice.lua
-- Runs only with QR_TEST_FLAVOR=forever: the zone survey's default and the
-- player's choice on the Forever client. Same cases as test_survey_choice.lua,
-- from survey_choice_cases.lua.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "survey_choice_cases.lua"))(T, QR, MockWoW, "forever")
