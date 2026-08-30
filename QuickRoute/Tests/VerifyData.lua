-- VerifyData.lua
-- Development command for the 12.1.0 maintenance pass.
--
-- The static data in Data/ carries uiMapIDs, journalInstanceIDs and spellIDs
-- that cannot be checked outside the game. /qrverify asks the live client about
-- every one of them, shows the answer in a copyable window, and stores it in
-- QuickRouteDB.verifyReport so a /reload flushes it to SavedVariables on disk.
--
-- Temporary. Remove this file, its .toc entry and the verifyReport field once
-- the data findings are settled.
local ADDON_NAME, QR = ...

local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat

-- Each row pairs an id with what the repository or the audit claims about it,
-- so the output reads as claim versus client rather than a list of numbers.
local MAPS = {
    { 2512, "audit: The Coiled Isle (12.1.0), absent from the graph" },
    { 2509, "audit: Vaults of Atal'Utek (12.1.0), absent" },
    { 2599, "audit: Val (12.0.7), absent" },
    { 2600, "audit: Naigtal (12.0.7), absent" },
    { 2352, "audit: Founder's Point (housing), absent" },
    { 2351, "audit: Razorwind Shores (housing), absent" },
    { 2537, "audit: continent-level fallback, absent" },
    { 110,  "repo: Silvermoon in ServicePOIs and Portals" },
    { 2393, "audit: the Silvermoon the portals actually land on" },
    { 2437, "repo: Zul'Aman (Midnight)" },
    { 2405, "repo: Voidstorm" },
    { 2413, "repo: Harandar (already corrected from 2576 once)" },
    { 2371, "audit: K'aresh, missing from the Z table" },
    { 67,  "repo: labelled Tanaris | audit: is Feralas" },
    { 69,  "repo: labelled Un'Goro | audit: is Tanaris" },
    { 71,  "audit: the real Tanaris" },
    { 78,  "audit: the real Un'Goro Crater" },
    { 203, "repo: labelled Un'Goro Crater" },
    { 249, "audit: the real Uldum" },
    { 261, "repo: labelled Uldum" },
    { 378, "repo: labelled Kun-Lai Summit" },
    { 379, "audit: the real Kun-Lai Summit, and the Zen Pilgrimage target" },
    { 700, "audit: phantom node joined by a 0.001s edge" },
    { 11,  "repo: Z.ASHENVALE | audit: wrong id" },
    { 63,  "audit: the real Ashenvale" },
    { 68,  "repo: Z.DUSTWALLOW_MARSH | audit: wrong id" },
    { 70,  "audit: the real Dustwallow Marsh" },
    { 101, "audit: phantom node joined by a 0.001s edge" },
    { 102, "audit: the real Netherstorm" },
    { 15,  "repo: Z.BADLANDS_SUBZONE" },
    { 17,  "repo: Z.BADLANDS" },
    { 23,  "repo: Mole Machine target, 'Eastern Plaguelands'" },
    { 36,  "audit: correct id for one of the aliases" },
    { 104, "audit: correct id for one of the aliases" },
    { 108, "audit: correct id for one of the aliases" },
    { 109, "audit: correct id for one of the aliases" },
    { 241, "audit: correct id (Twilight Highlands)" },
    { 942, "audit: correct id for one of the aliases" },
    { 773,  "repo: TeleportItems.lua:1282 destination" },
    { 809,  "repo: 'Peak of Serenity'" },
    { 1584, "repo: 'Blackrock Depths'" },
    { 646,  "audit: Broken Shore, proposed Death Gate target" },
    { 244,  "repo and audit: Tol Barad, used inconsistently" },
    { 245,  "audit: Tol Barad Peninsula" },
    { 1961, "audit: Korthia, destination without a node" },
    { 2107, "audit: The Forbidden Reach, destination without a node" },
    { 89, "repo: Darnassus services | audit: destroyed since 8.0.1" },
    { 90, "repo: Undercity services | audit: destroyed since 8.0.1" },
}

local INSTANCES = {
    { 1298, "audit: Operation: Floodgate" },
    { 1299, "repo: Windrunner Spire, coordinates copied from another map" },
    { 1302, "audit: Manaforge Omega" },
    { 1303, "audit: Eco-Dome Al'dani" },
    { 1305, "audit: Sporefall (12.0.7 raid)" },
    { 1311, "audit: Den of Nalorakk" },
    { 1317, "audit: The Tidebound Grotto (12.1.0 lair)" },
    { 1320, "audit: The Venomous Abyss (12.1.0 raid)" },
    { 1322, "audit: Altar of Fangs (12.1.0 dungeon)" },
    { 184,  "audit: End Time" },
    { 185,  "audit: Well of Eternity" },
    { 186,  "audit: Hour of Twilight" },
    { 276,  "audit: Halls of Reflection" },
    { 278,  "audit: Pit of Saron" },
    { 280,  "audit: The Forge of Souls" },
    { 281,  "audit: The Nexus" },
    { 282,  "audit: The Oculus" },
    { 251,  "audit: Old Hillsbrad" },
    { 255,  "audit: Black Morass" },
    { 968,  "audit: Atal'Dazar" },
    { 1041, "audit: Kings' Rest" },
}

local SPELLS = {
    { 204587, "repo: Demon Hunter class teleport | audit: no such spell" },
    { 368229, "repo: Evoker class teleport | audit: no such spell" },
    { 176242, "repo: Ashran Horde entry | audit: is the Alliance one" },
    { 176244, "repo: Ashran Alliance entry | audit: is a portal spell" },
    { 176248, "audit: the real Alliance Ashran teleport" },
}

local function MapRow(id, note)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    if not info then
        return string_format("| %d | **DOES NOT EXIST** | - | - | %s |", id, note)
    end
    return string_format("| %d | %s | %s | %s | %s |",
        id, tostring(info.name), tostring(info.mapType), tostring(info.parentMapID), note)
end

--- Make sure the Encounter Journal's data is available.
-- EJ_GetInstanceInfo lives in the load-on-demand Blizzard_EncounterJournal
-- addon, so it is nil until something opens the journal. Loading it here means
-- the report does not depend on the user having pressed Shift-J first.
-- @return string A short note on what was available, for the report header
local function EnsureEncounterJournal()
    if type(EJ_GetInstanceInfo) == "function" then
        return "EJ_GetInstanceInfo available"
    end

    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not loader then
        return "no LoadAddOn available"
    end

    local ok, err = pcall(loader, "Blizzard_EncounterJournal")
    if not ok then
        return "LoadAddOn failed: " .. tostring(err)
    end
    if type(EJ_GetInstanceInfo) == "function" then
        return "Blizzard_EncounterJournal loaded on demand"
    end
    return "loaded, but EJ_GetInstanceInfo is still nil"
end

local function InstanceRow(id, note)
    if type(EJ_GetInstanceInfo) ~= "function" then
        return string_format("| %d | _EJ_GetInstanceInfo missing_ | %s |", id, note)
    end
    local ok, name = pcall(EJ_GetInstanceInfo, id)
    if not ok then
        return string_format("| %d | **error: %s** | %s |", id, tostring(name), note)
    end
    if not name then
        return string_format("| %d | **nil** | %s |", id, note)
    end
    return string_format("| %d | %s | %s |", id, tostring(name), note)
end

local function SpellRow(id, note)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(id)
    end
    if not name and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        name = info and info.name
    end
    if not name then
        return string_format("| %d | **nil** | %s |", id, note)
    end
    return string_format("| %d | %s | %s |", id, tostring(name), note)
end

-- Words that mark a spell or toy as travel-related, in the locales this is
-- likely to run under. Matching on names is coarse, but dumping every spell a
-- character knows would bury the answer.
local TRAVEL_WORDS = {
    "teleport", "portal", "hearthstone", "ruhestein", "recall", "rückkehr",
    "rueckkehr", "summon", "beschwör", "beschwoer", "travel", "reise",
    "passage", "gate", "tor", "translocat", "transporter", "wormhole",
    "wurmloch", "dalaran", "shrine", "zuflucht", "delve", "tiefe",
}

local function LooksLikeTravel(name)
    if not name then return false end
    local lower = string.lower(name)
    for _, word in ipairs(TRAVEL_WORDS) do
        if string.find(lower, word, 1, true) then
            return true
        end
    end
    return false
end

--- Every teleport id the addon's data files already know about.
-- @return table Set keyed by item or spell id
local function KnownIDs()
    local known = {}
    for itemID in pairs(QR.TeleportItemsData or {}) do known[itemID] = true end
    for _, tbl in ipairs({ QR.ClassTeleportSpells, QR.RacialTeleportSpells,
                           QR.GeneralTeleportSpells }) do
        for spellID in pairs(tbl or {}) do known[spellID] = true end
    end
    for _, factionTable in pairs(QR.MageTeleports or {}) do
        for spellID in pairs(factionTable or {}) do known[spellID] = true end
    end
    return known
end

--- Owned toys the data files do not mention.
-- Enumeration honours the toy box's own filters, so the count is reported and
-- the caller is told to clear any search text first.
local function DiscoverToys(out, known)
    local function add(s) table_insert(out, s) end

    add("### Toys you own that QuickRoute does not know")
    add("")
    if not (C_ToyBox and C_ToyBox.GetNumFilteredToys and C_ToyBox.GetToyFromIndex
            and PlayerHasToy) then
        add("_Toy box API unavailable._")
        add("")
        return
    end

    local total = C_ToyBox.GetNumFilteredToys() or 0
    add(string_format("_Enumerated %d toys. This respects the toy box's filters — clear its search box and show all collected toys before trusting the list._",
        total))
    add("")
    add("| itemID | name | travel-ish |")
    add("|---|---|---|")

    local found = 0
    for i = 1, total do
        local itemID = C_ToyBox.GetToyFromIndex(i)
        if itemID and itemID > 0 and not known[itemID] then
            local ok, hasToy = pcall(PlayerHasToy, itemID)
            if ok and hasToy then
                local name
                if C_ToyBox.GetToyInfo then
                    local _, toyName = C_ToyBox.GetToyInfo(itemID)
                    name = toyName
                end
                name = name or "?"
                if LooksLikeTravel(name) then
                    found = found + 1
                    add(string_format("| %d | %s | yes |", itemID, name))
                end
            end
        end
    end
    if found == 0 then
        add("| - | _nothing travel-related that the data files miss_ | - |")
    end
    add("")
end

--- Known spells the data files do not mention.
local function DiscoverSpells(out, known)
    local function add(s) table_insert(out, s) end

    add("### Spells you know that QuickRoute does not know")
    add("")
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
            and C_SpellBook.GetSpellBookSkillLineInfo
            and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank) then
        add("_Spell book API unavailable._")
        add("")
        return
    end

    add("_Names are matched against a travel word list, so this is a shortlist rather than every spell._")
    add("")
    add("| spellID | name | skill line |")
    add("|---|---|---|")

    local found = 0
    local scanned = 0
    for lineIndex = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if lineInfo and lineInfo.itemIndexOffset and lineInfo.numSpellBookItems then
            for slot = lineInfo.itemIndexOffset + 1,
                       lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(
                    slot, Enum.SpellBookSpellBank.Player)
                if info and info.spellID then
                    scanned = scanned + 1
                    if not known[info.spellID] and not info.isPassive
                        and LooksLikeTravel(info.name) then
                        found = found + 1
                        add(string_format("| %d | %s | %s |",
                            info.spellID, tostring(info.name),
                            tostring(lineInfo.name)))
                    end
                end
            end
        end
    end
    if found == 0 then
        add("| - | _nothing travel-related that the data files miss_ | - |")
    end
    add("")
    add(string_format("_Scanned %d spell book entries._", scanned))
    add("")
end

--- Build the report as markdown.
-- @return string
function QR:BuildVerifyReport()
    local out = {}
    local function add(s) table_insert(out, s) end

    local build, buildNumber, _, iface = GetBuildInfo()
    add("## QuickRoute data check")
    add("")
    add(string_format("Client %s (%s), interface %s, addon v%s",
        tostring(build), tostring(buildNumber), tostring(iface), tostring(QR.version)))

    local playerMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if playerMap then
        local line = string_format("Standing on uiMapID %d", playerMap)
        if C_Map.GetPlayerMapPosition then
            local pos = C_Map.GetPlayerMapPosition(playerMap, "player")
            if pos then
                local x, y = pos:GetXY()
                if x and y then
                    line = line .. string_format(" at (%.4f, %.4f)", x, y)
                end
            end
        end
        add(line)
    end
    add("")

    add("### Maps")
    add("")
    add("| uiMapID | name | mapType | parent | claim |")
    add("|---|---|---|---|---|")
    local seen = {}
    for _, row in ipairs(MAPS) do
        if not seen[row[1]] then
            seen[row[1]] = true
            add(MapRow(row[1], row[2]))
        end
    end
    add("")

    add("### Encounter Journal instances")
    add("")
    add("_" .. EnsureEncounterJournal() .. "_")
    add("")
    add("| journalInstanceID | name | claim |")
    add("|---|---|---|")
    for _, row in ipairs(INSTANCES) do
        add(InstanceRow(row[1], row[2]))
    end
    add("")

    add("### Spells")
    add("")
    add("_nil can also mean the spell data is not cached yet — run /qrverify twice._")
    add("")
    add("| spellID | name | claim |")
    add("|---|---|---|")
    for _, row in ipairs(SPELLS) do
        add(SpellRow(row[1], row[2]))
    end
    add("")

    -- What the addon cannot find on its own: PlayerInventory only ever checks
    -- the ids already in the data files, so anything missing from them is
    -- invisible. These two sections compare against what the character has.
    local known = KnownIDs()
    DiscoverToys(out, known)
    DiscoverSpells(out, known)

    return table_concat(out, "\n")
end

local frame

--- Show a report in a copyable window.
-- @param text string
local function ShowReport(text)
    if not frame then
        frame = CreateFrame("Frame", "QuickRouteVerifyFrame", UIParent,
            "BasicFrameTemplateWithInset")
        frame:SetSize(720, 540)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetClampedToScreen(true)

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", frame, "TOP", 0, -6)
        title:SetText("QuickRoute data check — Ctrl+A, Ctrl+C. A /reload also writes it to SavedVariables.")

        local scroll = CreateFrame("ScrollFrame", "QuickRouteVerifyScroll", frame,
            "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        if QR.SkinScrollBar then
            QR.SkinScrollBar(scroll)
        end

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(660)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        frame.edit = edit
    end

    frame.edit:SetText(text)
    frame.edit:HighlightText()
    frame.edit:SetFocus()
    frame:Show()
end

SLASH_QRVERIFY1 = "/qrverify"
SlashCmdList["QRVERIFY"] = function()
    local report = QR:BuildVerifyReport()

    -- Persist so a /reload flushes it to SavedVariables and it can be read off
    -- disk without copying anything out of the window.
    if QuickRouteDB then
        QuickRouteDB.verifyReport = report
    end

    ShowReport(report)
    QR:Print("Data check written to the window and to QuickRouteDB.verifyReport. /reload to flush it to disk.")
end
