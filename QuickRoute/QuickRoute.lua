-- QuickRoute.lua
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local date = date
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local pcall = pcall

-- Namespace setup
QR.version = "1.4.0"
QR.debugMode = false

-- Constants
local DB_VERSION = 1
local INIT_DELAY = 2

-------------------------------------------------------------------------------
-- Debug Log System (ring buffer)
-------------------------------------------------------------------------------
local LOG_MAX_ENTRIES = 200
local logBuffer = {}
local logIndex = 0
local logCount = 0

--- Add a message to the debug log
-- Reuses existing table entries in the circular buffer to reduce GC pressure
-- @param level string "INFO", "WARN", "ERROR", "DEBUG"
-- @param msg string The message to log
function QR:Log(level, msg)
    logIndex = (logIndex % LOG_MAX_ENTRIES) + 1
    local entry = logBuffer[logIndex]
    if entry then
        entry.time = date("%H:%M:%S")
        entry.level = level
        entry.msg = msg
    else
        logBuffer[logIndex] = { time = date("%H:%M:%S"), level = level, msg = msg }
    end
    if logCount < LOG_MAX_ENTRIES then
        logCount = logCount + 1
    end
end

--- Get all log entries in chronological order
-- @return table Array of {time, level, msg} entries
function QR:GetLogEntries()
    local entries = {}
    if logCount == 0 then return entries end

    -- Start from oldest entry
    local start
    if logCount < LOG_MAX_ENTRIES then
        start = 1
    else
        start = (logIndex % LOG_MAX_ENTRIES) + 1
    end

    for i = 0, logCount - 1 do
        local idx = ((start - 1 + i) % LOG_MAX_ENTRIES) + 1
        if logBuffer[idx] then
            entries[#entries + 1] = logBuffer[idx]
        end
    end
    return entries
end

--- Clear all log entries
function QR:ClearLog()
    wipe(logBuffer)
    logIndex = 0
    logCount = 0
end

--- Print and log a message (replaces direct print calls)
-- @param msg string Message to print (can include WoW color codes)
function QR:Print(msg)
    print(msg)
    -- Strip color codes for clean log storage
    local cleanMsg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    self:Log("INFO", cleanMsg)
end

--- Print and log a debug message (only if debugMode is on)
-- @param msg string Debug message
function QR:Debug(msg)
    if self.debugMode then
        local L = self.L
        local prefix = L and L["DEBUG_PREFIX"] or "|cFF00FF00QuickRoute|r: "
        print(prefix .. msg)
    end
    self:Log("DEBUG", msg)
end

--- Print and log a warning message
-- @param msg string Warning message
function QR:Warn(msg)
    local L = self.L
    local prefix = L and L["WARNING_PREFIX"] or "|cFFFF6600QuickRoute WARNING|r: "
    print(prefix .. msg)
    self:Log("WARN", msg)
end

--- Print and log an error message
-- @param msg string Error message
function QR:Error(msg)
    local L = self.L
    local prefix = L and L["ERROR_PREFIX"] or "|cFFFF0000QuickRoute ERROR:|r "
    print(prefix .. msg)
    self:Log("ERROR", msg)
end

-- Create main frame for event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME then
        QR:Initialize()
    elseif event == "PLAYER_LOGIN" then
        QR:OnPlayerLogin()
    end
end)

function QR:Initialize()
    -- Initialize saved variables
    QuickRouteDB = QuickRouteDB or {}

    -- Migration logic
    local currentVersion = tonumber(QuickRouteDB.dbVersion) or 0
    if currentVersion < DB_VERSION then
        -- Future migrations go here
        -- if currentVersion < 1 then ... end
        -- if currentVersion < 2 then ... end
        QuickRouteDB.dbVersion = DB_VERSION
    end

    -- Set defaults for missing keys (also validates types for existing keys)
    local defaults = {
        showMinimap = true,
        considerCooldowns = true,
        waypointPriority = "mappin",  -- "mappin", "quest", "tomtom"
        autoWaypoint = false,  -- Auto-set TomTom/native waypoint for first route step
        autoDestination = false,      -- Auto-show route on quest tracking change
        maxCooldownHours = 24,        -- Max cooldown filter (24 = no limit)
        loadingScreenTime = 5,        -- Loading screen time in seconds
        windowScale = 1.0,            -- Window scale (1.0 = 100%)
        availabilityFilter = "all",   -- Teleport panel filter: "all", "available", "ready"
        useIconButtons = false,       -- Replace button text with icons
        sidebarCollapsed = false,     -- Map sidebar collapsed state
        activeTab = "route",          -- Last active tab in unified window
        groupByDestination = false,   -- Group teleports by destination
    }
    for k, v in pairs(defaults) do
        if QuickRouteDB[k] == nil or type(QuickRouteDB[k]) ~= type(v) then
            QuickRouteDB[k] = v
        end
    end

    self.db = QuickRouteDB

    -- First-run welcome message
    if not self.db.firstRunShown then
        local L = self.L
        local loadedMsg = L and L["ADDON_LOADED"] or "|cFF00FF00QuickRoute|r v%s loaded"
        local firstRunMsg = L and L["ADDON_FIRST_RUN"] or "Type |cFFFFFF00/qr|r to open or |cFFFFFF00/qrhelp|r for commands."
        print(string.format(loadedMsg, self.version) .. " " .. firstRunMsg)
        self.db.firstRunShown = true
    elseif self.debugMode then
        local L = self.L
        local loadedMsg = L and L["ADDON_LOADED"] or "|cFF00FF00QuickRoute|r v%s loaded"
        print(string.format(loadedMsg, self.version))
    end
end

function QR:OnPlayerLogin()
    -- Defer heavy initialization until player is fully loaded
    C_Timer.After(INIT_DELAY, function()
        if not self.db then
            self:Error("SavedVariables not initialized")
            return
        end
        -- Initialize dungeon data before graph build so nodes are available
        if QR.DungeonData then
            local ddOk, ddErr = pcall(function() QR.DungeonData:Initialize() end)
            if not ddOk then
                QR:Error("DungeonData init failed: " .. tostring(ddErr))
            end
        end

        local steps = {
            { "Graph",              function() QR:InitializeGraph() end },
            { "PlayerTeleports",    function() QR:ScanPlayerTeleports() end },
            { "SecureButtons",      function() QR.SecureButtons:Initialize() end },
            { "WaypointIntegration",function() QR.WaypointIntegration:Initialize() end },
            { "MainFrame",          function() QR.MainFrame:Initialize() end },
            { "UI",                 function() QR.UI:Initialize() end },
            { "TeleportPanel",      function() QR.TeleportPanel:Initialize() end },
            { "MinimapButton",      function() QR.MinimapButton:Initialize() end },
            { "MiniTeleportPanel",  function() QR.MiniTeleportPanel:Initialize() end },
            { "MapSidebar",         function() QR.MapSidebar:Initialize() end },
            { "MapTeleportButton",  function() QR.MapTeleportButton:Initialize() end },
            { "QuestTeleportBtns",  function() QR.QuestTeleportButtons:Initialize() end },
            { "POIRouting",         function() QR.POIRouting:Initialize() end },
            { "EJButton",           function() if QR.EncounterJournalButton then QR.EncounterJournalButton:Initialize() end end },
            { "DestinationSearch",  function() QR.DestinationSearch:Initialize() end },
            { "ServiceRouter",      function() QR.ServiceRouter:Initialize() end },
            { "SettingsPanel",      function() QR.SettingsPanel:Initialize() end },
        }
        for _, step in ipairs(steps) do
            local ok, err = pcall(step[2])
            if not ok then
                QR:Error("Init " .. step[1] .. " failed: " .. tostring(err))
            end
        end
    end)
end

function QR:InitializeGraph()
    QR.PathCalculator:BuildGraph()
    if self.debugMode then
        local L = self.L
        QR:Debug(L and L["TRAVEL_GRAPH_BUILT"] or "Travel graph built")
    end
end

function QR:ScanPlayerTeleports()
    QR.PlayerInventory:ScanAll()
    local count = QR.PlayerInventory:GetTeleportCount()
    if self.debugMode then
        local L = self.L
        QR:Debug(string.format(L and L["FOUND_TELEPORTS"] or "Found %d teleport methods", count))
    end
end

-------------------------------------------------------------------------------
-- Centralized Combat State Manager
-- Single event frame for PLAYER_REGEN_DISABLED/ENABLED, replacing per-module
-- combat frames. Modules register callbacks via QR:RegisterCombatCallback().
-------------------------------------------------------------------------------

QR.inCombat = false

-- Internal: registered callbacks { { enter = func|nil, leave = func|nil }, ... }
local combatCallbacks = {}

--- Register callbacks to be invoked when the player enters/leaves combat.
-- Either callback may be nil to skip that event.
-- @param enterCallback function|nil Called on PLAYER_REGEN_DISABLED (entering combat)
-- @param leaveCallback function|nil Called on PLAYER_REGEN_ENABLED (leaving combat)
function QR:RegisterCombatCallback(enterCallback, leaveCallback)
    if type(enterCallback) ~= "function" then enterCallback = nil end
    if type(leaveCallback) ~= "function" then leaveCallback = nil end
    if not enterCallback and not leaveCallback then return end
    combatCallbacks[#combatCallbacks + 1] = {
        enter = enterCallback,
        leave = leaveCallback,
    }
end

-- Create and register the single combat event frame
do
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            QR.inCombat = true
            for _, cb in ipairs(combatCallbacks) do
                if cb.enter then
                    local ok, err = pcall(cb.enter)
                    if not ok then
                        QR:Error("Combat enter callback error: " .. tostring(err))
                    end
                end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            QR.inCombat = false
            for _, cb in ipairs(combatCallbacks) do
                if cb.leave then
                    local ok, err = pcall(cb.leave)
                    if not ok then
                        QR:Error("Combat leave callback error: " .. tostring(err))
                    end
                end
            end
        end
    end)
    -- Expose the frame for test access
    QR.combatFrame = combatFrame
end

-- Expose namespace globally only in debug mode (for /run inspection)
if QR.debugMode then
    _G.QuickRoute = QR
end

-- Help command
local function PrintHelp()
    print("|cFF00FF00QuickRoute|r - Commands:")
    print("  /qr - Toggle pathfinder window")
    print("  /qr show - Show window")
    print("  /qr hide - Hide window")
    print("  /qr settings - Open settings panel")
    print("  /qr minimap - Toggle minimap button")
    print("  /qr debug - Toggle debug mode")
    print("  /qr priority mappin|quest|tomtom - Set waypoint source priority")
    print("  /qr autowaypoint - Toggle auto-waypoint")
    print("  /qrdebug - Show waypoint detection info")
    print("  /qrdebug copy - Copy full debug info (markdown for bug reports)")
    print("  /qrinv - Show available teleports")
    print("  /qrcd - Show teleport cooldowns")
    print("  /qrwp - Calculate path to current waypoint")
    print("  /qrpath <mapID> <x> <y> - Calculate path to coordinates")
    print("  /qr ah - Route to nearest Auction House")
    print("  /qr bank - Route to nearest Bank")
    print("  /qr void - Route to nearest Void Storage")
    print("  /qr craft - Route to nearest Crafting Table")
    print("  /qrscreenshot [all|route|teleport|search|mini] - Take UI screenshots")
    print("  /qrtest graph - Run graph unit tests")
end

SLASH_QRHELP1 = "/qrhelp"
SlashCmdList["QRHELP"] = PrintHelp

-------------------------------------------------------------------------------
-- Addon Compartment (WoW 10.x+) - minimap gear menu integration
-------------------------------------------------------------------------------
function QuickRoute_OnAddonCompartmentClick(addonName, buttonName)
    if buttonName == "RightButton" then
        if QR.MainFrame then
            QR.MainFrame:Toggle("teleports")
        end
    else
        if QR.MainFrame then
            QR.MainFrame:Toggle("route")
        end
    end
end

function QuickRoute_OnAddonCompartmentEnter(addonName, menuButtonFrame)
    local L = QR.L
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPRIGHT", menuButtonFrame, "BOTTOMRIGHT", 0, 0)
    GameTooltip:AddLine(L["ADDON_TITLE"])
    GameTooltip:AddLine(L["TOOLTIP_MINIMAP_LEFT"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["TOOLTIP_MINIMAP_RIGHT"], 0.7, 0.7, 0.7)
    QR.AddTooltipBranding(GameTooltip)
    GameTooltip:Show()
end

function QuickRoute_OnAddonCompartmentLeave(addonName, menuButtonFrame)
    GameTooltip_Hide()
end
