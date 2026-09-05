local T, QR = ...

local function isolated(body)
    local changes = {}
    local function set(tbl, key, value)
        changes[#changes + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local ok, err = pcall(body, set)
    for i = #changes, 1, -1 do local c = changes[i]; c[1][c[2]] = c[3] end
    if not ok then error(err) end
end

T:run("Travel requirements: false and unknown never grant access", function(t)
    isolated(function(set)
        local req = QR.TravelRequirements
        set(C_QuestLog, "IsQuestFlaggedCompleted", function(id) return id == 100 end)
        t:assertTrue(req:Check({ quest = 100 }), "Completed quest grants access")
        t:assertFalse(req:Check({ quest = 200 }), "Incomplete quest denies access")
        t:assertTrue(req:Check({ questNotCompleted = 200 }), "Known incomplete quest satisfies inverse")
        set(C_QuestLog, "IsQuestFlaggedCompleted", nil)
        t:assertNil(req:Check({ quest = 100 }), "Missing quest API stays unknown")
        t:assertNil(req:Check({ questNotCompleted = 100 }), "Missing quest API cannot grant inverse")
        t:assertNil(req:Check({ unsupportedCondition = true }), "Unknown condition never fails open")
    end)
end)

T:run("Hypothetical routes: transport matrix never moves the real player or spends a teleport", function(t)
    isolated(function(set)
        local pc, graph = QR.PathCalculator, QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.1, y = 0.1, nodeType = "player" })
        graph:AddNode("Landing", { mapID = 84, x = 0.9, y = 0.9 })
        graph:AddEdge("Player Location", "Landing", 0.001, "teleport", { teleportID = 123,
            teleportData = { type = QR.TeleportTypes.SPELL, mapID = 84 } })
        set(pc, "graph", graph); set(pc, "graphDirty", false)
        local original = graph.edges["Player Location"]["Landing"]
        local route = pc:CalculatePathFrom(84, 0.8, 0.8, 84, 0.9, 0.9, { excludeCooldowns = true })
        t:assertNotNil(route, "Hypothetical origin can route to a stop")
        for _, edge in ipairs(route and route.edges or {}) do
            t:assert(edge.edgeType ~= "teleport", "Reusable matrix excludes personal cooldown abilities")
        end
        t:assertEqual(0.1, graph.nodes["Player Location"].x, "Real player X is unchanged")
        t:assertEqual(original, graph.edges["Player Location"]["Landing"], "Real teleport edge is unchanged")
        t:assertEqual(graph, pc.graph, "Active routing graph remains the original object")
    end)
end)

T:run("Travel requirements: nested OR combines three-valued conditions", function(t)
    isolated(function(set)
        local req = QR.TravelRequirements
        set(C_QuestLog, "IsQuestFlaggedCompleted", function(id)
            if id == 100 then return true elseif id == 200 then return false end
        end)
        t:assertTrue(req:Check({ anyQuest = { 300, 100 } }), "One known success wins over an unknown")
        t:assertNil(req:Check({ anyQuest = { 300, 200 } }), "Unknown OR false remains unknown")
        t:assertFalse(req:Check({ anyQuest = { 200 } }), "All false OR is false")
        t:assertTrue(req:Check({ anyOf = { quest = 300, questNotCompleted = 200 } }), "Nested OR is evaluated")
    end)
end)

T:run("Travel requirements: phase search revisits locations after explicit switching", function(t)
    isolated(function(set)
        local req, graph = QR.TravelRequirements, QR.Graph:New()
        set(C_Map, "GetMapArtID", function() return 18 end)
        set(req, "phaseOverrides", {})
        graph:AddNode("Start", { mapID = 17 })
        graph:AddNode("Portal", { mapID = 17 })
        graph:AddNode("Past Zidormi", { mapID = 17, mapArtID = 18 })
        graph:AddNode("Present Zidormi", { mapID = 17, mapArtID = 628 })
        graph:AddNode("Goal", { mapID = 525 })
        graph:AddBidirectionalEdge("Start", "Portal", 1, "walk")
        graph:AddBidirectionalEdge("Portal", "Past Zidormi", 2, "walk")
        graph:AddBidirectionalEdge("Portal", "Present Zidormi", 2, "walk")
        graph:AddEdge("Past Zidormi", "Present Zidormi", 10, "phaseswitch", { phaseMapID = 17, phaseArtID = 628 })
        graph:AddEdge("Portal", "Goal", 5, "portal", { requirements = { mapArtID = { 17, 628 } } })
        local path, cost, edges = req:FindPath(graph, "Start", "Goal")
        t:assertNotNil(path, "A route exists after speaking to Zidormi")
        t:assertEqual(20, cost, "Cost includes reaching and using the explicit phase switch")
        local switches, visits = 0, 0
        for _, name in ipairs(path or {}) do if name == "Portal" then visits = visits + 1 end end
        for _, edge in ipairs(edges or {}) do if edge.edgeType == "phaseswitch" then switches = switches + 1 end end
        t:assertEqual(2, visits, "Same portal is reconsidered in a different phase")
        t:assertEqual(1, switches, "Phase cannot change through a walk edge")
        t:assertEqual(18, C_Map.GetMapArtID(17), "Search never changes live player phase")
    end)
end)

T:run("Travel requirements: unavailable cheapest option does not hide a valid alternative", function(t)
    isolated(function(set)
        set(C_QuestLog, "IsQuestFlaggedCompleted", function() return false end)
        local graph = QR.Graph:New()
        graph:AddNode("A"); graph:AddNode("B")
        graph:AddEdgeOption("A", "B", 1, "portal", { requirements = { quest = 100 } })
        graph:AddEdgeOption("A", "B", 30, "walk", {})
        local _, cost, edges = QR.TravelRequirements:FindPath(graph, "A", "B")
        t:assertEqual(30, cost, "Accessible walking option wins over locked portal")
        t:assertEqual("walk", edges and edges[1].edgeType, "Route carries the chosen accessible method")
    end)
end)

T:run("Travel requirements: unknown phase requires an explicit user selection", function(t)
    isolated(function(set)
        local req = QR.TravelRequirements
        set(C_Map, "GetMapArtID", function() return nil end)
        set(req, "phaseOverrides", {})
        t:assertNil(req:Check({ mapArtID = { 17, 18 } }), "Unknown phase does not invent a past-world route")
        t:assertTrue(req:SetPhaseOverride(17, 18), "User may select a documented current phase")
        t:assertTrue(req:Check({ mapArtID = { 17, 18 } }), "Explicit past-world selection grants matching phase")
        t:assertFalse(req:SetPhaseOverride(17, 999999), "Unknown art IDs cannot be selected")
        set(C_Map, "GetMapArtID", function() return 628 end)
        t:assertFalse(req:Check({ mapArtID = { 17, 18 } }), "New live phase overrides stale manual assumption")
    end)
end)

T:run("Travel requirements: phase assumptions are distinct from client evidence", function(t)
    isolated(function(set)
        local req = QR.TravelRequirements
        set(C_Map, "GetMapArtID", function() return nil end)
        set(C_Map, "GetBestMapForUnit", function() return 84 end)
        set(req, "phaseOverrides", {})
        req:SetPhaseOverride(17, 18)
        t:assertEqual(18, req:GetMapArtID(17), "Assumption supports planning")
        t:assertNil(req:GetLiveMapArtID(17), "Assumption cannot complete a phase action")
        local selected
        for _, option in ipairs(req:GetPhaseOptions()) do if option.mapID == 17 then selected = option end end
        t:assertEqual("assumed", selected.source, "UI labels manual assumption")
        set(C_Map, "GetMapArtID", function() return 628 end)
        t:assertEqual(628, req:GetLiveMapArtID(17), "Verified client state is reported separately")
        set(C_Map, "GetMapArtID", function() return 999999 end)
        t:assertNil(req:GetLiveMapArtID(17), "New undocumented client art is unknown")
        t:assertEqual(18, req:GetMapArtID(17), "Unknown new art still permits an explicit phase assumption")
    end)
end)

T:run("Travel requirements: alternate map revisions cannot be reached by walking", function(t)
    isolated(function(set)
        set(C_Map, "GetMapArtID", function(mapID) if mapID == 249 then return 289 end end)
        set(C_Map, "GetBestMapForUnit", function() return 84 end)
        local graph = QR.Graph:New()
        graph:AddNode("Past", { mapID = 249 })
        graph:AddNode("Tanaris", { mapID = 71 })
        graph:AddNode("Present", { mapID = 1527 })
        graph:AddBidirectionalEdge("Past", "Tanaris", 1, "walk")
        graph:AddBidirectionalEdge("Tanaris", "Present", 1, "walk")
        local path = QR.TravelRequirements:FindPath(graph, "Past", "Present")
        t:assertNil(path, "Travelling through neighboring zones cannot silently change Uldum phase")
        local zones = QR.BuildZoneTravelGraph()
        t:assertNil(zones.edges[249][1527], "No ordinary zero-cost edge connects Uldum revisions")
    end)
end)

T:run("Map coordinates: micro-zone endpoints project through verified parent transforms", function(t)
    isolated(function(set)
        set(C_Map, "GetMapInfo", function(mapID)
            if mapID == 2576 then return { mapType = 5, parentMapID = 2413 } end
            return { mapType = 3 }
        end)
        set(_G, "CreateVector2D", function(x, y) return { x = x, y = y } end)
        set(C_Map, "GetWorldPosFromMapPos", function(mapID, pos)
            if mapID == 2576 then return 1, { x = pos.x * 100, y = pos.y * 100 } end
        end)
        set(C_Map, "GetMapPosFromWorldPos", function(world, pos, requested)
            if world == 1 and requested == 2413 then
                return 2413, { GetXY = function() return pos.x / 200 + 0.2, pos.y / 200 + 0.2 end }
            end
        end)
        local mapID, x, y = QR.PathCalculator:ResolveMapPosition(2576, 0.64, 0.7)
        t:assertEqual(2413, mapID, "Microzone converted to enclosing outdoor zone")
        t:assertEqual(0.52, x, "X uses the transformed parent coordinate")
        t:assertEqual(0.55, y, "Y uses the transformed parent coordinate")
        set(C_Map, "GetMapPosFromWorldPos", function() return nil end)
        mapID, x, y = QR.PathCalculator:ResolveMapPosition(2576, 0.64, 0.7)
        t:assertEqual(2576, mapID, "Missing projection keeps original map")
        t:assertEqual(0.64, x, "Missing projection never relabels coordinates")
    end)
end)

T:run("Travel requirements: calendar-backed holidays stay unknown until synchronized", function(t)
    isolated(function(set)
        local req = QR.TravelRequirements
        set(req, "calendarReady", false)
        set(_G, "C_DateAndTime", { GetCurrentCalendarTime = function() return { year=2026, month=9, monthDay=6, hour=12, minute=0 } end })
        set(_G, "C_Calendar", {
            GetMonthInfo = function() return {year=2026,month=9} end,
            GetNumDayEvents = function() return 1 end,
            GetDayEvent = function() return {calendarType="HOLIDAY",iconTexture=235446,
                startTime={year=2026,month=9,monthDay=6,hour=10,minute=0},
                endTime={year=2026,month=9,monthDay=12,hour=23,minute=59}} end,
        })
        t:assertNil(req:Check({holiday="Darkmoon Faire"}), "Unloaded calendar never claims the Faire is open")
        set(req, "calendarReady", true)
        t:assertTrue(req:Check({holiday="Darkmoon Faire"}), "Synchronized event icon grants the correct holiday")
        set(C_DateAndTime, "GetCurrentCalendarTime", function() return {year=2026,month=9,monthDay=6,hour=9,minute=59} end)
        t:assertFalse(req:Check({holiday="Darkmoon Faire"}), "Opening day before event start is closed")
        set(C_DateAndTime, "GetCurrentCalendarTime", function() return {year=2026,month=9,monthDay=12,hour=23,minute=59} end)
        t:assertFalse(req:Check({holiday="Darkmoon Faire"}), "Closing timestamp is outside the event interval")
        set(C_Calendar, "GetDayEvent", function() return {calendarType="HOLIDAY",iconTexture=123} end)
        t:assertFalse(req:Check({holiday="Darkmoon Faire"}), "Different holiday does not unlock Darkmoon portals")
        set(C_Calendar, "GetMonthInfo", function() return {year=2026,month=10} end)
        t:assertNil(req:Check({holiday="Darkmoon Faire"}), "Calendar navigated to another month cannot claim today's event")
    end)
end)

T:run("Travel requirements: sourced portals never suppress a distinct ship", function(t)
    local req = QR.TravelRequirements
    t:assertTrue(req:HasReplacement(84, 1161, "portal"), "Verified Stormwind-Boralus portal replaces the coarse legacy copy")
    t:assertFalse(req:HasReplacement(84, 1161, "boat"), "Boat between the same maps remains an independent option")
end)

T:run("Routing: unusable owned toys and missing engineering never create teleport edges", function(t)
    isolated(function(set)
        local pc, graph = QR.PathCalculator, QR.Graph:New()
        graph:AddNode("Player Location", {mapID=84,x=0.5,y=0.5})
        set(pc, "graph", graph)
        set(QR.PlayerInfo, "HasEngineering", function() return false end)
        set(QR.PlayerInventory, "GetAllTeleports", function() return {
            [101]={isUsable=false,sourceType="toy",data={type="toy",mapID=85,x=0.5,y=0.5,destination="Unusable"}},
            [102]={isUsable=true,sourceType="toy",data={type="engineer",requiresEngineering=true,mapID=85,x=0.5,y=0.5,destination="Engineer"}},
        } end)
        pc:AddPlayerTeleportEdges()
        t:assertNil(graph.edges["Player Location"]["Unusable"], "Owned but unusable toy cannot be proposed")
        t:assertNil(graph.edges["Player Location"]["Engineer"], "Engineering-required generator needs actual profession")
    end)
end)

T:run("Routing: sourced island flights require discovery of both exact endpoints", function(t)
    isolated(function(set)
        local req = QR.TravelRequirements
        local a,b = {mapID=371,x=0.588,y=0.834},{mapID=554,x=0.230,y=0.710}
        set(_G,"C_TaxiMap", {GetTaxiNodesForMap=function(mapID)
            local p=mapID==371 and a or b
            return {{position={x=p.x,y=p.y},faction=0,isUndiscovered=mapID==554}}
        end})
        t:assertFalse(req:Check({flightDiscovery={a,b}}), "Undiscovered island cannot be reached by a fabricated taxi")
        set(C_TaxiMap,"GetTaxiNodesForMap",function(mapID)
            local p=mapID==371 and a or b
            return {{position={x=p.x,y=p.y},faction=0,isUndiscovered=false}}
        end)
        t:assertTrue(req:Check({flightDiscovery={a,b}}), "Both discovered masters enable documented route")
        set(C_TaxiMap,"GetTaxiNodesForMap",nil)
        t:assertNil(req:Check({flightDiscovery={a,b}}), "Unavailable discovery API stays unknown")
    end)
end)

T:run("Travel requirements: statically locked destinations never expand phase combinations", function(t)
    isolated(function(set)
        set(C_QuestLog,"IsQuestFlaggedCompleted",function()return true end)
        local graph=QR.Graph:New()
        graph:AddNode("A",{mapID=17});graph:AddNode("B",{mapID=525})
        graph:AddEdge("A","B",1,"portal",{requirements={questNotCompleted=34378,mapArtID={17,628}}})
        set(graph,"FindShortestPathWithState",function()error("unnecessary phase expansion")end)
        t:assertNil(QR.TravelRequirements:FindPath(graph,"A","B"), "Known locked entrance is rejected before expensive phase search")
    end)
end)

T:run("Travel requirements: taxi IDs and faction prevent confusing nearby or opposing masters", function(t)
    isolated(function(set)
        local point={mapID=2512,x=.5788,y=.4576,taxiNodeID=3168}
        set(_G,"UnitFactionGroup",function()return "Alliance"end)
        set(_G,"C_TaxiMap",{GetTaxiNodesForMap=function()return{{nodeID=3127,isUndiscovered=false,faction=0,position={x=point.x,y=point.y}}}end})
        t:assertFalse(QR.TravelRequirements:Check({flightDiscovery={point}}), "Matching coordinates cannot substitute another known taxi ID")
        set(C_TaxiMap,"GetTaxiNodesForMap",function()return{{nodeID=3168,isUndiscovered=false,faction=1}}end)
        t:assertFalse(QR.TravelRequirements:Check({flightDiscovery={point}}), "A Horde-only taxi cannot carry Alliance players")
        set(C_TaxiMap,"GetTaxiNodesForMap",function()return{{nodeID=3168,isUndiscovered=false,faction=0}}end)
        t:assertTrue(QR.TravelRequirements:Check({flightDiscovery={point}}), "Known neutral taxi ID remains valid if map projection changes")
    end)
end)

T:run("Routing: Oribos realms require discovered flights through the correct floor", function(t)
    isolated(function(set)
        local pc=QR.PathCalculator
        set(pc,"graph",nil);set(pc,"graphDirty",true)
        for _,key in ipairs({"nodeIndex","graphFaction","zoneTravelGraph","zoneTravelCache","knownFlightZonesOverride"})do set(pc,key,nil)end
        set(QR.PlayerInventory,"GetAllTeleports",function()return{}end)
        set(C_QuestLog,"IsQuestFlaggedCompleted",function()return true end)
        set(_G,"C_TaxiMap",{GetTaxiNodesForMap=function()return{}end})
        local graph=pc:BuildGraph()
        t:assertNil(QR.BuildZoneTravelGraph().edges[1670] and QR.BuildZoneTravelGraph().edges[1670][1533],
            "No ordinary walking edge crosses the gap from Oribos to Bastion")
        local path=QR.TravelRequirements:FindPath(graph,"Travel:ORIBOS","Travel:ASPIRANTS_REST_FLIGHT")
        t:assertNil(path,"An undiscovered realm cannot be reached through a fictitious Oribos portal")
        set(C_TaxiMap,"GetTaxiNodesForMap",function(mapID)
            local result={}
            for _,point in pairs(QR.TravelTransitions.nodes)do
                if point.mapID==mapID and point.taxiNodeID then result[#result+1]={nodeID=point.taxiNodeID,faction=0,isUndiscovered=false}end
            end
            return result
        end)
        graph=pc:BuildGraph()
        local edges,cost
        path,cost,edges=QR.TravelRequirements:FindPath(graph,"Travel:ORIBOS","Travel:ASPIRANTS_REST_FLIGHT")
        t:assertNotNil(path,"Known flight points provide the real route to Bastion")
        t:assertTrue(cost and cost>200,"Travel estimate includes real realm flight distance")
        local pad,flight
        for _,step in ipairs(path and pc:BuildSteps(path,edges) or{})do
            if step.instructionKey=="STEP_USE_TRANSLOCATION_PAD"then pad=step end
            if step.type=="flight"then flight=step end
        end
        t:assertNotNil(pad,"Route explicitly uses the translocation pad")
        t:assertNotNil(flight,"Route explicitly boards a flight")
        if pad then
            t:assertEqual(1670,pad.navMapID,"Pad navigation starts on Ring of Fates")
            t:assertEqual(.5209,pad.navX,"Pad waypoint uses its actual lower-floor coordinate")
            t:assertEqual(1671,pad.destMapID,"Pad reaches Ring of Transference")
        end
        if flight then
            t:assertEqual(1671,flight.navMapID,"Flight is boarded on the upper floor")
            t:assertEqual(.607,flight.navX,"Waypoint identifies the actual Oribos flight master")
            t:assertNotNil(flight.navLabel,"Source flight-master name remains visible")
        end
    end)
end)

T:run("Route context: reuses its private graph while checking live quest access", function(t)
    isolated(function(set)
        local pc,graph=QR.PathCalculator,QR.Graph:New()
        graph:AddNode("Player Location",{mapID=84,x=.1,y=.1,nodeType="player"})
        graph:AddNode("Gate",{mapID=84,x=.2,y=.2})
        graph:AddNode("Remote",{mapID=85,x=.5,y=.5})
        graph:AddEdge("Gate","Remote",5,"portal",{requirements={quest=100}})
        graph:AddEdge("Player Location","Remote",.001,"teleport",{teleportID=123,teleportData={mapID=85,type="spell"}})
        set(pc,"graph",graph);set(pc,"graphDirty",false)
        set(pc,"graphFaction",nil)
        set(C_QuestLog,"IsQuestFlaggedCompleted",function()return false end)
        local context=pc:CreateRouteContext({excludeCooldowns=true})
        t:assertNotNil(context,"A reusable isolated route context is created")
        local privateGraph=context.graph
        t:assert(privateGraph~=graph,"Context owns a separate graph")
        t:assertNil(context:CalculatePathFrom(84,.1,.1,85,.55,.5),"Locked gate stays unavailable despite parent's personal teleport")
        local newGraph=QR.Graph.New
        local allocations=0
        set(QR.Graph,"New",function(self)allocations=allocations+1;return newGraph(self)end)
        set(C_QuestLog,"IsQuestFlaggedCompleted",function()return true end)
        local route=context:CalculatePathFrom(84,.2,.2,85,.55,.5)
        t:assertNotNil(route,"Completed quest is picked up without recreating context")
        t:assertEqual(0,allocations,"Subsequent query reuses graph and zone caches")
        t:assertEqual(privateGraph,context.graph,"Private graph identity is stable across queries")
        t:assertEqual(.1,graph.nodes["Player Location"].x,"Parent's player position stays unchanged")
        t:assertEqual("teleport",graph.edges["Player Location"]["Remote"].edgeType,"Parent's teleport edge remains intact")
        for _,edge in ipairs(route and route.edges or{})do t:assert(edge.edgeType~="teleport","Reusable matrix never spends a personal teleport")end
    end)
end)

T:run("Route context: failed connections leave no temporary nodes or dangling edges", function(t)
    isolated(function(set)
        local pc,graph=QR.PathCalculator,QR.Graph:New()
        graph:AddNode("Player Location",{mapID=84,x=.1,y=.1,nodeType="player"})
        graph:AddNode("Landmark",{mapID=84,x=.8,y=.8})
        set(pc,"graph",graph);set(pc,"graphDirty",false);set(pc,"graphFaction",nil)
        local context=pc:CreateRouteContext({excludeCooldowns=true})
        local connect=context.ConnectNearbyNodes
        context.ConnectNearbyNodes=function(self,name,...)
            connect(self,name,...)
            if name~="Player Location"then error("simulated destination connection failure")end
        end
        local route=context:CalculatePathFrom(84,.2,.2,84,.7,.7)
        t:assertNil(route,"Failed query returns no route")
        local count=0
        for _ in pairs(context.graph.nodes)do count=count+1 end
        t:assertEqual(2,count,"Failed destination is removed from reusable graph")
        for _,outgoing in pairs(context.graph.edges)do
            for to in pairs(outgoing)do t:assertNotNil(context.graph.nodes[to],"No dangling edge retains failed destination")end
        end
        context.ConnectNearbyNodes=connect
        t:assertNotNil(context:CalculatePathFrom(84,.3,.3,84,.7,.7),"Next query recovers using the same context")
        t:assertEqual(.1,graph.nodes["Player Location"].x,"Even failures preserve parent's position")
        t:assertEqual(graph,pc.graph,"Parent graph is still the original graph")
    end)
end)

T:run("Route context: mutable caches never fall through to the active calculator", function(t)
    isolated(function(set)
        local pc,graph=QR.PathCalculator,QR.Graph:New()
        graph:AddNode("Player Location",{mapID=84,x=.1,y=.1,nodeType="player"})
        graph:AddNode("Landmark",{mapID=84,x=.8,y=.8})
        local parentZones=QR.Graph:New()
        parentZones:AddNode(84)
        local parentCache={untouched=true}
        local parentIndex={byMap={}}
        local override={[84]=true}
        set(pc,"graph",graph);set(pc,"graphDirty",false);set(pc,"graphFaction",nil)
        set(pc,"zoneTravelGraph",parentZones);set(pc,"zoneTravelCache",parentCache);set(pc,"nodeIndex",parentIndex)
        set(pc,"knownFlightZonesOverride",override)
        local context=pc:CreateRouteContext({excludeCooldowns=true})
        t:assertNil(context.zoneTravelGraph,"A new context does not inherit the parent's zone graph")
        t:assertNil(context.zoneTravelCache,"A new context does not inherit the parent's distance cache")
        t:assertNil(context.nodeIndex,"A new context does not inherit the parent's node index")
        t:assert(context.knownFlightZonesOverride~=override,"An explicit discovery override is copied, not shared")
        context:CalculatePathFrom(999991,.2,.2,84,.5,.5)
        t:assertNil(parentCache[999991],"Hypothetical origin cannot insert distances into parent's cache")
        t:assert(context.zoneTravelCache~=parentCache,"Populated context cache is privately owned")
        t:assert(context.zoneTravelGraph~=parentZones,"Populated zone graph is privately owned")
        t:assert(context.nodeIndex~=parentIndex,"Populated node index is privately owned")
        context.zoneTravelCache,context.zoneTravelGraph,context.nodeIndex=nil,nil,nil
        t:assertNil(context.zoneTravelCache,"Clearing private cache never exposes parent's cache")
        t:assertNil(context.zoneTravelGraph,"Clearing private zone graph never exposes parent's graph")
        t:assertNil(context.nodeIndex,"Clearing private index never exposes parent's index")
        context:BuildGraph()
        t:assertNil(parentCache[999991],"Private rebuild preserves the parent's distance entries")
        t:assertEqual(parentCache,pc.zoneTravelCache,"Private rebuild preserves parent cache identity")
        t:assertEqual(parentZones,pc.zoneTravelGraph,"Private rebuild preserves parent zone graph identity")
        t:assertEqual(parentIndex,pc.nodeIndex,"Private rebuild preserves parent node index identity")
    end)
end)
