-------------------------------------------------------------------------------
-- test_settingsheader.lua
-- The settings page header ("C2 — Leyliniennetz"): what it shows and where
-- it sits in the settings list.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local function resetState()
    MockWoW:Reset()
    QR.PlayerInventory.teleportItems = {}
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}
    QR.SettingsPanel.initialized = false
    QR.SettingsPanel.category = nil
    QR.SettingsPanel.headerInitializer = nil
end

local function makeHeader()
    local frame = CreateFrame("Frame")
    for k, v in pairs(QuickRouteSettingsHeaderMixin) do frame[k] = v end
    frame:OnLoad()
    return frame
end

T:run("SettingsHeader: branding stays out of the scrolling settings layout", function(t)
    resetState()
    QR.SettingsPanel:Register()
    local layout = _G.SettingsPanel:GetLayout(QR.SettingsPanel.category)
    t:assertNotNil(layout._initializers[1], "something was added to the layout")
    t:assertEqual("sectionHeader", layout._initializers[1]._type, "General is the first scrolling section")
    t:assertNil(QR.SettingsPanel.headerInitializer, "branding has no scrolling initializer")
end)

T:run("SettingsHeader: status data reads version, TomTom and the teleport count", function(t)
    resetState()
    MockWoW.config.addonMetadata.TomTom = { Version = "4.3.9" }
    _G.TomTom = {}
    QR.PlayerInventory.teleportItems = { [6948] = {}, [140192] = {} }
    QR.PlayerInventory.toys = { [64488] = {} }

    local data = QR.SettingsHeader:GetStatusData()
    t:assertEqual(QR.version, data.version)
    t:assertTrue(data.tomtomFound, "TomTom present")
    t:assertEqual("4.3.9", data.tomtomVersion)
    t:assertEqual(3, data.teleportCount)
    t:assertEqual("found, v4.3.9", QR.SettingsHeader:FormatTomTom(data))
    _G.TomTom = nil
end)

T:run("SettingsHeader: without TomTom the bar says so", function(t)
    resetState()
    local data = QR.SettingsHeader:GetStatusData()
    t:assertFalse(data.tomtomFound)
    t:assertEqual("not found", QR.SettingsHeader:FormatTomTom(data))
    t:assertEqual(0, data.teleportCount)
end)

T:run("SettingsHeader: compact branding leaves a separate native button gutter", function(t)
    resetState()
    local header = makeHeader()
    t:assertNotNil(header.Logo, "logo")
    t:assertNotNil(header.Title, "title")
    t:assertNotNil(header.StatusText, "compact status line")
    t:assertNotNil(header.RouteButton, "route button")
    t:assertEqual(116, header:GetHeight(), "compact header leaves room for settings")
    t:assertEqual(96, header.RouteButton:GetWidth(), "route button fits below native Defaults")
end)

T:run("SettingsHeader: Init fills the live values", function(t)
    resetState()
    _G.TomTom = {}
    QR.PlayerInventory.toys = { [64488] = {}, [140192] = {} }
    local header = makeHeader()
    header:Init({})
    t:assertNotNil(header.StatusText:GetText():find("2", 1, true), "teleport count remains visible")
    t:assertNotNil(header.StatusText:GetText():find("found", 1, true), "TomTom state remains visible")
    t:assertNotNil(header.MetaLine:GetText():find(QR.version, 1, true), "version in the meta line")
    _G.TomTom = nil
end)

local function NativePanel()
    local panel = CreateFrame("Frame")
    panel.Container = CreateFrame("Frame", nil, panel)
    local list = CreateFrame("Frame", nil, panel.Container)
    panel.Container.SettingsList = list
    local header = CreateFrame("Frame", nil, list)
    header:SetSize(660, 50)
    list.Header = header
    header.Title = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header.Title:SetText("QuickRoute")
    header.DefaultsButton = CreateFrame("Button", nil, header)
    header.DefaultsButton:SetSize(96, 22)
    header.DefaultsButton:SetPoint("TOPRIGHT", header, "TOPRIGHT", -36, -16)
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider")
    divider:SetPoint("TOP", header, "TOP", 0, -50)
    function panel:GetSettingsList() return self.Container.SettingsList end
    function panel:GetCurrentCategory() return self.currentCategory end
    function panel:DisplayCategory(category)
        self.currentCategory = category
        self:GetSettingsList().Header.Title:SetText(category:GetName())
    end
    function panel:OnSearchTextChanged()
        if self.searchText == "" then self:DisplayCategory(self.currentCategory)
        else self:GetSettingsList().Header.Title:SetText("Search Results") end
    end
    local category = { GetName = function() return "QuickRoute" end }
    local other = { GetName = function() return "Other Addon" end }
    panel.currentCategory, panel.searchText = category, ""
    panel:Show()
    panel.Container:Show()
    list:Show()
    header:Show()
    header.DefaultsButton:Show()
    return panel, header, divider, category, other
end

T:run("SettingsHeader: category, search and close restore Blizzard's shared header exactly", function(t)
    resetState()
    local panel, header, divider, category, other = NativePanel()
    t:assertTrue(QR.SettingsHeader:Install(panel, category), "hooks install on the actual native container")
    panel:DisplayCategory(category)
    t:assertEqual(116, header:GetHeight(), "branding occupies the native header above the list")
    t:assertFalse(header.Title:IsShown(), "duplicate native QuickRoute title is hidden")
    local point, relative, relativePoint, x, y = divider:GetPoint(1)
    t:assertEqual("BOTTOM", point, "divider follows the native header bottom")
    t:assertEqual(header, relative, "divider stays attached to the native header")
    t:assertEqual("BOTTOM", relativePoint, "divider uses the expanded header bottom")
    t:assertEqual(0, y, "divider has no extra gap")
    t:assertTrue(header.DefaultsButton:IsShown(), "native Defaults button stays visible")
    panel:DisplayCategory(other)
    t:assertEqual(50, header:GetHeight(), "another addon receives the original header height")
    t:assertTrue(header.Title:IsShown(), "another addon's native title is restored")
    t:assertEqual("Other Addon", header.Title:GetText(), "category title set by Blizzard is retained")
    point, relative, relativePoint, x, y = divider:GetPoint(1)
    t:assertEqual("TOP", point, "original divider point restored")
    t:assertEqual(header, relative, "original divider relative frame restored")
    t:assertEqual("TOP", relativePoint, "original divider relative point restored")
    t:assertEqual(0, x, "original divider x restored")
    t:assertEqual(-50, y, "original divider y restored")
    panel:DisplayCategory(category)
    panel.searchText = "teleport"
    panel:OnSearchTextChanged()
    t:assertEqual(50, header:GetHeight(), "search returns to native header geometry")
    t:assertTrue(header.Title:IsShown(), "search title is visible")
    panel.searchText = ""
    panel:OnSearchTextChanged()
    t:assertEqual(116, header:GetHeight(), "clearing search reactivates current category branding")
    panel:Hide()
    t:assertEqual(50, header:GetHeight(), "closing settings restores native geometry")
    t:assertTrue(header.Title:IsShown(), "closing restores the native title")
    panel:Show()
    t:assertEqual(116, header:GetHeight(), "reopening the category reactivates branding")
    panel:Hide()
end)

T:run("SettingsHeader: missing native divider never leaves a blank expanded header", function(t)
    resetState()
    local panel, header, divider, category = NativePanel()
    divider:SetAtlas("UnknownNativeDivider")
    QR.SettingsHeader:Install(panel, category)
    panel:DisplayCategory(category)
    t:assertEqual(50, header:GetHeight(), "unknown native geometry keeps its original height")
    t:assertTrue(header.Title:IsShown(), "native title remains when branding cannot attach")
end)

T:run("SettingsHeader: restoration retains a previously hidden title and custom divider anchors", function(t)
    resetState()
    local panel, header, divider, category, other = NativePanel()
    header:SetHeight(61)
    header.Title:Hide()
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 4, -61)
    divider:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT", -7, -61)
    QR.SettingsHeader:Install(panel, category)
    panel:DisplayCategory(other)
    t:assertEqual(61, header:GetHeight(), "pre-existing custom header height is restored")
    t:assertFalse(header.Title:IsShown(), "pre-existing hidden title stays hidden")
    t:assertEqual(2, divider:GetNumPoints(), "all original divider anchors are restored")
    local point, relative, relativePoint, x, y = divider:GetPoint(2)
    t:assertEqual("BOTTOMRIGHT", point, "second original anchor is preserved")
    t:assertEqual(header, relative, "second relative frame is preserved")
    t:assertEqual("TOPRIGHT", relativePoint, "second relative point is preserved")
    t:assertEqual(-7, x, "second horizontal offset is preserved")
    t:assertEqual(-61, y, "second vertical offset is preserved")
end)
