local T, QR, MockWoW = ...

local function withLayers(fn)
    local main = QR.MainFrame
    local saved = { combat = MockWoW.config.inCombatLockdown, frame = main.frame,
        tabs = main.tabs, content = main.contentFrames, header = main.header, subtitle = main.subtitle }
    MockWoW.config.inCombatLockdown = false
    main.frame, main.tabs, main.contentFrames = nil, {}, {}
    local button = QR.SecureButtons:GetButton()
    local ok, err = pcall(fn, main, button)
    MockWoW.config.inCombatLockdown = false
    if button then QR.SecureButtons:ReleaseButton(button) end
    if main.frame then main.frame:Hide() end
    main.frame, main.tabs, main.contentFrames = saved.frame, saved.tabs, saved.content
    main.header, main.subtitle = saved.header, saved.subtitle
    MockWoW.config.inCombatLockdown = saved.combat
    if not ok then error(err) end
end

-- Advance the actual centralized position manager, as a rendered UI frame
-- update would; the standalone mock does not run OnUpdate automatically.
local function updateOverlays()
    for index = 1, 20 do
        local name, manager = debug.getupvalue(QR.SecureButtons.AttachOverlay, index)
        if name == "overlayManagerFrame" then
            manager:GetScript("OnUpdate")(manager, 0.2)
            return
        end
        if not name then return end
    end
end

T:run("Overlay layering: main sits above HUD while secondary help covers its cast controls", function(t)
    withLayers(function(main, button)
        local frame = main:CreateFrame()
        t:assertEqual("HIGH", frame:GetFrameStrata(), "The main window uses the native panel layer above the HUD")
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(100, 30)
        row:SetFrameLevel(12)
        row:Show()
        button:SetFrameStrata("DIALOG")
        button:SetFrameLevel(100)
        QR.SecureButtons:AttachOverlay(button, row)
        local help = QR.CreateStandardWindow({ name = "QRLayerHelpTest", title = "Help", width = 300, height = 200 })
        t:assertEqual("DIALOG", help:GetFrameStrata(), "Secondary help uses the native dialog layer")
        t:assertEqual("HIGH", button:GetFrameStrata(), "A recycled cast button stays below the help window")
        t:assertFalse(button:IsUsingParentLevel(), "A UIParent-owned cast button must use its independent drawing level")
        t:assertEqual(13, button:GetFrameLevel(), "The cast button is only one level above its visible target")
        t:assertEqual(UIParent, button:GetParent(), "The protected cast button stays parented to UIParent")
        local override = QR.CreateStandardWindow({ name = "QRLayerOverrideTest", title = "Explicit layer",
            width = 300, height = 200, frameStrata = "FULLSCREEN_DIALOG" })
        t:assertEqual("FULLSCREEN_DIALOG", override:GetFrameStrata(), "An explicit window layer is respected")
        help:Hide()
        override:Hide()
    end)
end)

T:run("Overlay layering: target layer changes propagate without repeated protected writes", function(t)
    withLayers(function(_, button)
        local target = CreateFrame("Frame", nil, UIParent)
        target:SetSize(100, 30)
        target:SetFrameStrata("HIGH")
        target:SetFrameLevel(20)
        target:Show()
        QR.SecureButtons:AttachOverlay(button, target)
        local originalStrata, originalLevel = button.SetFrameStrata, button.SetFrameLevel
        local strataWrites, levelWrites = 0, 0
        button.SetFrameStrata = function(self, value) strataWrites = strataWrites + 1; originalStrata(self, value) end
        button.SetFrameLevel = function(self, value) levelWrites = levelWrites + 1; originalLevel(self, value) end
        target:SetFrameStrata("DIALOG")
        target:SetFrameLevel(30)
        updateOverlays()
        t:assertEqual("DIALOG", button:GetFrameStrata(), "An existing overlay follows a changed target layer")
        t:assertEqual(31, button:GetFrameLevel(), "An existing overlay follows a raised target")
        updateOverlays()
        t:assertEqual(1, strataWrites, "Unchanged strata does not write protected frame state again")
        t:assertEqual(1, levelWrites, "Unchanged frame level does not write protected frame state again")
        MockWoW.config.inCombatLockdown = true
        target:SetFrameStrata("HIGH")
        target:SetFrameLevel(40)
        updateOverlays()
        QR.SecureButtons:AttachOverlay(button, target)
        t:assertEqual(1, strataWrites, "Combat blocks both deferred and immediate strata writes")
        t:assertEqual(1, levelWrites, "Combat blocks both deferred and immediate level writes")
        MockWoW.config.inCombatLockdown = false
        updateOverlays()
        t:assertEqual("HIGH", button:GetFrameStrata(), "The overlay catches up when combat ends")
        t:assertEqual(41, button:GetFrameLevel(), "The overlay catches up to the current target level")
        button.SetFrameStrata, button.SetFrameLevel = originalStrata, originalLevel
    end)
end)
