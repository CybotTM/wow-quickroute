-- Remember observed hearthstone bindings per character, without guessing from
-- the current zone or sharing a different character's inn.
local ADDON_NAME, QR = ...
local pairs, type, pcall = pairs, type, pcall

QR.Hearthstone = {}
local Hearthstone = QR.Hearthstone

local function PlayerGUID()
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and type(guid) == "string" and guid ~= "" then return guid end
end

local function BindName()
    if not GetBindLocation then return nil end
    local ok, name = pcall(GetBindLocation)
    if ok and type(name) == "string" and name ~= "" then return name end
end

function Hearthstone:GetDestination()
    local guid, name = PlayerGUID(), BindName()
    local binds = QR.db and QR.db.hearthstoneBinds
    local point = guid and type(binds) == "table" and binds[guid]
    if type(point) ~= "table" or point.source ~= "HEARTHSTONE_BOUND"
        or not name or point.bindName ~= name then return nil end
    local mapID, x, y = QR.PathCalculator:ResolveMapPosition(point.mapID, point.x, point.y)
    if not mapID then return nil end
    return { mapID = mapID, x = x, y = y, bindName = name }
end

--- Called only for HEARTHSTONE_BOUND. Binding happens near the innkeeper, so
-- the recorded point is an observed approximation of the hearth landing.
function Hearthstone:RecordBind()
    local guid = PlayerGUID()
    if not guid or not QR.db then return false end
    if type(QR.db.hearthstoneBinds) ~= "table" then QR.db.hearthstoneBinds = {} end
    -- Clear first: a new binding with unavailable position must not leave the
    -- old location in use, including two different inns with the same name.
    QR.db.hearthstoneBinds[guid] = nil
    QR.PathCalculator.graphDirty = true
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return false end
    local ok, mapID, x, y = pcall(function()
        local map = C_Map.GetBestMapForUnit("player")
        if not map then return end
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        if not pos then return end
        local px, py = pos:GetXY()
        return QR.PathCalculator:ResolveMapPosition(map, px, py)
    end)
    local name = BindName()
    if not ok or not mapID or not name then return false end
    QR.db.hearthstoneBinds[guid] = {
        mapID = mapID, x = x, y = y, bindName = name, source = "HEARTHSTONE_BOUND",
    }
    return true
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
    return resolved
end

function Hearthstone:Initialize()
    if self.frame then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("HEARTHSTONE_BOUND")
    frame:SetScript("OnEvent", function() self:RecordBind() end)
    self.frame = frame
end
