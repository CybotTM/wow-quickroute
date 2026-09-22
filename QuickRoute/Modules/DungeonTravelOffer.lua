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
-- resolves to a single LFG activity. Every lookup is guarded and an unresolved
-- application simply produces no offer, so being wrong costs a missing offer
-- rather than a wrong destination. The tell is a debug line "no journal
-- instance for activity N" on every accepted group.
--
-- The instance identity comes out of the activity record. The generated
-- GroupFinderActivityInfo structure declares `mapID` and no journal field at
-- all, and a game map id is a different namespace from the journal instance id
-- the lookup is keyed by, so it is converted through the client rather than
-- passed through. Passing it through matched whichever journal record happened
-- to share the number, which is the one outcome the paragraph above promises
-- cannot happen.
--
-- SECOND ASSUMPTION, also only settleable against a live client: that this
-- `mapID` is the game map id GetInstanceForGameMap takes. The field carries no
-- documentation, and Blizzard's own group finder code never reads it. The
-- conversion result is checked against the journal before it is used, so a
-- wrong namespace normally costs an offer rather than a wrong one -- and the
-- Debug line below names the activity, the game map, the journal instance and
-- the instance name on every resolved offer, so one session of real groups
-- settles it either way.
local ADDON_NAME, QR = ...
local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring

local Offer = { pending = nil }
QR.DungeonTravelOffer = Offer

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
    local gameMapID = activity.mapID
    if type(gameMapID) == "number" then
        local journal = _G.C_EncounterJournal
        local converted = journal and Call(journal.GetInstanceForGameMap, gameMapID)
        if type(converted) == "number" then
            local instance = QR.DungeonData and QR.DungeonData:GetInstance(converted)
            if instance then
                -- The success path is logged as well as the failure, because
                -- the two ways of being wrong about the map namespace look
                -- different: one produces no offer, the other produces an
                -- offer to somewhere else. A line naming the activity, the
                -- game map, the journal instance and the name it resolved to
                -- settles which happened from one session.
                QR:Debug(string.format(
                    "DungeonTravelOffer: activity %s, game map %s -> journal instance %s (%s)",
                    tostring(activityID), tostring(gameMapID), tostring(converted),
                    tostring(instance.name)))
                return converted
            end
        end
    end
    QR:Debug("DungeonTravelOffer: no journal instance for activity " .. tostring(activityID) ..
        ", game map " .. tostring(gameMapID))
    return nil
end

--- Record an offer and tell the player it is available.
-- @param journalInstanceID number
function Offer:Present(journalInstanceID, resultID)
    local instance = QR.DungeonData and QR.DungeonData:GetInstance(journalInstanceID)
    if not (instance and instance.zoneMapID and instance.x and instance.y) then return false end
    -- A refused clear is a decision about the group the player has already
    -- left. A newly accepted group supersedes it: the flag survived into the
    -- new offer and destroyed it the moment the foreign detour above it ended.
    self.clearWhenFree = nil
    self.pending = {
        journalInstanceID = journalInstanceID,
        resultID = resultID,
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
        elseif held and held.detour then
            -- Somebody else's detour is in force. Stacking a second one under
            -- it left an offer detour that nothing could reach: every clear
            -- path is gated on `pending`, which the entry into the instance
            -- had already cleared.
            --
            -- An earlier offer of ours may still be suspended below. Retargeting
            -- it keeps the ledger and the offer naming the same dungeon; without
            -- that, ending the foreign detour restored the arrow to the first
            -- instance while the button named the second.
            if self:RetargetSuspended(self.pending) then
                self.holdsDetour = true
            else
                self.holdsDetour = false
            end
            QR:Debug("DungeonTravelOffer: another detour is in force, no detour taken")
        else
            QR.Journey:Detour(QR.Journey.SOURCE.DUNGEON_OFFER, self.pending)
            self.holdsDetour = true
        end
    end
    QR:Print(string.format(QR.L["DUNGEON_OFFER_READY"], tostring(instance.name)))
    if QR.UI and QR.UI.RefreshDungeonOffer then QR.UI:RefreshDungeonOffer() end
    return true
end

--- Calculate the route to the pending offer.
-- Calculation only: nothing here sets a waypoint or starts travel.
--
-- This goes through the internal calculator rather than through
-- QuickRouteAPI. The contract deliberately exports only the fields a foreign
-- consumer needs, and QuickRoute's own route panel reads more than that -- the
-- teleport identity a step's Use button is built from. Routing the addon's own
-- display through its own public contract produced a step list the panel could
-- not turn into a usable button.
-- @param callback function|nil Receives (result, failure)
function Offer:Route(callback)
    local pending = self.pending
    if not pending then return false end
    QR.PathCalculator:CalculatePathAsync(pending.mapID, pending.x, pending.y, pending.title,
        function(result, failure)
            -- The search outlives the offer it was started for. Leaving the
            -- group clears the offer, and without this the result still reached
            -- the panel and showed the way to a dungeon the player is no longer
            -- going to.
            --
            -- Two ways the offer stops standing. Its record is replaced or
            -- dropped, which `pending` catches. Or Clear was asked for and
            -- refused because another source holds the journey -- then
            -- `pending` survives on purpose, waiting for the release listener,
            -- and `clearWhenFree` is the only thing that says the player has
            -- already left the group.
            --
            -- The calculation itself runs to the end rather than being
            -- cancelled: it cleans up the temporary destination node on its way
            -- out, and the result is simply not published.
            if self.pending ~= pending or self.clearWhenFree then
                QR:Debug("DungeonTravelOffer: offer no longer stands, route dropped")
                if type(callback) == "function" then
                    -- Not retryable: asking again produces a route to a dungeon
                    -- the player is no longer going to. The same answer the
                    -- public contract gives a superseded request.
                    callback(nil, { reason = QR.PathCalculator.FAILURE.SUPERSEDED, retryable = false })
                end
                return
            end
            if not result then
                QR:Print(QR.PathCalculator:DescribeFailure(failure))
            elseif QR.UI and QR.UI.UpdateRoute then
                -- The panel reads the route's own destination to decide what a
                -- refused step is refused FOR. Every other producer stamps it;
                -- this one did not, so the reject button fell back to whichever
                -- journey was current -- after an asynchronous search, the one
                -- from before it. The refusal then applied to that route and
                -- the refused hop came straight back on this one.
                result.waypoint = { mapID = pending.mapID, x = pending.x,
                    y = pending.y, title = pending.title }
                result.waypointSource = "dungeon_offer"
                QR.UI:UpdateRoute(result)
            end
            if type(callback) == "function" then callback(result, failure) end
        end)
    return true
end

--- The offer's own detour, suspended under somebody else's.
-- @return table|nil The ledger entry, innermost first
function Offer:SuspendedDetour()
    local suspended = QR.Journey and QR.Journey.suspended
    if type(suspended) ~= "table" then return nil end
    for index = #suspended, 1, -1 do
        local entry = suspended[index]
        if entry.detour and entry.source == QR.Journey.SOURCE.DUNGEON_OFFER then
            return entry
        end
    end
    return nil
end

--- Point an offer detour that is suspended under somebody else's at a new
--- instance.
-- @return boolean Whether such an entry was found
function Offer:RetargetSuspended(destination)
    local entry = self:SuspendedDetour()
    if not entry then return false end
    entry.destination = { mapID = destination.mapID, x = destination.x,
        y = destination.y, title = destination.title }
    return true
end

--- Drop the offer. Entering the instance is the normal reason.
-- Ending the detour restores whatever journey it interrupted.
function Offer:Clear()
    -- Release first. Dropping `pending` regardless left the detour in force
    -- with every remaining clear path gated on `pending`, so nothing could ever
    -- end it.
    -- Only an offer that took a journey has one to give back. An offer
    -- presented while a third source held a detour never took one, and waiting
    -- for a journey it does not own would keep it forever.
    if QR.Journey and self.holdsDetour then
        local held = QR.Journey:Get()
        if held and held.source ~= QR.Journey.SOURCE.DUNGEON_OFFER then
            QR:Debug("DungeonTravelOffer: another source holds the journey, offer kept")
            -- Remembered, so the release listener finishes the job.
            self.clearWhenFree = true
            return false
        end
        QR.Journey:Release(QR.Journey.SOURCE.DUNGEON_OFFER)
    end
    self.pending = nil
    self.clearWhenFree = nil
    self.holdsDetour = nil
    if QR.UI and QR.UI.RefreshDungeonOffer then QR.UI:RefreshDungeonOffer() end
    return true
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
        if event == "GROUP_LEFT" then
            -- Entering the instance was the only exit, so a player who left or
            -- lost the group kept the detour for the rest of the session.
            if self.pending then self:Clear() end
            return
        end
        if status == "declined" or status == "cancelled" or status == "timedout" then
            -- Only for the application this offer came from. A player who
            -- applied to several groups otherwise lost the offer for the group
            -- that took them as soon as an unrelated application expired.
            if self.pending and self.pending.resultID == resultID then self:Clear() end
            return
        end
        if status ~= "inviteaccepted" then return end
        local journalInstanceID = self:ResolveInstance(resultID)
        if journalInstanceID then self:Present(journalInstanceID, resultID) end
    end)
    self.frame = frame
    -- A clear refused because another source held the journey had no second
    -- chance: every trigger is one-shot, so the offer and its detour stayed for
    -- the session. When the journey comes back, try again.
    if QR.Journey and QR.Journey.OnRelease then
        QR.Journey:OnRelease(function()
            if not self.pending then return end
            local held = QR.Journey:Get()
            -- The offer's own detour is gone: either it was released, or the
            -- player took the journey over by choosing somewhere else. Either
            -- way the offer no longer stands, and the pending record has to go
            -- with it or nothing will ever clear it.
            if held ~= nil and held.source == QR.Journey.SOURCE.DUNGEON_OFFER then
                -- The offer's own detour is current again, so a clear that was
                -- refused earlier can finish now.
                if self.clearWhenFree then self:Clear() end
                return
            end
            -- The player took the journey over by choosing somewhere else, so
            -- the offer no longer stands.
            --
            -- Only when this offer actually held a detour. An offer presented
            -- while a third source held one never took a journey at all, and
            -- treating "the current journey is not mine" as proof of a takeover
            -- destroyed it the moment that unrelated detour ended.
            if not self.holdsDetour then return end
            -- "I took a detour once" is not "my detour is gone". With two
            -- foreign detours above it, the offer's own entry is still in the
            -- ledger when the outer one ends, and destroying the offer here
            -- left that entry unreachable: every clear path is gated on
            -- `pending`. The player's own trip, suspended below it, never came
            -- back.
            if self:SuspendedDetour() then return end
            self.pending = nil
            self.clearWhenFree = nil
            self.holdsDetour = nil
            if QR.UI and QR.UI.RefreshDungeonOffer then QR.UI:RefreshDungeonOffer() end
        end)
    end
end
