-------------------------------------------------------------------------------
-- mock_wow_api.lua
-- WoW API mock framework for standalone Lua 5.1 testing
-- Simulates enough of the WoW environment to load and test the
-- QuickRoute addon outside of the game client.
-------------------------------------------------------------------------------

local MockWoW = {}

-------------------------------------------------------------------------------
-- Configurable State
-- Tests can modify these tables to simulate different player states.
-------------------------------------------------------------------------------

MockWoW.config = {
    -- Player identity
    playerFaction = "Alliance",       -- "Alliance" or "Horde"
    playerClass = "MAGE",            -- Uppercase class token
    playerClassName = "Mage",        -- Display name
    playerName = "Testplayer",
    playerLevel = 80,

    -- Current location
    currentMapID = 84,               -- Stormwind City
    playerX = 0.5,
    playerY = 0.5,

    -- Locale
    locale = "enUS",

    -- Player capabilities
    isFlyableArea = true,
    inCombatLockdown = false,

    -- Items the player has in bags: { [itemID] = { bagID, slot, count } }
    bagItems = {},

    -- Toys the player owns: { [itemID] = true }
    ownedToys = {},

    -- Spells the player knows: { [spellID] = true }
    knownSpells = {},

    -- Item counts: { [itemID] = count }
    itemCounts = {},

    -- Equipped items: { [slotID] = itemID }
    equippedItems = {},

    -- Professions: { { name, icon, skillLevel, maxSkill, numAbilities, spellOffset, skillLineID }, ... }
    professions = {},

    -- Cooldowns: { [id] = { start, duration, enable } }
    itemCooldowns = {},
    spellCooldowns = {},

    -- User waypoint state
    hasUserWaypoint = false,
    userWaypoint = nil,  -- { uiMapID, position = { x, y } }

    -- Super-tracked quest
    superTrackedQuestID = 0,
    questTitles = {},       -- { [questID] = "title" }
    questWaypoints = {},    -- { [questID] = { mapID, x, y } }
    questWaypointTexts = {},-- { [questID] = "Go to Stormwind" } -- non-nil = intermediate waypoint
    questsOnMap = {},       -- { [mapID] = { { questID, x, y }, ... } }
    questWatches = {},      -- { questID, questID, ... } indexed array of tracked quest IDs
    mapChildren = {},       -- { [parentMapID] = { {mapID, name, mapType}, ... } } for C_Map.GetMapChildrenInfo

    -- TomTom addon (nil means not loaded)
    tomtom = nil,

    -- GetTime base (seconds since epoch, monotonic)
    baseTime = 1000000,

    -- Sound tracking for PlaySound tests
    playedSounds = {},

    -- Hearthstone bind location
    bindLocation = "Stormwind City",
}

-- Map name database (mapID -> info table)
-- Covers all the key maps referenced by the addon
MockWoW.mapDatabase = {
    -- Eastern Kingdoms (continent mapID 13)
    [13]   = { mapID = 13,   name = "Eastern Kingdoms", mapType = 2 },
    [14]   = { mapID = 14,   name = "Arathi Highlands", mapType = 3 },
    [15]   = { mapID = 15,   name = "Badlands", mapType = 3 },
    [17]   = { mapID = 17,   name = "Badlands", mapType = 3 },
    [18]   = { mapID = 18,   name = "Tirisfal Glades", mapType = 3 },
    [19]   = { mapID = 19,   name = "Blasted Lands", mapType = 3 },
    [21]   = { mapID = 21,   name = "Silverpine Forest", mapType = 3 },
    [22]   = { mapID = 22,   name = "Western Plaguelands", mapType = 3 },
    [23]   = { mapID = 23,   name = "Eastern Plaguelands", mapType = 3 },
    [25]   = { mapID = 25,   name = "Hillsbrad Foothills", mapType = 3 },
    [26]   = { mapID = 26,   name = "The Hinterlands", mapType = 3 },
    [27]   = { mapID = 27,   name = "Dun Morogh", mapType = 3 },
    [32]   = { mapID = 32,   name = "Searing Gorge", mapType = 3 },
    [35]   = { mapID = 35,   name = "Blackrock Depths", mapType = 4 },
    [36]   = { mapID = 36,   name = "Loch Modan", mapType = 3 },
    [37]   = { mapID = 37,   name = "Elwynn Forest", mapType = 3, parentMapID = 13 },
    [42]   = { mapID = 42,   name = "Deadwind Pass", mapType = 3 },
    [47]   = { mapID = 47,   name = "Duskwood", mapType = 3 },
    [48]   = { mapID = 48,   name = "Redridge Mountains", mapType = 3 },
    [49]   = { mapID = 49,   name = "Eastern Plaguelands", mapType = 3 },
    [50]   = { mapID = 50,   name = "Northern Stranglethorn", mapType = 3 },
    [51]   = { mapID = 51,   name = "Swamp of Sorrows", mapType = 3 },
    [52]   = { mapID = 52,   name = "Westfall", mapType = 3 },
    [56]   = { mapID = 56,   name = "Wetlands", mapType = 3 },
    [84]   = { mapID = 84,   name = "Stormwind City", mapType = 3, parentMapID = 13 },
    [85]   = { mapID = 85,   name = "Orgrimmar", mapType = 3, parentMapID = 12 },
    [87]   = { mapID = 87,   name = "Ironforge", mapType = 3, parentMapID = 13 },
    [88]   = { mapID = 88,   name = "Thunder Bluff", mapType = 3, parentMapID = 12 },
    [89]   = { mapID = 89,   name = "Darnassus", mapType = 3, parentMapID = 12 },
    [90]   = { mapID = 90,   name = "Undercity", mapType = 3, parentMapID = 13 },
    [103]  = { mapID = 103,  name = "The Exodar", mapType = 3, parentMapID = 12 },
    [110]  = { mapID = 110,  name = "Silvermoon City", mapType = 3, parentMapID = 13 },

    -- Kalimdor (continent mapID 12)
    [12]   = { mapID = 12,   name = "Kalimdor", mapType = 2 },
    [1]    = { mapID = 1,    name = "Durotar", mapType = 3 },
    [7]    = { mapID = 7,    name = "Mulgore", mapType = 3 },
    [10]   = { mapID = 10,   name = "Northern Barrens", mapType = 3 },
    [11]   = { mapID = 11,   name = "Ashenvale", mapType = 3 },
    [57]   = { mapID = 57,   name = "Teldrassil", mapType = 3 },
    [62]   = { mapID = 62,   name = "Darkshore", mapType = 3 },
    [67]   = { mapID = 67,   name = "Feralas", mapType = 3 },
    [68]   = { mapID = 68,   name = "Dustwallow Marsh", mapType = 3 },
    [69]   = { mapID = 69,   name = "Tanaris", mapType = 3 },
    [70]   = { mapID = 70,   name = "Dustwallow Marsh", mapType = 3 },
    [71]   = { mapID = 71,   name = "Tanaris", mapType = 3 },
    [76]   = { mapID = 76,   name = "Azshara", mapType = 3 },
    [80]   = { mapID = 80,   name = "Moonglade", mapType = 3 },
    [81]   = { mapID = 81,   name = "Silithus", mapType = 3 },
    [83]   = { mapID = 83,   name = "Winterspring", mapType = 3 },
    [106]  = { mapID = 106,  name = "Felwood", mapType = 3 },
    [198]  = { mapID = 198,  name = "Mount Hyjal", mapType = 3 },
    [199]  = { mapID = 199,  name = "Southern Barrens", mapType = 3 },
    [261]  = { mapID = 261,  name = "Uldum", mapType = 3 },

    -- Outland (continent mapID 101)
    [100]  = { mapID = 100,  name = "Hellfire Peninsula", mapType = 3 },
    [101]  = { mapID = 101,  name = "Outland", mapType = 2 },
    [102]  = { mapID = 102,  name = "Zangarmarsh", mapType = 3 },
    [104]  = { mapID = 104,  name = "Shadowmoon Valley", mapType = 3 },
    [105]  = { mapID = 105,  name = "Blade's Edge Mountains", mapType = 3 },
    [107]  = { mapID = 107,  name = "Nagrand", mapType = 3 },
    [108]  = { mapID = 108,  name = "Terokkar Forest", mapType = 3 },
    [109]  = { mapID = 109,  name = "Netherstorm", mapType = 3 },
    [111]  = { mapID = 111,  name = "Shattrath City", mapType = 3 },
    [122]  = { mapID = 122,  name = "Isle of Quel'Danas", mapType = 3 },

    -- Northrend
    [113]  = { mapID = 113,  name = "Northrend", mapType = 2 },
    [114]  = { mapID = 114,  name = "Borean Tundra", mapType = 3 },
    [115]  = { mapID = 115,  name = "Dragonblight", mapType = 3 },
    [116]  = { mapID = 116,  name = "Grizzly Hills", mapType = 3 },
    [117]  = { mapID = 117,  name = "Howling Fjord", mapType = 3 },
    [118]  = { mapID = 118,  name = "Icecrown", mapType = 3 },
    [119]  = { mapID = 119,  name = "Sholazar Basin", mapType = 3 },
    [120]  = { mapID = 120,  name = "Storm Peaks", mapType = 3 },
    [121]  = { mapID = 121,  name = "Zul'Drak", mapType = 3 },
    [123]  = { mapID = 123,  name = "Wintergrasp", mapType = 3 },
    [125]  = { mapID = 125,  name = "Dalaran", mapType = 3, parentMapID = 113 },
    [127]  = { mapID = 127,  name = "Crystalsong Forest", mapType = 3 },

    -- Pandaria
    [371]  = { mapID = 371,  name = "The Jade Forest", mapType = 3 },
    [376]  = { mapID = 376,  name = "Valley of the Four Winds", mapType = 3 },
    [378]  = { mapID = 378,  name = "Kun-Lai Summit", mapType = 3 },
    [390]  = { mapID = 390,  name = "Vale of Eternal Blossoms", mapType = 3 },
    [418]  = { mapID = 418,  name = "Krasarang Wilds", mapType = 3 },
    [422]  = { mapID = 422,  name = "Dread Wastes", mapType = 3 },
    [424]  = { mapID = 424,  name = "Pandaria", mapType = 2 },
    [433]  = { mapID = 433,  name = "Isle of Thunder", mapType = 3 },
    [504]  = { mapID = 504,  name = "Isle of Thunder", mapType = 3 },

    -- Draenor
    [525]  = { mapID = 525,  name = "Frostfire Ridge", mapType = 3 },
    [535]  = { mapID = 535,  name = "Talador", mapType = 3 },
    [539]  = { mapID = 539,  name = "Shadowmoon Valley", mapType = 3 },
    [542]  = { mapID = 542,  name = "Spires of Arak", mapType = 3 },
    [543]  = { mapID = 543,  name = "Gorgrond", mapType = 3 },
    [550]  = { mapID = 550,  name = "Nagrand", mapType = 3 },
    [572]  = { mapID = 572,  name = "Draenor", mapType = 2 },
    [582]  = { mapID = 582,  name = "Lunarfall", mapType = 3 },
    [588]  = { mapID = 588,  name = "Ashran", mapType = 3 },
    [590]  = { mapID = 590,  name = "Frostwall", mapType = 3 },
    [622]  = { mapID = 622,  name = "Stormshield", mapType = 3 },
    [624]  = { mapID = 624,  name = "Warspear", mapType = 3 },

    -- Broken Isles
    [619]  = { mapID = 619,  name = "Broken Isles", mapType = 2 },
    [627]  = { mapID = 627,  name = "Dalaran", mapType = 3, parentMapID = 619 },
    [630]  = { mapID = 630,  name = "Azsuna", mapType = 3 },
    [634]  = { mapID = 634,  name = "Stormheim", mapType = 3 },
    [641]  = { mapID = 641,  name = "Val'sharah", mapType = 3 },
    [646]  = { mapID = 646,  name = "Broken Shore", mapType = 3 },
    [650]  = { mapID = 650,  name = "Highmountain", mapType = 3 },
    [680]  = { mapID = 680,  name = "Suramar", mapType = 3 },
    [715]  = { mapID = 715,  name = "Emerald Dreamway", mapType = 3 },
    [747]  = { mapID = 747,  name = "The Dreamgrove", mapType = 3 },
    [773]  = { mapID = 773,  name = "Tol Barad Peninsula", mapType = 3 },
    [809]  = { mapID = 809,  name = "Peak of Serenity", mapType = 3 },

    -- BFA
    [862]  = { mapID = 862,  name = "Zuldazar", mapType = 3, parentMapID = 875 },
    [863]  = { mapID = 863,  name = "Nazmir", mapType = 3, parentMapID = 875 },
    [864]  = { mapID = 864,  name = "Vol'dun", mapType = 3, parentMapID = 875 },
    [875]  = { mapID = 875,  name = "Zandalar", mapType = 2 },
    [876]  = { mapID = 876,  name = "Kul Tiras", mapType = 2 },
    [895]  = { mapID = 895,  name = "Tiragarde Sound", mapType = 3 },
    [896]  = { mapID = 896,  name = "Drustvar", mapType = 3 },
    [942]  = { mapID = 942,  name = "Stormsong Valley", mapType = 3 },
    [1161] = { mapID = 1161, name = "Boralus", mapType = 3, parentMapID = 876 },
    [1165] = { mapID = 1165, name = "Dazar'alor", mapType = 3, parentMapID = 875 },
    [1355] = { mapID = 1355, name = "Nazjatar", mapType = 3 },
    [1462] = { mapID = 1462, name = "Mechagon", mapType = 3 },

    -- Shadowlands
    [1525] = { mapID = 1525, name = "Revendreth", mapType = 3 },
    [1533] = { mapID = 1533, name = "Bastion", mapType = 3 },
    [1536] = { mapID = 1536, name = "Maldraxxus", mapType = 3 },
    [1543] = { mapID = 1543, name = "The Maw", mapType = 3 },
    [1550] = { mapID = 1550, name = "Shadowlands", mapType = 2 },
    [1565] = { mapID = 1565, name = "Ardenweald", mapType = 3 },
    [1670] = { mapID = 1670, name = "Oribos", mapType = 3, parentMapID = 1550 },
    [1961] = { mapID = 1961, name = "Korthia", mapType = 3 },
    [1970] = { mapID = 1970, name = "Zereth Mortis", mapType = 3 },

    -- Dragon Isles
    [1978] = { mapID = 1978, name = "Dragon Isles", mapType = 2 },
    [2022] = { mapID = 2022, name = "The Waking Shores", mapType = 3 },
    [2023] = { mapID = 2023, name = "Ohn'ahran Plains", mapType = 3 },
    [2024] = { mapID = 2024, name = "The Azure Span", mapType = 3 },
    [2025] = { mapID = 2025, name = "Thaldraszus", mapType = 3 },
    [2107] = { mapID = 2107, name = "Forbidden Reach", mapType = 3 },
    [2112] = { mapID = 2112, name = "Valdrakken", mapType = 3, parentMapID = 1978 },
    [2133] = { mapID = 2133, name = "Zaralek Cavern", mapType = 3 },
    [2151] = { mapID = 2151, name = "The Forbidden Reach", mapType = 3 },
    [2200] = { mapID = 2200, name = "Emerald Dream", mapType = 3 },
    [2239] = { mapID = 2239, name = "Bel'ameth", mapType = 3 },

    -- Khaz Algar
    [2213] = { mapID = 2213, name = "City of Threads", mapType = 3 },
    [2214] = { mapID = 2214, name = "The Ringing Deeps", mapType = 3 },
    [2215] = { mapID = 2215, name = "Hallowfall", mapType = 3 },
    [2248] = { mapID = 2248, name = "Isle of Dorn", mapType = 3 },
    [2255] = { mapID = 2255, name = "Azj-Kahet", mapType = 3 },
    [2274] = { mapID = 2274, name = "Khaz Algar", mapType = 2 },
    [2339] = { mapID = 2339, name = "Dornogal", mapType = 3, parentMapID = 2274 },
    [2346] = { mapID = 2346, name = "Undermine", mapType = 3 },
    [2369] = { mapID = 2369, name = "Siren Isle", mapType = 3 },
    [2371] = { mapID = 2371, name = "K'aresh", mapType = 3 },
    [2472] = { mapID = 2472, name = "Tazavesh", mapType = 3 },
}

-------------------------------------------------------------------------------
-- Event System
-- Tracks registered events per frame and allows firing them.
-------------------------------------------------------------------------------

MockWoW.eventFrames = {}  -- { frame = { events = {}, scriptHandler = func } }

--- Fire an event to all frames that have registered for it
-- @param event string The event name
-- @param ... Additional arguments passed to handlers
function MockWoW:FireEvent(event, ...)
    for _, frameData in ipairs(self.eventFrames) do
        if frameData.events[event] and frameData.scriptHandler then
            frameData.scriptHandler(frameData.frame, event, ...)
        end
    end
end

--- Get all frames registered for a given event
-- @param event string The event name
-- @return table Array of frame references
function MockWoW:GetFramesForEvent(event)
    local frames = {}
    for _, frameData in ipairs(self.eventFrames) do
        if frameData.events[event] then
            frames[#frames + 1] = frameData.frame
        end
    end
    return frames
end

--- Reset all mock state to defaults
function MockWoW:Reset()
    self.config.playerFaction = "Alliance"
    self.config.playerClass = "MAGE"
    self.config.playerClassName = "Mage"
    self.config.playerName = "Testplayer"
    self.config.playerLevel = 80
    self.config.currentMapID = 84
    self.config.playerX = 0.5
    self.config.playerY = 0.5
    self.config.locale = "enUS"
    self.config.isFlyableArea = true
    self.config.inCombatLockdown = false
    self.config.bagItems = {}
    self.config.ownedToys = {}
    self.config.knownSpells = {}
    self.config.itemCounts = {}
    self.config.equippedItems = {}
    self.config.professions = {}
    self.config.itemCooldowns = {}
    self.config.spellCooldowns = {}
    self.config.hasUserWaypoint = false
    self.config.userWaypoint = nil
    self.config.superTrackedQuestID = 0
    self.config.questTitles = {}
    self.config.questWaypoints = {}
    self.config.questWaypointTexts = {}
    self.config.questsOnMap = {}
    self.config.mapChildren = {}
    self.config.tomtom = nil
    self.config.baseTime = 1000000
    self.config.playedSounds = {}
    self.config.bindLocation = "Stormwind City"
    self.eventFrames = {}
end

-------------------------------------------------------------------------------
-- Frame Mock
-- Creates a table that behaves like a WoW Frame with common methods.
-------------------------------------------------------------------------------

local frameCounter = 0

local function CreateMockTexture(parent)
    local tex = {
        _parent = parent,
        _points = {},
        _shown = true,
        _alpha = 1.0,
        _desaturated = false,
    }
    function tex:SetTexture(t) self._texture = t end
    function tex:GetTexture() return self._texture end
    function tex:SetColorTexture() end
    function tex:SetSize() end
    function tex:SetHeight() end
    function tex:SetWidth() end
    function tex:SetPoint(point, ...) self._points[#self._points + 1] = { point, ... } end
    function tex:ClearAllPoints() self._points = {} end
    function tex:SetAllPoints() end
    function tex:Show() self._shown = true end
    function tex:Hide() self._shown = false end
    function tex:SetShown(show) if show then self:Show() else self:Hide() end end
    function tex:IsShown() return self._shown end
    function tex:SetTexCoord() end
    function tex:SetVertexColor() end
    function tex:SetAlpha(alpha) self._alpha = alpha end
    function tex:GetAlpha() return self._alpha end
    function tex:SetDesaturated(desat) self._desaturated = desat end
    function tex:SetDrawLayer() end
    return tex
end

local function CreateMockFontString(parent)
    local fs = {
        _parent = parent,
        _text = "",
        _shown = true,
        _points = {},
        _size = { w = 0, h = 12 },  -- Default font height
        _wordWrap = true,
    }
    function fs:SetText(text) self._text = text or "" end
    function fs:GetText() return self._text end
    function fs:SetPoint(point, ...) self._points[#self._points + 1] = { point, ... } end
    function fs:ClearAllPoints() self._points = {} end
    function fs:SetJustifyH() end
    function fs:SetJustifyV() end
    function fs:SetWordWrap(wrap) self._wordWrap = wrap end
    function fs:GetWordWrap() return self._wordWrap end
    function fs:SetWidth(w) self._size.w = w end
    function fs:GetWidth() return self._size.w end
    function fs:SetHeight(h) self._size.h = h end
    function fs:GetHeight() return self._size.h end
    function fs:SetTextColor(r, g, b, a)
        self._textColorR = r
        self._textColorG = g
        self._textColorB = b
        self._textColorA = a
    end
    function fs:SetTextToFit() end
    function fs:SetFontObject() end
    function fs:SetFont() end
    function fs:Show() self._shown = true end
    function fs:Hide() self._shown = false end
    function fs:IsShown() return self._shown end
    function fs:GetStringWidth() return #self._text * 7 end
    function fs:GetStringHeight()
        local charWidth = 7
        local availWidth = self._size.w or 200
        local textWidth = #self._text * charWidth
        if self._wordWrap and availWidth > 0 and textWidth > availWidth then
            local lines = math.ceil(textWidth / availWidth)
            return lines * 12  -- 12px per line (GameFontNormal)
        end
        return 12  -- Single line height
    end
    return fs
end

local function CreateMockFrame(frameType, name, parent, template)
    frameCounter = frameCounter + 1
    local frame = {
        _type = frameType or "Frame",
        _name = name,
        _parent = parent,
        _children = {},
        _scripts = {},
        _events = {},
        _points = {},
        _shown = false,
        _size = { w = 0, h = 0 },
        _attributes = {},
        _strata = "MEDIUM",
        _level = 1,
        _alpha = 1.0,
        _movable = false,
        _mouseEnabled = false,
        _clamped = false,
        _id = frameCounter,
    }

    -- Register in global if named
    if name then
        _G[name] = frame
    end

    -- Basic frame methods
    function frame:SetSize(w, h) self._size = { w = w, h = h } end
    function frame:GetWidth() return self._size.w end
    function frame:GetHeight() return self._size.h end
    function frame:SetWidth(w) self._size.w = w end
    function frame:SetHeight(h) self._size.h = h end
    function frame:SetPoint(point, ...) self._points[#self._points + 1] = { point, ... } end
    function frame:ClearAllPoints() self._points = {} end
    function frame:GetPoint(index)
        local p = self._points[index or 1]
        if p then
            return p[1], self._parent, p[1], 0, 0
        end
        return "CENTER", self._parent, "CENTER", 0, 0
    end
    function frame:SetAllPoints() end
    function frame:Show()
        local wasShown = self._shown
        self._shown = true
        if not wasShown and self._scripts and self._scripts["OnShow"] then
            self._scripts["OnShow"](self)
        end
    end
    function frame:SetShown(show)
        if show then self:Show() else self:Hide() end
    end
    function frame:Hide()
        local wasShown = self._shown
        self._shown = false
        if wasShown and self._scripts and self._scripts["OnHide"] then
            self._scripts["OnHide"](self)
        end
    end
    function frame:IsShown() return self._shown end
    function frame:IsVisible() return self._shown end
    function frame:IsMouseOver() return self._isMouseOver or false end
    function frame:SetParent(p) self._parent = p end
    function frame:GetParent() return self._parent end
    function frame:GetLeft() return 0 end
    function frame:GetRight() return self._size.w end
    function frame:GetTop() return self._size.h end
    function frame:GetBottom() return 0 end
    function frame:GetCenter() return self._size.w / 2, self._size.h / 2 end
    function frame:GetEffectiveScale() return 1.0 end
    function frame:SetMovable(val) self._movable = val end
    function frame:SetResizable() end
    function frame:EnableMouse(val) self._mouseEnabled = val end
    function frame:RegisterForDrag() end
    function frame:SetClampedToScreen(val) self._clamped = val end
    function frame:SetFrameStrata(strata) self._strata = strata end
    function frame:SetFrameLevel(level) self._level = level end
    function frame:SetAlpha(alpha) self._alpha = alpha end
    function frame:GetAlpha() return self._alpha end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor(r, g, b, a)
        self._backdropBorderColor = { r, g, b, a }
    end
    function frame:SetUsingParentLevel() end
    function frame:SetNormalTexture() end
    function frame:SetHighlightTexture() end
    function frame:SetPushedTexture() end
    function frame:SetDisabledTexture() end
    function frame:SetCheckedTexture() end
    function frame:RegisterForClicks(...) end
    function frame:SetChecked(val) self._checked = val end
    function frame:GetChecked() return self._checked end

    -- Attribute system (for SecureActionButtonTemplate)
    function frame:SetAttribute(key, value) self._attributes[key] = value end
    function frame:GetAttribute(key) return self._attributes[key] end

    -- Script system
    function frame:SetScript(scriptType, handler)
        self._scripts[scriptType] = handler
    end
    function frame:GetScript(scriptType)
        return self._scripts[scriptType]
    end
    function frame:HasScript(scriptType)
        return self._scripts[scriptType] ~= nil
    end
    function frame:HookScript(scriptType, hook)
        local original = self._scripts[scriptType]
        if original then
            self._scripts[scriptType] = function(...)
                original(...)
                hook(...)
            end
        else
            self._scripts[scriptType] = hook
        end
    end

    -- Event system
    function frame:RegisterEvent(event)
        self._events[event] = true
        -- Track in MockWoW for FireEvent
        local found = false
        for _, fd in ipairs(MockWoW.eventFrames) do
            if fd.frame == self then
                fd.events[event] = true
                found = true
                break
            end
        end
        if not found then
            MockWoW.eventFrames[#MockWoW.eventFrames + 1] = {
                frame = self,
                events = { [event] = true },
                scriptHandler = nil,
            }
        end
    end
    function frame:UnregisterEvent(event)
        self._events[event] = nil
        for _, fd in ipairs(MockWoW.eventFrames) do
            if fd.frame == self then
                fd.events[event] = nil
                break
            end
        end
    end
    function frame:UnregisterAllEvents()
        self._events = {}
        for _, fd in ipairs(MockWoW.eventFrames) do
            if fd.frame == self then
                fd.events = {}
                break
            end
        end
    end
    function frame:IsEventRegistered(event)
        return self._events[event] == true
    end

    -- Update OnEvent handler reference in eventFrames when SetScript is called
    local originalSetScript = frame.SetScript
    frame.SetScript = function(self, scriptType, handler)
        self._scripts[scriptType] = handler
        if scriptType == "OnEvent" then
            for _, fd in ipairs(MockWoW.eventFrames) do
                if fd.frame == self then
                    fd.scriptHandler = handler
                    return
                end
            end
            -- Frame not yet in eventFrames, add it
            MockWoW.eventFrames[#MockWoW.eventFrames + 1] = {
                frame = self,
                events = self._events,
                scriptHandler = handler,
            }
        end
    end

    -- Texture and FontString creation
    function frame:CreateTexture(name, layer)
        return CreateMockTexture(self)
    end
    function frame:CreateFontString(name, layer, template)
        return CreateMockFontString(self)
    end

    -- Scroll frame methods (for UIPanelScrollFrameTemplate)
    function frame:SetScrollChild(child)
        self._scrollChild = child
        child._parent = self
    end
    function frame:GetScrollChild()
        return self._scrollChild
    end

    -- EditBox methods
    function frame:SetMultiLine() end
    function frame:SetFontObject() end
    function frame:SetAutoFocus() end
    function frame:SetText(text) self._text = text end
    function frame:GetText() return self._text or "" end
    function frame:HighlightText() end
    function frame:SetFocus() end
    function frame:HasFocus() return self._hasFocus or false end
    function frame:ClearFocus()
        self._hasFocus = false
        if self._scripts and self._scripts["OnEditFocusLost"] then
            self._scripts["OnEditFocusLost"](self)
        end
    end

    -- Button-specific methods
    function frame:SetText(text) self._text = text or "" end
    function frame:GetText() return self._text or "" end
    function frame:Click()
        if self._scripts and self._scripts["OnClick"] then
            self._scripts["OnClick"](self, "LeftButton")
        end
    end
    function frame:SetEnabled() end
    function frame:IsEnabled() return true end
    function frame:Disable() end
    function frame:Enable() end

    -- Tooltip methods (for GameTooltip mock)
    function frame:SetOwner() end
    function frame:SetSpellByID() end
    function frame:SetItemByID() end
    function frame:AddLine() end
    function frame:SetText(text) self._text = text or "" end
    function frame:ClearLines() end

    -- Slider methods (for OptionsSliderTemplate)
    frame._sliderMin = 0
    frame._sliderMax = 1
    frame._sliderStep = 0.1
    frame._sliderValue = 0
    function frame:SetMinMaxValues(minVal, maxVal)
        self._sliderMin = minVal
        self._sliderMax = maxVal
    end
    function frame:GetMinMaxValues()
        return self._sliderMin, self._sliderMax
    end
    function frame:SetValueStep(step) self._sliderStep = step end
    function frame:SetObeyStepOnDrag(val) self._obeyStep = val end
    function frame:SetValue(val)
        self._sliderValue = val
        if self._scripts and self._scripts["OnValueChanged"] then
            self._scripts["OnValueChanged"](self, val)
        end
    end
    function frame:GetValue() return self._sliderValue end

    -- OptionsSliderTemplate sub-elements (Low/High labels)
    frame.Low = CreateMockFontString(frame)
    frame.High = CreateMockFontString(frame)

    -- Scale methods
    frame._scale = 1.0
    function frame:SetScale(scale) self._scale = scale end
    function frame:GetScale() return self._scale end

    -- WowStyle1DropdownTemplate methods (WoW 11.0+ modern dropdown)
    if template == "WowStyle1DropdownTemplate" then
        frame._isModern = true
        frame._defaultText = ""
        frame._setupMenuFunc = nil
        frame._overrideText = nil
        function frame:SetDefaultText(text) self._defaultText = text end
        function frame:SetupMenu(generatorFunc)
            self._setupMenuFunc = generatorFunc
        end
        function frame:OverrideText(text) self._overrideText = text end
        function frame:GenerateMenu()
            -- In real WoW this re-runs the generator to update selection text
            if self._setupMenuFunc then
                -- Create a mock rootDescription for test introspection
                local items = {}
                local rootDesc = {
                    CreateRadio = function(_, text, isSelected, setSelected, data)
                        local item = { type = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data }
                        items[#items + 1] = item
                        return item
                    end,
                    CreateButton = function(_, text, onClick)
                        local item = { type = "button", text = text, onClick = onClick, _enabled = true }
                        function item:SetEnabled(val) self._enabled = val end
                        items[#items + 1] = item
                        return item
                    end,
                    CreateTitle = function(_, text)
                        local item = { type = "title", text = text }
                        items[#items + 1] = item
                        return item
                    end,
                }
                self._setupMenuFunc(self, rootDesc)
                self._menuItems = items
            end
        end
    end

    return frame
end

-------------------------------------------------------------------------------
-- Install Global WoW API
-- This function installs all mock globals into _G.
-------------------------------------------------------------------------------

function MockWoW:Install()
    local cfg = self.config

    ---------------------------------------------------------------------------
    -- Basic Globals
    ---------------------------------------------------------------------------

    -- string.trim (WoW adds this to string metatable)
    if not string.trim then
        string.trim = function(s)
            return s:match("^%s*(.-)%s*$")
        end
    end

    -- date (WoW exposes os.date as global 'date')
    _G.date = os.date

    -- strsplit (WoW global)
    _G.strsplit = function(delimiter, str, pieces)
        local results = {}
        local pattern = "([^" .. delimiter .. "]*)" .. delimiter .. "?"
        for match in str:gmatch(pattern) do
            results[#results + 1] = match
            if pieces and #results >= pieces then break end
        end
        return unpack(results)
    end

    -- wipe (clears a table in-place)
    _G.wipe = function(t)
        if type(t) == "table" then
            for k in pairs(t) do
                t[k] = nil
            end
        end
        return t
    end

    -- date (already exists in standard Lua, keep it)
    -- print (already exists in standard Lua, keep it)

    -- GetLocale
    _G.GetLocale = function()
        return cfg.locale
    end

    -- GetBuildInfo: returns version, build, date, tocVersion
    _G.GetBuildInfo = function()
        return "12.0.1", "58238", "Feb 12 2026", 120001
    end

    -- GetTime (monotonic seconds)
    _G.GetTime = function()
        return cfg.baseTime
    end

    -- hooksecurefunc
    _G.hooksecurefunc = function(tbl, key, hook)
        if type(tbl) == "string" then
            -- hooksecurefunc("FuncName", hook) form
            local funcName = tbl
            hook = key
            local original = _G[funcName]
            if original then
                _G[funcName] = function(...)
                    local results = { original(...) }
                    hook(...)
                    return unpack(results)
                end
            end
        elseif type(tbl) == "table" and type(key) == "string" then
            -- hooksecurefunc(table, "method", hook) form
            local original = tbl[key]
            if original then
                tbl[key] = function(...)
                    local results = { original(...) }
                    hook(...)
                    return unpack(results)
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Player Info Functions
    ---------------------------------------------------------------------------

    _G.UnitFactionGroup = function(unit)
        if unit == "player" then
            return cfg.playerFaction, cfg.playerFaction
        end
        return nil
    end

    _G.UnitClass = function(unit)
        if unit == "player" then
            return cfg.playerClassName, cfg.playerClass
        end
        return "Unknown", "UNKNOWN"
    end

    _G.UnitName = function(unit)
        if unit == "player" then
            return cfg.playerName, nil
        end
        return "Unknown", nil
    end

    _G.UnitLevel = function(unit)
        if unit == "player" then
            return cfg.playerLevel
        end
        return 1
    end

    _G.IsFlyableArea = function()
        return cfg.isFlyableArea
    end

    _G.InCombatLockdown = function()
        return cfg.inCombatLockdown
    end

    _G.IsControlKeyDown = function()
        return cfg.isControlKeyDown or false
    end

    _G.IsInInstance = function()
        return cfg.inInstance or false, cfg.instanceType or "none"
    end

    ---------------------------------------------------------------------------
    -- Item Functions
    ---------------------------------------------------------------------------

    _G.GetItemInfo = function(itemID)
        -- Returns: name, link, quality, itemLevel, reqLevel, class, subclass, ...
        local name = "Item " .. tostring(itemID)
        local link = "|cff0070dd|Hitem:" .. tostring(itemID) .. "::::::::80:::::|h[" .. name .. "]|h|r"
        return name, link, 3, 1, 1, "Miscellaneous", "Junk", 1, "", 134400, 0
    end

    _G.GetItemIcon = function(itemID)
        return 134400  -- Generic item icon
    end

    _G.GetItemCount = function(itemID)
        return cfg.itemCounts[itemID] or 0
    end

    _G.GetItemCooldown = function(itemID)
        local cd = cfg.itemCooldowns[itemID]
        if cd then
            return cd.start, cd.duration, cd.enable or 1
        end
        return 0, 0, 1
    end

    _G.GetInventoryItemID = function(unit, slotID)
        if unit == "player" then
            return cfg.equippedItems[slotID]
        end
        return nil
    end

    ---------------------------------------------------------------------------
    -- Spell Functions
    ---------------------------------------------------------------------------

    _G.GetSpellInfo = function(spellID)
        -- Returns: name, rank, icon, castTime, minRange, maxRange, spellID
        local name = "Spell " .. tostring(spellID)
        return name, "", 134400, 0, 0, 0, spellID
    end

    _G.GetSpellLink = function(spellID)
        local name = "Spell " .. tostring(spellID)
        return "|cff71d5ff|Hspell:" .. tostring(spellID) .. "|h[" .. name .. "]|h|r"
    end

    _G.IsSpellKnown = function(spellID)
        return cfg.knownSpells[spellID] == true
    end

    _G.GetSpellCooldown = function(spellID)
        local cd = cfg.spellCooldowns[spellID]
        if cd then
            return cd.start, cd.duration, cd.enable or 1
        end
        return 0, 0, 1
    end

    ---------------------------------------------------------------------------
    -- Toy Functions
    ---------------------------------------------------------------------------

    _G.PlayerHasToy = function(itemID)
        return cfg.ownedToys[itemID] == true
    end

    ---------------------------------------------------------------------------
    -- Profession Functions
    ---------------------------------------------------------------------------

    -- Equipment slot constants
    _G.INVSLOT_FINGER1 = 11
    _G.INVSLOT_FINGER2 = 12
    _G.INVSLOT_TABARD = 19
    _G.INVSLOT_TRINKET1 = 13
    _G.INVSLOT_TRINKET2 = 14
    _G.NUM_BAG_SLOTS = 4

    _G.GetProfessions = function()
        local p = cfg.professions
        return p[1] and 1 or nil, p[2] and 2 or nil, nil, nil, nil
    end

    _G.GetProfessionInfo = function(index)
        local p = cfg.professions[index]
        if p then
            return p.name or "Unknown",
                   p.icon or 134400,
                   p.skillLevel or 1,
                   p.maxSkill or 300,
                   p.numAbilities or 0,
                   p.spellOffset or 0,
                   p.skillLineID or 0
        end
        return "Unknown", 134400, 1, 300, 0, 0, 0
    end

    -- Faction/reputation stubs
    _G.GetNumFactions = function() return 0 end
    _G.GetFactionInfo = function() return nil end

    -- Quest stubs
    _G.GetQuestLink = function() return nil end

    -- Achievement stubs
    _G.GetAchievementInfo = function() return nil end
    _G.GetAchievementLink = function() return nil end

    -- Bank stub
    _G.IsAtBank = function() return false end

    ---------------------------------------------------------------------------
    -- C_Map Namespace
    ---------------------------------------------------------------------------

    _G.C_Map = {}

    _G.C_Map.GetBestMapForUnit = function(unit)
        if unit == "player" then
            return cfg.currentMapID
        end
        return nil
    end

    _G.C_Map.GetMapInfo = function(mapID)
        if not mapID then return nil end
        local info = MockWoW.mapDatabase[mapID]
        if info then
            return { mapID = info.mapID, name = info.name, mapType = info.mapType, parentMapID = info.parentMapID }
        end
        -- Return a generic entry for unknown maps
        return { mapID = mapID, name = "Map " .. tostring(mapID), mapType = 3 }
    end

    _G.C_Map.GetPlayerMapPosition = function(mapID, unit)
        if unit == "player" then
            -- Return a position object with GetXY method
            return {
                GetXY = function(self)
                    return cfg.playerX, cfg.playerY
                end,
                x = cfg.playerX,
                y = cfg.playerY,
            }
        end
        return nil
    end

    _G.C_Map.HasUserWaypoint = function()
        return cfg.hasUserWaypoint
    end

    _G.C_Map.GetUserWaypoint = function()
        return cfg.userWaypoint
    end

    _G.C_Map.SetUserWaypoint = function(uiMapPoint)
        cfg.hasUserWaypoint = true
        cfg.userWaypoint = uiMapPoint
    end

    _G.C_Map.GetMapInfoAtPosition = function(mapID, x, y)
        -- For continent-level maps, try to resolve to a zone
        local info = MockWoW.mapDatabase[mapID]
        if info and info.mapType and info.mapType <= 2 then
            -- Return nil (no child map found) - tests can override
            return nil
        end
        return nil
    end

    _G.C_Map.GetMapChildrenInfo = function(mapID, mapType, allDescendants)
        -- Return configured child maps or empty table
        -- cfg.mapChildren = { [parentMapID] = { {mapID=123, name="Zone", mapType=3}, ... } }
        return cfg.mapChildren and cfg.mapChildren[mapID] or {}
    end

    ---------------------------------------------------------------------------
    -- C_Container Namespace
    ---------------------------------------------------------------------------

    _G.C_Container = {}

    _G.C_Container.GetContainerNumSlots = function(bagID)
        if bagID >= 0 and bagID <= 4 then
            -- Count how many items in this bag
            local maxSlot = 0
            for _, itemData in pairs(cfg.bagItems) do
                if itemData.bagID == bagID and itemData.slot > maxSlot then
                    maxSlot = itemData.slot
                end
            end
            return maxSlot > 0 and maxSlot or (bagID == 0 and 16 or 0)
        end
        return 0
    end

    _G.C_Container.GetContainerItemID = function(bagID, slot)
        for itemID, itemData in pairs(cfg.bagItems) do
            if itemData.bagID == bagID and itemData.slot == slot then
                return itemID
            end
        end
        return nil
    end

    _G.C_Container.GetContainerItemInfo = function(bagID, slot)
        for itemID, itemData in pairs(cfg.bagItems) do
            if itemData.bagID == bagID and itemData.slot == slot then
                return {
                    itemID = itemID,
                    stackCount = itemData.count or 1,
                    itemLink = "|cff0070dd|Hitem:" .. tostring(itemID) .. "|h[Item]|h|r",
                }
            end
        end
        return nil
    end

    -- Note: C_Container.GetItemCooldown does NOT exist in real WoW API.
    -- Item cooldowns use the global GetItemCooldown() function (defined above).

    -- Legacy fallbacks
    _G.GetContainerNumSlots = _G.C_Container.GetContainerNumSlots
    _G.GetContainerItemID = _G.C_Container.GetContainerItemID

    ---------------------------------------------------------------------------
    -- C_Spell Namespace
    ---------------------------------------------------------------------------

    _G.C_Spell = {}

    _G.C_Spell.GetSpellInfo = function(spellID)
        if not spellID then return nil end
        return {
            name = "Spell " .. tostring(spellID),
            iconID = 134400,
            spellID = spellID,
        }
    end

    _G.C_Spell.GetSpellCooldown = function(spellID)
        local cd = cfg.spellCooldowns[spellID]
        if cd then
            return {
                startTime = cd.start,
                duration = cd.duration,
                isEnabled = true,
            }
        end
        return {
            startTime = 0,
            duration = 0,
            isEnabled = true,
        }
    end

    _G.C_Spell.GetSpellTexture = function(spellID)
        return 134400  -- Generic spell icon
    end

    ---------------------------------------------------------------------------
    -- C_Item Namespace
    ---------------------------------------------------------------------------

    _G.C_Item = {}

    _G.C_Item.GetItemIconByID = function(itemID)
        return 134400
    end

    ---------------------------------------------------------------------------
    -- C_ToyBox Namespace
    ---------------------------------------------------------------------------

    _G.C_ToyBox = {}

    _G.C_ToyBox.IsToyUsable = function(itemID)
        return cfg.ownedToys[itemID] == true
    end

    ---------------------------------------------------------------------------
    -- C_MountJournal Namespace
    ---------------------------------------------------------------------------

    _G.C_MountJournal = {}

    _G.C_MountJournal.SummonByID = function(mountID)
        -- 0 = random favorite mount
    end

    ---------------------------------------------------------------------------
    -- Encounter Journal API
    ---------------------------------------------------------------------------

    -- Tier/instance data for EJ mocks
    local ejTiers = {
        [1] = {
            name = "Classic",
            dungeons = {
                { instanceID = 226, name = "Ragefire Chasm", mapID = 389, dungeonAreaMapID = 389, isRaid = false },
            },
            raids = {
                { instanceID = 741, name = "Molten Core", mapID = 232, dungeonAreaMapID = 232, isRaid = true },
            },
        },
        [2] = {
            name = "The War Within",
            dungeons = {
                { instanceID = 1267, name = "The Stonevault", mapID = 2341, dungeonAreaMapID = 2341, isRaid = false },
                { instanceID = 1268, name = "City of Threads", mapID = 2343, dungeonAreaMapID = 2343, isRaid = false },
            },
            raids = {
                { instanceID = 1273, name = "Nerub-ar Palace", mapID = 2345, dungeonAreaMapID = 2345, isRaid = true },
            },
        },
    }

    -- Build reverse lookup: instanceID -> instance data
    local ejInstanceByID = {}
    for _, tier in pairs(ejTiers) do
        for _, inst in ipairs(tier.dungeons) do
            ejInstanceByID[inst.instanceID] = inst
        end
        for _, inst in ipairs(tier.raids) do
            ejInstanceByID[inst.instanceID] = inst
        end
    end

    -- Build reverse lookup: mapID -> instanceID
    local ejMapToInstance = {}
    for id, inst in pairs(ejInstanceByID) do
        ejMapToInstance[inst.mapID] = id
    end

    local ejSelectedTier = 1

    _G.EJ_GetNumTiers = function()
        local count = 0
        for _ in pairs(ejTiers) do count = count + 1 end
        return count
    end

    _G.EJ_SelectTier = function(tier)
        ejSelectedTier = tier
    end

    _G.EJ_GetTierInfo = function(tier)
        local t = ejTiers[tier]
        if t then return t.name end
        return nil
    end

    _G.EJ_GetInstanceByIndex = function(index, isRaid)
        local tier = ejTiers[ejSelectedTier]
        if not tier then return nil, nil end
        local list = isRaid and tier.raids or tier.dungeons
        local inst = list[index]
        if inst then
            return inst.instanceID, inst.name
        end
        return nil, nil
    end

    _G.EJ_GetInstanceInfo = function(instanceID)
        local inst = ejInstanceByID[instanceID]
        if not inst then return nil end
        -- Returns: name, description, bgImage, buttonImage1, loreImage,
        --          buttonImage2, dungeonAreaMapID, link, shouldDisplayDifficulty,
        --          mapID, journalMediaID, isRaid
        return inst.name,
               inst.name .. " description",
               nil, nil, nil, nil,
               inst.dungeonAreaMapID,
               "|cff66bbff|Hjournal:1:" .. instanceID .. "|h[" .. inst.name .. "]|h|r",
               true,
               inst.mapID,
               0,
               inst.isRaid
    end

    ---------------------------------------------------------------------------
    -- C_EncounterJournal Namespace
    ---------------------------------------------------------------------------

    if not _G.C_EncounterJournal then _G.C_EncounterJournal = {} end

    -- Dungeon entrance data keyed by zone mapID
    local ejEntranceData = {
        [85] = {  -- Orgrimmar
            {
                areaPoiID = 226,
                position = { x = 0.39, y = 0.50, GetXY = function() return 0.39, 0.50 end },
                name = "Ragefire Chasm",
                description = "A dungeon beneath Orgrimmar",
                atlasName = "DungeonEntrance",
                journalInstanceID = 226,
            },
        },
        [2248] = {  -- Isle of Dorn
            {
                areaPoiID = 1267,
                position = { x = 0.62, y = 0.31, GetXY = function() return 0.62, 0.31 end },
                name = "The Stonevault",
                description = "A dungeon in Isle of Dorn",
                atlasName = "DungeonEntrance",
                journalInstanceID = 1267,
            },
            {
                areaPoiID = 1268,
                position = { x = 0.35, y = 0.55, GetXY = function() return 0.35, 0.55 end },
                name = "City of Threads",
                description = "A dungeon in Isle of Dorn",
                atlasName = "DungeonEntrance",
                journalInstanceID = 1268,
            },
        },
    }

    _G.C_EncounterJournal.GetDungeonEntrancesForMap = function(mapID)
        return ejEntranceData[mapID] or {}
    end

    _G.C_EncounterJournal.GetInstanceForGameMap = function(mapID)
        return ejMapToInstance[mapID] or nil
    end

    ---------------------------------------------------------------------------
    -- Enum.UIMapType
    ---------------------------------------------------------------------------

    if not _G.Enum then _G.Enum = {} end
    if not _G.Enum.UIMapType then
        _G.Enum.UIMapType = {
            Cosmic    = 0,
            World     = 1,
            Continent = 2,
            Zone      = 3,
            Dungeon   = 4,
            Micro     = 5,
            Orphan    = 6,
        }
    end

    ---------------------------------------------------------------------------
    -- C_SuperTrack Namespace
    ---------------------------------------------------------------------------

    _G.C_SuperTrack = {}

    _G.C_SuperTrack.GetSuperTrackedQuestID = function()
        return cfg.superTrackedQuestID
    end

    _G.C_SuperTrack.SetSuperTrackedUserWaypoint = function(enabled)
        -- Stub
    end

    _G.C_SuperTrack.GetSuperTrackedMapPin = function()
        return nil
    end

    ---------------------------------------------------------------------------
    -- C_QuestLog Namespace
    ---------------------------------------------------------------------------

    _G.C_QuestLog = {}

    _G.C_QuestLog.GetTitleForQuestID = function(questID)
        return cfg.questTitles[questID] or ("Quest " .. tostring(questID))
    end

    _G.C_QuestLog.GetNextWaypoint = function(questID)
        local wp = cfg.questWaypoints[questID]
        if wp then
            return wp.mapID, wp.x, wp.y
        end
        return nil, nil, nil
    end

    _G.C_QuestLog.GetNextWaypointForMap = function(questID, mapID)
        local wp = cfg.questWaypoints[questID]
        if wp and wp.mapID == mapID then
            return wp.x, wp.y
        end
        -- Also check per-map overrides (for testing projections to other maps)
        local perMap = cfg.questWaypointForMap and cfg.questWaypointForMap[questID]
        if perMap and perMap[mapID] then
            return perMap[mapID].x, perMap[mapID].y
        end
        return nil, nil
    end

    _G.C_QuestLog.GetNextWaypointText = function(questID)
        return cfg.questWaypointTexts and cfg.questWaypointTexts[questID] or nil
    end

    _G.C_QuestLog.GetQuestsOnMap = function(mapID)
        return cfg.questsOnMap[mapID] or {}
    end

    _G.C_QuestLog.IsQuestFlaggedCompleted = function(questID)
        return false
    end

    _G.C_QuestLog.IsOnQuest = function(questID)
        return false
    end

    _G.C_QuestLog.GetDistanceSqToQuest = function(questID)
        return nil, nil
    end

    _G.C_QuestLog.GetNumQuestWatches = function()
        return cfg.questWatches and #cfg.questWatches or 0
    end

    _G.C_QuestLog.GetQuestIDForQuestWatchIndex = function(index)
        return cfg.questWatches and cfg.questWatches[index] or nil
    end

    ---------------------------------------------------------------------------
    -- C_TaskQuest Namespace
    ---------------------------------------------------------------------------

    _G.C_TaskQuest = {}

    _G.C_TaskQuest.GetQuestLocation = function(questID, mapID)
        return nil, nil
    end

    ---------------------------------------------------------------------------
    -- C_Timer Namespace
    ---------------------------------------------------------------------------

    _G.C_Timer = {}

    -- After just calls the callback immediately in tests
    _G.C_Timer.After = function(delay, callback)
        if callback then
            callback()
        end
    end

    -- NewTimer returns a cancelable timer object
    _G.C_Timer.NewTimer = function(delay, callback)
        local timer = {
            cancelled = false,
            Cancel = function(self)
                self.cancelled = true
            end,
        }
        -- In tests, execute immediately unless cancelled
        if callback and not timer.cancelled then
            callback()
        end
        return timer
    end

    ---------------------------------------------------------------------------
    -- UiMapPoint
    ---------------------------------------------------------------------------

    _G.UiMapPoint = {}

    _G.UiMapPoint.CreateFromCoordinates = function(mapID, x, y)
        return {
            uiMapID = mapID,
            position = { x = x, y = y },
        }
    end

    ---------------------------------------------------------------------------
    -- Frame Creation
    ---------------------------------------------------------------------------

    _G.CreateFrame = function(frameType, name, parent, template)
        return CreateMockFrame(frameType, name, parent, template)
    end

    ---------------------------------------------------------------------------
    -- UIParent and UISpecialFrames
    ---------------------------------------------------------------------------

    _G.UIParent = CreateMockFrame("Frame", nil, nil, nil)
    _G.UIParent._shown = true
    _G.UIParent._size = { w = 1024, h = 768 }  -- Standard UI resolution for layout tests

    _G.UISpecialFrames = {}

    ---------------------------------------------------------------------------
    -- Minimap (for MinimapButton)
    ---------------------------------------------------------------------------

    _G.Minimap = CreateMockFrame("Frame", "Minimap", nil, nil)
    _G.Minimap._shown = true
    _G.Minimap._size = { w = 140, h = 140 }

    _G.GetCursorPosition = function()
        return 512, 384  -- Center of screen
    end

    ---------------------------------------------------------------------------
    -- Settings API (WoW 11.x Interface Options)
    ---------------------------------------------------------------------------

    _G.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
            return { GetID = function() return name end }
        end,
        RegisterAddOnCategory = function(category) end,
        OpenToCategory = function(id) end,
        -- Native vertical layout API (WoW 11.0+)
        RegisterVerticalLayoutCategory = function(name)
            return { GetID = function() return name end, _name = name }
        end,
        RegisterProxySetting = function(category, variable, varType, name, defaultValue, getValue, setValue)
            return {
                GetVariable = function() return variable end,
                SetValueChangedCallback = function(self, cb) self._callback = cb end,
                _variable = variable,
                _getValue = getValue,
                _setValue = setValue,
            }
        end,
        CreateCheckbox = function(category, setting, tooltip)
            return { _type = "checkbox", _setting = setting, _tooltip = tooltip }
        end,
        CreateSlider = function(category, setting, options, tooltip)
            return { _type = "slider", _setting = setting, _options = options, _tooltip = tooltip }
        end,
        CreateDropdown = function(category, setting, optionsFunc, tooltip)
            return { _type = "dropdown", _setting = setting, _optionsFunc = optionsFunc, _tooltip = tooltip }
        end,
        CreateSliderOptions = function(minValue, maxValue, rate)
            return {
                minValue = minValue or 0,
                maxValue = maxValue or 1,
                steps = (rate and (maxValue - minValue) / rate) or 100,
                SetLabelFormatter = function() end,
            }
        end,
        CreateControlTextContainer = function()
            local items = {}
            return {
                Add = function(self, value, text, tooltip)
                    items[#items + 1] = { value = value, text = text, tooltip = tooltip }
                end,
                GetData = function() return items end,
            }
        end,
        CreateElementInitializer = function(template, data) return {} end,
        VarType = {
            Boolean = "boolean",
            Number = "number",
            String = "string",
        },
    }

    _G.MinimalSliderWithSteppersMixin = {
        Label = { Right = 1 },
    }

    _G.InterfaceOptions_AddCategory = function(panel) end
    _G.InterfaceOptionsFrame_OpenToCategory = function(panel) end

    ---------------------------------------------------------------------------
    -- GameTooltip (with call tracking for UX consistency tests)
    ---------------------------------------------------------------------------

    _G.GameTooltip = CreateMockFrame("GameTooltip", nil, nil, nil)

    -- Call tracking arrays (reset these in tests via wipe())
    _G.GameTooltip._calls = {}

    local origSetOwner = _G.GameTooltip.SetOwner
    _G.GameTooltip.SetOwner = function(self, owner, anchor)
        self._calls[#self._calls + 1] = { method = "SetOwner", owner = owner, anchor = anchor }
        if origSetOwner then origSetOwner(self, owner, anchor) end
    end

    local origSetText = _G.GameTooltip.SetText
    _G.GameTooltip.SetText = function(self, text)
        self._calls[#self._calls + 1] = { method = "SetText", text = text }
        self._text = text or ""
    end

    local origAddLine = _G.GameTooltip.AddLine
    _G.GameTooltip.AddLine = function(self, text, r, g, b)
        self._calls[#self._calls + 1] = { method = "AddLine", text = text, r = r, g = g, b = b }
    end

    _G.GameTooltip.Show = function(self)
        self._calls[#self._calls + 1] = { method = "Show" }
        self._shown = true
    end

    _G.GameTooltip.SetSpellByID = function(self, id)
        self._calls[#self._calls + 1] = { method = "SetSpellByID", id = id }
    end

    _G.GameTooltip.SetItemByID = function(self, id)
        self._calls[#self._calls + 1] = { method = "SetItemByID", id = id }
    end

    -- Track GameTooltip_Hide calls
    cfg.tooltipHideCalls = 0
    _G.GameTooltip_Hide = function()
        cfg.tooltipHideCalls = (cfg.tooltipHideCalls or 0) + 1
    end

    ---------------------------------------------------------------------------
    -- Shopping Tooltips (comparison tooltips for equipped items)
    ---------------------------------------------------------------------------

    _G.ShoppingTooltip1 = CreateMockFrame("GameTooltip", nil, nil, nil)
    _G.ShoppingTooltip2 = CreateMockFrame("GameTooltip", nil, nil, nil)

    ---------------------------------------------------------------------------
    -- UIDropDownMenu Stubs
    ---------------------------------------------------------------------------

    _G.UIDropDownMenu_Initialize = function(frame, initFunc)
        if initFunc then
            -- Store for later
            frame._initFunc = initFunc
        end
    end

    _G.UIDropDownMenu_SetWidth = function(frame, width)
        if frame then frame._ddWidth = width end
    end

    _G.UIDropDownMenu_SetText = function(frame, text)
        if frame then frame._ddText = text end
    end

    _G.UIDropDownMenu_CreateInfo = function()
        return {
            text = "",
            func = nil,
            checked = false,
            disabled = false,
            notCheckable = false,
        }
    end

    _G.UIDropDownMenu_AddButton = function(info, level)
        -- Stub: in real WoW this adds to the dropdown menu
    end

    ---------------------------------------------------------------------------
    -- C_Widget stub (WoW 11.0+ modern widget detection)
    ---------------------------------------------------------------------------
    _G.C_Widget = {
        IsFrameWidget = function(frame) return frame ~= nil end,
    }

    ---------------------------------------------------------------------------
    -- WorldMapFrame stub
    ---------------------------------------------------------------------------

    _G.WorldMapFrame = CreateMockFrame("Frame", nil, nil, nil)
    _G.WorldMapFrame.GetMapID = function(self) return cfg.currentMapID end
    _G.WorldMapFrame.SetMapID = function(self, mapID)
        cfg.currentMapID = mapID
    end

    ---------------------------------------------------------------------------
    -- DungeonEntrancePinMixin stub (dungeon entrance pins on world map)
    ---------------------------------------------------------------------------

    _G.DungeonEntrancePinMixin = {
        OnMouseClickAction = function() end,
    }

    ---------------------------------------------------------------------------
    -- QuestMapFrame stub (sidebar in the world map)
    ---------------------------------------------------------------------------

    _G.QuestMapFrame = CreateMockFrame("Frame", nil, nil, nil)

    ---------------------------------------------------------------------------
    -- EncounterJournal stub (Blizzard Encounter Journal UI frame)
    ---------------------------------------------------------------------------

    _G.EncounterJournal = CreateMockFrame("Frame", "EncounterJournal", nil, nil)
    _G.EncounterJournal.instanceID = nil

    _G.EncounterJournal_DisplayInstance = function(instanceID)
        _G.EncounterJournal.instanceID = instanceID
    end

    ---------------------------------------------------------------------------
    -- SlashCmdList
    ---------------------------------------------------------------------------

    _G.SlashCmdList = _G.SlashCmdList or {}

    ---------------------------------------------------------------------------
    -- TomTom global (nil by default, set via config)
    ---------------------------------------------------------------------------

    _G.TomTom = cfg.tomtom

    ---------------------------------------------------------------------------
    -- SavedVariables placeholder
    ---------------------------------------------------------------------------

    _G.QuickRouteDB = _G.QuickRouteDB or {}

    ---------------------------------------------------------------------------
    -- Font objects (templates referenced by CreateFontString)
    ---------------------------------------------------------------------------

    _G.GameFontNormal = {}
    _G.GameFontNormalSmall = {}
    _G.GameFontNormalLarge = {}
    _G.GameFontHighlight = {}
    _G.GameFontHighlightSmall = {}

    ---------------------------------------------------------------------------
    -- Sound Functions
    ---------------------------------------------------------------------------

    _G.SOUNDKIT = {
        IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
        IG_MAINMENU_CLOSE = 851,
        IG_CHARACTER_INFO_OPEN = 839,
        IG_MAINMENU_OPEN = 850,
        IG_CHARACTER_INFO_TAB = 841,
    }

    -- WoW global string constants used by addons
    _G.CLOSE = "Close"

    _G.PlaySound = function(soundID, channel)
        -- Track calls for test verification
        if not cfg.playedSounds then
            cfg.playedSounds = {}
        end
        cfg.playedSounds[#cfg.playedSounds + 1] = {
            soundID = soundID,
            channel = channel,
        }
    end

    _G.GetBindLocation = function()
        return cfg.bindLocation
    end

    ---------------------------------------------------------------------------
    -- Misc WoW globals
    ---------------------------------------------------------------------------

    _G.FACTION_STANDING_LABEL1 = "Hated"
    _G.FACTION_STANDING_LABEL2 = "Hostile"
    _G.FACTION_STANDING_LABEL3 = "Unfriendly"
    _G.FACTION_STANDING_LABEL4 = "Neutral"
    _G.FACTION_STANDING_LABEL5 = "Friendly"
    _G.FACTION_STANDING_LABEL6 = "Honored"
    _G.FACTION_STANDING_LABEL7 = "Revered"
    _G.FACTION_STANDING_LABEL8 = "Exalted"

    return self
end

-------------------------------------------------------------------------------
-- Layout Computation Engine
-- Resolves anchor chains to absolute screen coordinates for layout testing.
-------------------------------------------------------------------------------

--- Parse a stored SetPoint entry into structured anchor data.
-- WoW's SetPoint has multiple call forms:
--   SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
--   SetPoint(point, offsetX, offsetY)  -- relativeTo = parent
--   SetPoint(point)  -- relativeTo = parent, relativePoint = point, offsets = 0
-- @param frame table The frame that called SetPoint
-- @param pointData table The stored {point, ...} from frame._points
-- @return table Parsed anchor with point, relativeTo, relativePoint, offsetX, offsetY
local function ParseSetPoint(frame, pointData)
    local point = pointData[1]
    local arg2 = pointData[2]
    local arg3 = pointData[3]
    local arg4 = pointData[4]
    local arg5 = pointData[5]

    local relativeTo, relativePoint, offsetX, offsetY

    if type(arg2) == "table" then
        -- SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
        relativeTo = arg2
        relativePoint = type(arg3) == "string" and arg3 or point
        offsetX = (type(arg3) == "string" and arg4 or arg3) or 0
        offsetY = (type(arg3) == "string" and arg5 or arg4) or 0
    elseif type(arg2) == "number" then
        -- SetPoint(point, offsetX, offsetY) - relative to parent
        relativeTo = frame._parent
        relativePoint = point
        offsetX = arg2
        offsetY = arg3 or 0
    else
        -- SetPoint(point) - relative to parent, same point, no offsets
        relativeTo = frame._parent
        relativePoint = point
        offsetX = 0
        offsetY = 0
    end

    return {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint or point,
        offsetX = tonumber(offsetX) or 0,
        offsetY = tonumber(offsetY) or 0,
    }
end

--- Get the x,y position of a named anchor point on a frame with known bounds.
-- WoW coordinate system: X increases right, Y increases up.
-- @param bounds table {left, right, top, bottom}
-- @param anchorPoint string Anchor name like "TOPLEFT", "CENTER", "RIGHT", etc.
-- @return number x, number y  The absolute position of that anchor
local function GetAnchorPosition(bounds, anchorPoint)
    local ap = (anchorPoint or "CENTER"):upper()
    local x, y

    -- X position
    if ap:find("LEFT") then
        x = bounds.left
    elseif ap:find("RIGHT") then
        x = bounds.right
    else
        x = (bounds.left + bounds.right) / 2
    end

    -- Y position
    if ap:find("TOP") then
        y = bounds.top
    elseif ap:find("BOTTOM") then
        y = bounds.bottom
    else
        y = (bounds.top + bounds.bottom) / 2
    end

    return x, y
end

--- Compute absolute screen bounds for a frame by resolving its anchor chain.
-- Results are cached on the frame as _computedBounds until ClearComputedBounds is called.
-- @param frame table The mock frame to compute bounds for
-- @return table|nil {left, right, top, bottom} or nil if unresolvable
function MockWoW:ComputeFrameBounds(frame)
    if not frame then return nil end

    -- Return cached result
    if frame._computedBounds then return frame._computedBounds end

    -- UIParent has fixed known bounds
    if frame == _G.UIParent then
        local bounds = {
            left = 0,
            bottom = 0,
            right = frame._size and frame._size.w or 1024,
            top = frame._size and frame._size.h or 768,
        }
        frame._computedBounds = bounds
        return bounds
    end

    -- Resolve parent bounds first
    local parent = frame._parent
    local parentBounds
    if parent then
        parentBounds = self:ComputeFrameBounds(parent)
    end

    if not parentBounds then
        -- No parent bounds available - use UIParent as fallback
        parentBounds = self:ComputeFrameBounds(_G.UIParent)
    end

    -- Parse all anchor points
    local anchors = {}
    for _, pointData in ipairs(frame._points or {}) do
        anchors[#anchors + 1] = ParseSetPoint(frame, pointData)
    end

    -- Track constraints from anchors
    local constraints = {}  -- left, right, top, bottom, centerX, centerY

    for _, anchor in ipairs(anchors) do
        -- Get the relative frame's bounds
        local relBounds
        if anchor.relativeTo then
            relBounds = self:ComputeFrameBounds(anchor.relativeTo)
        end
        if not relBounds then
            relBounds = parentBounds
        end

        if relBounds then
            -- Get the position of the relative anchor point
            local relX, relY = GetAnchorPosition(relBounds, anchor.relativePoint)

            -- Apply offsets (positive X = right, positive Y = up)
            local absX = relX + anchor.offsetX
            local absY = relY + anchor.offsetY

            -- Map this frame's anchor point to the absolute position
            local ap = anchor.point:upper()

            -- Set X constraint
            if ap:find("LEFT") then
                constraints.left = absX
            elseif ap:find("RIGHT") then
                constraints.right = absX
            else
                constraints.centerX = absX
            end

            -- Set Y constraint
            if ap:find("TOP") then
                constraints.top = absY
            elseif ap:find("BOTTOM") then
                constraints.bottom = absY
            else
                constraints.centerY = absY
            end
        end
    end

    -- Resolve missing bounds using explicit size
    local w = frame._size and frame._size.w or 0
    local h = frame._size and frame._size.h or 0
    local bounds = {}

    -- Resolve horizontal
    if constraints.left and constraints.right then
        bounds.left = constraints.left
        bounds.right = constraints.right
    elseif constraints.left then
        bounds.left = constraints.left
        bounds.right = constraints.left + w
    elseif constraints.right then
        bounds.right = constraints.right
        bounds.left = constraints.right - w
    elseif constraints.centerX then
        bounds.left = constraints.centerX - w / 2
        bounds.right = constraints.centerX + w / 2
    else
        -- No X anchors - default to parent's left edge
        bounds.left = parentBounds.left
        bounds.right = parentBounds.left + w
    end

    -- Resolve vertical (WoW: top > bottom)
    if constraints.top and constraints.bottom then
        bounds.top = constraints.top
        bounds.bottom = constraints.bottom
    elseif constraints.top then
        bounds.top = constraints.top
        bounds.bottom = constraints.top - h
    elseif constraints.bottom then
        bounds.bottom = constraints.bottom
        bounds.top = constraints.bottom + h
    elseif constraints.centerY then
        bounds.top = constraints.centerY + h / 2
        bounds.bottom = constraints.centerY - h / 2
    else
        -- No Y anchors - default to parent's top edge
        bounds.top = parentBounds.top
        bounds.bottom = parentBounds.top - h
    end

    frame._computedBounds = bounds
    return bounds
end

--- Clear computed bounds cache for a frame and all its children (recursive).
-- Call this before recomputing layout after anchor/size changes.
-- @param frame table|nil The frame to clear (nil = clear all via UIParent)
function MockWoW:ClearComputedBounds(frame)
    if not frame then
        -- Clear UIParent and let lazy recomputation handle everything
        if _G.UIParent then
            _G.UIParent._computedBounds = nil
        end
        return
    end
    frame._computedBounds = nil
    -- Clear children
    for _, child in ipairs(frame._children or {}) do
        self:ClearComputedBounds(child)
    end
end

--- Convenience: compute bounds and return width
-- @param frame table The mock frame
-- @return number The computed width, or 0 if bounds can't be resolved
function MockWoW:GetComputedWidth(frame)
    local bounds = self:ComputeFrameBounds(frame)
    if bounds then
        return bounds.right - bounds.left
    end
    return 0
end

--- Convenience: compute bounds and return height
-- @param frame table The mock frame
-- @return number The computed height, or 0 if bounds can't be resolved
function MockWoW:GetComputedHeight(frame)
    local bounds = self:ComputeFrameBounds(frame)
    if bounds then
        return bounds.top - bounds.bottom
    end
    return 0
end

-------------------------------------------------------------------------------
-- Module export
-------------------------------------------------------------------------------

return MockWoW
