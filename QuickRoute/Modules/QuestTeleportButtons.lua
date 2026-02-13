-- QuestTeleportButtons.lua
-- Shows teleport buttons next to tracked quests in the objective tracker
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local math_huge = math.huge
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local GetItemIcon = GetItemIcon

-- Constants
local POOL_SIZE = 8
local CACHE_TTL = 30         -- seconds
local UPDATE_THROTTLE = 0.2  -- seconds
local DEBOUNCE_DELAY = 0.3   -- seconds - debounce rapid QUEST_LOG_UPDATE events
local BUTTON_SIZE = 20
local BUTTON_OFFSET_X = -4   -- pixels left of quest header

-------------------------------------------------------------------------------
-- QuestTeleportButtons Module
-------------------------------------------------------------------------------
QR.QuestTeleportButtons = {
    pool = {},            -- Pre-created SecureActionButtonTemplate buttons
    activeButtons = {},   -- { [questID] = button }
    questCache = {},      -- { [questID] = { teleportID, sourceType, data, time } }
    initialized = false,
    updateElapsed = 0,
    enabled = true,
}

local QTB = QR.QuestTeleportButtons

-------------------------------------------------------------------------------
-- Quest Coordinate Detection
-- Reuses the same approach as WaypointIntegration:GetSuperTrackedWaypoint()
-------------------------------------------------------------------------------

--- Get the target map ID for a quest
-- Tries multiple APIs in priority order
-- @param questID number
-- @return number|nil mapID where the quest objective is located
local function GetQuestTargetMapID(questID)
    if not questID then return nil end

    -- Method 1: GetNextWaypoint returns actual target mapID (cross-map, 8.2.0+)
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local wpMapID, wpX, wpY = C_QuestLog.GetNextWaypoint(questID)
        if wpMapID then
            -- If continent-level, try to resolve to zone
            if C_Map and C_Map.GetMapInfo then
                local mapInfo = C_Map.GetMapInfo(wpMapID)
                if mapInfo and mapInfo.mapType and mapInfo.mapType <= 2 then
                    if C_Map.GetMapInfoAtPosition then
                        local childInfo = C_Map.GetMapInfoAtPosition(wpMapID, wpX or 0, wpY or 0)
                        if childInfo and childInfo.mapID and childInfo.mapID ~= wpMapID then
                            return childInfo.mapID
                        end
                    end
                end
            end
            return wpMapID
        end
    end

    -- Method 2: GetNextWaypointForMap on player's current map
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if playerMapID and C_QuestLog and C_QuestLog.GetNextWaypointForMap then
        local wpX, wpY = C_QuestLog.GetNextWaypointForMap(questID, playerMapID)
        if wpX and wpY then
            return playerMapID
        end
    end

    -- Method 3: GetQuestsOnMap - quest POI on player's map
    if playerMapID and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local questsOnMap = C_QuestLog.GetQuestsOnMap(playerMapID)
        if questsOnMap then
            for _, questInfo in ipairs(questsOnMap) do
                if questInfo.questID == questID then
                    if questInfo.x and questInfo.y and (questInfo.x ~= 0 or questInfo.y ~= 0) then
                        return playerMapID
                    end
                end
            end
        end
    end

    return nil
end

-------------------------------------------------------------------------------
-- Best Teleport Selection
-------------------------------------------------------------------------------

--- Find the best teleport to get close to a quest's map
-- Prefers: same map > same continent > any available
-- @param questMapID number The target map ID
-- @return number|nil teleportID
-- @return table|nil entry from GetAllTeleports
local function FindBestTeleportForQuest(questMapID)
    if not questMapID then return nil, nil end

    local teleports = QR.PlayerInventory and QR.PlayerInventory:GetAllTeleports()
    if not teleports then return nil, nil end

    local questContinent = QR.GetContinentForZone and QR.GetContinentForZone(questMapID)
    local bestID, bestEntry, bestScore = nil, nil, 0

    for id, entry in pairs(teleports) do
        if entry.data and entry.data.mapID then
            local score = 0

            -- Same map = best (score 3)
            if entry.data.mapID == questMapID then
                score = 3
            else
                local teleContinent = QR.GetContinentForZone and QR.GetContinentForZone(entry.data.mapID)
                if questContinent and teleContinent and questContinent == teleContinent then
                    -- Same continent (score 2)
                    score = 2
                else
                    -- Different continent (score 1)
                    score = 1
                end
            end

            -- Prefer teleports that are off cooldown
            if score > 0 and QR.CooldownTracker then
                local cd
                if entry.sourceType == "spell" then
                    cd = QR.CooldownTracker:GetSpellCooldown(id)
                else
                    cd = QR.CooldownTracker:GetItemCooldown(id)
                end
                -- Boost score for ready teleports
                if cd and cd.ready then
                    score = score + 0.5
                end
            end

            if score > bestScore then
                bestScore = score
                bestID = id
                bestEntry = entry
            end
        end
    end

    return bestID, bestEntry
end

-------------------------------------------------------------------------------
-- Cache Management
-------------------------------------------------------------------------------

--- Get or compute the best teleport for a quest, with caching
-- @param questID number
-- @return number|nil teleportID
-- @return string|nil sourceType
-- @return table|nil data from TeleportItemsData
local function GetCachedTeleportForQuest(questID)
    local now = GetTime()
    local cached = QTB.questCache[questID]
    if cached and (now - cached.time) < CACHE_TTL then
        return cached.teleportID, cached.sourceType, cached.data
    end

    local questMapID = GetQuestTargetMapID(questID)
    if not questMapID then
        QTB.questCache[questID] = { time = now }
        return nil, nil, nil
    end

    local teleportID, entry = FindBestTeleportForQuest(questMapID)
    if teleportID and entry then
        QTB.questCache[questID] = {
            teleportID = teleportID,
            sourceType = entry.sourceType,
            data = entry.data,
            time = now,
        }
        return teleportID, entry.sourceType, entry.data
    end

    QTB.questCache[questID] = { time = now }
    return nil, nil, nil
end

--- Invalidate the cache for all quests
function QTB:InvalidateCache()
    wipe(self.questCache)
end

-------------------------------------------------------------------------------
-- Button Pool & Configuration
-------------------------------------------------------------------------------

--- Initialize the module: create button pool and register events
function QTB:Initialize()
    if self.initialized then return end

    if InCombatLockdown() then
        -- Defer initialization until combat ends
        QR:RegisterCombatCallback(nil, function()
            QTB:Initialize()
        end)
        return
    end

    -- Create button pool
    for i = 1, POOL_SIZE do
        local btn = CreateFrame("Button", "QRQuestBtn" .. i, UIParent, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyDown", "AnyUp")
        btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        btn:Hide()
        btn.inUse = false
        btn.questID = nil

        -- Create icon texture
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        btn.icon = icon

        -- Tooltip handlers
        btn:SetScript("OnEnter", function(self)
            if not self.tooltipText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
            if self.tooltipSubtext then
                GameTooltip:AddLine(self.tooltipSubtext, 0.7, 0.7, 0.7, true)
            end
            QR.AddTooltipBranding(GameTooltip)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip_Hide()
        end)

        -- Micro-icon for brand identification
        QR.AddMicroIcon(btn, 8)

        self.pool[i] = btn
    end

    -- Create the OnUpdate frame for positioning
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame:SetScript("OnUpdate", function(frame, elapsed)
        QTB:OnUpdate(elapsed)
    end)
    self.updateFrame:Hide() -- Only show when buttons are active

    -- Register events
    self:RegisterEvents()

    -- Register combat callbacks to hide/show buttons
    QR:RegisterCombatCallback(
        function() -- entering combat: hide update frame (buttons freeze in place)
            if QTB.updateFrame then
                QTB.updateFrame:Hide()
            end
        end,
        function() -- leaving combat: refresh
            QTB:RefreshButtons()
        end
    )

    self.initialized = true
    QR:Debug("QuestTeleportButtons initialized with " .. POOL_SIZE .. " buttons")
end

--- Get a free button from the pool
-- @return Button|nil
local function GetFreeButton()
    for _, btn in ipairs(QTB.pool) do
        if not btn.inUse then
            btn.inUse = true
            return btn
        end
    end
    return nil
end

--- Release a button back to the pool
-- @param btn Button
local function ReleaseButton(btn)
    if not btn then return end
    if InCombatLockdown() then return end

    btn:Hide()
    btn:ClearAllPoints()
    btn:SetAttribute("type", nil)
    btn:SetAttribute("macrotext", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("toy", nil)
    btn:SetAttribute("item", nil)
    btn.inUse = false
    btn.questID = nil
    btn.tooltipText = nil
    btn.tooltipSubtext = nil
    if btn.icon then
        btn.icon:SetTexture(nil)
    end
end

--- Release all active buttons
function QTB:ReleaseAllButtons()
    if InCombatLockdown() then return end

    for questID, btn in pairs(self.activeButtons) do
        ReleaseButton(btn)
    end
    wipe(self.activeButtons)

    if self.updateFrame then
        self.updateFrame:Hide()
    end
end

--- Configure a button for a teleport
-- @param btn Button
-- @param teleportID number
-- @param sourceType string "spell", "toy", "item", "equipped"
-- @param data table TeleportItemsData entry
-- @return boolean success
local function ConfigureButton(btn, teleportID, sourceType, data)
    if InCombatLockdown() then return false end
    if not btn or not teleportID then return false end

    -- Validate ID is a positive integer (prevent macro injection)
    local math_floor = math.floor
    if type(teleportID) ~= "number" or teleportID ~= math_floor(teleportID) or teleportID <= 0 then return false end

    -- Set secure attributes
    if sourceType == "spell" then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", teleportID)
    elseif sourceType == "toy" then
        btn:SetAttribute("type", "toy")
        btn:SetAttribute("toy", teleportID)
    else
        -- item or equipped
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", "/use item:" .. teleportID)
    end

    -- Set icon
    if btn.icon then
        local iconID
        if sourceType == "spell" then
            iconID = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(teleportID)
                or GetSpellTexture and GetSpellTexture(teleportID)
        else
            iconID = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(teleportID)
                or GetItemIcon and GetItemIcon(teleportID)
        end
        if iconID then
            btn.icon:SetTexture(iconID)
        end
    end

    -- Set tooltip
    local name = data and data.name or tostring(teleportID)
    local dest = data and data.destination or ""
    btn.tooltipText = name
    btn.tooltipSubtext = dest ~= "" and dest or nil

    return true
end

-------------------------------------------------------------------------------
-- Quest Watch List & Button Refresh
-------------------------------------------------------------------------------

--- Get currently tracked quest IDs
-- @return table Array of quest IDs
local function GetTrackedQuestIDs()
    local quests = {}

    if C_QuestLog and C_QuestLog.GetNumQuestWatches then
        local numWatches = C_QuestLog.GetNumQuestWatches()
        for i = 1, numWatches do
            local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
            if questID and questID > 0 then
                quests[#quests + 1] = questID
            end
        end
    end

    return quests
end

--- Refresh all quest teleport buttons
-- Called on quest list changes, after combat, etc.
function QTB:RefreshButtons()
    if not self.initialized then return end
    if not self.enabled then return end
    if InCombatLockdown() then return end

    -- Release all current buttons
    self:ReleaseAllButtons()

    local trackedQuests = GetTrackedQuestIDs()
    if #trackedQuests == 0 then return end

    local hasActive = false
    for _, questID in ipairs(trackedQuests) do
        local teleportID, sourceType, data = GetCachedTeleportForQuest(questID)
        if teleportID and sourceType then
            local btn = GetFreeButton()
            if btn then
                if ConfigureButton(btn, teleportID, sourceType, data) then
                    btn.questID = questID
                    self.activeButtons[questID] = btn
                    hasActive = true
                else
                    ReleaseButton(btn)
                end
            end
        end
    end

    -- Start/stop the OnUpdate frame based on whether we have active buttons
    if hasActive and self.updateFrame then
        self.updateFrame:Show()
    end
end

-------------------------------------------------------------------------------
-- Button Positioning via OnUpdate
-------------------------------------------------------------------------------

--- OnUpdate handler: position buttons relative to ObjectiveTracker quest blocks
-- @param elapsed number Time since last frame
function QTB:OnUpdate(elapsed)
    self.updateElapsed = self.updateElapsed + elapsed
    if self.updateElapsed < UPDATE_THROTTLE then return end
    self.updateElapsed = 0

    if InCombatLockdown() then return end

    -- No ObjectiveTrackerFrame in test environment or if hidden
    if not ObjectiveTrackerFrame then
        return
    end

    -- WoW 11.x uses the MODULES system
    -- Try to find quest header blocks to position buttons next to
    local questBlocks = {}
    if ObjectiveTrackerFrame.MODULES then
        for _, module in ipairs(ObjectiveTrackerFrame.MODULES) do
            if module.usedBlocks then
                for questID, block in pairs(module.usedBlocks) do
                    if type(questID) == "number" and block.HeaderText then
                        questBlocks[questID] = block
                    end
                end
            end
        end
    end

    -- Position each active button next to its quest block
    for questID, btn in pairs(self.activeButtons) do
        local block = questBlocks[questID]
        if block and block:IsVisible() then
            local left = block:GetLeft()
            local top = block:GetTop()
            local bottom = block:GetBottom()
            if left and top and bottom then
                local centerY = (top + bottom) / 2
                btn:ClearAllPoints()
                btn:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", left + BUTTON_OFFSET_X, centerY)
                if not btn:IsShown() then
                    btn:Show()
                end
            end
        else
            -- Quest block not visible; hide button
            btn:Hide()
        end
    end
end

-------------------------------------------------------------------------------
-- Event Handling
-------------------------------------------------------------------------------

--- Register for quest-related events
function QTB:RegisterEvents()
    if self.eventFrame then return end

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    self.eventFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    self.eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")

    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        -- Don't refresh in combat
        if InCombatLockdown() then return end

        -- Invalidate cache on tracking changes
        if event == "QUEST_WATCH_LIST_CHANGED" or event == "SUPER_TRACKING_CHANGED" then
            QTB:InvalidateCache()
        end

        -- Debounce rapid QUEST_LOG_UPDATE events with a timer
        if QTB.debounceTimer then
            QTB.debounceTimer:Cancel()
        end
        QTB.debounceTimer = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
            QTB.debounceTimer = nil
            if not InCombatLockdown() then
                QTB:RefreshButtons()
            end
        end)
    end)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Enable or disable the quest teleport buttons
-- @param enable boolean
function QTB:SetEnabled(enable)
    self.enabled = enable
    if not enable then
        -- Cancel any pending debounce timer
        if self.debounceTimer then
            self.debounceTimer:Cancel()
            self.debounceTimer = nil
        end
        self:ReleaseAllButtons()
    else
        self:RefreshButtons()
    end
end

--- Get the pool size
-- @return number
function QTB:GetPoolSize()
    return POOL_SIZE
end

--- Get the cache TTL
-- @return number seconds
function QTB:GetCacheTTL()
    return CACHE_TTL
end
