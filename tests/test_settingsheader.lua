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

T:run("SettingsHeader: the header element is the first thing in the layout", function(t)
    resetState()
    QR.SettingsPanel:Register()
    local layout = _G.SettingsPanel:GetLayout(QR.SettingsPanel.category)
    t:assertNotNil(layout._initializers[1], "something was added to the layout")
    t:assertEqual("QuickRouteSettingsHeaderTemplate", layout._initializers[1]._template, "the header comes first")
    t:assertEqual(QR.SettingsPanel.headerInitializer, layout._initializers[1])
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

T:run("SettingsHeader: the element draws the network, the logo and the status bar", function(t)
    resetState()
    local header = makeHeader()
    t:assertNotNil(header.Logo, "logo")
    t:assertNotNil(header.Title, "title")
    t:assertNotNil(header.StatusBar, "status bar")
    t:assertNotNil(header.RouteButton, "route button")
    t:assertTrue(#(header._lines or {}) >= 18 + 2 * 4, "edges and the route are drawn as lines")
    t:assertEqual(236, header:GetHeight(), "the design's header height")
end)

T:run("SettingsHeader: Init fills the live values", function(t)
    resetState()
    _G.TomTom = {}
    QR.PlayerInventory.toys = { [64488] = {}, [140192] = {} }
    local header = makeHeader()
    header:Init({})
    t:assertEqual("2", header.CountText:GetText())
    t:assertEqual("found", header.TomTomText:GetText())
    t:assertNotNil(header.MetaLine:GetText():find(QR.version, 1, true), "version in the meta line")
    t:assertNotNil(header.MetaLine:GetText():find("github.com/CybotTM/wow-quickroute", 1, true), "site in the meta line")
    _G.TomTom = nil
end)
