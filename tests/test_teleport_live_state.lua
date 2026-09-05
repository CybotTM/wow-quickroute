local T, QR, MockWoW = ...

local function Isolated(fn)
    MockWoW:Reset()
    QR.PlayerInfo:InvalidateCache()
    local saved = {}
    local function set(owner, key, value)
        saved[#saved + 1] = { owner, key, owner[key] }
        owner[key] = value
    end
    local ok, err = pcall(fn, set)
    for i = #saved, 1, -1 do
        local entry = saved[i]
        entry[1][entry[2]] = entry[3]
    end
    MockWoW:Reset()
    QR.PlayerInfo:InvalidateCache()
    QR.PlayerInventory:ScanAll()
    if not ok then error(err) end
end

local function Find(entries, id)
    for _, entry in ipairs(entries or {}) do
        if entry.id == id then return entry end
    end
end

T:run("Live teleports: modern spellbook ownership agrees in both inventory panels", function(t)
    Isolated(function(set)
        MockWoW.config.playerClass = "MAGE"
        set(_G, "C_SpellBook", { IsSpellKnown = function(id) return id == 3561 end })
        set(_G, "IsSpellKnown", function() return false end)
        QR.PlayerInfo:InvalidateCache()
        QR.PlayerInventory:ScanAll()
        t:assertNotNil(QR.PlayerInventory.spells[3561], "Retail spellbook detects the known Stormwind teleport")
        local entry = Find(QR.TeleportPanel:CollectAllTeleports(), 3561)
        t:assertEqual("STATUS_READY", entry and entry.status.key,
            "The main inventory recognizes the same spell without the legacy API")
        local mini = QR.MiniTeleportPanel
        for _, key in ipairs({ "rows", "rowPool", "secureButtons" }) do set(mini, key, {}) end
        for _, key in ipairs({ "frame", "separator" }) do set(mini, key, nil) end
        mini:CreateFrame()
        mini:RefreshList()
        local found = false
        for _, button in ipairs(mini.secureButtons) do
            if button.teleportID == 3561 then found = true end
        end
        t:assertTrue(found, "The mini inventory offers the modern spellbook teleport")
        mini.frame:Hide()
    end)
end)

local function Clock(set)
    local now, timers = 1000, {}
    set(_G, "GetTime", function() return now end)
    set(C_Timer, "NewTimer", function(delay, callback)
        local timer = { deadline = now + delay, callback = callback }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end)
    return function(seconds)
        now = now + seconds
        local due = timers
        timers = {}
        for _, timer in ipairs(due) do
            if not timer.cancelled then
                if timer.deadline <= now then timer.callback()
                else timers[#timers + 1] = timer end
            end
        end
    end
end

local function ResetObserver(set)
    local tracker = QR.CooldownTracker
    for _, key in ipairs({ "listeners", "observedCooldowns" }) do set(tracker, key, {}) end
    for _, key in ipairs({ "eventFrame", "refreshTimer", "expiryTimer", "expiryDeadline",
        "notifying", "forceRefresh" }) do set(tracker, key, nil) end
    return tracker
end

T:run("Live teleports: one observer debounces cooldown events and refreshes at expiry", function(t)
    Isolated(function(set)
        local advance = Clock(set)
        local tracker = ResetObserver(set)
        local active, refreshes, queries = true, 0, 0
        set(QR.PlayerInventory, "GetAllTeleports", function()
            queries = queries + 1
            return { [140192] = { sourceType = "toy", data = QR.TeleportItemsData[140192] } }
        end)
        tracker:RegisterListener({}, function() refreshes = refreshes + 1 end, function() return active end)
        tracker:WatchActiveCooldowns()
        refreshes, queries = 0, 0
        local event = tracker.eventFrame:GetScript("OnEvent")
        MockWoW.config.itemCooldowns[140192] = { start = 1000, duration = 20, enable = 1 }
        event(tracker.eventFrame, "SPELL_UPDATE_COOLDOWN")
        event(tracker.eventFrame, "BAG_UPDATE_COOLDOWN")
        t:assertEqual(0, refreshes, "A cooldown event burst waits for one deferred update")
        advance(0.2)
        t:assertEqual(1, refreshes, "The event burst produces one changed-state refresh")
        t:assertEqual(1, queries, "The event burst scans the owned inventory once")
        event(tracker.eventFrame, "SPELL_UPDATE_COOLDOWN")
        advance(0.2)
        t:assertEqual(1, refreshes, "Unchanged cooldowns do not rebuild any UI")
        advance(20)
        t:assertEqual(2, refreshes, "Cooldown expiry refreshes readiness without another game event")
        active = false
        queries = 0
        event(tracker.eventFrame, "SPELL_UPDATE_COOLDOWN")
        advance(0.2)
        t:assertEqual(0, queries, "Hidden views do not scan cooldowns")
    end)
end)

T:run("Live teleports: usable filter removes a cooldown and restores it on expiry", function(t)
    Isolated(function(set)
        local advance = Clock(set)
        local tracker = ResetObserver(set)
        MockWoW.config.ownedToys[140192] = true
        QR.PlayerInventory:ScanAll()
        local main, panel = QR.MainFrame, QR.TeleportPanel
        set(main, "isShowing", true)
        set(main, "activeTab", "teleports")
        set(panel, "initialized", false)
        set(panel, "availabilityFilter", "usable")
        set(panel, "currentFilter", "All")
        set(panel, "searchText", "")
        for _, key in ipairs({ "teleportRows", "rowPool", "iconButtons", "cardPool", "cards" }) do
            set(panel, key, {})
        end
        set(panel, "frame", nil)
        set(panel, "sortedTeleports", {})
        panel:CreateContent(CreateFrame("Frame"))
        panel:Initialize()
        panel.availabilityFilter = "usable"
        panel:RefreshList()
        t:assertNotNil(Find(panel.sortedTeleports, 140192), "An off-cooldown owned toy is visible in usable")
        local event = tracker.eventFrame:GetScript("OnEvent")
        MockWoW.config.itemCooldowns[140192] = { start = 1000, duration = 20, enable = 1 }
        event(tracker.eventFrame, "BAG_UPDATE_COOLDOWN")
        advance(0.2)
        t:assertNil(Find(panel.sortedTeleports, 140192), "A newly used toy leaves the usable list automatically")
        advance(20)
        t:assertNotNil(Find(panel.sortedTeleports, 140192), "The toy returns when the cooldown expires")
        MockWoW.config.inCombatLockdown = true
        MockWoW.config.itemCooldowns[140192] = { start = 1020, duration = 20, enable = 1 }
        event(tracker.eventFrame, "BAG_UPDATE_COOLDOWN")
        advance(0.2)
        t:assertNotNil(Find(panel.sortedTeleports, 140192), "Combat does not rebuild secure activation rows")
        MockWoW.config.inCombatLockdown = false
        event(tracker.eventFrame, "PLAYER_REGEN_ENABLED")
        advance(0.2)
        t:assertNil(Find(panel.sortedTeleports, 140192), "Deferred state catches up after combat")
        panel.frame:Hide()
    end)
end)

T:run("Live teleports: sidebar resolves garrison choices and rejects the other faction", function(t)
    Isolated(function()
        MockWoW.config.ownedToys[110560] = true
        MockWoW.config.playerFaction = "Alliance"
        QR.PlayerInfo:InvalidateCache()
        QR.PlayerInventory:ScanAll()
        local entry = Find(QR.MapSidebar:FindTeleportsForMap(582), 110560)
        t:assertNotNil(entry, "Garrison Hearthstone appears for the resolved Lunarfall destination")
        if entry then
            t:assertEqual(582, entry.data.mapID, "The sidebar uses the selected landing map")
            t:assertFalse(entry.data.isDynamic, "The selected landing is resolved")
        end
        for _, candidate in ipairs(QR.MapSidebar:FindTeleportsForMap(525)) do
            t:assertFalse(candidate.data.mapID == 525,
                "An Alliance player never gets the Horde Frostwall landing")
        end
    end)
end)

T:run("Live teleports: map shortcut honors activation zone restrictions", function(t)
    Isolated(function(set)
        MockWoW.config.ownedToys[95567] = true
        set(C_ToyBox, "IsToyUsable", function() return true end)
        set(QR.PlayerInventory, "GetAllTeleports", function()
            return { [95567] = { sourceType = "toy", data = {
                name = "Kirin Tor Beacon", mapID = 504, x = 0.5, y = 0.5,
                usableOnMaps = { 504 },
            } } }
        end)
        set(QR.PlayerInfo, "IsOnAnyMap", function() return false end)
        t:assertNil(QR.MapTeleportButton:FindBestTeleportForMap(504),
            "The beacon is not offered from outside the Isle of Thunder")
        set(QR.PlayerInfo, "IsOnAnyMap", function() return true end)
        t:assertEqual(95567, QR.MapTeleportButton:FindBestTeleportForMap(504),
            "The beacon remains available inside its activation zone")
    end)
end)

local function MapViews(set)
    local map = CreateFrame("Frame")
    map.mapID = 627
    function map:GetMapID() return self.mapID end
    function map:SetMapID(id) self.mapID = id end
    set(_G, "WorldMapFrame", map)
    set(_G, "QuestMapFrame", CreateFrame("Frame", nil, map))
    local sidebar, button = QR.MapSidebar, QR.MapTeleportButton
    for _, key in ipairs({ "frame", "header", "content", "noTeleportText", "currentMapID" }) do
        set(sidebar, key, nil)
    end
    for _, key in ipairs({ "rows", "overlayButtons" }) do set(sidebar, key, {}) end
    set(sidebar, "initialized", false)
    set(sidebar, "collapsed", false)
    set(QR.db, "sidebarCollapsed", false)
    for _, key in ipairs({ "button", "currentMapID", "currentTeleportID", "currentSourceType" }) do
        set(button, key, nil)
    end
    set(button, "initialized", false)
    sidebar:Initialize()
    button:Initialize()
    map:Show()
    sidebar:Show()
    sidebar:UpdateForMap(627, true)
    return map, sidebar, button
end

T:run("Live teleports: mini and map views follow shared cooldown expiry", function(t)
    Isolated(function(set)
        local advance = Clock(set)
        local tracker = ResetObserver(set)
        MockWoW.config.ownedToys[140192] = true
        QR.PlayerInventory:ScanAll()
        local mini = QR.MiniTeleportPanel
        for _, key in ipairs({ "rows", "rowPool", "secureButtons" }) do set(mini, key, {}) end
        for _, key in ipairs({ "frame", "separator" }) do set(mini, key, nil) end
        set(mini, "isShowing", false)
        mini:Initialize()
        mini:Show()
        local map, sidebar, button = MapViews(set)
        local event = tracker.eventFrame:GetScript("OnEvent")
        MockWoW.config.itemCooldowns[140192] = { start = 1000, duration = 20, enable = 1 }
        event(tracker.eventFrame, "BAG_UPDATE_COOLDOWN")
        advance(0.2)
        t:assertTrue(mini.rows[1].statusLabel:GetText() ~= "", "The open mini panel shows the new cooldown")
        t:assertTrue(sidebar.rows[1].statusText:GetText() ~= QR.L["STATUS_READY"],
            "The open map sidebar shows the new cooldown")
        sidebar:Hide()
        button:UpdateForMap(627)
        t:assertTrue(button.button._qrCooldownText ~= "", "The floating map shortcut shows the cooldown")
        advance(20)
        t:assertEqual("", mini.rows[1].statusLabel:GetText(), "The mini panel clears expired cooldown text")
        t:assertTrue(not button.button._qrCooldownText or button.button._qrCooldownText == "",
            "The floating shortcut clears expired cooldown text")
        t:assertEqual(1, button.button:GetAlpha(), "The floating shortcut restores its ready appearance")
        mini:Hide()
        map:Hide()
    end)
end)

T:run("Live teleports: reopening the same map restores sidebar activation overlays", function(t)
    Isolated(function(set)
        ResetObserver(set)
        MockWoW.config.ownedToys[140192] = true
        QR.PlayerInventory:ScanAll()
        local map, sidebar = MapViews(set)
        t:assertGreaterThan(#sidebar.overlayButtons, 0, "The first map visit has clickable teleport icons")
        map:Hide()
        t:assertEqual(0, #sidebar.overlayButtons, "Closing the map releases its activation overlays")
        map:Show()
        sidebar:Show()
        t:assertGreaterThan(#sidebar.overlayButtons, 0, "Reopening the same zone rebuilds clickable icons")
        map:Hide()
    end)
end)

T:run("Live teleports: expanding the sidebar uses the map browsed while collapsed", function(t)
    Isolated(function(set)
        ResetObserver(set)
        set(QR.PlayerInventory, "GetAllTeleports", function()
            return {
                [140192] = { sourceType = "item", data = { mapID = 627, x = 0.5, y = 0.5 } },
                [6948] = { sourceType = "item", data = { mapID = 84, x = 0.5, y = 0.5 } },
            }
        end)
        local map, sidebar = MapViews(set)
        sidebar:Toggle()
        map:SetMapID(84)
        t:assertEqual(84, sidebar.currentMapID, "A collapsed sidebar remembers the newly browsed map")
        sidebar:Toggle()
        t:assertEqual(6948, sidebar.overlayButtons[1] and sidebar.overlayButtons[1].teleportID,
            "Expanding offers the teleport for the new map")
        map:Hide()
    end)
end)
