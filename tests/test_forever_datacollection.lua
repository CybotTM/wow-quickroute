-------------------------------------------------------------------------------
-- test_forever_datacollection.lua
-- Runs only with QR_TEST_FLAVOR=forever: the travel observations on the
-- Forever client. Same cases as test_datacollection.lua, from
-- datacollection_cases.lua, with Forever's map IDs.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "datacollection_cases.lua"))(T, QR, MockWoW, "forever")
