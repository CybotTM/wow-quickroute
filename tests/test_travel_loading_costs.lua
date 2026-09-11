local T, QR, MockWoW = ...

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

T:run("Loading costs: ordinary and dungeon teleports include one configured load and one cooldown", function(t)
    isolated(function(replace)
        replace(QR, "db", { loadingScreenTime = 11, considerCooldowns = true })
        local id = 999921
        local data = { type = "spell", name = "Loading destination", destination = "Loading destination",
            mapID = 2339, x = 0.5, y = 0.5, faction = "both", journalInstanceID = 1201 }
        replace(QR.TravelTime, "castTimeBySpell", {})
        replace(C_Spell, "GetSpellInfo", function() return { castTime = 7000 } end)
        replace(MockWoW.config, "spellCooldowns", {})
        replace(QR.PlayerInventory, "GetAllTeleports", function()
            return { [id] = { data = data, sourceType = "spell", isUsable = true } }
        end)
        local graph = QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
        graph:AddNode("Dungeon loading destination", { mapID = 2339, x = 0.5, y = 0.5,
            isDungeon = true, journalInstanceID = 1201 })
        local pc = QR.PathCalculator
        replace(pc, "graph", graph)
        pc:AddPlayerTeleportEdges()
        pc:AddDungeonTeleportEdges()
        for _, target in ipairs({ "Loading destination", "Dungeon loading destination" }) do
            local edge = graph:GetEdge("Player Location", target)
            t:assertNotNil(edge, target .. " has a usable teleport")
            if edge then t:assertEqual(18, edge.weight, target .. " costs seven-second cast plus eleven-second load") end
        end
        t:assertEqual(18, QR.TravelTime:GetEffectiveTime(id, data, true, "spell"),
            "The shared estimate used by map buttons agrees with route edges")
        MockWoW.config.spellCooldowns[id] = { start = GetTime(), duration = 30 }
        pc:RefreshTeleportEdgeWeights()
        for _, target in ipairs({ "Loading destination", "Dungeon loading destination" }) do
            local edge = graph:GetEdge("Player Location", target)
            if edge then t:assertEqual(48, edge.weight, target .. " adds the thirty-second wait once") end
        end
        QR.db.loadingScreenTime, QR.db.considerCooldowns = 0, false
        QR.TravelTime.castTimeBySpell = {}
        C_Spell.GetSpellInfo = function() return { castTime = 0 } end
        pc:AddPlayerTeleportEdges()
        pc:AddDungeonTeleportEdges()
        for _, target in ipairs({ "Loading destination", "Dungeon loading destination" }) do
            local edge = graph:GetEdge("Player Location", target)
            t:assertNotNil(edge, target .. " remains connected when instant and configured loading is zero")
            if edge then t:assertEqual(0.001, edge.weight, target .. " keeps only the positive graph epsilon") end
        end
    end)
end)

T:run("Loading costs: zero replaces defaults and missing settings retain type defaults", function(t)
    isolated(function(replace)
        replace(QR, "db", { loadingScreenTime = 0 })
        local data = { type = "spell", class = "MAGE", castTime = 7 }
        t:assertEqual(7, QR.TravelTime:GetTeleportTime(data), "Zero loading preserves only the cast time")
        t:assertEqual(0, QR.TravelTime:GetPortalTime(), "Zero loading also applies to portals")
        QR.db.loadingScreenTime = nil
        t:assertEqual(10, QR.TravelTime:GetTeleportTime(data), "Missing setting retains the mage three-second default")
        t:assertEqual(5, QR.TravelTime:GetPortalTime(), "Missing setting retains the portal five-second default")
        t:assertEqual(18, QR.TravelTime:GetTeleportTime({ type = "hearthstone" }),
            "Missing setting retains the hearthstone ten-second cast plus eight-second load")
    end)
end)

T:run("Loading costs: portals honor total costs and instant floor changes", function(t)
    isolated(function(replace)
        replace(QR, "db", { loadingScreenTime = 11 })
        replace(QR, "TravelTransitions", { nodes = {
            A = { mapID = 84, x = 0.1, y = 0.1 },
            B = { mapID = 85, x = 0.2, y = 0.2 },
            C = { mapID = 85, x = 0.3, y = 0.3 },
            D = { mapID = 85, x = 0.4, y = 0.4 },
        }, edges = {
            { from = "A", to = "B", method = "portal" },
            { from = "B", to = "C", method = "portal", noLoadingScreen = true },
            { from = "C", to = "D", method = "portal", cost = 20 },
        } })
        replace(QR.PathCalculator, "graph", QR.Graph:New())
        QR.PathCalculator:AddConditionalConnections()
        local graph = QR.PathCalculator.graph
        t:assertEqual(11, graph:GetEdge("Travel:A", "Travel:B").weight, "An ordinary portal loads once")
        t:assertEqual(0.001, graph:GetEdge("Travel:B", "Travel:C").weight, "Floor changes without loading retain only graph epsilon")
        t:assertEqual(20, graph:GetEdge("Travel:C", "Travel:D").weight, "An explicit complete duration is not surcharged")
        QR.db.loadingScreenTime = 0
        QR.PathCalculator:AddConditionalConnections()
        t:assertEqual(0.001, graph:GetEdge("Travel:A", "Travel:B").weight,
            "A configured zero loading duration preserves portal connectivity")
    end)
end)
