-------------------------------------------------------------------------------
-- test_miniteleportpanel_views.lua
-- The three views of the Quick Teleports popup (tiles, map table, travel
-- journal): placement on the continent map, the "Ohne festen Ort" section,
-- secure overlays, the saved view and position, the wooden frame and its
-- fallbacks, and that a cooldown tick creates no textures.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local P = QR.MiniTeleportPanel
local VIEWS = { P.VIEW_TILES, P.VIEW_TABLE, P.VIEW_JOURNAL }
local DB_KEYS = { "miniPanelView", "miniPanelPoint", "miniPanelRelPoint", "miniPanelX", "miniPanelY" }

-- Shared QR.db: what this file found is put back by the last test.
local originalDb = {}
for _, key in ipairs(DB_KEYS) do originalDb[key] = QR.db and QR.db[key] end

-- Spells of an Alliance mage with a known point (TeleportItems.lua) and the
-- maps they are on: Stormwind 84 and Ironforge 87 in Eastern Kingdoms (13),
-- Darnassus 89 and The Exodar 103 in Kalimdor (12).
local STORMWIND, IRONFORGE, DARNASSUS, EXODAR = 3561, 3562, 3565, 32271
-- Toys without a drawable point: Dalaran Hearthstone lands on map 627, which
-- has no continent in the mock; the Last Relic of Argus lands at random.
local DALARAN_HS, RELIC = 140192, 64457

local function gridTiles(cols, rows)
    local tiles = {}
    for i = 1, cols * rows do tiles[i] = 700000 + i end
    return { cols = cols, rows = rows, tiles = tiles }
end

-- Darnassus lands in Rut'theran Village (map 62, TeleportDestinationData);
-- the mock's map 62 has no parent, so it is given Kalimdor here and put back
-- by the last test.
local darkshore = MockWoW.mapDatabase[62]
local darkshoreParent = darkshore and darkshore.parentMapID

local function resetState(view)
    -- Give back the buttons a previous test left on screen: dropping the list
    -- without releasing would drain the addon-wide pool for later files.
    MockWoW.config.inCombatLockdown = false
    if P.frame then P:Hide() end
    QR.SecureButtons:ReleasePendingButtons()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    if darkshore then darkshore.parentMapID = 12 end
    P.frame = nil
    P.isShowing = false
    P.rows, P.rowPool, P.cardPool, P.tokenPool, P.panelPool = {}, {}, {}, {}, {}
    P.secureButtons = {}
    P.separator = nil
    P.elementById = nil
    for _, key in ipairs(DB_KEYS) do QR.db[key] = nil end
    QR.db.miniPanelView = view
    MockWoW.config.playerClass = "MAGE"
    MockWoW.config.playerFaction = "Alliance"
    -- Continents at their real size: 3840x2560, 15x10 tiles.
    MockWoW.config.mapArt[13] = gridTiles(15, 10)
    MockWoW.config.mapArt[12] = gridTiles(15, 10)
    -- Rectangles deliberately not square, so swapped axes land elsewhere.
    MockWoW.config.mapRects[84] = { [13] = { 0.40, 0.48, 0.70, 0.82 } }
    MockWoW.config.mapRects[87] = { [13] = { 0.47, 0.52, 0.55, 0.62 } }
    MockWoW.config.mapRects[89] = { [12] = { 0.38, 0.42, 0.10, 0.16 } }
    MockWoW.config.mapRects[103] = { [12] = { 0.30, 0.34, 0.25, 0.30 } }
    MockWoW.config.mapRects[62] = { [12] = { 0.36, 0.46, 0.05, 0.25 } }
    for _, id in ipairs({ STORMWIND, IRONFORGE, DARNASSUS, EXODAR }) do
        MockWoW.config.knownSpells[id] = true
    end
    MockWoW.config.ownedToys[DALARAN_HS] = true
    MockWoW.config.ownedToys[RELIC] = true
    QR.PlayerInfo:InvalidateCache()
    QR.SecureButtons:Initialize()
    QR.SecureButtons.pendingReleases = nil
end

local function inUseSet()
    local set = {}
    for _, btn in ipairs(QR.SecureButtons.pool or {}) do
        if btn.inUse then set[btn] = true end
    end
    return set
end

local function buttonFor(id)
    for _, btn in ipairs(P.secureButtons) do
        if btn.teleportID == id then return btn end
    end
end

local function inPool(pool, element)
    for _, e in ipairs(pool) do
        if e == element then return true end
    end
    return false
end

--- Every CreateTexture call in the mock so far.
local function texturesCreated()
    return MockWoW.texturesCreated or 0
end

local function near(a, b) return math.abs(a - b) < 1e-9 end

-------------------------------------------------------------------------------
-- Placement
-------------------------------------------------------------------------------

T:run("MiniTP views: a point is placed on its continent through the zone's rectangle", function(t)
    resetState(P.VIEW_TILES)
    local data = QR.MageTeleports.Alliance[STORMWIND]
    local place = P.PlaceEntry({ id = STORMWIND, data = data, isSpell = true })
    t:assertNotNil(place, "Stormwind is placed")
    if not place then return end
    t:assertEqual(13, place.continentID, "on Eastern Kingdoms, got " .. tostring(place.continentID))
    t:assertEqual("Eastern Kingdoms", place.continentName, "with the continent's name")
    t:assertTrue(near(place.x, 0.40 + data.x * 0.08), "x from minX..maxX, got " .. tostring(place.x))
    t:assertTrue(near(place.y, 0.70 + data.y * 0.12), "y from minY..maxY, got " .. tostring(place.y))
end)

T:run("MiniTP views: no zone rectangle on the continent leaves the entry unplaced", function(t)
    resetState(P.VIEW_TILES)
    MockWoW.config.mapRects[84] = nil
    local data = QR.MageTeleports.Alliance[STORMWIND]
    t:assertNil(P.PlaceEntry({ id = STORMWIND, data = data, isSpell = true }),
        "GetMapRectOnMap answering nothing gives no place")
    local saved = C_Map.GetMapRectOnMap
    C_Map.GetMapRectOnMap = nil
    MockWoW.config.mapRects[84] = { [13] = { 0.40, 0.48, 0.70, 0.82 } }
    local ok, place = pcall(P.PlaceEntry, { id = STORMWIND, data = data, isSpell = true })
    C_Map.GetMapRectOnMap = saved
    t:assertTrue(ok, "a client without GetMapRectOnMap does not error: " .. tostring(place))
    t:assertNil(place, "and gives no place")
end)

T:run("MiniTP views: an empty answer from TeleportDestinations is final", function(t)
    resetState(P.VIEW_TILES)
    -- A random landing: GetDestinations answers {} on purpose.
    local relic = QR.TeleportItemsData[RELIC]
    t:assertNil(P.DestinationPoint({ id = RELIC, data = relic }), "a random toy has no point")
    -- A dynamic entry with stale static coordinates is still not drawn.
    local fake = { mapID = 84, x = 0.5, y = 0.5, isDynamic = true, destination = "Somewhere" }
    t:assertNil(P.DestinationPoint({ id = 999001, data = fake }), "a dynamic entry is not drawn from its data")
end)

-------------------------------------------------------------------------------
-- Every view: builds, overlays, the unplaced section, the mount row
-------------------------------------------------------------------------------

for _, view in ipairs(VIEWS) do
    T:run("MiniTP views [" .. view .. "]: builds with several teleports and an overlay each", function(t)
        resetState(view)
        local ok, err = pcall(function() P:Show() end)
        t:assertTrue(ok, "Show() builds the view without error: " .. tostring(err))
        if not ok then return end
        t:assertTrue(P.isShowing, "the popup is open")
        -- Four placed spells, two unplaced toys, one mount row.
        t:assertEqual(7, #P.rows, "every entry has an element, got " .. #P.rows)
        t:assertEqual(7, #P.secureButtons, "one overlay per teleport plus the mount row, got " .. #P.secureButtons)
        for _, id in ipairs({ STORMWIND, IRONFORGE, DARNASSUS, EXODAR, DALARAN_HS, RELIC }) do
            local btn = buttonFor(id)
            t:assertNotNil(btn, "teleport " .. id .. " has an overlay")
            if btn then
                t:assertEqual(0, btn:GetAlpha(), "the overlay of " .. id .. " is invisible")
                t:assertNotNil(btn.qrAfterUse, "the overlay of " .. id .. " closes the popup after use")
            end
        end
        local last = P.rows[#P.rows]
        t:assertEqual(QR.L["MINI_PANEL_SUMMON_MOUNT"], last.nameLabel:GetText(), "the mount row is last")
    end)

    T:run("MiniTP views [" .. view .. "]: placed entries get a cross, the rest go under the heading", function(t)
        resetState(view)
        P:Show()
        for _, id in ipairs({ STORMWIND, IRONFORGE, DARNASSUS, EXODAR }) do
            local element = P.elementById[id]
            t:assertNotNil(element, "teleport " .. id .. " is on screen")
            if element then
                t:assertTrue(element.marker:IsShown(), "teleport " .. id .. " shows the cross")
                t:assertFalse(inPool(P.rowPool, element) and view ~= P.VIEW_JOURNAL,
                    "teleport " .. id .. " is drawn by the view, not as a plain row")
            end
        end
        for _, id in ipairs({ DALARAN_HS, RELIC }) do
            local element = P.elementById[id]
            t:assertTrue(element ~= nil and inPool(P.rowPool, element), "teleport " .. id .. " is a plain row")
            if element then
                t:assertFalse(element.marker:IsShown(), "teleport " .. id .. " has no cross")
                t:assertFalse(element.mapView:IsShown(), "teleport " .. id .. " has no map")
            end
        end
        local header = P.frame.unplacedHeader
        t:assertTrue(header:IsShown(), "the section heading is shown")
        t:assertEqual(QR.L["MINI_PANEL_NO_FIXED_PLACE"], header:GetText(), "and says Ohne festen Ort")
    end)

    T:run("MiniTP views [" .. view .. "]: a left click on an overlay closes the popup", function(t)
        resetState(view)
        P:Show()
        local btn = buttonFor(STORMWIND)
        t:assertNotNil(btn, "the Stormwind element has an overlay")
        if not btn then return end
        local post = btn:GetScript("PostClick")
        t:assertNotNil(post, "the overlay reacts to a click")
        if post then post(btn, "LeftButton", false) end
        t:assertFalse(P.isShowing, "the popup closed after use")
    end)

    T:run("MiniTP views [" .. view .. "]: combat start releases every overlay", function(t)
        resetState(view)
        local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
        t:assertNotNil(handler, "the combat manager is reachable")
        if not handler then return end
        local before = inUseSet()
        P:Show()
        local mine = {}
        for btn in pairs(inUseSet()) do
            if not before[btn] then mine[#mine + 1] = btn end
        end
        t:assertEqual(7, #mine, "the view took one button per element, got " .. #mine)
        MockWoW.config.inCombatLockdown = true
        handler(QR.combatFrame, "PLAYER_REGEN_DISABLED")
        MockWoW.config.inCombatLockdown = false
        handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")
        local held = 0
        for _, btn in ipairs(mine) do
            if btn.inUse then held = held + 1 end
        end
        t:assertEqual(0, held, "every button went back to the pool, still held: " .. held)
        t:assertFalse(P.isShowing, "the popup closed for combat")
    end)

    T:run("MiniTP views [" .. view .. "]: a cooldown tick creates no textures and keeps the overlays", function(t)
        resetState(view)
        local base = MockWoW.config.baseTime
        MockWoW.config.spellCooldowns[STORMWIND] = { start = base - 100, duration = 1800, enable = 1 }
        local start = texturesCreated()
        P:Show()
        local afterShow = texturesCreated() - start
        local buttons = {}
        for i, btn in ipairs(P.secureButtons) do buttons[i] = btn end
        local element = P.elementById[STORMWIND]
        local textBefore = element and element.statusLabel:GetText() or ""

        MockWoW.config.baseTime = base + 125
        local configureCalls = 0
        local configure = QR.SecureButtons.ConfigureButton
        QR.SecureButtons.ConfigureButton = function(...)
            configureCalls = configureCalls + 1
            return configure(...)
        end
        P:RefreshList()
        QR.SecureButtons.ConfigureButton = configure
        local afterTick = texturesCreated() - start
        local sameButtons = #buttons == #P.secureButtons
        for i, btn in ipairs(buttons) do sameButtons = sameButtons and P.secureButtons[i] == btn end
        local textAfter = element and element.statusLabel:GetText() or ""

        -- A cooldown ending changes the order: the view is built again, from
        -- its pools.
        MockWoW.config.spellCooldowns[STORMWIND] = nil
        P:RefreshList()
        local afterRebuild = texturesCreated() - start
        MockWoW.config.baseTime = base

        t:assertGreaterThan(afterShow, 0, "building the view created textures")
        t:assertEqual(afterShow, afterTick, "the tick created none (show " .. afterShow .. ", tick " .. afterTick .. ")")
        t:assertTrue(sameButtons, "the tick kept the same overlays")
        t:assertEqual(0, configureCalls, "and configured no button, got " .. configureCalls)
        t:assertTrue(textBefore:find("|cFFFF6600", 1, true) ~= nil, "the element showed the cooldown: " .. textBefore)
        t:assertTrue(textAfter ~= textBefore, "the tick changed the time: " .. textBefore .. " -> " .. textAfter)
        t:assertEqual(afterShow, afterRebuild,
            "a rebuild reuses the pooled textures (show " .. afterShow .. ", rebuild " .. afterRebuild .. ")")
        local rebuilt = P.elementById[STORMWIND]
        t:assertTrue(rebuilt ~= nil and rebuilt.dimmed == false, "the rebuild shows the ready teleport undimmed")
        P:Hide()
    end)
end

T:run("MiniTP views: the tick updates the remaining time in place", function(t)
    resetState(P.VIEW_TILES)
    local base = MockWoW.config.baseTime
    MockWoW.config.spellCooldowns[STORMWIND] = { start = base - 100, duration = 1800, enable = 1 }
    P:Show()
    local card = P.elementById[STORMWIND]
    local before = card.statusLabel:GetText()
    local buttons = {}
    for i, btn in ipairs(P.secureButtons) do buttons[i] = btn end
    t:assertTrue(card.dimmed, "a card on cooldown is dimmed")
    t:assertTrue(card.shade:IsShown(), "and shaded")
    MockWoW.config.baseTime = base + 600
    P:RefreshList()
    MockWoW.config.baseTime = base
    t:assertEqual(card, P.elementById[STORMWIND], "the same card stays")
    t:assertTrue(card.statusLabel:GetText() ~= before,
        "with the new time: " .. tostring(before) .. " -> " .. tostring(card.statusLabel:GetText()))
    local same = #buttons == #P.secureButtons
    for i, btn in ipairs(buttons) do same = same and P.secureButtons[i] == btn end
    t:assertTrue(same, "and the same overlays")
end)

T:run("MiniTP views: an item name that arrives late replaces the fallback", function(t)
    resetState(P.VIEW_TILES)
    -- Neither item API knows the name yet: the popup falls back to the data.
    local modern, legacy = C_Item.GetItemInfo, _G.GetItemInfo
    local function uncached(original)
        return function(id, ...)
            if id == DALARAN_HS then return nil end
            return original(id, ...)
        end
    end
    C_Item.GetItemInfo, _G.GetItemInfo = uncached(modern), uncached(legacy)
    local ok, err = pcall(function() P:Show() end)
    C_Item.GetItemInfo, _G.GetItemInfo = modern, legacy
    t:assertTrue(ok, "the popup opened: " .. tostring(err))
    local row = P.elementById[DALARAN_HS]
    local before = row and row.nameLabel:GetText()
    local expected = C_Item.GetItemInfo(DALARAN_HS)
    P:RefreshList()
    row = P.elementById[DALARAN_HS]
    t:assertTrue(expected ~= nil and expected ~= before,
        "the client name differs from the fallback: " .. tostring(before) .. " / " .. tostring(expected))
    t:assertEqual(expected, row and row.nameLabel:GetText(), "the next refresh shows the client's name")
    P:Hide()
end)

T:run("MiniTP views: a landing resolved while the popup is open moves onto the map", function(t)
    resetState(P.VIEW_TILES)
    local destinations = QR.TeleportDestinations
    local original = destinations.GetDestinations
    local known = false
    destinations.GetDestinations = function(self, id, data)
        if id == STORMWIND and not known then return {} end
        return original(self, id, data)
    end
    local ok, err = pcall(function()
        P:Show()
        t:assertTrue(inPool(P.rowPool, P.elementById[STORMWIND]), "without a landing Stormwind is a plain row")
        known = true
        P:RefreshList()
    end)
    destinations.GetDestinations = original
    t:assertTrue(ok, "the refresh ran: " .. tostring(err))
    t:assertTrue(inPool(P.cardPool, P.elementById[STORMWIND]), "once the landing is known it is a card")
    P:Hide()
end)

-------------------------------------------------------------------------------
-- Texture budget
-------------------------------------------------------------------------------

T:run("MiniTP views: a card draws a window of the continent, not all 150 tiles", function(t)
    resetState(P.VIEW_TILES)
    P:Show()
    local card = P.elementById[STORMWIND]
    local used = card and card.mapView.tilesUsed or 0
    t:assertGreaterThan(used, 0, "the card shows map art")
    t:assertTrue(used <= 30, "at most 6x5 tiles of a 15x10 continent, got " .. used)
    t:assertTrue(#card.mapView.tiles <= 30, "and created no more than that, got " .. #card.mapView.tiles)
end)

T:run("MiniTP views: the cross and the tile under it sit where the art window puts them", function(t)
    resetState(P.VIEW_TILES)
    P:Show()
    local card = P.elementById[STORMWIND]
    t:assertNotNil(card, "Stormwind is a card")
    if not card then return end
    local view = card.mapView
    local place = P.PlaceEntry({ id = STORMWIND, data = (QR.ClassTeleportSpells or {})[STORMWIND]
        or QR.MageTeleports.Alliance[STORMWIND], isSpell = true })
    local art = P.MapArt(13)
    local left, top, width = P.ArtWindow(art, { place }, 1280, view.viewWidth / view.viewHeight)
    local scale = view.viewWidth / width
    local px, py = place.x * art.layerWidth, place.y * art.layerHeight
    local point = card.marker._points[#card.marker._points]
    t:assertEqual(view, point[2], "the cross is placed on the map view")
    t:assertTrue(math.abs(point[4] - (px - left) * scale) < 1e-6,
        "cross x " .. tostring(point[4]) .. " = " .. tostring((px - left) * scale))
    t:assertTrue(math.abs(point[5] + (py - top) * scale) < 1e-6,
        "cross y " .. tostring(point[5]) .. " = " .. tostring(-(py - top) * scale))
    -- The tile the point lies in: row-major in the layer's tile grid.
    local col, row = math.floor(px / art.tileWidth), math.floor(py / art.tileHeight)
    local file = art.tiles[row * art.cols + col + 1]
    local found
    for i = 1, view.tilesUsed do
        if view.tiles[i]:GetTexture() == file then found = view.tiles[i] end
    end
    t:assertNotNil(found, "the tile under the cross (col " .. col .. ", row " .. row .. ") is drawn")
    if found then
        local p = found._points[#found._points]
        local x0 = (math.max(col * art.tileWidth, left) - left) * scale
        local y0 = -(math.max(row * art.tileHeight, top) - top) * scale
        t:assertTrue(math.abs(p[4] - x0) < 1e-6 and math.abs(p[5] - y0) < 1e-6,
            string.format("at its place in the window: (%.3f,%.3f), expected (%.3f,%.3f)", p[4], p[5], x0, y0))
        t:assertTrue(p[4] <= point[4] and p[5] >= point[5], "with the cross inside it")
    end
    P:Hide()
end)

T:run("MiniTP views: a small continent fits whole on a card", function(t)
    resetState(P.VIEW_TILES)
    MockWoW.config.mapArt[13] = gridTiles(4, 3)
    local art = P.MapArt(13)
    local left, top, width, height = P.ArtWindow(art, { { x = 0.5, y = 0.5 } }, 1280, 1.5)
    t:assertEqual(0, left, "the window starts at the left edge, got " .. left)
    t:assertEqual(art.layerWidth, width, "and spans the layer's width, got " .. width)
    t:assertTrue(top >= 0 and top + height <= art.layerHeight,
        "without leaving the layer vertically: top " .. top .. ", height " .. height)
end)

-------------------------------------------------------------------------------
-- View B: tokens that would overlap are spread apart
-------------------------------------------------------------------------------

local function overlaps(a, b, size)
    return math.abs(a.x - b.x) < size and math.abs(a.y - b.y) < size
end

T:run("MiniTP views: SpreadTokens moves tokens apart and keeps them on the view", function(t)
    local size = 20
    local points = { { x = 50, y = 50 }, { x = 50, y = 50 }, { x = 52, y = 49 }, { x = 5, y = 5 } }
    local spots = P.SpreadTokens(points, size, 120, 80)
    t:assertEqual(#points, #spots, "one spot per token")
    for i = 1, #spots do
        for j = i + 1, #spots do
            t:assertFalse(overlaps(spots[i], spots[j], size),
                string.format("tokens %d (%.1f,%.1f) and %d (%.1f,%.1f) do not overlap",
                    i, spots[i].x, spots[i].y, j, spots[j].x, spots[j].y))
        end
        t:assertTrue(spots[i].x >= size / 2 and spots[i].x <= 120 - size / 2
            and spots[i].y >= size / 2 and spots[i].y <= 80 - size / 2,
            string.format("token %d stays on the view at (%.1f,%.1f)", i, spots[i].x, spots[i].y))
    end
    t:assertEqual(50, spots[1].x, "the first token keeps its own point")
end)

T:run("MiniTP views: the map table spreads tokens whose crosses coincide", function(t)
    resetState(P.VIEW_TABLE)
    -- Ironforge's rectangle chosen so its landing falls on Stormwind's spot.
    -- The panel reads the class spell table first (CollectOwnedTeleports).
    local function spell(id) return (QR.ClassTeleportSpells or {})[id] or QR.MageTeleports.Alliance[id] end
    local sw = P.PlaceEntry({ id = STORMWIND, data = spell(STORMWIND), isSpell = true })
    local ifData = spell(IRONFORGE)
    local minX, minY = sw.x - ifData.x * 0.01, sw.y - ifData.y * 0.01
    MockWoW.config.mapRects[87] = { [13] = { minX, minX + 0.01, minY, minY + 0.01 } }
    local ok, err = pcall(function() P:Show() end)
    t:assertTrue(ok, "the table builds: " .. tostring(err))
    if not ok then return end
    local a, b = P.elementById[STORMWIND], P.elementById[IRONFORGE]
    t:assertNotNil(a and b, "both are tokens on the table")
    if not (a and b) then return end
    local layout = P.tableLayout[13]
    t:assertTrue(math.abs(layout.crosses[1].x - layout.crosses[2].x) < 1e-6
        and math.abs(layout.crosses[1].y - layout.crosses[2].y) < 1e-6,
        string.format("their crosses share one spot: (%.3f,%.3f) and (%.3f,%.3f), %d crosses",
            layout.crosses[1].x, layout.crosses[1].y, layout.crosses[2].x, layout.crosses[2].y, #layout.crosses))
    t:assertFalse(overlaps({ x = a.layoutX, y = a.layoutY }, { x = b.layoutX, y = b.layoutY }, P.TOKEN_SIZE),
        string.format("but the tokens do not overlap: (%.1f,%.1f) and (%.1f,%.1f)",
            a.layoutX, a.layoutY, b.layoutX, b.layoutY))
end)

-------------------------------------------------------------------------------
-- The switch and the saved settings
-------------------------------------------------------------------------------

T:run("MiniTP views: the default view is the tiles", function(t)
    resetState(nil)
    t:assertEqual(P.VIEW_TILES, P:GetView(), "no saved choice means tiles")
    QR.db.miniPanelView = "bogus"
    t:assertEqual(P.VIEW_TILES, P:GetView(), "an unknown saved value means tiles")
end)

T:run("MiniTP views: the title bar switch saves the choice and rebuilds", function(t)
    resetState(P.VIEW_TILES)
    P:Show()
    local button = P.frame.viewButtons[P.VIEW_TABLE]
    t:assertNotNil(button, "the title bar has a map table button")
    t:assertNotNil(button:GetScript("OnEnter"), "with a tooltip")
    button:GetScript("OnClick")(button)
    t:assertEqual(P.VIEW_TABLE, QR.db.miniPanelView, "the choice is saved")
    t:assertTrue(button.selected, "the button shows as selected")
    t:assertFalse(P.frame.viewButtons[P.VIEW_TILES].selected, "the old one does not")
    t:assertTrue(P.elementById[STORMWIND].isToken == true, "the popup now shows tokens")
    t:assertEqual(7, #P.secureButtons, "with one overlay per element again, got " .. #P.secureButtons)
    t:assertTrue(#MockWoW.config.playedSounds > 0, "the click plays a sound")

    -- A new session: a fresh frame opens on the saved view.
    P:Hide()
    P.frame = nil
    P:Show()
    t:assertTrue(P.elementById[STORMWIND].isToken == true, "the saved view is used on the next open")
    P:Hide()
end)

T:run("MiniTP views: Show() uses a saved position", function(t)
    resetState(P.VIEW_TILES)
    QR.db.miniPanelPoint, QR.db.miniPanelRelPoint, QR.db.miniPanelX, QR.db.miniPanelY = "TOPLEFT", "BOTTOMLEFT", 120, 340
    P:Show()
    local point = P.frame._points[1]
    t:assertEqual(1, #P.frame._points, "one anchor")
    t:assertEqual("TOPLEFT", point[1], "the saved point")
    t:assertEqual(UIParent, point[2], "relative to UIParent")
    t:assertEqual("BOTTOMLEFT", point[3], "the saved relative point")
    t:assertEqual(120, point[4], "the saved x")
    t:assertEqual(340, point[5], "the saved y")
    P:Hide()
end)

T:run("MiniTP views: without a saved position the popup opens at the minimap button", function(t)
    resetState(P.VIEW_TILES)
    QR.db.miniPanelPoint = "NOWHERE"
    P:Show()
    local point = P.frame._points[1]
    local anchor = QR.MinimapButton and QR.MinimapButton.button or Minimap
    t:assertEqual("TOPRIGHT", point[1], "anchored by its top right")
    t:assertEqual(anchor, point[2], "to the minimap button")
    P:Hide()
end)

T:run("MiniTP views: dragging the title bar moves the popup and saves where", function(t)
    resetState(P.VIEW_TILES)
    P:Show()
    local bar = P.frame.titleBar
    t:assertTrue(bar._mouseEnabled, "the title bar takes the mouse")
    t:assertTrue(P.frame._movable, "the popup is movable")
    t:assertTrue(P.frame._clamped, "and clamped to the screen")
    local started = false
    local originalStart = P.frame.StartMoving
    P.frame.StartMoving = function() started = true end
    bar:GetScript("OnDragStart")(bar)
    P.frame.StartMoving = originalStart
    t:assertTrue(started, "a drag on the title bar moves the frame")
    P.frame:ClearAllPoints()
    P.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    bar:GetScript("OnDragStop")(bar)
    t:assertEqual("CENTER", QR.db.miniPanelPoint, "the drop saves the point, got " .. tostring(QR.db.miniPanelPoint))
    t:assertTrue(QR.IsValidWindowPosition(QR.db.miniPanelPoint, QR.db.miniPanelRelPoint,
        QR.db.miniPanelX, QR.db.miniPanelY), "as a position Show() accepts")
    P:Hide()
end)

-------------------------------------------------------------------------------
-- Skin and guards for clients without the APIs (WoW Forever loads this file)
-------------------------------------------------------------------------------

local WOOD = { "Neutral-NineSlice-Corner", "_Neutral-NineSlice-EdgeTop", "_Neutral-NineSlice-EdgeBottom",
    "!Neutral-NineSlice-EdgeLeft", "!Neutral-NineSlice-EdgeRight" }

T:run("MiniTP views: the wooden frame is used when every atlas exists", function(t)
    resetState(P.VIEW_TILES)
    for _, atlas in ipairs(WOOD) do MockWoW.config.atlases[atlas] = true end
    P:CreateFrame()
    t:assertEqual("wood", P.frame.skin, "the wooden frame is applied")
    t:assertEqual("_Neutral-NineSlice-EdgeTop", P.frame.woodBorder.TopEdge:GetAtlas(), "with the top edge atlas")
end)

T:run("MiniTP views: an empty zone rectangle leaves the entry unplaced", function(t)
    -- The client answers a zone it cannot draw on the continent with
    -- 0, 0, 0, 0; the cross then sat on the continent's top left corner.
    resetState(P.VIEW_TILES)
    MockWoW.config.mapRects[84] = { [13] = { 0, 0, 0, 0 } }
    local data = QR.MageTeleports.Alliance[STORMWIND]
    t:assertNil(P.PlaceEntry({ id = STORMWIND, data = data, isSpell = true }),
        "a rectangle without area gives no place")
end)

T:run("MiniTP views: the content stays inside the wooden frame's planks", function(t)
    resetState(P.VIEW_TILES)
    P:CreateFrame()
    local narrowWidth = P.frame:GetWidth()
    t:assertEqual("backdrop", P.frame.skin, "the backdrop first")
    P.frame = nil
    for _, atlas in ipairs(WOOD) do MockWoW.config.atlases[atlas] = true end
    P:CreateFrame()
    t:assertEqual("wood", P.frame.skin, "then the wooden frame")
    -- The mock's atlases are 32 px: the content keeps 4 px off the planks.
    t:assertEqual(36, P.frame.contentInset, "the content inset follows the edge atlas")
    -- PADDING is 10: 26 px more on each side keep the content width.
    t:assertEqual(narrowWidth + 52, P.frame:GetWidth(), "the frame grows by the extra inset on both sides")
end)

T:run("MiniTP views: the housing teleport shows the dashboard's homestone", function(t)
    resetState(P.VIEW_TILES)
    local frame = CreateFrame("Frame")
    local tex = frame:CreateTexture()
    MockWoW.config.atlases["dashboard-panel-homestone-teleport-button"] = true
    P.SetEntryIcon(tex, { id = 1233637, isSpell = true, data = {} })
    t:assertEqual("dashboard-panel-homestone-teleport-button", tex:GetAtlas(), "the housing dashboard's homestone")
    MockWoW.config.atlases["dashboard-panel-homestone-teleport-button"] = nil
    local plain = frame:CreateTexture()
    P.SetEntryIcon(plain, { id = 1233637, isSpell = true, data = {} })
    t:assertNil(plain:GetAtlas(), "without the atlas the spell's own icon is used")
    t:assertNotNil(plain:GetTexture(), "and a texture is set")
end)

T:run("MiniTP views: a random delve shows the map legend's delve symbol", function(t)
    resetState(P.VIEW_TILES)
    local entry = { id = 230850, isSpell = false, data = { destination = "Random Delve" } }
    t:assertFalse(P.DestinationText(entry):find("|A:", 1, true) ~= nil, "no symbol without the atlas")
    MockWoW.config.atlases["delves-regular"] = true
    local text = P.DestinationText(entry)
    t:assertEqual(1, text:find("|A:delves-regular:14:14|a ", 1, true), "the delve symbol in front, got " .. text)
    t:assertTrue(#text > #"|A:delves-regular:14:14|a ", "followed by the destination")
end)

T:run("MiniTP views: one missing atlas falls back to the backdrop", function(t)
    resetState(P.VIEW_TILES)
    for i = 2, #WOOD do MockWoW.config.atlases[WOOD[i]] = true end
    P:CreateFrame()
    t:assertEqual("backdrop", P.frame.skin, "without the corner atlas the backdrop is used")
end)

T:run("MiniTP views: the journal lies on parchment when the atlas exists", function(t)
    resetState(P.VIEW_JOURNAL)
    MockWoW.config.atlases["QuestBG-Parchment"] = true
    P:Show()
    t:assertEqual("QuestBG-Parchment", P.frame.parchment:GetAtlas(), "Blizzard's quest parchment")
    t:assertTrue(P.frame.parchment:IsShown(), "shown in the journal")
    P:Hide()
    QR.db.miniPanelView = P.VIEW_TILES
    P:Show()
    t:assertFalse(P.frame.parchment:IsShown(), "and not on the map table")
    P:Hide()
end)

T:run("MiniTP views: every view builds on a client without the newer APIs", function(t)
    local saved = {
        C_Texture = _G.C_Texture, NineSliceUtil = _G.NineSliceUtil, NineSliceLayouts = _G.NineSliceLayouts,
        rect = C_Map.GetMapRectOnMap, layers = C_Map.GetMapArtLayers, textures = C_Map.GetMapArtLayerTextures,
    }
    for _, view in ipairs(VIEWS) do
        resetState(view)
        _G.C_Texture, _G.NineSliceUtil, _G.NineSliceLayouts = nil, nil, nil
        C_Map.GetMapRectOnMap, C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures = nil, nil, nil
        local ok, err = pcall(function() P:Show() end)
        _G.C_Texture, _G.NineSliceUtil, _G.NineSliceLayouts = saved.C_Texture, saved.NineSliceUtil, saved.NineSliceLayouts
        C_Map.GetMapRectOnMap, C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures = saved.rect, saved.layers, saved.textures
        t:assertTrue(ok, view .. " builds without the APIs: " .. tostring(err))
        if ok then
            t:assertEqual("backdrop", P.frame.skin, view .. " falls back to the backdrop")
            t:assertEqual(7, #P.rows, view .. " still lists every entry, got " .. #P.rows)
            P:Hide()
        end
    end
end)

T:run("MiniTP views: a client without the map art functions still draws cards", function(t)
    resetState(P.VIEW_TILES)
    local layers, textures = C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures
    C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures = nil, nil
    local ok, err = pcall(function() P:Show() end)
    C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures = layers, textures
    t:assertTrue(ok, "the tiles build without map art functions: " .. tostring(err))
    local card = ok and P.elementById[STORMWIND]
    t:assertTrue(card and inPool(P.cardPool, card), "Stormwind is still a card")
    if card then
        t:assertEqual(0, card.mapView.tilesUsed, "with no tiles")
        t:assertTrue(card.marker:IsShown(), "and its cross")
    end
    if ok then P:Hide() end
end)

T:run("MiniTP views: a continent without art still marks the spot", function(t)
    resetState(P.VIEW_TILES)
    MockWoW.config.mapArt[13] = nil
    P:Show()
    local card = P.elementById[STORMWIND]
    t:assertNotNil(card, "Stormwind is still a card")
    t:assertEqual(0, card.mapView.tilesUsed, "with no tiles")
    t:assertTrue(card.marker:IsShown(), "but its cross")
    P:Hide()
end)

-------------------------------------------------------------------------------
-- Put back what this file changed in the shared state
-------------------------------------------------------------------------------

T:run("MiniTP views: restore shared state", function(t)
    resetState(nil)
    P.frame = nil
    for _, key in ipairs(DB_KEYS) do QR.db[key] = originalDb[key] end
    if darkshore then darkshore.parentMapID = darkshoreParent end
    t:assertEqual(originalDb.miniPanelView, QR.db.miniPanelView, "the saved view is what it was")
end)
