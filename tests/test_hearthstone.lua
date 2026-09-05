local T, QR = ...

local function isolated(body)
    local saved = {}
    local function replace(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local ok, err = pcall(body, replace)
    for i = #saved, 1, -1 do
        local item = saved[i]
        item[1][item[2]] = item[3]
    end
    if not ok then error(err) end
end

local function setup(replace)
    replace(QR.db, "hearthstoneBinds", {})
    replace(_G, "UnitGUID", function() return "Player-1-A" end)
    replace(_G, "GetBindLocation", function() return "Lion's Pride Inn" end)
    replace(C_Map, "GetBestMapForUnit", function() return 37 end)
    replace(C_Map, "GetPlayerMapPosition", function()
        return { GetXY = function() return 0.43, 0.65 end }
    end)
    replace(QR.PathCalculator, "graphDirty", false)
end

T:run("Hearthstone: only an observed bind creates a destination", function(t)
    isolated(function(replace)
        setup(replace)
        t:assertNil(QR.Hearthstone:GetDestination(), "Current zone does not guess the hearth destination")
        t:assertTrue(QR.Hearthstone:RecordBind(), "Bind event records valid player location")
        local destination = QR.Hearthstone:GetDestination()
        t:assertNotNil(destination, "Observed bind becomes routable")
        t:assertEqual(37, destination.mapID, "Bind retains observed map")
        t:assertEqual(0.43, destination.x, "Bind retains observed X")
        t:assertTrue(QR.PathCalculator.graphDirty, "Bind changes invalidate the routing graph")
    end)
end)

T:run("Hearthstone: a city-named inn cannot relocate the existing city node", function(t)
    isolated(function(replace)
        setup(replace)
        replace(_G, "GetBindLocation", function() return "Stormwind City" end)
        QR.Hearthstone:RecordBind()
        local graph = QR.Graph:New()
        graph:AddNode("Stormwind City", { mapID = 84, x = 0.4965, y = 0.8725 })
        replace(QR.PathCalculator, "graph", graph)
        replace(QR.PlayerInventory, "GetAllTeleports", function()
            return { [6948] = { sourceType = "item", data = QR.TeleportItemsData[6948] } }
        end)
        replace(QR.db, "maxCooldownHours", 24)
        QR.PathCalculator:AddPlayerTeleportEdges()
        for target, edge in pairs(graph.edges["Player Location"] or {}) do
            if edge.edgeType == "teleport" then
                t:assert(target ~= "Stormwind City", "Hearth has its own destination node")
                t:assertEqual(37, graph.nodes[target].mapID, "Graph landing matches observed bind map")
                t:assertEqual(0.43, graph.nodes[target].x, "Graph landing matches observed bind X")
            end
        end
        t:assertEqual(84, graph.nodes["Stormwind City"].mapID, "Existing city remains unchanged")
    end)
end)

T:run("Hearthstone: bind is character scoped and current-name checked", function(t)
    isolated(function(replace)
        setup(replace)
        QR.Hearthstone:RecordBind()
        replace(_G, "UnitGUID", function() return "Player-1-B" end)
        t:assertNil(QR.Hearthstone:GetDestination(), "Another character cannot inherit the bind")
        replace(_G, "UnitGUID", function() return "Player-1-A" end)
        replace(_G, "GetBindLocation", function() return "Different Inn" end)
        t:assertNil(QR.Hearthstone:GetDestination(), "A changed bind name invalidates the remembered point")
    end)
end)

T:run("Hearthstone: failed new bind clears stale coordinates", function(t)
    isolated(function(replace)
        setup(replace)
        QR.Hearthstone:RecordBind()
        replace(C_Map, "GetPlayerMapPosition", function() return nil end)
        t:assertFalse(QR.Hearthstone:RecordBind(), "Missing coordinates do not invent a bind position")
        t:assertNil(QR.Hearthstone:GetDestination(), "An old same-name bind cannot survive a failed observation")
    end)
end)

T:run("Hearthstone: resolving preserves actual item or spell identity", function(t)
    isolated(function(replace)
        setup(replace)
        QR.Hearthstone:RecordBind()
        for _, kind in ipairs({ QR.TeleportTypes.ITEM, QR.TeleportTypes.TOY, QR.TeleportTypes.SPELL }) do
            local original = { isDynamic = true, destination = "Bound Location", type = kind, name = "Ability" }
            local data = QR.Hearthstone:ResolveTeleport(original)
            t:assertEqual(kind, data.type, "Resolved transport preserves original source kind")
            t:assertEqual(37, data.mapID, "Bound variants share observed destination")
            t:assertTrue(original.isDynamic, "Static data is not mutated")
            t:assertNil(original.mapID, "Original dynamic coordinates remain untouched")
        end
        local garrison = { isDynamic = true, destination = "Garrison" }
        t:assertEqual(garrison, QR.Hearthstone:ResolveTeleport(garrison), "Garrison is not mapped to a normal inn")
    end)
end)

T:run("Hearthstone: normal hearth becomes a real graph option", function(t)
    isolated(function(replace)
        setup(replace)
        QR.Hearthstone:RecordBind()
        replace(QR.PathCalculator, "graph", QR.Graph:New())
        replace(QR.PlayerInventory, "GetAllTeleports", function()
            return { [6948] = { sourceType = "item", data = QR.TeleportItemsData[6948] } }
        end)
        replace(QR.db, "maxCooldownHours", 24)
        QR.PathCalculator:AddPlayerTeleportEdges()
        local found
        for _, edge in pairs(QR.PathCalculator.graph.edges["Player Location"] or {}) do
            if edge.edgeType == "teleport" and edge.data.teleportID == 6948 then found = edge end
        end
        t:assertNotNil(found, "Owned normal hearthstone is offered by the planner")
        if found then
            t:assertEqual("item", found.data.sourceType, "Use action retains item identity")
            t:assertEqual(37, found.data.teleportData.mapID, "Route goes to observed bind map")
        end
    end)
end)
