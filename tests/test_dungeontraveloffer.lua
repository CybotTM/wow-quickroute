local T, QR = ...

-- Travel to a dungeon is offered when the player is accepted into a group for
-- it. The identity of the instance comes from an id, never from the group's
-- title, and the offer never acts on the player by itself.

local function withLFG(searchResult, activity, body)
    local saved = _G.C_LFGList
    _G.C_LFGList = {
        GetSearchResultInfo = function() return searchResult end,
        GetActivityInfoTable = function() return activity end,
    }
    local ok, err = pcall(body)
    _G.C_LFGList = saved
    if not ok then error(err, 0) end
end

local function withInstance(instanceID, record, body)
    local dd = QR.DungeonData
    local saved = dd.instances[instanceID]
    dd.instances[instanceID] = record
    local ok, err = pcall(body)
    dd.instances[instanceID] = saved
    if not ok then error(err, 0) end
end

local INSTANCE = { name = "Test Halls", zoneMapID = 84, x = 0.42, y = 0.58, isRaid = false }

T:run("DungeonOffer: a single resolvable activity produces an offer", function(t)
    withInstance(70001, INSTANCE, function()
        withLFG({ activityIDs = { 555 } }, { journalInstanceID = 70001 }, function()
            local resolved = QR.DungeonTravelOffer:ResolveInstance(1)
            t:assertEqual(70001, resolved, "the journal instance is read from the activity")
            t:assertTrue(QR.DungeonTravelOffer:Present(resolved), "the offer is presented")
            local pending = QR.DungeonTravelOffer.pending
            t:assertEqual(84, pending.mapID, "the offer carries the entrance zone")
            t:assertEqual("Test Halls", pending.title, "and the instance name")
            QR.DungeonTravelOffer:Clear()
        end)
    end)
end)

T:run("DungeonOffer: an ambiguous application produces no offer", function(t)
    withInstance(70001, INSTANCE, function()
        withLFG({ activityIDs = { 555, 556 } }, { journalInstanceID = 70001 }, function()
            t:assertNil(QR.DungeonTravelOffer:ResolveInstance(1),
                "two activities are two possible destinations, so neither is offered")
        end)
    end)
end)

T:run("DungeonOffer: an activity with no known instance produces no offer", function(t)
    withLFG({ activityIDs = { 555 } }, { shortName = "+15 NW need heals" }, function()
        t:assertNil(QR.DungeonTravelOffer:ResolveInstance(1),
            "a group title is not an instance identifier")
    end)
    withInstance(70001, INSTANCE, function()
        withLFG({ activityIDs = { 555 } }, { journalInstanceID = 999999 }, function()
            t:assertNil(QR.DungeonTravelOffer:ResolveInstance(1),
                "an id QuickRoute does not know is not offered")
        end)
    end)
end)

T:run("DungeonOffer: a missing LFG API is survived without error", function(t)
    local saved = _G.C_LFGList
    _G.C_LFGList = nil
    t:assertNil(QR.DungeonTravelOffer:ResolveInstance(1), "no API means no offer")
    _G.C_LFGList = {}
    t:assertNil(QR.DungeonTravelOffer:ResolveInstance(1), "an API without the lookups means no offer")
    _G.C_LFGList = saved
end)

T:run("DungeonOffer: routing shows the route and sets no waypoint", function(t)
    withInstance(70001, INSTANCE, function()
        local pc = QR.PathCalculator
        local savedCalc, savedAfter = pc.CalculatePath, C_Timer.After
        local savedSet = QR.WaypointIntegration.SetTomTomWaypoint
        local savedUpdate = QR.UI.UpdateRoute
        local queue, touched, updated = {}, 0, 0
        C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
        QR.WaypointIntegration.SetTomTomWaypoint = function() touched = touched + 1 end
        QR.UI.UpdateRoute = function() updated = updated + 1 end
        pc.CalculatePath = function(_, mapID)
            return { totalTime = 42, steps = { { type = "walk", to = "Entrance", navMapID = mapID } } }
        end
        QR.DungeonTravelOffer:Present(70001)
        local got
        QR.DungeonTravelOffer:Route(function(result) got = result end)
        while #queue > 0 do table.remove(queue, 1)() end
        pc.CalculatePath, C_Timer.After = savedCalc, savedAfter
        QR.WaypointIntegration.SetTomTomWaypoint = savedSet
        QR.UI.UpdateRoute = savedUpdate
        QR.DungeonTravelOffer:Clear()
            t:assertNotNil(got, "the route arrives")
        -- The route panel builds a step's Use button from the teleport identity,
        -- which the public contract deliberately does not export. Routing the
        -- addon's own display through its own contract produced a step list the
        -- panel could not turn into a usable button.
        t:assertNotNil(got.steps, "the panel receives the steps it renders")
        t:assertEqual(0, touched, "offering travel set no waypoint")
        t:assertEqual(1, updated, "the route is shown rather than acted on")
    end)
end)

T:run("DungeonOffer: routing without an offer does nothing", function(t)
    QR.DungeonTravelOffer:Clear()
    t:assertFalse(QR.DungeonTravelOffer:Route(), "no offer, no request")
end)

T:run("DungeonOffer: an unrelated instance does not clear the offer", function(t)
    withInstance(70005, { name = "Offered Halls", zoneMapID = 84, x = 0.4, y = 0.5 }, function()
        local savedIn, savedInfo = _G.IsInInstance, _G.GetInstanceInfo
        _G.IsInInstance = function() return true, "party" end
        QR.DungeonTravelOffer:Present(70005)
        _G.GetInstanceInfo = function() return "Some Other Raid" end
        t:assertFalse(QR.DungeonTravelOffer:InsideOfferedInstance(),
            "standing in a different instance is not arrival")
        _G.GetInstanceInfo = function() return "Offered Halls" end
        t:assertTrue(QR.DungeonTravelOffer:InsideOfferedInstance(),
            "standing in the offered one is")
        _G.GetInstanceInfo = function() return nil end
        t:assertFalse(QR.DungeonTravelOffer:InsideOfferedInstance(),
            "a silent client keeps the offer rather than dropping it")
        _G.IsInInstance, _G.GetInstanceInfo = savedIn, savedInfo
        QR.DungeonTravelOffer:Clear()
    end)
end)

T:run("DungeonOffer: the route the panel receives can still build a Use button", function(t)
    withInstance(70006, { name = "Use Halls", zoneMapID = 84, x = 0.4, y = 0.5 }, function()
        local pc = QR.PathCalculator
        local savedCalc, savedAfter, savedUpdate = pc.CalculatePath, C_Timer.After, QR.UI.UpdateRoute
        local queue, received = {}, nil
        C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
        QR.UI.UpdateRoute = function(_, result) received = result end
        pc.CalculatePath = function()
            return { totalTime = 10, steps = { {
                type = "teleport", from = "A", to = "B", time = 10, action = "Teleport to B",
                teleportID = 6948, sourceType = "item", teleportData = { name = "Hearthstone" },
                navMapID = 84, navX = 0.5, navY = 0.5,
            } } }
        end
        QR.DungeonTravelOffer:Present(70006, 1)
        QR.DungeonTravelOffer:Route()
        while #queue > 0 do table.remove(queue, 1)() end
        pc.CalculatePath, C_Timer.After, QR.UI.UpdateRoute = savedCalc, savedAfter, savedUpdate
        QR.DungeonTravelOffer:Clear()
        t:assertNotNil(received, "the panel received a route")
        local step = received.steps[1]
        t:assertEqual(6948, step.teleportID, "the teleport identity survives to the panel")
        t:assertEqual("item", step.sourceType, "and so does where it comes from")
        t:assertNotNil(step.teleportData, "and the data the button is built from")
    end)
end)

T:run("DungeonOffer: another application's outcome leaves this offer alone", function(t)
    withInstance(70007, { name = "Kept Halls", zoneMapID = 84, x = 0.4, y = 0.5 }, function()
        QR.DungeonTravelOffer:Present(70007, 4242)
        local handler = QR.DungeonTravelOffer.frame:GetScript("OnEvent")
        handler(QR.DungeonTravelOffer.frame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 9999, "timedout")
        t:assertNotNil(QR.DungeonTravelOffer.pending, "an unrelated application expiring keeps the offer")
        handler(QR.DungeonTravelOffer.frame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 4242, "cancelled")
        t:assertNil(QR.DungeonTravelOffer.pending, "its own application being cancelled clears it")
    end)
end)

T:run("DungeonOffer: leaving the group ends the offer and gives the trip back", function(t)
    withInstance(70008, { name = "Left Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        QR.Journey:Clear()
        QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2, title = "Chosen" })
        QR.Journey:Lock(QR.Journey.SOURCE.MANUAL)
        QR.DungeonTravelOffer:Present(70008, 7)
        local handler = QR.DungeonTravelOffer.frame:GetScript("OnEvent")
        handler(QR.DungeonTravelOffer.frame, "GROUP_LEFT")
        t:assertNil(QR.DungeonTravelOffer.pending, "leaving the group drops the offer")
        t:assertEqual(QR.Journey.SOURCE.MANUAL, QR.Journey:Get().source, "and the player's trip comes back")
        QR.Journey:Clear()
    end)
end)

T:run("DungeonOffer: an offer is kept while another source holds the journey", function(t)
    withInstance(70009, { name = "Held Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        QR.Journey:Clear()
        QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2 })
        QR.Journey:Lock(QR.Journey.SOURCE.MANUAL)
        QR.DungeonTravelOffer:Present(70009, 8)
        -- Somebody else detours over the offer. Dropping `pending` here left the
        -- detour in force with nothing able to end it.
        QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5 })
        t:assertFalse(QR.DungeonTravelOffer:Clear(), "the offer is not cleared while somebody else owns the journey")
        t:assertNotNil(QR.DungeonTravelOffer.pending, "so it is still there to clear later")
        -- Every clear trigger is one-shot, so without a second chance the offer
        -- and its detour stayed for the session. Releasing the other source has
        -- to finish the job by itself.
        QR.Journey:Release("rare_alert")
        t:assertNil(QR.DungeonTravelOffer.pending,
            "releasing the other source clears the offer without another trigger")
        QR.Journey:Clear()
    end)
end)
