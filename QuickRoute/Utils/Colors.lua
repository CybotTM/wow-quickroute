-- Colors.lua
-- Centralized WoW color code constants
local ADDON_NAME, QR = ...

QR.Colors = {
    -- UI colors
    ADDON_GREEN = "|cFF00FF00",  -- Addon name / success
    ERROR_RED = "|cFFFF0000",    -- Errors
    WARN_ORANGE = "|cFFFF6600",  -- Warnings
    WHITE = "|cFFFFFFFF",        -- General text
    YELLOW = "|cFFFFFF00",       -- Highlights / commands
    GRAY = "|cFFAAAAAA",         -- Dimmed text (type labels)
    LIGHT_BLUE = "|cFF00CCFF",   -- Step numbers / info
    GOLD = "|cFFFFD100",         -- Section headers

    -- Step type colors (used in UI.lua/TeleportPanel.lua)
    TELEPORT = "|cFF00CCFF",     -- Teleport steps
    PORTAL = "|cFF9966FF",       -- Portal steps
    WALK = "|cFFFFFF00",         -- Walk steps
    TRANSPORT = "|cFFFF9900",    -- Boat/zeppelin/tram

    -- Cooldown colors
    READY_GREEN = "|cFF00FF00",  -- Ready / off cooldown
    COOLDOWN_RED = "|cFFFF0000", -- On cooldown

    -- Brand colors (used for addon identity across all UI elements)
    BRAND_R = 0.0,               -- Brand accent RGB (green-gold)
    BRAND_G = 0.8,
    BRAND_B = 0.2,
    BRAND_A = 0.9,
    BRAND_HEX = "|cFF00CC33",   -- Brand color as WoW color code

    -- Reset
    R = "|r",                    -- Color reset shorthand
}

-------------------------------------------------------------------------------
-- Branding: Tooltip attribution + accent borders + micro-icon
-------------------------------------------------------------------------------

local BRAND_ICON = "Interface\\Icons\\INV_Misc_Map02"
local BRAND_COLOR = { r = 0.0, g = 0.8, b = 0.2 }

--- Add QuickRoute branding footer to a GameTooltip.
-- Call this just before GameTooltip:Show() in every tooltip handler.
-- Adds a blank separator line + "QuickRoute — /qr" in brand color.
function QR.AddTooltipBranding(tooltip)
    if not tooltip then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("|TInterface\\Icons\\INV_Misc_Map02:12:12:0:0|t " ..
        QR.Colors.BRAND_HEX .. "QuickRoute|r  " ..
        "|cFF888888/qr|r", 1, 1, 1)
end

--- Add a brand-colored accent border to a frame.
-- Creates a thin inner glow/border in the addon's brand color.
-- @param frame Frame The frame to add the accent to
-- @param thickness number Border thickness in pixels (default 1)
-- @return table The border textures { top, bottom, left, right }
function QR.AddBrandAccent(frame, thickness)
    if not frame then return end
    thickness = thickness or 1

    local borders = {}
    local r, g, b, a = BRAND_COLOR.r, BRAND_COLOR.g, BRAND_COLOR.b, 0.6

    -- Top border
    borders.top = frame:CreateTexture(nil, "OVERLAY")
    borders.top:SetColorTexture(r, g, b, a)
    borders.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borders.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borders.top:SetHeight(thickness)

    -- Bottom border
    borders.bottom = frame:CreateTexture(nil, "OVERLAY")
    borders.bottom:SetColorTexture(r, g, b, a)
    borders.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borders.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borders.bottom:SetHeight(thickness)

    -- Left border
    borders.left = frame:CreateTexture(nil, "OVERLAY")
    borders.left:SetColorTexture(r, g, b, a)
    borders.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borders.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borders.left:SetWidth(thickness)

    -- Right border
    borders.right = frame:CreateTexture(nil, "OVERLAY")
    borders.right:SetColorTexture(r, g, b, a)
    borders.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borders.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borders.right:SetWidth(thickness)

    frame._brandBorders = borders
    return borders
end

--- Add a small QuickRoute micro-icon to a button.
-- Places a tiny map icon in the bottom-right corner for addon identification.
-- @param button Button The button to add the icon to
-- @param size number Icon size in pixels (default 10)
-- @return Texture The micro-icon texture
function QR.AddMicroIcon(button, size)
    if not button then return end
    size = size or 10

    local icon = button:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetTexture(BRAND_ICON)
    icon:SetSize(size, size)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    icon:SetAlpha(0.7)
    button._brandIcon = icon
    return icon
end
