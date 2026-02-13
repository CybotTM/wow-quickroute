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

--- Get player faction as "Alliance" or "Horde" (cached)
-- @return string "Alliance" or "Horde"
function PlayerInfo:GetFaction()
    if not cachedFaction then
        cachedFaction = UnitFactionGroup("player") or "Alliance"
    end
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

--- Clear all cached values
-- Call when profession changes or for testing purposes.
function PlayerInfo:InvalidateCache()
    cachedFaction = nil
    cachedClass = nil
    cachedHasEngineering = nil
end
