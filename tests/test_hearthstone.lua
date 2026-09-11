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

-- These events run through the production frame handler. Timers are queued so
-- a successful cast cannot accidentally record its still-visible origin.
local function arrivalFixture(replace)
    setup(replace)
    replace(MockWoW, "eventFrames", {})
    local state = { mapID = 627, x = 0.4, y = 0.6, area = "Dalaran", now = 100, timers = {} }
    replace(_G, "GetTime", function() return state.now end)
    replace(_G, "GetMinimapZoneText", function() return state.area end)
    replace(_G, "GetSubZoneText", function() return state.area end)
    replace(_G, "GetZoneText", function() return state.zone end)
    replace(_G, "GetRealZoneText", function() return state.zone end)
    replace(C_Map, "GetBestMapForUnit", function() return state.mapID end)
    replace(C_Map, "GetPlayerMapPosition", function()
        if state.unavailable then return nil end
        return { GetXY = function() return state.x, state.y end }
    end)
    replace(C_Item, "GetItemSpell", function(id)
        if id == 6948 then return "Hearthstone", 8690 end
        if id == 93672 then return "Dark Portal", 136508 end
    end)
    replace(C_Timer, "NewTimer", function(delay, callback)
        local timer = { callback = callback, delay = delay, Cancel = function(self) self.cancelled = true end }
        state.timers[#state.timers + 1] = timer
        return timer
    end)
    for _, key in ipairs({ "frame", "pendingArrival", "hearthSpells", "hearthItems" }) do
        replace(QR.Hearthstone, key, nil)
    end
    QR.Hearthstone:Initialize()
    local handler = QR.Hearthstone.frame:GetScript("OnEvent")
    function state:event(event, ...)
        if QR.Hearthstone.frame._events[event] then handler(QR.Hearthstone.frame, event, ...) end
    end
    function state:cast(spellID)
        self:event("UNIT_SPELLCAST_START", "player", "Cast-Hearth", spellID or 8690)
        self:event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Hearth", spellID or 8690)
    end
    function state:land()
        self.mapID, self.x, self.y, self.area = 37, 0.43, 0.65, "Lion's Pride Inn"
    end
    function state:tick()
        local timers = self.timers
        self.timers = {}
        for _, timer in ipairs(timers) do
            if not timer.cancelled then
                if timer.delay <= 0.25 then self.now = self.now + timer.delay; timer.callback()
                else self.timers[#self.timers + 1] = timer end
            end
        end
    end
    return state
end

T:run("Hearthstone: existing binding is learned from the verified arrival, never the cast origin", function(t)
    isolated(function(replace)
        local state = arrivalFixture(replace)
        state:cast()
        t:assertNil(QR.Hearthstone:GetDestination(), "Successful cast does not immediately save Dalaran")
        state:event("LOADING_SCREEN_ENABLED")
        state:land()
        state:event("PLAYER_ENTERING_WORLD", false, false)
        t:assertNil(QR.Hearthstone:GetDestination(), "Coordinates during loading are not accepted")
        state:event("LOADING_SCREEN_DISABLED")
        state:tick()
        local destination = QR.Hearthstone:GetDestination()
        t:assertNotNil(destination, "An old binding becomes routable after using the hearthstone")
        if destination then
            t:assertEqual(37, destination.mapID, "Observed destination is the inn map")
            t:assertEqual(0.43, destination.x, "Observed destination is the actual landing X")
            t:assertEqual("HEARTHSTONE_ARRIVAL", QR.db.hearthstoneBinds["Player-1-A"].source,
                "Arrival provenance remains distinct from rebinding")
        end
        t:assertTrue(QR.PathCalculator.graphDirty, "Learning an arrival invalidates the graph")
        local resolved = QR.TeleportDestinations:GetDestinations(6948, { data = QR.TeleportItemsData[6948] })
        t:assertEqual(1, #resolved, "The learned old bind enters the normal planner destination provider")
        t:assertEqual(37, resolved[1] and resolved[1].mapID, "Planner receives the observed inn map")
    end)
end)

T:run("Hearthstone: completion after the loading events retains the pre-cast origin", function(t)
    isolated(function(replace)
        local state = arrivalFixture(replace)
        state:event("UNIT_SPELLCAST_START", "player", "Cast-Hearth", 8690)
        state:event("LOADING_SCREEN_ENABLED")
        state:land()
        state:event("PLAYER_ENTERING_WORLD", false, false)
        state:event("LOADING_SCREEN_DISABLED")
        t:assertNil(QR.Hearthstone:GetDestination(), "A completed loading screen alone does not prove cast success")
        state:event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Hearth", 8690)
        t:assertNotNil(QR.Hearthstone:GetDestination(), "Delayed success still uses the captured departure position")
    end)
end)

T:run("Hearthstone: a city-named bind accepts its observed arrival in an inn subzone", function(t)
    isolated(function(replace)
        local state = arrivalFixture(replace)
        replace(_G, "GetBindLocation", function() return "Stormwind City" end)
        state:cast()
        state:event("LOADING_SCREEN_ENABLED")
        state.mapID, state.x, state.y = 84, 0.601, 0.755
        state.area, state.zone = "The Gilded Rose", "Stormwind City"
        state:event("LOADING_SCREEN_DISABLED")
        local destination = QR.Hearthstone:GetDestination()
        t:assertNotNil(destination, "A matching parent-zone name validates a successful observed landing")
        if destination then
            t:assertEqual(0.601, destination.x, "The actual inn coordinate is retained, not the city centre")
        end
    end)
end)

T:run("Hearthstone: idle deadline, canceled retries and unrelated gameplay remain bounded", function(t)
    isolated(function(replace)
        local state = arrivalFixture(replace)
        local calls = 0
        replace(C_Item, "GetItemSpell", function() calls = calls + 1 end)
        for i = 1, 100 do
            state:event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Other" .. i, 133)
        end
        t:assertEqual(0, calls, "Ordinary spell events perform no item lookups")
        t:assertEqual(0, #state.timers, "Ordinary spell events schedule no capture timers")
        state:cast()
        local timeout = state.timers[1]
        t:assertNotNil(timeout, "A pending hearth has a bounded expiration timer")
        if timeout then
            state.now = state.now + 60
            timeout.callback()
        end
        state:land()
        state:event("LOADING_SCREEN_DISABLED")
        t:assertNil(QR.Hearthstone:GetDestination(), "An expired cast cannot be revived by a later load")
        state:cast()
        state:event("ZONE_CHANGED")
        local oldTimer = state.timers[#state.timers]
        state:event("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-Hearth", 8690)
        if oldTimer then oldTimer.callback() end
        t:assertNil(QR.Hearthstone:GetDestination(), "Canceled callbacks cannot resurrect old capture state")
    end)
end)

T:run("Hearthstone: late cached toy spell is learned without parsing its localized name", function(t)
    isolated(function(replace)
        local state = arrivalFixture(replace)
        replace(QR.Hearthstone.hearthSpells, 136508, nil)
        state:event("GET_ITEM_INFO_RECEIVED", 93672, true)
        state:cast(136508)
        state:land()
        state:event("ZONE_CHANGED_NEW_AREA")
        t:assertNotNil(QR.Hearthstone:GetDestination(), "A cache event resolves the toy's real on-use spell")
    end)
end)

T:run("Hearthstone: unrelated loading, interrupted and expired casts cannot create a binding", function(t)
    for _, scenario in ipairs({ "unrelated", "interrupted", "expired", "wrong-area", "unchanged", "other-cast" }) do
        isolated(function(replace)
            local state = arrivalFixture(replace)
            if scenario ~= "unrelated" then
                state:event("UNIT_SPELLCAST_START", "player", "Cast-Hearth", 8690)
                if scenario == "interrupted" then
                    state:event("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-Hearth", 8690)
                else
                    state:event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Hearth", 8690)
                end
            end
            state:event("LOADING_SCREEN_ENABLED")
            if scenario ~= "unchanged" then state:land() end
            if scenario == "expired" then state.now = state.now + 90 end
            if scenario == "wrong-area" then state.area = "Another Inn" end
            if scenario == "other-cast" then state:event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Other", 3561) end
            state:event("LOADING_SCREEN_DISABLED")
            for _ = 1, 16 do state:tick() end
            t:assertNil(QR.Hearthstone:GetDestination(), scenario .. " does not save a false hearth destination")
        end)
    end
end)

T:run("Hearthstone: cosmetic hearth, delayed map position and same-map arrival are learned", function(t)
    isolated(function(replace)
        local state = arrivalFixture(replace)
        state.mapID = 37
        state:cast(136508)
        state:tick()
        t:assertNil(QR.Hearthstone:GetDestination(), "Toy cast initially retains unknown landing")
        state:land()
        state.unavailable = true
        state:event("ZONE_CHANGED")
        state:tick()
        t:assertNil(QR.Hearthstone:GetDestination(), "Unavailable post-cast position is not fabricated")
        state.unavailable = false
        state:tick()
        t:assertNotNil(QR.Hearthstone:GetDestination(), "Same-map toy landing is learned once coordinates arrive")
    end)
end)

T:run("Hearthstone: arrival capture rejects changed character, binding and secret payloads", function(t)
    for _, scenario in ipairs({ "character", "binding", "secret" }) do
        isolated(function(replace)
            local state = arrivalFixture(replace)
            state:cast()
            state:land()
            if scenario == "character" then replace(_G, "UnitGUID", function() return "Player-1-B" end) end
            if scenario == "binding" then replace(_G, "GetBindLocation", function() return "Other Inn" end) end
            if scenario == "secret" then
                replace(_G, "issecretvalue", function(value) return value == state.x end)
            end
            state:event("ZONE_CHANGED")
            state:tick()
            t:assertNil(QR.Hearthstone:GetDestination(), scenario .. " cannot validate an arrival")
        end)
    end
end)
