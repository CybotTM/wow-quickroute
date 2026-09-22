local T, QR, MockWoW = ...

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

T:run("DungeonOffer: a cleared offer publishes no route", function(t)
    withInstance(70001, INSTANCE, function()
        local pc = QR.PathCalculator
        local savedAsync = pc.CalculatePathAsync
        local savedUpdate = QR.UI.UpdateRoute
        local deliver, updated = nil, 0
        QR.UI.UpdateRoute = function() updated = updated + 1 end
        -- The calculator is held open on purpose. The lifecycle under test is
        -- the offer's: a search started for one offer finishing after that
        -- offer is gone.
        pc.CalculatePathAsync = function(_, mapID, _, _, _, callback)
            deliver = function()
                callback({ totalTime = 42, steps = { { type = "walk", to = "Entrance", navMapID = mapID } } })
            end
            return 1
        end
        QR.DungeonTravelOffer:Present(70001)
        local got, failure, called = nil, nil, 0
        QR.DungeonTravelOffer:Route(function(result, reason)
            called, got, failure = called + 1, result, reason
        end)
        -- Leaving the group is the ordinary way this happens.
        QR.DungeonTravelOffer:Clear()
        deliver()
        pc.CalculatePathAsync = savedAsync
        QR.UI.UpdateRoute = savedUpdate
        t:assertNil(QR.DungeonTravelOffer.pending, "the offer is gone before the result arrives")
        t:assertEqual(0, updated, "the panel shows no route for an offer that no longer stands")
        t:assertEqual(1, called, "the consumer still hears back rather than waiting forever")
        t:assertNil(got, "the consumer receives no route")
        t:assertEqual(QR.PathCalculator.FAILURE.SUPERSEDED, type(failure) == "table" and failure.reason or failure,
            "the consumer is told the request was superseded")
    end)
end)

T:run("DungeonOffer: a clear that could not finish still stops the route", function(t)
    withInstance(70001, INSTANCE, function()
        local pc = QR.PathCalculator
        local savedAsync = pc.CalculatePathAsync
        local savedUpdate = QR.UI.UpdateRoute
        local deliver, updated = nil, 0
        QR.UI.UpdateRoute = function() updated = updated + 1 end
        pc.CalculatePathAsync = function(_, mapID, _, _, _, callback)
            deliver = function() callback({ totalTime = 42, steps = { { type = "walk", navMapID = mapID } } }) end
            return 1
        end
        QR.Journey.current, QR.Journey.suspended = nil, {}
        QR.DungeonTravelOffer:Present(70001)
        QR.DungeonTravelOffer:Route()
        -- A second detour stacks above the offer's. Clear cannot give the
        -- journey back while somebody else holds it, so it keeps the offer
        -- record until the release listener fires -- and the player has left
        -- the group all the same.
        QR.Journey:Detour(QR.Journey.SOURCE.QUEST, { mapID = 84, x = 0.1, y = 0.1, title = "Elsewhere" })
        local cleared = QR.DungeonTravelOffer:Clear()
        deliver()
        pc.CalculatePathAsync = savedAsync
        QR.UI.UpdateRoute = savedUpdate
        t:assertFalse(cleared, "the clear could not finish")
        t:assertNotNil(QR.DungeonTravelOffer.pending, "so the offer record is still there on purpose")
        t:assertEqual(0, updated, "and no route is shown for the group the player has left")
        QR.Journey.current, QR.Journey.suspended = nil, {}
        QR.DungeonTravelOffer.clearWhenFree = nil
        QR.DungeonTravelOffer.holdsDetour = nil
        QR.DungeonTravelOffer.pending = nil
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

T:run("DungeonOffer: the route panel shows and hides the offer button", function(t)
    withInstance(70010, { name = "Button Halls", zoneMapID = 84, x = 0.4, y = 0.5 }, function()
        QR.UI:Initialize()
        QR.Journey:Clear()
        QR.DungeonTravelOffer:Clear()
        local button = QR.UI.frame.dungeonOfferButton
        t:assertNotNil(button, "the panel has an offer button")
        t:assertFalse(button:IsShown(), "hidden while no offer is pending")
        QR.DungeonTravelOffer:Present(70010, 21)
        t:assertTrue(button:IsShown(), "shown as soon as an offer is presented")
        t:assertNotNil(button:GetText():find("Button Halls", 1, true),
            "and it names the instance, got " .. tostring(button:GetText()))
        QR.DungeonTravelOffer:Clear()
        t:assertFalse(button:IsShown(), "hidden again once the offer is gone")
        QR.Journey:Clear()
    end)
end)

T:run("DungeonOffer: the offer button is what calls Route", function(t)
    withInstance(70011, { name = "Click Halls", zoneMapID = 84, x = 0.4, y = 0.5 }, function()
        QR.UI:Initialize()
        QR.Journey:Clear()
        local saved = QR.DungeonTravelOffer.Route
        local called = 0
        QR.DungeonTravelOffer.Route = function() called = called + 1 return true end
        QR.DungeonTravelOffer:Present(70011, 22)
        QR.UI.frame.dungeonOfferButton:GetScript("OnClick")(QR.UI.frame.dungeonOfferButton)
        QR.DungeonTravelOffer.Route = saved
        QR.DungeonTravelOffer:Clear()
        QR.Journey:Clear()
        t:assertEqual(1, called, "clicking the button routes to the offered instance")
    end)
end)

T:run("DungeonOffer: a foreign detour is not stacked under", function(t)
    withInstance(70012, { name = "Stack Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        QR.Journey:Clear()
        QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2, title = "Chosen" })
        QR.Journey:Lock(QR.Journey.SOURCE.MANUAL)
        QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5 })
        QR.DungeonTravelOffer:Present(70012, 23)
        t:assertEqual("rare_alert", QR.Journey:Get().source, "the other detour still owns the journey")
        t:assertEqual(1, #QR.Journey.suspended,
            "and no second detour was stacked under it, got " .. #QR.Journey.suspended)
        QR.Journey:Release("rare_alert")
        t:assertEqual(QR.Journey.SOURCE.MANUAL, QR.Journey:Get().source, "the player's trip comes back")
        -- The offer never held a journey, so ending an unrelated detour must not
        -- be read as the player taking over and destroy it.
        t:assertNotNil(QR.DungeonTravelOffer.pending, "and the offer is still there to click")
        QR.DungeonTravelOffer:Clear()
        t:assertNil(QR.DungeonTravelOffer.clearWhenFree, "the clear left no flag behind")
        QR.Journey:Clear()
    end)
end)

T:run("DungeonOffer: a detour ended with Resume also releases the offer", function(t)
    withInstance(70013, { name = "Resume Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        QR.Journey:Clear()
        QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2 })
        QR.Journey:Lock(QR.Journey.SOURCE.MANUAL)
        QR.DungeonTravelOffer:Present(70013, 24)
        QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5 })
        t:assertFalse(QR.DungeonTravelOffer:Clear(), "the clear is refused while the alert holds it")
        -- Resume, not Release: it is the module's documented way to end a
        -- detour, and it announced nothing, so the offer stayed for the session.
        QR.Journey:Resume("rare_alert")
        t:assertNil(QR.DungeonTravelOffer.pending,
            "ending the detour with Resume clears the offer too")
        QR.Journey:Clear()
    end)
end)

T:run("DungeonOffer: a second offer under a foreign detour retargets the suspended one", function(t)
    withInstance(70014, { name = "Alpha Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        withInstance(70015, { name = "Beta Halls", zoneMapID = 86, x = 0.6, y = 0.7 }, function()
            QR.Journey:Clear()
            QR.DungeonTravelOffer:Present(70014, 31)
            QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5 })
            QR.DungeonTravelOffer:Present(70015, 32)
            t:assertEqual("Beta Halls", QR.DungeonTravelOffer.pending.title, "the newer offer is the pending one")
            QR.Journey:Release("rare_alert")
            -- The ledger and the offer have to name the same dungeon: ending the
            -- foreign detour used to restore the arrow to the first instance
            -- while the button named the second.
            t:assertEqual("Beta Halls", QR.Journey:Get().destination.title,
                "and the restored detour points at it too, got "
                .. tostring(QR.Journey:Get().destination.title))
            QR.DungeonTravelOffer:Clear()
            QR.Journey:Clear()
        end)
    end)
end)

T:run("DungeonOffer: two foreign detours above the offer's do not destroy it", function(t)
    withInstance(70017, { name = "Nested Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        QR.Journey:Clear()
        QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2, title = "Chosen" })
        QR.Journey:Lock(QR.Journey.SOURCE.MANUAL)
        QR.DungeonTravelOffer:Present(70017, 33)
        QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5 })
        QR.Journey:Detour("world_boss", { mapID = 91, x = 0.5, y = 0.5 })
        -- The outer foreign detour ends. The offer's own detour is not current
        -- and not gone: it is the entry below the one that just came back.
        QR.Journey:Release("world_boss")
        t:assertEqual("rare_alert", QR.Journey:Get().source,
            "the inner foreign detour is current, got " .. tostring(QR.Journey:Get().source))
        t:assertNotNil(QR.DungeonTravelOffer.pending,
            "the offer survives, because its detour is still in the ledger")

        -- And the whole stack unwinds: without the offer, its detour would be
        -- unreachable and the player's locked trip would never come back.
        QR.Journey:Release("rare_alert")
        t:assertEqual(QR.Journey.SOURCE.DUNGEON_OFFER, QR.Journey:Get().source,
            "the offer's detour is current again")
        QR.DungeonTravelOffer:Clear()
        t:assertEqual(QR.Journey.SOURCE.MANUAL, QR.Journey:Get().source,
            "and clearing the offer gives the player their own trip back, got "
            .. tostring(QR.Journey:Get().source))
        QR.Journey:Clear()
    end)
end)

T:run("DungeonOffer: retargeting a suspended offer makes the offer hold that detour", function(t)
    withInstance(70018, { name = "Gamma Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        withInstance(70019, { name = "Delta Halls", zoneMapID = 86, x = 0.6, y = 0.7 }, function()
            QR.Journey:Clear()
            QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2 })
            QR.Journey:Lock(QR.Journey.SOURCE.MANUAL)
            QR.DungeonTravelOffer:Present(70018, 34)
            QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5 })
            QR.DungeonTravelOffer:Present(70019, 35)
            t:assertTrue(QR.DungeonTravelOffer.holdsDetour,
                "the retargeted entry is the offer's own detour")
            -- Read through what the flag governs rather than through the flag
            -- alone: the release listener destroys an offer that holds nothing.
            QR.Journey:Release("rare_alert")
            QR.Journey:Release(QR.Journey.SOURCE.DUNGEON_OFFER)
            t:assertNil(QR.DungeonTravelOffer.pending,
                "so ending it is read as the journey being taken over")
            QR.Journey:Clear()
        end)
    end)
end)

T:run("DungeonOffer: retargeting reports no entry rather than guessing", function(t)
    withInstance(70020, { name = "Epsilon Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        QR.Journey:Clear()
        local destination = { mapID = 86, x = 0.6, y = 0.7, title = "Epsilon Halls" }
        t:assertFalse(QR.DungeonTravelOffer:RetargetSuspended(destination),
            "an empty ledger holds no offer detour")

        -- A suspended entry that is itself a detour, from another source. A
        -- scan that asks only "is this a detour" moves somebody else's arrow.
        QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2 })
        QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5, title = "Rare" })
        QR.Journey:Detour("world_boss", { mapID = 91, x = 0.5, y = 0.5 })
        t:assertFalse(QR.DungeonTravelOffer:RetargetSuspended(destination),
            "and a suspended detour from another source is not ours to move")
        t:assertEqual("Rare", QR.Journey.suspended[2].destination.title,
            "so its destination is untouched, got "
            .. tostring(QR.Journey.suspended[2].destination.title))

        -- The ledger is a field of a module that may not be loaded. Present
        -- reads the return value, so a nil ledger must answer false rather
        -- than raise.
        local savedSuspended = QR.Journey.suspended
        QR.Journey.suspended = nil
        local ok, answered = pcall(function() return QR.DungeonTravelOffer:RetargetSuspended(destination) end)
        QR.Journey.suspended = savedSuspended
        t:assertTrue(ok, "a ledger that is not a table does not raise")
        t:assertFalse(answered, "it answers that there is no entry")
        QR.Journey:Clear()
    end)
end)

T:run("DungeonOffer: a refused clear does not reach the next group's offer", function(t)
    withInstance(70022, { name = "Left Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        withInstance(70023, { name = "Joined Halls", zoneMapID = 86, x = 0.6, y = 0.7 }, function()
            QR.Journey:Clear()
            QR.DungeonTravelOffer:Initialize()
            QR.Journey:Claim(QR.Journey.SOURCE.MANUAL, { mapID = 84, x = 0.1, y = 0.2, title = "Chosen" })
            QR.Journey:Lock(QR.Journey.SOURCE.MANUAL)
            QR.DungeonTravelOffer:Present(70022, 41)
            QR.Journey:Detour("rare_alert", { mapID = 90, x = 0.5, y = 0.5 })

            -- The player leaves the first group while the alert holds the
            -- journey. The clear cannot finish now, so it is remembered.
            QR.DungeonTravelOffer.frame:GetScript("OnEvent")(QR.DungeonTravelOffer.frame, "GROUP_LEFT")
            t:assertTrue(QR.DungeonTravelOffer.clearWhenFree,
                "the clear for the group that was left is remembered")

            -- A second group takes them, seconds later.
            QR.DungeonTravelOffer:Present(70023, 42)
            t:assertEqual("Joined Halls", QR.DungeonTravelOffer.pending.title,
                "the new group's offer is the pending one")

            -- The alert ends. The remembered clear belongs to the group the
            -- player already left, not to this one.
            QR.Journey:Release("rare_alert")
            t:assertNotNil(QR.DungeonTravelOffer.pending,
                "the new offer survives the foreign detour ending")
            t:assertEqual(QR.Journey.SOURCE.DUNGEON_OFFER, QR.Journey:Get().source,
                "and its detour is still in force, got " .. tostring(QR.Journey:Get().source))

            QR.DungeonTravelOffer:Clear()
            QR.Journey:Clear()
        end)
    end)
end)

T:run("DungeonOffer: a step refused on the offer's route is refused for the dungeon", function(t)
    withInstance(70021, { name = "Refusal Halls", zoneMapID = 85, x = 0.4, y = 0.5 }, function()
        local pc = QR.PathCalculator
        local queue = {}
        local savedAfter = C_Timer.After
        C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
        pc:ClearExcludedEdges()
        QR.Journey:Clear()
        QR.UI:Initialize()

        -- Whatever the router calculated last, before the offer's own search.
        pc:CalculatePath(84, 0.1, 0.2)
        QR.DungeonTravelOffer:Present(70021, 40)
        local routed
        QR.DungeonTravelOffer:Route(function(result) routed = result end)
        while #queue > 0 and not routed do table.remove(queue, 1)() end
        while #queue > 0 do table.remove(queue, 1)() end
        C_Timer.After = savedAfter

        if not (routed and routed.steps and routed.steps[1]) then
            -- Assert what the branch was entered for, not something weaker: a
            -- route that exists with no steps must not report a pass here.
            t:assertNotNil(routed and routed.steps and routed.steps[1],
                "the offer produced a route with a step to refuse")
            QR.DungeonTravelOffer:Clear()
            QR.Journey:Clear()
            return
        end

        -- The row on screen, built by the panel from the route the offer
        -- displayed. The button reads the destination off that route.
        local stepFrame = QR.UI:CreateStepLabel(1, routed.steps[1], 0, "pending")
        t:assertNotNil(stepFrame.rejectButton, "the row has a reject button")
        stepFrame.rejectButton:GetScript("OnClick")(stepFrame.rejectButton)

        local pair = pc:StepEdgePairs(routed.steps[1])[1]
        t:assertNotNil(pair, "the row stands for at least one graph hop")

        -- Routing to the dungeon again must see the refusal, and routing
        -- anywhere else must not. A refusal stamped from the global instead of
        -- from the displayed route lands on the journey that happened to be
        -- current, which after an asynchronous search is the one from before it.
        pc:CalculatePath(85, 0.4, 0.5)
        t:assertTrue(pc:IsEdgeExcluded(pair.from, pair.to),
            "the dungeon route sees the step the player refused on it")
        pc:CalculatePath(84, 0.1, 0.2)
        t:assertFalse(pc:IsEdgeExcluded(pair.from, pair.to),
            "and the route that was current before the search does not")

        pc:ClearExcludedEdges()
        QR.DungeonTravelOffer:Clear()
        QR.Journey:Clear()
    end)
end)

T:run("DungeonOffer: the offer button does not sit on top of another control", function(t)
    withInstance(70016, { name = "Overlap Halls", zoneMapID = 84, x = 0.4, y = 0.5 }, function()
        QR.UI:Initialize()
        QR.Journey:Clear()
        QR.DungeonTravelOffer:Present(70016, 33)
        local frame = QR.UI.frame
        local offer = MockWoW:ComputeFrameBounds(frame.dungeonOfferButton)
        for _, name in ipairs({ "multiRouteButton", "currencyButton", "phaseButton" }) do
            local other = frame[name] and MockWoW:ComputeFrameBounds(frame[name])
            if other then
                t:assertTrue(offer.left >= other.right or offer.right <= other.left,
                    "the offer button clears " .. name .. ": offer [" .. offer.left .. "," .. offer.right
                    .. "] vs " .. name .. " [" .. other.left .. "," .. other.right .. "]")
            end
        end
        QR.DungeonTravelOffer:Clear()
        QR.Journey:Clear()
    end)
end)
