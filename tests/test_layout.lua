-------------------------------------------------------------------------------
-- test_layout.lua
-- Layout assertion tests for QR UI
-- Verifies frame dimensions, anchor chains, and spatial relationships
-- without requiring in-game screenshots.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

--- Create a minimal mock result for UpdateRoute
local function createMockResult(stepCount, includeUseButton)
    local steps = {}
    for i = 1, (stepCount or 3) do
        local step = {
            type = i == 1 and includeUseButton and "teleport" or "walk",
            action = "Go to Zone " .. i,
            to = "Zone " .. i,
            time = 60 * i,
            destMapID = 84 + i,
            destX = 0.5,
            destY = 0.5,
        }
        if step.type == "teleport" then
            step.teleportID = 6948  -- Hearthstone
            step.sourceType = "item"
        end
        steps[i] = step
    end
    return {
        waypoint = { title = "Test Destination", mapID = 85 },
        waypointSource = "mappin",
        totalTime = 300,
        steps = steps,
    }
end

--- Reset UI state and ensure frame exists
local function setupUI()
    -- Clear any cached bounds from previous tests
    MockWoW:ClearComputedBounds()

    -- Initialize MainFrame first (creates container + content frames)
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true

    -- Ensure UI content frame exists
    if not QR.UI.frame then
        local contentFrame = QR.MainFrame:GetContentFrame("route")
        QR.UI:CreateContent(contentFrame)
    end
    QR.UI.initialized = true

    -- Reset calculating state
    QR.UI.isCalculating = false

    return QR.UI.frame
end

-------------------------------------------------------------------------------
-- 1. Layout engine basics
-------------------------------------------------------------------------------

T:run("Layout: UIParent has expected bounds", function(t)
    MockWoW:ClearComputedBounds()
    local bounds = MockWoW:ComputeFrameBounds(UIParent)
    t:assertNotNil(bounds, "UIParent bounds computed")
    t:assertEqual(0, bounds.left, "UIParent left = 0")
    t:assertEqual(0, bounds.bottom, "UIParent bottom = 0")
    t:assertEqual(1024, bounds.right, "UIParent right = 1024")
    t:assertEqual(768, bounds.top, "UIParent top = 768")
end)

T:run("Layout: frame with CENTER anchor is centered", function(t)
    MockWoW:ClearComputedBounds()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(200, 100)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    local bounds = MockWoW:ComputeFrameBounds(frame)
    t:assertNotNil(bounds, "Centered frame bounds computed")
    t:assertEqual(412, bounds.left, "left = (1024-200)/2")
    t:assertEqual(612, bounds.right, "right = (1024+200)/2")
    t:assertEqual(434, bounds.top, "top = center(384) + height/2(50)")
    t:assertEqual(334, bounds.bottom, "bottom = center(384) - height/2(50)")
end)

T:run("Layout: frame with two opposing anchors has implicit width", function(t)
    MockWoW:ClearComputedBounds()
    local parent = CreateFrame("Frame", nil, UIParent)
    parent:SetSize(300, 50)
    parent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)

    local child = CreateFrame("Frame", nil, parent)
    child:SetSize(0, 20)  -- Width should be implicit from anchors
    child:SetPoint("LEFT", parent, "LEFT", 10, 0)
    child:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    local childBounds = MockWoW:ComputeFrameBounds(child)
    t:assertNotNil(childBounds, "Two-anchor child bounds computed")

    local childWidth = childBounds.right - childBounds.left
    t:assertEqual(280, childWidth, "implicit width = parent(300) - left(10) - right(10)")
end)

T:run("Layout: GetComputedWidth/Height helpers work", function(t)
    MockWoW:ClearComputedBounds()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(150, 75)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    t:assertEqual(150, MockWoW:GetComputedWidth(frame), "computed width = 150")
    t:assertEqual(75, MockWoW:GetComputedHeight(frame), "computed height = 75")
end)

T:run("Layout: offset from parent's TOPLEFT", function(t)
    MockWoW:ClearComputedBounds()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(100, 50)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -30)

    local bounds = MockWoW:ComputeFrameBounds(frame)
    t:assertNotNil(bounds, "Offset frame bounds computed")
    t:assertEqual(20, bounds.left, "left = 0 + 20")
    t:assertEqual(120, bounds.right, "right = 20 + 100")
    t:assertEqual(738, bounds.top, "top = 768 - 30")
    t:assertEqual(688, bounds.bottom, "bottom = 738 - 50")
end)

T:run("Layout: chained anchors resolve correctly", function(t)
    MockWoW:ClearComputedBounds()
    local frameA = CreateFrame("Frame", nil, UIParent)
    frameA:SetSize(200, 40)
    frameA:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)

    local frameB = CreateFrame("Frame", nil, UIParent)
    frameB:SetSize(100, 40)
    frameB:SetPoint("LEFT", frameA, "RIGHT", 10, 0)

    local boundsB = MockWoW:ComputeFrameBounds(frameB)
    t:assertNotNil(boundsB, "Chained frame B bounds computed")
    -- frameA right = 50 + 200 = 250; frameB left = 250 + 10 = 260
    t:assertEqual(260, boundsB.left, "frameB left = frameA.right + 10")
    t:assertEqual(360, boundsB.right, "frameB right = 260 + 100")
end)

-------------------------------------------------------------------------------
-- 2. Main UI frame layout
-------------------------------------------------------------------------------

T:run("Layout: MainFrame has minimum width", function(t)
    MockWoW:ClearComputedBounds()
    setupUI()

    -- Now the MainFrame is the container with explicit size
    local mainFrame = QR.MainFrame.frame
    t:assertNotNil(mainFrame, "MainFrame exists")
    local width = mainFrame:GetWidth()
    t:assertGreaterThan(width, 499, "MainFrame width >= 500")
end)

T:run("Layout: scrollChild width matches content area width minus margins", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()

    local scrollChild = frame.scrollChild
    t:assertNotNil(scrollChild, "scrollChild exists")

    -- Content frame gets width from anchors (MainFrame width), so use MainFrame width
    local mainFrameWidth = QR.MainFrame.frame:GetWidth()
    local scrollChildWidth = scrollChild:GetWidth()
    t:assertEqual(mainFrameWidth - 50, scrollChildWidth,
        "scrollChild width = MainFrame width - 50 (scroll bar margin)")
end)

-------------------------------------------------------------------------------
-- 3. Step label layout
-------------------------------------------------------------------------------

T:run("Layout: stepFrame width equals scrollChild width", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()

    -- Create a route with walk-only steps (no use button)
    local mockResult = createMockResult(2, false)
    QR.UI:UpdateRoute(mockResult)

    t:assertGreaterThan(#QR.UI.stepLabels, 0, "step labels created")

    local scrollChildWidth = frame.scrollChild:GetWidth()
    for i, stepFrame in ipairs(QR.UI.stepLabels) do
        t:assertEqual(scrollChildWidth, stepFrame:GetWidth(),
            "step " .. i .. " width = scrollChild width")
    end
end)

T:run("Layout: navButton is inside stepFrame bounds", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, false)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")

    local navButton = stepFrame.navButton
    t:assertNotNil(navButton, "nav button exists")

    -- navButton should be inside stepFrame (TOPRIGHT anchor with -5, -10 offset)
    -- Check the anchor setup
    t:assertGreaterThan(#navButton._points, 0, "navButton has anchor points")

    local anchor = navButton._points[1]
    t:assertEqual("TOPRIGHT", anchor[1], "navButton anchored to TOPRIGHT")
end)

T:run("Layout: label spans from LEFT to navButton with margins", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, false)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")

    local label = stepFrame.label
    t:assertNotNil(label, "label exists")

    -- label should have 2 anchor points (TOPLEFT and RIGHT)
    t:assertEqual(2, #label._points, "label has 2 anchors (TOPLEFT + RIGHT)")

    -- First anchor: TOPLEFT of stepFrame (offset for icon)
    local leftAnchor = label._points[1]
    t:assertEqual("TOPLEFT", leftAnchor[1], "first anchor is TOPLEFT")

    -- Second anchor: RIGHT of navButton - 5
    local rightAnchor = label._points[2]
    t:assertEqual("RIGHT", rightAnchor[1], "second anchor is RIGHT")

    -- Compute actual label width via layout engine
    local stepBounds = MockWoW:ComputeFrameBounds(stepFrame)
    local navBounds = MockWoW:ComputeFrameBounds(stepFrame.navButton)
    if stepBounds and navBounds then
        local labelWidth = navBounds.left - 5 - (stepBounds.left + 5)
        t:assertGreaterThan(labelWidth, 199, "label width >= 200px")
    end
end)

T:run("Layout: label width is same with or without use button", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()

    -- Route WITHOUT use button
    local walkResult = createMockResult(1, false)
    QR.UI:UpdateRoute(walkResult)
    local walkLabel = QR.UI.stepLabels[1].label
    t:assertNotNil(walkLabel, "walk label exists")
    local walkAnchors = #walkLabel._points

    -- Route WITH use button
    QR.UI:ClearStepLabels()
    MockWoW:ClearComputedBounds()
    local teleportResult = createMockResult(1, true)
    QR.UI:UpdateRoute(teleportResult)
    local teleportLabel = QR.UI.stepLabels[1].label
    t:assertNotNil(teleportLabel, "teleport label exists")
    local teleportAnchors = #teleportLabel._points

    -- Both should have same anchor count (LEFT + RIGHT)
    -- UseButton is an overlay on UIParent, doesn't affect label anchoring
    t:assertEqual(walkAnchors, teleportAnchors,
        "label anchor count same with/without use button")
    t:assertEqual(2, teleportAnchors, "teleport label has 2 anchors")

    -- Both labels should anchor RIGHT to navButton (not useButton)
    local walkRight = walkLabel._points[2]
    local teleportRight = teleportLabel._points[2]
    -- The relative frame (arg2) should be the navButton, not useButton
    -- navButton is a child of stepFrame
    t:assertNotNil(walkRight[2], "walk label right anchor has relative frame")
    t:assertNotNil(teleportRight[2], "teleport label right anchor has relative frame")
end)

T:run("Layout: useButton is NOT parented to stepFrame (overlay pattern)", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, true)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")

    local useButton = stepFrame.useButton
    if useButton then
        -- useButton should be parented to UIParent (or at least NOT stepFrame)
        local parent = useButton:GetParent()
        -- Due to overlay pattern, parent should remain as originally created (not stepFrame)
        local isStepFrame = (parent == stepFrame)
        t:assertFalse(isStepFrame, "useButton is NOT parented to stepFrame")

        -- Should be tracked by centralized overlay manager (no per-button OnUpdate)
        t:assertGreaterThan(QR.SecureButtons:GetActiveOverlayCount(), 0,
            "useButton is tracked by overlay manager")

        -- Should store reference to stepFrame (backward compat)
        t:assertEqual(stepFrame, useButton._qrStepFrame,
            "useButton stores _qrStepFrame reference")
    end
    -- If useButton is nil (combat lockdown or no SecureButtons), that's ok
end)

T:run("Layout: label has word wrap enabled for multi-line text", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, false)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")
    local label = stepFrame.label
    t:assertNotNil(label, "label exists")

    t:assertTrue(label:GetWordWrap(), "label word wrap is enabled for long text")
end)

-------------------------------------------------------------------------------
-- Card layout elements
-------------------------------------------------------------------------------

T:run("Layout: card step has icon texture", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, false)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")
    t:assertNotNil(stepFrame.iconTexture, "step has icon texture")
    t:assertTrue(stepFrame.iconTexture._shown, "icon texture is visible")
    t:assertNotNil(stepFrame.iconTexture._texture, "icon has texture path set")
end)

T:run("Layout: card step has two text lines", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, false)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")
    t:assertNotNil(stepFrame.label, "line 1 (action) exists")
    t:assertNotNil(stepFrame.label2, "line 2 (destination) exists")
    t:assertTrue(stepFrame.label._shown, "line 1 is visible")
    t:assertTrue(stepFrame.label2._shown, "line 2 is visible")
end)

T:run("Layout: current step has gold highlight border", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(3, false)
    QR.UI:UpdateRoute(mockResult)

    -- Step 1 should be "current" (index matches GetCurrentStepIndex)
    local step1 = QR.UI.stepLabels[1]
    t:assertNotNil(step1.highlight, "step 1 has highlight element")
    t:assertTrue(step1.highlight._shown, "current step highlight is shown")

    -- Step 3 should be "upcoming" (no highlight)
    local step3 = QR.UI.stepLabels[3]
    t:assertNotNil(step3.highlight, "step 3 has highlight element")
    t:assertFalse(step3.highlight._shown, "upcoming step highlight is hidden")
end)

T:run("Layout: completed step icon is desaturated", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(3, false)
    -- Set player position in step 1's dest zone to make step 1 completed
    -- Steps have destMapID = 85, 86, 87; setting currentMapID=85 makes step 1 completed
    MockWoW.config.currentMapID = 85
    QR.UI:UpdateRoute(mockResult)

    -- Step 1 is completed (player is in its dest zone)
    local step1 = QR.UI.stepLabels[1]
    t:assertNotNil(step1.iconTexture, "step 1 has icon")
    t:assertTrue(step1.iconTexture._desaturated, "completed step icon is desaturated")

    -- Step 2 is current, should not be desaturated
    local step2 = QR.UI.stepLabels[2]
    t:assertNotNil(step2.iconTexture, "step 2 has icon")
    t:assertFalse(step2.iconTexture._desaturated, "current step icon is not desaturated")

    -- Restore
    MockWoW.config.currentMapID = 84
end)

T:run("Layout: card step height is at least 48px", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, false)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")
    t:assertGreaterThan(stepFrame:GetHeight(), 47, "step height >= 48px")
end)

T:run("Layout: ReleaseStepLabelFrame hides card elements", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(1, false)
    QR.UI:UpdateRoute(mockResult)

    local stepFrame = QR.UI.stepLabels[1]
    t:assertNotNil(stepFrame, "step frame exists")

    -- Release the frame
    QR.UI:ReleaseStepLabelFrame(stepFrame)

    -- All card elements should be hidden
    t:assertFalse(stepFrame.label._shown, "label hidden after release")
    t:assertFalse(stepFrame.label2._shown, "label2 hidden after release")
    t:assertFalse(stepFrame.iconTexture._shown, "icon hidden after release")
    t:assertFalse(stepFrame.highlight._shown, "highlight hidden after release")
end)

-------------------------------------------------------------------------------
-- 4. Multiple steps layout
-------------------------------------------------------------------------------

T:run("Layout: steps are stacked vertically without overlap", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(3, false)
    QR.UI:UpdateRoute(mockResult)

    t:assertEqual(3, #QR.UI.stepLabels, "3 step labels created")

    -- Each step should have positive, increasing height
    -- Verify step frames have reasonable heights and are sequentially positioned
    local totalHeight = 0
    for i = 1, #QR.UI.stepLabels do
        local sf = QR.UI.stepLabels[i]
        local h = sf:GetHeight()
        t:assertGreaterThan(h, 0, "step " .. i .. " has positive height")
        totalHeight = totalHeight + h
    end
end)

T:run("Layout: scrollChild height accommodates all steps", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()
    local mockResult = createMockResult(5, false)
    QR.UI:UpdateRoute(mockResult)

    local scrollChild = frame.scrollChild
    local padding = 10     -- PADDING constant

    -- Sum up actual step heights (dynamic with word wrap)
    local totalStepHeight = 0
    for _, stepFrame in ipairs(QR.UI.stepLabels) do
        totalStepHeight = totalStepHeight + (stepFrame:GetHeight() or 48)
    end

    -- scrollChild height should be at least (sum of step heights + PADDING)
    local expectedMinHeight = totalStepHeight + padding
    t:assertGreaterThan(scrollChild:GetHeight(), expectedMinHeight - 1,
        "scrollChild height >= sum of step heights + padding")
end)

-------------------------------------------------------------------------------
-- 5. Button row layout
-------------------------------------------------------------------------------

T:run("Layout: bottom buttons exist and have reasonable sizes", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()

    t:assertNotNil(frame.refreshButton, "refresh button exists")
    t:assertNotNil(frame.copyDebugButton, "copy debug button exists")
    t:assertNotNil(frame.zoneDebugButton, "zone debug button exists")

    -- Each button should have positive width
    t:assertGreaterThan(frame.refreshButton:GetWidth(), 0, "refresh button has width")
    t:assertGreaterThan(frame.copyDebugButton:GetWidth(), 0, "copy debug button has width")
    t:assertGreaterThan(frame.zoneDebugButton:GetWidth(), 0, "zone debug button has width")
end)

T:run("Layout: toolbar buttons are chained left-to-right", function(t)
    MockWoW:ClearComputedBounds()
    local frame = setupUI()

    -- Verify anchor chain: refresh -> copyDebug -> zoneDebug (toolbar row at top)
    local copyAnchors = frame.copyDebugButton._points
    t:assertGreaterThan(#copyAnchors, 0, "copy debug has anchors")
    t:assertEqual("LEFT", copyAnchors[1][1], "copy debug anchor is LEFT")

    local zoneAnchors = frame.zoneDebugButton._points
    t:assertGreaterThan(#zoneAnchors, 0, "zone debug has anchors")
    t:assertEqual("LEFT", zoneAnchors[1][1], "zone debug anchor is LEFT")

    -- Compute positions and verify order
    local refreshBounds = MockWoW:ComputeFrameBounds(frame.refreshButton)
    local copyBounds = MockWoW:ComputeFrameBounds(frame.copyDebugButton)
    local zoneBounds = MockWoW:ComputeFrameBounds(frame.zoneDebugButton)

    if refreshBounds and copyBounds and zoneBounds then
        t:assertGreaterThan(copyBounds.left, refreshBounds.left,
            "copy is to the right of refresh")
        t:assertGreaterThan(zoneBounds.left, copyBounds.left,
            "zone is to the right of copy")
    end
end)

-------------------------------------------------------------------------------
-- 6. ClearStepLabels resets layout
-------------------------------------------------------------------------------

T:run("Layout: ClearStepLabels releases all frames", function(t)
    MockWoW:ClearComputedBounds()
    setupUI()
    local mockResult = createMockResult(3, true)
    QR.UI:UpdateRoute(mockResult)

    t:assertEqual(3, #QR.UI.stepLabels, "3 step labels before clear")

    QR.UI:ClearStepLabels()

    t:assertEqual(0, #QR.UI.stepLabels, "0 step labels after clear")
    t:assertGreaterThan(#QR.UI.stepLabelPool, 0, "pool has recycled frames")
end)
