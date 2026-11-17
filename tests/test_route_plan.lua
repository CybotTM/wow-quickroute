-------------------------------------------------------------------------------
-- test_route_plan.lua
-- The route tab as a travel plan (design E of 2026-11-17): continent headers
-- between the steps, a timeline rail with a node per step, the current step
-- marked "Now", and the summary column with labelled actions.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local UI = QR.UI

local function setupUI()
    MockWoW:ClearComputedBounds()
    if not QR.MainFrame.frame then QR.MainFrame:CreateFrame() end
    QR.MainFrame.initialized = true
    if not UI.frame then UI:CreateContent(QR.MainFrame:GetContentFrame("route")) end
    UI.initialized = true
    UI.isCalculating = false
    MockWoW.config.inCombatLockdown = false
    UI:ClearStepLabels()
    return UI.frame
end

-- Stormwind (84) and Elwynn Forest (37) are on one continent, Valdrakken
-- (2112) and Zaralek Cavern (2133) on another.
local function crossContinentRoute(firstType)
    return {
        waypoint = { title = "Aberrus", mapID = 2133, x = 0.5, y = 0.5 },
        totalTime = 104,
        steps = {
            { type = firstType or "walk", to = "Portal Room", localizedTo = "Portal Room", time = 4,
              fromMapID = 84, destMapID = 84, destX = 0.487, destY = 0.936,
              teleportID = firstType == "teleport" and 6948 or nil, sourceType = "item" },
            { type = "portal", to = "Valdrakken", localizedTo = "Valdrakken", time = 10,
              fromMapID = 84, destMapID = 2112, destX = 0.5, destY = 0.5 },
            { type = "walk", to = "Zaralek Cavern", localizedTo = "Zaralek Cavern", time = 90,
              fromMapID = 2112, destMapID = 2133, destX = 0.5, destY = 0.5 },
        },
    }
end

local function visibleHeaders()
    local list = {}
    for _, header in ipairs(UI.groupHeaders) do
        if header:IsShown() then list[#list + 1] = header end
    end
    return list
end

T:run("RoutePlan: the test maps sit on two different continents", function(t)
    local ek, isles = QR.GetContinentForZone(84), QR.GetContinentForZone(2112)
    t:assertNotNil(ek, "Stormwind has a continent")
    t:assertNotNil(isles, "Valdrakken has a continent")
    t:assertEqual(ek, QR.GetContinentForZone(37), "Elwynn Forest shares Stormwind's")
    t:assertTrue(ek ~= isles, "the two differ")
end)

T:run("RoutePlan: steps split into one group per continent, by where they start", function(t)
    local groups = UI:BuildContinentGroups(crossContinentRoute().steps)
    t:assertEqual(2, #groups, "two continents, two groups")
    t:assertEqual(1, groups[1].first, "the first group starts at step 1")
    t:assertEqual(2, groups[1].last, "and holds the portal, which starts in Stormwind")
    t:assertEqual(3, groups[2].first, "the second starts in Valdrakken")
    t:assertEqual(14, groups[1].time, "group time adds its steps")
    t:assertEqual(QR.GetLocalizedContinentName(QR.GetContinentForZone(2112)), groups[2].name,
        "the group carries the continent's display name")
end)

T:run("RoutePlan: a step on an unknown map joins the group before it", function(t)
    local steps = crossContinentRoute().steps
    steps[2].fromMapID, steps[2].destMapID = 999999, 999999
    local groups = UI:BuildContinentGroups(steps)
    t:assertEqual(2, #groups, "no group of its own")
    t:assertEqual(2, groups[1].last, "it stays with the step before")
end)

T:run("RoutePlan: the list shows a header above each continent's first step", function(t)
    local frame = setupUI()
    UI:UpdateRoute(crossContinentRoute())
    -- Pooled frames keep bounds cached by an earlier test.
    MockWoW:ClearComputedBounds()
    for _, f in ipairs(UI.stepLabels) do f._computedBounds = nil end
    for _, f in ipairs(UI.groupHeaders) do f._computedBounds = nil end
    local headers = visibleHeaders()
    t:assertEqual(2, #headers, "two headers")
    local h1 = MockWoW:ComputeFrameBounds(headers[1])
    local row1 = MockWoW:ComputeFrameBounds(UI.stepLabels[1])
    local h2 = MockWoW:ComputeFrameBounds(headers[2])
    local row3 = MockWoW:ComputeFrameBounds(UI.stepLabels[3])
    local row2 = MockWoW:ComputeFrameBounds(UI.stepLabels[2])
    if h1 and row1 and h2 and row2 and row3 then
        t:assertGreaterThan(h1.bottom + 1, row1.top, "header 1 sits above step 1")
        t:assertGreaterThan(row2.bottom + 1, h2.top, "header 2 sits below step 2")
        t:assertGreaterThan(h2.bottom + 1, row3.top, "and above step 3")
    end
    local text = headers[1].label:GetText()
    t:assertTrue(text:find(QR.GetLocalizedContinentName(QR.GetContinentForZone(84)), 1, true) ~= nil,
        "header 1 names the continent")
    t:assertTrue(text:find(string.format(QR.L["ROUTE_PANEL_STEPS"], 2), 1, true) ~= nil, "and its step count")
    UI:ClearStepLabels()
    t:assertEqual(0, #visibleHeaders(), "clearing the route hides the headers")
    t:assertFalse(frame.summaryPanel:IsShown(), "and the summary column")
end)

T:run("RoutePlan: the current step reads Now, has a gold node and a tinted row", function(t)
    setupUI()
    UI:UpdateRoute(crossContinentRoute())
    local current = UI.currentStepFrame
    t:assertEqual(UI.stepLabels[1], current, "step 1 is current")
    t:assertTrue(current.label:GetText():find(QR.L["ROUTE_NOW"] .. ":", 1, true) ~= nil, "its text starts with Now")
    t:assertTrue(current.highlight:IsShown(), "its row is tinted")
    t:assertTrue(current.node:IsShown(), "it has a node on the rail")
    local upcoming = UI.stepLabels[2]
    t:assertFalse(upcoming.highlight:IsShown(), "the next row is not tinted")
    t:assertTrue(upcoming.label:GetText():find("^2%. ") ~= nil, "and keeps its number")
    t:assertTrue(upcoming.rail:IsShown(), "the rail runs through the middle rows")
end)

T:run("RoutePlan: the summary column shows the time, the step count and the next action", function(t)
    local frame = setupUI()
    UI:UpdateRoute(crossContinentRoute())
    local panel = frame.summaryPanel
    t:assertTrue(panel:IsShown(), "the column is shown")
    t:assertEqual(QR.CooldownTracker:FormatTime(104), panel.timeValue:GetText(), "total travel time")
    local detail = panel.timeDetail:GetText()
    t:assertTrue(detail:find(string.format(QR.L["ROUTE_PANEL_STEPS"], 3), 1, true) ~= nil, "three steps")
    t:assertTrue(detail:find(string.format(QR.L["ROUTE_PANEL_CONTINENTS"], 2), 1, true) ~= nil, "two continents")
    local action = UI:BuildStepCardTexts(crossContinentRoute().steps[1])
    t:assertEqual(action, panel.nextText:GetText(), "the current step's action")
    t:assertTrue(panel.navAction:IsShown(), "Set waypoint is offered")
    t:assertFalse(panel.useAction:IsShown(), "Use only for a teleport step")
end)

T:run("RoutePlan: Set waypoint in the column acts on the current step", function(t)
    local frame = setupUI()
    UI:UpdateRoute(crossContinentRoute())
    local set
    local saved = QR.WaypointIntegration.SetTomTomWaypoint
    QR.WaypointIntegration.SetTomTomWaypoint = function(_, mapID, x, y) set = { mapID, x, y } end
    local ok, err = pcall(function()
        frame.summaryPanel.navAction:GetScript("OnClick")(frame.summaryPanel.navAction)
    end)
    QR.WaypointIntegration.SetTomTomWaypoint = saved
    if not ok then error(err, 0) end
    local nav = UI.currentStepFrame.navButton
    t:assertNotNil(set, "a waypoint was set")
    t:assertEqual(nav.destMapID, set and set[1], "on the current step's map")
    t:assertEqual(nav.destX, set and set[2], "at its x")
end)

T:run("RoutePlan: Step not possible in the column refuses the current step", function(t)
    local frame = setupUI()
    local pc = QR.PathCalculator
    local savedPairs = pc.StepEdgePairs
    pc.StepEdgePairs = function() return { { from = "A", to = "B" } } end
    local refused
    local ok, err = pcall(function()
        UI:UpdateRoute(crossContinentRoute())
        local reject = UI.currentStepFrame.rejectButton
        t:assertTrue(reject ~= nil and reject:IsShown(), "the current row offers a refusal")
        t:assertTrue(frame.summaryPanel.rejectAction:IsShown(), "so the column offers it too")
        reject:SetScript("OnClick", function() refused = true end)
        frame.summaryPanel.rejectAction:GetScript("OnClick")(frame.summaryPanel.rejectAction)
    end)
    pc.StepEdgePairs = savedPairs
    if not ok then error(err, 0) end
    t:assertTrue(refused, "the click reaches the current row's refusal")
    UI:UpdateRoute(crossContinentRoute())
    local row = UI.currentStepFrame.rejectButton
    t:assertEqual(row ~= nil and row:IsShown(), frame.summaryPanel.rejectAction:IsShown(),
        "without a connection to refuse, the column hides it with the row")
end)

T:run("RoutePlan: a teleport step gets Use with a secure overlay, released with the route", function(t)
    local frame = setupUI()
    MockWoW.config.bagItems = { [6948] = { 0, 1, 1 } }
    MockWoW.config.itemCounts = { [6948] = 1 }
    UI:UpdateRoute(crossContinentRoute("teleport"))
    local panel = frame.summaryPanel
    t:assertTrue(panel.useAction:IsShown(), "Use is offered")
    t:assertNotNil(panel.secureUse, "a secure button covers it")
    t:assertEqual(6948, panel.secureUse and panel.secureUse.teleportID, "for the step's teleport")
    local secure = panel.secureUse
    UI:ClearStepLabels()
    t:assertNil(panel.secureUse, "clearing the route drops it")
    t:assertFalse(secure.inUse, "and returns it to the pool")
end)

T:run("RoutePlan: in combat the column offers no Use", function(t)
    local frame = setupUI()
    MockWoW.config.inCombatLockdown = true
    local ok, err = pcall(function() UI:UpdateRoute(crossContinentRoute("teleport")) end)
    MockWoW.config.inCombatLockdown = false
    if not ok then error(err, 0) end
    t:assertFalse(frame.summaryPanel.useAction:IsShown(), "no Use under lockdown")
    t:assertNil(frame.summaryPanel.secureUse, "and no secure button taken")
    UI:ClearStepLabels()
end)
