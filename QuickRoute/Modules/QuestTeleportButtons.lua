-- QuestTeleportButtons.lua
-- Shows teleport buttons next to tracked quests in the objective tracker
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local math_huge = math.huge
local math_floor = math.floor
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
local MOVEMENT_CHECK_INTERVAL = 1

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

-- A small stable bucket avoids sub-pixel movement invalidating all quest
-- routes, while approaching an objective can replace a teleport with walking.
local function GetPositionBucket()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, bucket = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        if type(mapID) ~= "number" or (issecretvalue and issecretvalue(mapID))
            or mapID ~= mapID or mapID <= 0 or mapID >= math_huge or mapID % 1 ~= 0 then return end
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if not position then return end
        local x, y = position.x, position.y
        if position.GetXY then x, y = position:GetXY() end
        if (issecretvalue and (issecretvalue(x) or issecretvalue(y))) or type(x) ~= "number" or type(y) ~= "number"
            or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return end
        return string_format("%d:%d:%d", mapID, math_floor(x * 1000), math_floor(y * 1000))
    end)
    return ok and bucket or nil
end

-------------------------------------------------------------------------------
-- Route-based Teleport Selection
-------------------------------------------------------------------------------

--- Offer only an immediately usable first step of the computed quest route.
-- A teleport on the same continent is not necessarily faster than walking,
-- and a teleport later in the route must not skip its preceding travel.
local function FindBestTeleportForQuest(questID)
    if not (QR.WaypointIntegration and QR.PathCalculator and QR.PlayerInventory) then
        return nil, nil
    end
    local waypoint = QR.WaypointIntegration:GetQuestWaypoint(questID)
    if not waypoint then return nil, nil end

    local route = QR.PathCalculator:CalculatePath(waypoint.mapID, waypoint.x, waypoint.y, waypoint.title)
    local step = route and route.steps and route.steps[1]
    if not step or step.type ~= "teleport" or not step.teleportID then
        return nil, nil
    end
    local teleports = QR.PlayerInventory:GetAllTeleports()
    local entry = teleports and teleports[step.teleportID]
    local cooldown = QR.CooldownTracker and QR.CooldownTracker:GetCooldown(step.teleportID, step.sourceType)
    if not entry or not entry.data or not cooldown or not cooldown.ready then
        return nil, nil
    end
    return step.teleportID, { sourceType = entry.sourceType, data = step.teleportData or entry.data }
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
    local position = GetPositionBucket()
    if not position then QTB.questCache[questID] = nil; return nil, nil, nil end
    local cached = QTB.questCache[questID]
    local calculator = QR.PathCalculator
    if cached and cached.position == position and cached.graph == (calculator and calculator.graph)
        and not (calculator and calculator.graphDirty) and (now - cached.time) < CACHE_TTL then
        local cooldown = cached.teleportID and QR.CooldownTracker
            and QR.CooldownTracker:GetCooldown(cached.teleportID, cached.sourceType)
        if not cached.teleportID or (cooldown and cooldown.ready) then
            return cached.teleportID, cached.sourceType, cached.data
        end
    end

    local teleportID, entry = FindBestTeleportForQuest(questID)
    if teleportID and entry then
        QTB.questCache[questID] = {
            teleportID = teleportID,
            sourceType = entry.sourceType,
            data = entry.data,
            time = now,
            position = position,
            graph = QR.PathCalculator and QR.PathCalculator.graph,
        }
        return teleportID, entry.sourceType, entry.data
    end

    QTB.questCache[questID] = { time = now, position = position, graph = QR.PathCalculator and QR.PathCalculator.graph }
    return nil, nil, nil
end

--- Invalidate the cache for all quests
function QTB:InvalidateCache()
    self:CancelRefresh()
    wipe(self.questCache)
end

--- Invalidate queued per-frame work without touching protected buttons.
function QTB:CancelRefresh()
    self._refreshGeneration = (self._refreshGeneration or 0) + 1
    self._refreshRunning = false
end

-- SPELL_UPDATE_COOLDOWN also fires for unrelated abilities and global
-- cooldown updates. Replan quests only when a teleport's readiness changes.
local function UpdateCooldownState()
    local previous = QTB.cooldownState or {}
    local current, changed = {}, false
    local teleports = QR.PlayerInventory and QR.PlayerInventory:GetAllTeleports() or {}
    for id, entry in pairs(teleports) do
        local cooldown = QR.CooldownTracker and QR.CooldownTracker:GetCooldown(id, entry.sourceType)
        current[id] = cooldown and cooldown.ready or false
        if current[id] ~= previous[id] then changed = true end
    end
    for id in pairs(previous) do
        if current[id] == nil then changed = true end
    end
    QTB.cooldownState = current
    return changed
end

-------------------------------------------------------------------------------
-- Button Pool & Configuration
-------------------------------------------------------------------------------

--- Initialize the module: create button pool and register events
function QTB:Initialize()
    if self.initialized then return end
    self:CancelRefresh()

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

    -- Keep lightweight movement detection separate from secure positioning:
    -- walking may become preferable even when no teleport button is visible.
    self.movementFrame = CreateFrame("Frame")
    self.movementFrame:SetScript("OnUpdate", function(_, elapsed) QTB:OnMovementUpdate(elapsed) end)
    self.movementFrame:Hide()

    -- Register events
    self:RegisterEvents()

    -- Register combat callbacks to hide/show buttons
    QR:RegisterCombatCallback(
        function() -- entering combat: hide update frame (buttons freeze in place)
            QTB:CancelRefresh()
            if QTB.updateFrame then
                QTB.updateFrame:Hide()
            end
            if QTB.movementFrame then QTB.movementFrame:Hide() end
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
    btn:SetScript("PreClick", nil)
    btn:SetScript("PostClick", nil)
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
    self:CancelRefresh()
    if self.movementFrame then self.movementFrame:Hide() end
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

    if not QR.SecureButtons or not QR.SecureButtons:ConfigureButton(btn, teleportID, sourceType, data) then
        return false
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

    if C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
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
    self:CancelRefresh()
    if not self.initialized then return end
    if InCombatLockdown() then return end
    if not self.enabled then
        self:ReleaseAllButtons()
        return
    end

    -- Release all current buttons
    self:ReleaseAllButtons()
    UpdateCooldownState()

    local trackedQuests = GetTrackedQuestIDs()
    if #trackedQuests == 0 then return end
    if self.movementFrame then self.movementFrame:Show() end
    self._lastRefreshPosition = GetPositionBucket()
    self._lastRefreshGraph = QR.PathCalculator and QR.PathCalculator.graph

    local generation = self._refreshGeneration
    local index, activeCount = 1, 0
    self._refreshRunning = true
    local function IsCurrent()
        return generation == QTB._refreshGeneration and QTB.initialized and QTB.enabled and not InCombatLockdown()
    end
    local function RefreshOne()
        if not IsCurrent() then return end
        local questID = trackedQuests[index]
        if not questID or activeCount >= POOL_SIZE then return end
        -- A route calculation can take several milliseconds. Never calculate
        -- every watched quest in the same quest-log/event frame.
        local ok, teleportID, sourceType, data = pcall(GetCachedTeleportForQuest, questID)
        if not IsCurrent() then return end
        if not ok then
            QR:Debug("Quest button route unavailable: " .. tostring(teleportID))
            teleportID = nil
        end
        if teleportID and sourceType then
            local btn = GetFreeButton()
            if btn then
                if ConfigureButton(btn, teleportID, sourceType, data) then
                    btn.questID = questID
                    QTB.activeButtons[questID] = btn
                    activeCount = activeCount + 1
                    if QTB.updateFrame then QTB.updateFrame:Show() end
                else
                    ReleaseButton(btn)
                end
            end
        end
        index = index + 1
        if index <= #trackedQuests and activeCount < POOL_SIZE then
            C_Timer.After(0, RefreshOne)
        else
            QTB._refreshRunning = false
            QTB._lastRefreshGraph = QR.PathCalculator and QR.PathCalculator.graph
        end
    end
    C_Timer.After(0, RefreshOne)
end

--- Sample movement at most once per second; route work remains in the batch.
function QTB:OnMovementUpdate(elapsed)
    self._movementElapsed = (self._movementElapsed or 0) + elapsed
    if self._movementElapsed < MOVEMENT_CHECK_INTERVAL then return end
    self._movementElapsed = 0
    if not self.initialized or not self.enabled or InCombatLockdown() or self._refreshRunning then return end
    local position = GetPositionBucket()
    local calculator = QR.PathCalculator
    if position ~= self._lastRefreshPosition or (calculator and (calculator.graph ~= self._lastRefreshGraph or calculator.graphDirty)) then
        self:RefreshButtons()
    end
end

-------------------------------------------------------------------------------
-- Button Positioning via OnUpdate
-------------------------------------------------------------------------------

--- OnUpdate handler: position buttons relative to ObjectiveTracker quest blocks
-- @param elapsed number Time since last frame
--- Collect the objective-tracker blocks keyed by questID.
-- The tracker's shape has changed more than once and is Blizzard's own UI
-- code, not a documented API, so all three known shapes are tried in turn and
-- an unknown one yields an empty table rather than an error:
--   * modules + EnumerateActiveBlocks(callback)  -- current mixin surface
--   * modules + nested usedBlocks[template][id]  -- intermediate shape
--   * MODULES + flat usedBlocks[questID]         -- what this file assumed
-- @return table { [questID] = block }
-- @return boolean Whether every block provider present was read successfully.
--   An empty table with recognised = true means the tracker really has no
--   blocks. recognised = false means either an unknown shape or a provider
--   that raised -- in both cases the block set is incomplete and the caller
--   must not conclude a quest's block is gone. One provider failing is enough:
--   its blocks are missing from an otherwise plausible-looking result.
function QTB:CollectQuestBlocks()
    local blocks = {}
    local recognised = false
    local failed = false

    local function record(id, block)
        if type(id) == "number" and type(block) == "table" and block.HeaderText then
            blocks[id] = block
        end
    end

    local modules = ObjectiveTrackerFrame and
        (ObjectiveTrackerFrame.modules or ObjectiveTrackerFrame.MODULES)
    if type(modules) ~= "table" then
        return blocks, false
    end

    for _, module in pairs(modules) do
        if type(module) == "table" then
            local hasEnumerator = type(module.EnumerateActiveBlocks) == "function"
            local hasUsedBlocks = type(module.usedBlocks) == "table"
            local handled = false

            if hasEnumerator then
                -- Only a call that returned counts as read. An enumerator that
                -- errors tells us nothing about how many blocks there are, and
                -- reporting "read it, none there" would hide every button --
                -- exactly what the caller's guard exists to prevent.
                handled = pcall(module.EnumerateActiveBlocks, module, function(block)
                    if type(block) == "table" then
                        record(block.id, block)
                    end
                end)
            end

            -- Fall through to the older shape when the enumerator is absent OR
            -- raised. This was an elseif, so a module carrying both fields got
            -- no fallback at all.
            if not handled and hasUsedBlocks then
                for key, value in pairs(module.usedBlocks) do
                    if type(value) == "table" and value.HeaderText then
                        -- Flat: usedBlocks[questID] = block
                        record(key, value)
                    elseif type(value) == "table" then
                        -- Nested: usedBlocks[template][id] = block
                        for id, block in pairs(value) do
                            record(id, block)
                        end
                    end
                end
                handled = true
            end

            if handled then
                recognised = true
            elseif hasEnumerator or hasUsedBlocks then
                -- A block provider we could not read. A module carrying
                -- neither field is simply not one -- the tracker has many
                -- module types -- and must not count as a failure.
                failed = true
            end
        end
    end

    return blocks, recognised and not failed
end


function QTB:OnUpdate(elapsed)
    self.updateElapsed = self.updateElapsed + elapsed
    if self.updateElapsed < UPDATE_THROTTLE then return end
    self.updateElapsed = 0

    if InCombatLockdown() then return end

    -- No ObjectiveTrackerFrame in test environment or if hidden
    if not ObjectiveTrackerFrame then
        return
    end

    local questBlocks, recognised = self:CollectQuestBlocks()
    if not recognised then
        -- The tracker's shape is one this code does not know. Leaving the
        -- buttons where they are beats hiding every one of them: that is a
        -- positioning problem, not a reason to take working teleports off the
        -- screen. An empty table from a shape that IS recognised falls through
        -- to the loop below, which hides the buttons whose block is gone.
        return
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
                btn:SetScale(block:GetEffectiveScale() / UIParent:GetEffectiveScale())
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
    self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.eventFrame:RegisterEvent("SPELLS_CHANGED")
    self.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")

    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        -- Quest targets can change during combat or while this feature is
        -- disabled. Invalidate Lua state now; defer all button work.
        if InCombatLockdown() or not QTB.enabled then QTB:InvalidateCache(); return end
        if event == "SPELL_UPDATE_COOLDOWN" and not UpdateCooldownState() then return end

        QTB:InvalidateCache()

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
