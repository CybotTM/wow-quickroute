-------------------------------------------------------------------------------
-- test_minimapbutton.lua
-- Tests for the MinimapButton module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-- Helper: reinitialize the minimap button module
local function reinitialize()
    QR.MinimapButton.button = nil
    QR.MinimapButton.initialized = false
    QR.db.showMinimap = true
    QR.db.minimapAngle = nil
end

T:run("MinimapButton: module exists", function(t)
    t:assertNotNil(QR.MinimapButton)
    t:assertEqual(type(QR.MinimapButton.Initialize), "function")
    t:assertEqual(type(QR.MinimapButton.Create), "function")
    t:assertEqual(type(QR.MinimapButton.Show), "function")
    t:assertEqual(type(QR.MinimapButton.Hide), "function")
    t:assertEqual(type(QR.MinimapButton.ApplyVisibility), "function")
end)

T:run("MinimapButton: Create returns a button frame", function(t)
    reinitialize()
    local btn = QR.MinimapButton:Create()
    t:assertNotNil(btn)
    t:assertEqual(QR.MinimapButton.button, btn)
end)

T:run("MinimapButton: Create is idempotent", function(t)
    reinitialize()
    local btn1 = QR.MinimapButton:Create()
    local btn2 = QR.MinimapButton:Create()
    t:assertEqual(btn1, btn2)
end)

T:run("MinimapButton: Initialize sets initialized flag", function(t)
    reinitialize()
    t:assertEqual(QR.MinimapButton.initialized, false)
    QR.MinimapButton:Initialize()
    t:assertEqual(QR.MinimapButton.initialized, true)
end)

T:run("MinimapButton: Initialize is idempotent", function(t)
    reinitialize()
    QR.MinimapButton:Initialize()
    local btn = QR.MinimapButton.button
    QR.MinimapButton:Initialize()  -- Should not recreate
    t:assertEqual(QR.MinimapButton.button, btn)
end)

T:run("MinimapButton: Show creates button if nil", function(t)
    reinitialize()
    t:assertNil(QR.MinimapButton.button)
    QR.MinimapButton:Show()
    t:assertNotNil(QR.MinimapButton.button)
end)

T:run("MinimapButton: Hide hides the button", function(t)
    reinitialize()
    QR.MinimapButton:Create()
    QR.MinimapButton:Show()
    QR.MinimapButton:Hide()
    t:assertEqual(QR.MinimapButton.button._shown, false)
end)

T:run("MinimapButton: ApplyVisibility shows when showMinimap=true", function(t)
    reinitialize()
    QR.db.showMinimap = true
    QR.MinimapButton:Create()
    QR.MinimapButton:ApplyVisibility()
    t:assertEqual(QR.MinimapButton.button._shown, true)
end)

T:run("MinimapButton: ApplyVisibility hides when showMinimap=false", function(t)
    reinitialize()
    QR.db.showMinimap = false
    QR.MinimapButton:Create()
    QR.MinimapButton.button._shown = true  -- Manually show
    QR.MinimapButton:ApplyVisibility()
    t:assertEqual(QR.MinimapButton.button._shown, false)
end)

T:run("MinimapButton: UpdatePosition uses saved angle", function(t)
    reinitialize()
    QR.db.minimapAngle = 0  -- 0 radians = right side
    QR.MinimapButton:Create()
    QR.MinimapButton:UpdatePosition()
    -- Button should have a SetPoint call (position updated)
    local btn = QR.MinimapButton.button
    t:assertNotNil(btn)
    -- Verify the button has anchor points set (SetPoint was called)
    t:assertGreaterThan(#btn._points, 0)
end)

T:run("MinimapButton: UpdatePosition uses default angle when no saved angle", function(t)
    reinitialize()
    QR.db.minimapAngle = nil
    QR.MinimapButton:Create()
    QR.MinimapButton:UpdatePosition()
    local btn = QR.MinimapButton.button
    t:assertGreaterThan(#btn._points, 0)
end)

T:run("MinimapButton: button has click handler", function(t)
    reinitialize()
    local btn = QR.MinimapButton:Create()
    t:assertNotNil(btn._scripts["OnClick"])
end)

T:run("MinimapButton: button has tooltip handlers", function(t)
    reinitialize()
    local btn = QR.MinimapButton:Create()
    t:assertNotNil(btn._scripts["OnEnter"])
    t:assertNotNil(btn._scripts["OnLeave"])
end)

T:run("MinimapButton: button has drag handlers", function(t)
    reinitialize()
    local btn = QR.MinimapButton:Create()
    t:assertNotNil(btn._scripts["OnDragStart"])
    t:assertNotNil(btn._scripts["OnDragStop"])
end)

T:run("MinimapButton: Hide on nil button is safe", function(t)
    reinitialize()
    -- Should not error when button is nil
    QR.MinimapButton:Hide()
end)
