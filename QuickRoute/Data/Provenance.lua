-- Provenance.lua
-- Where a coordinate came from.
--
-- A large catalogue can hide silent omissions and silent guesses equally well.
-- Two records that look the same in the data can be a position somebody stood
-- on and photographed, and a number copied from an older version of the map.
-- Routing treats them identically; a reviewer and a player should not have to.
--
-- The vocabulary is small on purpose, and a record carries it only where it is
-- actually known. An unmarked record is not claimed to be surveyed: it is
-- unmarked, which the coverage test in tests/test_provenance.lua counts and
-- pins so the unmarked set cannot grow unnoticed.

-- What that count covers, stated here because the number reads as if it
-- covered everything: service points, capital cities and portal hubs. Five
-- other files carry coordinates and are not counted -- DestinationCatalog,
-- FlightPoints, DungeonEntrances, TravelShortcuts and HearthstoneLocations.
-- The pin is therefore a statement about three sources, not about the
-- catalogue as a whole, and a new data file joins the uncounted set silently.
--
-- HearthstoneLocations carries its own words for the same idea, `source =
-- "INN_DATABASE"` and `isApproximate`, which are REFERENCE and ESTIMATED under
-- another name. Nothing reconciles the two vocabularies today.
local ADDON_NAME, QR = ...

QR.Provenance = {
    -- Somebody was there and recorded the position, with a source to check.
    SURVEYED = "surveyed",
    -- Derived rather than observed: a zone centre, an interpolation, a guess
    -- that is good enough to route with and must not be presented as exact.
    ESTIMATED = "estimated",
    -- Taken from a catalogue about the world rather than from the client.
    REFERENCE = "reference",
    -- Known to be doubtful. Usually a value carried over from an older map.
    UNVERIFIED = "unverified",
}

QR.Provenance.VALUES = {
    [QR.Provenance.SURVEYED] = true,
    [QR.Provenance.ESTIMATED] = true,
    [QR.Provenance.REFERENCE] = true,
    [QR.Provenance.UNVERIFIED] = true,
}

--- Whether a value is one of the four the vocabulary allows.
function QR.Provenance:IsKnown(value)
    return self.VALUES[value] == true
end
