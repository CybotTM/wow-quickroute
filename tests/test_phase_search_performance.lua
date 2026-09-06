local T, QR = ...

local function isolated(body)
    local changes = {}
    local function set(tbl, key, value)
        changes[#changes + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local ok, err = pcall(body, set)
    for i = #changes, 1, -1 do
        local change = changes[i]
        change[1][change[2]] = change[3]
    end
    if not ok then error(err) end
end

T:run("Phase search: valid route does not inspect unrelated phase metadata", function(t)
    isolated(function(set)
        local req, graph = QR.TravelRequirements, QR.Graph:New()
        local phaseReads, unrelatedReads, metadataReads, fallbackCalls = 0, 0, 0, 0
        set(req, "phaseOverrides", {})
        set(C_Map, "GetBestMapForUnit", function() return 84 end)
        set(C_Map, "GetMapArtID", function(mapID)
            if mapID == 17 then phaseReads = phaseReads + 1; return 18 end
            unrelatedReads = unrelatedReads + 1
            return 1
        end)
        graph:AddNode("Start", { mapID = 84 })
        graph:AddNode("Goal", { mapID = 2339 })
        graph:AddEdge("Start", "Goal", 1, "portal", { requirements = { mapArtID = { 17, 18 } } })
        -- An unrelated dense region must not make a direct valid route query
        -- inspect every node/edge or ask the client for unrelated phase state.
        local function metadata(fields)
            return setmetatable(fields or {}, { __index = function(_, key)
                if key == "requirements" then metadataReads = metadataReads + 1 end
            end })
        end
        for i = 1, 500 do
            graph:AddNode("Remote" .. i, metadata({ mapID = 900000 + i, mapArtID = 1 }))
        end
        for i = 1, 500 do
            for offset = 1, 10 do
                graph:AddEdge("Remote" .. i, "Remote" .. ((i + offset - 1) % 500 + 1),
                    10, "walk", metadata())
            end
        end
        local original = graph.FindShortestPathWithState
        graph.FindShortestPathWithState = function(self, ...)
            fallbackCalls = fallbackCalls + 1
            return original(self, ...)
        end
        local path, cost = req:FindPath(graph, "Start", "Goal")
        t:assertNotNil(path, "Direct route remains available with 500 unrelated phase nodes")
        t:assertEqual(1, cost, "Direct route retains its optimal travel cost")
        t:assertEqual(1, phaseReads, "Live phase on the selected route is read once")
        t:assertEqual(0, unrelatedReads, "No unrelated map phase is queried")
        t:assertEqual(0, metadataReads, "No unrelated node or edge metadata is inspected")
        t:assertEqual(0, fallbackCalls, "A valid lower-bound route needs no stateful search")
    end)
end)

T:run("Phase search: rejected optimistic route discovers alternative phase switches", function(t)
    isolated(function(set)
        local req, graph = QR.TravelRequirements, QR.Graph:New()
        local phases, reads = { [17] = 18, [249] = 289 }, {}
        set(req, "phaseOverrides", {})
        set(C_Map, "GetBestMapForUnit", function() return 84 end)
        set(C_Map, "GetMapArtID", function(mapID)
            reads[mapID] = (reads[mapID] or 0) + 1
            return phases[mapID]
        end)
        set(C_QuestLog, "IsQuestFlaggedCompleted", function() return nil end)
        graph:AddNode("Start", { mapID = 84 })
        graph:AddNode("Goal", { mapID = 2339 })
        graph:AddNode("Past", { mapID = 249 })
        graph:AddNode("Present", { mapID = 1527 })
        graph:AddEdge("Start", "Goal", 1, "portal", { requirements = { mapArtID = { 17, 628 } } })
        graph:AddEdge("Start", "Past", 1, "walk")
        graph:AddEdge("Past", "Present", 2, "phaseswitch", { phaseMapID = 249, phaseArtID = 260 })
        graph:AddEdge("Present", "Goal", 1, "portal", { requirements = {
            anyOf = { { quest = 900001 }, { mapArtID = { 249, 260 } } },
        } })

        local path, cost, edges = req:FindPath(graph, "Start", "Goal")
        t:assertNotNil(path, "Fallback finds a route through a phase absent from the optimistic path")
        t:assertEqual(4, cost, "Fallback includes the alternative route's explicit phase switch")
        t:assertEqual("phaseswitch", edges and edges[2].edgeType, "Past and present cannot be crossed without switching")
        t:assertEqual(1, reads[249], "Fallback initializes the previously unrelated Uldum phase")
        t:assertEqual(289, phases[249], "Hypothetical switching preserves live phase state")

        phases[17], phases[249], reads = 628, nil, {}
        local _, directCost = req:FindPath(graph, "Start", "Goal")
        t:assertEqual(1, directCost, "A new live phase immediately enables the direct route")
        t:assertNil(reads[249], "Direct route does not query now-irrelevant unknown Uldum state")

        phases[17], phases[249] = nil, nil
        local unavailable = req:FindPath(graph, "Start", "Goal")
        t:assertNil(unavailable, "Unknown phase state cannot reuse either previous successful route")
    end)
end)

T:run("Phase search: live quest and phase changes retain parallel transport choices", function(t)
    isolated(function(set)
        local req, graph = QR.TravelRequirements, QR.Graph:New()
        local completed, phase = false, 289
        set(req, "phaseOverrides", {})
        set(C_Map, "GetBestMapForUnit", function() return 84 end)
        set(C_Map, "GetMapArtID", function() return phase end)
        set(C_QuestLog, "IsQuestFlaggedCompleted", function() return completed end)
        graph:AddNode("Start", { mapID = 84 })
        graph:AddNode("Goal", { mapID = 2339 })
        graph:AddEdgeOption("Start", "Goal", 1, "portal", { requirements = {
            quest = 900001, anyOf = { mapArtID = { 249, 289 } },
        } })
        graph:AddEdgeOption("Start", "Goal", 20, "walk", {})
        local _, cost = req:FindPath(graph, "Start", "Goal")
        t:assertEqual(20, cost, "Incomplete quest retains the slower accessible walking option")
        completed = true
        local _, unlockedCost, unlockedEdges = req:FindPath(graph, "Start", "Goal")
        t:assertEqual(1, unlockedCost, "Quest completion is evaluated anew without rebuilding the graph")
        t:assertEqual("portal", unlockedEdges and unlockedEdges[1].edgeType, "Nested named phase requirement enables the portal")
        phase = 260
        local _, changedCost, changedEdges = req:FindPath(graph, "Start", "Goal")
        t:assertEqual(20, changedCost, "Live phase change removes the cheap portal from consideration")
        t:assertEqual("walk", changedEdges and changedEdges[1].edgeType, "Stateful fallback preserves parallel walking transport")
        phase = nil
        local _, unknownCost = req:FindPath(graph, "Start", "Goal")
        t:assertEqual(20, unknownCost, "Unknown phase cannot grant portal access")
        completed, phase = nil, 289
        local _, unknownQuestCost = req:FindPath(graph, "Start", "Goal")
        t:assertEqual(20, unknownQuestCost, "Unknown quest state cannot reuse prior access")
    end)
end)

T:run("Phase search: implicit and explicit start phases are checked on zero-edge routes", function(t)
    isolated(function(set)
        local req, graph = QR.TravelRequirements, QR.Graph:New()
        local phases = { [249] = 260, [17] = 18 }
        set(req, "phaseOverrides", {})
        set(C_Map, "GetBestMapForUnit", function() return 84 end)
        set(C_Map, "GetMapArtID", function(mapID) return phases[mapID] end)
        graph:AddNode("Start", { mapID = 1527 })
        graph:AddNode("Goal", { mapID = 84 })
        graph:AddEdge("Start", "Goal", 1, "walk")
        local path, cost = req:FindPath(graph, "Start", "Start")
        t:assertNotNil(path, "A zero-edge route validates the start node's implicit present phase")
        t:assertEqual(0, cost, "Already being at the destination has zero cost")
        phases[249] = 289
        t:assertNil(req:FindPath(graph, "Start", "Start"), "Zero-edge routes cannot bypass an invalid implicit start phase")
        t:assertNil(req:FindPath(graph, "Start", "Goal"), "A route cannot leave an inaccessible start node")
        graph:AddNode("Controlled", { mapID = 900001, phaseCheckMapID = 17, mapArtID = 18 })
        t:assertNotNil(req:FindPath(graph, "Controlled", "Controlled"), "Explicit phaseCheckMapID is collected independently of node mapID")
        phases[17] = nil
        t:assertNil(req:FindPath(graph, "Controlled", "Controlled"), "Unknown explicit start phase remains unavailable")
    end)
end)
