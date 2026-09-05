-- Indexed, licensed retail reference destinations. Game-provided live targets
-- remain authoritative; a quest-giver reference is never relabeled as a turn-in.
local ADDON_NAME, QR = ...
local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local lower, find, format = string.lower, string.find, string.format
local insert, sort = table.insert, table.sort
local tonumber = tonumber
local huge = math.huge

QR.Catalog = {}
local Catalog = QR.Catalog
local CLASS_IDS = { WARRIOR=1, PALADIN=2, HUNTER=3, ROGUE=4, PRIEST=5, DEATHKNIGHT=6,
    SHAMAN=7, MAGE=8, WARLOCK=9, MONK=10, DRUID=11, DEMONHUNTER=12, EVOKER=13 }

local function finite(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value > -huge and value < huge
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local function contains(list, value)
    if not value or type(list) ~= "table" then return false end
    for _, entry in ipairs(list) do if entry == value then return true end end
    return false
end

local function validPoint(point)
    return type(point) == "table" and finite(point.mapID) and point.mapID > 0 and point.mapID % 1 == 0
        and finite(point.x) and finite(point.y) and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1
end

function Catalog:Reset()
    self._source, self._searchCache, self._accessCache = nil, nil, nil
    self._npcNames = nil
end

function Catalog:Initialize()
    local source = QR.DestinationCatalog
    if self._source == source and self.byCurrency then return end
    self._source = source
    self.byCurrency, self.byQuest, self.byNPC, self.byMap, self.searchRows = {}, {}, {}, {}, {}
    self._accessCache, self._searchCache = nil, nil
    if type(source) ~= "table" then return end
    for _, entry in ipairs(source.vendors or {}) do
        if validPoint(entry) and finite(entry.currencyID) and entry.currencyID > 0 then
            self.byCurrency[entry.currencyID] = self.byCurrency[entry.currencyID] or {}
            insert(self.byCurrency[entry.currencyID], entry)
        end
    end
    for _, category in ipairs({ "npcs", "quests" }) do
        for _, entry in ipairs(source[category] or {}) do
            if validPoint(entry) and type(entry.name) == "string" then
                local index = entry.questID and self.byQuest or self.byNPC
                local id = entry.questID or entry.npcID
                if finite(id) and id > 0 then
                    index[id] = index[id] or {}
                    insert(index[id], entry)
                    entry.searchName = lower(entry.name)
                    insert(self.searchRows, entry)
                    self.byMap[entry.mapID] = self.byMap[entry.mapID] or {}
                    insert(self.byMap[entry.mapID], entry)
                end
            end
        end
    end
end

local function hasProfession(skillLineID)
    if not (GetProfessions and GetProfessionInfo) then return false end
    local professions = { GetProfessions() }
    for _, index in pairs(professions) do
        local ok, _, _, _, _, _, _, skillID = pcall(GetProfessionInfo, index)
        if ok and skillID == skillLineID then return true end
    end
    return false
end

local function reputation(factionID)
    local major = _G.C_MajorFactions
    local data = major and safeCall(major.GetMajorFactionData, factionID)
    if type(data) == "table" and data.isUnlocked and finite(data.renownLevel) then return data.renownLevel end
    local api = _G.C_Reputation
    data = api and safeCall(api.GetFactionDataByID, factionID)
    if type(data) == "table" and finite(data.currentStanding) then return data.currentStanding end
end

function Catalog:CheckRequirements(req)
    if type(req) ~= "table" then return false end
    local faction = QR.PlayerInfo and QR.PlayerInfo:GetFaction()
    if req.r and ((req.r == 1 and faction ~= "Horde") or (req.r == 2 and faction ~= "Alliance")) then return false end
    if req.c then
        local class = QR.PlayerInfo and QR.PlayerInfo:GetClass()
        if not contains(req.c, CLASS_IDS[class]) then return false end
    end
    if req.races then
        if not _G.UnitRace then return false end
        local ok, _, _, raceID = pcall(_G.UnitRace, "player")
        if not ok or not contains(req.races, raceID) then return false end
    end
    if req.lvl and req.lvl > 0 then
        local level = safeCall(_G.UnitLevel, "player")
        if not finite(level) or level < req.lvl then return false end
    end
    for _, group in ipairs(req.questGroups or {}) do
        local complete = 0
        for _, questID in ipairs(group.ids or {}) do
            if C_QuestLog and safeCall(C_QuestLog.IsQuestFlaggedCompleted, questID) == true then complete = complete + 1 end
        end
        if not finite(group.required) or complete < group.required then return false end
    end
    if req.requireSkill and not hasProfession(req.requireSkill) then return false end
    if req.covenantID then
        local api = _G.C_Covenants
        if not api or safeCall(api.GetActiveCovenantID) ~= req.covenantID then return false end
    end
    local reputationRules = {}
    for _, rule in ipairs(req.reputationRules or {}) do insert(reputationRules, rule) end
    for _, key in ipairs({ "minReputation", "maxReputation", "minRenown" }) do
        if req[key] then insert(reputationRules, { kind = key, values = req[key] }) end
    end
    for _, constraint in ipairs(reputationRules) do
        local rule, key = constraint.values, constraint.kind
        if rule then
            if type(rule) ~= "table" or not finite(rule[1]) or not finite(rule[2]) then return false end
            local current = reputation(rule[1])
            if not finite(current) then return false end
            if key == "maxReputation" then
                if current >= rule[2] then return false end
            elseif current < rule[2] then return false end
        end
    end
    return true
end

function Catalog:IsAvailable(entry, includeCompleted)
    local now = GetTime()
    if not self._accessCache or now - (self._accessTime or 0) >= 1 then
        self._accessCache, self._accessTime = {}, now
    end
    local req = entry.requirements
    local ready = req and self._accessCache[req]
    if ready == nil then
        ready = self:CheckRequirements(req)
        if req then self._accessCache[req] = ready end
    end
    if not ready then return false end
    if entry.questID and not includeCompleted and not entry.repeatable and C_QuestLog
        and safeCall(C_QuestLog.IsQuestFlaggedCompleted, entry.questID) == true then return false end
    return true
end

function Catalog:GetDisplayName(entry)
    local name
    if entry.questID and C_QuestLog then name = safeCall(C_QuestLog.GetTitleForQuestID, entry.questID) end
    if not entry.questID and finite(entry.npcID) then
        self._npcNames = self._npcNames or {}
        local cached = self._npcNames[entry.npcID]
        if cached then return cached end
        local api = _G.C_TooltipInfo
        local info = api and safeCall(api.GetHyperlink, format("unit:Creature-0-0-0-0-%d-0000000000", entry.npcID))
        name = type(info) == "table" and info.lines and info.lines[1] and info.lines[1].leftText
        if not (issecretvalue and issecretvalue(name)) and type(name) == "string" and name ~= "" then
            self._npcNames[entry.npcID] = name
        else
            name = nil
        end
    end
    if type(name) == "string" and name ~= "" then
        entry.localizedSearchName = lower(name)
        return name
    end
    return entry.name
end

function Catalog:GetCurrencyLocations(currencyID)
    self:Initialize()
    local locations, found = {}, {}
    for _, entry in ipairs(self.byCurrency[currencyID] or {}) do
        if self:IsAvailable(entry, true) then
            local key = format("%d:%d:%.5f:%.5f", entry.npcID, entry.mapID, entry.x, entry.y)
            if not found[key] then
                found[key] = true
                insert(locations, { npcID = entry.npcID, name = self:GetDisplayName(entry), mapID = entry.mapID,
                    x = entry.x, y = entry.y, source = "catalogue", currencies = { [currencyID] = true },
                    reference = entry })
            end
        end
    end
    return locations
end

function Catalog:GetCurrencies()
    self:Initialize()
    local ids = {}
    for id in pairs(self.byCurrency) do insert(ids, id) end
    sort(ids)
    return ids
end

function Catalog:GetQuestLocations(questID, role, includeCompleted)
    self:Initialize()
    local results = {}
    for _, entry in ipairs(self.byQuest[questID] or {}) do
        if (not role or entry.role == role) and self:IsAvailable(entry, includeCompleted) then insert(results, entry) end
    end
    return results
end

--- Incremental substring filtering: extending a query searches previous matches,
-- not the full catalogue again. Empty queries use the current-map index only.
function Catalog:Search(query, mapID, limit)
    self:Initialize()
    query = lower(type(query) == "string" and query or "")
    local numericID = tonumber(query)
    limit = limit or 40
    local candidates, matches = self.searchRows, {}
    if query == "" then
        candidates = self.byMap[mapID] or {}
    elseif self._searchCache and not tonumber(self._searchCache.query) and #query >= #self._searchCache.query
        and query:sub(1, #self._searchCache.query) == self._searchCache.query then
        candidates = self._searchCache.matches
    end
    if query ~= "" and #query < 2 then return {}, false end
    local results, more = {}, false
    for _, entry in ipairs(candidates) do
        if query == "" or (numericID and (entry.questID or entry.npcID) == numericID)
            or find(entry.searchName, query, 1, true)
            or (entry.localizedSearchName and find(entry.localizedSearchName, query, 1, true)) then
            insert(matches, entry)
            if self:IsAvailable(entry) then
                if #results < limit then insert(results, entry) else more = true end
            end
        end
    end
    if query ~= "" then self._searchCache = { query = query, matches = matches } end
    return results, more
end

function Catalog:RouteToQuest(questID, role)
    questID = tonumber(questID)
    if not finite(questID) or questID <= 0 then return false end
    if role ~= "giver" and QR.WaypointIntegration then
        local wp = QR.WaypointIntegration:GetQuestWaypoint(questID)
        if wp then
            QR.POIRouting:RouteToMapPosition(wp.mapID, wp.x, wp.y)
            return true
        end
        QR:Print(QR.L["DESTINATION_UNAVAILABLE"])
        return false
    end
    local entries = self:GetQuestLocations(questID, "giver", true)
    local location = QR.ServiceRouter and QR.ServiceRouter:FindNearestLocation(entries)
    if location then
        QR.POIRouting:RouteToMapPosition(location.mapID, location.x, location.y)
        return true
    end
    QR:Print(QR.L["DESTINATION_UNAVAILABLE"])
    return false
end
