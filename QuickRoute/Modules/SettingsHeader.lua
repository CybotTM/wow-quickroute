-- SettingsHeader.lua
-- The header element of the settings page: "C2 — Leyliniennetz" from the
-- design canvas. A 236px band with the logo (112px), the addon name, a
-- subtitle and a meta line (version, author, site), drawn over a travel
-- network -- nodes, edges and one route in gold -- and, below that, a status
-- bar with the TomTom detection, the number of teleports found and a button
-- that opens the route window. The settings themselves follow unchanged;
-- Blizzard's own "Defaults" button stays where it is.
local ADDON_NAME, QR = ...

local CreateFrame = CreateFrame
local CreateColor = CreateColor
local string_format = string.format

QR.SettingsHeader = {}
local SettingsHeader = QR.SettingsHeader

local L

-- Design tokens, from the canvas.
local HEADER_HEIGHT = 236
local PAD_X = 34
local PAD_TOP = 26
local LOGO_SIZE = 112
local TITLE_GAP = 22
local STATUS_BAR_HEIGHT = 50
local GOLD = { 1.0, 0.82, 0.0 }            -- #ffd100
local GOLD_DIM = { 0.788, 0.647, 0.18 }    -- #c9a52e
local PARCH = { 0.937, 0.886, 0.769 }      -- #efe2c4
local GRAY = { 0.616, 0.616, 0.616 }       -- #9d9d9d
local CYAN = { 0.31, 0.847, 0.933 }        -- #4fd8ee
local ROUND_DOT = "Interface\\COMMON\\Indicator-Gray"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SITE_URL = "github.com/CybotTM/wow-quickroute"

-- The network, in the 820x236 space the design was drawn in. Edges are pairs
-- of node coordinates; the route is the gold path through five of them.
local NET_EDGES = {
    { 92, 178, 212, 214 }, { 212, 214, 344, 196 }, { 344, 196, 286, 128 }, { 286, 128, 92, 178 },
    { 286, 128, 430, 150 }, { 430, 150, 520, 214 }, { 520, 214, 648, 190 }, { 648, 190, 742, 132 },
    { 742, 132, 636, 78 }, { 636, 78, 508, 96 }, { 508, 96, 430, 150 }, { 508, 96, 396, 44 },
    { 396, 44, 286, 128 }, { 396, 44, 214, 60 }, { 214, 60, 92, 178 }, { 742, 132, 790, 202 },
    { 648, 190, 560, 152 }, { 560, 152, 508, 96 },
}
local NET_NODES = {
    { 212, 214 }, { 344, 196 }, { 430, 150 }, { 520, 214 }, { 648, 190 },
    { 508, 96 }, { 214, 60 }, { 560, 152 }, { 790, 202 },
}
local ROUTE = { { 92, 178 }, { 286, 128 }, { 396, 44 }, { 636, 78 }, { 742, 132 } }

-------------------------------------------------------------------------------
-- Data (no frames, so tests can read it)
-------------------------------------------------------------------------------

--- What the status bar and the meta line show.
-- @return table { version, author, site, tomtomFound, tomtomVersion, teleportCount }
function SettingsHeader:GetStatusData()
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata
    local version = QR.version or (meta and meta(ADDON_NAME, "Version")) or "dev"
    local author = (meta and meta(ADDON_NAME, "Author")) or "Sebastian Mendel"
    local tomtomFound = QR.WaypointIntegration and QR.WaypointIntegration:HasTomTom() or false
    local tomtomVersion = tomtomFound and meta and meta("TomTom", "Version") or nil
    local count = QR.PlayerInventory and QR.PlayerInventory:GetTeleportCount() or 0
    return {
        version = version,
        author = author,
        site = SITE_URL,
        tomtomFound = tomtomFound,
        tomtomVersion = tomtomVersion,
        teleportCount = count,
    }
end

--- The TomTom line of the status bar.
function SettingsHeader:FormatTomTom(data)
    L = L or QR.L
    if data.tomtomFound then
        if data.tomtomVersion and data.tomtomVersion ~= "" then
            return string_format(L["SETTINGS_TOMTOM_FOUND_VERSION"] or "found, v%s", data.tomtomVersion)
        end
        return L["SETTINGS_TOMTOM_FOUND"] or "found"
    end
    return L["SETTINGS_TOMTOM_MISSING"] or "not found"
end

-------------------------------------------------------------------------------
-- Drawing helpers
-------------------------------------------------------------------------------

local function Line(parent, x1, y1, x2, y2, r, g, b, a, thickness, layer, sublevel)
    local line = parent:CreateLine(nil, layer or "ARTWORK", nil, sublevel or 0)
    line:SetColorTexture(r, g, b, a)
    line:SetThickness(thickness)
    line:SetStartPoint("TOPLEFT", parent, x1, -y1)
    line:SetEndPoint("TOPLEFT", parent, x2, -y2)
    return line
end

local function Dot(parent, x, y, size, r, g, b, a, layer, sublevel)
    local dot = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    dot:SetTexture(ROUND_DOT)
    dot:SetVertexColor(r, g, b, a)
    dot:SetSize(size, size)
    dot:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
    return dot
end

local function Text(parent, template, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    if size then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    if r then fs:SetTextColor(r, g, b) end
    fs:SetShadowOffset(0, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-------------------------------------------------------------------------------
-- The element
-------------------------------------------------------------------------------
QuickRouteSettingsHeaderMixin = {}

function QuickRouteSettingsHeaderMixin:OnLoad()
    L = QR.L
    self:SetHeight(HEADER_HEIGHT)

    -- Night-blue ground, darkening to the right, and a hairline in gold below.
    local bg = self:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    bg:SetGradient("HORIZONTAL", CreateColor(0.086, 0.141, 0.29, 1), CreateColor(0.02, 0.027, 0.06, 1))
    local rule = self:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.34)

    -- The travel network: faint cyan edges and nodes, one route in gold with a
    -- soft glow (a wider, fainter line underneath).
    for _, e in ipairs(NET_EDGES) do
        Line(self, e[1], e[2], e[3], e[4], CYAN[1], CYAN[2], CYAN[3], 0.16, 1, "ARTWORK", 0)
    end
    for i = 1, #ROUTE - 1 do
        local a, b = ROUTE[i], ROUTE[i + 1]
        Line(self, a[1], a[2], b[1], b[2], GOLD[1], GOLD[2], GOLD[3], 0.12, 8, "ARTWORK", 1)
        Line(self, a[1], a[2], b[1], b[2], GOLD[1], GOLD[2], GOLD[3], 0.72, 2.4, "ARTWORK", 2)
    end
    for _, n in ipairs(NET_NODES) do
        Dot(self, n[1], n[2], 7, CYAN[1], CYAN[2], CYAN[3], 0.55, "ARTWORK", 3)
    end
    for i, n in ipairs(ROUTE) do
        local isEnd = i == 1 or i == #ROUTE
        if isEnd then
            Dot(self, n[1], n[2], 25, GOLD[1], GOLD[2], GOLD[3], 0.30, "ARTWORK", 3)
            Dot(self, n[1], n[2], 12, GOLD[1], GOLD[2], GOLD[3], 0.9, "ARTWORK", 4)
        else
            Dot(self, n[1], n[2], 9, 0.56, 0.914, 0.969, 0.9, "ARTWORK", 4)
        end
    end

    -- Readability veil: strong on the left, where the text is.
    local veil = self:CreateTexture(nil, "ARTWORK", nil, 5)
    veil:SetAllPoints()
    veil:SetColorTexture(1, 1, 1, 1)
    veil:SetGradient("HORIZONTAL", CreateColor(0.02, 0.027, 0.06, 0.80), CreateColor(0.02, 0.027, 0.06, 0.44))

    -- Logo, name, subtitle, meta line.
    local logo = self:CreateTexture(nil, "OVERLAY")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", self, "TOPLEFT", PAD_X, -PAD_TOP)
    logo:SetTexture(QR.LOGO_PATH or "Interface\\Icons\\INV_Misc_Map02")
    self.Logo = logo

    local title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetFont("Fonts\\MORPHEUS.TTF", 34, "")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    title:SetShadowOffset(0, -2)
    title:SetShadowColor(0, 0, 0, 0.9)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", TITLE_GAP, -8)
    title:SetText(L["ADDON_TITLE"] or "QuickRoute")
    self.Title = title

    local subtitle = Text(self, "GameFontNormal", 14, PARCH[1], PARCH[2], PARCH[3])
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("RIGHT", self, "RIGHT", -PAD_X, 0)
    subtitle:SetText(L["SETTINGS_HEADER_SUBTITLE"] or "Shortest way to your destination, via teleports, portals and spells.")
    self.Subtitle = subtitle

    local metaLine = Text(self, "GameFontNormalSmall", 13, GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3])
    metaLine:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    metaLine:SetPoint("RIGHT", self, "RIGHT", -PAD_X, 0)
    self.MetaLine = metaLine

    -- Status bar.
    local bar = CreateFrame("Frame", nil, self, "BackdropTemplate")
    bar:SetHeight(STATUS_BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
    bar:SetPoint("RIGHT", self, "RIGHT", -PAD_X, 0)
    bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bar:SetBackdropColor(0.024, 0.035, 0.07, 0.78)
    bar:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.20)
    self.StatusBar = bar

    local tomtomDot = bar:CreateTexture(nil, "ARTWORK")
    tomtomDot:SetTexture(ROUND_DOT)
    tomtomDot:SetSize(9, 9)
    tomtomDot:SetPoint("LEFT", bar, "LEFT", 16, 0)
    self.TomTomDot = tomtomDot

    local tomtomLabel = Text(bar, "GameFontNormalSmall", 13, GRAY[1], GRAY[2], GRAY[3])
    tomtomLabel:SetPoint("LEFT", tomtomDot, "RIGHT", 9, 0)
    tomtomLabel:SetText(L["SETTINGS_TOMTOM"] or "TomTom")
    local tomtomText = Text(bar, "GameFontNormalSmall", 13, PARCH[1], PARCH[2], PARCH[3])
    tomtomText:SetPoint("LEFT", tomtomLabel, "RIGHT", 6, 0)
    self.TomTomText = tomtomText

    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetWidth(1)
    sep:SetPoint("TOP", bar, "TOP", 0, -11)
    sep:SetPoint("BOTTOM", bar, "BOTTOM", 0, 11)
    sep:SetPoint("LEFT", tomtomText, "RIGHT", 26, 0)
    sep:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)

    local countDot = bar:CreateTexture(nil, "ARTWORK")
    countDot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    countDot:SetSize(12, 12)
    countDot:SetPoint("LEFT", sep, "RIGHT", 26, 0)
    local countLabel = Text(bar, "GameFontNormalSmall", 13, GRAY[1], GRAY[2], GRAY[3])
    countLabel:SetPoint("LEFT", countDot, "RIGHT", 9, 0)
    countLabel:SetText(L["SETTINGS_TELEPORTS_FOUND"] or "Teleports found")
    local countText = Text(bar, "GameFontNormalSmall", 13, PARCH[1], PARCH[2], PARCH[3])
    countText:SetPoint("LEFT", countLabel, "RIGHT", 6, 0)
    self.CountText = countText

    local label = (L["SETTINGS_OPEN_ROUTE"] or "Open route window") .. "  |cFFC9A52E/qr|r"
    local button = QR.CreateModernButton(bar, 12 + 7 * #label, 28)
    button:SetPoint("RIGHT", bar, "RIGHT", -16, 0)
    button:SetText(label)
    if button.GetTextWidth then button:SetWidth(button:GetTextWidth() + 28) end
    button:SetScript("OnClick", function()
        if QR.MainFrame then QR.MainFrame:Show("route") end
    end)
    self.RouteButton = button
end

--- Called by the settings list whenever the element is shown.
function QuickRouteSettingsHeaderMixin:Init(initializer)
    self:Refresh()
end

--- Fill the live parts: version line, TomTom, teleport count.
function QuickRouteSettingsHeaderMixin:Refresh()
    L = QR.L
    local data = SettingsHeader:GetStatusData()
    self.MetaLine:SetText(string_format("%s %s  |cFF7D641C·|r  %s  |cFF7D641C·|r  |cFF4FD8EE%s|r",
        L["SETTINGS_VERSION"] or "Version", data.version, data.author, data.site))
    self.TomTomText:SetText(SettingsHeader:FormatTomTom(data))
    if data.tomtomFound then
        self.TomTomDot:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 1)
    else
        self.TomTomDot:SetVertexColor(GRAY[1], GRAY[2], GRAY[3], 1)
    end
    self.CountText:SetText(tostring(data.teleportCount))
end
