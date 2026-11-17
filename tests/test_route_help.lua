-------------------------------------------------------------------------------
-- test_route_help.lua
-- The help overlay of the route window (design D of 2026-11-17).
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local RH = QR.RouteHelp
local MF = QR.MainFrame

local function withWindow(fn)
    local savedDB = QR.db
    QR.db = setmetatable({}, { __index = savedDB })
    QR.db.routeHelpSeen = false  -- nil would read through to the shared table
    QR.db.routeViewMode = "window"
    if not MF.frame then MF:CreateFrame() end
    MF.initialized = true
    if not QR.UI.frame then QR.UI:CreateContent(MF:GetContentFrame("route")) end
    QR.UI.initialized = true
    local savedRefresh = QR.UI.RefreshRoute
    QR.UI.RefreshRoute = function() end
    if RH.frame then RH.frame:Hide() end
    RH.isShowing = false
    local ok, err = pcall(fn)
    QR.UI.RefreshRoute = savedRefresh
    if RH.frame then RH.frame:Hide() end
    RH.isShowing = false
    MF:Hide("test")
    QR.db = savedDB
    if not ok then error(err, 0) end
end

T:run("RouteHelp: opens by itself the first time, then only on ?", function(t)
    withWindow(function()
        MF:Show("route", "test")
        t:assertTrue(RH.isShowing, "the first route window shows the help")
        RH.frame.box.done:GetScript("OnClick")(RH.frame.box.done)
        t:assertFalse(RH.isShowing, "Got it closes it")
        t:assertTrue(QR.db.routeHelpSeen, "and remembers that it was seen")
        MF:Hide("test")
        MF:Show("route", "test")
        t:assertFalse(RH.isShowing, "the next window opens without it")
        local help = QR.UI.frame.helpButton
        help:GetScript("OnClick")(help)
        t:assertTrue(RH.isShowing, "? opens it")
        help:GetScript("OnClick")(help)
        t:assertFalse(RH.isShowing, "and closes it")
    end)
end)

T:run("RouteHelp: the Teleports tab does not open it, and switching there closes it", function(t)
    withWindow(function()
        MF:Show("teleports", "test")
        t:assertFalse(RH.isShowing, "the Teleports tab opens no help")
        MF:SetActiveTab("route")
        RH:Show()
        MF:SetActiveTab("teleports")
        t:assertFalse(RH.isShowing, "switching to Teleports closes it")
    end)
end)

T:run("RouteHelp: a click on the dimmed window closes it", function(t)
    withWindow(function()
        RH:Show()
        RH.frame:GetScript("OnClick")(RH.frame)
        t:assertFalse(RH.isShowing, "closed")
        t:assertFalse(RH.frame:IsShown(), "and hidden")
    end)
end)

T:run("RouteHelp: one numbered badge per control, on that control", function(t)
    withWindow(function()
        QR.UI.frame.summaryPanel:Show()
        RH:Show()
        for i, entry in ipairs(RH.ENTRIES) do
            local badge = RH.badges[i]
            local target = QR.UI.frame[entry.field]
            t:assertNotNil(target, entry.field .. " exists on the route tab")
            t:assertTrue(badge:IsShown(), "badge " .. i .. " is shown")
            t:assertEqual(target, badge._points[1] and badge._points[1][2], "badge " .. i .. " sits on " .. entry.field)
            t:assertEqual(tostring(i), badge.label:GetText(), "badge " .. i .. " shows its number")
            t:assertEqual(string.format("%d.  %s", i, QR.L[entry.key]), RH.frame.box.items[i]:GetText(),
                "item " .. i .. " explains it")
        end
        RH:Hide()
        QR.UI.frame.summaryPanel:Hide()
        RH:Show()
        local panelIndex
        for i, entry in ipairs(RH.ENTRIES) do if entry.field == "summaryPanel" then panelIndex = i end end
        t:assertFalse(RH.badges[panelIndex]:IsShown(), "a hidden control gets no badge")
    end)
end)
