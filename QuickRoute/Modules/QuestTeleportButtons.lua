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
local PENDING_GRACE = 2     -- retain an inactive icon across a brief data gap

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

--- Drop the cooldown answers remembered for one refresh batch.
-- Called from every path that leaves a batch, including the ones that abandon
-- it half way: a batch left open would keep answering later callers -- the
-- panels, the filters, the readiness check -- from memory, and cooldowns are
-- live state.
local function EndCooldownBatch(generation)
    -- A refresh that has been superseded still gets one more frame, and it must
    -- not close the batch its successor just opened. Callers inside a refresh
    -- pass their generation; callers that mean "close whatever is open" -- the
    -- readiness check, CancelRefresh -- pass nothing.
    if generation and generation ~= QTB._refreshGeneration then return end
    if QR.CooldownTracker and QR.CooldownTracker.EndBatch then
        QR.CooldownTracker:EndBatch()
    end
end

-- The one event after which a cached route may be wrong in a way no field of
-- the cache key can show: a teleport coming off cooldown can beat the one a
-- cached entry chose, and the read path only re-checks the cooldown of the
-- teleport already cached. SPELL_UPDATE_COOLDOWN reaches this table only once
-- UpdateCooldownState has confirmed a readiness really moved.
--
-- Every other event this module listens to is deliberately absent.
--
-- SUPER_TRACKING_CHANGED changes which quest carries the arrow, not what any
-- quest's route is: WaypointIntegration:GetQuestWaypoint takes an explicit
-- questID and never consults C_SuperTrack. Measured with 25 tracked quests, a
-- firing re-computed all 25 routes and none of the 25 values differed, at 62 ms
-- for a character with a full teleport collection. It fires on every quest
-- turn-in and accept, whenever an objective auto-advances the arrow, on any
-- click in the tracker or on the map, and whenever another addon calls
-- C_SuperTrack.SetSuperTrackedQuestID. WaypointIntegration says the same of its
-- own cache one file over: "per-questID entries are already keyed correctly".
--
-- QUEST_WATCH_LIST_CHANGED does change the watched set, but only for the quest
-- added or removed. Every refresh ends in PruneQuestCache(watched), which drops
-- exactly the entries no longer watched, and a newly watched quest has no entry
-- to be stale. Wiping the other 24 measured 50 ms and changed nothing.
--
-- SPELLS_CHANGED and BAG_UPDATE_DELAYED: a teleport appearing or disappearing
-- reaches the graph through PlayerInventory's rescan, which builds a new graph,
-- and every cached entry records the graph it was computed against -- so those
-- invalidate themselves.
local INVALIDATING_EVENTS = {
    SPELL_UPDATE_COOLDOWN = true,
}

-- A small stable bucket avoids sub-pixel movement invalidating all quest
-- routes, while approaching an objective can replace a teleport with walking.
--
-- The divisor decides how far the player walks before every tracked quest is
-- routed again, and each of those is a Dijkstra run over the whole graph. At
-- 1000 a bucket was a few yards across, so ordinary walking recomputed
-- everything several times a second -- both here and through the movement
-- probe in OnMovementUpdate, which compares the same bucket.
--
-- Of the two decisions the bucket exists for, the zone change is carried by the
-- mapID in the key on its own. The other -- the objective is now close enough
-- to walk to -- is not answered by any divisor: CACHE_TTL already expires every
-- entry within 30 seconds regardless of where the player stands, so that is
-- what bounds how stale this choice can get, and it did so at 1000 too.
local POSITION_BUCKETS = 20

--- Where a quest points, at the same resolution as the player's own position.
-- Keyed on the map alone this missed an objective advancing to another part of
-- the same zone -- a destination is wired into the graph by its coordinates, so
-- two points in one zone attach to different nearby nodes and can pick a
-- different first teleport. Keyed on exact coordinates it would recompute
-- constantly instead: C_QuestLog.GetNextWaypoint walks a multi-step quest along
-- its path, so the coordinates drift while the destination does not. The same
-- grid that decides the player has moved decides the objective has.
local function DestinationBucket(waypoint)
    if not waypoint or not waypoint.mapID then return nil end
    local x, y = waypoint.x, waypoint.y
    if type(x) ~= "number" or type(y) ~= "number" then return waypoint.mapID .. ":?" end
    return string_format("%d:%d:%d", waypoint.mapID,
        math_floor(x * POSITION_BUCKETS), math_floor(y * POSITION_BUCKETS))
end

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
        return string_format("%d:%d:%d", mapID,
            math_floor(x * POSITION_BUCKETS), math_floor(y * POSITION_BUCKETS))
    end)
    return ok and bucket or nil
end

-------------------------------------------------------------------------------
-- Route-based Teleport Selection
-------------------------------------------------------------------------------

--- Offer only an immediately usable first step of the computed quest route.
-- A teleport on the same continent is not necessarily faster than walking,
-- and a teleport later in the route must not skip its preceding travel.
--- Where this quest currently points. Resolved through WaypointIntegration's
-- own 30-second coordinate cache, so asking on every read is cheap.
local function ResolveQuestWaypoint(questID)
    if not QR.WaypointIntegration then return nil end
    local button = QTB.activeButtons[questID]
    local retry = button and button._pendingSince ~= nil
    return QR.WaypointIntegration:GetQuestWaypoint(questID, retry)
end

local function FindBestTeleportForQuest(questID, waypoint)
    if not (QR.WaypointIntegration and QR.PathCalculator and QR.PlayerInventory) then
        return nil, nil, true
    end
    if not waypoint then return nil, nil, true end

    local route = QR.PathCalculator:CalculatePath(waypoint.mapID, waypoint.x, waypoint.y, waypoint.title)
    if not route then return nil, nil, true end
    local step = route and route.steps and route.steps[1]
    if not step or step.type ~= "teleport" or not step.teleportID then
        return nil, nil, nil, true
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
    if not position then QTB.questCache[questID] = nil; return nil, nil, nil, true end
    local cached = QTB.questCache[questID]
    local calculator = QR.PathCalculator

    -- Where the quest points is part of the key. Completing an objective can
    -- advance a quest to one on another continent without the player moving a
    -- step, and every other field of this key would still match -- the cached
    -- entry would go on offering a teleport to where the quest used to be.
    --
    -- The map, not the coordinates: GetNextWaypoint walks a multi-step quest
    -- along its path, so x and y drift while the destination stays put, and
    -- comparing them would recompute a route that cannot have changed. Which
    -- zone the player is being sent to is what decides the first step.
    local waypoint = ResolveQuestWaypoint(questID)
    local destination = DestinationBucket(waypoint)

    if cached and not (QTB.flightChoices and QTB.flightChoices[questID])
        and cached.position == position and cached.graph == (calculator and calculator.graph)
        and cached.destination == destination
        and not (calculator and calculator.graphDirty) and (now - cached.time) < CACHE_TTL then
        local cooldown = cached.teleportID and QR.CooldownTracker
            and QR.CooldownTracker:GetCooldown(cached.teleportID, cached.sourceType)
        if not cached.teleportID or (cooldown and cooldown.ready) then
            return cached.teleportID, cached.sourceType, cached.data, nil, cached.direct
        end
    end

    local generation = QTB._refreshGeneration
    local teleportID, entry, incomplete, direct = FindBestTeleportForQuest(questID, waypoint)
    -- Reentrant invalidation cancels this result as well as its UI callback.
    -- Never refill the cache with a route from the cancelled calculation.
    if generation ~= QTB._refreshGeneration then return nil, nil, nil, true end
    if incomplete then
        -- An API/route gap is not a confirmed walking result. In particular,
        -- do not suppress a pending button's short retry with a 30s negative.
        QTB.questCache[questID] = nil
        return nil, nil, nil, true
    end
    if teleportID and entry then
        QTB.questCache[questID] = {
            teleportID = teleportID,
            sourceType = entry.sourceType,
            data = entry.data,
            time = now,
            position = position,
            destination = destination,
            graph = QR.PathCalculator and QR.PathCalculator.graph,
        }
        return teleportID, entry.sourceType, entry.data
    end

    QTB.questCache[questID] = { time = now, position = position, destination = destination,
        graph = QR.PathCalculator and QR.PathCalculator.graph, direct = direct }
    return nil, nil, nil, nil, direct
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
    EndCooldownBatch()
end

-- TTL must release entries, not just stop reusing them. Lower-priority quests
-- may never be queried again after the eight-button pool fills, and each entry
-- can otherwise retain an entire obsolete travel graph.
local function PruneQuestCache(watched)
    local now = GetTime()
    local graph = QR.PathCalculator and QR.PathCalculator.graph
    for questID, cached in pairs(QTB.questCache) do
        if (watched and not watched[questID]) or type(cached.time) ~= "number"
            or now - cached.time >= CACHE_TTL or cached.graph ~= graph then
            QTB.questCache[questID] = nil
        end
    end
end

-- SPELL_UPDATE_COOLDOWN also fires for unrelated abilities and global
-- cooldown updates. Replan quests only when a teleport's readiness changes.
local function UpdateCooldownState()
    -- This is the check that decides whether a cooldown moved, so it has to see
    -- the client and not a batch's remembered answers -- CooldownTracker's own
    -- comment says as much. A refresh batch spans a frame per tracked quest, so
    -- one can still be open when SPELL_UPDATE_COOLDOWN arrives; reading its
    -- memo here would report "nothing changed" for the very teleport the player
    -- just used, and the rest of the batch would hand out a button for it.
    EndCooldownBatch()
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

-- Clear the action without changing the icon or its position. A pending
-- recommendation must never leave the previous teleport/equipment clickable.
local function ClearButtonAction(btn)
    btn:SetAttribute("type", nil)
    btn:SetAttribute("macrotext", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("toy", nil)
    btn:SetAttribute("item", nil)
    btn:SetAttribute("house-neighborhood-guid", nil)
    btn:SetAttribute("house-guid", nil)
    btn:SetAttribute("house-plot-id", nil)
    btn:SetScript("PreClick", nil)
    btn:SetScript("PostClick", nil)
    btn.teleportID, btn.sourceType, btn.equipSlot = nil, nil, nil
end

--- Release a button back to the pool
-- @param btn Button
local function ReleaseButton(btn)
    if not btn then return end
    if InCombatLockdown() then return end

    btn:Hide()
    btn:ClearAllPoints()
    ClearButtonAction(btn)
    btn._pendingSince = nil
    btn._pendingTeleportID, btn._pendingSourceType = nil, nil
    btn.inUse = false
    btn.questID = nil
    -- The next quest to use this button must be positioned, not assumed to be
    -- where the last one was.
    btn._lastX, btn._lastY, btn._lastScale = nil, nil, nil
    btn.tooltipText = nil
    btn.tooltipSubtext = nil
    if btn.icon then
        btn.icon:SetTexture(nil)
    end
end

local function KeepPendingButton(btn)
    local id, source = btn._pendingTeleportID or btn.teleportID, btn._pendingSourceType or btn.sourceType
    local inventory = QR.PlayerInventory and QR.PlayerInventory:GetAllTeleports()
    local entry = inventory and inventory[id]
    local cooldown = id and QR.CooldownTracker and QR.CooldownTracker:GetCooldown(id, source)
    if not entry or not entry.data or entry.sourceType ~= source
        or (issecretvalue and issecretvalue(entry.isUsable)) or entry.isUsable == false
        or not cooldown or not cooldown.ready then return false end
    local now = GetTime()
    if not btn._pendingSince then
        btn._pendingSince = now
        btn._pendingTeleportID, btn._pendingSourceType = id, source
        ClearButtonAction(btn)
        btn.tooltipText = QR.L["CALCULATING"]
        btn.tooltipSubtext = nil
    end
    if now - btn._pendingSince >= PENDING_GRACE then return false end
    -- The deadline belongs to the first failed sample and is never extended.
    -- The lightweight movement probe retries even if the player stops moving.
    local retryAt = now + MOVEMENT_CHECK_INTERVAL
    if not QTB._pendingRefreshAt or retryAt < QTB._pendingRefreshAt then QTB._pendingRefreshAt = retryAt end
    return true
end

--- Release all active buttons
function QTB:ReleaseAllButtons()
    self:CancelRefresh()
    wipe(self.questCache)
    self._lastRefreshGraph, self._lastRefreshPosition = nil, nil
    self._pendingRefreshAt = nil
    if self.flightChoices then wipe(self.flightChoices) end
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
        -- A retained quest button may now cast a different teleport whose
        -- texture is not cached yet. Never leave the previous action's icon.
        btn.icon:SetTexture(iconID or 134400)
    end

    -- Set tooltip
    local name = data and data.name or tostring(teleportID)
    local dest = data and data.destination or ""
    btn.tooltipText = name
    btn.tooltipSubtext = dest ~= "" and dest or nil
    btn.teleportID, btn.sourceType = teleportID, sourceType
    btn._pendingSince = nil
    btn._pendingTeleportID, btn._pendingSourceType = nil, nil

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

    UpdateCooldownState()

    local trackedQuests = GetTrackedQuestIDs()
    local watched = {}
    for _, questID in ipairs(trackedQuests) do watched[questID] = true end
    local flying = false
    if _G.IsFlying then
        local ok, value = pcall(_G.IsFlying)
        flying = ok and not (issecretvalue and issecretvalue(value)) and value == true
    end
    self.flightChoices = self.flightChoices or {}
    for questID in pairs(self.flightChoices) do
        if not flying or not watched[questID] then self.flightChoices[questID] = nil end
    end
    -- Keep surviving buttons in place while the asynchronous route batch runs.
    -- Releasing the entire pool here made every movement refresh visibly blink.
    for questID, btn in pairs(self.activeButtons) do
        if not watched[questID] then
            ReleaseButton(btn)
            self.activeButtons[questID] = nil
        end
    end
    PruneQuestCache(watched)
    if #trackedQuests == 0 then self:ReleaseAllButtons(); return end
    if self.movementFrame then self.movementFrame:Show() end
    self._lastRefreshPosition = GetPositionBucket()
    self._lastRefreshGraph = QR.PathCalculator and QR.PathCalculator.graph

    local generation = self._refreshGeneration
    local index, activeCount, retained = 1, 0, {}
    self._pendingRefreshAt = nil
    self._refreshRunning = true
    -- Every route in this batch prices every teleport against its cooldown, and
    -- the batch runs one route per frame, so the same question reaches the
    -- client once per tracked quest. One answer serves the batch.
    if QR.CooldownTracker and QR.CooldownTracker.BeginBatch then
        QR.CooldownTracker:BeginBatch()
    end
    local function IsCurrent()
        return generation == QTB._refreshGeneration and QTB.initialized and QTB.enabled and not InCombatLockdown()
    end
    local function RefreshOne()
        if not IsCurrent() then EndCooldownBatch(generation); return end
        local questID = trackedQuests[index]
        if not questID or activeCount >= POOL_SIZE then EndCooldownBatch(generation); return end
        -- A route calculation can take several milliseconds. Never calculate
        -- every watched quest in the same quest-log/event frame.
        local ok, teleportID, sourceType, data, incomplete, direct = pcall(GetCachedTeleportForQuest, questID)
        if not IsCurrent() then EndCooldownBatch(generation); return end
        if not ok then
            QR:Debug("Quest button route unavailable: " .. tostring(teleportID))
            teleportID = nil
            incomplete = true
        end
        local previous = QTB.flightChoices[questID]
        if flying and direct and (previous or QTB.activeButtons[questID]) then
            -- Instantaneous flight speed can cross the direct/teleport tie on
            -- adjacent samples. Retire a slower teleport immediately, but ask
            -- for a fresh confirmation before showing it again.
            QTB.flightChoices[questID] = {}
        elseif flying and teleportID and sourceType and previous then
            local now = GetTime()
            if previous.id ~= teleportID or previous.source ~= sourceType then
                previous.id, previous.source, previous.since = teleportID, sourceType, now
            end
            if now - previous.since < MOVEMENT_CHECK_INTERVAL then
                QTB.questCache[questID] = nil -- confirmation must calculate a fresh route
                local retryAt = previous.since + MOVEMENT_CHECK_INTERVAL
                if not QTB._pendingRefreshAt or retryAt < QTB._pendingRefreshAt then QTB._pendingRefreshAt = retryAt end
                teleportID = nil
            else
                QTB.flightChoices[questID] = nil
            end
        elseif incomplete and previous then
            QTB.flightChoices[questID] = {}
        elseif not incomplete then
            QTB.flightChoices[questID] = nil
        end
        if teleportID and sourceType then
            local btn = QTB.activeButtons[questID] or GetFreeButton()
            if not btn then
                -- A new higher-priority quest may replace a full pool's last
                -- unprocessed entry. Already-confirmed quests keep their slot.
                for candidate = #trackedQuests, index + 1, -1 do
                    local oldID = trackedQuests[candidate]
                    local old = QTB.activeButtons[oldID]
                    if old and not retained[oldID] then
                        ReleaseButton(old)
                        QTB.activeButtons[oldID] = nil
                        btn = GetFreeButton()
                        break
                    end
                end
            end
            if btn then
                if ConfigureButton(btn, teleportID, sourceType, data) then
                    btn.questID = questID
                    QTB.activeButtons[questID] = btn
                    retained[questID] = true
                    activeCount = activeCount + 1
                    if QTB.updateFrame then QTB.updateFrame:Show() end
                else
                    ReleaseButton(btn)
                    QTB.activeButtons[questID] = nil
                end
            end
        elseif incomplete and QTB.activeButtons[questID] and KeepPendingButton(QTB.activeButtons[questID]) then
            retained[questID] = true
            activeCount = activeCount + 1
        elseif QTB.activeButtons[questID] then
            ReleaseButton(QTB.activeButtons[questID])
            QTB.activeButtons[questID] = nil
        end
        index = index + 1
        if index <= #trackedQuests and activeCount < POOL_SIZE then
            C_Timer.After(0, RefreshOne)
        else
            PruneQuestCache(watched) -- A route in this batch may have rebuilt the graph.
            for oldID, btn in pairs(QTB.activeButtons) do
                if not retained[oldID] then
                    ReleaseButton(btn)
                    QTB.activeButtons[oldID] = nil
                end
            end
            if not next(QTB.activeButtons) and QTB.updateFrame then QTB.updateFrame:Hide() end
            QTB._refreshRunning = false
            EndCooldownBatch(generation)
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
    PruneQuestCache()
    local position = GetPositionBucket()
    local calculator = QR.PathCalculator
    if (self._pendingRefreshAt and GetTime() >= self._pendingRefreshAt)
        or position ~= self._lastRefreshPosition or (calculator and (calculator.graph ~= self._lastRefreshGraph or calculator.graphDirty)) then
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
-- Reused across calls. This runs five times a second for as long as a quest
-- teleport button is on screen, and two fresh tables plus two closures per call
-- measured 2.9 KiB each time -- around 50 MiB an hour of standing still. The
-- returned table is only read before the next call, which is the same contract
-- CooldownTracker's result tables carry.
local collectedBlocks = {}
local collectedQuestTagged = {}

function QTB:CollectQuestBlocks()
    local blocks = collectedBlocks
    local questTagged = collectedQuestTagged
    wipe(blocks)
    wipe(questTagged)
    local recognised = false
    local failed = false

    local record = self._recordQuestBlock
    if not record then
        record = function(id, block, isQuestModule)
            if type(id) == "number" and not (issecretvalue and issecretvalue(id))
                and type(block) == "table" and block.HeaderText
                and (isQuestModule or not questTagged[id]) then
                blocks[id] = block
                questTagged[id] = isQuestModule
            end
        end
        self._recordQuestBlock = record
    end

    local modules = ObjectiveTrackerFrame and
        (ObjectiveTrackerFrame.modules or ObjectiveTrackerFrame.MODULES)
    if type(modules) ~= "table" then
        return blocks, false
    end

    for _, module in pairs(modules) do
        if type(module) == "table" then
            local tagOK, tag = true, module.tag
            if type(module.GetTag) == "function" then
                tagOK, tag = pcall(module.GetTag, module)
            end
            if not tagOK or (issecretvalue and issecretvalue(tag)) then
                -- An unreadable identity cannot prove that a quest disappeared.
                failed = true
            elseif tag == nil or tag == "" or tag == "quest" then
                -- Native ordinary/campaign quests share this tag. Achievement and
                -- recipe modules use independent numeric IDs, so their untagged
                -- blocks must never replace a tagged quest with the same ID.
                -- Keep untagged providers for older and custom tracker layouts.
                local isQuestModule = tag == "quest"
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
                            record(block.id, block, isQuestModule)
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
                            record(key, value, isQuestModule)
                        elseif type(value) == "table" then
                            -- Nested: usedBlocks[template][id] = block
                            for id, block in pairs(value) do
                                record(id, block, isQuestModule)
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
    end

    return blocks, recognised and not failed
end


function QTB:OnUpdate(elapsed)
    self.updateElapsed = self.updateElapsed + elapsed
    if self.updateElapsed < UPDATE_THROTTLE then return end
    self.updateElapsed = 0

    if InCombatLockdown() then return end

    -- Nothing to position. The frame is hidden when the last button goes, so
    -- this is belt and braces -- but walking the tracker's whole module tree
    -- five times a second to place no buttons is the one case worth spelling
    -- out.
    if not next(self.activeButtons) then return end

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
                local anchorX = left + BUTTON_OFFSET_X
                local scale = block:GetEffectiveScale() / UIParent:GetEffectiveScale()
                -- Re-anchoring invalidates the frame's layout, so it is done
                -- only when the block actually moved. The tracker is static
                -- most of the time, and this runs five times a second.
                -- SecureButtons' overlay loop guards the same way.
                if btn._lastX ~= anchorX or btn._lastY ~= centerY or btn._lastScale ~= scale then
                    btn:SetScale(scale)
                    btn:ClearAllPoints()
                    btn:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", anchorX, centerY)
                    btn._lastX, btn._lastY, btn._lastScale = anchorX, centerY, scale
                end
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
        if InCombatLockdown() then
            -- Nothing is read from the cache during a fight and no button work
            -- runs, so there is nothing to keep fresh; emptying it here would
            -- only move a full recompute of every tracked quest to the moment
            -- the fight ends, on top of the inventory scan and graph rebuild
            -- that land there. A quest untracked mid-fight is dropped by the
            -- PruneQuestCache at the end of the first refresh afterwards, and a
            -- newly tracked one has no entry to be stale.
            QTB:CancelRefresh()
            return
        end
        if not QTB.enabled then QTB:InvalidateCache(); return end
        if event == "SPELL_UPDATE_COOLDOWN" and not UpdateCooldownState() then return end

        -- Only a confirmed cooldown change empties the cache; see
        -- INVALIDATING_EVENTS above for why nothing else has to.
        -- Everything a cached entry depends on -- the player's
        -- position bucket, the graph it was computed against, whether the graph
        -- is dirty, the entry's age, and the teleport's cooldown -- is checked
        -- on every read, so a wholesale wipe here adds no freshness. It did
        -- take all of it away: QUEST_LOG_UPDATE fires about once a second while
        -- the player moves, and every firing then re-routed each tracked quest
        -- from scratch, which is one Dijkstra run over the whole graph per
        -- quest. Any addon that makes the client re-check quests, spells or
        -- bags paid the same bill, which is why the cost grew with the number
        -- of addons installed rather than with anything QuickRoute was asked to
        -- do. See https://github.com/CybotTM/wow-quickroute/issues/66.
        --
        -- The in-flight refresh is still cancelled on every event: its results
        -- describe the state before whatever just happened.
        if INVALIDATING_EVENTS[event] then
            QTB:InvalidateCache()
        else
            QTB:CancelRefresh()
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
