-- Diagnostics.lua
-- Records Lua errors and teleport-list rebuilds into SavedVariables.
--
-- Both answer questions that only exist while the game is running and that a
-- screenshot of the error frame answers badly: what exactly threw, and what the
-- teleport panel believed it had at the moment it drew an empty list. Keeping
-- them on disk means a report is "reproduce it once and reload" rather than a
-- transcription.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, pcall, tostring = pairs, ipairs, pcall, tostring
local string_format = string.format
local table_concat, table_remove = table.concat, table.remove
local date = date

QR.Diagnostics = {}
local Diagnostics = QR.Diagnostics

-- Ring buffers. Small, because these live in SavedVariables and are rewritten
-- whole on every logout.
local MAX_ERRORS = 40
local MAX_REFRESHES = 60

local function push(list, entry, cap)
    list[#list + 1] = entry
    while #list > cap do
        table_remove(list, 1)
    end
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--- Record one Lua error.
function Diagnostics:RecordError(message)
    if not QR.db then return end
    QR.db.errors = QR.db.errors or {}
    local text = tostring(message)
    -- Collapse a repeat rather than filling the buffer with one error.
    local last = QR.db.errors[#QR.db.errors]
    if last and last.message == text then
        last.count = (last.count or 1) + 1
        last.seen = date("%Y-%m-%d %H:%M:%S")
        return
    end
    push(QR.db.errors, {
        message = text,
        stack = debugstack and debugstack(2, 12, 0) or nil,
        seen = date("%Y-%m-%d %H:%M:%S"),
        count = 1,
    }, MAX_ERRORS)
end

--- Record the outcome of one teleport-list rebuild.
-- The panel keeps its filtered result on itself, so this reads the counts after
-- the fact rather than reaching into RefreshList.
function Diagnostics:RecordRefresh()
    if not QR.db then return end
    QR.db.refreshes = QR.db.refreshes or {}
    local panel = QR.TeleportPanel
    local inv = QR.PlayerInventory
    push(QR.db.refreshes, {
        shown = panel and panel.sortedTeleports and #panel.sortedTeleports or 0,
        filter = (panel and panel.availabilityFilter)
            or (QR.db and QR.db.availabilityFilter) or "all",
        invItems = inv and Count(inv.teleportItems) or -1,
        invToys = inv and Count(inv.toys) or -1,
        invSpells = inv and Count(inv.spells) or -1,
        loading = (_G.LoadingScreenEnabled ~= nil) and tostring(_G.LoadingScreenEnabled) or nil,
        combat = InCombatLockdown and InCombatLockdown() or false,
        seen = date("%H:%M:%S"),
    }, MAX_REFRESHES)
end

function Diagnostics:Clear()
    if not QR.db then return end
    QR.db.errors = {}
    QR.db.refreshes = {}
end

function Diagnostics:Render()
    local lines = { "## QuickRoute Diagnostics", "" }
    local errors = (QR.db and QR.db.errors) or {}
    lines[#lines + 1] = string_format("### Errors (%d)", #errors)
    lines[#lines + 1] = ""
    for _, e in ipairs(errors) do
        lines[#lines + 1] = string_format("- `%s` x%d — %s",
            tostring(e.message), e.count or 1, tostring(e.seen))
    end
    if #errors == 0 then lines[#lines + 1] = "  (none)" end

    local refreshes = (QR.db and QR.db.refreshes) or {}
    lines[#lines + 1] = ""
    lines[#lines + 1] = string_format("### Teleport list rebuilds (%d)", #refreshes)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| time | shown | filter | items | toys | spells | combat |"
    lines[#lines + 1] = "|---|---|---|---|---|---|---|"
    for _, r in ipairs(refreshes) do
        lines[#lines + 1] = string_format("| %s | %d | %s | %d | %d | %d | %s |",
            tostring(r.seen), r.shown or 0, tostring(r.filter),
            r.invItems or -1, r.invToys or -1, r.invSpells or -1,
            tostring(r.combat))
    end
    return table_concat(lines, "\n")
end

function Diagnostics:Initialize()
    if QR.db then
        QR.db.errors = QR.db.errors or {}
        QR.db.refreshes = QR.db.refreshes or {}
    end

    -- Chain rather than replace: whatever was handling errors keeps handling
    -- them, including the default frame the player sees.
    if seterrorhandler and geterrorhandler and not self.errorHandlerInstalled then
        local previous = geterrorhandler()
        seterrorhandler(function(err)
            pcall(function() Diagnostics:RecordError(err) end)
            if previous then return previous(err) end
        end)
        self.errorHandlerInstalled = true
    end

    -- A post-hook, so a rebuild is recorded even when it is the one that ends
    -- up drawing nothing.
    if hooksecurefunc and QR.TeleportPanel and not self.refreshHookInstalled then
        hooksecurefunc(QR.TeleportPanel, "RefreshList", function()
            pcall(function() Diagnostics:RecordRefresh() end)
        end)
        self.refreshHookInstalled = true
    end

    QR:Debug("Diagnostics initialized")
end

SLASH_QRDIAG1 = "/qrdiag"
SlashCmdList["QRDIAG"] = function(msg)
    local cmd = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if cmd == "clear" then
        Diagnostics:Clear()
        QR:Print("Diagnostics cleared.")
        return
    end
    local report = Diagnostics:Render()
    QR:Print(string_format("Diagnostics: %d error(s), %d rebuild(s).",
        #((QR.db and QR.db.errors) or {}), #((QR.db and QR.db.refreshes) or {})))
    if QR.UI and QR.UI.CopyDebugToClipboard then
        QR.UI:CopyDebugToClipboard()
        if QR.UI.copyFrame and QR.UI.copyFrame.editBox then
            QR.UI.copyFrame.editBox:SetText(report)
            QR.UI.copyFrame.editBox:HighlightText()
        end
    end
end
