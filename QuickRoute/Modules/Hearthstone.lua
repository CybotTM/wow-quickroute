-- Prefer observed character bindings; resolve existing bindings against known
-- inns when their localized name identifies exactly one catalogue location.
-- Unknown or ambiguous names still require an observed bind or hearth arrival.
local ADDON_NAME, QR = ...
local pairs, type, pcall = pairs, type, pcall
local math_abs = math.abs

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

QR.Hearthstone = {}
local Hearthstone = QR.Hearthstone

local function PlayerGUID()
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and Public(guid) and type(guid) == "string" and guid ~= "" then return guid end
end

local function BindName()
    if not GetBindLocation then return nil end
    local ok, name = pcall(GetBindLocation)
    if ok and Public(name) and type(name) == "string" and name ~= "" then return name end
end

local function Position()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local ok, mapID, x, y = pcall(function()
        local map = C_Map.GetBestMapForUnit("player")
        if not Number(map) or map <= 0 then return end
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        if not pos then return end
        local px, py = pos:GetXY()
        if not Number(px) or not Number(py) then return end
        return QR.PathCalculator:ResolveMapPosition(map, px, py)
    end)
    if ok and mapID then return { mapID = mapID, x = x, y = y } end
end

local function AtBindArea(name)
    -- Some binds use the city/zone name while the minimap names the inn.
    -- Only compare names after the successful cast and observed displacement;
    -- none of these names is used to manufacture landing coordinates.
    for _, getter in pairs({ _G.GetMinimapZoneText, _G.GetSubZoneText,
        _G.GetZoneText, _G.GetRealZoneText }) do
        local ok, area = pcall(getter)
        if ok and Public(area) and area == name then return true end
    end
    return false
end

local function StorePoint(guid, name, point, source)
    if not QR.db then return false end
    if type(QR.db.hearthstoneBinds) ~= "table" then QR.db.hearthstoneBinds = {} end
    QR.db.hearthstoneBinds[guid] = {
        mapID = point.mapID, x = point.x, y = point.y, bindName = name, source = source,
    }
    QR.PathCalculator.graphDirty = true
    return true
end

--- Localize the small inn catalogue once, including collision-only entries.
-- Never publish a partial index: an unavailable second name could make an
-- ambiguous binding look unique. Failed builds retry on entering the world.
function Hearthstone:BuildInnIndex()
    local index, complete = {}, true
    -- API hooks may reenter GetDestination while names are being localized.
    -- Publish only the completed index, never a temporarily unique candidate.
    self.innIndex = {}
    if type(QR.HearthstoneLocations) ~= "table" or not (C_Map and C_Map.GetAreaInfo) then
        self.innIndexIncomplete = true
        return
    end
    for _, inn in pairs(QR.HearthstoneLocations) do
        if type(inn) ~= "table" or not Number(inn.areaID) or inn.areaID <= 0
            or inn.areaID % 1 ~= 0 then
            complete = false
        else
            local ok, name = pcall(C_Map.GetAreaInfo, inn.areaID)
            if not ok or not Public(name) or type(name) ~= "string" or name == "" then
                complete = false
            else
                local mapID, x, y = QR.PathCalculator:ResolveMapPosition(inn.mapID, inn.x, inn.y)
                local previous = index[name]
                if inn.ambiguous or not mapID or previous == false then
                    index[name] = false
                elseif previous and (previous.mapID ~= mapID or previous.x ~= x or previous.y ~= y) then
                    index[name] = false
                else
                    index[name] = { mapID = mapID, x = x, y = y }
                end
            end
        end
    end
    self.innIndexIncomplete = not complete
    if complete then
        self.innIndex = index
        -- A tooltip can discover an inn after the planner built its graph.
        -- Repricing old edges alone would not add the new hearth destination.
        QR.PathCalculator.graphDirty = true
    end
end

function Hearthstone:GetDestination()
    local guid, name = PlayerGUID(), BindName()
    if not guid or not name then return nil end
    local binds = type(QR.db) == "table" and QR.db.hearthstoneBinds
    local point = type(binds) == "table" and binds[guid]
    if type(point) == "table" and point.bindName == name
        and (point.source == "HEARTHSTONE_BOUND" or point.source == "HEARTHSTONE_ARRIVAL") then
        local mapID, x, y = QR.PathCalculator:ResolveMapPosition(point.mapID, point.x, point.y)
        if mapID then return { mapID = mapID, x = x, y = y, bindName = name } end
    end
    if not self.innIndex then self:BuildInnIndex() end
    point = self.innIndex[name]
    if not point then return nil end
    return { mapID = point.mapID, x = point.x, y = point.y, bindName = name,
        source = "INN_DATABASE", isApproximate = true }
end

--- Called only for HEARTHSTONE_BOUND. Binding happens near the innkeeper, so
-- the recorded point is an observed approximation of the hearth landing.
function Hearthstone:RecordBind()
    self:CancelArrival()
    local guid = PlayerGUID()
    if not guid or not QR.db then return false end
    if type(QR.db.hearthstoneBinds) ~= "table" then QR.db.hearthstoneBinds = {} end
    -- Clear first: a new binding with unavailable position must not leave the
    -- old location in use, including two different inns with the same name.
    QR.db.hearthstoneBinds[guid] = nil
    QR.PathCalculator.graphDirty = true
    local point = Position()
    local name = BindName()
    if not point or not name then return false end
    return StorePoint(guid, name, point, "HEARTHSTONE_BOUND")
end

function Hearthstone:CancelArrival()
    local pending = self.pendingArrival
    self.pendingArrival = nil
    if pending and pending.timer then pending.timer:Cancel() end
end

function Hearthstone:ScheduleArrival(pending, delay, callback)
    if pending.timer then pending.timer:Cancel() end
    if not (C_Timer and C_Timer.NewTimer) then self:CancelArrival(); return end
    pending.timer = C_Timer.NewTimer(delay, function()
        if self.pendingArrival == pending then pending.timer = nil; callback() end
    end)
end

function Hearthstone:StartArrival(castGUID, spellID)
    self:CancelArrival()
    local guid, name, origin, now = PlayerGUID(), BindName(), Position(), GetTime()
    if not guid or not name or not origin or not Number(now) then return end
    local pending = { guid = guid, bindName = name, origin = origin, castGUID = castGUID,
        spellID = spellID, deadline = now + 60, attempts = 0 }
    self.pendingArrival = pending
    self:ScheduleArrival(pending, 60, function() self:CancelArrival() end)
    return pending
end

function Hearthstone:TryArrival()
    local pending, now = self.pendingArrival, GetTime()
    if not pending then return end
    if not Number(now) or now > pending.deadline or PlayerGUID() ~= pending.guid
        or BindName() ~= pending.bindName then self:CancelArrival(); return end
    if not pending.succeeded or not pending.arrived or pending.loading then return end
    local point = Position()
    local origin = pending.origin
    if point and (point.mapID ~= origin.mapID or math_abs(point.x - origin.x) > 0.001
        or math_abs(point.y - origin.y) > 0.001) and AtBindArea(pending.bindName) then
        StorePoint(pending.guid, pending.bindName, point, "HEARTHSTONE_ARRIVAL")
        self:CancelArrival()
        return
    end
    pending.attempts = pending.attempts + 1
    if pending.attempts >= 12 then self:CancelArrival(); return end
    self:ScheduleArrival(pending, 0.25, function() self:TryArrival() end)
end

-- C_Item.GetItemSpell gives the actual on-use spell for cosmetic hearthstones.
-- Resolve this small known set at initialization/item-cache events, never by
-- scanning inventory or requesting tooltips on every player spell cast.
function Hearthstone:ResolveHearthSpell(itemID)
    if not (C_Item and C_Item.GetItemSpell) then return end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
    if ok and Number(spellID) and spellID > 0 then self.hearthSpells[spellID] = true end
end

function Hearthstone:OnEvent(event, unit, castGUID, spellID)
    if event == "PLAYER_ENTERING_WORLD" and self.innIndexIncomplete then
        self.innIndex, self.innIndexIncomplete = nil, nil
        QR.PathCalculator.graphDirty = true
    end
    if event == "HEARTHSTONE_BOUND" then self:RecordBind(); return end
    if event == "GET_ITEM_INFO_RECEIVED" then
        if Number(unit) and self.hearthItems[unit] then self:ResolveHearthSpell(unit) end
        return
    end
    if event:find("^UNIT_SPELLCAST_") then
        if not Public(unit) or unit ~= "player" then return end
        if not Number(spellID) or not Public(castGUID) or type(castGUID) ~= "string" or castGUID == "" then
            self:CancelArrival(); return
        end
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
            if not self.hearthSpells[spellID] then self:CancelArrival(); return end
            local pending = self.pendingArrival
            if event == "UNIT_SPELLCAST_START" or not pending or pending.castGUID ~= castGUID then
                pending = self:StartArrival(castGUID, spellID)
            end
            if pending and event == "UNIT_SPELLCAST_SUCCEEDED" then
                pending.succeeded = true
                self:TryArrival()
            end
        elseif self.pendingArrival and self.pendingArrival.castGUID == castGUID then
            self:CancelArrival()
        end
        return
    end
    local pending = self.pendingArrival
    if not pending then return end
    if event == "LOADING_SCREEN_ENABLED" then
        pending.loading = true
        pending.arrived = false
        local now = GetTime()
        if not Number(now) or now >= pending.deadline then self:CancelArrival(); return end
        local remaining = pending.deadline - now
        self:ScheduleArrival(pending, remaining, function() self:CancelArrival() end)
    elseif event == "PLAYER_ENTERING_WORLD" and (unit or castGUID) then
        self:CancelArrival() -- login/reload cannot prove the previous cast's arrival
    else
        if event == "LOADING_SCREEN_DISABLED" then pending.loading = false end
        pending.arrived = true
        self:TryArrival()
    end
end

--- Resolve bound hearth items, cosmetic toys and Astral Recall only.
function Hearthstone:ResolveTeleport(data)
    if not data or not data.isDynamic or data.destination ~= "Bound Location" then return data end
    local point = self:GetDestination()
    if not point then return data end
    local resolved = {}
    for key, value in pairs(data) do resolved[key] = value end
    resolved.mapID, resolved.x, resolved.y = point.mapID, point.x, point.y
    resolved.destination = point.bindName
    resolved.nodeKey = "Hearthstone:" .. point.mapID .. ":" .. point.x .. ":" .. point.y
    resolved.isDynamic = false
    resolved.isBoundHearth = true
    resolved.hearthstoneSource, resolved.isApproximate = point.source, point.isApproximate
    return resolved
end

function Hearthstone:Initialize()
    if self.frame then return end
    self.hearthSpells, self.hearthItems = { [8690] = true }, {}
    for itemID, data in pairs(QR.TeleportItemsData or {}) do
        if data.isDynamic and data.destination == "Bound Location" then
            self.hearthItems[itemID] = true
            self:ResolveHearthSpell(itemID)
        end
    end
    for spellID, data in pairs(QR.ClassTeleportSpells or {}) do
        if data.isDynamic and data.destination == "Bound Location" then self.hearthSpells[spellID] = true end
    end
    local frame = CreateFrame("Frame")
    for _, event in pairs({ "HEARTHSTONE_BOUND", "GET_ITEM_INFO_RECEIVED", "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)
    self.frame = frame
end
