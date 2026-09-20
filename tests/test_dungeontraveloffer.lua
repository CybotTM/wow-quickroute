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

T:run("DungeonOffer: routing goes through the public contract and sets no waypoint", function(t)
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
        t:assertNotNil(got, "the route arrives through the routing contract")
        t:assertEqual(1, got.apiVersion, "it is the public contract, not internal state")
        t:assertEqual(0, touched, "offering travel set no waypoint")
        t:assertEqual(1, updated, "the route is shown rather than acted on")
    end)
end)

T:run("DungeonOffer: routing without an offer does nothing", function(t)
    QR.DungeonTravelOffer:Clear()
    t:assertFalse(QR.DungeonTravelOffer:Route(), "no offer, no request")
end)
