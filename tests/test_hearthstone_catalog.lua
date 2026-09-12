local T, QR, MockWoW = ...
local areaNames = require("fixtures.hearthstone_area_names")

local function isolated(locale, body)
    local saved = {}
    local function replace(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local name, calls = areaNames[locale][14771], 0
    replace(QR.db, "hearthstoneBinds", {})
    replace(QR.Hearthstone, "innIndex", nil)
    replace(QR.Hearthstone, "innIndexIncomplete", nil)
    replace(QR.PathCalculator, "graphDirty", false)
    replace(_G, "UnitGUID", function() return "Player-Catalog-Test" end)
    replace(_G, "GetBindLocation", function() return name end)
    replace(C_Map, "GetAreaInfo", function(id)
        calls = calls + 1
        return areaNames[locale][id]
    end)
    local ok, err = pcall(body, function(value) name = value end, function() return calls end, replace)
    for i = #saved, 1, -1 do
        local entry = saved[i]
        entry[1][entry[2]] = entry[3]
    end
    if not ok then error(err) end
end

T:run("Hearthstone catalog: shipped records match the reviewed client-data snapshot", function(t)
    t:assertEqual("table", type(QR.HearthstoneLocations), "The real catalog loads through the addon manifest")
    if type(QR.HearthstoneLocations) ~= "table" then return end
    local ids, maps, points, positions, blockers, defaults = {}, {}, {}, 0, 0, 0
    for _, entry in ipairs(QR.HearthstoneLocations) do
        t:assert(type(entry.areaID) == "number" and entry.areaID > 0 and entry.areaID % 1 == 0,
            "Every record has an integer AreaTable ID")
        t:assertNil(ids[entry.areaID], "Area ID " .. tostring(entry.areaID) .. " is not repeated")
        ids[entry.areaID] = true
        for _, locale in ipairs({ "enUS", "deDE" }) do
            t:assertNotNil(areaNames[locale][entry.areaID], locale .. " contains client data for " .. entry.areaID)
        end
        if entry.ambiguous then
            blockers = blockers + 1
            t:assertNil(entry.mapID, "Blocked area " .. entry.areaID .. " cannot carry a route destination")
        else
            positions = positions + 1
            t:assert(type(entry.mapID) == "number" and entry.mapID > 0 and entry.mapID % 1 == 0,
                "Inn " .. entry.areaID .. " has an integer UI map ID")
            t:assert(type(entry.x) == "number" and entry.x >= 0 and entry.x <= 1
                and type(entry.y) == "number" and entry.y >= 0 and entry.y <= 1,
                "Inn " .. entry.areaID .. " has finite normalized coordinates")
            maps[entry.mapID] = true
            points[tostring(entry.mapID) .. ":" .. tostring(entry.x) .. ":" .. tostring(entry.y)] = true
        end
        if entry.isDefault then
            defaults = defaults + 1
            t:assert(entry.areaID == 3462 or entry.areaID == 15995,
                "Only the explicitly chosen Morgenluft alias pair can be a default")
            t:assertEqual(2395, entry.mapID, "Both Morgenluft aliases select the modern map")
            t:assertEqual(0.462, entry.x, "Both aliases retain the current Sylmara NPC map-data X")
            t:assertEqual(0.460, entry.y, "Both aliases retain the current Sylmara NPC map-data Y")
        end
    end
    local mapCount, pointCount = 0, 0
    for _ in pairs(maps) do mapCount = mapCount + 1 end
    for _ in pairs(points) do pointCount = pointCount + 1 end
    t:assertEqual(119, #QR.HearthstoneLocations, "The published 2026-09-12 snapshot has 119 records")
    t:assertEqual(60, positions, "The snapshot has 60 positioned rows including both modern Morgenluft aliases")
    t:assertEqual(59, pointCount, "The 60 positioned rows identify 59 distinct catalog targets")
    t:assertEqual(59, blockers, "The published snapshot preserves 59 explicit ambiguity/phase blockers")
    t:assertEqual(2, defaults, "Exactly the two Morgenluft name aliases carry the explicit default marker")
    t:assertEqual(44, mapCount, "The published inn positions cover 44 distinct UI maps")
end)

for _, locale in ipairs({ "enUS", "deDE" }) do
    T:run("Hearthstone catalog: all real " .. locale .. " names build a complete reusable index", function(t)
        isolated(locale, function(bindTo, calls)
            local resolvedNames = {}
            for _, entry in ipairs(QR.HearthstoneLocations) do
                local name = areaNames[locale][entry.areaID]
                bindTo(name)
                local point = QR.Hearthstone:GetDestination()
                local modernDefault = name == areaNames[locale][15995]
                if entry.ambiguous and not modernDefault then
                    t:assertNil(point, locale .. " ambiguity blocker " .. entry.areaID .. " remains unresolved")
                else
                    t:assertNotNil(point, locale .. " sourced inn " .. entry.areaID .. " resolves before first use")
                    if point then
                        resolvedNames[name] = true
                        t:assertEqual(modernDefault and 2395 or entry.mapID, point.mapID,
                            "Inn " .. entry.areaID .. " uses its source map or the explicit modern Morgenluft default")
                        t:assertEqual("INN_DATABASE", point.source, "Inn " .. entry.areaID .. " retains inferred provenance")
                        t:assertTrue(point.isApproximate, "Inn " .. entry.areaID .. " does not claim an exact landing")
                    end
                end
            end
            local resolved = 0
            for _ in pairs(resolvedNames) do resolved = resolved + 1 end
            t:assertEqual(59, resolved, locale .. " resolves 58 unambiguous names and the explicit Morgenluft default")
            t:assertEqual(119, calls(), "Each of the 119 real names is localized once for " .. locale)
            t:assertEqual(false, QR.Hearthstone.innIndexIncomplete, "The complete " .. locale .. " fixture permits inference")
            t:assertNil(next(QR.db.hearthstoneBinds), "Catalog lookups never save inferred character observations")
        end)
    end)

    T:run("Hearthstone catalog: " .. locale .. " Dornogal uses the sourced inn point", function(t)
        isolated(locale, function(bindTo)
            bindTo(areaNames[locale][14771])
            local point = QR.Hearthstone:GetDestination()
            t:assertNotNil(point, "Dornogal resolves from its real " .. locale .. " client label")
            if point then
                t:assertEqual(2339, point.mapID, "Dornogal uses the city UI map")
                t:assertEqual(0.4482, point.x, "Dornogal X is the pinned TWW_Dorn.lua:64 source point")
                t:assertEqual(0.4649, point.y, "Dornogal Y is the pinned TWW_Dorn.lua:64 source point")
            end
        end)
    end)
end

T:run("Hearthstone catalog: real German Morgenluft defaults to the modern inn before observation", function(t)
    isolated("deDE", function(bindTo)
        t:assertEqual("Morgenluft", areaNames.deDE[3462], "Legacy AreaTable 3462 uses the client's German name")
        t:assertEqual("Morgenluft", areaNames.deDE[15995], "Midnight AreaTable 15995 has the same German name")
        bindTo(areaNames.deDE[15995])
        local point = QR.Hearthstone:GetDestination()
        t:assertEqual(2395, point and point.mapID, "The requested default uses modern Eversong Woods")
        t:assertEqual(0.462, point and point.x, "Default X follows the current Sylmara NPC map-data position")
        t:assertEqual(0.460, point and point.y, "Default Y follows the sourced modern innkeeper position")
        t:assertEqual("INN_DATABASE", point and point.source, "The selected default retains catalog provenance")
        t:assertTrue(point and point.isApproximate, "Default coordinates remain an inn approximation")
        t:assertTrue(point and point.isDefault, "The approximate destination identifies its explicit default policy")
        t:assertNil(next(QR.db.hearthstoneBinds), "Using the default never manufactures a saved observation")
    end)
end)

for _, mapID in ipairs({94, 2395}) do
    for _, source in ipairs({"HEARTHSTONE_BOUND", "HEARTHSTONE_ARRIVAL"}) do
        T:run("Hearthstone catalog: saved " .. source .. " on map " .. mapID .. " overrides the modern default", function(t)
            isolated("deDE", function(bindTo)
                bindTo("Morgenluft")
                -- Synthetic observed coordinates deliberately differ from the
                -- sourced default; they exercise character-data precedence.
                QR.db.hearthstoneBinds["Player-Catalog-Test"] = {
                    mapID = mapID, x = 0.4123, y = 0.5678, bindName = "Morgenluft", source = source,
                }
                local point = QR.Hearthstone:GetDestination()
                t:assertEqual(mapID, point and point.mapID, "The saved observation determines the actual map")
                t:assertEqual(0.4123, point and point.x, "Observed X replaces the catalog approximation")
                t:assertEqual(0.5678, point and point.y, "Observed Y replaces the catalog approximation")
                t:assertFalse(point and point.isApproximate == true, "The result is no longer a catalog approximation")
                t:assertFalse(point and point.isDefault == true, "A saved observation is not labelled as the default")
                t:assertEqual(source, QR.db.hearthstoneBinds["Player-Catalog-Test"].source,
                    "Lookup preserves the saved observation's provenance")
            end)
        end)
    end
end

local function captureFixture(replace)
    local state = { mapID = 627, x = 0.4, y = 0.6, area = "Dalaran", timers = {} }
    replace(MockWoW, "eventFrames", {})
    replace(_G, "GetTime", function() return 100 end)
    replace(_G, "GetMinimapZoneText", function() return state.area end)
    replace(_G, "GetSubZoneText", function() return state.area end)
    replace(_G, "GetZoneText", function() return state.area end)
    replace(_G, "GetRealZoneText", function() return state.area end)
    replace(C_Map, "GetBestMapForUnit", function() return state.mapID end)
    replace(C_Map, "GetPlayerMapPosition", function()
        return { GetXY = function() return state.x, state.y end }
    end)
    replace(C_Item, "GetItemSpell", function(id)
        if id == 6948 then return "Hearthstone", 8690 end
    end)
    replace(C_Timer, "NewTimer", function(delay, callback)
        local timer = { delay = delay, callback = callback, Cancel = function(self) self.cancelled = true end }
        state.timers[#state.timers + 1] = timer
        return timer
    end)
    for _, key in ipairs({"frame", "pendingArrival", "hearthSpells", "hearthItems"}) do
        replace(QR.Hearthstone, key, nil)
    end
    QR.Hearthstone:Initialize()
    local frame = QR.Hearthstone.frame
    local handler = frame:GetScript("OnEvent")
    function state:event(event, ...)
        if frame._events[event] then handler(frame, event, ...) end
    end
    return state
end

for _, mapID in ipairs({94, 2395}) do
    T:run("Hearthstone catalog: a Morgenluft arrival through frame events on map " .. mapID .. " replaces the default", function(t)
        isolated("deDE", function(bindTo, _, replace)
            bindTo("Morgenluft")
            local state = captureFixture(replace)
            local default = QR.Hearthstone:GetDestination()
            t:assertEqual(2395, default and default.mapID, "The unobserved binding starts with the modern default")
            QR.PathCalculator.graphDirty = false
            state:event("UNIT_SPELLCAST_START", "player", "Cast-Catalog-Arrival", 8690)
            state:event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Catalog-Arrival", 8690)
            t:assertNil(next(QR.db.hearthstoneBinds), "Cast success does not save the departure map")
            state:event("LOADING_SCREEN_ENABLED")
            -- Simulated successful landing, not measured coordinates of an inn.
            state.mapID, state.x, state.y, state.area = mapID, 0.4123, 0.5678, "Morgenluft"
            state:event("PLAYER_ENTERING_WORLD", false, false)
            t:assertNil(next(QR.db.hearthstoneBinds), "Loading coordinates cannot replace the default prematurely")
            state:event("LOADING_SCREEN_DISABLED")
            local point = QR.Hearthstone:GetDestination()
            local stored = QR.db.hearthstoneBinds["Player-Catalog-Test"]
            t:assertEqual(mapID, point and point.mapID, "Completed arrival supplies the actual legacy or modern map")
            t:assertEqual(0.4123, point and point.x, "Completed arrival supplies the actual landing X")
            t:assertEqual(0.5678, point and point.y, "Completed arrival supplies the actual landing Y")
            t:assertEqual("HEARTHSTONE_ARRIVAL", stored and stored.source, "Successful use is persisted as arrival evidence")
            t:assertFalse(point and point.isApproximate == true, "The inferred default no longer labels the result")
            t:assertFalse(point and point.isDefault == true, "Actual arrival removes the default marker")
            t:assertTrue(QR.PathCalculator.graphDirty, "Actual landing invalidates routes built from the default")
            t:assertNil(QR.Hearthstone.pendingArrival, "Completed capture releases its pending generation")
            local resolved = QR.Hearthstone:ResolveTeleport(QR.TeleportItemsData[6948])
            t:assertEqual(mapID, resolved.mapID, "The planner's hearth option immediately receives the observed map")
            t:assertEqual(0.4123, resolved.x, "The planner's hearth option immediately receives the observed X")
            for _, timer in ipairs(state.timers) do timer.callback() end
            t:assertEqual(stored, QR.db.hearthstoneBinds["Player-Catalog-Test"],
                "Callbacks from completed capture generations cannot replace the saved observation")
        end)
    end)

    T:run("Hearthstone catalog: rebinding at Morgenluft on map " .. mapID .. " replaces the default", function(t)
        isolated("deDE", function(bindTo, _, replace)
            bindTo("Morgenluft")
            local state = captureFixture(replace)
            local default = QR.Hearthstone:GetDestination()
            t:assertEqual(2395, default and default.mapID, "Rebinding begins with the unobserved modern default")
            QR.PathCalculator.graphDirty = false
            state.mapID, state.x, state.y, state.area = mapID, 0.4123, 0.5678, "Morgenluft"
            state:event("HEARTHSTONE_BOUND")
            local point = QR.Hearthstone:GetDestination()
            local stored = QR.db.hearthstoneBinds["Player-Catalog-Test"]
            t:assertEqual(mapID, point and point.mapID, "The bind event overrides the default with its observed map")
            t:assertEqual(0.4123, point and point.x, "The bind event overrides the default with its observed X")
            t:assertEqual("HEARTHSTONE_BOUND", stored and stored.source, "Rebinding retains distinct observation provenance")
            t:assertTrue(QR.PathCalculator.graphDirty, "Rebinding invalidates routes built from the default")
        end)
    end)
end
