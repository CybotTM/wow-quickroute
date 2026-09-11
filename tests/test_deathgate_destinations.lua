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
    replace(Enum, "GarrisonType", { Type_7_0_Garrison = 3 })
    replace(_G, "C_Garrison", { HasGarrison = function(kind) return kind == 3 end })
    replace(C_QuestLog, "IsOnQuest", function() return false end)
    replace(C_Map, "GetBestMapForUnit", function() return 627 end)
    replace(QR.PlayerInfo, "GetClass", function() return "DEATHKNIGHT" end)
    replace(QR.PathCalculator, "graphDirty", false)
    replace(QR.TeleportDestinations, "deathGateUsable", false)
end

T:run("Death Gate: a Legion knight does not land in the Eastern Plaguelands", function(t)
    isolated(function(replace)
        setup(replace)
        local choices = QR.TeleportDestinations:GetDestinations(50977, QR.ClassTeleportSpells[50977])
        t:assertEqual(1, #choices, "Confirmed class hall gives one outward destination")
        if choices[1] then
            t:assertEqual(648, choices[1].mapID, "Legion Death Gate uses Acherus in the Broken Isles")
            t:assertEqual("Travel:ACHERUS", choices[1].nodeKey, "Landing connects to the modelled class-hall exit")
        end
        t:assertTrue(QR.ClassTeleportSpells[50977].isDynamic, "Catalogue does not promise a static Death Gate landing")
    end)
end)

T:run("Dynamic travel: the complete route prefers the cloak and then a nearer observed hearth", function(t)
    isolated(function(replace)
        setup(replace)
        replace(QR.PlayerInfo, "GetFaction", function() return "Alliance" end)
        replace(_G, "UnitFactionGroup", function() return "Alliance" end)
        replace(_G, "UnitLevel", function() return 90 end)
        replace(_G, "UnitGUID", function() return "Player-Route-Test" end)
        replace(_G, "GetBindLocation", function() return "Observed Inn" end)
        replace(_G, "C_TaxiMap", {})
        replace(C_Map, "GetPlayerMapPosition", function()
            return { GetXY = function() return 0.5, 0.5 end }
        end)
        replace(QR.db, "hearthstoneBinds", {})
        replace(QR.db, "maxCooldownHours", 24)
        replace(QR.db, "considerCooldowns", true)
        replace(QR.TravelTime, "CanFly", function() return false end)
        replace(QR.PlayerInventory, "GetAllTeleports", function()
            return {
                [50977] = { sourceType = "spell", data = QR.ClassTeleportSpells[50977] },
                [65360] = { sourceType = "item", data = QR.TeleportItemsData[65360] },
                [6948] = { sourceType = "item", data = QR.TeleportItemsData[6948] },
            }
        end)
        replace(QR.CooldownTracker, "GetCooldown", function()
            return { ready = true, remaining = 0, duration = 0 }
        end)
        -- Fresh calculator with the real methods and data, without inheriting
        -- another test's graph or lookup caches. No path result is stubbed.
        local calculator = { graphDirty = true }
        for key, value in pairs(QR.PathCalculator) do
            if type(value) == "function" then calculator[key] = value end
        end
        replace(QR, "PathCalculator", calculator)
        local stormwind = calculator:CalculatePath(84, 0.4965, 0.8725)
        t:assertNotNil(stormwind, "The character can reach Stormwind")
        t:assertEqual(65360, stormwind and stormwind.steps[1].teleportID, "Ready guild cloak beats Death Gate to Stormwind")
        local crypts = calculator:CalculatePath(2437, 0.254, 0.84)
        t:assertEqual(65360, crypts and crypts.steps[1].teleportID, "Unknown hearth does not displace the known cloak route")
        -- This is an observed test fixture, not a claimed coordinate for any
        -- real inn. The target is the known Twilight Crypts outdoor entrance.
        QR.db.hearthstoneBinds["Player-Route-Test"] = {
            mapID = 2395, x = 0.45, y = 0.5, bindName = "Observed Inn", source = "HEARTHSTONE_ARRIVAL",
        }
        calculator.graphDirty = true
        local nearer = calculator:CalculatePath(2437, 0.254, 0.84)
        t:assertEqual(6948, nearer and nearer.steps[1].teleportID, "A nearer observed hearth is selected over both alternatives")
        t:assert(nearer and crypts and nearer.totalTime < crypts.totalTime, "Selected hearth reduces the complete route estimate")
    end)
end)

T:run("Death Gate: unknown progress and special destinations are never guessed", function(t)
    isolated(function(replace)
        setup(replace)
        local data = QR.ClassTeleportSpells[50977]
        replace(C_Garrison, "HasGarrison", function() return false end)
        t:assertEqual(0, #QR.TeleportDestinations:GetDestinations(50977, data), "No hall is not proof of the old Acherus phase")
        replace(C_Garrison, "HasGarrison", function() error("API unavailable") end)
        t:assertEqual(0, #QR.TeleportDestinations:GetDestinations(50977, data), "An unavailable API cannot grant a destination")
        replace(C_Garrison, "HasGarrison", function() return true end)
        replace(C_QuestLog, "IsOnQuest", function(id) return id == 38990 end)
        t:assertEqual(0, #QR.TeleportDestinations:GetDestinations(50977, data), "The Icecrown artifact diversion is not the class hall")
        replace(C_QuestLog, "IsOnQuest", function() return false end)
        for _, mapID in ipairs({647, 648}) do
            replace(C_Map, "GetBestMapForUnit", function() return mapID end)
            t:assertEqual(0, #QR.TeleportDestinations:GetDestinations(50977, data), "Acherus floor " .. mapID .. " uses an unknown return point")
        end
    end)
end)

T:run("Death Gate: progression changes invalidate only an affected knight's graph", function(t)
    isolated(function(replace)
        setup(replace)
        local frame = QR.TeleportDestinations.frame
        local event = frame and frame:GetScript("OnEvent")
        t:assertNotNil(event, "Destination observer is initialized")
        if not event then return end
        event(frame, "QUEST_TURNED_IN", 38990)
        t:assertTrue(QR.PathCalculator.graphDirty, "Finishing the artifact diversion updates the outward route")
        replace(QR.PathCalculator, "graphDirty", false)
        event(frame, "QUEST_ACCEPTED", 99999)
        t:assertFalse(QR.PathCalculator.graphDirty, "An unrelated quest leaves an unchanged destination graph intact")
        replace(QR.TeleportDestinations, "deathGateUsable", false)
        event(frame, "PLAYER_ENTERING_WORLD", false, false)
        t:assertTrue(QR.PathCalculator.graphDirty, "A class hall becoming available after loading updates the route")
        replace(QR.PathCalculator, "graphDirty", false)
        replace(QR.TeleportDestinations, "deathGateUsable", false)
        replace(QR.PlayerInfo, "GetClass", function() return "MAGE" end)
        event(frame, "QUEST_ACCEPTED", 38990)
        t:assertFalse(QR.PathCalculator.graphDirty, "Other classes do not rebuild for a Death Gate phase change")
    end)
end)
