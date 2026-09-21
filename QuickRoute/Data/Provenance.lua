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
