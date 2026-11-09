-------------------------------------------------------------------------------
-- test_subzone_origin.lua
-- A sub-zone the routing model does not know is resolved onto its parent zone.
--
-- A 12.1.5 zone survey saw the player walk into 34 such maps -- Der Düsterweg
-- (2525) and Murder Row (2433) in Silvermoon, Kriegval's Rest (2250) on the
-- Isle of Dorn, phased copies of Silvermoon (2605) and Eversong (2594). Standing
-- on one, the player node had no overland edge: the route to the Silvermoon
-- portal room from Der Düsterweg was hearthstone to Dalaran, portal to
-- Stormwind, portal to Silvermoon, and with no teleport there was no route.
-------------------------------------------------------------------------------

local T, QR = ...

local SILVERMOON, DUESTERWEG = 2393, 2525    -- parent zone, unknown sub-zone
local ZULAMAN, ATALAMAN = 2437, 2536         -- a sub-zone the model knows
local QUELTHALAS, ARCANTINA = 2537, 2541     -- type 4 under a continent
local DUNGEON = 2308                         -- own world space, no projection

local MAPS = {
    [SILVERMOON] = { mapType = 3, parentMapID = 2395 },
    [DUESTERWEG] = { mapType = 4, parentMapID = SILVERMOON },
    [ZULAMAN] = { mapType = 3, parentMapID = QUELTHALAS },
    [ATALAMAN] = { mapType = 3, parentMapID = ZULAMAN },
    [QUELTHALAS] = { mapType = 2, parentMapID = 13 },
    [ARCANTINA] = { mapType = 4, parentMapID = QUELTHALAS },
    [DUNGEON] = { mapType = 4, parentMapID = 2215 },
    [2215] = { mapType = 3, parentMapID = 2274 },
}

local function withMaps(body)
    local changes = {}
    local function set(tbl, key, value)
        changes[#changes + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local state = { mapID = DUESTERWEG, x = 0.2, y = 0.3 }
    local function vector(x, y)
        return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
    end
    set(C_Map, "GetBestMapForUnit", function() return state.mapID end)
    set(C_Map, "GetPlayerMapPosition", function() return vector(state.x, state.y) end)
    set(C_Map, "GetMapInfo", function(mapID)
        local info = MAPS[mapID]
        if not info then return nil end
        return { mapID = mapID, name = "Fixture " .. mapID, mapType = info.mapType,
            parentMapID = info.parentMapID }
    end)
    set(C_Map, "GetMapInfoAtPosition", function() return nil end)
    -- World space 1 holds the open world; the dungeon has none the client can
    -- project into its parent, which is what keeps it on its own map.
    set(C_Map, "GetWorldPosFromMapPos", function(mapID, position)
        if mapID == DUNGEON then return nil end
        return 1, position
    end)
    set(C_Map, "GetMapPosFromWorldPos", function(_, _, target) return target, vector(0.6, 0.7) end)
    set(_G, "CreateVector2D", vector)
    set(QR.PlayerInventory, "GetAllTeleports", function() return {} end)
    local ok, err = pcall(body, state)
    for index = #changes, 1, -1 do
        local change = changes[index]
        change[1][change[2]] = change[3]
    end
    if not ok then error(err) end
end

local function newCalculator()
    return setmetatable({ graph = QR.Graph:New(), graphDirty = false,
        zoneTravelGraph = QR.Graph:New(), zoneTravelCache = {} }, { __index = function(_, key)
            local value = QR.PathCalculator[key]
            if type(value) == "function" then return value end
        end })
end

T:run("Sub-zone origin: an unknown sub-zone resolves onto its parent zone", function(t)
    withMaps(function()
        local mapID, x, y = newCalculator():ResolveMapPosition(DUESTERWEG, 0.2, 0.3)
        t:assertEqual(SILVERMOON, mapID, "Der Düsterweg resolves to Silvermoon, got " .. tostring(mapID))
        t:assertEqual(0.6, x, "the x coordinate is transformed, got " .. tostring(x))
        t:assertEqual(0.7, y, "the y coordinate is transformed, got " .. tostring(y))
    end)
end)

T:run("Sub-zone origin: the player in an unknown sub-zone walks to its parent", function(t)
    withMaps(function()
        local calculator = newCalculator()
        calculator:AddPlayerTeleportEdges()
        local player = calculator.graph.nodes["Player Location"]
        t:assertEqual(SILVERMOON, player and player.mapID,
            "the player node sits on Silvermoon, got " .. tostring(player and player.mapID))
        local route = calculator:CalculatePath(SILVERMOON, 0.5641, 0.7077)
        t:assertNotNil(route, "a route to the Silvermoon portal room exists without any teleport")
        if route then
            t:assertEqual("walk", route.steps[1].type,
                "and it starts on foot, got " .. tostring(route.steps[1].type))
        end
    end)
end)

T:run("Sub-zone origin: maps the model knows keep their own map", function(t)
    withMaps(function()
        local calculator = newCalculator()
        local mapID = calculator:ResolveMapPosition(ATALAMAN, 0.2, 0.3)
        t:assertEqual(ATALAMAN, mapID, "Atal'Aman has overland links and stays, got " .. tostring(mapID))
        mapID = calculator:ResolveMapPosition(ARCANTINA, 0.2, 0.3)
        t:assertEqual(ARCANTINA, mapID,
            "the Arcantina's parent is a continent, so it stays, got " .. tostring(mapID))
        mapID = calculator:ResolveMapPosition(DUNGEON, 0.2, 0.3)
        t:assertEqual(DUNGEON, mapID,
            "a dungeon the client cannot project stays, got " .. tostring(mapID))
    end)
end)

T:run("Sub-zone origin: a sub-zone with graph nodes of its own stays", function(t)
    withMaps(function()
        local calculator = newCalculator()
        calculator.graph:AddNode("Fixture node", { mapID = DUESTERWEG, x = 0.5, y = 0.5 })
        local mapID = calculator:ResolveMapPosition(DUESTERWEG, 0.2, 0.3)
        t:assertEqual(DUESTERWEG, mapID,
            "a node on the sub-zone makes it routable, got " .. tostring(mapID))
    end)
end)
