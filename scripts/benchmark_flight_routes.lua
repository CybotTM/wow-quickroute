-- Reproducible CalculatePath sweep; times are estimates, not client timings.
-- Usage: lua5.1 scripts/benchmark_flight_routes.lua [checkout-root]
-- Run the same script against immutable before/after checkouts and compare TSV.
local root = arg[1] or "."
package.path = root .. "/tests/?.lua;" .. package.path
local mock = require("mock_wow_api")
mock:Install()

-- Movement APIs must describe a real capability state, rather than truthy
-- fallback stubs. This profile is an unmounted character with no flight mount.
_G.IsFlying = function() return false end
_G.IsMounted = function() return false end
_G.IsIndoors = function() return false end
_G.IsAdvancedFlyableArea = function() return false end
_G.GetUnitSpeed = function() return 0, 7, 0, 0 end
_G.C_MountJournal = { GetMountIDs = function() return {} end }
local loader = require("addon_loader")
local QR = loader:Load(mock, { addonDir = root .. "/QuickRoute/", quiet = true })
assert(loader:AllFilesLoaded(), loader:GetStatus())
loader:InitializeAddon(mock)
local pc = QR.PathCalculator
local maps = { 17, 47, 84, 85, 87, 103, 110, 198, 371, 390, 862, 1161,
    1462, 2112, 2214, 2215, 2248, 2255, 2339 }
local regional = { [2214] = true, [2215] = true, [2248] = true,
    [2255] = true, [2339] = true }
local discovered = {}
_G.C_TaxiMap = { GetTaxiNodesForMap = function(mapID)
    local point = pc:FlightPointFor(mapID)
    if not point then return {} end
    return {{ position = { x = point.x, y = point.y },
        isUndiscovered = not discovered[mapID] }}
end }
print("faction\tteleport\tdiscovery\tfrom\tto\tseconds\tflights\tsteps")
for _, faction in ipairs({ "Alliance", "Horde" }) do
    for _, teleport in ipairs({ "none", "ready", "cooldown" }) do
        for _, discovery in ipairs({ "none", "regional", "all" }) do
            mock:Reset()
            mock.config.playerFaction = faction
            mock.config.playerClass = teleport == "none" and "WARRIOR" or "MAGE"
            mock.config.isFlyableArea = false
            mock.config.knownSpells = teleport == "none" and {} or { [446540] = true }
            if teleport == "cooldown" then
                mock.config.spellCooldowns[446540] = {
                    start = mock.config.baseTime, duration = 3600, enable = 1 }
            end
            QR.PlayerInfo:InvalidateCache()
            QR.PlayerInventory:ScanAll()
            discovered = {}
            for mapID in pairs(QR.FlightPoints) do
                if discovery == "all" or (discovery == "regional" and regional[mapID]) then
                    discovered[mapID] = true
                end
            end
            for _, source in ipairs(maps) do
                mock.config.currentMapID = source
                mock.config.playerX, mock.config.playerY = 0.5, 0.5
                QR.TravelTime:ClearMovementCache()
                pc.graphDirty = true
                for _, destination in ipairs(maps) do
                    if source ~= destination then
                        local route = pc:CalculatePath(destination, 0.5, 0.5)
                        assert(not pc.graphDirty, "graph build failed")
                        local flights, steps = 0, {}
                        if route then
                            for _, step in ipairs(route.steps) do
                                if step.type == "flight" then flights = flights + 1 end
                                steps[#steps + 1] = step.type .. ":" .. step.from .. ">" .. step.to
                            end
                        end
                        print(table.concat({ faction, teleport, discovery, source, destination,
                            route and string.format("%.6f", route.totalTime) or "unreachable",
                            flights, table.concat(steps, " | ") }, "\t"))
                    end
                end
            end
        end
    end
end
