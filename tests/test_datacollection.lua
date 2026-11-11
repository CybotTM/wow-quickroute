-------------------------------------------------------------------------------
-- test_datacollection.lua
-- The travel observations (QR.DataCollection) on the retail client. The cases
-- live in datacollection_cases.lua and run on Forever too
-- (test_forever_datacollection.lua).
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "datacollection_cases.lua"))(T, QR, MockWoW, "retail")
