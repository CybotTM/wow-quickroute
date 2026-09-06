local T, QR = ...

local function isolated(body)
    local changes = {}
    local function set(owner, key, value)
        changes[#changes + 1] = { owner, key, owner[key] }
        owner[key] = value
    end
    local panel, missing = QR.TeleportPanel
    for _, entry in ipairs(panel:CollectAllTeleports()) do
        if entry.status.key == "STATUS_MISSING" then missing = entry.status; break end
    end
    local entry = { id = 393222, isSpell = true, status = missing,
        data = { name = "Path of the Watcher's Legacy", type = QR.TeleportTypes.SPELL } }
    local matches = { { spellID = 393222, u = 2 }, { spellID = 393222, u = 2 } }
    local att = { PhaseConstants = { NEVER_IMPLEMENTED = 1, REMOVED_FROM_GAME = 2 },
        SearchForField = function() return matches end,
        CurrentCharacterFilters = function() return false end }
    set(_G, "AllTheThings", att)
    set(_G, "ATTC", nil)
    set(panel, "acquisitionFrame", nil)
    set(panel, "frame", CreateFrame("Frame"))
    panel.frame:SetSize(560, 450)
    panel.frame.scrollChild = CreateFrame("Frame", nil, panel.frame)
    local ok, err = pcall(body, panel, entry, matches, att, set)
    if panel.acquisitionFrame then panel.acquisitionFrame:Hide() end
    for index = #changes, 1, -1 do
        local change = changes[index]
        change[1][change[2]] = change[3]
    end
    if not ok then error(err) end
end

local function labelled(panel, entry)
    local info = panel:GetAcquisitionInfo(entry.id, entry)
    return info and info:find(QR.L["ACQUISITION_UNOBTAINABLE"], 1, true) ~= nil
end

T:run("Acquisition availability: removed seasonal sources have visible QR labels", function(t)
    isolated(function(panel, entry)
        t:assertTrue(labelled(panel, entry), "Both removed Uldaman sources produce an unavailable acquisition label")
        local info = panel:GetAcquisitionInfo(entry.id, entry)
        t:assertTrue(info:find(QR.L["ACQUISITION_UNOBTAINABLE_HINT"], 1, true) ~= nil,
            "The explanation attributes availability to ATT and preserves existing unlocks")
        local row = panel:CreateTeleportRow(entry, 0)
        t:assertEqual(QR.L["ACQUISITION_UNOBTAINABLE_SHORT"], row.helpButton:GetText(),
            "The list exposes unavailable acquisition without requiring an ATT popout")
        local icon = panel:GetIconFrame()
        panel:ConfigureGridIcon(icon, entry)
        t:assertEqual("common-icon-redx", icon.unavailableBadge and icon.unavailableBadge:GetAtlas(),
            "The grouped icon uses a native unavailable marker instead of an unsupported glyph")
        t:assertTrue(icon.unavailableBadge and icon.unavailableBadge:IsShown(), "The native unavailable badge is visible")
        t:assertFalse(icon.helpBadge:IsShown(), "A confirmed unavailable entry does not show a competing question mark")
        t:assertNil(icon.useButton, "An unavailable unowned teleport never gets a secure activation action")
        panel:ShowAcquisitionHelp(entry)
        t:assertEqual(QR.L["ACQUISITION_UNOBTAINABLE"], panel.acquisitionFrame.titleText:GetText(),
            "The help window title does not promise acquisition for a removed source")
        panel:ReleaseRowFrame(row)
        panel:ReleaseIconFrame(icon)
    end)
end)

T:run("Acquisition availability: all alternatives must prove removal", function(t)
    isolated(function(panel, entry, matches)
        matches[3] = { spellID = entry.id }
        t:assertFalse(labelled(panel, entry), "An unmarked current alternative defeats old seasonal removal markers")
        matches[3] = nil
        matches[2] = { spellID = entry.id, parent = { u = 2 } }
        t:assertTrue(labelled(panel, entry), "Removal on the source ancestry is recognized")
        matches[2].parent.u = 1
        t:assertTrue(labelled(panel, entry), "A never-implemented alternative cannot make acquisition available")
        matches[2].parent.u = 99
        t:assertFalse(labelled(panel, entry), "An unknown availability flag cannot prove removal")
        matches[2].parent = { rwp = 100200 }
        t:assertFalse(labelled(panel, entry), "A historical patch marker alone does not prove current unavailability")
        matches[2] = { spellID = entry.id + 1, u = 2 }
        t:assertFalse(labelled(panel, entry), "A mismatched indexed result cannot establish availability for another spell")
    end)
end)

T:run("Acquisition availability: incomplete and unsafe ATT data stays unknown", function(t)
    isolated(function(panel, entry, matches, att, set)
        local original = matches[2]
        matches[2] = { spellID = entry.id, u = 2 }
        matches[2].parent = matches[2]
        t:assertFalse(labelled(panel, entry), "A cyclic source cannot establish complete evidence")
        local node = { spellID = entry.id, u = 2 }
        matches[2] = node
        for _ = 1, 17 do node.parent = {}; node = node.parent end
        t:assertFalse(labelled(panel, entry), "Over-depth ancestry remains unknown")
        matches[2] = original
        for index = 3, 33 do matches[index] = { spellID = entry.id, u = 2 } end
        t:assertFalse(labelled(panel, entry), "A truncated source list cannot hide a later obtainable alternative")
        for index = 3, 33 do matches[index] = nil end
        matches[3], matches[2] = matches[2], nil
        t:assertFalse(labelled(panel, entry), "Sparse source arrays are not treated as complete")
        matches[2], matches[3] = original, nil
        set(_G, "issecretvalue", function(value) return value == 7777 end)
        matches[2] = { spellID = entry.id, u = 7777 }
        t:assertFalse(labelled(panel, entry), "Restricted availability metadata never produces a removal claim")
        att.SearchForField = function() error("ATT data is loading") end
        t:assertFalse(labelled(panel, entry), "Failed ATT lookups retain ordinary missing-item guidance")
        set(_G, "AllTheThings", nil)
        t:assertFalse(labelled(panel, entry), "Without ATT the addon makes no unsupported seasonal claim")
    end)
end)

T:run("Acquisition availability: owned teleports and tradeable items are preserved", function(t)
    isolated(function(panel, entry, matches, att)
        local missing = entry.status
        local calls = 0
        att.SearchForField = function() calls = calls + 1; return matches end
        entry.status = { key = "STATUS_READY" }
        t:assertFalse(labelled(panel, entry), "An already learned teleport is not labelled unavailable to use")
        t:assertEqual(0, calls, "Owned entries do not query acquisition metadata")
        entry.status = missing
        entry.isSpell = false
        matches[1], matches[2] = { itemID = entry.id, u = 2, b = 1 }, nil
        t:assertTrue(labelled(panel, entry), "A removed bind-on-pickup item can have confirmed unavailable acquisition")
        matches[1].b = 2
        t:assertFalse(labelled(panel, entry), "Removed bind-on-equip copies may remain tradeable")
        matches[1].b = nil
        t:assertFalse(labelled(panel, entry), "Unknown item binding never rules out existing tradeable copies")
    end)
end)

T:run("Acquisition availability: pooled labels clear when a source becomes available", function(t)
    isolated(function(panel, entry, matches)
        local row = panel:CreateTeleportRow(entry, 0)
        local icon = panel:GetIconFrame()
        panel:ConfigureGridIcon(icon, entry)
        matches[2].u = nil
        panel:ConfigureRowTexts(row, entry)
        panel:ConfigureGridIcon(icon, entry)
        t:assertEqual(QR.L["ACQUISITION_HELP"], row.helpButton:GetText(), "A refreshed row restores ordinary acquisition help")
        t:assertEqual("?", icon.helpBadge:GetText(), "A refreshed icon clears an obsolete unavailable marker")
        t:assertTrue(icon.helpBadge:IsShown(), "Ordinary acquisition help returns after source recovery")
        t:assertFalse(icon.unavailableBadge:IsShown(), "The pooled native badge does not outlive unavailable acquisition")
        panel:ReleaseRowFrame(row)
        panel:ReleaseIconFrame(icon)
    end)
end)

T:run("Acquisition availability: obtainable filter keeps owned and unknown entries", function(t)
    isolated(function(panel, entry, matches, att, set)
        local unknown = { id = 393256, isSpell = true, status = entry.status,
            data = { name = "Other teleport" }, filterCategory = "Spells" }
        local owned = { id = entry.id, isSpell = true,
            status = { key = "STATUS_READY", sortOrder = 1 }, data = entry.data, filterCategory = "Spells" }
        att.SearchForField = function(_, id)
            return id == entry.id and matches or { { spellID = id } }
        end
        set(panel, "CollectAllTeleports", function() return { entry, unknown, owned } end)
        set(panel, "ClearRows", function() end)
        set(panel, "CreateTeleportRow", function(_, item) return { entry = item } end)
        set(panel, "teleportRows", {})
        set(panel, "sortedTeleports", {})
        set(panel, "groupByDestination", false)
        set(panel, "currentFilter", "All")
        set(panel, "searchText", "")
        set(panel, "availabilityFilter", "obtainable")
        set(QR.CooldownTracker, "WatchActiveCooldowns", function() end)
        panel.frame.statusSummary = panel.frame:CreateFontString()
        panel:RefreshList()
        t:assertEqual(2, #panel.sortedTeleports, "Only the confirmed unavailable acquisition leaves Obtainable")
        local foundOwned, foundUnknown = false, false
        for _, item in ipairs(panel.sortedTeleports) do
            foundOwned = foundOwned or item == owned
            foundUnknown = foundUnknown or item == unknown
        end
        t:assertTrue(foundOwned, "Previously learned teleports remain in the filtered list")
        t:assertTrue(foundUnknown, "Uncertain acquisition remains visible without a false removal claim")
        panel.availabilityFilter = "all"
        panel:RefreshList()
        t:assertEqual(3, #panel.sortedTeleports, "Show All retains unavailable acquisitions for reference")
    end)
end)

T:run("Acquisition guidance: ATT purchase reputation is explained beside the vendor route", function(t)
    isolated(function(panel, entry, _, _, set)
        entry.id, entry.isSpell = 190237, false
        entry.data.type = QR.TeleportTypes.TOY
        local source = { npcID = 182257 }
        local item = { itemID = 190237, minReputation = { 2478, 42000 }, parent = source }
        local path = { item, source }
        set(_G, "C_Reputation", { GetFactionDataByID = function() return { name = "The Enlightened" } end })
        set(panel, "GetAcquisitionLocation", function()
            return { kind = "vendor", source = "ATT", name = "Vilo", mapID = 1970, x = .348, y = .641,
                purchaseRequirements = { minReputation = { 2478, 42000 } }, purchaseAvailable = false }, path
        end)
        local info = panel:GetATTAcquisitionInfo(entry, path)
        local requirement = string.format(QR.L["ACQUISITION_REPUTATION_MIN"], "The Enlightened", 42000)
        t:assertTrue(info and info:find(requirement, 1, true) ~= nil, "Source help states the actual vendor purchase reputation threshold")
        panel:ShowAcquisitionHelp(entry)
        t:assertTrue(panel.acquisitionFrame.routeButton:IsShown(), "A purchase-locked item still offers the visit to Vilo")
        t:assertTrue(panel.acquisitionFrame.details:GetText():find(QR.L["ATT_SEARCH_PURCHASE_TT"], 1, true) ~= nil,
            "The route is distinguished from permission to buy the item")
        t:assertTrue(panel.acquisitionFrame.details:GetText():find("Vilo", 1, true) ~= nil,
            "An ATT vendor route identifies the actual vendor before the click")
        t:assertTrue(panel.acquisitionFrame.details:GetText():find("34.8, 64.1", 1, true) ~= nil,
            "An ATT vendor route shows its independently recorded coordinates")
        t:assertFalse(panel.acquisitionFrame.details:GetText():find(QR.L["HINT_CHECK_TOY_VENDORS"], 1, true) ~= nil,
            "A concrete known source replaces generic advice to search for toy vendors")
    end)
end)
