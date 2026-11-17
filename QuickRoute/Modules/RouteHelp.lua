-------------------------------------------------------------------------------
-- RouteHelp.lua
-- The help overlay of the route window (design D of 2026-11-17): it dims the
-- window, puts a numbered badge on each control and explains them in a box.
-- It opens by itself the first time the route window is shown, and from the
-- "?" button in the toolbar at any time.
-------------------------------------------------------------------------------

local ADDON_NAME, QR = ...

local string_format = string.format

local RouteHelp = { isShowing = false, badges = {} }
QR.RouteHelp = RouteHelp

local L

local BOX_WIDTH = 440
local BADGE_SIZE = 20

--- The controls the help explains, in the order of its list. Each names the
-- frame field on the route tab that carries the badge, and the text key.
local ENTRIES = {
    { field = "searchBox",     key = "HELP_SEARCH" },
    { field = "refreshButton", key = "HELP_REFRESH" },
    { field = "compactButton", key = "HELP_COMPACT" },
    { field = "moreButton",    key = "HELP_MORE" },
    { field = "scrollFrame",   key = "HELP_PLAN" },
    { field = "summaryPanel",  key = "HELP_PANEL", onlyWhenShown = true },
}
RouteHelp.ENTRIES = ENTRIES

local function Badge(parent, number)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge.circle = badge:CreateTexture(nil, "ARTWORK")
    badge.circle:SetAllPoints(badge)
    badge.circle:SetColorTexture(1, 0.82, 0, 1)
    badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    badge.label:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.label:SetTextColor(0.1, 0.08, 0)
    badge.label:SetText(tostring(number))
    return badge
end

--- Build the overlay over the route window's content once.
-- @return Frame|nil The overlay, or nil before the route tab exists
function RouteHelp:CreateFrame()
    if self.frame then return self.frame end
    local content = QR.UI and QR.UI.frame
    local window = QR.MainFrame and QR.MainFrame.frame
    if not content or not window then return nil end
    L = QR.L

    local overlay = CreateFrame("Button", nil, window)
    overlay:SetAllPoints(window)
    overlay:SetFrameStrata("DIALOG")
    overlay.dim = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.dim:SetAllPoints(overlay)
    overlay.dim:SetColorTexture(0, 0, 0, 0.6)
    -- A click on the dimmed window closes the help, as the button does.
    overlay:SetScript("OnClick", function() RouteHelp:Hide() end)
    overlay:Hide()

    local box = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    box:SetWidth(BOX_WIDTH)
    box:SetPoint("CENTER", overlay, "CENTER", 0, -10)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    box:SetBackdropColor(0.1, 0.1, 0.13, 0.98)
    box:SetBackdropBorderColor(1, 0.82, 0, 1)
    box:EnableMouse(true)
    overlay.box = box

    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12)
    title:SetText(L["HELP_TITLE"])
    box.title = title

    box.items = {}
    local previous = title
    for i, entry in ipairs(ENTRIES) do
        local item = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        item:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -10 or -6)
        item:SetWidth(BOX_WIDTH - 28)
        item:SetJustifyH("LEFT")
        item:SetWordWrap(true)
        item:SetText(string_format("%d.  %s", i, L[entry.key]))
        box.items[i] = item
        previous = item
    end
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
    hint:SetWidth(BOX_WIDTH - 28)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText(L["HELP_REOPEN"])
    box.hint = hint

    local done = QR.CreateModernButton(box, 110, 24)
    done:SetText(L["HELP_DONE"])
    done:SetPoint("TOPRIGHT", hint, "BOTTOMRIGHT", 0, -10)
    done:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        RouteHelp:Hide()
    end)
    box.done = done

    for i in ipairs(ENTRIES) do
        self.badges[i] = Badge(overlay, i)
    end

    self.frame = overlay
    return overlay
end

--- Fit the box to its text and put each badge on its control.
function RouteHelp:Layout()
    local box = self.frame.box
    local height = 12 + (box.title:GetStringHeight() or 16) + 10
    for _, item in ipairs(box.items) do height = height + (item:GetStringHeight() or 14) + 6 end
    height = height + 10 + (box.hint:GetStringHeight() or 12) + 10 + 24 + 12
    box:SetHeight(height)

    local content = QR.UI.frame
    for i, entry in ipairs(ENTRIES) do
        local badge = self.badges[i]
        local target = content[entry.field]
        badge:ClearAllPoints()
        -- The summary column exists only with a route; the toolbar always does.
        if target and (not entry.onlyWhenShown or target:IsShown()) then
            badge:SetPoint("CENTER", target, "TOPLEFT", 2, -2)
            badge:Show()
        else
            badge:Hide()
        end
    end
end

function RouteHelp:Show()
    if not self:CreateFrame() then return end
    self:Layout()
    self.frame:Show()
    self.isShowing = true
end

--- Close the help. Closing it once is enough: it no longer opens by itself.
function RouteHelp:Hide()
    if self.frame then self.frame:Hide() end
    self.isShowing = false
    if QR.db then QR.db.routeHelpSeen = true end
end

function RouteHelp:Toggle()
    if self.isShowing then self:Hide() else self:Show() end
end

--- Open the help the first time the route window is shown.
function RouteHelp:ShowIfNew()
    if QR.db and not QR.db.routeHelpSeen and not self.isShowing then
        self:Show()
    end
end

