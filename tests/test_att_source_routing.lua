local T, QR, MockWoW = ...

local function withATTSource(callback)
    local panel = QR.TeleportPanel
    local saved = { att = _G.AllTheThings, attc = _G.ATTC, catalog = QR.Catalog,
        reputation = _G.C_Reputation, major = _G.C_MajorFactions, secret = _G.issecretvalue,
        completed = C_QuestLog.IsQuestFlaggedCompleted, combat = MockWoW.config.inCombatLockdown }
    local reputation = 42000
    local ancestor = {mapID = 1970, awp = 90200, lvl = 60,
        parent = {mapID = 1550, awp = 90002, lvl = 50, parent = {mapID = 947}}}
    -- Installed ATT 5.3.8, db/Standard/Categories/Zones.lua:5-6:
    -- n(182257,{coords={[1970]={{34.8,64.1}}}, ... toy(190237,{b=1,minReputation=a[1555]}) ...})
    -- Shared a[1555] is {2478,42000}; this is Vilo's actual purchase source.
    local vendor = { npcID = 182257, name = "Vilo", coords = { [1970] = { {34.8,64.1} } },
        parent = {headerID = -58, parent = ancestor} }
    local source = { itemID = 190237, b = 1, minReputation = {2478,42000}, parent = vendor }
    local matches = {source}
    _G.AllTheThings = { SearchForField = function() return matches end,
        HeaderConstants = {VENDORS = -58},
        CurrentCharacterFilters = function(node) return not node.excluded end }
    _G.ATTC, _G.C_MajorFactions = nil, nil
    _G.C_Reputation = { GetFactionDataByID = function() return { currentStanding = reputation } end }
    C_QuestLog.IsQuestFlaggedCompleted = function() return true end
    QR.Catalog = { Initialize = function() end, byNPC = {}, IsAvailable = function() return true end,
        CheckRequirements = saved.catalog.CheckRequirements, GetQuestLocations = function() return {} end }
    MockWoW.config.inCombatLockdown = false
    local entry = { id = 190237, isSpell = false, data = {name = "Broker Translocation Matrix"} }
    local ok, err = pcall(callback, panel, entry, vendor, source, ancestor, matches,
        function(value) reputation = value end)
    _G.AllTheThings, _G.ATTC, QR.Catalog = saved.att, saved.attc, saved.catalog
    _G.C_Reputation, _G.C_MajorFactions, _G.issecretvalue = saved.reputation, saved.major, saved.secret
    C_QuestLog.IsQuestFlaggedCompleted = saved.completed
    MockWoW.config.inCombatLockdown = saved.combat
    if not ok then error(err) end
end

T:run("ATT source routing: Vilo's recorded coordinates work without a bundled NPC position", function(t)
    withATTSource(function(panel, entry, vendor)
        local point = panel:GetAcquisitionLocation(entry)
        t:assertEqual(1970, point and point.mapID, "Vilo routes to the recorded Zereth Mortis map")
        t:assertEqual(.348, point and point.x, "ATT's 34.8 percent x is normalized once")
        t:assertTrue(point and math.abs(point.y - .641) < .000001, "ATT's 64.1 percent y is normalized once")
        t:assertEqual(182257, point and point.npcID, "Route retains Vilo's NPC identity")
        t:assertEqual("Vilo", point and point.name, "Route names the actual source NPC")
        t:assertEqual("vendor", point and point.kind, "ATT's explicit vendor header identifies Vilo as a vendor")
        t:assertEqual(34.8, vendor.coords[1970][1][1], "Reading a source never rewrites ATT coordinates")
    end)
end)

T:run("ATT source routing: a generic NPC is not labeled as a vendor or granted a purchase exception", function(t)
    withATTSource(function(panel, entry, vendor, _, ancestor, _, setReputation)
        vendor.parent = ancestor
        local point = panel:GetATTSourceLocation(entry)
        t:assertEqual("npc", point and point.kind, "Unclassified NPC sources keep a neutral source kind")
        t:assertNil(point and point.purchaseRequirements, "An NPC alone does not establish a vendor purchase requirement")
        setReputation(0)
        t:assertNil(panel:GetATTSourceLocation(entry), "A drop/quest source cannot bypass its reputation restriction as a purchase gate")
        _G.AllTheThings.SearchForField = function() return {vendor} end
        point = panel:GetATTSourceLocation({id = 182257, isNPC = true})
        t:assertEqual("npc", point and point.kind, "Direct lookup of an accessible generic NPC remains available")
    end)
end)

T:run("ATT source routing: a quest reward under a vendor is not a vendor purchase", function(t)
    withATTSource(function(panel, entry, vendor, source, _, _, setReputation)
        source.parent = {questID = 123, parent = vendor}
        setReputation(0)
        t:assertNil(panel:GetATTSourceLocation(entry), "A quest reward cannot borrow the NPC's vendor purchase exception")
    end)
end)

T:run("ATT source routing: a missing purchase reputation does not hide an accessible vendor", function(t)
    withATTSource(function(panel, entry, _, source, ancestor, _, setReputation)
        setReputation(41999)
        local locked = panel:GetAcquisitionLocation(entry)
        t:assertEqual(182257, locked and locked.npcID, "Vilo can still be visited before reaching Exalted")
        t:assertFalse(locked and locked.purchaseAvailable, "Vendor route does not claim the toy can already be bought")
        local required = locked and locked.purchaseRequirements and locked.purchaseRequirements.minReputation
        t:assertEqual(2478, required and required[1], "Purchase hint retains the Enlightened faction identity")
        t:assertEqual(42000, required and required[2], "Purchase hint retains the exact Exalted requirement")
        setReputation(42000)
        local available = panel:GetAcquisitionLocation(entry)
        t:assertTrue(available and available.purchaseAvailable, "Exalted reputation satisfies the recorded purchase gate")
        source.lvl = 999
        t:assertNil(panel:GetAcquisitionLocation(entry), "The item's level requirement remains an access gate")
        source.lvl = nil
        source.sourceQuests = {999}
        C_QuestLog.IsQuestFlaggedCompleted = function() return false end
        t:assertNil(panel:GetAcquisitionLocation(entry), "The item's prerequisite quests remain access gates")
        source.sourceQuests = nil
        ancestor.minReputation = {2478,42001}
        t:assertNil(panel:GetAcquisitionLocation(entry), "Reputation restricting the vendor's ancestor remains an access gate")
        ancestor.minReputation = nil
        ancestor.sourceQuests = {123}
        C_QuestLog.IsQuestFlaggedCompleted = function() return false end
        t:assertNil(panel:GetAcquisitionLocation(entry), "Quest restrictions above the vendor still block routing")
        ancestor.sourceQuests = nil
        source.u = 2
        t:assertNil(panel:GetAcquisitionLocation(entry), "Removed item sources never gain routes from NPC coordinates")
        source.u = nil
        ancestor.excluded = true
        t:assertNil(panel:GetAcquisitionLocation(entry), "Current-character restrictions on ancestors are retained")
    end)
end)

T:run("ATT source routing: NPC names use the existing ATT cache without forcing a tooltip lookup", function(t)
    withATTSource(function(panel, entry, vendor)
        vendor.name = nil
        _G.AllTheThings.NPCNameFromID = setmetatable({[182257] = "Vilo"}, {
            __index = function() error("An uncached tooltip name must not be requested") end,
        })
        local point = panel:GetATTSourceLocation(entry)
        t:assertEqual("Vilo", point and point.name, "Source name comes from ATT's cached NPC name")
        _G.AllTheThings.NPCNameFromID[182257] = nil
        point = panel:GetATTSourceLocation(entry)
        t:assertEqual(string.format(QR.L["ACQUISITION_NPC_FALLBACK"], 182257), point and point.name,
            "Uncached source names use a localized NPC identity without invoking ATT tooltip code")
    end)
end)

T:run("ATT source routing: item and generic quest reference coordinates are not vendor locations", function(t)
    withATTSource(function(panel, entry, vendor, source)
        vendor.coords = nil
        source.coords = { [84] = { {50,50} } }
        t:assertNil(panel:GetAcquisitionLocation(entry), "The item's generic reference midpoint is never used")
        vendor.npcID, vendor.questID = nil, 123
        vendor.coords = { [84] = { {50,50} } }
        t:assertNil(panel:GetAcquisitionLocation(entry), "A quest reference does not establish its giver's position")
    end)
end)

T:run("ATT source routing: malformed and secret coordinates cannot become route destinations", function(t)
    withATTSource(function(panel, entry, vendor)
        local secret = {}
        _G.issecretvalue = function(value) return value == secret end
        for _, coords in ipairs({
            { [1970] = { {-1,64.1} } }, { [1970] = { {34.8,101} } },
            { [1970] = { {0/0,64.1} } }, { [1970] = { {34.8,math.huge} } },
            { [0] = { {34.8,64.1} } }, { [1970] = { {secret,64.1} } },
            { [1970] = secret }, { [1970] = { {34.8,64.1,1971} } },
        }) do
            vendor.coords = coords
            t:assertNil(panel:GetAcquisitionLocation(entry), "Invalid ATT coordinate data does not produce a route")
        end
    end)
end)

T:run("ATT source routing: fresh calls recheck changed coordinates and availability", function(t)
    withATTSource(function(panel, entry, vendor, _, _, _, setReputation)
        local first = panel:GetAcquisitionLocation(entry)
        vendor.coords[1970][1] = {40,60}
        local moved = panel:GetAcquisitionLocation(entry)
        t:assertEqual(.348, first and first.x, "An earlier result is a detached coordinate snapshot")
        t:assertEqual(.4, moved and moved.x, "A later route request observes changed source coordinates")
        setReputation(0)
        local locked = panel:GetAcquisitionLocation(entry)
        t:assertFalse(locked and locked.purchaseAvailable, "A later click rechecks the purchase reputation instead of reusing it")
    end)
end)

T:run("ATT source routing: direct NPC searches retain source identity and reject replacement nodes", function(t)
    withATTSource(function(panel, _, vendor)
        local indexed = vendor
        _G.AllTheThings.SearchForField = function(key, id)
            if key == "npcID" and id == 182257 then return {indexed} end
            return {}
        end
        local entry = {id = 182257, isNPC = true}
        local point = panel:GetATTSourceLocation(entry)
        t:assertEqual(182257, point and point.npcID, "Direct NPC search resolves Vilo's indexed source")
        t:assertEqual(vendor, point and point.attSourceNode, "Search result retains the validated source identity")
        indexed = {npcID = 182257, coords = vendor.coords}
        t:assertNil(panel:GetATTSourceLocation(entry, vendor), "A replaced indexed NPC cannot reuse an earlier result")
        vendor.u = 2
        indexed = vendor
        t:assertNil(panel:GetATTSourceLocation(entry, vendor), "A source newly marked removed is checked again on selection")
    end)
end)

T:run("ATT source routing: quest reward routes use independently indexed giver NPC coordinates", function(t)
    withATTSource(function(panel, entry, vendor, source)
        local quest = {questID = 123, qgs = {182257}, coords = {[84] = {{50,50}}}}
        source.parent = quest
        _G.AllTheThings.SearchForField = function(key, id)
            if key == "itemID" and id == entry.id then return {source} end
            if key == "npcID" and id == 182257 then return {vendor} end
            return {}
        end
        local point = panel:GetATTSourceLocation(entry)
        t:assertEqual(1970, point and point.mapID, "Quest reward routes to its giver's independently indexed map")
        t:assertEqual(.348, point and point.x, "Quest reward retains the giver's coordinate instead of the quest midpoint")
        vendor.parent = {sourceQuests = {999}}
        C_QuestLog.IsQuestFlaggedCompleted = function() return false end
        t:assertNil(panel:GetATTSourceLocation(entry), "The separate giver NPC's full ancestry is checked too")
    end)
end)

T:run("ATT source routing: direct NPC search never substitutes an ancestor NPC", function(t)
    withATTSource(function(panel, _, vendor)
        vendor.parent = {npcID = 99, coords = vendor.coords}
        vendor.coords = nil
        _G.AllTheThings.SearchForField = function() return {vendor} end
        t:assertNil(panel:GetATTSourceLocation({id = 182257, isNPC = true}), "Vilo cannot borrow a different NPC's location")
    end)
end)

T:run("ATT source routing: repeated quest alternatives have a bounded independent NPC lookup budget", function(t)
    withATTSource(function(panel, entry, _, _, _, matches)
        for index = 1, 12 do
            local qgs = {}
            for id = 1, 12 do qgs[id] = 1000 + index * 12 + id end
            matches[index] = {itemID = entry.id, parent = {questID = index, qgs = qgs}}
        end
        local npcQueries = 0
        _G.AllTheThings.SearchForField = function(key)
            if key == "itemID" then return matches end
            npcQueries = npcQueries + 1
            return {}
        end
        t:assertNil(panel:GetATTSourceLocation(entry), "Missing giver positions never fabricate a destination")
        t:assertEqual(12, npcQueries, "A single request performs at most 12 indexed giver lookups across all alternatives")
    end)
end)

T:run("ATT source routing: unavailable acquisition suppresses a static vendor fallback", function(t)
    withATTSource(function(panel, entry, _, source)
        for _, candidate in ipairs(panel:CollectAllTeleports()) do
            if candidate.status.key == "STATUS_MISSING" then entry.status = candidate.status; break end
        end
        entry.data.vendor = {mapID = 84, x = .5, y = .5}
        _G.AllTheThings.PhaseConstants = {REMOVED_FROM_GAME = 2, NEVER_IMPLEMENTED = 1}
        source.u = 2
        t:assertNil(panel:GetAcquisitionLocation(entry), "An unavailable item's stale static vendor cannot remain routable")
    end)
end)
