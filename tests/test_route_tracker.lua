-------------------------------------------------------------------------------
-- test_route_tracker.lua
-- The compact route tracker (design F of 2026-11-17): the switch between the
-- window and the tracker, which requests open which view, the tracker's own
-- saved position, and what it shows for a route.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local RT = QR.RouteTracker
local MF = QR.MainFrame

local function route(firstType, extra)
    local steps = {
        { type = firstType or "walk", to = "Portal Room", localizedTo = "Portal Room", time = 4,
          fromMapID = 84, destMapID = 84, destX = 0.487, destY = 0.936,
          teleportID = firstType == "teleport" and 6948 or nil, sourceType = "item" },
        { type = "portal", to = "Valdrakken", localizedTo = "Valdrakken", time = 10,
          fromMapID = 84, destMapID = 2112, destX = 0.5, destY = 0.5 },
        { type = "walk", to = "Zaralek Cavern", localizedTo = "Zaralek Cavern", time = 90,
          fromMapID = 2112, destMapID = 2133, destX = 0.5, destY = 0.5 },
    }
    for i = 1, (extra or 0) do
        steps[#steps + 1] = { type = "walk", to = "Extra " .. i, localizedTo = "Extra " .. i, time = 5,
            fromMapID = 2133, destMapID = 2133, destX = 0.5, destY = 0.5 }
    end
    return { waypoint = { title = "Aberrus", mapID = 2133, x = 0.5, y = 0.5 }, totalTime = 104, steps = steps }
end

local function withTracker(fn)
    local savedDB = QR.db
    QR.db = setmetatable({}, { __index = savedDB })
    MockWoW.config.inCombatLockdown = false
    if not MF.frame then MF:CreateFrame() end
    MF.initialized = true
    if not QR.UI.frame then QR.UI:CreateContent(MF:GetContentFrame("route")) end
    QR.UI.initialized = true
    local savedRefresh = QR.UI.RefreshRoute
    local refreshes = 0
    QR.UI.RefreshRoute = function() refreshes = refreshes + 1 end
    RT:CreateFrame()
    local ok, err = pcall(fn, function() return refreshes end)
    QR.UI.RefreshRoute = savedRefresh
    RT:Hide()
    MF:Hide("test")
    QR.db = savedDB
    if not ok then error(err, 0) end
end

local function lineTexts()
    local texts = {}
    for _, line in ipairs(RT.lines) do texts[#texts + 1] = line:GetText() end
    return texts
end

local function anyLine(pattern)
    for _, text in ipairs(lineTexts()) do
        if text:find(pattern, 1, true) then return true end
    end
    return false
end

T:run("RouteTracker: the window is the default view", function(t)
    withTracker(function()
        t:assertEqual(RT.MODE_WINDOW, RT:GetMode(), "window mode by default")
        MF:Show("route", "poi-routing")
        t:assertTrue(MF.isShowing, "a route request opens the window")
        t:assertFalse(RT.isShowing, "and not the tracker")
    end)
end)

T:run("RouteTracker: Compact closes the window and opens the tracker", function(t)
    withTracker(function()
        MF:Show("route", "test")
        QR.UI.frame.compactButton:GetScript("OnClick")(QR.UI.frame.compactButton)
        t:assertEqual(RT.MODE_COMPACT, QR.db.routeViewMode, "compact mode is saved")
        t:assertFalse(MF.isShowing, "the window is closed")
        t:assertTrue(RT.isShowing, "the tracker is open")
    end)
end)

T:run("RouteTracker: in compact mode route requests open the tracker, teleports the window", function(t)
    withTracker(function(refreshes)
        QR.db.routeViewMode = RT.MODE_COMPACT
        local before = refreshes()
        for _, reason in ipairs({ "poi-routing", "minimap-left", "slash-qr-show", "waypoint-auto:test" }) do
            RT:Hide()
            MF:Show("route", reason)
            t:assertFalse(MF.isShowing, reason .. ": the window stays closed")
            t:assertTrue(RT.isShowing, reason .. ": the tracker opens")
        end
        t:assertGreaterThan(refreshes(), before, "the route is still calculated")
        MF:Show("teleports", "minimap-right")
        t:assertTrue(MF.isShowing, "the Teleports tab opens the window")
        MF:Hide("test")
        MF:Show("route", "screenshot")
        t:assertTrue(MF.isShowing, "a screenshot gets the window")
    end)
end)

T:run("RouteTracker: in compact mode toggling the route toggles the tracker", function(t)
    withTracker(function()
        QR.db.routeViewMode = RT.MODE_COMPACT
        RT:Hide()
        MF:Toggle("route", "minimap-left")
        t:assertTrue(RT.isShowing, "the first toggle opens the tracker")
        MF:Toggle("route", "minimap-left")
        t:assertFalse(RT.isShowing, "the second closes it")
        t:assertFalse(MF.isShowing, "the window never opened")
    end)
end)

T:run("RouteTracker: Window switches back and opens the window on the route", function(t)
    withTracker(function()
        QR.db.routeViewMode = RT.MODE_COMPACT
        RT:Show()
        RT.frame.windowButton:GetScript("OnClick")(RT.frame.windowButton)
        t:assertEqual(RT.MODE_WINDOW, QR.db.routeViewMode, "window mode is saved")
        t:assertFalse(RT.isShowing, "the tracker is closed")
        t:assertTrue(MF.isShowing, "the window is open")
        t:assertEqual("route", MF.activeTab, "on the route tab")
    end)
end)

T:run("RouteTracker: the tracker saves its position apart from the window's", function(t)
    withTracker(function()
        QR.db.mainFramePoint, QR.db.mainFrameX = "CENTER", 11
        local frame = RT.frame
        -- The mock's GetPoint drops offsets; this frame reports where it was dropped.
        local savedGetPoint = frame.GetPoint
        frame.GetPoint = function() return "TOPLEFT", UIParent, "TOPLEFT", 120, -80 end
        frame:GetScript("OnDragStop")(frame)
        frame.GetPoint = savedGetPoint
        t:assertEqual("TOPLEFT", QR.db.trackerPoint, "tracker point saved")
        t:assertEqual(120, QR.db.trackerX, "tracker x saved")
        t:assertEqual(-80, QR.db.trackerY, "tracker y saved")
        t:assertEqual("CENTER", QR.db.mainFramePoint, "the window's point is untouched")
        t:assertEqual(11, QR.db.mainFrameX, "the window's x is untouched")
        local old = RT.frame
        RT.frame = nil
        RT:CreateFrame()
        local p = RT.frame._points[1] or {}
        local point, x, y = p[1], p[4], p[5]
        t:assertEqual("TOPLEFT", point, "a new tracker frame comes back at the saved point")
        t:assertEqual(120, x, "at the saved x")
        t:assertEqual(-80, y, "at the saved y")
        RT.frame:Hide()
        RT.frame = old
    end)
end)

T:run("RouteTracker: shows the time, the destination, continents and the current step", function(t)
    withTracker(function()
        RT:Show()
        RT:Update(route())
        t:assertTrue(RT.frame.title:GetText():find(QR.CooldownTracker:FormatTime(104), 1, true) ~= nil,
            "the title carries the travel time")
        t:assertTrue(anyLine("Aberrus"), "the destination is listed")
        t:assertTrue(anyLine(QR.GetLocalizedContinentName(QR.GetContinentForZone(84))), "the first continent")
        t:assertTrue(anyLine(QR.GetLocalizedContinentName(QR.GetContinentForZone(2112))), "the second continent")
        local current = QR.UI:BuildStepCardTexts(route().steps[1])
        t:assertTrue(anyLine("> " .. QR.Colors.R .. current), "the current step leads with >")
        t:assertTrue(RT.frame.action:IsShown(), "with its action")
    end)
end)

T:run("RouteTracker: a long route lists five steps ahead and counts the rest", function(t)
    withTracker(function()
        RT:Show()
        RT:Update(route(nil, 6), 1)
        t:assertTrue(anyLine(string.format(QR.L["TRACKER_MORE_STEPS"], 3)), "nine steps: current, five ahead, three more")
    end)
end)

T:run("RouteTracker: a walk step's action sets the waypoint", function(t)
    withTracker(function()
        RT:Show()
        RT:Update(route())
        local set
        local saved = QR.WaypointIntegration.SetTomTomWaypoint
        QR.WaypointIntegration.SetTomTomWaypoint = function(_, mapID, x, y) set = { mapID, x, y } end
        local ok, err = pcall(function() RT.frame.action:GetScript("OnClick")(RT.frame.action) end)
        QR.WaypointIntegration.SetTomTomWaypoint = saved
        if not ok then error(err, 0) end
        local anchor = QR.PathCalculator:SelectStepAnchor(route().steps[1])
        t:assertEqual(anchor.mapID, set and set[1], "on the current step's map")
        t:assertNil(RT.secureAction, "no secure button for a walk")
    end)
end)

T:run("RouteTracker: a teleport step's action is a secure overlay, released on hide", function(t)
    withTracker(function()
        RT:Show()
        RT:Update(route("teleport"))
        t:assertNotNil(RT.secureAction, "a secure button covers the action")
        t:assertEqual(6948, RT.secureAction and RT.secureAction.teleportID, "for the step's teleport")
        local secure = RT.secureAction
        RT:Hide()
        t:assertNil(RT.secureAction, "hiding drops it")
        t:assertFalse(secure.inUse, "and returns it to the pool")
        RT:Show()
        MockWoW.config.inCombatLockdown = true
        RT:Update(route("teleport"))
        MockWoW.config.inCombatLockdown = false
        t:assertNil(RT.secureAction, "no secure button under lockdown")
    end)
end)

T:run("RouteTracker: the route tab feeds the open tracker", function(t)
    withTracker(function()
        RT:Show()
        RT:ShowMessage("before")
        t:assertNil(RT.currentStep, "the tracker starts without a step")
        QR.UI:UpdateRoute(route())
        t:assertEqual(route().steps[1].to, RT.currentStep and RT.currentStep.to, "UpdateRoute reaches the tracker")
        QR.UI:ClearRoute()
        t:assertNil(RT.currentStep, "a cleared route clears it")
        t:assertTrue(anyLine(QR.L["SET_WAYPOINT_HINT"]), "and it says to set a waypoint")
    end)
end)
