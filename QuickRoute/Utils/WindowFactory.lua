-- WindowFactory.lua
-- Factory for creating standard addon windows with common UI patterns
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local math_max = math.max
local table_insert = table.insert
local CreateFrame = CreateFrame

-------------------------------------------------------------------------------
-- Modern UI Helpers
-------------------------------------------------------------------------------

--- Restyle a UIPanelScrollFrameTemplate scrollbar to modern thin appearance.
-- Hides arrow buttons, narrows the bar, and restyles the thumb.
-- @param scrollFrame ScrollFrame The scroll frame (must have a global name)
function QR.SkinScrollBar(scrollFrame)
    local name = scrollFrame.GetName and scrollFrame:GetName()
    if not name then return end

    local scrollBar = _G[name .. "ScrollBar"]
    if not scrollBar then return end

    -- Hide arrow buttons
    local upBtn = _G[name .. "ScrollBarScrollUpButton"]
    local downBtn = _G[name .. "ScrollBarScrollDownButton"]
    if upBtn then
        upBtn:SetAlpha(0)
        upBtn:SetSize(1, 1)
        if upBtn.EnableMouse then upBtn:EnableMouse(false) end
    end
    if downBtn then
        downBtn:SetAlpha(0)
        downBtn:SetSize(1, 1)
        if downBtn.EnableMouse then downBtn:EnableMouse(false) end
    end

    -- Narrow the scrollbar
    scrollBar:SetWidth(8)

    -- Restyle thumb texture
    local thumbTex = _G[name .. "ScrollBarThumbTexture"]
    if thumbTex then
        thumbTex:SetTexture("Interface\\Buttons\\WHITE8x8")
        if thumbTex.SetVertexColor then thumbTex:SetVertexColor(0.5, 0.5, 0.55, 0.6) end
        thumbTex:SetWidth(6)
    end

    -- Add thin track background
    if not scrollBar._modernTrack then
        local track = scrollBar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0.08, 0.08, 0.1, 0.3)
        scrollBar._modernTrack = track
    end
end

--- Create a modern flat button (replaces UIPanelButtonTemplate).
-- Dark background, subtle border, hover highlight.
-- @param parent Frame Parent frame
-- @param width number Button width (default 80)
-- @param height number Button height (default 22)
-- @return Button The created button
function QR.CreateModernButton(parent, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 80, height or 22)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    if btn.SetFontString then btn:SetFontString(fs) end

    -- Hover/leave border highlight (HookScript survives later SetScript calls)
    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.25, 0.9)
            self:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
        end)
        btn:HookScript("OnLeave", function(self)
            self:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
            self:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)
        end)
    end

    return btn
end

--- Create a modern flat checkbox (replaces UICheckButtonTemplate).
-- Dark background, thin border, ✓ checkmark text.
-- Supports :SetChecked(bool) and :GetChecked() for compatibility.
-- @param parent Frame Parent frame
-- @param size number Checkbox size (default 20)
-- @return CheckButton-like Frame The created checkbox
function QR.CreateModernCheckbox(parent, size)
    size = size or 20
    local cb = CreateFrame("Button", nil, parent, "BackdropTemplate")
    cb:SetSize(size, size)
    cb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cb:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
    cb:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.8)

    local checkmark = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkmark:SetPoint("CENTER", 0, 0)
    checkmark:SetText("\226\156\147")  -- ✓
    checkmark:SetTextColor(0.3, 1.0, 0.3)
    checkmark:Hide()
    cb._checkmark = checkmark

    local isChecked = false
    function cb:SetChecked(val)
        isChecked = val and true or false
        if isChecked then
            checkmark:Show()
            cb:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.9)
        else
            checkmark:Hide()
            cb:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.8)
        end
    end
    function cb:GetChecked()
        return isChecked
    end

    -- Toggle on click (callers can override OnClick via SetScript)
    cb:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
    end)

    -- Hover highlight
    if cb.HookScript then
        cb:HookScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 0.9)
        end)
        cb:HookScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
        end)
    end

    return cb
end

--- Create a modern flat icon button (replaces texture-based icon buttons).
-- Uses a FontString glyph instead of old UI texture files.
-- @param parent Frame Parent frame
-- @param size number Button size (default 18)
-- @param glyph string UTF-8 glyph character (default ↻)
-- @return Button The created button
function QR.CreateModernIconButton(parent, size, glyph)
    size = size or 18
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    btn:SetBackdropColor(0, 0, 0, 0)

    local icon = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon:SetPoint("CENTER", 0, 0)
    icon:SetText(glyph or "\226\134\187")  -- ↻
    icon:SetTextColor(0.6, 0.6, 0.65)
    btn._icon = icon

    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.25, 0.6)
            icon:SetTextColor(1, 1, 1)
        end)
        btn:HookScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
            icon:SetTextColor(0.6, 0.6, 0.65)
        end)
    end

    return btn
end

--- Create a standard addon window with backdrop, title bar, close button, and drag support.
-- Eliminates duplication between UI.lua and TeleportPanel.lua.
--
-- @param options table Configuration options:
--   name           string   Global frame name (e.g. "QuickRouteFrame")
--   title          string   Title bar text
--   width          number   Frame width
--   height         number   Frame height
--   defaultPoint   string   Default anchor point (default: "CENTER")
--   defaultX       number   Default X offset (default: 0)
--   defaultY       number   Default Y offset (default: 0)
--   savedPosKeys   table    Keys for saved position in QR.db:
--                            { point, relPoint, x, y }
--   onClose        function Close button callback
--   onHide         function OnHide callback (for isShowing sync)
--   frameStrata    string   Optional frame strata override (e.g. "HIGH")
--   titleBarWidth  number   Optional explicit title bar texture width
-- @return Frame The created frame
function QR.CreateStandardWindow(options)
    assert(options, "CreateStandardWindow: options required")
    assert(options.name, "CreateStandardWindow: name required")
    assert(options.title, "CreateStandardWindow: title required")
    assert(options.width, "CreateStandardWindow: width required")
    assert(options.height, "CreateStandardWindow: height required")

    -- Create main frame with backdrop
    local frame = CreateFrame("Frame", options.name, UIParent, "BackdropTemplate")
    frame:SetSize(options.width, options.height)

    -- Restore saved position or use default
    local db = QR.db or {}
    local posKeys = options.savedPosKeys
    if posKeys and type(db[posKeys.x]) == "number" and type(db[posKeys.y]) == "number"
        and type(db[posKeys.point]) == "string" and type(db[posKeys.relPoint]) == "string" then
        frame:SetPoint(db[posKeys.point], UIParent, db[posKeys.relPoint], db[posKeys.x], db[posKeys.y])
    else
        local defaultPoint = options.defaultPoint or "CENTER"
        local defaultX = options.defaultX or 0
        local defaultY = options.defaultY or 0
        frame:SetPoint(defaultPoint, UIParent, defaultPoint, defaultX, defaultY)
    end

    -- Movable / draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position to SavedVariables
        if posKeys then
            local point, _, relPoint, x, y = self:GetPoint()
            if QR.db then
                QR.db[posKeys.point] = point
                QR.db[posKeys.relPoint] = relPoint
                QR.db[posKeys.x] = x
                QR.db[posKeys.y] = y
            end
        end
    end)
    frame:SetClampedToScreen(true)

    -- Optional frame strata
    if options.frameStrata then
        frame:SetFrameStrata(options.frameStrata)
    end

    -- Allow ESC key to close the frame
    table_insert(UISpecialFrames, options.name)

    -- Sync isShowing when frame is hidden by any means (ESC, frame:Hide(), etc.)
    -- Without this, closing via ESC leaves isShowing=true, causing the UI to
    -- incorrectly reopen after combat ends
    if options.onHide then
        frame:SetScript("OnHide", function()
            options.onHide()
        end)
    end

    -- Set backdrop (flat dark panel, WoW settings style)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.95)

    -- Brand accent border
    QR.AddBrandAccent(frame, 1)

    -- Title (simple gold text at top-left, no ornate header texture)
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 12, -10)
    titleText:SetText(options.title)
    titleText:SetTextColor(1, 0.82, 0)
    frame.titleText = titleText

    -- Close button (modern flat style)
    local closeButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    closeButton:SetBackdropColor(0, 0, 0, 0)

    local closeTxt = closeButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeTxt:SetPoint("CENTER", 0, 0)
    closeTxt:SetText("\195\151")  -- × multiplication sign
    closeTxt:SetTextColor(0.6, 0.6, 0.6)

    if closeButton.HookScript then
        closeButton:HookScript("OnEnter", function(self)
            self:SetBackdropColor(0.6, 0.15, 0.15, 0.8)
            closeTxt:SetTextColor(1, 1, 1)
        end)
        closeButton:HookScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
            closeTxt:SetTextColor(0.6, 0.6, 0.6)
        end)
    end

    if options.onClose then
        closeButton:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
            local success, err = pcall(function()
                options.onClose()
            end)
            if not success then
                QR:Error(tostring(err))
            end
        end)
    else
        closeButton:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
            frame:Hide()
        end)
    end

    -- Hide initially
    frame:Hide()

    return frame
end

-------------------------------------------------------------------------------
-- Portrait Header Helper
-------------------------------------------------------------------------------

--- Create a portrait header area at the top of a frame (like WoW Character pane).
-- Adds a round portrait texture, title FontString, and subtitle FontString.
-- @param frame Frame The parent frame to attach the header to
-- @param options table Configuration:
--   icon    string  Texture path for the portrait (default: addon icon)
--   title   string  Title text (default: "QuickRoute")
-- @return table { portrait = Texture, title = FontString, subtitle = FontString }
function QR.CreatePortraitHeader(frame, options)
    options = options or {}
    local iconPath = options.icon or QR.LOGO_PATH or "Interface\\Icons\\INV_Misc_Map02"
    local titleText = options.title or "QuickRoute"

    -- Round portrait
    local portrait = frame:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(42, 42)
    portrait:SetPoint("TOPLEFT", 10, -8)
    if SetPortraitToTexture then
        SetPortraitToTexture(portrait, iconPath)
    else
        portrait:SetTexture(iconPath)
    end

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 8, -2)
    title:SetText(titleText)
    title:SetTextColor(1, 0.82, 0)

    -- Subtitle (dynamic, e.g. "Route to Stormwind City")
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    subtitle:SetText("")

    return { portrait = portrait, title = title, subtitle = subtitle }
end

-------------------------------------------------------------------------------
-- Tab Bar Helper
-------------------------------------------------------------------------------

--- Create a bottom tab bar on a frame (like WoW Character pane tabs).
-- @param frame Frame The parent frame
-- @param tabs table Array of { key = string, label = string }
-- @param onTabClick function Callback(tabKey) when a tab is clicked
-- @return table Map of tabKey -> tabButton
function QR.CreateTabBar(frame, tabs, onTabClick)
    local tabButtons = {}
    local tabWidth = math_max(80, (frame:GetWidth() - 4) / #tabs)
    local TAB_HEIGHT = 28

    for i, tabInfo in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(tabWidth, TAB_HEIGHT)
        btn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (i - 1) * tabWidth + 2, 2)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.8)

        -- Tab text
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER", 0, 0)
        text:SetText(tabInfo.label)
        text:SetTextColor(0.5, 0.5, 0.5)
        btn.text = text

        -- Active indicator (top accent line, hidden by default)
        local accent = btn:CreateTexture(nil, "OVERLAY")
        accent:SetColorTexture(QR.Colors.BRAND_R, QR.Colors.BRAND_G, QR.Colors.BRAND_B, QR.Colors.BRAND_A)
        accent:SetHeight(2)
        accent:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        accent:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
        accent:Hide()
        btn.accent = accent

        btn.tabKey = tabInfo.key

        -- Hover
        if btn.HookScript then
            btn:HookScript("OnEnter", function(self)
                if not self._isActive then
                    self:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
                end
            end)
            btn:HookScript("OnLeave", function(self)
                if not self._isActive then
                    self:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
                end
            end)
        end

        btn:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            if onTabClick then
                onTabClick(self.tabKey)
            end
        end)

        tabButtons[tabInfo.key] = btn
    end

    return tabButtons
end

--- Update tab bar visual state: highlight active tab, dim others.
-- @param tabButtons table Map of tabKey -> tabButton (from CreateTabBar)
-- @param activeKey string The key of the active tab
function QR.UpdateTabBarState(tabButtons, activeKey)
    for key, btn in pairs(tabButtons) do
        if key == activeKey then
            btn._isActive = true
            btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
            btn.text:SetTextColor(1, 0.82, 0)
            btn.accent:Show()
        else
            btn._isActive = false
            btn:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
            btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.8)
            btn.text:SetTextColor(0.5, 0.5, 0.5)
            btn.accent:Hide()
        end
    end
end
