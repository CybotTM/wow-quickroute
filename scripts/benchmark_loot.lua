-- Compare graph rebuilds caused by ordinary loot. Standalone Lua, not native RAM/FPS.
-- Run from repo root: lua5.1 scripts/benchmark_loot.lua [addon-directory/]
-- GC is paused for allocation attribution and restarted after the sample.
package.path = "tests/?.lua;" .. package.path
local Mock = require("mock_wow_api")
Mock:Install()
local QR = {}
local root = arg[1] or "QuickRoute/"
for line in io.lines(root .. "QuickRoute.toc") do
    line = line:gsub("\r", ""):gsub("\\", "/")
    if line:match("%.lua$") and not line:match("^#") then
        assert(loadfile(root .. line))("QuickRoute", QR)
    end
end
Mock:FireEvent("ADDON_LOADED", "QuickRoute")
Mock:FireEvent("PLAYER_LOGIN")
QR.PlayerInventory:ScanAll()
QR.PathCalculator:CalculatePath(84, .55, .65)
local builds, scans = 0, 0
local build, scan = QR.PathCalculator.BuildGraph, QR.PlayerInventory.ScanAll
QR.PathCalculator.BuildGraph = function(self, ...)
    builds = builds + 1
    return build(self, ...)
end
QR.PlayerInventory.ScanAll = function(self, ...)
    scans = scans + 1
    return scan(self, ...)
end
collectgarbage("collect")
collectgarbage("stop")
local before, started = collectgarbage("count"), os.clock()
for index = 1, 10 do
    Mock.config.bagItems[900001] = { bagID = 0, slot = 1, count = index }
    QR.PlayerInventory.eventFrame:GetScript("OnEvent")(QR.PlayerInventory.eventFrame, "BAG_UPDATE")
    QR.PathCalculator:CalculatePath(84, .55, .65)
end
local allocated, elapsed = collectgarbage("count") - before, os.clock() - started
collectgarbage("collect")
local delta = collectgarbage("count") - before
collectgarbage("restart")
print(string.format("LOOT batches=10 scans=%d graphBuilds=%d allocated=%.1fKiB retainedDelta=%.1fKiB CPU=%.1fms",
    scans, builds, allocated, delta, elapsed * 1000))
