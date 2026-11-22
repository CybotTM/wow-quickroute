-- MiniTeleportPanel.lua
-- Compact teleport popup for middle-click on minimap button. Three views of
-- the same owned teleports, chosen by the player and saved: map-table tiles,
-- one big map table, and a travel journal on parchment.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type = pairs, ipairs, type
local string_format = string.format
local string_byte, string_sub = string.byte, string.sub
local table_insert, table_sort, table_concat = table.insert, table.sort, table.concat
local math_floor, math_ceil, math_max, math_min, math_abs = math.floor, math.ceil, math.max, math.min, math.abs
local math_cos, math_sin, math_pi = math.cos, math.sin, math.pi
local tostring, pcall = tostring, pcall
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------------
-- MiniTeleportPanel Module
-------------------------------------------------------------------------------
QR.MiniTeleportPanel = {
    frame = nil,
    isShowing = false,
    rows = {},           -- every entry element on screen, in display order; the mount row is last
    rowPool = {},        -- journal rows (view C, the "Ohne festen Ort" section, the mount row)
    cardPool = {},       -- view A cards
    tokenPool = {},      -- view B tokens
    panelPool = {},      -- view B continent panels
    secureButtons = {},
}

local MiniTeleportPanel = QR.MiniTeleportPanel

-- Constants
local PANEL_WIDTH = 420
local ROW_HEIGHT = 24        -- plain rows: the "Ohne festen Ort" section and the mount row
local JOURNAL_ROW_HEIGHT = 44
local ICON_SIZE = 18
local PADDING = 10           -- inside the wooden border, whose corners reach 6 px in
local TITLE_HEIGHT = 24
local MAX_CONTENT_HEIGHT = 400
local SECTION_GAP = 7        -- 3px gap + 1px line + 3px gap
local HEADER_HEIGHT = 16
local ELLIPSIS = "..."

-- Row layout. The name and destination columns were fixed at 100 px each
-- regardless of the panel, which left them narrower than the space the row
-- actually has. They are derived from it instead, so widening the panel widens
-- them. GAPS is the 2 px before the icon, 4 px after it, and 2 px after the
-- status column.
local SCROLLBAR_WIDTH = 18
local STATUS_WIDTH = 52
local COLUMN_GAP = 4
local GAPS = 8
local ROW_WIDTH = PANEL_WIDTH - PADDING * 2 - SCROLLBAR_WIDTH
local LABEL_AREA = ROW_WIDTH - ICON_SIZE - STATUS_WIDTH - GAPS - COLUMN_GAP
local NAME_WIDTH = math.floor(LABEL_AREA / 2)
local DEST_WIDTH = LABEL_AREA - NAME_WIDTH

-- View A: three cards across. Continent art is 3:2 (1002x668 and 3840x2560
-- base layers alike), so the map keeps that shape.
local CARD_COLUMNS = 3
local CARD_GAP = 6
local CARD_WIDTH = math.floor((ROW_WIDTH - CARD_GAP * (CARD_COLUMNS - 1)) / CARD_COLUMNS)
local CARD_MAP_HEIGHT = math.floor(CARD_WIDTH * 2 / 3)
local CARD_HEIGHT = CARD_MAP_HEIGHT + 30
local CARD_ICON_SIZE = 22

-- View B: continent panels two across, tokens pinned on them.
local TABLE_COLUMNS = 2
local TABLE_GAP = 6
local TABLE_PANEL_WIDTH = math.floor((ROW_WIDTH - TABLE_GAP * (TABLE_COLUMNS - 1)) / TABLE_COLUMNS)
local TABLE_PANEL_HEIGHT = math.floor(TABLE_PANEL_WIDTH * 2 / 3)
local TOKEN_SIZE = 20
local TOKEN_OFFSET = 15      -- from the cross down to the token's centre

-- View C: thumbnail on the right of a journal row.
local THUMB_WIDTH = 60
local THUMB_HEIGHT = 40

-- How much of a continent one card or thumbnail shows, in art pixels of the
-- base layer. Most continents are 3840x2560 (15x10 tiles of 256 px): the whole
-- continent on every card would be 150 textures each. 1280 px is a third of
-- such a continent, wide enough to recognise the region around the cross, and
-- spans at most 6x5 tiles; a 1002x668 continent (Pandaria, Draenor, the Broken
-- Isles, Argus) fits whole.
local ENTRY_MAP_SPAN = 1280
-- A table panel shows at least this much, more when its tokens are spread out.
local TABLE_MAP_SPAN = 1280

-- The destination marker: the raid target "Cross". One constant, so the exact
-- graphic can be swapped later.
local DESTINATION_MARKER = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"
local MARKER_SIZE = 14

-- Blizzard's wooden frame (NineSliceLayouts.WoodenNeutralFrameTemplate). Every
-- atlas is probed: the WoW Forever client loads this file too.
local WOOD_ATLASES = {
    "Neutral-NineSlice-Corner",
    "_Neutral-NineSlice-EdgeTop",
    "_Neutral-NineSlice-EdgeBottom",
    "!Neutral-NineSlice-EdgeLeft",
    "!Neutral-NineSlice-EdgeRight",
}
local PARCHMENT_ATLAS = "QuestBG-Parchment"

-- Views, in the order of the title bar buttons.
local VIEW_TILES, VIEW_TABLE, VIEW_JOURNAL = "tiles", "table", "journal"
local DEFAULT_VIEW = VIEW_TILES
local VIEWS = {
    { key = VIEW_TILES,   label = "MINI_PANEL_VIEW_TILES",   tip = "MINI_PANEL_VIEW_TILES_TIP",
      icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = VIEW_TABLE,   label = "MINI_PANEL_VIEW_TABLE",   tip = "MINI_PANEL_VIEW_TABLE_TIP",
      icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
    { key = VIEW_JOURNAL, label = "MINI_PANEL_VIEW_JOURNAL", tip = "MINI_PANEL_VIEW_JOURNAL_TIP",
      icon = "Interface\\Icons\\INV_Misc_Book_09" },
}
local VALID_VIEW = { [VIEW_TILES] = true, [VIEW_TABLE] = true, [VIEW_JOURNAL] = true }

MiniTeleportPanel.VIEW_TILES, MiniTeleportPanel.VIEW_TABLE, MiniTeleportPanel.VIEW_JOURNAL =
    VIEW_TILES, VIEW_TABLE, VIEW_JOURNAL
MiniTeleportPanel.DESTINATION_MARKER = DESTINATION_MARKER
MiniTeleportPanel.TOKEN_SIZE = TOKEN_SIZE

--- Put text on a fixed-width label, ending it with an ellipsis when it is too
-- long. The labels have word wrap off, so an over-long name is cut mid-word
-- with nothing to show that anything was removed. The row's tooltip carries the
-- full name; the ellipsis is what tells the reader to go and look at it.
-- @param label FontString sized with SetWidth
-- @param text string|nil
function MiniTeleportPanel.SetTextFitted(label, text)
    text = text or ""
    label:SetText(text)

    local limit = label:GetWidth() or 0
    if limit <= 0 or label:GetStringWidth() <= limit then
        return
    end

    local bytes = #text
    while bytes > 0 do
        bytes = bytes - 1
        -- Never cut inside a multi-byte character: back off over continuation
        -- bytes, which are the ones in 0x80..0xBF.
        while bytes > 0 do
            local b = string_byte(text, bytes + 1)
            if not b or b < 0x80 or b >= 0xC0 then
                break
            end
            bytes = bytes - 1
        end
        label:SetText(string_sub(text, 1, bytes) .. ELLIPSIS)
        if label:GetStringWidth() <= limit then
            return
        end
    end
end

local SetTextFitted = MiniTeleportPanel.SetTextFitted

-- Hidden container for recycled frames (avoids SetParent(nil) taint)
local recycleContainer = CreateFrame("Frame")
recycleContainer:Hide()

-- Localization shorthand
local L

-- Status definitions (mirrors TeleportPanel STATUS)
local STATUS = {
    READY = { key = "STATUS_READY", color = "|cFF00FF00", sortOrder = 1 },
    ON_CD = { key = "STATUS_ON_CD", color = "|cFFFF6600", sortOrder = 2 },
    OWNED = { key = "STATUS_OWNED", color = "|cFF00CC00", sortOrder = 3 },
    UNAVAILABLE = { key = "STATUS_UNAVAILABLE", color = QR.Colors.GRAY, sortOrder = 4 },
    MISSING = { key = "STATUS_MISSING", color = "|cFFFFFF00", sortOrder = 4 },
    NA = { key = "STATUS_NA", color = "|cFF666666", sortOrder = 5 },
    -- Owned, but the game only accepts it on certain maps and the player is elsewhere
    ZONE = { key = "STATUS_ZONE", color = "|cFF888888", sortOrder = 4 },
}

--- Get teleport status for a given ID (simplified from TeleportPanel)
-- @param id number The item or spell ID
-- @param data table The teleport data entry
-- @param isSpell boolean Whether this is a spell
-- @return table status, number|nil cooldownRemaining
local function GetTeleportStatus(id, data, isSpell)
    if not QR.PlayerInfo:CanUseTeleport(data) then
        return STATUS.NA, nil
    end

    -- Check ownership
    local owned = false
    local sourceType = "item"

    if isSpell then
        owned = QR.PlayerInventory and QR.PlayerInventory:KnowsTeleportSpell(id, data) or false
        sourceType = "spell"
    elseif data.type == QR.TeleportTypes.TOY then
        owned = PlayerHasToy and PlayerHasToy(id) or false
        sourceType = "toy"
    else
        if QR.PlayerInventory then
            owned = QR.PlayerInventory:HasTeleport(id)
        else
            owned = false
        end
        sourceType = "item"
    end

    if not owned then
        return STATUS.MISSING, nil
    end

    -- Zone restriction (Kirin Tor Beacon: Isle of Thunder only, and so on)
    if data.usableOnMaps and not QR.PlayerInfo:IsOnAnyMap(data.usableOnMaps) then
        return STATUS.ZONE, nil
    end

    if sourceType == "toy" and not QR.PlayerInventory:IsToyUsable(id, data) then
        return STATUS.UNAVAILABLE, nil
    end

    -- Check cooldown
    if QR.CooldownTracker then
        local cooldown = QR.CooldownTracker:GetCooldown(id, sourceType)
        if cooldown then
            if cooldown.ready then
                return STATUS.READY, 0
            else
                return STATUS.ON_CD, cooldown.remaining
            end
        end
    end

    return STATUS.OWNED, nil
end

--- Get localized name for a teleport entry via WoW API
-- @param entry table The teleport entry
-- @return string The localized name
local function GetLocalizedName(entry)
    if not entry then return "" end
    local id = entry.id
    if entry.isSpell then
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            if info and info.name then return info.name end
        end
        if GetSpellInfo then
            local name = GetSpellInfo(id)
            if name then return name end
        end
    else
        if C_Item and C_Item.GetItemInfo then
            local name = C_Item.GetItemInfo(id)
            if name then return name end
        end
        if GetItemInfo then
            local name = GetItemInfo(id)
            if name then return name end
        end
    end
    return entry.data and entry.data.name or ""
end

--- Get localized destination for a teleport entry
-- @param entry table The teleport entry
-- @return string The localized destination
local function GetLocalizedDestination(entry)
    local data = entry and entry.data
    if not data then return "" end
    if data.mapID and C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(data.mapID)
        if mapInfo and mapInfo.name then return mapInfo.name end
    end
    if data.isDynamic and data.destination == "Bound Location" then
        if GetBindLocation then
            local bindLoc = GetBindLocation()
            if bindLoc and bindLoc ~= "" then return bindLoc end
        end
    end
    -- For nil-mapID entries, use L[] keys (same as TeleportPanel)
    local dest = data.destination
    if dest and QR.DEST_L_KEYS then
        local lKey = QR.DEST_L_KEYS[dest]
        if lKey then return L[lKey] end
    end
    return dest or ""
end

--- Collect owned teleports (READY, ON_CD, or OWNED status only)
-- @return table Array of filtered/sorted teleport entries
local function CollectOwnedTeleports()
    local teleports = {}
    local seen = {}

    local function addEntry(id, data, isSpell)
        if seen[id] then return end
        seen[id] = true
        local status, cooldownRemaining = GetTeleportStatus(id, data, isSpell)
        if status == STATUS.READY or status == STATUS.ON_CD or status == STATUS.OWNED then
            table_insert(teleports, {
                id = id,
                data = data,
                isSpell = isSpell,
                status = status,
                cooldownRemaining = cooldownRemaining or 0,
            })
        end
    end

    -- Items, toys, hearthstones, engineering
    for id, data in pairs(QR.TeleportItemsData or {}) do
        addEntry(id, data, false)
    end

    -- Class spells
    for id, data in pairs(QR.ClassTeleportSpells or {}) do
        addEntry(id, data, true)
    end

    -- Mage teleports
    for faction, spells in pairs(QR.MageTeleports or {}) do
        for id, data in pairs(spells) do
            addEntry(id, data, true)
        end
    end

    -- Racial spells
    for id, data in pairs(QR.RacialTeleportSpells or {}) do
        addEntry(id, data, true)
    end

    -- General spells (housing, etc.)
    for id, data in pairs(QR.GeneralTeleportSpells or {}) do
        addEntry(id, data, true)
    end

    -- Sort: READY first, then by cooldown remaining ascending, then by name
    table_sort(teleports, function(a, b)
        if a.status.sortOrder ~= b.status.sortOrder then
            return a.status.sortOrder < b.status.sortOrder
        end
        if a.cooldownRemaining ~= b.cooldownRemaining then
            return a.cooldownRemaining < b.cooldownRemaining
        end
        return (a.data.name or "") < (b.data.name or "")
    end)

    -- Deduplicate by localized destination: keep best entry per destination
    local destMap = {}   -- destination string -> best entry
    local destOrder = {} -- maintain insertion order
    for _, entry in ipairs(teleports) do
        local dest = GetLocalizedDestination(entry)
        if not destMap[dest] then
            destMap[dest] = entry
            table_insert(destOrder, dest)
        else
            local existing = destMap[dest]
            -- Prefer better status (lower sortOrder = better), then shorter cooldown
            if entry.status.sortOrder < existing.status.sortOrder
                or (entry.status.sortOrder == existing.status.sortOrder
                    and entry.cooldownRemaining < existing.cooldownRemaining) then
                destMap[dest] = entry
            end
        end
    end
    -- Rebuild teleports from deduped map (preserving dest order)
    teleports = {}
    for _, dest in ipairs(destOrder) do
        table_insert(teleports, destMap[dest])
    end

    return teleports
end


-------------------------------------------------------------------------------
-- Where a teleport lands, on its continent's map
-------------------------------------------------------------------------------

local CONTINENT_MAP_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

local function IsCoordinate(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 1
end

--- The landing point of an entry, or nil when it has none that can be drawn.
-- TeleportDestinations decides first: it resolves the housing plot, the camp,
-- the bound inn and the destination supplements, and it answers with nothing
-- on purpose for random landings, approximate ones and a Death Gate whose
-- landing is unknown. Its empty answer is final; the static data.mapID/x/y is
-- read only when the module itself is missing, and never for a dynamic or
-- random entry. Several candidates (houses, a multi-landing toy) share one
-- secure button, so the first candidate is the one drawn.
-- @param entry table { id, data }
-- @return number|nil, number|nil, number|nil mapID, x, y
function MiniTeleportPanel.DestinationPoint(entry)
    local data = entry and entry.data
    if type(data) ~= "table" then return nil end
    local destinations = QR.TeleportDestinations
    if destinations and destinations.GetDestinations then
        local ok, list = pcall(destinations.GetDestinations, destinations, entry.id, data)
        if not ok or type(list) ~= "table" then return nil end
        local first = list[1]
        if type(first) == "table" and type(first.mapID) == "number"
            and IsCoordinate(first.x) and IsCoordinate(first.y) then
            return first.mapID, first.x, first.y
        end
        return nil
    end
    if data.isDynamic or data.isRandom then return nil end
    if type(data.mapID) == "number" and IsCoordinate(data.x) and IsCoordinate(data.y) then
        return data.mapID, data.x, data.y
    end
    return nil
end

--- The continent a map belongs to: the map itself or the first continent up
-- its parent chain.
-- @param mapID number
-- @return number|nil, string|nil continent mapID, continent name
function MiniTeleportPanel.ContinentOf(mapID)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local current = mapID
    for _ = 1, 12 do  -- a guard against a parent cycle, far deeper than any real chain
        if type(current) ~= "number" or current <= 0 then return nil end
        local info = C_Map.GetMapInfo(current)
        if not info then return nil end
        if info.mapType == CONTINENT_MAP_TYPE then return current, info.name end
        current = info.parentMapID
    end
    return nil
end

--- Place an entry on its continent.
-- @param entry table
-- @return table|nil { continentID, continentName, x, y } with x, y in 0..1 of the continent
function MiniTeleportPanel.PlaceEntry(entry)
    local mapID, x, y = MiniTeleportPanel.DestinationPoint(entry)
    if not mapID then return nil end
    local continentID, continentName = MiniTeleportPanel.ContinentOf(mapID)
    if not continentID then return nil end
    local cx, cy = x, y
    if mapID ~= continentID then
        -- Without the zone's rectangle on the continent there is no honest spot
        -- for the cross; the entry goes to "Ohne festen Ort" rather than to a
        -- guessed position.
        if not C_Map.GetMapRectOnMap then return nil end
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, continentID)
        if not ok or type(minX) ~= "number" or type(maxX) ~= "number"
            or type(minY) ~= "number" or type(maxY) ~= "number" then
            return nil
        end
        cx = minX + x * (maxX - minX)
        cy = minY + y * (maxY - minY)
    end
    if not IsCoordinate(cx) or not IsCoordinate(cy) then return nil end
    return { continentID = continentID, continentName = continentName or "", x = cx, y = cy }
end

--- The base art layer of a map: its tile grid and the tile files.
-- @param mapID number
-- @return table|nil { layerWidth, layerHeight, tileWidth, tileHeight, cols, rows, tiles }
function MiniTeleportPanel.MapArt(mapID)
    if not mapID or not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then
        return nil
    end
    local layers = C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    if not layer or not layer.tileWidth or layer.tileWidth <= 0 or not layer.tileHeight or layer.tileHeight <= 0
        or not layer.layerWidth or layer.layerWidth <= 0 or not layer.layerHeight or layer.layerHeight <= 0 then
        return nil
    end
    local tiles = C_Map.GetMapArtLayerTextures(mapID, 1)
    if not tiles or #tiles == 0 then return nil end
    local cols = math_ceil(layer.layerWidth / layer.tileWidth)
    local rows = math_ceil(layer.layerHeight / layer.tileHeight)
    if #tiles < cols * rows then return nil end
    return {
        layerWidth = layer.layerWidth, layerHeight = layer.layerHeight,
        tileWidth = layer.tileWidth, tileHeight = layer.tileHeight,
        cols = cols, rows = rows, tiles = tiles,
    }
end

local function Clamp(value, low, high)
    if high < low then return low end
    return math_max(low, math_min(high, value))
end

--- The part of a map's art a view shows: a rectangle of the base layer with
-- the shape of the view, at least span art pixels wide (or the whole layer),
-- containing every point, as close to centred on them as the layer allows.
-- @param art table from MapArt
-- @param points table { {x, y}, ... } in 0..1 of the map
-- @param span number art pixels
-- @param aspect number view width / height
-- @return number, number, number, number left, top, width, height in art pixels
function MiniTeleportPanel.ArtWindow(art, points, span, aspect)
    local minX, maxX, minY, maxY = 1, 0, 1, 0
    for _, p in ipairs(points) do
        minX, maxX = math_min(minX, p.x), math_max(maxX, p.x)
        minY, maxY = math_min(minY, p.y), math_max(maxY, p.y)
    end
    if maxX < minX then minX, maxX, minY, maxY = 0.5, 0.5, 0.5, 0.5 end
    local lw, lh = art.layerWidth, art.layerHeight
    -- A quarter tile of margin keeps a cross off the very edge.
    local margin = art.tileWidth / 2
    local width = math_max(span, (maxX - minX) * lw + margin * 2, ((maxY - minY) * lh + margin * 2) * aspect)
    local height = width / aspect
    if width > lw then width = lw; height = width / aspect end
    if height > lh then height = lh; width = height * aspect end
    local cx, cy = (minX + maxX) / 2 * lw, (minY + maxY) / 2 * lh
    local left = Clamp(cx - width / 2, 0, lw - width)
    local top = Clamp(cy - height / 2, 0, lh - height)
    return left, top, width, height
end

--- Spread tokens so that no two overlap, each staying as near its own point
-- as it can. Tokens are placed in order; one that would overlap an earlier one
-- is moved to the nearest free spot on rings around its point. A pure
-- function of its inputs, so the layout can be checked without frames.
-- @param points table { {x, y}, ... } token centres in view pixels
-- @param size number token edge in pixels
-- @param width number view width
-- @param height number view height
-- @return table { {x, y}, ... } in the same order
function MiniTeleportPanel.SpreadTokens(points, size, width, height)
    local half = size / 2
    local step = size + 1   -- one pixel apart, so the clickable squares never touch
    local placed = {}
    local function fit(x, y)
        return Clamp(x, half, width - half), Clamp(y, half, height - half)
    end
    local function free(x, y)
        for _, p in ipairs(placed) do
            if math_abs(p.x - x) < step and math_abs(p.y - y) < step then return false end
        end
        return true
    end
    for i, point in ipairs(points) do
        local x, y = fit(point.x, point.y)
        if not free(x, y) then
            local found = false
            for ring = 1, 30 do
                local radius = ring * half
                local count = 8 * ring
                for k = 0, count - 1 do
                    local angle = 2 * math_pi * k / count
                    local nx, ny = fit(point.x + radius * math_cos(angle), point.y + radius * math_sin(angle))
                    if free(nx, ny) then x, y, found = nx, ny, true; break end
                end
                if found then break end
            end
        end
        placed[i] = { x = x, y = y }
    end
    return placed
end

-------------------------------------------------------------------------------
-- Map views: a frame that draws a window of a map's art, and a cross
-------------------------------------------------------------------------------

local function CreateMapView(parent, width, height)
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(width, height)
    view.viewWidth, view.viewHeight = width, height
    view.tiles = {}
    -- Shown where a map has no art, so the frame does not read as missing.
    local fill = view:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.18, 0.14, 0.09, 1)
    view.fill = fill
    return view
end

local function CreateMarker(parent)
    local marker = parent:CreateTexture(nil, "OVERLAY", nil, 2)
    marker:SetTexture(DESTINATION_MARKER)
    marker:SetSize(MARKER_SIZE, MARKER_SIZE)
    marker:Hide()
    return marker
end

--- Draw a window of art into a map view. Tile textures are created only when
-- this view needs more than it has ever had; a view drawn again with the same
-- continent creates nothing. Returns the scale (view pixels per art pixel).
-- @return number|nil scale, number left, number top (nil when there is no art)
local function DrawArt(view, art, left, top, width, height)
    local used = 0
    if art then
        local scale = view.viewWidth / width
        local tw, th = art.tileWidth, art.tileHeight
        local right, bottom = left + width, top + height
        local c0, c1 = math_floor(left / tw), math_min(art.cols - 1, math_floor((right - 0.001) / tw))
        local r0, r1 = math_floor(top / th), math_min(art.rows - 1, math_floor((bottom - 0.001) / th))
        for row = r0, r1 do
            for col = c0, c1 do
                -- The visible part of this tile, in art pixels. A layer that is
                -- not a whole number of tiles (1002x668) ends inside its last
                -- column and row; the clip at the layer size drops the blank rest.
                local tx0, ty0 = col * tw, row * th
                local ix0, ix1 = math_max(tx0, left), math_min(tx0 + tw, right, art.layerWidth)
                local iy0, iy1 = math_max(ty0, top), math_min(ty0 + th, bottom, art.layerHeight)
                if ix1 > ix0 and iy1 > iy0 then
                    used = used + 1
                    local tex = view.tiles[used]
                    if not tex then
                        tex = view:CreateTexture(nil, "ARTWORK")
                        view.tiles[used] = tex
                    end
                    local file = art.tiles[row * art.cols + col + 1]
                    if tex.qrFile ~= file then
                        tex:SetTexture(file)
                        tex.qrFile = file
                    end
                    tex:SetTexCoord((ix0 - tx0) / tw, (ix1 - tx0) / tw, (iy0 - ty0) / th, (iy1 - ty0) / th)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", view, "TOPLEFT", (ix0 - left) * scale, -(iy0 - top) * scale)
                    tex:SetSize((ix1 - ix0) * scale, (iy1 - iy0) * scale)
                    tex:Show()
                end
            end
        end
    end
    for i = used + 1, #view.tiles do view.tiles[i]:Hide() end
    view.tilesUsed = used
    if used == 0 then return nil end
    return view.viewWidth / width, left, top
end

--- Grey a map view and an icon for an entry on cooldown, or restore them.
local function SetDesaturated(region, desaturated)
    if region and region.SetDesaturated then region:SetDesaturated(desaturated) end
end

local function DimMapView(view, dimmed)
    if not view then return end
    for i = 1, view.tilesUsed or 0 do SetDesaturated(view.tiles[i], dimmed) end
end

--- Draw one entry's continent into a map view with the cross at its point.
-- @return boolean true when the cross is on the art
local function DrawEntryMap(view, marker, place)
    local art = MiniTeleportPanel.MapArt(place.continentID)
    if not art then
        DrawArt(view, nil)
        -- No art: the cross still marks the spot on the plain fill, scaled to
        -- the whole continent, which is where the point is.
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", view, "TOPLEFT", place.x * view.viewWidth, -place.y * view.viewHeight)
        marker:Show()
        return false
    end
    local left, top, width, height = MiniTeleportPanel.ArtWindow(art, { place },
        ENTRY_MAP_SPAN, view.viewWidth / view.viewHeight)
    local scale = DrawArt(view, art, left, top, width, height)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", view, "TOPLEFT",
        (place.x * art.layerWidth - left) * scale, -(place.y * art.layerHeight - top) * scale)
    marker:Show()
    return true
end

-------------------------------------------------------------------------------
-- Frame skin: Blizzard's wooden frame, or the old backdrop
-------------------------------------------------------------------------------

local function AtlasExists(atlas)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    return ok and info ~= nil
end
MiniTeleportPanel.AtlasExists = AtlasExists

--- The wooden nine-slice layout, when this client has it and every atlas it
-- names. Nil sends the panel to the backdrop.
function MiniTeleportPanel.WoodenLayout()
    local util, layouts = _G.NineSliceUtil, _G.NineSliceLayouts
    local layout = util and util.ApplyLayout and layouts and layouts.WoodenNeutralFrameTemplate
    if type(layout) ~= "table" then return nil end
    for _, atlas in ipairs(WOOD_ATLASES) do
        if not AtlasExists(atlas) then return nil end
    end
    return layout
end

local function ApplySkin(frame)
    local layout = MiniTeleportPanel.WoodenLayout()
    if layout then
        -- The pieces go on their own frame above the content, so the wood
        -- overlaps the content's edge the way Blizzard's frames do. It takes
        -- no mouse input: clicks fall through to the cards and overlays.
        local border = CreateFrame("Frame", nil, frame)
        border:SetAllPoints(frame)
        border:SetFrameLevel(frame:GetFrameLevel() + 20)
        local ok = pcall(_G.NineSliceUtil.ApplyLayout, border, layout)
        if ok then
            local bg = frame:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
            bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
            bg:SetColorTexture(0.16, 0.11, 0.07, 0.97)  -- a dark table top under the maps
            frame.woodBorder = border
            frame.skin = "wood"
            return
        end
        border:Hide()
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    frame.skin = "backdrop"
end

-------------------------------------------------------------------------------
-- Saved settings: view and position
-------------------------------------------------------------------------------

function MiniTeleportPanel:GetView()
    local view = QR.db and QR.db.miniPanelView
    if VALID_VIEW[view] then return view end
    return DEFAULT_VIEW
end

--- Switch the view and keep the choice.
-- @param view string "tiles", "table" or "journal"
function MiniTeleportPanel:SetView(view)
    if not VALID_VIEW[view] then return end
    if QR.db then QR.db.miniPanelView = view end
    self:UpdateViewButtons()
    -- Rebuilding releases and takes secure buttons, which lockdown forbids;
    -- the choice is kept and applied on the next open.
    if self.frame and self.isShowing and not InCombatLockdown() then
        self.frame.signature = nil
        self:RefreshList()
    end
end

local function SavePosition(frame)
    if not QR.db then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    QR.db.miniPanelPoint, QR.db.miniPanelRelPoint, QR.db.miniPanelX, QR.db.miniPanelY = point, relPoint, x, y
end

--- Put the panel where the player left it, or at the minimap button.
-- @return boolean true when a saved position was used
function MiniTeleportPanel:ApplyPosition()
    if not self.frame then return false end
    local db = QR.db or {}
    if QR.IsValidWindowPosition and QR.IsValidWindowPosition(db.miniPanelPoint, db.miniPanelRelPoint,
        db.miniPanelX, db.miniPanelY) then
        self.frame:ClearAllPoints()
        self.frame:SetPoint(db.miniPanelPoint, UIParent, db.miniPanelRelPoint, db.miniPanelX, db.miniPanelY)
        return true
    end
    self:AnchorToMinimapButton()
    return false
end

-------------------------------------------------------------------------------
-- Frame Creation
-------------------------------------------------------------------------------

local function ShowViewTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:AddLine(L[button.view.label], 1, 0.82, 0)
    GameTooltip:AddLine(L[button.view.tip], 1, 1, 1, true)
    QR.AddTooltipBranding(GameTooltip)
    GameTooltip:Show()
end

--- Create the panel frame
-- @return Frame The panel frame
function MiniTeleportPanel:CreateFrame()
    if self.frame then return self.frame end
    L = QR.L

    local frame = CreateFrame("Frame", "QRMiniTeleportPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, TITLE_HEIGHT + PADDING * 2)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    ApplySkin(frame)

    -- Title bar: the drag handle. The secure overlays sit on the cards inside
    -- the scroll frame below it and are hidden once a card scrolls past the
    -- scroll frame's top, so none of them can cover this strip.
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING + 2)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING + 2)
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
    end)
    frame.titleBar = titleBar

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 2, 0)
    title:SetJustifyH("LEFT")
    frame.title = title

    -- View switch: three icon buttons at the right of the title bar.
    frame.viewButtons = {}
    local previous
    for i = #VIEWS, 1, -1 do
        local view = VIEWS[i]
        local button = CreateFrame("Button", nil, titleBar)
        button:SetSize(20, 20)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -3, 0)
        else
            button:SetPoint("RIGHT", titleBar, "RIGHT", 0, 0)
        end
        local glow = button:CreateTexture(nil, "BACKGROUND")
        glow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        glow:SetColorTexture(1, 0.82, 0, 0.55)
        button.glow = glow
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(view.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon = icon
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.2)
        button.view = view
        button:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            MiniTeleportPanel:SetView(view.key)
        end)
        button:SetScript("OnEnter", ShowViewTooltip)
        button:SetScript("OnLeave", function() GameTooltip_Hide() end)
        frame.viewButtons[view.key] = button
        previous = button
    end

    -- Scroll frame for the content (modern thin scrollbar)
    local scrollFrame = CreateFrame("ScrollFrame", "QRMiniTPScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(TITLE_HEIGHT + PADDING))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING - 10, PADDING)
    QR.SkinScrollBar(scrollFrame)

    -- Parchment behind the travel journal: Blizzard's quest log paper where
    -- the client has the atlas, a tinted fill where it does not.
    local parchment = frame:CreateTexture(nil, "BORDER")
    parchment:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -2, 2)
    parchment:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 2, -2)
    if AtlasExists(PARCHMENT_ATLAS) then
        parchment:SetAtlas(PARCHMENT_ATLAS)
    else
        parchment:SetColorTexture(0.80, 0.70, 0.52, 1)
    end
    parchment:Hide()
    frame.parchment = parchment

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(ROW_WIDTH)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild

    -- Heading of the section for entries without a drawable point.
    local unplacedHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unplacedHeader:SetJustifyH("LEFT")
    unplacedHeader:Hide()
    frame.unplacedHeader = unplacedHeader

    -- ESC to close
    table_insert(UISpecialFrames, "QRMiniTeleportPanel")

    -- Sync isShowing on hide. OnHide also fires when an ancestor is hidden
    -- (Alt+Z, a cinematic) and that is not a close: the panel comes back on its
    -- own with its rows and secure buttons intact. Clearing isShowing there
    -- disarmed the enter-combat callback, which is gated on it, so the panel
    -- and its overlay buttons stayed on screen for the whole next fight. The
    -- frame's own IsShown() is still true when an ancestor did the hiding.
    frame:SetScript("OnHide", function(f)
        if f:IsShown() then
            return
        end
        self.isShowing = false
    end)

    frame:Hide()
    self.frame = frame
    self:UpdateViewButtons()
    return frame
end

function MiniTeleportPanel:UpdateViewButtons()
    local buttons = self.frame and self.frame.viewButtons
    if not buttons then return end
    local current = self:GetView()
    for key, button in pairs(buttons) do
        local selected = key == current
        button.glow:SetShown(selected)
        SetDesaturated(button.icon, not selected)
        button.selected = selected
    end
end

-------------------------------------------------------------------------------
-- Pooled elements. Each carries icon, nameLabel (the item), destLabel (where
-- it goes) and statusLabel (the cooldown), whatever the view, so status
-- updates and the tests read every view the same way.
-------------------------------------------------------------------------------

local function TakeFromPool(pool, parent)
    for _, element in ipairs(pool) do
        if not element.inUse then
            element.inUse = true
            element:SetParent(parent)
            element:ClearAllPoints()
            element:Show()
            return element
        end
    end
end

local function ReleasePool(pool)
    for _, element in ipairs(pool) do
        if element.inUse then
            element.inUse = false
            element:Hide()
            element:SetParent(recycleContainer)
        end
    end
end

--- Create or recycle a plain or journal row.
-- @return Frame A row frame
function MiniTeleportPanel:GetRow()
    local row = TakeFromPool(self.rowPool, self.frame.scrollChild)
    if row then return row end

    row = CreateFrame("Frame", nil, self.frame.scrollChild)
    row:SetHeight(ROW_HEIGHT)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon = icon

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    row.nameLabel = nameLabel

    local destLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    destLabel:SetJustifyH("LEFT")
    destLabel:SetWordWrap(false)
    row.destLabel = destLabel

    local statusLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetJustifyH("RIGHT")
    statusLabel:SetWidth(STATUS_WIDTH)
    row.statusLabel = statusLabel

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)

    -- The journal's map thumbnail; created with the row, shown only there.
    local thumb = CreateMapView(row, THUMB_WIDTH, THUMB_HEIGHT)
    thumb:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.mapView = thumb
    row.marker = CreateMarker(thumb)

    row.inUse = true
    table_insert(self.rowPool, row)
    return row
end

--- Lay a row out as a plain line (icon, name, destination, status) or as a
-- journal row (icon, destination large over the item name, thumbnail).
local function LayoutRow(row, journal, onParchment)
    row.icon:ClearAllPoints()
    row.nameLabel:ClearAllPoints()
    row.destLabel:ClearAllPoints()
    row.statusLabel:ClearAllPoints()
    if journal then
        row:SetHeight(JOURNAL_ROW_HEIGHT)
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        local textWidth = ROW_WIDTH - 4 - 30 - 6 - STATUS_WIDTH - THUMB_WIDTH - 8
        row.destLabel:SetFontObject(GameFontNormal)
        row.destLabel:SetJustifyH("LEFT")  -- a font object carries its own justification
        row.destLabel:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
        row.destLabel:SetWidth(textWidth)
        row.nameLabel:SetFontObject(GameFontHighlightSmall)
        row.nameLabel:SetJustifyH("LEFT")
        row.nameLabel:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
        row.nameLabel:SetWidth(textWidth)
        row.statusLabel:SetPoint("RIGHT", row.mapView, "LEFT", -4, 0)
        row.mapView:Show()
    else
        row:SetHeight(ROW_HEIGHT)
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.nameLabel:SetFontObject(GameFontNormalSmall)
        row.nameLabel:SetJustifyH("LEFT")
        row.nameLabel:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.nameLabel:SetWidth(NAME_WIDTH)
        row.destLabel:SetFontObject(GameFontHighlightSmall)
        row.destLabel:SetJustifyH("LEFT")
        row.destLabel:SetPoint("LEFT", row.nameLabel, "RIGHT", 4, 0)
        row.destLabel:SetWidth(DEST_WIDTH)
        row.statusLabel:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.mapView:Hide()
        row.marker:Hide()
    end
    -- Dark ink on parchment, the usual light text on the dark table. The
    -- templates' black drop shadow smears dark ink on light paper, so it is
    -- dropped there, as on the quest log's parchment.
    local shadow = onParchment and 0 or 1
    for _, label in ipairs({ row.nameLabel, row.destLabel, row.statusLabel }) do
        if label.SetShadowOffset then label:SetShadowOffset(shadow, -shadow) end
    end
    if onParchment then
        row.nameLabel:SetTextColor(0.16, 0.08, 0.02)
        row.destLabel:SetTextColor(0.10, 0.05, 0)
    else
        row.nameLabel:SetTextColor(1, 1, 1)
        row.destLabel:SetTextColor(0.85, 0.85, 0.85)
    end
end

--- Create or recycle a view A card.
function MiniTeleportPanel:GetCard()
    local card = TakeFromPool(self.cardPool, self.frame.scrollChild)
    if card then return card end

    card = CreateFrame("Frame", nil, self.frame.scrollChild)
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)

    -- A thin dark frame around the map, like a card on the table.
    local edge = card:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", 0, -(CARD_MAP_HEIGHT + 2))
    edge:SetColorTexture(0.05, 0.03, 0.02, 1)

    local mapView = CreateMapView(card, CARD_WIDTH - 2, CARD_MAP_HEIGHT)
    mapView:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    card.mapView = mapView
    card.marker = CreateMarker(mapView)

    -- Continent banner, top left on the map.
    local bannerBg = mapView:CreateTexture(nil, "OVERLAY")
    bannerBg:SetPoint("TOPLEFT", mapView, "TOPLEFT", 0, 0)
    bannerBg:SetSize(CARD_WIDTH - 2, 13)
    bannerBg:SetColorTexture(0.10, 0.06, 0.03, 0.75)
    local banner = mapView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banner:SetPoint("TOPLEFT", mapView, "TOPLEFT", 3, -1)
    banner:SetWidth(CARD_WIDTH - 8)
    banner:SetJustifyH("LEFT")
    banner:SetWordWrap(false)
    card.banner = banner

    -- Shade over the map while on cooldown, with the remaining time on it.
    local shade = mapView:CreateTexture(nil, "OVERLAY", nil, 1)
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.5)
    shade:Hide()
    card.shade = shade

    local icon = mapView:CreateTexture(nil, "OVERLAY", nil, 3)
    icon:SetSize(CARD_ICON_SIZE, CARD_ICON_SIZE)
    icon:SetPoint("BOTTOMLEFT", mapView, "BOTTOMLEFT", 3, 3)
    card.icon = icon

    local statusLabel = mapView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabel:SetPoint("CENTER", mapView, "CENTER", 0, 0)
    statusLabel:SetWidth(CARD_WIDTH - 8)
    statusLabel:SetJustifyH("CENTER")
    card.statusLabel = statusLabel

    local destLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    destLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -(CARD_MAP_HEIGHT + 4))
    destLabel:SetWidth(CARD_WIDTH - 2)
    destLabel:SetJustifyH("LEFT")
    destLabel:SetWordWrap(false)
    card.destLabel = destLabel

    local nameLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", destLabel, "BOTTOMLEFT", 0, -2)
    nameLabel:SetWidth(CARD_WIDTH - 2)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    card.nameLabel = nameLabel

    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    card.inUse = true
    table_insert(self.cardPool, card)
    return card
end

--- Create or recycle a view B continent panel.
function MiniTeleportPanel:GetPanel()
    local panel = TakeFromPool(self.panelPool, self.frame.scrollChild)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, self.frame.scrollChild)
    panel:SetSize(TABLE_PANEL_WIDTH, TABLE_PANEL_HEIGHT)
    local edge = panel:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.05, 0.03, 0.02, 1)
    local mapView = CreateMapView(panel, TABLE_PANEL_WIDTH - 2, TABLE_PANEL_HEIGHT - 2)
    mapView:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    panel.mapView = mapView
    local bannerBg = mapView:CreateTexture(nil, "OVERLAY")
    bannerBg:SetPoint("TOPLEFT", mapView, "TOPLEFT", 0, 0)
    bannerBg:SetSize(TABLE_PANEL_WIDTH - 2, 13)
    bannerBg:SetColorTexture(0.10, 0.06, 0.03, 0.75)
    local banner = mapView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banner:SetPoint("TOPLEFT", mapView, "TOPLEFT", 3, -1)
    banner:SetWidth(TABLE_PANEL_WIDTH - 8)
    banner:SetJustifyH("LEFT")
    banner:SetWordWrap(false)
    panel.banner = banner

    panel.inUse = true
    table_insert(self.panelPool, panel)
    return panel
end

--- Create or recycle a view B token: the icon, pinned near its cross.
function MiniTeleportPanel:GetToken(parent)
    local token = TakeFromPool(self.tokenPool, parent)
    if token then return token end

    token = CreateFrame("Frame", nil, parent)
    token:SetSize(TOKEN_SIZE, TOKEN_SIZE)
    local ring = token:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT", token, "TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", token, "BOTTOMRIGHT", 1, -1)
    ring:SetColorTexture(0.08, 0.05, 0.02, 1)
    local icon = token:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    token.icon = icon
    -- The cross stays on the true point; the token sits beside it when it had
    -- to make room, joined to it by a short line.
    token.marker = CreateMarker(token)
    if token.CreateLine then
        local line = token:CreateLine(nil, "ARTWORK")
        line:SetColorTexture(0.9, 0.15, 0.1, 0.9)
        if line.SetThickness then line:SetThickness(1) end
        line:Hide()
        token.leader = line
    end
    local statusLabel = token:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("TOP", token, "BOTTOM", 0, -1)
    statusLabel:SetWidth(TOKEN_SIZE * 3)
    statusLabel:SetJustifyH("CENTER")
    token.statusLabel = statusLabel
    -- Names travel in the tooltip; the token itself is only the icon.
    token.nameLabel = token:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    token.nameLabel:Hide()
    token.destLabel = token:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    token.destLabel:Hide()

    token.inUse = true
    table_insert(self.tokenPool, token)
    return token
end

--- Release all rows back to pool
function MiniTeleportPanel:ReleaseAllRows()
    if self.separator then
        self.separator:Hide()
    end
    if self.frame and self.frame.unplacedHeader then
        self.frame.unplacedHeader:Hide()
    end
    -- Release secure buttons. No lockdown guard here: ReleaseButton queues the
    -- button in pendingReleases when it cannot touch it, and the leave-combat
    -- handler flushes that queue. Skipping the call under lockdown and then
    -- dropping self.secureButtons anyway lost the only reference to each held
    -- button, leaking two pool slots per combat start until all 60 were gone.
    if QR.SecureButtons then
        for _, btn in ipairs(self.secureButtons) do
            QR.SecureButtons:ReleaseButton(btn)
        end
    end
    self.secureButtons = {}

    ReleasePool(self.rowPool)
    ReleasePool(self.cardPool)
    ReleasePool(self.tokenPool)
    ReleasePool(self.panelPool)
    self.rows = {}
    self.elementById = {}
    -- The next refresh builds the view again rather than updating statuses.
    -- Kept on the frame, so a new frame never inherits an old one's elements.
    if self.frame then self.frame.signature = nil end
end

--- Close the popup once a row was used. Deferred one frame, so the secure
-- action of the click has run before the rows release their buttons.
local function CloseAfterUse()
    C_Timer.After(0, function()
        if MiniTeleportPanel.isShowing and not InCombatLockdown() then MiniTeleportPanel:Hide() end
    end)
end

--- Get the icon texture for a teleport entry
-- @param entry table The teleport entry
-- @return string|number The icon texture path or ID
local function GetTeleportIcon(entry)
    if entry.isSpell then
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(entry.id)
            if info and info.iconID then return info.iconID end
        end
        if GetSpellInfo then
            local _, _, icon = GetSpellInfo(entry.id)
            if icon then return icon end
        end
    else
        if C_Item and C_Item.GetItemIconByID then
            local icon = C_Item.GetItemIconByID(entry.id)
            if icon then return icon end
        end
        if GetItemIcon then
            local icon = GetItemIcon(entry.id)
            if icon then return icon end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-------------------------------------------------------------------------------
-- Shared per-entry wiring: texts, cooldown state, secure overlay
-------------------------------------------------------------------------------

local function StatusText(entry)
    -- READY/OWNED show nothing; ON_CD shows the countdown.
    if entry.status == STATUS.READY or entry.status == STATUS.OWNED then
        return ""
    elseif entry.status == STATUS.ON_CD then
        local timeStr = QR.CooldownTracker and QR.CooldownTracker:FormatTime(entry.cooldownRemaining) or "?"
        return entry.status.color .. timeStr .. "|r"
    end
    return entry.status.color .. (L[entry.status.key] or "?") .. "|r"
end

--- Update what a cooldown tick changes: the status text and the dimming.
local function ApplyStatus(element, entry)
    element.statusLabel:SetText(StatusText(entry))
    local dimmed = entry.status == STATUS.ON_CD
    if element.dimmed == dimmed then return end
    element.dimmed = dimmed
    SetDesaturated(element.icon, dimmed)
    DimMapView(element.mapView, dimmed)
    if element.shade then element.shade:SetShown(dimmed) end
    if element.SetAlpha and element.isToken then element:SetAlpha(dimmed and 0.75 or 1) end
end

local function FillTexts(element, entry)
    element.icon:SetTexture(GetTeleportIcon(entry))
    SetTextFitted(element.nameLabel, GetLocalizedName(entry))
    SetTextFitted(element.destLabel, GetLocalizedDestination(entry))
    element.dimmed = nil
    ApplyStatus(element, entry)
end

local function ShowEntryTooltip(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if btn.sourceType == "spell" then
        GameTooltip:SetSpellByID(btn.teleportID)
    else
        GameTooltip:SetItemByID(btn.teleportID)
    end
    if btn.qrDestination and btn.qrDestination ~= "" then
        GameTooltip:AddLine(btn.qrDestination, 1, 1, 1)
    end
    QR.AddTooltipBranding(GameTooltip)
    GameTooltip:Show()
end

--- Lay an invisible secure button over an element, configured for its entry.
function MiniTeleportPanel:AttachSecure(element, entry, width, height)
    if not QR.SecureButtons or InCombatLockdown() then return end
    local secBtn = QR.SecureButtons:GetButton()
    if not secBtn then return end
    local sourceType = entry.isSpell and "spell" or (entry.data.type == QR.TeleportTypes.TOY and "toy" or "item")
    local configured = QR.SecureButtons:ConfigureButton(secBtn, entry.id, sourceType, entry.data)
    if not configured then
        QR.SecureButtons:ReleaseButton(secBtn)
        return
    end
    secBtn:SetSize(width, height)
    QR.SecureButtons:AttachOverlay(secBtn, element, self.frame.scrollFrame, 0, true)
    secBtn:SetAlpha(0)  -- Invisible overlay, the element provides visuals
    secBtn.qrAfterUse = CloseAfterUse
    secBtn.qrDestination = GetLocalizedDestination(entry)
    secBtn:SetScript("OnEnter", ShowEntryTooltip)
    secBtn:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)
    table_insert(self.secureButtons, secBtn)
end

-------------------------------------------------------------------------------
-- Views. Each lays out its placed entries from the top of the scroll child and
-- returns the height it used; the "Ohne festen Ort" section follows.
-------------------------------------------------------------------------------

local function SortByContinent(placed)
    table_sort(placed, function(a, b)
        if a.place.continentName ~= b.place.continentName then
            return a.place.continentName < b.place.continentName
        end
        local da, db = GetLocalizedDestination(a), GetLocalizedDestination(b)
        if da ~= db then return da < db end
        return a.id < b.id
    end)
end

--- View A: a grid of cards, continent by continent.
function MiniTeleportPanel:LayoutTiles(placed)
    SortByContinent(placed)
    local scrollChild = self.frame.scrollChild
    for i, entry in ipairs(placed) do
        local card = self:GetCard()
        local col = (i - 1) % CARD_COLUMNS
        local row = math_floor((i - 1) / CARD_COLUMNS)
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
            col * (CARD_WIDTH + CARD_GAP), -row * (CARD_HEIGHT + CARD_GAP))
        card.banner:SetText(entry.place.continentName)
        DrawEntryMap(card.mapView, card.marker, entry.place)
        FillTexts(card, entry)
        self:AttachSecure(card, entry, CARD_WIDTH, CARD_HEIGHT)
        table_insert(self.rows, card)
        self.elementById[entry.id] = card
    end
    if #placed == 0 then return 0 end
    local rows = math_ceil(#placed / CARD_COLUMNS)
    return rows * CARD_HEIGHT + (rows - 1) * CARD_GAP + CARD_GAP
end

--- View B: one table, a panel per continent, each teleport a token on it.
function MiniTeleportPanel:LayoutTable(placed)
    SortByContinent(placed)
    local groups, order = {}, {}
    for _, entry in ipairs(placed) do
        local id = entry.place.continentID
        if not groups[id] then
            groups[id] = { name = entry.place.continentName, entries = {} }
            table_insert(order, id)
        end
        table_insert(groups[id].entries, entry)
    end

    local scrollChild = self.frame.scrollChild
    self.tableLayout = {}
    for i, continentID in ipairs(order) do
        local group = groups[continentID]
        local panel = self:GetPanel()
        local col = (i - 1) % TABLE_COLUMNS
        local row = math_floor((i - 1) / TABLE_COLUMNS)
        panel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
            col * (TABLE_PANEL_WIDTH + TABLE_GAP), -row * (TABLE_PANEL_HEIGHT + TABLE_GAP))
        panel.banner:SetText(group.name)

        local view = panel.mapView
        local w, h = view.viewWidth, view.viewHeight
        local places = {}
        for k, entry in ipairs(group.entries) do places[k] = entry.place end
        -- Where each cross goes, in view pixels.
        local art = MiniTeleportPanel.MapArt(continentID)
        local crosses = {}
        if art then
            local left, top, width, height = MiniTeleportPanel.ArtWindow(art, places, TABLE_MAP_SPAN, w / h)
            local scale = DrawArt(view, art, left, top, width, height)
            for k, place in ipairs(places) do
                crosses[k] = { x = (place.x * art.layerWidth - left) * scale,
                               y = (place.y * art.layerHeight - top) * scale }
            end
        else
            DrawArt(view, nil)
            for k, place in ipairs(places) do crosses[k] = { x = place.x * w, y = place.y * h } end
        end
        -- A token hangs just below its cross, so the icon never hides it.
        local wanted = {}
        for k, cross in ipairs(crosses) do
            wanted[k] = { x = cross.x, y = cross.y + TOKEN_OFFSET }
        end
        local spots = MiniTeleportPanel.SpreadTokens(wanted, TOKEN_SIZE, w, h)
        self.tableLayout[continentID] = { crosses = crosses, tokens = spots }

        for k, entry in ipairs(group.entries) do
            local token = self:GetToken(view)
            token.isToken = true
            local spot, cross = spots[k], crosses[k]
            token:SetPoint("CENTER", view, "TOPLEFT", spot.x, -spot.y)
            token.layoutX, token.layoutY = spot.x, spot.y
            local dx, dy = cross.x - spot.x, cross.y - spot.y
            token.marker:ClearAllPoints()
            token.marker:SetPoint("CENTER", token, "CENTER", dx, -dy)
            token.marker:Show()
            if token.leader then
                local want = wanted[k]
                if math_abs(spot.x - want.x) > TOKEN_SIZE / 2 or math_abs(spot.y - want.y) > TOKEN_SIZE / 2 then
                    token.leader:SetStartPoint("CENTER", token, 0, 0)
                    token.leader:SetEndPoint("CENTER", token, dx, -dy)
                    token.leader:Show()
                else
                    token.leader:Hide()
                end
            end
            FillTexts(token, entry)
            self:AttachSecure(token, entry, TOKEN_SIZE, TOKEN_SIZE)
            table_insert(self.rows, token)
            self.elementById[entry.id] = token
        end
    end
    if #order == 0 then return 0 end
    local rows = math_ceil(#order / TABLE_COLUMNS)
    return rows * TABLE_PANEL_HEIGHT + (rows - 1) * TABLE_GAP + TABLE_GAP
end

--- View C: the travel journal, one row per teleport with a thumbnail.
function MiniTeleportPanel:LayoutJournal(placed)
    local scrollChild = self.frame.scrollChild
    local yOffset = 0
    for _, entry in ipairs(placed) do
        local row = self:GetRow()
        LayoutRow(row, true, true)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        DrawEntryMap(row.mapView, row.marker, entry.place)
        FillTexts(row, entry)
        self:AttachSecure(row, entry, ROW_WIDTH, JOURNAL_ROW_HEIGHT)
        table_insert(self.rows, row)
        self.elementById[entry.id] = row
        yOffset = yOffset + JOURNAL_ROW_HEIGHT
    end
    return yOffset
end

local LAYOUTS = {
    [VIEW_TILES] = MiniTeleportPanel.LayoutTiles,
    [VIEW_TABLE] = MiniTeleportPanel.LayoutTable,
    [VIEW_JOURNAL] = MiniTeleportPanel.LayoutJournal,
}

-------------------------------------------------------------------------------
-- Refresh & Display
-------------------------------------------------------------------------------

--- An identity for what the view shows: the view and the teleports in their
-- order, each with its name, destination and landing. While it holds, a
-- refresh only updates cooldown texts and dimming; the cards, their map
-- textures and the secure buttons stay as they are. Names and landings are
-- part of it because they can arrive while the popup is open: an item name
-- the client had not cached yet, a housing plot or inn recorded later.
local function Signature(view, teleports)
    local parts = { view }
    for i, entry in ipairs(teleports) do
        local mapID, x, y = MiniTeleportPanel.DestinationPoint(entry)
        parts[i + 1] = table_concat({ tostring(entry.id), GetLocalizedName(entry), GetLocalizedDestination(entry),
            tostring(mapID), tostring(x), tostring(y) }, "|")
    end
    return table_concat(parts, ",")
end

--- Refresh the teleport list
function MiniTeleportPanel:RefreshList()
    if not self.frame then return end

    if QR.CooldownTracker then QR.CooldownTracker:WatchActiveCooldowns() end

    L = QR.L
    local view = self:GetView()
    local teleports = CollectOwnedTeleports()

    local signature = Signature(view, teleports)
    if signature == self.frame.signature and self.elementById then
        for _, entry in ipairs(teleports) do
            local element = self.elementById[entry.id]
            if element then ApplyStatus(element, entry) end
        end
        return
    end

    self:ReleaseAllRows()
    self.frame.title:SetText(L["MINI_PANEL_TITLE"])
    self.frame.parchment:SetShown(view == VIEW_JOURNAL)
    local onParchment = view == VIEW_JOURNAL

    if #teleports == 0 then
        -- Show "no teleports" message
        local row = self:GetRow()
        LayoutRow(row, false, onParchment)
        row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
        row.icon:SetTexture(nil)
        row.nameLabel:SetWidth(LABEL_AREA + COLUMN_GAP)
        SetTextFitted(row.nameLabel, L["MINI_PANEL_NO_TELEPORTS"])
        row.nameLabel:SetTextColor(0.5, 0.5, 0.5)
        row.destLabel:SetText("")
        row.statusLabel:SetText("")
        table_insert(self.rows, row)

        local totalHeight = TITLE_HEIGHT + ROW_HEIGHT + PADDING * 3
        self.frame:SetHeight(totalHeight)
        self.frame.scrollChild:SetHeight(ROW_HEIGHT)
        self.frame.signature = signature
        return
    end

    -- Split into entries with a point on a continent and the rest.
    local placed, unplaced = {}, {}
    for _, entry in ipairs(teleports) do
        entry.place = MiniTeleportPanel.PlaceEntry(entry)
        table_insert(entry.place and placed or unplaced, entry)
    end

    local yOffset = LAYOUTS[view](self, placed)

    -- "Ohne festen Ort": random landings, entries without a drawable point, and
    -- the mount row, below a separator. Created once and re-anchored: this used
    -- to build a fresh Frame on every refresh and never hide or reuse it, so
    -- each refresh left another 1px line behind in the scroll child.
    local scrollChild = self.frame.scrollChild
    if not self.separator then
        local separator = CreateFrame("Frame", nil, scrollChild)
        separator:SetHeight(1)
        local sepTex = separator:CreateTexture(nil, "ARTWORK")
        sepTex:SetAllPoints()
        sepTex:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        self.separator = separator
    end
    self.separator:ClearAllPoints()
    self.separator:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -yOffset - 3)
    self.separator:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)
    self.separator:Show()
    yOffset = yOffset + SECTION_GAP

    local header = self.frame.unplacedHeader
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -yOffset)
    header:SetText(L["MINI_PANEL_NO_FIXED_PLACE"])
    if onParchment then
        header:SetTextColor(0.35, 0.12, 0.02)
        header:SetShadowOffset(0, 0)
    else
        header:SetTextColor(1, 0.82, 0)
        header:SetShadowOffset(1, -1)
    end
    header:Show()
    yOffset = yOffset + HEADER_HEIGHT

    for _, entry in ipairs(unplaced) do
        local row = self:GetRow()
        LayoutRow(row, false, onParchment)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        FillTexts(row, entry)
        self:AttachSecure(row, entry, ROW_WIDTH, ROW_HEIGHT)
        table_insert(self.rows, row)
        self.elementById[entry.id] = row
        yOffset = yOffset + ROW_HEIGHT
    end

    -- Mount button row
    local mountRow = self:GetRow()
    LayoutRow(mountRow, false, onParchment)
    mountRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    mountRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    mountRow.icon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    SetDesaturated(mountRow.icon, false)
    mountRow.dimmed = nil
    SetTextFitted(mountRow.nameLabel, L["MINI_PANEL_SUMMON_MOUNT"])
    SetTextFitted(mountRow.destLabel, L["MINI_PANEL_RANDOM_FAVORITE"])
    mountRow.statusLabel:SetText("")

    -- Secure macro button for mount summon
    if QR.SecureButtons and not InCombatLockdown() then
        local secBtn = QR.SecureButtons:GetButton()
        if secBtn then
            secBtn:SetAttribute("type", "macro")
            secBtn:SetAttribute("macrotext", "/run C_MountJournal.SummonByID(0)")
            secBtn:SetScript("PostClick", function(_, button)
                if button == "LeftButton" then CloseAfterUse() end
            end)
            secBtn:SetSize(ROW_WIDTH, ROW_HEIGHT)
            QR.SecureButtons:AttachOverlay(secBtn, mountRow, self.frame.scrollFrame, 0, true)
            secBtn:SetAlpha(0)

            secBtn:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L["MINI_PANEL_SUMMON_MOUNT"], 1, 0.82, 0)
                GameTooltip:AddLine(L["MINI_PANEL_RANDOM_FAVORITE"], 1, 1, 1)
                QR.AddTooltipBranding(GameTooltip)
                GameTooltip:Show()
            end)
            secBtn:SetScript("OnLeave", function()
                GameTooltip_Hide()
            end)

            table_insert(self.secureButtons, secBtn)
        end
    end

    table_insert(self.rows, mountRow)
    yOffset = yOffset + ROW_HEIGHT

    local contentHeight = yOffset
    local visibleHeight = math_min(contentHeight, MAX_CONTENT_HEIGHT)
    self.frame:SetHeight(TITLE_HEIGHT + visibleHeight + PADDING * 3)
    self.frame.scrollChild:SetHeight(contentHeight)
    self.frame.signature = signature
end

--- Anchor the panel to the minimap button
function MiniTeleportPanel:AnchorToMinimapButton()
    if not self.frame then return end

    local btn = QR.MinimapButton and QR.MinimapButton.button
    if btn then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPRIGHT", btn, "BOTTOMLEFT", 0, -4)
    else
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 0, -4)
    end
end

-------------------------------------------------------------------------------
-- Show / Hide / Toggle
-------------------------------------------------------------------------------

function MiniTeleportPanel:Show()
    if InCombatLockdown() then
        QR:Print(L["CANNOT_USE_IN_COMBAT"])
        return
    end

    if not self.frame then
        self:CreateFrame()
    end

    self:ApplyPosition()
    self:UpdateViewButtons()
    self.frame.signature = nil
    self:RefreshList()
    self.frame:Show()
    self.isShowing = true
    if QR.CooldownTracker then QR.CooldownTracker:WatchActiveCooldowns() end
end

function MiniTeleportPanel:Hide()
    if self.frame then
        if not InCombatLockdown() then
            self:ReleaseAllRows()
        end
        self.frame:Hide()
    end
    self.isShowing = false
end

function MiniTeleportPanel:Toggle()
    if self.isShowing then
        self:Hide()
    else
        self:Show()
    end
end

-------------------------------------------------------------------------------
-- Combat Integration
-------------------------------------------------------------------------------

--- Initialize combat callbacks for auto-hide
function MiniTeleportPanel:RegisterCombat()
    QR:RegisterCombatCallback(
        -- Enter combat: release the rows, then hide the panel.
        -- Hiding the frame does not hide the secure overlay buttons: those are
        -- parented to UIParent, not to this panel, so they stayed on screen at
        -- alpha 0 for the whole fight and kept their slots in the 60-button
        -- pool. Lockdown is already active here -- PLAYER_REGEN_DISABLED marks
        -- its start -- so the releases queue and are flushed on leave.
        function()
            if MiniTeleportPanel.isShowing and MiniTeleportPanel.frame then
                MiniTeleportPanel:ReleaseAllRows()
                MiniTeleportPanel.frame:Hide()
                MiniTeleportPanel.isShowing = false
            end
        end
    )
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function MiniTeleportPanel:Initialize()
    L = QR.L
    self:RegisterCombat()
    if QR.CooldownTracker then
        QR.CooldownTracker:RegisterListener(self, function() self:RefreshList() end, function()
            return self.isShowing and self.frame and self.frame:IsVisible()
        end)
    end
    QR:Debug("MiniTeleportPanel initialized")
end
