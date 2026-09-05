-- Player access checks and phase-state routing. Unknown API state never grants
-- access. The user can supply an explicit current-phase assumption when the
-- client cannot report it; search itself never changes the live game state.
local ADDON_NAME, QR = ...
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall
local table_sort, table_concat = table.sort, table.concat
local math_huge = math.huge

QR.TravelRequirements = { phaseOverrides = {} }
local TR = QR.TravelRequirements

local function Known(value)
    return not (issecretvalue and issecretvalue(value)) and value ~= nil
end

local function Number(value)
    return Known(value) and type(value) == "number" and value == value
        and value > -math_huge and value < math_huge
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and Known(value) then return value end
end

function TR:GetLiveMapArtID(mapID)
    -- Some revisions use distinct UiMapIDs (Uldum/Vale/Tirisfal). Standing on
    -- that alternate map is stronger evidence than querying the old map's art.
    local phases = QR.TravelPhaseGroups and QR.TravelPhaseGroups[mapID]
    local playerMap = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    if phases and phases[1] and phases[2] and phases[1].mapID ~= phases[2].mapID then
        for _, phase in ipairs(phases) do if playerMap == phase.mapID then return phase.artID end end
    end
    local art = Read(C_Map and C_Map.GetMapArtID, mapID)
    if Number(art) and art > 0 then
        if not phases then return art end
        for _, phase in ipairs(phases) do if phase.artID == art then return art end end
        -- A new client art variant is unknown to this catalogue. Do not label
        -- it a verified past/present phase or block an explicit assumption.
    end
end

function TR:GetMapArtID(mapID)
    return self:GetLiveMapArtID(mapID) or self.phaseOverrides[mapID]
end

--- Conditional replacements suppress older unconditional copies of the same
-- transport. Otherwise a locked portal could be bypassed through legacy data.
function TR:HasReplacement(fromMapID, toMapID, method)
    if method and method ~= "portal" then return false end
    local data = QR.TravelTransitions
    if not data then return false end
    if self.replacementData ~= data then
        self.replacementData, self.replacementPairs = data, {}
        for _, edge in ipairs(data.edges) do
            if edge.method == "portal" then
                local from, to = data.nodes[edge.from], data.nodes[edge.to]
                self.replacementPairs[from.mapID .. ":" .. to.mapID] = true
                if not edge.oneway then self.replacementPairs[to.mapID .. ":" .. from.mapID] = true end
            end
        end
    end
    return self.replacementPairs[fromMapID .. ":" .. toMapID] or false
end

function TR:GetPhaseOptions()
    local results = {}
    for mapID, phases in pairs(QR.TravelPhaseGroups or {}) do
        local info = Read(C_Map and C_Map.GetMapInfo, mapID)
        local live = self:GetLiveMapArtID(mapID)
        local current = live or self.phaseOverrides[mapID]
        results[#results + 1] = {
            mapID = mapID, name = info and info.name or tostring(mapID),
            currentArtID = current, known = current ~= nil, phases = phases,
            source = live and "client" or (current and "assumed" or "unknown"),
        }
    end
    table_sort(results, function(a, b) return a.mapID < b.mapID end)
    return results
end

function TR:SetPhaseOverride(mapID, artID)
    local phases = QR.TravelPhaseGroups and QR.TravelPhaseGroups[mapID]
    if not phases then return false end
    local valid = artID == nil
    for _, phase in ipairs(phases) do if phase.artID == artID then valid = true end end
    if not valid then return false end
    self.phaseOverrides[mapID] = artID
    if QR.PathCalculator then QR.PathCalculator.graphDirty = true end
    return true
end

local function Boolean(value)
    if type(value) == "boolean" then return value end
end

local function Quest(id)
    return Boolean(Read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, id))
end

local checkers = {}
local function CalendarStamp(date)
    if type(date) ~= "table" then return nil end
    local stamp = 0
    for _, field in ipairs({"year", "month", "monthDay", "hour", "minute"}) do
        if not Number(date[field]) then return nil end
        stamp = stamp * 100 + date[field]
    end
    return stamp
end

checkers.holiday = function(name)
    if not TR.calendarReady then return nil end
    local icons = QR.TravelHolidayIcons and QR.TravelHolidayIcons[name]
    if not icons then return nil end
    local today = Read(C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime)
    local month = Read(C_Calendar and C_Calendar.GetMonthInfo, 0)
    if type(today) ~= "table" or type(month) ~= "table" or not Number(today.monthDay)
        or today.month ~= month.month or today.year ~= month.year then return nil end
    local count = Read(C_Calendar and C_Calendar.GetNumDayEvents, 0, today.monthDay)
    if not Number(count) or count < 0 or count > 366 then return nil end
    for index = 1, count do
        local event = Read(C_Calendar.GetDayEvent, 0, today.monthDay, index)
        if type(event) ~= "table" then return nil end
        if event.calendarType == "HOLIDAY" then
            for _, texture in ipairs(icons) do
                if event.iconTexture == texture then
                    -- CalendarDayEvent exposes the full interval. A holiday
                    -- shown on today's calendar can still be closed this hour.
                    local now, first, last = CalendarStamp(today), CalendarStamp(event.startTime), CalendarStamp(event.endTime)
                    if not now or not first or not last then return nil end
                    if now >= first and now < last then return true end
                end
            end
        end
    end
    return false
end
checkers.flightDiscovery = function(points)
    if type(points) ~= "table" or not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return nil end
    local playerFaction = Read(UnitFactionGroup, "player")
    for _, point in ipairs(points) do
        local nodes = Read(C_TaxiMap.GetTaxiNodesForMap, point.mapID)
        if type(nodes) ~= "table" then return nil end
        local found = false
        for _, node in ipairs(nodes) do
            local position = node.position
            local faction = node.faction == 0 or (node.faction == 1 and playerFaction == "Horde")
                or (node.faction == 2 and playerFaction == "Alliance")
            local matches = point.taxiNodeID and node.nodeID == point.taxiNodeID
            if not point.taxiNodeID and position and Number(position.x) and Number(position.y)
                and Number(point.x) and Number(point.y) then
                matches = math.abs(position.x-point.x) <= 0.001 and math.abs(position.y-point.y) <= 0.001
            end
            if node.isUndiscovered == false and faction and matches then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return #points > 0
end
checkers.quest = Quest
checkers.questNotCompleted = function(id)
    local complete = Quest(id)
    if complete ~= nil then return not complete end
end
checkers.anyQuest = function(ids)
    if type(ids) ~= "table" then return nil end
    local unknown = false
    for _, id in ipairs(ids) do
        local result = Quest(id)
        if result == true then return true end
        if result == nil then unknown = true end
    end
    if not unknown then return false end
end
checkers.minLevel = function(level)
    local actual = Read(UnitLevel, "player")
    if Number(actual) and actual > 0 and Number(level) then return actual >= level end
end
checkers.maxLevel = function(level)
    local actual = Read(UnitLevel, "player")
    if Number(actual) and actual > 0 and Number(level) then return actual <= level end
end
checkers.faction = function(faction)
    local actual = Read(UnitFactionGroup, "player")
    if type(actual) == "string" then return actual == faction end
end
checkers.class = function(class)
    if not UnitClass then return nil end
    local ok, _, actual = pcall(UnitClass, "player")
    if ok and Known(actual) and type(actual) == "string" then return actual == class end
end
checkers.covenant = function(id)
    local actual = Read(C_Covenants and C_Covenants.GetActiveCovenantID)
    if Number(actual) then return actual == id end
end
checkers.reputation = function(required)
    if type(required) ~= "table" then return nil end
    local info = Read(C_Reputation and C_Reputation.GetFactionDataByID, required.factionID)
    if type(info) == "table" and Number(info.reaction) and Number(required.standing) then
        return info.reaction >= required.standing
    end
end
checkers.mapArtID = function(required, phases, ignorePhase)
    if ignorePhase then return true end
    if type(required) ~= "table" then return nil end
    local mapID, artID = required.mapID or required[1], required.artID or required[2]
    local current = phases and phases[mapID]
    if current == nil then current = TR:GetMapArtID(mapID) end
    if Number(current) and Number(artID) then return current == artID end
end
checkers.anyOf = function(requirements, phases, ignorePhase)
    if type(requirements) ~= "table" then return nil end
    local unknown = false
    for kind, value in pairs(requirements) do
        local result
        if type(kind) == "number" then
            result = TR:Check(value, phases, ignorePhase)
        elseif checkers[kind] then
            result = checkers[kind](value, phases, ignorePhase)
        end
        if result == true then return true end
        if result == nil then unknown = true end
    end
    if not unknown then return false end
end

--- true=available, false=known locked, nil=unknown. ignorePhase is only for
-- graph construction: phase conditions still apply during stateful search.
function TR:Check(requirements, phases, ignorePhase)
    if requirements == nil then return true end
    if type(requirements) ~= "table" then return nil end
    local unknown = false
    for kind, value in pairs(requirements) do
        local checker = checkers[kind]
        local ok, result = false, nil
        if checker then ok, result = pcall(checker, value, phases, ignorePhase) end
        if ok and result == false then return false end
        if not ok or result == nil then unknown = true end
    end
    if not unknown then return true end
end

--- Maps which exist in only one documented phase (including alternate UiMapIDs)
-- inherit that requirement even for generic dungeon/player/destination nodes.
function TR:GetNodePhase(mapID)
    if not mapID then return nil end
    local data, groups = QR.TravelTransitions, QR.TravelPhaseGroups
    if self.nodePhaseData ~= data or self.nodePhaseGroups ~= groups then
        self.nodePhaseData, self.nodePhaseGroups, self.nodePhases = data, groups, {}
        local function add(id, control, art)
            local prior = self.nodePhases[id]
            if prior == false then return end
            if prior and (prior.mapID ~= control or prior.artID ~= art) then
                self.nodePhases[id] = false -- This UiMapID can represent both phases.
            else
                self.nodePhases[id] = { mapID = control, artID = art }
            end
        end
        for control, phases in pairs(groups or {}) do
            for _, phase in ipairs(phases) do add(phase.mapID, control, phase.artID) end
        end
        for _, node in pairs(data and data.nodes or {}) do
            if node.mapArtID then add(node.mapID, node.phaseCheckMapID or node.mapID, node.mapArtID) end
        end
    end
    return self.nodePhases[mapID] or nil
end

function TR:CanTraverseZoneMaps(fromMapID, toMapID)
    local from, to = self:GetNodePhase(fromMapID), self:GetNodePhase(toMapID)
    return not (from and to and from.mapID == to.mapID and from.artID ~= to.artID)
end

function TR:FindPath(graph, start, goal)
    -- First find the unrestricted lower bound. If that exact route satisfies
    -- every requirement, it is already optimal; disconnected destinations need
    -- no phase-state expansion at all.
    local staticChecks = {}
    local function staticAllowed(requirements)
        if requirements == nil then return true end
        if staticChecks[requirements] == nil then staticChecks[requirements] = self:Check(requirements, nil, true) == true end
        return staticChecks[requirements]
    end
    local function withoutPhase(from, to, edge)
        return staticAllowed(graph.nodes[from].requirements) and staticAllowed(graph.nodes[to].requirements)
            and staticAllowed(edge.data and edge.data.requirements)
    end
    local optimisticPath, optimisticCost, optimisticEdges = graph:FindShortestPath(start, goal, withoutPhase)
    if not optimisticPath then return nil end
    local phaseMaps = {}
    local function collect(requirements)
        if type(requirements) ~= "table" then return end
        if type(requirements.mapArtID) == "table" then
            local mapID = requirements.mapArtID.mapID or requirements.mapArtID[1]
            if Number(mapID) then phaseMaps[mapID] = true end
        end
        if type(requirements.anyOf) == "table" then
            for kind, value in pairs(requirements.anyOf) do
                collect(type(kind) == "number" and value or { [kind] = value })
            end
        end
    end
    for _, node in pairs(graph.nodes) do
        local implicit = self:GetNodePhase(node.mapID)
        if implicit then phaseMaps[implicit.mapID] = true end
        if node.mapArtID then phaseMaps[node.phaseCheckMapID or node.mapID] = true end
        collect(node.requirements)
    end
    for _, outgoing in pairs(graph.edges) do
        for _, selected in pairs(outgoing) do
            for _, edge in ipairs(selected.alternatives or { selected }) do
                collect(edge.data and edge.data.requirements)
                if edge.data and edge.data.phaseMapID then phaseMaps[edge.data.phaseMapID] = true end
            end
        end
    end
    local keys, initial = {}, {}
    for mapID in pairs(phaseMaps) do
        keys[#keys + 1] = mapID
        initial[mapID] = self:GetMapArtID(mapID) or false
    end
    table_sort(keys)
    local policy = { initialState = initial }
    function policy:Signature(state)
        local parts = {}
        for _, mapID in ipairs(keys) do parts[#parts + 1] = tostring(state[mapID]) end
        return table_concat(parts, ",")
    end
    -- Requirements/API answers are stable for one synchronous search. Reuse
    -- their result per phase state to avoid repeated quest calls on dense maps.
    local checks = {}
    local function check(requirements, state)
        if requirements == nil then return true end
        local byState = checks[state]
        if not byState then byState = {}; checks[state] = byState end
        if byState[requirements] == nil then byState[requirements] = TR:Check(requirements, state) == true end
        return byState[requirements]
    end
    local function allowed(node, state)
        if not check(node.requirements, state) then return false end
        local implicit = TR:GetNodePhase(node.mapID)
        if implicit and state[implicit.mapID] ~= implicit.artID then return false end
        if node.mapArtID then
            return state[node.phaseCheckMapID or node.mapID] == node.mapArtID
        end
        return true
    end
    function policy:Advance(from, to, edge, state)
        if not allowed(graph.nodes[from], state) then return nil end
        local data = edge.data or {}
        if not check(data.requirements, state) then return nil end
        local nextState = state
        if edge.edgeType == "phaseswitch" then
            local target = graph.nodes[to]
            local mapID = data.phaseMapID or target.phaseCheckMapID or target.mapID
            local artID = data.phaseArtID or target.mapArtID
            if not Number(mapID) or not Number(artID) then return nil end
            nextState = {}
            for key, value in pairs(state) do nextState[key] = value end
            nextState[mapID] = artID
        end
        if allowed(graph.nodes[to], nextState) then return nextState end
    end
    local optimisticState = allowed(graph.nodes[start], initial) and initial or nil
    if not optimisticState then return nil end
    for index, edge in ipairs(optimisticEdges) do
        optimisticState = policy:Advance(optimisticPath[index], optimisticPath[index+1], edge, optimisticState)
        if not optimisticState then break end
    end
    if optimisticState then return optimisticPath, optimisticCost, optimisticEdges end
    return graph:FindShortestPathWithState(start, goal, policy)
end

function TR:Initialize()
    if self.frame then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
        "CALENDAR_UPDATE_EVENT_LIST" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "CALENDAR_UPDATE_EVENT_LIST" then self.calendarReady = true end
        -- Access requirements are evaluated live at search time; objective and
        -- calendar updates do not rebuild the entire retained transport graph.
        if (event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD") and QR.PathCalculator then
            QR.PathCalculator.graphDirty = true
        end
    end)
    self.frame = frame
    -- Requests calendar data; does not open Blizzard's calendar UI.
    Read(C_Calendar and C_Calendar.OpenCalendar)
end
