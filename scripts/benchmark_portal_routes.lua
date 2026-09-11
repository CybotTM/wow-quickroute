-- Full CalculatePath sweep for the portal-return regressions (#21/#40).
-- Usage: lua5.1 scripts/benchmark_portal_routes.lua [checkout-root]
-- Fixture character has no personal teleports; durations are model estimates.
local root = arg[1] or "."
package.path = root .. "/tests/?.lua;" .. package.path
local mock = require("mock_wow_api")
mock:Install()
_G.IsFlying = function() return false end
_G.IsMounted = function() return false end
_G.IsIndoors = function() return false end
_G.IsAdvancedFlyableArea = function() return false end
_G.GetUnitSpeed = function() return 0, 7, 0, 0 end
_G.C_MountJournal = { GetMountIDs = function() return {} end }
local loader = require("addon_loader")
local QR = loader:Load(mock, { addonDir = root .. "/QuickRoute/", quiet = true })
if not loader:AllFilesLoaded() then error(loader:GetStatus()) end
local output = print
_G.print = function() end
loader:InitializeAddon(mock)
_G.print = output
local pc = QR.PathCalculator
QR.PlayerInventory.GetAllTeleports = function() return {} end
C_QuestLog.IsQuestFlaggedCompleted = function() return true end
C_Map.GetMapArtID = function(mapID)
    if mapID == 390 then return 402 elseif mapID == 1530 then return 1342 end
end
local discovery = "none"
_G.C_TaxiMap = { GetTaxiNodesForMap = function(mapID)
    local result = {}
    if discovery ~= "all" then return result end
    local p = pc:FlightPointFor(mapID)
    if p then result[#result + 1] = { nodeID = p.node, position = { x = p.x, y = p.y }, faction = 0, isUndiscovered = false } end
    for id, node in pairs(QR.TravelTransitions.nodes) do
        if node.mapID == mapID and (node.taxiNodeID or id:match("FLIGHT")) then
            result[#result + 1] = { nodeID = node.taxiNodeID, position = { x = node.x, y = node.y }, faction = 0, isUndiscovered = false }
        end
    end
    return result
end }
print("case\tfaction\tdiscovery\tfrom\tto\tseconds\tsteps")
local function check(case, faction, from, to, x, y, tx, ty)
    mock.config.currentMapID = from
    mock.config.playerX, mock.config.playerY = x or .5, y or .5
    pc.graphDirty = true
    local route = pc:CalculatePath(to, tx or .5, ty or .5)
    local steps = {}
    for _, step in ipairs(route and route.steps or {}) do
        steps[#steps + 1] = step.type .. ":" .. step.from .. ">" .. step.to
    end
    print(table.concat({case, faction, discovery, from, to,
        route and string.format("%.3f", route.totalTime) or "unreachable", table.concat(steps, " | ")}, "\t"))
end
for _, faction in ipairs({"Alliance", "Horde"}) do
    mock:Reset()
    mock.config.playerFaction = faction
    mock.config.playerClass = "WARRIOR"
    mock.config.isFlyableArea = false
    QR.PlayerInfo:InvalidateCache()
    QR.TravelTime:ClearMovementCache()
    for _, status in ipairs({"none", "all"}) do
        discovery = status
        for _, continent in ipairs({"PANDARIA", "DRAENOR"}) do
            for _, mapID in ipairs(QR.Continents[continent].zones) do
                check("issue21", faction, mapID, faction == "Alliance" and 84 or 85)
            end
        end
        for _, key in ipairs({"ASPIRANTS_REST_FLIGHT", "THEATER_OF_PAIN_FLIGHT", "TIRNA_VAAL_FLIGHT", "PRIDEFALL_HAMLET_FLIGHT"}) do
            local point = QR.TravelTransitions.nodes[key]
            local oribos = QR.TravelTransitions.nodes.ORIBOS_FLIGHT
            check("issue40", faction, point.mapID, oribos.mapID, point.x, point.y, oribos.x, oribos.y)
            check("issue40", faction, oribos.mapID, point.mapID, oribos.x, oribos.y, point.x, point.y)
        end
    end
end
