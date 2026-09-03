-- The simulator has no user-waypoint store, so the map-pin API is backed by one
-- here. This is the same contract the client offers (HasUserWaypoint /
-- GetUserWaypoint / SetUserWaypoint over a UiMapPoint); the route itself is
-- calculated entirely by the addon.
local pin = nil
C_Map.SetUserWaypoint = function(point) pin = point end
C_Map.GetUserWaypoint = function() return pin end
C_Map.HasUserWaypoint = function() return pin ~= nil end
C_Map.ClearUserWaypoint = function() pin = nil end
if not UiMapPoint then UiMapPoint = {} end
if not UiMapPoint.CreateFromCoordinates then
  UiMapPoint.CreateFromCoordinates = function(uiMapID, x, y, z)
    return { uiMapID = uiMapID, position = CreateVector2D and CreateVector2D(x, y) or { x = x, y = y } }
  end
end
