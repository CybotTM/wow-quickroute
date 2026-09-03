-- The addon table is private unless debug mode is on, so it is reached the way
-- the frames themselves hold it: as an upvalue of a script the addon installed.
local function FindQR()
  local kinds = { "OnUpdate", "OnEvent", "OnShow", "OnClick", "OnHide" }
  local frame = EnumerateFrames()
  while frame do
    for _, kind in ipairs(kinds) do
      local handler = frame.GetScript and frame:GetScript(kind)
      if handler then
        local i = 1
        while true do
          local name, value = debug.getupvalue(handler, i)
          if not name then break end
          if type(value) == "table"
            and type(value.PathCalculator) == "table"
            and type(value.PathCalculator.BuildGraph) == "function" then
            return value
          end
          i = i + 1
        end
      end
    end
    frame = EnumerateFrames(frame)
  end
end

-- The teleport graph is built once at load, before the character's collection
-- is known here, so it holds no player teleport edges. Rescanning and rebuilding
-- is what the addon itself does when the collection changes.
local function RebuildQuickRouteGraph()
  local QR = FindQR()
  if not QR then return nil end
  if QR.PlayerInventory and QR.PlayerInventory.ScanAll then QR.PlayerInventory:ScanAll() end
  if QR.PathCalculator then
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    QR.PathCalculator:BuildGraph()
  end
  return QR
end

QR_DOC.FindQR = FindQR
QR_DOC.RebuildGraph = RebuildQuickRouteGraph
