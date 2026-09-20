local T, QR = ...

-- A large catalogue hides a silent guess as well as it hides a silent omission.
-- These tests do not claim the catalogue is fully sourced. They pin what is
-- marked, refuse an invented marker, and count what is still unmarked so the
-- unmarked set cannot grow without somebody noticing.

T:run("Provenance: the vocabulary is closed", function(t)
    for _, value in ipairs({ "surveyed", "estimated", "reference", "unverified" }) do
        t:assertTrue(QR.Provenance:IsKnown(value), value .. " is a known origin")
    end
    t:assertFalse(QR.Provenance:IsKnown("probably fine"), "an invented origin is refused")
    t:assertFalse(QR.Provenance:IsKnown(nil), "an absent origin is not a known one")
end)

local function collectMarked()
    local marked, bad = {}, {}
    local function check(where, record)
        if type(record) ~= "table" then return end
        if record.provenance ~= nil then
            marked[#marked + 1] = { where = where, value = record.provenance }
            if not QR.Provenance:IsKnown(record.provenance) then
                bad[#bad + 1] = where .. " = " .. tostring(record.provenance)
            end
        end
    end
    for name, city in pairs(QR.CAPITAL_CITIES or {}) do check("city " .. name, city) end
    for serviceType, points in pairs(QR.ServicePOIs or {}) do
        for index, point in ipairs(points) do check(serviceType .. " #" .. index, point) end
    end
    for hubName, hub in pairs((QR.PortalHubs or {})) do
        for index, portal in ipairs(hub.portals or {}) do
            check("portal " .. hubName .. " #" .. index, portal)
        end
    end
    return marked, bad
end

T:run("Provenance: every marked record uses a word from the vocabulary", function(t)
    local marked, bad = collectMarked()
    t:assertEqual(0, #bad, "no record carries an invented origin: " .. table.concat(bad, ", "))
    t:assertGreaterThan(#marked, 0, "records do carry an origin, got " .. #marked)
end)

T:run("Provenance: a doubtful coordinate is marked rather than described in a comment", function(t)
    -- Both Silvermoon portal landings carry the old map 110 coordinates. The
    -- comment said so and nothing could read the comment.
    local unverified = 0
    for _, hub in pairs(QR.PortalHubs or {}) do
        for _, portal in ipairs(hub.portals or {}) do
            if portal.provenance == QR.Provenance.UNVERIFIED then unverified = unverified + 1 end
        end
    end
    t:assertEqual(2, unverified,
        "the two unverified portal landings are marked as such, got " .. unverified)
end)

T:run("Provenance: the shared Silvermoon position is marked as surveyed", function(t)
    t:assertEqual(QR.Provenance.SURVEYED, QR.CAPITAL_CITIES["Silvermoon City"].provenance,
        "the city entry states that its coordinate was surveyed")
end)

-- The coverage gate. This number is a measurement of today's tree, not a
-- target: it may fall as records are sourced and it must not rise. A rise means
-- a coordinate was added without saying where it came from.
local UNMARKED_SERVICE_POINTS = 33

T:run("Provenance: the unmarked service points are counted and pinned", function(t)
    local unmarked = 0
    for _, points in pairs(QR.ServicePOIs or {}) do
        for _, point in ipairs(points) do
            if point.provenance == nil then unmarked = unmarked + 1 end
        end
    end
    t:assertEqual(UNMARKED_SERVICE_POINTS, unmarked,
        "service points without a stated origin, got " .. unmarked
        .. ". Lower the pin when you source one; never raise it to make this pass.")
end)
