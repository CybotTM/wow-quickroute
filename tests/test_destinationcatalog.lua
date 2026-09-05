local T, QR, MockWoW = ...

local function withCatalog(fn)
    local cat = QR.Catalog
    local saved = { source = QR.DestinationCatalog, faction = MockWoW.config.playerFaction,
        completed = C_QuestLog.IsQuestFlaggedCompleted, title = C_QuestLog.GetTitleForQuestID,
        professions = _G.GetProfessions, professionInfo = _G.GetProfessionInfo,
        reputation = _G.C_Reputation, major = _G.C_MajorFactions, level = _G.UnitLevel,
        poi = QR.POIRouting, wi = QR.WaypointIntegration, tooltip = _G.C_TooltipInfo }
    QR.DestinationCatalog = {
        vendors = {
            { npcID = 10, name = "Token Seller", mapID = 84, x = 0.3, y = 0.5, currencyID = 2003, requirements = { r = 2 } },
            { npcID = 11, name = "Locked Seller", mapID = 84, x = 0.4, y = 0.5, currencyID = 2003,
                requirements = { questGroups = { { ids = {100}, required = 1 } } } },
            { npcID = 12, name = "Horde Seller", mapID = 85, x = 0.4, y = 0.5, currencyID = 2003, requirements = { r = 1 } },
        },
        quests = {
            { questID = 100, name = "A Helping Hand", mapID = 84, x = 0.3, y = 0.5, role = "giver", requirements = {} },
            { questID = 101, name = "A Helping Hand Again", mapID = 84, x = 0.4, y = 0.5, role = "reference", requirements = {} },
            { questID = 102, name = "Completed Story", mapID = 84, x = 0.5, y = 0.5, role = "giver", requirements = {} },
            { questID = 103, name = "Daily Completed Story", mapID = 84, x = 0.5, y = 0.5, role = "giver", repeatable = true, requirements = {} },
        },
        npcs = {
            { npcID = 20, name = "Test Quartermaster", mapID = 85, x = 0.3, y = 0.5, requirements = {} },
            { npcID = 21, name = "Invalid Coordinates", mapID = 85, x = 2, y = 0.5, requirements = {} },
        },
    }
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
    C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 102 or id == 103 end
    C_QuestLog.GetTitleForQuestID = function() return nil end
    _G.C_TooltipInfo = nil
    cat:Reset()
    local ok, err = pcall(fn, cat)
    QR.DestinationCatalog = saved.source
    C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetTitleForQuestID = saved.completed, saved.title
    _G.GetProfessions, _G.GetProfessionInfo, _G.UnitLevel = saved.professions, saved.professionInfo, saved.level
    _G.C_Reputation, _G.C_MajorFactions, _G.C_TooltipInfo = saved.reputation, saved.major, saved.tooltip
    QR.POIRouting, QR.WaypointIntegration = saved.poi, saved.wi
    MockWoW.config.playerFaction = saved.faction
    QR.PlayerInfo:InvalidateCache()
    cat:Reset()
    if not ok then error(err) end
end

T:run("Destination catalogue: unvisited vendors require faction and actual unlocks", function(t)
    withCatalog(function(cat)
        local vendors = cat:GetCurrencyLocations(2003)
        t:assertEqual(1, #vendors, "Only accessible Alliance vendor is listed before visits")
        t:assertEqual("catalogue", vendors[1].source, "Reference provenance is retained")
        C_QuestLog.IsQuestFlaggedCompleted = function() return true end
        cat:Reset()
        t:assertEqual(2, #cat:GetCurrencyLocations(2003), "Quest completion unlocks the second vendor")
        t:assertEqual(0, #cat:GetCurrencyLocations(99999), "Unsupported currency has no fabricated vendors")
    end)
end)

T:run("Destination catalogue: prerequisite groups preserve any and all semantics", function(t)
    withCatalog(function(cat)
        C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 2 or id == 3 end
        local req = { questGroups = { {ids = {1, 2}, required = 1}, {ids = {3, 4}, required = 2} } }
        t:assertFalse(cat:CheckRequirements(req), "Child all-group still needs quest 4")
        req.questGroups[2].required = 1
        t:assertTrue(cat:CheckRequirements(req), "One completed alternative in each inherited group is sufficient")
        C_QuestLog.IsQuestFlaggedCompleted = nil
        t:assertFalse(cat:CheckRequirements(req), "Unavailable quest API never grants gated access")
    end)
end)

T:run("Destination catalogue: profession uses skill line and all reputation gates", function(t)
    withCatalog(function(cat)
        _G.GetProfessions = function() return 1 end
        _G.GetProfessionInfo = function() return "Tailoring", 1, 100, 100, 0, 0, 197 end
        t:assertTrue(cat:CheckRequirements({ requireSkill = 197 }), "Base tailoring skill line satisfies profession gate")
        t:assertFalse(cat:CheckRequirements({ requireSkill = 3908 }), "Recipe spell ID does not masquerade as profession")
        _G.C_MajorFactions = { GetMajorFactionData = function() return nil end }
        _G.C_Reputation = { GetFactionDataByID = function(id) return { currentStanding = id == 1 and 42000 or 0 } end }
        local rules = { {kind = "minReputation", values = {1, 42000}}, {kind = "minReputation", values = {2, 9000}} }
        t:assertFalse(cat:CheckRequirements({ reputationRules = rules }), "A child reputation gate does not discard its parent")
        rules[2].values[2] = 0
        t:assertTrue(cat:CheckRequirements({ reputationRules = rules }), "Both explicit standing requirements are satisfied")
    end)
end)

T:run("Destination catalogue: search is indexed, bounded and role aware", function(t)
    withCatalog(function(cat)
        local results, more = cat:Search("help", 85, 1)
        t:assertEqual(1, #results, "Explicit result cap is respected")
        t:assertTrue(more, "Additional matches ask player to narrow the search")
        t:assertEqual("giver", results[1].role, "Giver role is retained rather than claiming an objective")
        results = cat:Search("helping hand again", 85)
        t:assertEqual(1, #results, "Extending the query filters prior matches")
        t:assertEqual("reference", results[1].role, "Generic source coordinate stays a reference")
        t:assertEqual(1, #cat._searchCache.matches, "Query refinement retains only one candidate")
        t:assertEqual(1, #cat:Search("", 85), "Empty query uses the current-map index and rejects bad coordinates")
        t:assertEqual(0, #cat:Search("a", 84), "One-character global search does not scan the catalogue")
        t:assertEqual(0, #cat:Search("102", 84), "Completed one-time quests are hidden")
        t:assertEqual(1, #cat:Search("103", 84), "Repeatable quests remain searchable after prior completion")
        t:assertEqual(1, #cat:GetQuestLocations(102, "giver", true), "Explicit quest-ID giver lookup can find a completed quest reference")
        cat:Search("10", 84)
        t:assertEqual(1, #cat:Search("100", 84), "Extending an exact numeric ID searches beyond earlier numeric matches")
    end)
end)

T:run("Destination catalogue: visible names use localized live game data", function(t)
    withCatalog(function(cat)
        local quest = cat:GetQuestLocations(100)[1]
        C_QuestLog.GetTitleForQuestID = function() return "Eine helfende Hand" end
        t:assertEqual("Eine helfende Hand", cat:GetDisplayName(quest), "Loaded localized quest title overrides source English")
        local calls = 0
        _G.C_TooltipInfo = { GetHyperlink = function() calls = calls + 1; return { lines = {{ leftText = "Rüstmeister" }} } end }
        local npc = cat:Search("quartermaster")[1]
        t:assertEqual("Rüstmeister", cat:GetDisplayName(npc), "NPC tooltip provides localized display name")
        cat:GetDisplayName(npc)
        t:assertEqual(1, calls, "NPC name lookup is cached after resolution")
    end)
end)

T:run("Destination catalogue: newly resolved translations invalidate earlier empty search refinements", function(t)
    withCatalog(function(cat)
        t:assertEqual(0, #cat:Search("helf"), "Unresolved German text initially has no source-language match")
        C_QuestLog.GetTitleForQuestID = function() return "Eine helfende Hand" end
        cat:GetDisplayName(cat:GetQuestLocations(100)[1])
        t:assertEqual(1, #cat:Search("helfende"), "Newly localized title is found when extending a formerly empty query")
        local first = cat:Search("quartermaster")[1]
        _G.C_TooltipInfo = {GetHyperlink=function()return {lines={{leftText="Rüstmeister"}}}end}
        cat:GetDisplayName(first)
        local duplicate = {npcID=first.npcID,name="Other source name",searchName="other source name",mapID=84,x=.1,y=.2,requirements={}}
        cat.searchRows[#cat.searchRows+1] = duplicate
        t:assertEqual(2, #cat:Search("rüstmeister"), "A translated NPC name also finds its independently recorded second location")
    end)
end)

T:run("Destination catalogue: live objective routing never substitutes a giver", function(t)
    withCatalog(function(cat)
        local routed
        QR.POIRouting = { RouteToMapPosition = function(_, mapID, x) routed = { mapID, x } end }
        QR.WaypointIntegration = { GetQuestWaypoint = function() return nil end }
        t:assertFalse(cat:RouteToQuest(100, "target"), "Missing live target remains unavailable despite a known giver")
        t:assertNil(routed, "No false giver route is published as quest target")
        QR.WaypointIntegration.GetQuestWaypoint = function() return {mapID = 85, x = 0.7, y = 0.6} end
        t:assertTrue(cat:RouteToQuest(100, "target"), "Live target routes when game provides a coordinate")
        t:assertEqual(85, routed[1], "Live target's map is preserved")
    end)
end)
