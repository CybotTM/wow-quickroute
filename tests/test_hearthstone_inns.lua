local T, QR = ...

local function isolated(body)
    local saved = {}
    local function replace(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    replace(QR.db, "hearthstoneBinds", {})
    replace(QR.Hearthstone, "innIndex", nil)
    replace(QR.Hearthstone, "innIndexIncomplete", nil)
    replace(QR.PathCalculator, "graphDirty", false)
    replace(_G, "UnitGUID", function() return "Player-Inn-Test" end)
    replace(_G, "GetBindLocation", function() return "Testgasthaus" end)
    -- Synthetic locations test the resolver independently of catalogue coverage.
    replace(QR, "HearthstoneLocations", {
        { areaID = 900001, mapID = 37, x = 0.43, y = 0.65 },
    })
    replace(C_Map, "GetAreaInfo", function(id)
        if id == 900001 then return "Testgasthaus" end
        if id == 900002 then return "Anderes Gasthaus" end
    end)
    local ok, err = pcall(body, replace)
    for i = #saved, 1, -1 do
        local item = saved[i]
        item[1][item[2]] = item[3]
    end
    if not ok then error(err) end
end

T:run("Hearthstone inns: an existing localized binding is routable before its first use", function(t)
    isolated(function(replace)
        replace(C_Map, "GetPlayerMapPosition", function() error("Lookup must not read the current player position") end)
        local point = QR.Hearthstone:GetDestination()
        t:assertNotNil(point, "A known German bind name resolves without a saved observation")
        if point then
            t:assertEqual(37, point.mapID, "Destination uses the inn's map")
            t:assertEqual(0.43, point.x, "Destination uses the inn's X, not a zone centre")
            t:assertEqual("Testgasthaus", point.bindName, "Destination retains the client's localized name")
            t:assertEqual("INN_DATABASE", point.source, "Catalogue provenance is explicit")
            t:assertTrue(point.isApproximate, "Inn coordinates are marked as approximate")
        end
        t:assertNil(next(QR.db.hearthstoneBinds), "An inferred location is never persisted as an observation")
    end)
end)

T:run("Hearthstone inns: a character's actual observation takes precedence", function(t)
    isolated(function()
        QR.db.hearthstoneBinds["Player-Inn-Test"] = {
            bindName = "Testgasthaus", mapID = 37, x = 0.431, y = 0.651, source = "HEARTHSTONE_ARRIVAL",
        }
        local point = QR.Hearthstone:GetDestination()
        t:assertEqual(0.431, point and point.x, "Actual landing overrides approximate catalogue coordinates")
        t:assertFalse(point and point.isApproximate == true, "Actual arrival is not labelled as catalogue data")
    end)
end)

T:run("Hearthstone inns: stale and foreign observations cannot override the known inn", function(t)
    isolated(function()
        QR.db.hearthstoneBinds["Player-Other"] = {
            bindName = "Testgasthaus", mapID = 84, x = 0.6, y = 0.7, source = "HEARTHSTONE_ARRIVAL",
        }
        QR.db.hearthstoneBinds["Player-Inn-Test"] = {
            bindName = "Previous inn", mapID = 84, x = 0.6, y = 0.7, source = "HEARTHSTONE_BOUND",
        }
        local point = QR.Hearthstone:GetDestination()
        t:assertEqual(37, point and point.mapID, "Current localized binding determines the inferred destination")
    end)
end)

T:run("Hearthstone inns: distinct inns with the same localized name stay unresolved", function(t)
    isolated(function(replace)
        QR.HearthstoneLocations[2] = { areaID = 900002, mapID = 84, x = 0.6, y = 0.7 }
        replace(C_Map, "GetAreaInfo", function() return "Testgasthaus" end)
        t:assertNil(QR.Hearthstone:GetDestination(), "A name collision never chooses the first or nearest candidate")
        QR.db.hearthstoneBinds["Player-Inn-Test"] = {
            bindName = "Testgasthaus", mapID = 84, x = 0.601, y = 0.701, source = "HEARTHSTONE_ARRIVAL",
        }
        t:assertEqual(0.601, QR.Hearthstone:GetDestination().x, "An actual observation still resolves an ambiguous name")
    end)
end)

T:run("Hearthstone inns: a reentrant API hook cannot observe a partially built index", function(t)
    isolated(function(replace)
        QR.HearthstoneLocations[2] = { areaID = 900002, mapID = 84, x = 0.6, y = 0.7 }
        local nestedDestination, calls = nil, 0
        replace(C_Map, "GetAreaInfo", function()
            calls = calls + 1
            if calls == 2 then nestedDestination = QR.Hearthstone:GetDestination() end
            return "Testgasthaus"
        end)
        t:assertNil(QR.Hearthstone:GetDestination(), "Completed index rejects the duplicate name")
        t:assertNil(nestedDestination, "A hooked area-name getter cannot expose the first candidate early")
    end)
end)

T:run("Hearthstone inns: a hole in the catalogue cannot hide a collision blocker", function(t)
    isolated(function(replace)
        QR.HearthstoneLocations[3] = { areaID = 900002, ambiguous = true }
        replace(C_Map, "GetAreaInfo", function() return "Testgasthaus" end)
        t:assertNil(QR.Hearthstone:GetDestination(), "A later blocker remains effective beyond a missing array entry")
    end)
end)

T:run("Hearthstone inns: duplicate references to the same point do not create ambiguity", function(t)
    isolated(function(replace)
        QR.HearthstoneLocations[2] = { areaID = 900002, mapID = 37, x = 0.43, y = 0.65 }
        replace(C_Map, "GetAreaInfo", function() return "Testgasthaus" end)
        t:assertNotNil(QR.Hearthstone:GetDestination(), "Equivalent aliases identify one physical catalogue point")
    end)
end)

T:run("Hearthstone inns: an explicit ambiguous area blocks an otherwise unique match", function(t)
    isolated(function(replace)
        QR.HearthstoneLocations[2] = { areaID = 900002, ambiguous = true }
        replace(C_Map, "GetAreaInfo", function() return "Testgasthaus" end)
        t:assertNil(QR.Hearthstone:GetDestination(), "Known multi-inn areas cannot be inferred from incomplete coordinates")
    end)
end)

T:run("Hearthstone inns: unavailable localization cannot turn a duplicate into a unique match", function(t)
    isolated(function(replace)
        QR.HearthstoneLocations[2] = { areaID = 900002, mapID = 84, x = 0.6, y = 0.7 }
        replace(C_Map, "GetAreaInfo", function(id) if id == 900001 then return "Testgasthaus" end end)
        t:assertNil(QR.Hearthstone:GetDestination(), "Incomplete localization cannot establish a unique destination")
        replace(C_Map, "GetAreaInfo", function() return "Testgasthaus" end)
        QR.Hearthstone:OnEvent("PLAYER_ENTERING_WORLD", true, false)
        t:assertNil(QR.Hearthstone:GetDestination(), "Retry after login recognizes both conflicting candidates")
    end)
end)

T:run("Hearthstone inns: unknown, non-exact and secret names remain unresolved", function(t)
    for _, name in ipairs({ "Unknown inn", "Testgasthaus annex", "testgasthaus", "" }) do
        isolated(function(replace)
            replace(_G, "GetBindLocation", function() return name end)
            t:assertNil(QR.Hearthstone:GetDestination(), "Name '" .. name .. "' is not guessed or partially matched")
        end)
    end
    isolated(function(replace)
        replace(_G, "issecretvalue", function(value) return value == "Testgasthaus" end)
        t:assertNil(QR.Hearthstone:GetDestination(), "Secret bind names are not compared or indexed")
    end)
end)

T:run("Hearthstone inns: missing or throwing APIs safely recover after entering the world", function(t)
    for _, getter in ipairs({ false, function() error("Unavailable") end }) do
        isolated(function(replace)
            replace(C_Map, "GetAreaInfo", getter or nil)
            t:assertNil(QR.Hearthstone:GetDestination(), "Unavailable area names do not cause a Lua error or guess")
            replace(C_Map, "GetAreaInfo", function() return "Testgasthaus" end)
            QR.Hearthstone:OnEvent("PLAYER_ENTERING_WORLD", true, false)
            t:assertNotNil(QR.Hearthstone:GetDestination(), "Available localized data is retried after entering the world")
        end)
    end
end)

T:run("Hearthstone inns: malformed coordinates cannot create or disambiguate a destination", function(t)
    for _, value in ipairs({ -0.1, 1.1, math.huge, 0/0, "0.5" }) do
        isolated(function()
            QR.HearthstoneLocations[1].x = value
            t:assertNil(QR.Hearthstone:GetDestination(), "Invalid coordinate is rejected")
        end)
    end
    isolated(function(replace)
        QR.HearthstoneLocations[2] = { areaID = 900002, mapID = 84, x = -1, y = 0.7 }
        replace(C_Map, "GetAreaInfo", function() return "Testgasthaus" end)
        t:assertNil(QR.Hearthstone:GetDestination(), "An invalid second candidate cannot make the first look unique")
    end)
end)

T:run("Hearthstone inns: repeated lookups reuse localized names and do not share mutable results", function(t)
    isolated(function(replace)
        local calls = 0
        replace(C_Map, "GetAreaInfo", function() calls = calls + 1; return "Testgasthaus" end)
        local point = QR.Hearthstone:GetDestination()
        t:assertNotNil(point, "Initial known inn is resolved")
        if point then point.x = 0.99 end
        for _ = 1, 100 do QR.Hearthstone:GetDestination() end
        t:assertEqual(1, calls, "Each area's localized name is read once, not once per route or item")
        t:assertEqual(0.43, QR.Hearthstone:GetDestination() and QR.Hearthstone:GetDestination().x,
            "Mutating a result cannot corrupt the next lookup")
    end)
end)

T:run("Hearthstone inns: a known inn tooltip describes the approximation instead of requiring first use", function(t)
    isolated(function(replace)
        replace(QR.PlayerInventory, "HasTeleport", function(_, id) return id == 6948 end)
        replace(QR.TeleportPanel, "GetItemLocationInfo", function() return nil end)
        local lines = {}
        replace(_G, "GameTooltip", {
            SetOwner = function() end, SetItemByID = function() end, Show = function() end,
            AddLine = function(_, text) lines[#lines + 1] = text end,
        })
        local entry
        for _, candidate in ipairs(QR.TeleportPanel:CollectAllTeleports()) do
            if candidate.id == 6948 then entry = candidate; break end
        end
        t:assertNotNil(entry, "Owned hearthstone is displayed in the normal teleport panel")
        local row = CreateFrame("Frame")
        row.entry, row.teleportID, row.isSpell = entry, 6948, false
        QR.TeleportPanel:ConfigureRowTooltip(row)
        row:GetScript("OnEnter")(row)
        local text = table.concat(lines, "\n")
        t:assert(text:find(QR.L["HEARTH_DESTINATION_CATALOG_HINT"], 1, true) ~= nil,
            "Real hover handler explains the automatically inferred approximate destination")
        t:assert(text:find(QR.L["HEARTH_DESTINATION_HINT"], 1, true) == nil,
            "Known inns do not tell the user that first use is required")
    end)
end)
