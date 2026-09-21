local T, QR = ...

-- A guide step, a rare alert, a manual trip and an accepted dungeon group are
-- different intents. The last writer used to win; now the destination has an
-- owner, and an interruption is a detour rather than a replacement.

local S = QR.Journey.SOURCE
local A = { mapID = 84, x = 0.1, y = 0.2, title = "Chosen" }
local B = { mapID = 85, x = 0.3, y = 0.4, title = "Alert" }

T:run("Journey: an unlocked journey may be taken over", function(t)
    QR.Journey:Clear()
    t:assertTrue(QR.Journey:Claim(S.MANUAL, A), "the first source takes the journey")
    t:assertTrue(QR.Journey:Claim(S.EXTERNAL, B), "an unlocked journey may change hands")
    t:assertEqual(S.EXTERNAL, QR.Journey:Get().source, "the new source owns it")
    QR.Journey:Clear()
end)

T:run("Journey: a locked journey cannot be replaced by another source", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    t:assertTrue(QR.Journey:Lock(S.MANUAL), "the owner may lock it")
    t:assertFalse(QR.Journey:Claim(S.EXTERNAL, B), "another source is refused")
    t:assertEqual(84, QR.Journey:Get().destination.mapID, "the player's destination stands")
    t:assertTrue(QR.Journey:Claim(S.MANUAL, B), "the owner may still change its own destination")
    t:assertFalse(QR.Journey:Lock(S.EXTERNAL), "a source that does not own it cannot lock it")
    QR.Journey:Clear()
end)

T:run("Journey: a detour suspends the trip and gives it back", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    QR.Journey:Lock(S.MANUAL)
    t:assertTrue(QR.Journey:Detour(S.DUNGEON_OFFER, B), "a detour interrupts even a locked journey")
    local during = QR.Journey:Get()
    t:assertEqual(S.DUNGEON_OFFER, during.source, "the detour owns the destination while it lasts")
    t:assertTrue(during.detour, "and says it is a detour")
    local restored = QR.Journey:Resume(S.DUNGEON_OFFER)
    t:assertNotNil(restored, "the interrupted journey comes back")
    t:assertEqual(84, QR.Journey:Get().destination.mapID, "with the destination the player chose")
    t:assertTrue(QR.Journey:Get().locked, "and still locked")
    QR.Journey:Clear()
end)

T:run("Journey: only the owner may release it", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    t:assertFalse(QR.Journey:Release(S.QUEST), "a stranger cannot clear the journey")
    t:assertNotNil(QR.Journey:Get(), "so it is still there")
    t:assertTrue(QR.Journey:Release(S.MANUAL), "the owner can")
    t:assertNil(QR.Journey:Get(), "and then there is none")
end)

T:run("Journey: a destination without a map is refused", function(t)
    QR.Journey:Clear()
    t:assertFalse(QR.Journey:Claim(S.MANUAL, { x = 0.5, y = 0.5 }), "no map, no journey")
    t:assertFalse(QR.Journey:Claim(S.MANUAL, nil), "no destination, no journey")
    t:assertNil(QR.Journey:Get(), "nothing was recorded")
end)

T:run("Journey: a manually chosen destination is claimed and locked", function(t)
    QR.Journey:Clear()
    QR.POIRouting:RouteToMapPosition(84, 0.55, 0.65)
    local held = QR.Journey:Get()
    t:assertNotNil(held, "routing by hand takes the journey")
    t:assertEqual(S.MANUAL, held.source, "the player owns it")
    t:assertTrue(held.locked, "and it is protected from other sources")
    QR.Journey:Clear()
end)

T:run("Journey: a dungeon offer detours rather than replacing the trip", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    QR.Journey:Lock(S.MANUAL)
    local dd = QR.DungeonData
    local saved = dd.instances[70002]
    dd.instances[70002] = { name = "Offer Halls", zoneMapID = 85, x = 0.5, y = 0.5 }
    QR.DungeonTravelOffer:Present(70002)
    t:assertEqual(S.DUNGEON_OFFER, QR.Journey:Get().source, "the offer takes over temporarily")
    QR.DungeonTravelOffer:Clear()
    t:assertEqual(S.MANUAL, QR.Journey:Get().source, "clearing the offer gives the trip back")
    t:assertEqual(84, QR.Journey:Get().destination.mapID, "with the destination the player chose")
    dd.instances[70002] = saved
    QR.Journey:Clear()
end)

T:run("Journey: a second dungeon offer replaces the first detour instead of stacking", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    QR.Journey:Lock(S.MANUAL)
    local dd = QR.DungeonData
    local first, second = dd.instances[70003], dd.instances[70004]
    dd.instances[70003] = { name = "First Halls", zoneMapID = 85, x = 0.5, y = 0.5 }
    dd.instances[70004] = { name = "Second Halls", zoneMapID = 86, x = 0.6, y = 0.6 }
    QR.DungeonTravelOffer:Present(70003)
    QR.DungeonTravelOffer:Present(70004)
    t:assertEqual(86, QR.Journey:Get().destination.mapID, "the newer offer is the one in force")
    t:assertTrue(QR.Journey:Get().detour, "it is still a detour")
    QR.DungeonTravelOffer:Clear()
    t:assertEqual(S.MANUAL, QR.Journey:Get().source, "one clear gives the player's own trip back")
    t:assertEqual(84, QR.Journey:Get().destination.mapID, "with the destination they chose")
    dd.instances[70003], dd.instances[70004] = first, second
    QR.Journey:Clear()
end)

T:run("Journey: a lock survives a detour, and nothing is stranded", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    QR.Journey:Lock(S.MANUAL)
    QR.Journey:Detour(S.DUNGEON_OFFER, B)
    -- The detour itself is unlocked, so consulting only the current entry let a
    -- third source claim straight through the lock and strand the trip.
    t:assertFalse(QR.Journey:Claim(S.QUEST, { mapID = 90, x = 0.1, y = 0.1 }),
        "a third source cannot claim past a locked journey that a detour suspended")
    t:assertEqual(S.DUNGEON_OFFER, QR.Journey:Get().source, "the detour still owns the destination")
    t:assertEqual(1, #QR.Journey.suspended, "exactly one journey is suspended")
    QR.Journey:Release(S.DUNGEON_OFFER)
    t:assertEqual(S.MANUAL, QR.Journey:Get().source, "the player's trip comes back")
    t:assertEqual(0, #QR.Journey.suspended, "and nothing is left on the stack")
    QR.Journey:Clear()
end)

T:run("Journey: Resume hands back a copy, not the record", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    QR.Journey:Lock(S.MANUAL)
    QR.Journey:Detour(S.DUNGEON_OFFER, B)
    local restored = QR.Journey:Resume(S.DUNGEON_OFFER)
    restored.source = S.QUEST
    restored.locked = false
    restored.destination.mapID = 999
    local held = QR.Journey:Get()
    t:assertEqual(S.MANUAL, held.source, "the owner cannot be rewritten through the returned table")
    t:assertTrue(held.locked, "nor the lock")
    t:assertEqual(84, held.destination.mapID, "nor the destination")
    QR.Journey:Clear()
end)

T:run("Journey: the detour's own owner claiming again does not strand the trip", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    QR.Journey:Lock(S.MANUAL)
    QR.Journey:Detour(S.DUNGEON_OFFER, B)
    -- Claim, not Retarget. Dropping the detour flag here left the locked trip
    -- on the stack with nothing able to pop it.
    t:assertTrue(QR.Journey:Claim(S.DUNGEON_OFFER, { mapID = 86, x = 0.6, y = 0.6 }),
        "the detour owner may move its own destination")
    t:assertTrue(QR.Journey:Get().detour, "and it is still a detour")
    QR.Journey:Release(S.DUNGEON_OFFER)
    t:assertEqual(S.MANUAL, QR.Journey:Get().source, "so the player's trip comes back")
    t:assertEqual(0, #QR.Journey.suspended, "with nothing left on the stack")
    QR.Journey:Clear()
end)

T:run("Journey: routing by hand is refused while somebody else's detour is in force", function(t)
    QR.Journey:Clear()
    QR.Journey:Claim(S.MANUAL, A)
    QR.Journey:Lock(S.MANUAL)
    QR.Journey:Detour(S.DUNGEON_OFFER, B)
    local savedDB = QR.db
    QR.db = QR.db or {}
    QR.db.lastDestination = nil
    -- The ledger said the detour owns the arrow and POIRouting routed anyway,
    -- so the record and the addon disagreed about where the player was going.
    QR.POIRouting:RouteToMapPosition(86, 0.55, 0.65)
    t:assertEqual(S.DUNGEON_OFFER, QR.Journey:Get().source, "the detour still owns the journey")
    t:assertNil(QR.db.lastDestination, "and no destination was written behind its back")
    QR.Journey:Release(S.DUNGEON_OFFER)
    QR.Journey:Release(S.MANUAL)
    QR.POIRouting:RouteToMapPosition(86, 0.55, 0.65)
    t:assertEqual(86, QR.db.lastDestination and QR.db.lastDestination.mapID,
        "and routing works again once nothing holds the journey")
    QR.db = savedDB
    QR.Journey:Clear()
end)
