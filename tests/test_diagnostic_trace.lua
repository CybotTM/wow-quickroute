-------------------------------------------------------------------------------
-- test_diagnostic_trace.lua
-- The diagnostic trace on the retail client. The cases live in
-- trace_cases.lua and run on Forever too (test_forever_diagnostic_trace.lua).
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
assert(loadfile(dir .. "trace_cases.lua"))(T, QR, MockWoW, "retail")
