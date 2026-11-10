#!/usr/bin/env lua5.1
-------------------------------------------------------------------------------
-- make_trace_fixture.lua
-- Produce a SavedVariables file with a diagnostic trace, written by the addon
-- itself: the mock client is installed, the addon is loaded through its TOC,
-- the trace is turned on through the setting, and a short play session is
-- driven through the same entry points the client calls. The file is then
-- written in the format the client uses for SavedVariables.
--
-- tests/test_export_trace.py runs it for both flavors and feeds the result to
-- scripts/export_trace.py.
--
-- Usage: lua5.1 tests/make_trace_fixture.lua <retail|forever> <out.lua> [fill]
--   fill: repeat the session until the buffer holds this many entries (for
--   measuring the file size at the cap)
-------------------------------------------------------------------------------

local flavor, outPath, fill = arg[1], arg[2], tonumber(arg[3])
if (flavor ~= "retail" and flavor ~= "forever") or not outPath then
    io.stderr:write("usage: lua5.1 tests/make_trace_fixture.lua <retail|forever> <out.lua> [fill]\n")
    os.exit(2)
end

local scriptDir = (debug.getinfo(1, "S").source:gsub("^@", "")):match("(.*/)") or "tests/"
package.path = scriptDir .. "?.lua;" .. package.path

local MockWoW = require("mock_wow_api")
if flavor == "forever" then MockWoW:UseForever() end
MockWoW:Install()
local AddonLoader = require("addon_loader")
local QR = AddonLoader:Load(MockWoW, {
    addonDir = scriptDir .. "../QuickRoute/",
    quiet = true,
    toc = flavor == "forever" and "QuickRoute_Camelot.toc" or "QuickRoute.toc",
})
if not AddonLoader:AllFilesLoaded() then
    io.stderr:write("addon failed to load: " .. AddonLoader:GetStatus() .. "\n")
    os.exit(1)
end
-- The addon prints while it loads; the caller only wants the file.
local realPrint = print
_G.print = function() end
AddonLoader:FireAddonLoaded(MockWoW)
AddonLoader:FirePlayerLogin(MockWoW)

local cfg = MockWoW.config
cfg.baseTime = 1000

-- What the settings checkbox does.
QR.db.diagnosticTrace = true
QR.Diagnostics:ApplyTraceSetting()
QR.db.autoDestination = true

local function session()
    -- More than two seconds before the open: outside its look-back window.
    cfg.baseTime = cfg.baseTime + 1
    MockWoW:FireEvent("QUEST_DETAIL")
    cfg.baseTime = cfg.baseTime + 3
    MockWoW:FireEvent("GOSSIP_SHOW", "")
    cfg.baseTime = cfg.baseTime + 0.5
    MockWoW:FireEvent("QUEST_ACCEPTED", 4711)
    cfg.baseTime = cfg.baseTime + 0.5
    if QR.MainFrame.frame then QR.MainFrame.frame:Hide() end
    QR.MainFrame.isShowing = false
    -- What WaypointIntegration's SUPER_TRACKING_CHANGED handler calls.
    QR.WaypointIntegration:OnWaypointChanged("SUPER_TRACKING_CHANGED")
    cfg.baseTime = cfg.baseTime + 5
    QR.MainFrame:Hide("close-button")
end

session()
if fill then
    -- A full session per round computes a route each time, which takes
    -- minutes at 20000 entries. The rounds after the first replay the entries
    -- the first one recorded through Diagnostics:Trace, the same store path,
    -- so the size per entry is that of a real session.
    local recorded = QR.Diagnostics:GetTraceEntries()
    local i = 0
    -- Stops at whichever bound comes first: the entry cap or the byte bound
    -- (once the byte bound drops an entry, the count stops growing).
    while QR.db.trace.n < fill and QR.db.trace.n < QR.Diagnostics.TRACE_CAP
        and (QR.db.trace.dropped or 0) == 0 do
        local e = recorded[(i % #recorded) + 1]
        cfg.baseTime = cfg.baseTime + 0.25
        QR.Diagnostics:Trace(e.c, e.m, e.f, e.l)
        i = i + 1
    end
    -- One more session so the buffer has wrapped.
    session()
end
QR.db.diagnosticTrace = false
QR.Diagnostics:ApplyTraceSetting()

-------------------------------------------------------------------------------
-- SavedVariables writer, in the client's layout: one assignment per variable,
-- tab indentation, ["key"] = value, and array items with a -- [n] comment.
-------------------------------------------------------------------------------

local function quote(s)
    return (string.format("%q", s):gsub("\\\n", "\\n"))
end

local function serialize(out, value, indent)
    local t = type(value)
    if t == "string" then
        out[#out + 1] = quote(value)
    elseif t == "number" then
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            out[#out + 1] = string.format("%d", value)
        else
            out[#out + 1] = string.format("%.14g", value)
        end
    elseif t == "boolean" then
        out[#out + 1] = tostring(value)
    elseif t == "table" then
        out[#out + 1] = "{\n"
        local n = #value
        for i = 1, n do
            out[#out + 1] = indent .. "\t"
            serialize(out, value[i], indent .. "\t")
            out[#out + 1] = ", -- [" .. i .. "]\n"
        end
        local keys = {}
        for k in pairs(value) do
            if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b)
            if type(a) ~= type(b) then return type(a) == "number" end
            return a < b
        end)
        for _, k in ipairs(keys) do
            local v = value[k]
            if type(v) ~= "function" then
                out[#out + 1] = indent .. "\t[" .. (type(k) == "string" and quote(k) or tostring(k)) .. "] = "
                serialize(out, v, indent .. "\t")
                out[#out + 1] = ",\n"
            end
        end
        out[#out + 1] = indent .. "}"
    else
        out[#out + 1] = "nil"
    end
end

local out = { "\nQuickRouteDB = " }
serialize(out, _G.QuickRouteDB, "")
out[#out + 1] = "\n"
local handle = assert(io.open(outPath, "w"))
handle:write(table.concat(out))
handle:close()
realPrint(string.format("%s: %d trace entries, %d dropped", outPath, QR.db.trace.n, QR.db.trace.dropped or 0))
