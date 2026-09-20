-- Journey.lua
-- Who owns the destination right now.
--
-- A player runs several addons that each believe they may set the arrow: a
-- guide step, a rare alert, a manually chosen trip, a dungeon group that was
-- just accepted. They are different intents and they are not interchangeable,
-- but until now the last writer won and the player's own trip was gone.
--
-- A journey therefore has an owner and, optionally, a lock. A different source
-- cannot replace a locked journey; it can ask for a detour, which suspends the
-- journey and restores it afterwards. Nothing here sets a waypoint: this module
-- decides whose destination is current, and the modules that act read it.
local ADDON_NAME, QR = ...
local type, tostring = type, tostring

local Journey = { current = nil, suspended = {} }
QR.Journey = Journey

-- The sources QuickRoute itself uses. A consumer of the routing contract may
-- name its own; the string is an identity, not a permission.
Journey.SOURCE = {
    MANUAL = "manual",
    QUEST = "quest",
    DUNGEON_OFFER = "dungeon_offer",
    EXTERNAL = "external",
}

local function Destination(destination)
    if type(destination) ~= "table" then return nil end
    if type(destination.mapID) ~= "number" then return nil end
    return {
        mapID = destination.mapID,
        x = destination.x,
        y = destination.y,
        title = destination.title,
    }
end

--- Take the journey for a source.
-- Refused while another source holds a locked journey, so the player's own trip
-- is not replaced by an alert that happened to fire.
-- @param source string Who is asking
-- @param destination table {mapID, x, y, title}
-- @return boolean Whether this source now owns the journey
function Journey:Claim(source, destination)
    local target = Destination(destination)
    if type(source) ~= "string" or not target then return false end
    if self.current and self.current.locked and self.current.source ~= source then
        QR:Debug("Journey: " .. source .. " refused, " .. tostring(self.current.source) .. " holds a locked journey")
        return false
    end
    -- A detour is unlocked, so consulting the lock alone let a third source
    -- claim straight through the lock of the journey the detour suspended. That
    -- journey then sat on the stack with no way back and its owner could no
    -- longer release it.
    if self.current and self.current.detour and self.current.source ~= source then
        QR:Debug("Journey: " .. source .. " refused, a detour by " .. tostring(self.current.source) .. " is in force")
        return false
    end
    -- The detour's own owner may change where it goes, and it stays a detour:
    -- dropping the flag here would strand the journey underneath it just as
    -- surely. Retarget is the call that says this explicitly.
    local detour = self.current and self.current.detour and self.current.source == source or nil
    self.current = { source = source, destination = target, locked = false, detour = detour }
    return true
end

--- Protect the current journey from being replaced by another source.
function Journey:Lock(source)
    if not self.current or self.current.source ~= source then return false end
    self.current.locked = true
    return true
end

function Journey:Unlock(source)
    if not self.current or self.current.source ~= source then return false end
    self.current.locked = false
    return true
end

--- Suspend the current journey and take over temporarily.
-- A detour is how a rare alert or a dungeon offer interrupts a locked trip
-- without destroying it.
-- @return boolean Whether the detour was taken
function Journey:Detour(source, destination)
    local target = Destination(destination)
    if type(source) ~= "string" or not target then return false end
    if self.current then
        self.suspended[#self.suspended + 1] = self.current
    end
    self.current = { source = source, destination = target, locked = false, detour = true }
    return true
end

--- Change where the current journey goes, keeping who owns it and whether it
--- is a detour.
-- A second interruption from the same source replaces the first rather than
-- stacking on it: two detours would need two Resume calls to give the player
-- their own trip back, and the first would restore the earlier interruption.
-- @return boolean Whether the destination was changed
function Journey:Retarget(source, destination)
    local target = Destination(destination)
    if not self.current or self.current.source ~= source or not target then return false end
    self.current.destination = target
    return true
end

--- End a detour and restore what it interrupted.
-- @return table|nil The restored journey, or nil when there was nothing to
--   restore
function Journey:Resume(source)
    if not self.current or self.current.source ~= source or not self.current.detour then return nil end
    self.current = table.remove(self.suspended)
    -- A copy, like Get returns. Handing back the live record let the caller
    -- rewrite the owner and the lock without going through Claim.
    return self:Get()
end

--- Give up the journey. Only its owner may.
function Journey:Release(source)
    if not self.current or self.current.source ~= source then return false end
    if self.current.detour then
        self.current = table.remove(self.suspended)
        return true
    end
    self.current = nil
    return true
end

--- The destination in force, with who owns it.
function Journey:Get()
    if not self.current then return nil end
    return {
        source = self.current.source,
        destination = Destination(self.current.destination),
        locked = self.current.locked == true,
        detour = self.current.detour == true,
    }
end

--- Forget everything. Used when a character logs in or the player clears.
function Journey:Clear()
    self.current = nil
    self.suspended = {}
end
