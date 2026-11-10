-------------------------------------------------------------------------------
-- test_forever_diagnostic_trace.lua
-- Runs only with QR_TEST_FLAVOR=forever: the diagnostic trace on the Forever
-- client. Same cases as test_diagnostic_trace.lua, from trace_cases.lua.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "trace_cases.lua"))(T, QR, MockWoW, "forever")
