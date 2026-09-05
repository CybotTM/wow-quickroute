-- Compact branding inside Blizzard's shared settings header. The scrolling
-- settings list remains native, and every shared-header change is restored
-- when another category, search results, or a closed panel takes its place.
local ADDON_NAME, QR = ...
local CreateFrame = CreateFrame
local string_format = string.format
local pairs, ipairs, pcall, type, unpack = pairs, ipairs, pcall, type, unpack

QR.SettingsHeader = { registrations = setmetatable({}, { __mode = "k" }) }
local SettingsHeader = QR.SettingsHeader
local HEADER_HEIGHT = 116
local GUTTER = 150
local SITE_URL = "github.com/CybotTM/wow-quickroute"
local DIVIDER_ATLAS = "Options_HorizontalDivider"

function SettingsHeader:GetStatusData()
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata
    local version = QR.version or (meta and meta(ADDON_NAME, "Version")) or "dev"
    local author = (meta and meta(ADDON_NAME, "Author")) or "Sebastian Mendel"
    local tomtomFound = QR.WaypointIntegration and QR.WaypointIntegration:HasTomTom() or false
    return {
        version = version, author = author, site = SITE_URL,
        tomtomFound = tomtomFound,
        tomtomVersion = tomtomFound and meta and meta("TomTom", "Version") or nil,
        teleportCount = QR.PlayerInventory and QR.PlayerInventory:GetTeleportCount() or 0,
    }
end

function SettingsHeader:FormatTomTom(data)
    local L = QR.L
    if data.tomtomFound then
        if data.tomtomVersion and data.tomtomVersion ~= "" then
            return string_format(L["SETTINGS_TOMTOM_FOUND_VERSION"], data.tomtomVersion)
        end
        return L["SETTINGS_TOMTOM_FOUND"]
    end
    return L["SETTINGS_TOMTOM_MISSING"]
end

local function Text(parent, template, y, height)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", 94, y)
    text:SetPoint("RIGHT", parent, "RIGHT", -GUTTER, 0)
    text:SetHeight(height)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(false)
    return text
end

QuickRouteSettingsHeaderMixin = {}

function QuickRouteSettingsHeaderMixin:OnLoad()
    if self.Logo then return end
    self:SetHeight(HEADER_HEIGHT)
    local background = self:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.035, 0.05, 0.08, 0.78)

    -- Retain the travel-network motif quietly behind the readable text.
    local points = { { 178, 99 }, { 287, 64 }, { 396, 17 }, { 515, 88 } }
    for index = 1, #points - 1 do
        local a, b = points[index], points[index + 1]
        local line = self:CreateLine(nil, "ARTWORK")
        line:SetThickness(1)
        line:SetColorTexture(0.8, 0.66, 0.2, 0.20)
        line:SetStartPoint("TOPLEFT", self, a[1], -a[2])
        line:SetEndPoint("TOPLEFT", self, b[1], -b[2])
    end
    for _, point in ipairs(points) do
        local dot = self:CreateTexture(nil, "ARTWORK")
        dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
        dot:SetVertexColor(0.35, 0.85, 0.9, 0.35)
        dot:SetSize(6, 6)
        dot:SetPoint("CENTER", self, "TOPLEFT", point[1], -point[2])
    end

    local logo = self:CreateTexture(nil, "ARTWORK")
    logo:SetSize(72, 72)
    logo:SetPoint("TOPLEFT", self, "TOPLEFT", 10, -18)
    logo:SetTexture(QR.LOGO_PATH or "Interface\\Icons\\INV_Misc_Map02")
    self.Logo = logo

    self.Title = Text(self, "GameFontNormalHuge", -8, 26)
    self.Title:SetText(QR.L["ADDON_TITLE"])
    self.MetaLine = Text(self, "GameFontHighlight", -36, 16)
    self.Subtitle = Text(self, "GameFontHighlight", -55, 30)
    self.Subtitle:SetWordWrap(true)
    self.Subtitle:SetText(QR.L["SETTINGS_HEADER_SUBTITLE"])
    self.StatusText = Text(self, "GameFontNormal", -92, 16)

    -- Native Defaults stays at TOPRIGHT (-36, -16), 96x22. This independent
    -- action uses the same right gutter below it and cannot cover status text.
    local button = QR.CreateModernButton(self, 96, 22)
    button:SetPoint("TOPRIGHT", self, "TOPRIGHT", -36, -50)
    button:SetText(QR.L["TAB_ROUTE"] .. "  /qr")
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if QR.MainFrame then QR.MainFrame:Show("route") end
    end)
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(QR.L["SETTINGS_OPEN_ROUTE"])
        GameTooltip:AddLine(SITE_URL, 0.7, 0.85, 1)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    self.RouteButton = button
end

function QuickRouteSettingsHeaderMixin:Refresh()
    local data, L = SettingsHeader:GetStatusData(), QR.L
    self.MetaLine:SetText(string_format("%s %s  /  %s", L["SETTINGS_VERSION"], data.version, data.author))
    self.StatusText:SetText(string_format("%s %s  /  %s: %d",
        L["SETTINGS_TOMTOM"], SettingsHeader:FormatTomTom(data), L["SETTINGS_TELEPORTS_FOUND"], data.teleportCount))
end

function QuickRouteSettingsHeaderMixin:Init()
    self:Refresh()
end

local function NativeHeader(panel)
    local list
    if type(panel.GetSettingsList) == "function" then
        local ok, result = pcall(panel.GetSettingsList, panel)
        if ok then list = result end
    elseif panel.Container then
        list = panel.Container.SettingsList
    end
    return list and list.Header
end

local function Divider(header)
    if not header.GetRegions then return end
    for _, region in ipairs({ header:GetRegions() }) do
        if region.GetAtlas and region:GetAtlas() == DIVIDER_ATLAS
            and region.GetNumPoints and region.GetPoint then
            return region
        end
    end
end

function SettingsHeader:Restore(panel)
    local registration = self.registrations[panel]
    local state = registration and registration.state
    if not state then return end
    registration.frame:Hide()
    state.header:SetHeight(state.height)
    state.title:SetShown(state.titleShown)
    state.divider:ClearAllPoints()
    for _, point in ipairs(state.points) do state.divider:SetPoint(unpack(point, 1, 5)) end
    registration.state = nil
end

local function Searching(panel)
    if panel.SearchBox and panel.SearchBox.GetText then
        local text = panel.SearchBox:GetText()
        return type(text) == "string" and text ~= ""
    end
    return type(panel.searchText) == "string" and panel.searchText ~= ""
end

function SettingsHeader:Update(panel, category)
    local registration = self.registrations[panel]
    if not registration then return end
    if not category and panel.GetCurrentCategory then category = panel:GetCurrentCategory() end
    if category ~= registration.category or Searching(panel) or not panel:IsShown() then
        self:Restore(panel)
        return
    end
    local header = NativeHeader(panel)
    if registration.state and registration.state.header ~= header then
        self:Restore(panel)
        registration.frame = nil
    end
    if not header or not header.Title or not header.GetHeight then return end
    local divider = Divider(header)
    if not divider then self:Restore(panel); return end
    if not registration.frame then
        -- Build only after locating native geometry. A missing API or failed
        -- drawing operation leaves the native title and height untouched.
        local frame
        local ok = pcall(function()
            frame = CreateFrame("Frame", nil, header)
            frame:Hide()
            frame:SetFrameLevel(header:GetFrameLevel())
            for key, method in pairs(QuickRouteSettingsHeaderMixin) do frame[key] = method end
            frame:OnLoad()
            frame:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            frame:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        end)
        if not ok then if frame then frame:Hide() end; return end
        registration.frame = frame
    end
    if not registration.state then
        local points = {}
        for index = 1, divider:GetNumPoints() do points[index] = { divider:GetPoint(index) } end
        registration.state = {
            header = header, height = header:GetHeight(), title = header.Title,
            titleShown = header.Title:IsShown(), divider = divider, points = points,
        }
    end
    registration.frame:Refresh()
    header:SetHeight(HEADER_HEIGHT)
    header.Title:Hide()
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)
    registration.frame:Show()
end

--- Add post-hooks to one native panel. No Blizzard method is replaced.
function SettingsHeader:Install(panel, category)
    if not panel or not category or type(hooksecurefunc) ~= "function"
        or type(panel.DisplayCategory) ~= "function" or type(panel.OnSearchTextChanged) ~= "function"
        or type(panel.HookScript) ~= "function" or type(panel.IsShown) ~= "function" then return false end
    local registration = self.registrations[panel]
    if registration then
        self:Restore(panel)
        registration.category = category
    else
        registration = { category = category }
        self.registrations[panel] = registration
        hooksecurefunc(panel, "DisplayCategory", function(owner, displayed) SettingsHeader:Update(owner, displayed) end)
        hooksecurefunc(panel, "OnSearchTextChanged", function(owner) SettingsHeader:Update(owner) end)
        panel:HookScript("OnShow", function(owner) SettingsHeader:Update(owner) end)
        panel:HookScript("OnHide", function(owner) SettingsHeader:Restore(owner) end)
    end
    self:Update(panel)
    return true
end
