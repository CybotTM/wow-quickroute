local T, QR = ...

local MICRO, PARENT, REMOTE = 800001, 800002, 800003

local function withOrigin(body)
    local changes = {}
    local function set(tbl, key, value)
        changes[#changes + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local state = { mapID = MICRO, position = true, projection = true, x = 0.2, y = 0.3 }
    local function vector(x, y)
        return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
    end
    set(C_Map, "GetBestMapForUnit", function() return state.mapID end)
    set(C_Map, "GetPlayerMapPosition", function()
        if state.position then return vector(state.x, state.y) end
    end)
    set(C_Map, "GetMapInfo", function(mapID)
        return { mapID = mapID, name = "Projection fixture " .. tostring(mapID),
            mapType = mapID == MICRO and 5 or 3, parentMapID = mapID == MICRO and PARENT or 0 }
    end)
    set(C_Map, "GetMapInfoAtPosition", function() return nil end)
    set(C_Map, "GetWorldPosFromMapPos", function(_, position) return 1, position end)
    set(C_Map, "GetMapPosFromWorldPos", function(_, _, target)
        if state.projection then return target, vector(0.6, 0.7) end
    end)
    set(C_Map, "GetMapWorldSize", function() return 1000, 1000 end)
    set(_G, "CreateVector2D", vector)
    set(_G, "IsMounted", function() return true end)
    set(_G, "IsFlying", function() return true end)
    set(_G, "IsFlyableArea", function() return true end)
    set(_G, "IsAdvancedFlyableArea", function() return true end)
    set(_G, "IsIndoors", function() return false end)
    set(_G, "GetUnitSpeed", function() return 80, 7, 28.7 end)
    set(_G, "C_PlayerInfo", { GetGlidingInfo = function() return true, true, 80 end })
    set(QR.PlayerInventory, "GetAllTeleports", function() return {} end)
    QR.TravelTime:ClearMovementCache()
    QR.TravelTime:ClearMapScaleCache()
    local ok, err = pcall(body, state, set)
    for index = #changes, 1, -1 do
        local change = changes[index]
        change[1][change[2]] = change[3]
    end
    QR.TravelTime:ClearMovementCache()
    QR.TravelTime:ClearMapScaleCache()
    if not ok then error(err) end
end

local function newCalculator()
    return setmetatable({ graph = QR.Graph:New(), graphDirty = false,
        zoneTravelGraph = QR.Graph:New(), zoneTravelCache = {} }, { __index = function(_, key)
            local value = QR.PathCalculator[key]
            if type(value) == "function" then return value end
        end })
end

T:run("Player origin: initial node and movement use verified parent coordinates", function(t)
    withOrigin(function(state)
        local calculator = newCalculator()
        calculator:AddPlayerTeleportEdges()
        local player = calculator.graph.nodes["Player Location"]
        t:assertEqual(PARENT, player.mapID, "The initial player node uses the verified parent map")
        t:assertEqual(0.6, player.x, "The initial X coordinate is transformed, not relabeled")
        t:assertEqual(0.7, player.y, "The initial Y coordinate is transformed, not relabeled")
        local route = calculator:CalculatePath(PARENT, 0.8, 0.7)
        t:assertNotNil(route, "A microzone origin reaches a destination on its verified parent")
        if route then
            t:assertEqual("walk", route.steps[1].type, "Continuous movement is available without inventing a teleport")
            t:assertEqual(3, route.totalTime, "Two hundred yards retains the actual 80-yard-per-second flight speed")
        end
        state.mapID, state.x, state.y = PARENT, 0.6, 0.7
        t:assertNotNil(calculator:CalculatePath(PARENT, 0.8, 0.7), "Leaving the microzone preserves route availability")
        state.mapID, state.x, state.y = MICRO, 0.2, 0.3
        t:assertNotNil(calculator:CalculatePath(PARENT, 0.8, 0.7), "Re-entering the microzone preserves route availability")
        t:assertEqual(PARENT, player.mapID, "Movement updates continue to normalize the player map")
        t:assertEqual(0.6, player.x, "Movement updates continue to transform the coordinate")
    end)
end)

T:run("Player origin: unavailable projection preserves the original coordinate space", function(t)
    withOrigin(function(state)
        state.projection = false
        local calculator = newCalculator()
        calculator:AddPlayerTeleportEdges()
        local player = calculator.graph.nodes["Player Location"]
        t:assertEqual(MICRO, player.mapID, "An unavailable transform preserves the original map")
        t:assertEqual(0.2, player.x, "An unavailable transform preserves the original X coordinate")
        t:assertEqual(0.3, player.y, "An unavailable transform preserves the original Y coordinate")
        t:assertNil(calculator:CalculatePath(PARENT, 0.8, 0.7), "No route is fabricated by attaching raw coordinates to the parent")
        state.projection = true
        t:assertNotNil(calculator:CalculatePath(PARENT, 0.8, 0.7), "The next query recovers when the client supplies the transform")
    end)
end)

T:run("Player origin: unavailable or invalid positions cannot create midpoint nodes", function(t)
    withOrigin(function(state)
        local calculator = newCalculator()
        state.position = false
        calculator:AddPlayerTeleportEdges()
        t:assertNil(calculator.graph.nodes["Player Location"], "No initial player location is guessed while the position API is unavailable")
        state.position = true
        state.x = 0 / 0
        calculator:AddPlayerTeleportEdges()
        t:assertNil(calculator.graph.nodes["Player Location"], "Invalid initial coordinates cannot create a player node")
        state.x = 0.2
        calculator:AddPlayerTeleportEdges()
        local player = calculator.graph.nodes["Player Location"]
        state.position = false
        t:assertFalse(calculator:UpdatePlayerLocation(), "Temporary position loss reports an unavailable origin")
        t:assertEqual(0.6, player.x, "Temporary position loss does not overwrite the last verified coordinate")
        state.position = true
        t:assertTrue(calculator:UpdatePlayerLocation(), "Position recovery restores ordinary routing")
    end)
end)

T:run("Player origin: flight permission follows the verified current map only", function(t)
    withOrigin(function(state, set)
        t:assertEqual(80, QR.TravelTime:GetMovementSpeed(PARENT, true), "Projected current parent uses live gliding speed")
        t:assert(QR.TravelTime:GetMovementSpeed(REMOTE, true) < 80, "An unrelated remote map does not inherit gliding speed")
        set(_G, "IsIndoors", function() return true end)
        QR.TravelTime:ClearMovementCache()
        t:assertEqual(7, QR.TravelTime:GetMovementSpeed(PARENT, true), "Projection never bypasses the current indoor flight restriction")
        set(_G, "IsIndoors", function() return false end)
        state.projection = false
        QR.TravelTime:ClearMovementCache()
        t:assert(QR.TravelTime:GetMovementSpeed(PARENT, true) < 80, "An unverified parent does not inherit gliding speed")
        t:assertEqual(80, QR.TravelTime:GetMovementSpeed(MICRO, true), "The valid raw microzone still uses live flight speed")
    end)
end)
