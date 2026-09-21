-- TargetIdentity.lua
-- What a destination is, not just where it is.
--
-- Knowing a coordinate is not the same as knowing what the player is supposed
-- to do there. A quest objective, the place to hand that quest in, a reference
-- location out of a catalogue, a prerequisite that has to be done first and a
-- vendor that sells the thing all look identical once they are reduced to a
-- map and two numbers, and they need different sentences and different
-- completion rules.
--
-- This module owns the vocabulary and the two checks that keep it honest: a
-- quest that is not in the log is a reference, not an objective, and arriving
-- somewhere is not completing anything.
local ADDON_NAME, QR = ...
local type, pcall = type, pcall

local Identity = {}
QR.TargetIdentity = Identity

Identity.ROLE = {
    OBJECTIVE = "objective",        -- an active quest objective in this character's log
    TURN_IN = "turn_in",            -- where an active quest is handed in
    REFERENCE = "reference",        -- a catalogued location, not an active task
    PREREQUISITE = "prerequisite",  -- has to be done before the real target
    ACQUISITION = "acquisition",    -- a source for something the player wants
    SERVICE = "service",            -- a vendor, bank, auction house
    ENTRANCE = "entrance",          -- an instance entrance
    HUB = "hub",                    -- a city or travel hub
}

local ROLE_LABEL = {
    objective = "TARGET_ROLE_OBJECTIVE",
    turn_in = "TARGET_ROLE_TURN_IN",
    reference = "TARGET_ROLE_REFERENCE",
    prerequisite = "TARGET_ROLE_PREREQUISITE",
    acquisition = "TARGET_ROLE_ACQUISITION",
    service = "TARGET_ROLE_SERVICE",
    entrance = "TARGET_ROLE_ENTRANCE",
    hub = "TARGET_ROLE_HUB",
}

--- The localized word for a role.
-- @param role string One of Identity.ROLE
-- @return string|nil
function Identity:Describe(role)
    local key = ROLE_LABEL[role]
    return key and QR.L[key] or nil
end

--- Whether this quest is actually in this character's log right now.
-- A quest that is not is a reference location: the coordinate may be correct
-- and the task is not available, so nothing may present it as an objective.
-- @param questID number
-- @return boolean
function Identity:IsActiveObjective(questID)
    if type(questID) ~= "number" then return false end
    local questLog = _G.C_QuestLog
    if not (questLog and questLog.IsOnQuest) then return false end
    local ok, onQuest = pcall(questLog.IsOnQuest, questID)
    return ok and onQuest == true
end

--- The role a quest destination really has for this character.
-- @param questID number
-- @return string Identity.ROLE.OBJECTIVE or Identity.ROLE.REFERENCE
function Identity:QuestRole(questID)
    if self:IsActiveObjective(questID) then return self.ROLE.OBJECTIVE end
    return self.ROLE.REFERENCE
end

--- Whether standing at a target finishes what it is for.
-- Always false. Arrival is arrival: an objective needs its own completion, an
-- acquisition needs the item, a service needs the interaction. This is a
-- function rather than an absent feature so that nothing has to infer it.
-- @return boolean
function Identity:ArrivalCompletes()
    return false
end
