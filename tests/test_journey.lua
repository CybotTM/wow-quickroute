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
