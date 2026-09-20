-- DungeonTravelOffer.lua
-- Offer the way to a dungeon at the moment the player is accepted into a group.
--
-- QuickRoute already knows every entrance and every dungeon teleport. What it
-- did not do was offer them when the player actually needs them, which is the
-- second they are invited into a Premade Group Finder group for an instance
-- they now have to travel to.
--
-- Two rules shape this module.
--
-- It resolves an instance from an identifier, never from the group's title. A
-- fuzzy match on "+15 NW need heals" is a guess, and a guess that moves the
-- player's arrow is worse than doing nothing.
--
-- It offers, it does not act. No waypoint is set, no teleport is cast and no
-- protected action is touched. The player clicks, or nothing happens.
--
-- ASSUMPTION, only settleable against a live client: the accepted application
-- resolves to a single LFG activity, and that activity carries a journal
-- instance id under one of the field names read in ResolveInstance below. Every
-- lookup is guarded and an unresolved application simply produces no offer, so
-- being wrong costs a missing offer rather than a wrong destination. The tell is
-- a debug line "no journal instance for activity N" on every accepted group.
local ADDON_NAME, QR = ...
local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring

local Offer = { pending = nil }
QR.DungeonTravelOffer = Offer

-- Field names an activity record may carry the journal instance under. Read in
-- order; the first numeric one wins.
local INSTANCE_FIELDS = { "journalInstanceID", "instanceID", "mapID" }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

--- Resolve the journal instance an accepted application is for.
-- @param resultID number The search result the application belongs to
-- @return number|nil journalInstanceID
function Offer:ResolveInstance(resultID)
    local lfg = _G.C_LFGList
    if not lfg or type(resultID) ~= "number" then return nil end
    local info = Call(lfg.GetSearchResultInfo, resultID)
    if type(info) ~= "table" or type(info.activityIDs) ~= "table" then return nil end
    -- More than one activity is more than one possible destination. Offering
    -- one of them is a guess.
    if #info.activityIDs ~= 1 then
        QR:Debug("DungeonTravelOffer: application covers " .. #info.activityIDs .. " activities, no offer")
        return nil
    end
    local activityID = info.activityIDs[1]
    local activity = Call(lfg.GetActivityInfoTable, activityID)
    if type(activity) ~= "table" then return nil end
    for _, field in ipairs(INSTANCE_FIELDS) do
        local value = activity[field]
        if type(value) == "number" and QR.DungeonData and QR.DungeonData:GetInstance(value) then
            return value
        end
    end
    QR:Debug("DungeonTravelOffer: no journal instance for activity " .. tostring(activityID))
    return nil
end

--- Record an offer and tell the player it is available.
-- @param journalInstanceID number
function Offer:Present(journalInstanceID)
    local instance = QR.DungeonData and QR.DungeonData:GetInstance(journalInstanceID)
    if not (instance and instance.zoneMapID and instance.x and instance.y) then return false end
    self.pending = {
        journalInstanceID = journalInstanceID,
        mapID = instance.zoneMapID,
        x = instance.x,
        y = instance.y,
        title = instance.name,
    }
    -- A dungeon group is an interruption, not a replacement: the trip the
    -- player was on is suspended and comes back when the detour ends.
    --
    -- A second offer replaces the first rather than stacking on it. Two
    -- detours would need two clears to give the player's own trip back, and
    -- the first clear would restore the earlier offer instead.
    if QR.Journey then
        local held = QR.Journey:Get()
        if held and held.detour and held.source == QR.Journey.SOURCE.DUNGEON_OFFER then
            QR.Journey:Retarget(QR.Journey.SOURCE.DUNGEON_OFFER, self.pending)
        else
            QR.Journey:Detour(QR.Journey.SOURCE.DUNGEON_OFFER, self.pending)
        end
    end
    QR:Print(string.format(QR.L["DUNGEON_OFFER_READY"], tostring(instance.name)))
    return true
end

--- Calculate the route to the pending offer.
-- Goes through the public routing contract, which is the same contract another
-- addon would use, and which never sets a waypoint by itself.
-- @param callback function|nil Receives (result, failure)
function Offer:Route(callback)
    local pending = self.pending
    if not pending then return false end
    QR.RoutingAPI:CalculateRoute({
        mapID = pending.mapID, x = pending.x, y = pending.y, title = pending.title,
    }, function(result, failure)
        if not result then
            QR:Print(QR.PathCalculator:DescribeFailure(failure))
        elseif QR.UI and QR.UI.UpdateRoute then
            QR.UI:UpdateRoute(result)
        end
        if type(callback) == "function" then callback(result, failure) end
    end)
    return true
end

--- Drop the offer. Entering the instance is the normal reason.
-- Ending the detour restores whatever journey it interrupted.
function Offer:Clear()
    self.pending = nil
    if QR.Journey then QR.Journey:Release(QR.Journey.SOURCE.DUNGEON_OFFER) end
end

--- Whether the player is now inside the instance the offer was for.
-- Being inside *some* instance is not arrival: a battleground, a scenario or an
-- unrelated raid would otherwise drop the offer and end the detour.
function Offer:InsideOfferedInstance()
    local pending = self.pending
    if not pending then return false end
    if Call(_G.IsInInstance) ~= true then return false end
    local instance = QR.DungeonData and QR.DungeonData:GetInstance(pending.journalInstanceID)
    if not (instance and type(instance.name) == "string" and instance.name ~= "") then return false end
    -- The journal record carries a name and no instance id, so the name is what
    -- there is to compare. Both sides come from the client in the same locale.
    -- A mismatch or a silent API keeps the offer: it is dropped when the group
    -- ends or the player routes elsewhere, never by an unrelated loading
    -- screen.
    local ok, currentName = pcall(_G.GetInstanceInfo)
    if not ok or type(currentName) ~= "string" then return false end
    return currentName == instance.name
end

function Offer:Initialize()
    if self.frame then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "LFG_LIST_APPLICATION_STATUS_UPDATED", "PLAYER_ENTERING_WORLD", "GROUP_LEFT" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, resultID, status)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Verified entry clears the offer; a loading screen on the way
            -- there does not, because the player is not inside yet.
            if self:InsideOfferedInstance() then self:Clear() end
            return
        end
        if event == "GROUP_LEFT" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED"
            and (status == "declined" or status == "cancelled" or status == "timedout") then
            -- Entering the instance was the only exit, so a player who left or
            -- lost the group kept the detour for the rest of the session.
            if self.pending then self:Clear() end
            if event == "GROUP_LEFT" then return end
        end
        if status ~= "inviteaccepted" then return end
        local journalInstanceID = self:ResolveInstance(resultID)
        if journalInstanceID then self:Present(journalInstanceID) end
    end)
    self.frame = frame
end
