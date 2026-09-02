-- PlayerInfo.lua
-- Centralized player information utility (faction, class, professions)
-- Eliminates duplication across TeleportPanel, TeleportItems, Portals,
-- PlayerInventory, and PathCalculator modules.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local UnitFactionGroup = UnitFactionGroup
local UnitClass = UnitClass
local GetProfessions = GetProfessions
local GetProfessionInfo = GetProfessionInfo

-------------------------------------------------------------------------------
-- PlayerInfo Module
-------------------------------------------------------------------------------
QR.PlayerInfo = {}

local PlayerInfo = QR.PlayerInfo

-- Internal cache (module-level locals for speed)
local cachedFaction = nil
local cachedClass = nil
local cachedHasEngineering = nil

-- Engineering skill line ID (works for all locales)
local ENGINEERING_SKILL_LINE_ID = 202

--- Get player faction as "Alliance", "Horde" or "Neutral" (cached, with one
--- exception).
--
-- "Neutral" is the only value that can change while the player is logged in: a
-- pandaren begins neutral and picks a side at the end of the starting
-- experience. So it is deliberately not cached, and every other value is,
-- exactly as before. That needs no event registration and no guess at which
-- event fires -- which matters, because the addon registers no faction events
-- and nothing in it ever called InvalidateCache.
--
-- Without this a pandaren who chose Horde kept "Neutral" for the rest of the
-- session, and every faction-gated decision was made for the wrong character.
-- @return string "Alliance", "Horde" or "Neutral"
function PlayerInfo:GetFaction()
    if cachedFaction and cachedFaction ~= "Neutral" then
        return cachedFaction
    end
    cachedFaction = UnitFactionGroup("player") or "Alliance"
    return cachedFaction
end

--- Get player class as uppercase token like "MAGE", "DRUID" (cached)
-- @return string The uppercase class token
function PlayerInfo:GetClass()
    if not cachedClass then
        local _, classToken = UnitClass("player")
        cachedClass = classToken
    end
    return cachedClass
end

--- Check if player class matches the given class name
-- @param className string Uppercase class token to check (e.g. "MAGE")
-- @return boolean True if the player's class matches
function PlayerInfo:IsClass(className)
    return self:GetClass() == className
end

--- Check if player has Engineering profession (cached)
-- Uses skill line ID 202 for locale-independence, with string fallback
-- for older API versions.
-- @return boolean True if the player has Engineering
function PlayerInfo:HasEngineering()
    if cachedHasEngineering == nil then
        cachedHasEngineering = false
        local prof1, prof2 = GetProfessions()

        -- Helper to check if a profession index is Engineering
        local function CheckProfession(profIndex)
            if not profIndex then return false end
            local name, _, _, _, _, _, skillLineID = GetProfessionInfo(profIndex)
            -- Check skill line ID (locale-independent)
            if skillLineID == ENGINEERING_SKILL_LINE_ID then
                return true
            end
            -- Fallback for older API versions that don't return skillLineID
            if name and (name == "Engineering" or name == "Ingenieurwesen" or name == "Ingénierie") then
                return true
            end
            return false
        end

        cachedHasEngineering = CheckProfession(prof1) or CheckProfession(prof2)
    end
    return cachedHasEngineering
end

--- Whether the player stands on one of the given maps or on a map nested
-- inside one of them (a raid floor inside its island, a city inside its zone).
-- Teleports with a `usableOnMaps` list only work there; the game refuses
-- them elsewhere, so the addon must not offer them as ready.
-- @param mapIDs table Array of uiMapIDs
-- @return boolean true when the player's map, or one of its ancestors, is listed;
--   also true when the map API cannot say where the player is
function PlayerInfo:IsOnAnyMap(mapIDs)
    if not mapIDs or #mapIDs == 0 then return true end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return true end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return true end
    local wanted = {}
    for _, id in ipairs(mapIDs) do wanted[id] = true end
    local guard = 0
    while mapID and guard < 16 do
        if wanted[mapID] then return true end
        local info = C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
        if mapID == 0 then mapID = nil end
        guard = guard + 1
    end
    return false
end

--- Clear all cached values
-- Call when profession changes or for testing purposes.
function PlayerInfo:InvalidateCache()
    cachedFaction = nil
    cachedClass = nil
    cachedHasEngineering = nil
end
