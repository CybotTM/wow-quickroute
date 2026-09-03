-- Documentation screenshots.
--
-- The character owns a plausible collection rather than every teleport in the
-- game: eight is what a well-travelled character actually carries, it fills the
-- card grid without a half-row, and it leaves the quick-teleport list short
-- enough to end cleanly instead of being clipped mid-row.
--
-- Nothing here fakes a name or an icon. Those come from the simulator's own
-- item, spell and map tables, so what the screenshots show is what the client
-- shows.

local TOYS = {
  [110560] = true, -- Garrison Hearthstone            -> Garrison
  [128353] = true, -- Admiral's Compass               -> Garrison Shipyard
  [230850] = true, -- Delve-O-Bot 7001                -> Random Delve
  [37863]  = true, -- Direbrew's Remote               -> Blackrock Mountain
  [129276] = true, -- Beginner's Guide                -> Azsuna
  [202046] = true, -- Lucky Tortollan Charm           -> Stormsong Valley
  [243056] = true, -- Delver's Mana-Bound Ethergate   -> Dornogal
  [253629] = true, -- Personal Key to the Arcantina   -> Silvermoon City
}
local BAG = { 6948 } -- Hearthstone, the one ordinary item

-- Toys
local origHasToy = PlayerHasToy
PlayerHasToy = function(id) return TOYS[id] == true end
if C_ToyBox then
  C_ToyBox.IsToyUsable = function(id) return TOYS[id] == true end
end

-- The bag scan is left to do its real work; it is simply given a bag.
if C_Container then
  local origSlots, origItemID = C_Container.GetContainerNumSlots, C_Container.GetContainerItemID
  C_Container.GetContainerNumSlots = function(bag)
    if bag == 0 then return #BAG end
    return origSlots and origSlots(bag) or 0
  end
  C_Container.GetContainerItemID = function(bag, slot)
    if bag == 0 then return BAG[slot] end
    return origItemID and origItemID(bag, slot) or nil
  end
end

-- The overlay buttons of the secure frames are positioned by an OnUpdate
-- handler that only acts after 0.1 s of accumulated elapsed time. The three
-- 16 ms ticks of the screenshot path never reach that, so the positioner is
-- called directly once the view is open.
local function RepositionQuickRouteOverlays()
  local frame = EnumerateFrames()
  while frame do
    local handler = frame.GetScript and frame:GetScript("OnUpdate")
    if handler then
      local i = 1
      while true do
        local name = debug.getupvalue(handler, i)
        if not name then break end
        local _, value = debug.getupvalue(handler, i)
        local drives = name == "activeOverlays"
          or (type(value) == "table" and type(value.RefreshButtons) == "function")
        if drives then pcall(handler, frame, 1.0) break end
        i = i + 1
      end
    end
    frame = EnumerateFrames(frame)
  end
end

-- Blizzard frames that sit over or behind the addon's own windows in this
-- layout. The panels are semi-transparent, so a tracker behind one reads
-- through it; hiding them is the difference between a legible screenshot and
-- one where two interfaces overlap. Nothing of QuickRoute is hidden.
local function HideOverlapping(names)
  for _, name in ipairs(names) do
    local f = _G[name]
    if f and f.Hide then f:Hide() end
  end
end

local function OpenView(action)
  C_Timer.After(0, function()
    if PTR_IssueReporter then PTR_IssueReporter:Hide() end
    action()
    RepositionQuickRouteOverlays()
  end)
end

QR_DOC = {
  OpenView = OpenView,
  Reposition = RepositionQuickRouteOverlays,
  HideOverlapping = HideOverlapping,
}
