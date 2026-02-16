-- Localization.lua
-- Localization system for QuickRoute
local ADDON_NAME, QR = ...

QR.L = setmetatable({}, {
    __index = function(t, k)
        return k  -- Return key as fallback
    end
})

local L = QR.L

-------------------------------------------------------------------------------
-- English strings (default)
-------------------------------------------------------------------------------

-- General
L["ADDON_TITLE"] = "QuickRoute"
L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s loaded"
L["ADDON_FIRST_RUN"] = "Type |cFFFFFF00/qr|r to open or |cFFFFFF00/qrhelp|r for commands."
L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute ERROR:|r "
L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute WARNING|r: "
L["MINIMAP_SHOWN"] = "Minimap button shown"
L["MINIMAP_HIDDEN"] = "Minimap button hidden"
L["PRIORITY_SET_TO"] = "Waypoint priority set to '%s'"
L["PRIORITY_USAGE"] = "Usage: /qr priority mappin|quest|tomtom"
L["PRIORITY_CURRENT"] = "Current priority"

-- UI Elements
L["DESTINATION"] = "Destination:"
L["NO_WAYPOINT"] = "No waypoint set"
L["REFRESH"] = "Refresh"
L["COPY_DEBUG"] = "Copy Debug"
L["ZONE_INFO"] = "Zone Info"
L["INVENTORY"] = "Inventory"
L["NAV"] = "Nav"
L["USE"] = "Use"
L["CLOSE"] = "Close"
L["FILTER"] = "Filter:"
L["ALL"] = "All"
L["ITEMS"] = "Items"
L["TOYS"] = "Toys"
L["SPELLS"] = "Spells"

-- Status Labels
L["STATUS_READY"] = "READY"
L["STATUS_ON_CD"] = "ON CD"
L["STATUS_OWNED"] = "OWNED"
L["STATUS_MISSING"] = "MISSING"
L["STATUS_NA"] = "N/A"

-- Panels
L["TELEPORT_INVENTORY"] = "Teleport Inventory"
L["COPY_DEBUG_TITLE"] = "Copy Debug Info (Ctrl+C)"

-- Status Messages
L["CALCULATING"] = "Calculating..."
L["SCANNING"] = "Scanning..."
L["IN_COMBAT"] = "In Combat"
L["CANNOT_USE_IN_COMBAT"] = "Cannot use during combat"
L["WAYPOINT_SET"] = "Waypoint set for %s"
L["NO_PATH_FOUND"] = "No route found"
L["NO_DESTINATION"] = "No destination for this step"
L["CANNOT_FIND_LOCATION"] = "Cannot find location for %s"
L["SET_WAYPOINT_HINT"] = "Set a waypoint to calculate route"
L["PATH_CALCULATION_ERROR"] = "Path calculation error"
L["DESTINATION_NOT_REACHABLE"] = "Destination not reachable with current teleports"

-- Debug
L["DEBUG_MODE_ENABLED"] = "Debug mode enabled"
L["DEBUG_MODE_DISABLED"] = "Debug mode disabled"
L["TRAVEL_GRAPH_BUILT"] = "Travel graph built"
L["FOUND_TELEPORTS"] = "Found %d teleport methods"
L["UI_INITIALIZED"] = "UI initialized"
L["TELEPORT_PANEL_INITIALIZED"] = "TeleportPanel initialized"
L["SECURE_BUTTONS_INITIALIZED"] = "SecureButtons initialized with %d buttons"
L["POOL_EXHAUSTED"] = "SecureButtons pool exhausted (%d buttons in use)"

-- Summary
L["SHOWING_TELEPORTS"] = "Showing %d teleports | %d owned | %d ready"
L["ESTIMATED_TRAVEL_TIME"] = "%s estimated travel time"
L["SOURCE"] = "Source"
L["SOURCE_MAP_PIN"] = "Map Pin"
L["SOURCE_MAP_CLICK"] = "Map Click"
L["SOURCE_QUEST"] = "Quest Objective"
L["NO_ROUTE_HINT"] = "Try a different destination or scan teleports (/qrinv)"

-- Waypoint Source Selector
L["WAYPOINT_SOURCE"] = "Target:"
L["WAYPOINT_AUTO"] = "Auto"
L["WAYPOINT_MAP_PIN"] = "Map Pin"
L["WAYPOINT_TOMTOM"] = "TomTom"
L["WAYPOINT_QUEST"] = "Quest"
L["TOOLTIP_WAYPOINT_SOURCE"] = "Select which waypoint to navigate to"
L["NO_WAYPOINTS_AVAILABLE"] = "No waypoints available"

-- Column Headers
L["NAME"] = "Name"
L["DESTINATION_HEADER"] = "Destination"
L["STATUS"] = "Status"

-- Tooltips
L["TOOLTIP_REFRESH"] = "Recalculate the route to your waypoint"
L["TOOLTIP_DEBUG"] = "Copy debug information to clipboard"
L["TOOLTIP_ZONE"] = "Copy zone debug information to clipboard"
L["TOOLTIP_TELEPORTS"] = "Open teleport inventory panel"
L["TOOLTIP_NAV"] = "Set navigation waypoint to this destination"
L["TOOLTIP_USE"] = "Use this teleport"

-- Action Types
L["ACTION_TELEPORT"] = "Teleport"
L["ACTION_WALK"] = "Walk"
L["ACTION_FLY"] = "Fly"
L["ACTION_PORTAL"] = "Portal"
L["ACTION_HEARTHSTONE"] = "Hearthstone"
L["ACTION_USE_TELEPORT"] = "Use %s to teleport to %s"
L["ACTION_USE"] = "Use %s"
L["ACTION_BOAT"] = "Boat"
L["ACTION_ZEPPELIN"] = "Zeppelin"
L["ACTION_TRAM"] = "Tram"
L["ACTION_TRAVEL"] = "Travel"
L["COOLDOWN_SHORT"] = "CD"

-- Step Descriptions (used in route display)
L["STEP_GO_TO"] = "Go to %s"
L["STEP_GO_TO_IN_ZONE"] = "Go to %s in %s"
L["STEP_TAKE_PORTAL"] = "Take portal to %s"
L["STEP_TAKE_BOAT"] = "Take boat to %s"
L["STEP_TAKE_ZEPPELIN"] = "Take zeppelin to %s"
L["STEP_TAKE_TRAM"] = "Take Deeprun Tram to %s"
L["STEP_TELEPORT_TO"] = "Teleport to %s"

-- Route Progress
L["STEP_COMPLETED"] = "completed"
L["STEP_CURRENT"] = "current"

-- Settings
L["AUTO_WAYPOINT_TOGGLE"] = "Auto-waypoint: "
L["AUTO_WAYPOINT_ON"] = "ON (will set TomTom/native waypoint for first step)"
L["AUTO_WAYPOINT_OFF"] = "OFF (WoW built-in navigation used)"
L["SETTINGS_GENERAL"] = "General"
L["SETTINGS_NAVIGATION"] = "Navigation"
L["SETTINGS_SHOW_MINIMAP"] = "Show Minimap Button"
L["SETTINGS_SHOW_MINIMAP_TT"] = "Show or hide the minimap button"
L["SETTINGS_AUTO_WAYPOINT"] = "Auto-set Waypoint for First Step"
L["SETTINGS_CONSIDER_CD"] = "Consider Cooldowns in Routing"
L["SETTINGS_CONSIDER_CD_TT"] = "Factor teleport cooldowns into route calculations"
L["SETTINGS_AUTO_DEST"] = "Auto-show route on quest tracking"
L["SETTINGS_AUTO_DEST_TT"] = "Automatically calculate and show the route when you track a new quest"
L["SETTINGS_ROUTING"] = "Routing"
L["SETTINGS_MAX_COOLDOWN"] = "Max Cooldown (hours)"
L["SETTINGS_MAX_COOLDOWN_TT"] = "Exclude teleports with cooldowns longer than this"
L["SETTINGS_LOADING_TIME"] = "Loading Screen Time (seconds)"
L["SETTINGS_LOADING_TIME_TT"] = "Adds this many seconds to each teleport/portal in route calculations to account for loading screens. Higher values make walking preferred over short teleports. Set to 0 to ignore loading times."
L["SETTINGS_APPEARANCE"] = "Appearance"
L["SETTINGS_WINDOW_SCALE"] = "Window Scale"
L["SETTINGS_WINDOW_SCALE_TT"] = "Scale of the route and teleport windows (75%-150%)"
L["SETTINGS_DESCRIPTION"] = "Get to any destination as easily and as fast as possible."
L["SETTINGS_FEATURES"] = "Features"
L["SETTINGS_FEAT_ROUTING"] = "Optimal routing"
L["SETTINGS_FEAT_TELEPORTS"] = "Teleport browser"
L["SETTINGS_FEAT_MAPBUTTON"] = "World map button"
L["SETTINGS_FEAT_QUESTBUTTONS"] = "Quest tracker buttons"
L["SETTINGS_FEAT_COLLAPSING"] = "Route collapsing"
L["SETTINGS_FEAT_AUTODEST"] = "Auto-destination"
L["SETTINGS_FEAT_POIROUTING"] = "Map click routing"
L["SETTINGS_FEAT_DESTGROUP"] = "Destination grouping"

-- Minimap Button
L["TOOLTIP_MINIMAP_LEFT"] = "Left-click: Toggle route window"
L["TOOLTIP_MINIMAP_RIGHT"] = "Right-click: Teleport inventory"
L["TOOLTIP_MINIMAP_DRAG"] = "Drag: Move button"
L["TOOLTIP_MINIMAP_MIDDLE"] = "Middle-click: Quick teleports"

-- Mini Teleport Panel
L["MINI_PANEL_TITLE"] = "Quick Teleports"
L["MINI_PANEL_NO_TELEPORTS"] = "No teleports available"
L["MINI_PANEL_SUMMON_MOUNT"] = "Summon Mount"
L["MINI_PANEL_RANDOM_FAVORITE"] = "Random favorite"

-- Dungeon/Raid routing
L["DUNGEON_PICKER_TITLE"] = "Dungeons & Raids"
L["DUNGEON_PICKER_SEARCH"] = "Search..."
L["DUNGEON_PICKER_NO_RESULTS"] = "No matching instances"
L["DUNGEON_ROUTE_TO"] = "Route to entrance"
L["DUNGEON_ROUTE_TO_TT"] = "Calculate the fastest route to this dungeon entrance"
L["DUNGEON_TAG"] = "Dungeon"
L["DUNGEON_RAID_TAG"] = "Raid"
L["DUNGEON_ENTRANCE"] = "%s Entrance"
L["EJ_ROUTE_BUTTON_TT"] = "Route to this instance entrance"

-- Destination Search
L["DEST_SEARCH_PLACEHOLDER"] = "Search destinations..."
L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Active Waypoint"
L["DEST_SEARCH_CITIES"] = "Cities"
L["DEST_SEARCH_DUNGEONS"] = "Dungeons & Raids"
L["DEST_SEARCH_NO_RESULTS"] = "No matching destinations"
L["DEST_SEARCH_ROUTE_TO_TT"] = "Click to calculate route"

-- Service POI routing
L["SERVICE_AUCTION_HOUSE"] = "Auction House"
L["SERVICE_BANK"] = "Bank"
L["SERVICE_VOID_STORAGE"] = "Void Storage"
L["SERVICE_CRAFTING_TABLE"] = "Crafting Table"
L["SERVICE_NEAREST_AUCTION_HOUSE"] = "Nearest Auction House"
L["SERVICE_NEAREST_BANK"] = "Nearest Bank"
L["SERVICE_NEAREST_VOID_STORAGE"] = "Nearest Void Storage"
L["SERVICE_NEAREST_CRAFTING_TABLE"] = "Nearest Crafting Table"
L["DEST_SEARCH_SERVICES"] = "Services"

-- Errors / Hints
L["UNKNOWN"] = "Unknown"
L["UNKNOWN_VENDOR"] = "Unknown vendor"
L["QUEST_FALLBACK"] = "Quest #%d"
L["TELEPORT_FALLBACK"] = "Teleport"
L["NO_LIMIT"] = "No limit"
L["WAYPOINT_DETECTION_FAILED"] = "Waypoint detection failed"
L["TOOLTIP_RESCAN"] = "Rescan inventory for teleport items"
L["HOW_TO_OBTAIN"] = "How to obtain:"
L["HINT_CHECK_TOY_VENDORS"] = "Check Toy vendors, world drops, or achievements"
L["HINT_REQUIRES_ENGINEERING"] = "Requires Engineering profession"
L["HINT_CHECK_WOWHEAD"] = "Check Wowhead for acquisition details"

-- Dynamic destination names (nil-mapID entries, cannot use C_Map.GetMapInfo)
L["DEST_BOUND_LOCATION"] = "Bound Location"
L["DEST_GARRISON"] = "Garrison"
L["DEST_GARRISON_SHIPYARD"] = "Garrison Shipyard"
L["DEST_CAMP_LOCATION"] = "Camp Location"
L["DEST_RANDOM"] = "Random location"
L["DEST_ILLIDARI_CAMP"] = "Illidari Camp"
L["DEST_RANDOM_NORTHREND"] = "Random Northrend Location"
L["DEST_RANDOM_PANDARIA"] = "Random Pandaria Location"
L["DEST_RANDOM_DRAENOR"] = "Random Draenor Location"
L["DEST_RANDOM_ARGUS"] = "Random Argus Location"
L["DEST_RANDOM_KUL_TIRAS"] = "Random Kul Tiras Location"
L["DEST_RANDOM_ZANDALAR"] = "Random Zandalar Location"
L["DEST_RANDOM_SHADOWLANDS"] = "Random Shadowlands Location"
L["DEST_RANDOM_DRAGON_ISLES"] = "Random Dragon Isles Location"
L["DEST_RANDOM_KHAZ_ALGAR"] = "Random Khaz Algar Location"
L["DEST_HOMESTEAD"] = "Homestead"
L["DEST_RANDOM_WORLDWIDE"] = "Random location worldwide"
L["DEST_RANDOM_NATURAL"] = "Random natural location"
L["DEST_RANDOM_BROKEN_ISLES"] = "Random Broken Isles Ley Line"

-- Acquisition text
L["ACQ_LEGION_INTRO"] = "Quest reward from initial Legion intro questline"
L["ACQ_WOD_INTRO"] = "Quest reward from Warlords of Draenor intro questline"
L["ACQ_KYRIAN"] = "Kyrian covenant feature"
L["ACQ_VENTHYR"] = "Venthyr covenant feature"
L["ACQ_NIGHT_FAE"] = "Night Fae covenant feature"
L["ACQ_NECROLORD"] = "Necrolord covenant feature"
L["ACQ_ARGENT_TOURNAMENT"] = "Exalted with Argent Crusade + Champion of faction at Argent Tournament"
L["ACQ_HELLSCREAMS_REACH"] = "Exalted with Hellscream's Reach (Tol Barad dailies)"
L["ACQ_BARADINS_WARDENS"] = "Exalted with Baradin's Wardens (Tol Barad dailies)"
L["ACQ_KARAZHAN_OPERA"] = "Drop from The Big Bad Wolf (Opera event) in Karazhan"
L["ACQ_ICC_LK25"] = "Drop from heroic Lich King 25 in Icecrown Citadel"

-- Acquisition requirement labels
L["REQ_REPUTATION"] = "Reputation"
L["REQ_QUEST"] = "Quest"
L["REQ_ACHIEVEMENT"] = "Achievement"
L["REQ_COMPLETE"] = "Complete"
L["REQ_IN_PROGRESS"] = "In Progress"
L["REQ_NOT_STARTED"] = "Not Started"
L["REQ_CURRENT"] = "Current"

-- TeleportPanel grouping
L["GROUP_BY_DEST"] = "Group by Destination"
L["GROUP_BY_DEST_TT"] = "Group teleports by destination zone"
L["TELEPORTS_COUNT"] = "%d teleports"

-- TeleportPanel location strings
L["LOC_TOY_COLLECTION"] = "Toy Collection (account-wide)"
L["LOC_IN_BAGS"] = "In bags (Bag %d, Slot %d)"
L["LOC_IN_BANK_MAIN"] = "In bank (Main)"
L["LOC_IN_BANK_BAG"] = "In bank (Bag %d)"
L["LOC_BANK_OR_BAGS"] = "Location: Bank or bags (visit bank to check)"
L["LOC_VENDOR"] = "Vendor:"
L["LOC_LOCATION"] = "Location:"

-- Availability filter
L["AVAIL_ALL"] = "Show All"
L["AVAIL_USABLE"] = "Usable Now"
L["AVAIL_OBTAINABLE"] = "Obtainable"
L["AVAIL_FILTER_TT"] = "Cycle filter: Show All (everything) / Usable Now (off cooldown, owned) / Obtainable (owned + obtainable, excludes faction/class-locked)"

-- Settings hint
L["SETTINGS_COMMANDS_HINT"] = "/qr - Route window | /qrteleports - Inventory | /qrtest graph - Run tests"

-- Icon buttons
L["SETTINGS_ICON_BUTTONS"] = "Use Icon Buttons"
L["SETTINGS_ICON_BUTTONS_TT"] = "Replace text labels on buttons with icons for a more compact UI"

-- Map teleport button
L["MAP_BTN_LEFT_CLICK"] = "Left-click: Use teleport"
L["MAP_BTN_RIGHT_CLICK"] = "Right-click: Show route"
L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+Right-click map: Route to location"
L["QUEST_TRACK_HINT"] = "Shift+Click quest to route to objective"

-- Map sidebar panel
L["SIDEBAR_TITLE"] = "QuickRoute"
L["SIDEBAR_NO_TELEPORTS"] = "No teleports for this zone"
L["SIDEBAR_COLLAPSE_TT"] = "Click to collapse/expand"

-- Main frame tabs
L["TAB_ROUTE"] = "Route"
L["TAB_TELEPORTS"] = "Teleports"
L["FILTER_OPTIONS"] = "Filter Options"

-------------------------------------------------------------------------------
-- German translations (deDE)
-------------------------------------------------------------------------------
if GetLocale() == "deDE" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s geladen"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute FEHLER:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute WARNUNG|r: "
    L["ADDON_FIRST_RUN"] = "Tippe |cFFFFFF00/qr|r zum Öffnen oder |cFFFFFF00/qrhelp|r für Befehle."
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "Minimap-Button angezeigt"
    L["MINIMAP_HIDDEN"] = "Minimap-Button versteckt"
    L["PRIORITY_SET_TO"] = "Wegpunkt-Priorität auf '%s' gesetzt"
    L["PRIORITY_USAGE"] = "Verwendung: /qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "Aktuelle Priorität"

    -- UI Elements
    L["DESTINATION"] = "Ziel:"
    L["NO_WAYPOINT"] = "Kein Wegpunkt gesetzt"
    L["REFRESH"] = "Aktualisieren"
    L["COPY_DEBUG"] = "Debug kopieren"
    L["ZONE_INFO"] = "Zoneninfo"
    L["INVENTORY"] = "Inventar"
    L["NAV"] = "Nav"
    L["USE"] = "Nutzen"
    L["CLOSE"] = "Schließen"
    L["FILTER"] = "Filter:"
    L["ALL"] = "Alle"
    L["ITEMS"] = "Gegenstände"
    L["TOYS"] = "Spielzeug"
    L["SPELLS"] = "Zauber"

    -- Status Labels
    L["STATUS_READY"] = "BEREIT"
    L["STATUS_ON_CD"] = "CD"
    L["STATUS_OWNED"] = "BESITZT"
    L["STATUS_MISSING"] = "FEHLT"
    L["STATUS_NA"] = "N/V"

    -- Panels
    L["TELEPORT_INVENTORY"] = "Teleport-Inventar"
    L["COPY_DEBUG_TITLE"] = "Debug-Info kopieren (Strg+C)"

    -- Status Messages
    L["CALCULATING"] = "Berechne..."
    L["SCANNING"] = "Scanne..."
    L["IN_COMBAT"] = "Im Kampf"
    L["CANNOT_USE_IN_COMBAT"] = "Im Kampf nicht nutzbar"
    L["WAYPOINT_SET"] = "Wegpunkt gesetzt für %s"
    L["NO_PATH_FOUND"] = "Keine Route gefunden"
    L["NO_DESTINATION"] = "Kein Ziel für diesen Schritt"
    L["CANNOT_FIND_LOCATION"] = "Position für %s nicht gefunden"
    L["SET_WAYPOINT_HINT"] = "Setze einen Wegpunkt um Route zu berechnen"
    L["PATH_CALCULATION_ERROR"] = "Fehler bei Routenberechnung"
    L["DESTINATION_NOT_REACHABLE"] = "Ziel mit aktuellen Teleports nicht erreichbar"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "Debug-Modus aktiviert"
    L["DEBUG_MODE_DISABLED"] = "Debug-Modus deaktiviert"
    L["TRAVEL_GRAPH_BUILT"] = "Reisegraph erstellt"
    L["FOUND_TELEPORTS"] = "%d Teleportmethoden gefunden"
    L["UI_INITIALIZED"] = "UI initialisiert"
    L["TELEPORT_PANEL_INITIALIZED"] = "TeleportPanel initialisiert"
    L["SECURE_BUTTONS_INITIALIZED"] = "SecureButtons mit %d Buttons initialisiert"
    L["POOL_EXHAUSTED"] = "SecureButtons-Pool erschöpft (%d Buttons in Verwendung)"

    -- Summary
    L["SHOWING_TELEPORTS"] = "Zeige %d Teleports | %d besessen | %d bereit"
    L["ESTIMATED_TRAVEL_TIME"] = "%s geschätzte Reisezeit"
    L["SOURCE"] = "Quelle"
    L["SOURCE_MAP_PIN"] = "Kartenmarkierung"
    L["SOURCE_MAP_CLICK"] = "Kartenklick"
    L["SOURCE_QUEST"] = "Questziel"
    L["NO_ROUTE_HINT"] = "Versuche ein anderes Ziel oder scanne Teleports (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "Ziel:"
    L["WAYPOINT_AUTO"] = "Automatisch"
    L["WAYPOINT_MAP_PIN"] = "Kartenmarkierung"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "Questziel"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "Wegpunktziel zur Navigation auswählen"
    L["NO_WAYPOINTS_AVAILABLE"] = "Keine Wegpunkte verfügbar"

    -- Column Headers
    L["NAME"] = "Name"
    L["DESTINATION_HEADER"] = "Ziel"
    L["STATUS"] = "Status"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "Route zu deinem Wegpunkt neu berechnen"
    L["TOOLTIP_DEBUG"] = "Debug-Informationen in Zwischenablage kopieren"
    L["TOOLTIP_ZONE"] = "Zonen-Debug-Infos in Zwischenablage kopieren"
    L["TOOLTIP_TELEPORTS"] = "Teleport-Inventar öffnen"
    L["TOOLTIP_NAV"] = "Navigations-Wegpunkt zu diesem Ziel setzen"
    L["TOOLTIP_USE"] = "Diesen Teleport verwenden"

    -- Action Types
    L["ACTION_TELEPORT"] = "Teleport"
    L["ACTION_WALK"] = "Laufen"
    L["ACTION_FLY"] = "Fliegen"
    L["ACTION_PORTAL"] = "Portal"
    L["ACTION_HEARTHSTONE"] = "Ruhestein"
    L["ACTION_USE_TELEPORT"] = "%s benutzen um nach %s zu teleportieren"
    L["ACTION_USE"] = "%s benutzen"
    L["ACTION_BOAT"] = "Schiff"
    L["ACTION_ZEPPELIN"] = "Zeppelin"
    L["ACTION_TRAM"] = "Tram"
    L["ACTION_TRAVEL"] = "Reisen"
    L["COOLDOWN_SHORT"] = "AZ"

    -- Step Descriptions
    L["STEP_GO_TO"] = "Gehe zu %s"
    L["STEP_GO_TO_IN_ZONE"] = "Gehe zu %s in %s"
    L["STEP_TAKE_PORTAL"] = "Portal nach %s nehmen"
    L["STEP_TAKE_BOAT"] = "Schiff nach %s nehmen"
    L["STEP_TAKE_ZEPPELIN"] = "Zeppelin nach %s nehmen"
    L["STEP_TAKE_TRAM"] = "Tiefenbahn nach %s nehmen"
    L["STEP_TELEPORT_TO"] = "Teleport nach %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "erledigt"
    L["STEP_CURRENT"] = "aktuell"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "Auto-Wegpunkt: "
    L["AUTO_WAYPOINT_ON"] = "AN (setzt TomTom/nativen Wegpunkt für ersten Schritt)"
    L["AUTO_WAYPOINT_OFF"] = "AUS (WoW-eigene Navigation wird verwendet)"
    L["SETTINGS_GENERAL"] = "Allgemein"
    L["SETTINGS_NAVIGATION"] = "Navigation"
    L["SETTINGS_SHOW_MINIMAP"] = "Minimap-Button anzeigen"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "Minimap-Button ein- oder ausblenden"
    L["SETTINGS_AUTO_WAYPOINT"] = "Wegpunkt für ersten Schritt automatisch setzen"
    L["SETTINGS_CONSIDER_CD"] = "Abklingzeiten bei Routenberechnung berücksichtigen"
    L["SETTINGS_CONSIDER_CD_TT"] = "Teleport-Abklingzeiten in Routenberechnungen einbeziehen"
    L["SETTINGS_AUTO_DEST"] = "Route bei Questverfolgung automatisch anzeigen"
    L["SETTINGS_AUTO_DEST_TT"] = "Route automatisch berechnen und anzeigen, wenn eine neue Quest verfolgt wird"
    L["SETTINGS_ROUTING"] = "Routenberechnung"
    L["SETTINGS_MAX_COOLDOWN"] = "Max. Abklingzeit (Stunden)"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "Teleports mit längeren Abklingzeiten ausschließen"
    L["SETTINGS_LOADING_TIME"] = "Ladebildschirmzeit (Sekunden)"
    L["SETTINGS_LOADING_TIME_TT"] = "Addiert diese Sekunden zu jedem Teleport/Portal bei der Routenberechnung für Ladebildschirme. Höhere Werte bevorzugen Laufen gegenüber kurzen Teleports. Auf 0 setzen um Ladezeiten zu ignorieren."
    L["SETTINGS_APPEARANCE"] = "Darstellung"
    L["SETTINGS_WINDOW_SCALE"] = "Fensterskalierung"
    L["SETTINGS_WINDOW_SCALE_TT"] = "Skalierung der Routen- und Teleportfenster (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "So einfach und schnell wie möglich zu jedem Ziel gelangen."
    L["SETTINGS_FEATURES"] = "Funktionen"
    L["SETTINGS_FEAT_ROUTING"] = "Optimale Routenführung"
    L["SETTINGS_FEAT_TELEPORTS"] = "Teleport-Browser"
    L["SETTINGS_FEAT_MAPBUTTON"] = "Weltkarten-Button"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "Quest-Tracker-Buttons"
    L["SETTINGS_FEAT_COLLAPSING"] = "Routenschritte zusammenfassen"
    L["SETTINGS_FEAT_AUTODEST"] = "Auto-Ziel"
    L["SETTINGS_FEAT_POIROUTING"] = "Kartenklick-Routing"
    L["SETTINGS_FEAT_DESTGROUP"] = "Zielgruppierung"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "Linksklick: Routenfenster umschalten"
    L["TOOLTIP_MINIMAP_RIGHT"] = "Rechtsklick: Teleport-Inventar"
    L["TOOLTIP_MINIMAP_DRAG"] = "Ziehen: Button verschieben"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "Mittelklick: Schnell-Teleports"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "Schnell-Teleports"
    L["MINI_PANEL_NO_TELEPORTS"] = "Keine Teleporte verfügbar"
    L["MINI_PANEL_SUMMON_MOUNT"] = "Reittier rufen"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "Zufälliger Favorit"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "Dungeons & Schlachtzüge"
    L["DUNGEON_PICKER_SEARCH"] = "Suchen..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "Keine passenden Instanzen"
    L["DUNGEON_ROUTE_TO"] = "Route zum Eingang"
    L["DUNGEON_ROUTE_TO_TT"] = "Berechne die schnellste Route zum Eingang dieser Instanz"
    L["DUNGEON_TAG"] = "Dungeon"
    L["DUNGEON_RAID_TAG"] = "Schlachtzug"
    L["DUNGEON_ENTRANCE"] = "%s Eingang"
    L["EJ_ROUTE_BUTTON_TT"] = "Route zum Eingang dieser Instanz"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "Ziele suchen..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Aktiver Wegpunkt"
    L["DEST_SEARCH_CITIES"] = "Staedte"
    L["DEST_SEARCH_DUNGEONS"] = "Dungeons & Schlachtzuege"
    L["DEST_SEARCH_NO_RESULTS"] = "Keine passenden Ziele"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "Klicken um Route zu berechnen"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "Auktionshaus"
    L["SERVICE_BANK"] = "Bank"
    L["SERVICE_VOID_STORAGE"] = "Leerenlager"
    L["SERVICE_CRAFTING_TABLE"] = "Handwerkstisch"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "Nächstes Auktionshaus"
    L["SERVICE_NEAREST_BANK"] = "Nächste Bank"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "Nächstes Leerenlager"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "Nächster Handwerkstisch"
    L["DEST_SEARCH_SERVICES"] = "Dienste"

    -- Errors / Hints
    L["UNKNOWN"] = "Unbekannt"
    L["UNKNOWN_VENDOR"] = "Unbekannter Händler"
    L["QUEST_FALLBACK"] = "Quest #%d"
    L["TELEPORT_FALLBACK"] = "Teleport"
    L["NO_LIMIT"] = "Kein Limit"
    L["WAYPOINT_DETECTION_FAILED"] = "Wegpunkterkennung fehlgeschlagen"
    L["TOOLTIP_RESCAN"] = "Inventar nach Teleport-Gegenständen erneut durchsuchen"
    L["HOW_TO_OBTAIN"] = "So erhältlich:"
    L["HINT_CHECK_TOY_VENDORS"] = "Spielzeughändler, Weltdrops oder Erfolge prüfen"
    L["HINT_REQUIRES_ENGINEERING"] = "Erfordert Ingenieurskunst"
    L["HINT_CHECK_WOWHEAD"] = "Auf Wowhead nach Beschaffungsdetails suchen"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "Gebundener Ort"
    L["DEST_GARRISON"] = "Garnison"
    L["DEST_GARRISON_SHIPYARD"] = "Garnisons-Werft"
    L["DEST_CAMP_LOCATION"] = "Lagerort"
    L["DEST_RANDOM"] = "Zufälliger Ort"
    L["DEST_ILLIDARI_CAMP"] = "Illidari-Lager"
    L["DEST_RANDOM_NORTHREND"] = "Zufälliger Ort in Nordend"
    L["DEST_RANDOM_PANDARIA"] = "Zufälliger Ort in Pandaria"
    L["DEST_RANDOM_DRAENOR"] = "Zufälliger Ort in Draenor"
    L["DEST_RANDOM_ARGUS"] = "Zufälliger Ort auf Argus"
    L["DEST_RANDOM_KUL_TIRAS"] = "Zufälliger Ort in Kul Tiras"
    L["DEST_RANDOM_ZANDALAR"] = "Zufälliger Ort in Zandalar"
    L["DEST_RANDOM_SHADOWLANDS"] = "Zufälliger Ort in den Schattenlanden"
    L["DEST_RANDOM_DRAGON_ISLES"] = "Zufälliger Ort auf den Dracheninseln"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "Zufälliger Ort in Khaz Algar"
    L["DEST_HOMESTEAD"] = "Grundstück"
    L["DEST_RANDOM_WORLDWIDE"] = "Zufälliger Ort weltweit"
    L["DEST_RANDOM_NATURAL"] = "Zufälliger natürlicher Ort"
    L["DEST_RANDOM_BROKEN_ISLES"] = "Zufällige Ley-Linie der Verheerten Inseln"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "Questbelohnung der Legion-Einstiegsquestreihe"
    L["ACQ_WOD_INTRO"] = "Questbelohnung der Warlords-of-Draenor-Einstiegsquestreihe"
    L["ACQ_KYRIAN"] = "Kyrianer-Pakt-Feature"
    L["ACQ_VENTHYR"] = "Venthyr-Pakt-Feature"
    L["ACQ_NIGHT_FAE"] = "Nachtfae-Pakt-Feature"
    L["ACQ_NECROLORD"] = "Nekrolord-Pakt-Feature"
    L["ACQ_ARGENT_TOURNAMENT"] = "Ehrfürchtig beim Argentumkreuzzug + Streiter der Fraktion beim Argentumturnier"
    L["ACQ_HELLSCREAMS_REACH"] = "Ehrfürchtig bei Höllschreis Hand (Tol-Barad-Dailys)"
    L["ACQ_BARADINS_WARDENS"] = "Ehrfürchtig bei Baradins Wächter (Tol-Barad-Dailys)"
    L["ACQ_KARAZHAN_OPERA"] = "Drop vom Großen Bösen Wolf (Oper) in Karazhan"
    L["ACQ_ICC_LK25"] = "Drop vom heroischen Lichkönig 25 in der Eiskronenzitadelle"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "Ruf"
    L["REQ_QUEST"] = "Quest"
    L["REQ_ACHIEVEMENT"] = "Erfolg"
    L["REQ_COMPLETE"] = "Abgeschlossen"
    L["REQ_IN_PROGRESS"] = "In Bearbeitung"
    L["REQ_NOT_STARTED"] = "Nicht begonnen"
    L["REQ_CURRENT"] = "Aktuell"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "Nach Ziel gruppieren"
    L["GROUP_BY_DEST_TT"] = "Teleports nach Zielzone gruppieren"
    L["TELEPORTS_COUNT"] = "%d Teleports"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "Spielzeugsammlung (accountweit)"
    L["LOC_IN_BAGS"] = "In Taschen (Tasche %d, Platz %d)"
    L["LOC_IN_BANK_MAIN"] = "In Bank (Hauptfach)"
    L["LOC_IN_BANK_BAG"] = "In Bank (Tasche %d)"
    L["LOC_BANK_OR_BAGS"] = "Ort: Bank oder Taschen (Bank besuchen zum Prüfen)"
    L["LOC_VENDOR"] = "Händler:"
    L["LOC_LOCATION"] = "Ort:"

    -- Availability filter
    L["AVAIL_ALL"] = "Alle anzeigen"
    L["AVAIL_USABLE"] = "Jetzt nutzbar"
    L["AVAIL_OBTAINABLE"] = "Erhältlich"
    L["AVAIL_FILTER_TT"] = "Filter wechseln: Alle (alles) / Jetzt nutzbar (bereit, im Besitz) / Erhältlich (besessen + erhältlich, ohne Fraktions-/Klassenbeschränkung)"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - Routenfenster | /qrteleports - Inventar | /qrtest graph - Tests ausführen"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "Symbol-Buttons verwenden"
    L["SETTINGS_ICON_BUTTONS_TT"] = "Textbeschriftungen auf Buttons durch Symbole ersetzen für eine kompaktere Oberfläche"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "Linksklick: Teleport verwenden"
    L["MAP_BTN_RIGHT_CLICK"] = "Rechtsklick: Route anzeigen"
    L["MAP_BTN_CTRL_RIGHT"] = "Strg+Rechtsklick auf Karte: Route zum Ort"
    L["QUEST_TRACK_HINT"] = "Shift+Klick auf Quest: Route zum Ziel"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "Keine Teleporte für diese Zone"
    L["SIDEBAR_COLLAPSE_TT"] = "Klicken zum Ein-/Ausklappen"

    -- Main frame tabs
    L["TAB_ROUTE"] = "Route"
    L["TAB_TELEPORTS"] = "Teleporte"
    L["FILTER_OPTIONS"] = "Filteroptionen"
end

-------------------------------------------------------------------------------
-- French translations (frFR)
-------------------------------------------------------------------------------
if GetLocale() == "frFR" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s chargé"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute ERREUR :|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute ATTENTION|r : "
    L["ADDON_FIRST_RUN"] = "Tapez |cFFFFFF00/qr|r pour ouvrir ou |cFFFFFF00/qrhelp|r pour les commandes."
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r : "
    L["MINIMAP_SHOWN"] = "Bouton minimap affiché"
    L["MINIMAP_HIDDEN"] = "Bouton minimap masqué"
    L["PRIORITY_SET_TO"] = "Priorité du waypoint définie sur '%s'"
    L["PRIORITY_USAGE"] = "Usage : /qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "Priorité actuelle"

    -- UI Elements
    L["DESTINATION"] = "Destination :"
    L["NO_WAYPOINT"] = "Aucun point de passage défini"
    L["REFRESH"] = "Actualiser"
    L["COPY_DEBUG"] = "Copier Debug"
    L["ZONE_INFO"] = "Info Zone"
    L["INVENTORY"] = "Inventaire"
    L["NAV"] = "Nav"
    L["USE"] = "Utiliser"
    L["CLOSE"] = "Fermer"
    L["FILTER"] = "Filtre :"
    L["ALL"] = "Tous"
    L["ITEMS"] = "Objets"
    L["TOYS"] = "Jouets"
    L["SPELLS"] = "Sorts"

    -- Status Labels
    L["STATUS_READY"] = "PRÊT"
    L["STATUS_ON_CD"] = "EN RA"
    L["STATUS_OWNED"] = "POSSÉDÉ"
    L["STATUS_MISSING"] = "MANQUANT"
    L["STATUS_NA"] = "N/D"

    -- Panels
    L["TELEPORT_INVENTORY"] = "Inventaire de téléportation"
    L["COPY_DEBUG_TITLE"] = "Copier les infos de debug (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "Calcul en cours..."
    L["SCANNING"] = "Analyse..."
    L["IN_COMBAT"] = "En combat"
    L["CANNOT_USE_IN_COMBAT"] = "Inutilisable en combat"
    L["WAYPOINT_SET"] = "Point de passage défini pour %s"
    L["NO_PATH_FOUND"] = "Aucun itinéraire trouvé"
    L["NO_DESTINATION"] = "Pas de destination pour cette étape"
    L["CANNOT_FIND_LOCATION"] = "Impossible de trouver l'emplacement de %s"
    L["SET_WAYPOINT_HINT"] = "Définir un point de passage pour calculer l'itinéraire"
    L["PATH_CALCULATION_ERROR"] = "Erreur de calcul d'itinéraire"
    L["DESTINATION_NOT_REACHABLE"] = "Destination inaccessible avec les téléportations actuelles"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "Mode debug activé"
    L["DEBUG_MODE_DISABLED"] = "Mode debug désactivé"
    L["TRAVEL_GRAPH_BUILT"] = "Graphe de voyage construit"
    L["FOUND_TELEPORTS"] = "%d méthodes de téléportation trouvées"
    L["UI_INITIALIZED"] = "Interface initialisée"
    L["TELEPORT_PANEL_INITIALIZED"] = "Panneau de téléportation initialisé"
    L["SECURE_BUTTONS_INITIALIZED"] = "Boutons sécurisés initialisés avec %d boutons"
    L["POOL_EXHAUSTED"] = "Pool de boutons sécurisés épuisé (%d boutons utilisés)"

    -- Summary
    L["SHOWING_TELEPORTS"] = "%d téléportations affichées | %d possédées | %d prêtes"
    L["ESTIMATED_TRAVEL_TIME"] = "%s temps de trajet estimé"
    L["SOURCE"] = "Source"
    L["SOURCE_MAP_PIN"] = "Repère sur la carte"
    L["SOURCE_MAP_CLICK"] = "Clic sur la carte"
    L["SOURCE_QUEST"] = "Objectif de quête"
    L["NO_ROUTE_HINT"] = "Essayez une autre destination ou analysez les téléportations (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "Cible :"
    L["WAYPOINT_AUTO"] = "Auto"
    L["WAYPOINT_MAP_PIN"] = "Repère carte"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "Quête"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "Choisir le point de passage pour la navigation"
    L["NO_WAYPOINTS_AVAILABLE"] = "Aucun point de passage disponible"

    -- Column Headers
    L["NAME"] = "Nom"
    L["DESTINATION_HEADER"] = "Destination"
    L["STATUS"] = "Statut"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "Recalculer l'itinéraire vers votre point de passage"
    L["TOOLTIP_DEBUG"] = "Copier les informations de debug dans le presse-papiers"
    L["TOOLTIP_ZONE"] = "Copier les informations de zone dans le presse-papiers"
    L["TOOLTIP_TELEPORTS"] = "Ouvrir le panneau d'inventaire de téléportation"
    L["TOOLTIP_NAV"] = "Définir un point de navigation vers cette destination"
    L["TOOLTIP_USE"] = "Utiliser cette téléportation"

    -- Action Types
    L["ACTION_TELEPORT"] = "Téléportation"
    L["ACTION_WALK"] = "Marcher"
    L["ACTION_FLY"] = "Voler"
    L["ACTION_PORTAL"] = "Portail"
    L["ACTION_HEARTHSTONE"] = "Pierre de foyer"
    L["ACTION_USE_TELEPORT"] = "Utiliser %s pour se téléporter à %s"
    L["ACTION_USE"] = "Utiliser %s"
    L["ACTION_BOAT"] = "Bateau"
    L["ACTION_ZEPPELIN"] = "Zeppelin"
    L["ACTION_TRAM"] = "Tram"
    L["ACTION_TRAVEL"] = "Voyager"
    L["COOLDOWN_SHORT"] = "RA"

    -- Step Descriptions
    L["STEP_GO_TO"] = "Aller à %s"
    L["STEP_GO_TO_IN_ZONE"] = "Aller à %s dans %s"
    L["STEP_TAKE_PORTAL"] = "Prendre le portail vers %s"
    L["STEP_TAKE_BOAT"] = "Prendre le bateau vers %s"
    L["STEP_TAKE_ZEPPELIN"] = "Prendre le zeppelin vers %s"
    L["STEP_TAKE_TRAM"] = "Prendre le Tram des profondeurs vers %s"
    L["STEP_TELEPORT_TO"] = "Se téléporter à %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "terminé"
    L["STEP_CURRENT"] = "en cours"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "Point de passage auto : "
    L["AUTO_WAYPOINT_ON"] = "ACTIVÉ (définira un point TomTom/natif pour la première étape)"
    L["AUTO_WAYPOINT_OFF"] = "DÉSACTIVÉ (navigation intégrée de WoW utilisée)"
    L["SETTINGS_GENERAL"] = "Général"
    L["SETTINGS_NAVIGATION"] = "Navigation"
    L["SETTINGS_SHOW_MINIMAP"] = "Afficher le bouton Minicarte"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "Afficher ou masquer le bouton de la minicarte"
    L["SETTINGS_AUTO_WAYPOINT"] = "Point de passage auto pour la première étape"
    L["SETTINGS_CONSIDER_CD"] = "Prendre en compte les temps de recharge"
    L["SETTINGS_CONSIDER_CD_TT"] = "Intégrer les temps de recharge des téléportations dans le calcul d'itinéraire"
    L["SETTINGS_AUTO_DEST"] = "Afficher l'itinéraire auto lors du suivi de quête"
    L["SETTINGS_AUTO_DEST_TT"] = "Calculer et afficher automatiquement l'itinéraire lors du suivi d'une nouvelle quête"
    L["SETTINGS_ROUTING"] = "Itinéraire"
    L["SETTINGS_MAX_COOLDOWN"] = "Temps de recharge max (heures)"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "Exclure les téléportations avec un temps de recharge supérieur"
    L["SETTINGS_LOADING_TIME"] = "Temps d'écran de chargement (secondes)"
    L["SETTINGS_LOADING_TIME_TT"] = "Ajoute ces secondes à chaque téléportation/portail dans le calcul d'itinéraire pour les écrans de chargement. Des valeurs plus élevées favorisent la marche. Réglez à 0 pour ignorer."
    L["SETTINGS_APPEARANCE"] = "Apparence"
    L["SETTINGS_WINDOW_SCALE"] = "Échelle de la fenêtre"
    L["SETTINGS_WINDOW_SCALE_TT"] = "Échelle des fenêtres d'itinéraire et de téléportation (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "Atteignez n'importe quelle destination le plus facilement et rapidement possible."
    L["SETTINGS_FEATURES"] = "Fonctionnalités"
    L["SETTINGS_FEAT_ROUTING"] = "Itinéraire optimal"
    L["SETTINGS_FEAT_TELEPORTS"] = "Explorateur de téléportations"
    L["SETTINGS_FEAT_MAPBUTTON"] = "Bouton carte du monde"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "Boutons du suivi de quêtes"
    L["SETTINGS_FEAT_COLLAPSING"] = "Regroupement d'itinéraire"
    L["SETTINGS_FEAT_AUTODEST"] = "Destination automatique"
    L["SETTINGS_FEAT_POIROUTING"] = "Itinéraire par clic sur la carte"
    L["SETTINGS_FEAT_DESTGROUP"] = "Regroupement par destination"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "Clic gauche : Afficher/masquer la fenêtre d'itinéraire"
    L["TOOLTIP_MINIMAP_RIGHT"] = "Clic droit : Inventaire de téléportation"
    L["TOOLTIP_MINIMAP_DRAG"] = "Glisser : Déplacer le bouton"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "Clic molette : Téléportations rapides"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "Téléportations rapides"
    L["MINI_PANEL_NO_TELEPORTS"] = "Aucune téléportation disponible"
    L["MINI_PANEL_SUMMON_MOUNT"] = "Invoquer la monture"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "Favori aléatoire"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "Donjons & Raids"
    L["DUNGEON_PICKER_SEARCH"] = "Rechercher..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "Aucune instance correspondante"
    L["DUNGEON_ROUTE_TO"] = "Itinéraire vers l'entrée"
    L["DUNGEON_ROUTE_TO_TT"] = "Calculer l'itinéraire le plus rapide vers l'entrée de ce donjon"
    L["DUNGEON_TAG"] = "Donjon"
    L["DUNGEON_RAID_TAG"] = "Raid"
    L["DUNGEON_ENTRANCE"] = "Entrée de %s"
    L["EJ_ROUTE_BUTTON_TT"] = "Itinéraire vers l'entrée de cette instance"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "Rechercher destinations..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Point de passage actif"
    L["DEST_SEARCH_CITIES"] = "Villes"
    L["DEST_SEARCH_DUNGEONS"] = "Donjons & Raids"
    L["DEST_SEARCH_NO_RESULTS"] = "Aucune destination correspondante"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "Cliquer pour calculer l'itineraire"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "Hotel des ventes"
    L["SERVICE_BANK"] = "Banque"
    L["SERVICE_VOID_STORAGE"] = "Coffre du Vide"
    L["SERVICE_CRAFTING_TABLE"] = "Table d'artisanat"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "Hôtel des ventes le plus proche"
    L["SERVICE_NEAREST_BANK"] = "Banque la plus proche"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "Stockage du Vide le plus proche"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "Table d'artisanat la plus proche"
    L["DEST_SEARCH_SERVICES"] = "Services"

    -- Errors / Hints
    L["UNKNOWN"] = "Inconnu"
    L["UNKNOWN_VENDOR"] = "Vendeur inconnu"
    L["QUEST_FALLBACK"] = "Quête n°%d"
    L["TELEPORT_FALLBACK"] = "Téléport"
    L["NO_LIMIT"] = "Sans limite"
    L["WAYPOINT_DETECTION_FAILED"] = "Échec de la détection du point de passage"
    L["TOOLTIP_RESCAN"] = "Réanalyser l'inventaire pour les objets de téléportation"
    L["HOW_TO_OBTAIN"] = "Comment l'obtenir :"
    L["HINT_CHECK_TOY_VENDORS"] = "Vérifiez les vendeurs de jouets, les butins ou les hauts faits"
    L["HINT_REQUIRES_ENGINEERING"] = "Nécessite la profession Ingénierie"
    L["HINT_CHECK_WOWHEAD"] = "Consultez Wowhead pour les détails d'obtention"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "Lieu de liaison"
    L["DEST_GARRISON"] = "Fief"
    L["DEST_GARRISON_SHIPYARD"] = "Chantier naval du fief"
    L["DEST_CAMP_LOCATION"] = "Emplacement du camp"
    L["DEST_RANDOM"] = "Lieu aléatoire"
    L["DEST_ILLIDARI_CAMP"] = "Camp illidari"
    L["DEST_RANDOM_NORTHREND"] = "Lieu aléatoire en Norfendre"
    L["DEST_RANDOM_PANDARIA"] = "Lieu aléatoire en Pandarie"
    L["DEST_RANDOM_DRAENOR"] = "Lieu aléatoire en Draenor"
    L["DEST_RANDOM_ARGUS"] = "Lieu aléatoire sur Argus"
    L["DEST_RANDOM_KUL_TIRAS"] = "Lieu aléatoire à Kul Tiras"
    L["DEST_RANDOM_ZANDALAR"] = "Lieu aléatoire à Zandalar"
    L["DEST_RANDOM_SHADOWLANDS"] = "Lieu aléatoire dans les Ombreterre"
    L["DEST_RANDOM_DRAGON_ISLES"] = "Lieu aléatoire aux Îles des Dragons"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "Lieu aléatoire à Khaz Algar"
    L["DEST_HOMESTEAD"] = "Propriété"
    L["DEST_RANDOM_WORLDWIDE"] = "Lieu aléatoire mondial"
    L["DEST_RANDOM_NATURAL"] = "Lieu naturel aléatoire"
    L["DEST_RANDOM_BROKEN_ISLES"] = "Ligne tellurique aléatoire des Îles Brisées"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "Récompense de quête de l'introduction de Legion"
    L["ACQ_WOD_INTRO"] = "Récompense de quête de l'introduction de Warlords of Draenor"
    L["ACQ_KYRIAN"] = "Fonctionnalité du pacte kyrien"
    L["ACQ_VENTHYR"] = "Fonctionnalité du pacte venthyr"
    L["ACQ_NIGHT_FAE"] = "Fonctionnalité du pacte faë nocturne"
    L["ACQ_NECROLORD"] = "Fonctionnalité du pacte nécro-seigneur"
    L["ACQ_ARGENT_TOURNAMENT"] = "Exalté auprès de la Croisade d'argent + Champion au Tournoi d'argent"
    L["ACQ_HELLSCREAMS_REACH"] = "Exalté auprès du Poing de Hurlenfer (quêtes journalières de Tol Barad)"
    L["ACQ_BARADINS_WARDENS"] = "Exalté auprès des Gardiens de Baradin (quêtes journalières de Tol Barad)"
    L["ACQ_KARAZHAN_OPERA"] = "Butin du Grand méchant loup (Opéra) à Karazhan"
    L["ACQ_ICC_LK25"] = "Butin du Roi-liche héroïque 25 à la Citadelle de la Couronne de glace"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "Réputation"
    L["REQ_QUEST"] = "Quête"
    L["REQ_ACHIEVEMENT"] = "Haut fait"
    L["REQ_COMPLETE"] = "Terminé"
    L["REQ_IN_PROGRESS"] = "En cours"
    L["REQ_NOT_STARTED"] = "Non commencé"
    L["REQ_CURRENT"] = "Actuel"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "Grouper par destination"
    L["GROUP_BY_DEST_TT"] = "Grouper les téléportations par zone de destination"
    L["TELEPORTS_COUNT"] = "%d téléportations"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "Collection de jouets (tout le compte)"
    L["LOC_IN_BAGS"] = "Dans les sacs (Sac %d, Emplacement %d)"
    L["LOC_IN_BANK_MAIN"] = "En banque (Principal)"
    L["LOC_IN_BANK_BAG"] = "En banque (Sac %d)"
    L["LOC_BANK_OR_BAGS"] = "Emplacement : Banque ou sacs (visitez la banque pour vérifier)"
    L["LOC_VENDOR"] = "Vendeur :"
    L["LOC_LOCATION"] = "Emplacement :"

    -- Availability filter
    L["AVAIL_ALL"] = "Tout afficher"
    L["AVAIL_USABLE"] = "Utilisable"
    L["AVAIL_OBTAINABLE"] = "Obtenable"
    L["AVAIL_FILTER_TT"] = "Changer le filtre : Tout / Utilisable (prêt, possédé) / Obtenable (possédé + obtenable, exclut faction/classe)"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - Fenêtre de route | /qrteleports - Inventaire | /qrtest graph - Lancer les tests"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "Utiliser les boutons icônes"
    L["SETTINGS_ICON_BUTTONS_TT"] = "Remplacer les libellés texte par des icônes pour une interface plus compacte"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "Clic gauche : Utiliser le téléport"
    L["MAP_BTN_RIGHT_CLICK"] = "Clic droit : Afficher l'itinéraire"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+Clic droit sur la carte : Itinéraire vers ce lieu"
    L["QUEST_TRACK_HINT"] = "Shift+Clic sur quête : Itinéraire vers l'objectif"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "Aucun téléport pour cette zone"
    L["SIDEBAR_COLLAPSE_TT"] = "Cliquer pour réduire/développer"

    -- Main frame tabs
    L["TAB_ROUTE"] = "Itinéraire"
    L["TAB_TELEPORTS"] = "Téléports"
    L["FILTER_OPTIONS"] = "Options de filtre"
end

-------------------------------------------------------------------------------
-- Spanish translations (esES / esMX)
-------------------------------------------------------------------------------
local esLocale = GetLocale()
if esLocale == "esES" or esLocale == "esMX" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s cargado"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute ERROR:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute AVISO|r: "
    L["ADDON_FIRST_RUN"] = "Escribe |cFFFFFF00/qr|r para abrir o |cFFFFFF00/qrhelp|r para comandos."
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "Botón del minimapa visible"
    L["MINIMAP_HIDDEN"] = "Botón del minimapa oculto"
    L["PRIORITY_SET_TO"] = "Prioridad del waypoint establecida en '%s'"
    L["PRIORITY_USAGE"] = "Uso: /qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "Prioridad actual"

    -- UI Elements
    L["DESTINATION"] = "Destino:"
    L["NO_WAYPOINT"] = "Sin punto de referencia"
    L["REFRESH"] = "Actualizar"
    L["COPY_DEBUG"] = "Copiar Debug"
    L["ZONE_INFO"] = "Info de Zona"
    L["INVENTORY"] = "Inventario"
    L["NAV"] = "Nav"
    L["USE"] = "Usar"
    L["CLOSE"] = "Cerrar"
    L["FILTER"] = "Filtro:"
    L["ALL"] = "Todo"
    L["ITEMS"] = "Objetos"
    L["TOYS"] = "Juguetes"
    L["SPELLS"] = "Hechizos"

    -- Status Labels
    L["STATUS_READY"] = "LISTO"
    L["STATUS_ON_CD"] = "EN RE"
    L["STATUS_OWNED"] = "POSEÍDO"
    L["STATUS_MISSING"] = "FALTA"
    L["STATUS_NA"] = "N/D"

    -- Panels
    L["TELEPORT_INVENTORY"] = "Inventario de teletransporte"
    L["COPY_DEBUG_TITLE"] = "Copiar info de debug (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "Calculando..."
    L["SCANNING"] = "Escaneando..."
    L["IN_COMBAT"] = "En combate"
    L["CANNOT_USE_IN_COMBAT"] = "No se puede usar en combate"
    L["WAYPOINT_SET"] = "Punto de referencia establecido para %s"
    L["NO_PATH_FOUND"] = "No se encontró ruta"
    L["NO_DESTINATION"] = "Sin destino para este paso"
    L["CANNOT_FIND_LOCATION"] = "No se puede encontrar la ubicación de %s"
    L["SET_WAYPOINT_HINT"] = "Establece un punto de referencia para calcular la ruta"
    L["PATH_CALCULATION_ERROR"] = "Error al calcular la ruta"
    L["DESTINATION_NOT_REACHABLE"] = "Destino inalcanzable con los teletransportes actuales"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "Modo debug activado"
    L["DEBUG_MODE_DISABLED"] = "Modo debug desactivado"
    L["TRAVEL_GRAPH_BUILT"] = "Grafo de viaje construido"
    L["FOUND_TELEPORTS"] = "%d métodos de teletransporte encontrados"
    L["UI_INITIALIZED"] = "Interfaz inicializada"
    L["TELEPORT_PANEL_INITIALIZED"] = "Panel de teletransporte inicializado"
    L["SECURE_BUTTONS_INITIALIZED"] = "Botones seguros inicializados con %d botones"
    L["POOL_EXHAUSTED"] = "Pool de botones seguros agotado (%d botones en uso)"

    -- Summary
    L["SHOWING_TELEPORTS"] = "Mostrando %d teletransportes | %d poseídos | %d listos"
    L["ESTIMATED_TRAVEL_TIME"] = "%s tiempo de viaje estimado"
    L["SOURCE"] = "Fuente"
    L["SOURCE_MAP_PIN"] = "Marcador del mapa"
    L["SOURCE_MAP_CLICK"] = "Clic en el mapa"
    L["SOURCE_QUEST"] = "Objetivo de misión"
    L["NO_ROUTE_HINT"] = "Prueba otro destino o escanea teletransportes (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "Objetivo:"
    L["WAYPOINT_AUTO"] = "Auto"
    L["WAYPOINT_MAP_PIN"] = "Marcador"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "Misión"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "Seleccionar punto de referencia para la navegación"
    L["NO_WAYPOINTS_AVAILABLE"] = "No hay puntos de referencia disponibles"

    -- Column Headers
    L["NAME"] = "Nombre"
    L["DESTINATION_HEADER"] = "Destino"
    L["STATUS"] = "Estado"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "Recalcular la ruta hacia tu punto de referencia"
    L["TOOLTIP_DEBUG"] = "Copiar información de debug al portapapeles"
    L["TOOLTIP_ZONE"] = "Copiar información de zona al portapapeles"
    L["TOOLTIP_TELEPORTS"] = "Abrir panel de inventario de teletransporte"
    L["TOOLTIP_NAV"] = "Establecer punto de navegación a este destino"
    L["TOOLTIP_USE"] = "Usar este teletransporte"

    -- Action Types
    L["ACTION_TELEPORT"] = "Teletransporte"
    L["ACTION_WALK"] = "Caminar"
    L["ACTION_FLY"] = "Volar"
    L["ACTION_PORTAL"] = "Portal"
    L["ACTION_HEARTHSTONE"] = "Piedra de hogar"
    L["ACTION_USE_TELEPORT"] = "Usar %s para teletransportarse a %s"
    L["ACTION_USE"] = "Usar %s"
    L["ACTION_BOAT"] = "Barco"
    L["ACTION_ZEPPELIN"] = "Zepelín"
    L["ACTION_TRAM"] = "Tranvía"
    L["ACTION_TRAVEL"] = "Viajar"
    L["COOLDOWN_SHORT"] = "RE"

    -- Step Descriptions
    L["STEP_GO_TO"] = "Ir a %s"
    L["STEP_GO_TO_IN_ZONE"] = "Ir a %s en %s"
    L["STEP_TAKE_PORTAL"] = "Tomar portal a %s"
    L["STEP_TAKE_BOAT"] = "Tomar barco a %s"
    L["STEP_TAKE_ZEPPELIN"] = "Tomar zepelín a %s"
    L["STEP_TAKE_TRAM"] = "Tomar Tranvía Subterráneo a %s"
    L["STEP_TELEPORT_TO"] = "Teletransportarse a %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "completado"
    L["STEP_CURRENT"] = "actual"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "Punto de referencia auto: "
    L["AUTO_WAYPOINT_ON"] = "ACTIVADO (establecerá punto TomTom/nativo para el primer paso)"
    L["AUTO_WAYPOINT_OFF"] = "DESACTIVADO (se usa la navegación integrada de WoW)"
    L["SETTINGS_GENERAL"] = "General"
    L["SETTINGS_NAVIGATION"] = "Navegación"
    L["SETTINGS_SHOW_MINIMAP"] = "Mostrar botón del minimapa"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "Mostrar u ocultar el botón del minimapa"
    L["SETTINGS_AUTO_WAYPOINT"] = "Establecer punto de referencia auto para el primer paso"
    L["SETTINGS_CONSIDER_CD"] = "Considerar tiempos de reutilización en la ruta"
    L["SETTINGS_CONSIDER_CD_TT"] = "Incluir tiempos de reutilización de teletransporte en el cálculo de ruta"
    L["SETTINGS_AUTO_DEST"] = "Mostrar ruta auto al seguir misiones"
    L["SETTINGS_AUTO_DEST_TT"] = "Calcular y mostrar automáticamente la ruta al seguir una nueva misión"
    L["SETTINGS_ROUTING"] = "Cálculo de ruta"
    L["SETTINGS_MAX_COOLDOWN"] = "Tiempo de reutilización máx. (horas)"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "Excluir teletransportes con tiempo de reutilización mayor"
    L["SETTINGS_LOADING_TIME"] = "Tiempo de pantalla de carga (segundos)"
    L["SETTINGS_LOADING_TIME_TT"] = "Añade estos segundos a cada teletransporte/portal en el cálculo de ruta para pantallas de carga. Valores más altos prefieren caminar. Pon 0 para ignorar."
    L["SETTINGS_APPEARANCE"] = "Apariencia"
    L["SETTINGS_WINDOW_SCALE"] = "Escala de ventana"
    L["SETTINGS_WINDOW_SCALE_TT"] = "Escala de las ventanas de ruta y teletransporte (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "Llega a cualquier destino de la forma más fácil y rápida posible."
    L["SETTINGS_FEATURES"] = "Características"
    L["SETTINGS_FEAT_ROUTING"] = "Ruta óptima"
    L["SETTINGS_FEAT_TELEPORTS"] = "Explorador de teletransportes"
    L["SETTINGS_FEAT_MAPBUTTON"] = "Botón del mapa del mundo"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "Botones del rastreador de misiones"
    L["SETTINGS_FEAT_COLLAPSING"] = "Compactación de ruta"
    L["SETTINGS_FEAT_AUTODEST"] = "Destino automático"
    L["SETTINGS_FEAT_POIROUTING"] = "Ruta por clic en el mapa"
    L["SETTINGS_FEAT_DESTGROUP"] = "Agrupación por destino"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "Clic izquierdo: Mostrar/ocultar ventana de ruta"
    L["TOOLTIP_MINIMAP_RIGHT"] = "Clic derecho: Inventario de teletransporte"
    L["TOOLTIP_MINIMAP_DRAG"] = "Arrastrar: Mover botón"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "Clic central: Teletransportes rápidos"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "Teletransportes rápidos"
    L["MINI_PANEL_NO_TELEPORTS"] = "No hay teletransportes disponibles"
    L["MINI_PANEL_SUMMON_MOUNT"] = "Invocar montura"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "Favorito aleatorio"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "Mazmorras y bandas"
    L["DUNGEON_PICKER_SEARCH"] = "Buscar..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "No se encontraron instancias"
    L["DUNGEON_ROUTE_TO"] = "Ruta a la entrada"
    L["DUNGEON_ROUTE_TO_TT"] = "Calcular la ruta más rápida a la entrada de esta mazmorra"
    L["DUNGEON_TAG"] = "Mazmorra"
    L["DUNGEON_RAID_TAG"] = "Banda"
    L["DUNGEON_ENTRANCE"] = "Entrada de %s"
    L["EJ_ROUTE_BUTTON_TT"] = "Ruta a la entrada de esta instancia"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "Buscar destinos..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Punto de ruta activo"
    L["DEST_SEARCH_CITIES"] = "Ciudades"
    L["DEST_SEARCH_DUNGEONS"] = "Mazmorras y bandas"
    L["DEST_SEARCH_NO_RESULTS"] = "No se encontraron destinos"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "Clic para calcular la ruta"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "Casa de subastas"
    L["SERVICE_BANK"] = "Banco"
    L["SERVICE_VOID_STORAGE"] = "Depósito del Vacío"
    L["SERVICE_CRAFTING_TABLE"] = "Mesa de artesanía"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "Casa de subastas más cercana"
    L["SERVICE_NEAREST_BANK"] = "Banco más cercano"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "Depósito del Vacío más cercano"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "Mesa de artesanía más cercana"
    L["DEST_SEARCH_SERVICES"] = "Servicios"

    -- Errors / Hints
    L["UNKNOWN"] = "Desconocido"
    L["UNKNOWN_VENDOR"] = "Vendedor desconocido"
    L["QUEST_FALLBACK"] = "Misión n.º %d"
    L["TELEPORT_FALLBACK"] = "Teletransporte"
    L["NO_LIMIT"] = "Sin límite"
    L["WAYPOINT_DETECTION_FAILED"] = "Detección de punto de referencia fallida"
    L["TOOLTIP_RESCAN"] = "Reescanear inventario en busca de objetos de teletransporte"
    L["HOW_TO_OBTAIN"] = "Cómo obtenerlo:"
    L["HINT_CHECK_TOY_VENDORS"] = "Revisa vendedores de juguetes, botines o logros"
    L["HINT_REQUIRES_ENGINEERING"] = "Requiere la profesión Ingeniería"
    L["HINT_CHECK_WOWHEAD"] = "Consulta Wowhead para detalles de obtención"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "Ubicación vinculada"
    L["DEST_GARRISON"] = "Bastión"
    L["DEST_GARRISON_SHIPYARD"] = "Astillero del bastión"
    L["DEST_CAMP_LOCATION"] = "Ubicación del campamento"
    L["DEST_RANDOM"] = "Ubicación aleatoria"
    L["DEST_ILLIDARI_CAMP"] = "Campamento illidari"
    L["DEST_RANDOM_NORTHREND"] = "Ubicación aleatoria en Rasganorte"
    L["DEST_RANDOM_PANDARIA"] = "Ubicación aleatoria en Pandaria"
    L["DEST_RANDOM_DRAENOR"] = "Ubicación aleatoria en Draenor"
    L["DEST_RANDOM_ARGUS"] = "Ubicación aleatoria en Argus"
    L["DEST_RANDOM_KUL_TIRAS"] = "Ubicación aleatoria en Kul Tiras"
    L["DEST_RANDOM_ZANDALAR"] = "Ubicación aleatoria en Zandalar"
    L["DEST_RANDOM_SHADOWLANDS"] = "Ubicación aleatoria en Tierras Sombrías"
    L["DEST_RANDOM_DRAGON_ISLES"] = "Ubicación aleatoria en las Islas Dragón"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "Ubicación aleatoria en Khaz Algar"
    L["DEST_HOMESTEAD"] = "Hogar"
    L["DEST_RANDOM_WORLDWIDE"] = "Ubicación aleatoria mundial"
    L["DEST_RANDOM_NATURAL"] = "Ubicación natural aleatoria"
    L["DEST_RANDOM_BROKEN_ISLES"] = "Línea Ley aleatoria de las Islas Abruptas"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "Recompensa de misión de la introducción de Legion"
    L["ACQ_WOD_INTRO"] = "Recompensa de misión de la introducción de Warlords of Draenor"
    L["ACQ_KYRIAN"] = "Característica del pacto kyrian"
    L["ACQ_VENTHYR"] = "Característica del pacto venthyr"
    L["ACQ_NIGHT_FAE"] = "Característica del pacto sílfide nocturna"
    L["ACQ_NECROLORD"] = "Característica del pacto necroseñor"
    L["ACQ_ARGENT_TOURNAMENT"] = "Exaltado con la Cruzada Argenta + Campeón en el Torneo Argenta"
    L["ACQ_HELLSCREAMS_REACH"] = "Exaltado con el Dominio de Grito Infernal (diarias de Tol Barad)"
    L["ACQ_BARADINS_WARDENS"] = "Exaltado con los Custodios de Baradin (diarias de Tol Barad)"
    L["ACQ_KARAZHAN_OPERA"] = "Botín del Gran Lobo Malvado (Ópera) en Karazhan"
    L["ACQ_ICC_LK25"] = "Botín del Rey Exánime heroico 25 en Ciudadela de la Corona de Hielo"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "Reputación"
    L["REQ_QUEST"] = "Misión"
    L["REQ_ACHIEVEMENT"] = "Logro"
    L["REQ_COMPLETE"] = "Completado"
    L["REQ_IN_PROGRESS"] = "En progreso"
    L["REQ_NOT_STARTED"] = "No iniciado"
    L["REQ_CURRENT"] = "Actual"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "Agrupar por destino"
    L["GROUP_BY_DEST_TT"] = "Agrupar teletransportes por zona de destino"
    L["TELEPORTS_COUNT"] = "%d teletransportes"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "Colección de juguetes (toda la cuenta)"
    L["LOC_IN_BAGS"] = "En bolsas (Bolsa %d, Espacio %d)"
    L["LOC_IN_BANK_MAIN"] = "En banco (Principal)"
    L["LOC_IN_BANK_BAG"] = "En banco (Bolsa %d)"
    L["LOC_BANK_OR_BAGS"] = "Ubicación: Banco o bolsas (visita el banco para verificar)"
    L["LOC_VENDOR"] = "Vendedor:"
    L["LOC_LOCATION"] = "Ubicación:"

    -- Availability filter
    L["AVAIL_ALL"] = "Mostrar todo"
    L["AVAIL_USABLE"] = "Usable ahora"
    L["AVAIL_OBTAINABLE"] = "Obtenible"
    L["AVAIL_FILTER_TT"] = "Cambiar filtro: Todo / Usable ahora (listo, poseído) / Obtenible (poseído + obtenible, excluye facción/clase)"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - Ventana de ruta | /qrteleports - Inventario | /qrtest graph - Ejecutar tests"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "Usar botones de icono"
    L["SETTINGS_ICON_BUTTONS_TT"] = "Reemplazar etiquetas de texto con iconos para una interfaz más compacta"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "Clic izquierdo: Usar teletransporte"
    L["MAP_BTN_RIGHT_CLICK"] = "Clic derecho: Mostrar ruta"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+Clic derecho en mapa: Ruta a ubicación"
    L["QUEST_TRACK_HINT"] = "Shift+Clic en misión: Ruta al objetivo"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "No hay teletransportes para esta zona"
    L["SIDEBAR_COLLAPSE_TT"] = "Clic para contraer/expandir"

    -- Main frame tabs
    L["TAB_ROUTE"] = "Ruta"
    L["TAB_TELEPORTS"] = "Teletransportes"
    L["FILTER_OPTIONS"] = "Opciones de filtro"
end

-------------------------------------------------------------------------------
-- Brazilian Portuguese translations (ptBR)
-------------------------------------------------------------------------------
if GetLocale() == "ptBR" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s carregado"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute ERRO:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute AVISO|r: "
    L["ADDON_FIRST_RUN"] = "Digite |cFFFFFF00/qr|r para abrir ou |cFFFFFF00/qrhelp|r para comandos."
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "Botão do minimapa exibido"
    L["MINIMAP_HIDDEN"] = "Botão do minimapa oculto"
    L["PRIORITY_SET_TO"] = "Prioridade do waypoint definida para '%s'"
    L["PRIORITY_USAGE"] = "Uso: /qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "Prioridade atual"

    -- UI Elements
    L["DESTINATION"] = "Destino:"
    L["NO_WAYPOINT"] = "Nenhum ponto de referência definido"
    L["REFRESH"] = "Atualizar"
    L["COPY_DEBUG"] = "Copiar Debug"
    L["ZONE_INFO"] = "Info da Zona"
    L["INVENTORY"] = "Inventário"
    L["NAV"] = "Nav"
    L["USE"] = "Usar"
    L["CLOSE"] = "Fechar"
    L["FILTER"] = "Filtro:"
    L["ALL"] = "Tudo"
    L["ITEMS"] = "Itens"
    L["TOYS"] = "Brinquedos"
    L["SPELLS"] = "Feitiços"

    -- Status Labels
    L["STATUS_READY"] = "PRONTO"
    L["STATUS_ON_CD"] = "EM REC"
    L["STATUS_OWNED"] = "POSSUI"
    L["STATUS_MISSING"] = "FALTA"
    L["STATUS_NA"] = "N/D"

    -- Panels
    L["TELEPORT_INVENTORY"] = "Inventário de teletransporte"
    L["COPY_DEBUG_TITLE"] = "Copiar info de debug (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "Calculando..."
    L["SCANNING"] = "Escaneando..."
    L["IN_COMBAT"] = "Em combate"
    L["CANNOT_USE_IN_COMBAT"] = "Não é possível usar em combate"
    L["WAYPOINT_SET"] = "Ponto de referência definido para %s"
    L["NO_PATH_FOUND"] = "Nenhuma rota encontrada"
    L["NO_DESTINATION"] = "Sem destino para esta etapa"
    L["CANNOT_FIND_LOCATION"] = "Não foi possível encontrar a localização de %s"
    L["SET_WAYPOINT_HINT"] = "Defina um ponto de referência para calcular a rota"
    L["PATH_CALCULATION_ERROR"] = "Erro ao calcular a rota"
    L["DESTINATION_NOT_REACHABLE"] = "Destino inacessível com os teletransportes atuais"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "Modo debug ativado"
    L["DEBUG_MODE_DISABLED"] = "Modo debug desativado"
    L["TRAVEL_GRAPH_BUILT"] = "Grafo de viagem construído"
    L["FOUND_TELEPORTS"] = "%d métodos de teletransporte encontrados"
    L["UI_INITIALIZED"] = "Interface inicializada"
    L["TELEPORT_PANEL_INITIALIZED"] = "Painel de teletransporte inicializado"
    L["SECURE_BUTTONS_INITIALIZED"] = "Botões seguros inicializados com %d botões"
    L["POOL_EXHAUSTED"] = "Pool de botões seguros esgotado (%d botões em uso)"

    -- Summary
    L["SHOWING_TELEPORTS"] = "Mostrando %d teletransportes | %d possuídos | %d prontos"
    L["ESTIMATED_TRAVEL_TIME"] = "%s tempo de viagem estimado"
    L["SOURCE"] = "Fonte"
    L["SOURCE_MAP_PIN"] = "Marcador do mapa"
    L["SOURCE_MAP_CLICK"] = "Clique no mapa"
    L["SOURCE_QUEST"] = "Objetivo de missão"
    L["NO_ROUTE_HINT"] = "Tente outro destino ou escaneie teletransportes (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "Alvo:"
    L["WAYPOINT_AUTO"] = "Auto"
    L["WAYPOINT_MAP_PIN"] = "Marcador"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "Missão"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "Selecionar ponto de referência para navegação"
    L["NO_WAYPOINTS_AVAILABLE"] = "Nenhum ponto de referência disponível"

    -- Column Headers
    L["NAME"] = "Nome"
    L["DESTINATION_HEADER"] = "Destino"
    L["STATUS"] = "Status"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "Recalcular a rota até seu ponto de referência"
    L["TOOLTIP_DEBUG"] = "Copiar informações de debug para a área de transferência"
    L["TOOLTIP_ZONE"] = "Copiar informações de zona para a área de transferência"
    L["TOOLTIP_TELEPORTS"] = "Abrir painel de inventário de teletransporte"
    L["TOOLTIP_NAV"] = "Definir ponto de navegação para este destino"
    L["TOOLTIP_USE"] = "Usar este teletransporte"

    -- Action Types
    L["ACTION_TELEPORT"] = "Teletransporte"
    L["ACTION_WALK"] = "Caminhar"
    L["ACTION_FLY"] = "Voar"
    L["ACTION_PORTAL"] = "Portal"
    L["ACTION_HEARTHSTONE"] = "Pedra de regresso"
    L["ACTION_USE_TELEPORT"] = "Usar %s para se teletransportar para %s"
    L["ACTION_USE"] = "Usar %s"
    L["ACTION_BOAT"] = "Barco"
    L["ACTION_ZEPPELIN"] = "Zepelim"
    L["ACTION_TRAM"] = "Metrô"
    L["ACTION_TRAVEL"] = "Viajar"
    L["COOLDOWN_SHORT"] = "REC"

    -- Step Descriptions
    L["STEP_GO_TO"] = "Ir para %s"
    L["STEP_GO_TO_IN_ZONE"] = "Ir para %s em %s"
    L["STEP_TAKE_PORTAL"] = "Pegar portal para %s"
    L["STEP_TAKE_BOAT"] = "Pegar barco para %s"
    L["STEP_TAKE_ZEPPELIN"] = "Pegar zepelim para %s"
    L["STEP_TAKE_TRAM"] = "Pegar Metrô Subterrâneo para %s"
    L["STEP_TELEPORT_TO"] = "Teletransportar para %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "concluído"
    L["STEP_CURRENT"] = "atual"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "Ponto de referência auto: "
    L["AUTO_WAYPOINT_ON"] = "LIGADO (definirá ponto TomTom/nativo para a primeira etapa)"
    L["AUTO_WAYPOINT_OFF"] = "DESLIGADO (navegação integrada do WoW usada)"
    L["SETTINGS_GENERAL"] = "Geral"
    L["SETTINGS_NAVIGATION"] = "Navegação"
    L["SETTINGS_SHOW_MINIMAP"] = "Mostrar botão do minimapa"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "Mostrar ou ocultar o botão do minimapa"
    L["SETTINGS_AUTO_WAYPOINT"] = "Definir ponto de referência auto para a primeira etapa"
    L["SETTINGS_CONSIDER_CD"] = "Considerar recarga no cálculo de rota"
    L["SETTINGS_CONSIDER_CD_TT"] = "Incluir tempos de recarga de teletransporte no cálculo de rota"
    L["SETTINGS_AUTO_DEST"] = "Mostrar rota auto ao rastrear missões"
    L["SETTINGS_AUTO_DEST_TT"] = "Calcular e mostrar automaticamente a rota ao rastrear uma nova missão"
    L["SETTINGS_ROUTING"] = "Cálculo de rota"
    L["SETTINGS_MAX_COOLDOWN"] = "Recarga máxima (horas)"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "Excluir teletransportes com recarga maior que este valor"
    L["SETTINGS_LOADING_TIME"] = "Tempo de tela de carregamento (segundos)"
    L["SETTINGS_LOADING_TIME_TT"] = "Adiciona estes segundos a cada teletransporte/portal no cálculo de rota para telas de carregamento. Valores maiores preferem caminhar. Defina 0 para ignorar."
    L["SETTINGS_APPEARANCE"] = "Aparência"
    L["SETTINGS_WINDOW_SCALE"] = "Escala da janela"
    L["SETTINGS_WINDOW_SCALE_TT"] = "Escala das janelas de rota e teletransporte (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "Chegue a qualquer destino da forma mais fácil e rápida possível."
    L["SETTINGS_FEATURES"] = "Recursos"
    L["SETTINGS_FEAT_ROUTING"] = "Rota otimizada"
    L["SETTINGS_FEAT_TELEPORTS"] = "Navegador de teletransportes"
    L["SETTINGS_FEAT_MAPBUTTON"] = "Botão do mapa-múndi"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "Botões do rastreador de missões"
    L["SETTINGS_FEAT_COLLAPSING"] = "Compactação de rota"
    L["SETTINGS_FEAT_AUTODEST"] = "Destino automático"
    L["SETTINGS_FEAT_POIROUTING"] = "Rota por clique no mapa"
    L["SETTINGS_FEAT_DESTGROUP"] = "Agrupamento por destino"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "Clique esquerdo: Mostrar/ocultar janela de rota"
    L["TOOLTIP_MINIMAP_RIGHT"] = "Clique direito: Inventário de teletransporte"
    L["TOOLTIP_MINIMAP_DRAG"] = "Arrastar: Mover botão"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "Clique do meio: Teletransportes rápidos"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "Teletransportes rápidos"
    L["MINI_PANEL_NO_TELEPORTS"] = "Nenhum teletransporte disponível"
    L["MINI_PANEL_SUMMON_MOUNT"] = "Invocar montaria"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "Favorito aleatório"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "Masmorras e Raides"
    L["DUNGEON_PICKER_SEARCH"] = "Pesquisar..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "Nenhuma instância encontrada"
    L["DUNGEON_ROUTE_TO"] = "Rota para a entrada"
    L["DUNGEON_ROUTE_TO_TT"] = "Calcular a rota mais rápida para a entrada desta masmorra"
    L["DUNGEON_TAG"] = "Masmorra"
    L["DUNGEON_RAID_TAG"] = "Raide"
    L["DUNGEON_ENTRANCE"] = "Entrada de %s"
    L["EJ_ROUTE_BUTTON_TT"] = "Rota para a entrada desta instância"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "Pesquisar destinos..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Ponto de rota ativo"
    L["DEST_SEARCH_CITIES"] = "Cidades"
    L["DEST_SEARCH_DUNGEONS"] = "Masmorras e Raides"
    L["DEST_SEARCH_NO_RESULTS"] = "Nenhum destino encontrado"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "Clique para calcular a rota"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "Casa de Leilões"
    L["SERVICE_BANK"] = "Banco"
    L["SERVICE_VOID_STORAGE"] = "Armazém do Vazio"
    L["SERVICE_CRAFTING_TABLE"] = "Mesa de Artesanato"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "Casa de Leilões mais próxima"
    L["SERVICE_NEAREST_BANK"] = "Banco mais próximo"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "Armazém do Vazio mais próximo"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "Mesa de Artesanato mais próxima"
    L["DEST_SEARCH_SERVICES"] = "Serviços"

    -- Errors / Hints
    L["UNKNOWN"] = "Desconhecido"
    L["UNKNOWN_VENDOR"] = "Vendedor desconhecido"
    L["QUEST_FALLBACK"] = "Missão #%d"
    L["TELEPORT_FALLBACK"] = "Teletransporte"
    L["NO_LIMIT"] = "Sem limite"
    L["WAYPOINT_DETECTION_FAILED"] = "Falha na detecção do ponto de referência"
    L["TOOLTIP_RESCAN"] = "Reescanear inventário em busca de itens de teletransporte"
    L["HOW_TO_OBTAIN"] = "Como obter:"
    L["HINT_CHECK_TOY_VENDORS"] = "Verifique vendedores de brinquedos, drops ou conquistas"
    L["HINT_REQUIRES_ENGINEERING"] = "Requer a profissão Engenharia"
    L["HINT_CHECK_WOWHEAD"] = "Consulte o Wowhead para detalhes de obtenção"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "Local vinculado"
    L["DEST_GARRISON"] = "Guarnição"
    L["DEST_GARRISON_SHIPYARD"] = "Estaleiro da guarnição"
    L["DEST_CAMP_LOCATION"] = "Local do acampamento"
    L["DEST_RANDOM"] = "Local aleatório"
    L["DEST_ILLIDARI_CAMP"] = "Acampamento illidari"
    L["DEST_RANDOM_NORTHREND"] = "Local aleatório em Nortúndria"
    L["DEST_RANDOM_PANDARIA"] = "Local aleatório em Pandária"
    L["DEST_RANDOM_DRAENOR"] = "Local aleatório em Draenor"
    L["DEST_RANDOM_ARGUS"] = "Local aleatório em Argus"
    L["DEST_RANDOM_KUL_TIRAS"] = "Local aleatório em Kul Tiras"
    L["DEST_RANDOM_ZANDALAR"] = "Local aleatório em Zandalar"
    L["DEST_RANDOM_SHADOWLANDS"] = "Local aleatório nas Terras Sombrias"
    L["DEST_RANDOM_DRAGON_ISLES"] = "Local aleatório nas Ilhas Dragão"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "Local aleatório em Khaz Algar"
    L["DEST_HOMESTEAD"] = "Propriedade"
    L["DEST_RANDOM_WORLDWIDE"] = "Local aleatório mundial"
    L["DEST_RANDOM_NATURAL"] = "Local natural aleatório"
    L["DEST_RANDOM_BROKEN_ISLES"] = "Linha Ley aleatória das Ilhas Partidas"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "Recompensa de missão da introdução de Legion"
    L["ACQ_WOD_INTRO"] = "Recompensa de missão da introdução de Warlords of Draenor"
    L["ACQ_KYRIAN"] = "Recurso do pacto kyriano"
    L["ACQ_VENTHYR"] = "Recurso do pacto venthyr"
    L["ACQ_NIGHT_FAE"] = "Recurso do pacto feérico noturno"
    L["ACQ_NECROLORD"] = "Recurso do pacto necrosenhor"
    L["ACQ_ARGENT_TOURNAMENT"] = "Exaltado com a Cruzada Argêntea + Campeão no Torneio Argênteo"
    L["ACQ_HELLSCREAMS_REACH"] = "Exaltado com o Domínio de Grito Infernal (diárias de Tol Barad)"
    L["ACQ_BARADINS_WARDENS"] = "Exaltado com os Guardiões de Baradin (diárias de Tol Barad)"
    L["ACQ_KARAZHAN_OPERA"] = "Drop do Grande Lobo Mau (Ópera) em Karazhan"
    L["ACQ_ICC_LK25"] = "Drop do Lich Rei heroico 25 na Cidadela da Coroa de Gelo"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "Reputação"
    L["REQ_QUEST"] = "Missão"
    L["REQ_ACHIEVEMENT"] = "Conquista"
    L["REQ_COMPLETE"] = "Concluído"
    L["REQ_IN_PROGRESS"] = "Em andamento"
    L["REQ_NOT_STARTED"] = "Não iniciado"
    L["REQ_CURRENT"] = "Atual"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "Agrupar por destino"
    L["GROUP_BY_DEST_TT"] = "Agrupar teletransportes por zona de destino"
    L["TELEPORTS_COUNT"] = "%d teletransportes"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "Coleção de brinquedos (toda a conta)"
    L["LOC_IN_BAGS"] = "Nas bolsas (Bolsa %d, Espaço %d)"
    L["LOC_IN_BANK_MAIN"] = "No banco (Principal)"
    L["LOC_IN_BANK_BAG"] = "No banco (Bolsa %d)"
    L["LOC_BANK_OR_BAGS"] = "Localização: Banco ou bolsas (visite o banco para verificar)"
    L["LOC_VENDOR"] = "Vendedor:"
    L["LOC_LOCATION"] = "Localização:"

    -- Availability filter
    L["AVAIL_ALL"] = "Mostrar tudo"
    L["AVAIL_USABLE"] = "Usável agora"
    L["AVAIL_OBTAINABLE"] = "Obtível"
    L["AVAIL_FILTER_TT"] = "Alternar filtro: Tudo / Usável agora (pronto, possuído) / Obtível (possuído + obtível, exclui facção/classe)"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - Janela de rota | /qrteleports - Inventário | /qrtest graph - Executar testes"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "Usar botões de ícone"
    L["SETTINGS_ICON_BUTTONS_TT"] = "Substituir rótulos de texto por ícones para uma interface mais compacta"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "Clique esquerdo: Usar teletransporte"
    L["MAP_BTN_RIGHT_CLICK"] = "Clique direito: Mostrar rota"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+Clique direito no mapa: Rota para local"
    L["QUEST_TRACK_HINT"] = "Shift+Clique na missão: Rota ao objetivo"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "Nenhum teletransporte para esta zona"
    L["SIDEBAR_COLLAPSE_TT"] = "Clique para recolher/expandir"

    -- Main frame tabs
    L["TAB_ROUTE"] = "Rota"
    L["TAB_TELEPORTS"] = "Teletransportes"
    L["FILTER_OPTIONS"] = "Opções de filtro"
end

-------------------------------------------------------------------------------
-- Russian translations (ruRU)
-------------------------------------------------------------------------------
if GetLocale() == "ruRU" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s загружен"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute ОШИБКА:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute ВНИМАНИЕ|r: "
    L["ADDON_FIRST_RUN"] = "Введите |cFFFFFF00/qr|r для открытия или |cFFFFFF00/qrhelp|r для списка команд."
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "Кнопка миникарты показана"
    L["MINIMAP_HIDDEN"] = "Кнопка миникарты скрыта"
    L["PRIORITY_SET_TO"] = "Приоритет путевой точки установлен на '%s'"
    L["PRIORITY_USAGE"] = "Использование: /qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "Текущий приоритет"

    -- UI Elements
    L["DESTINATION"] = "Назначение:"
    L["NO_WAYPOINT"] = "Путевая точка не задана"
    L["REFRESH"] = "Обновить"
    L["COPY_DEBUG"] = "Копир. отладку"
    L["ZONE_INFO"] = "Инфо зоны"
    L["INVENTORY"] = "Инвентарь"
    L["NAV"] = "Навиг."
    L["USE"] = "Исп."
    L["CLOSE"] = "Закрыть"
    L["FILTER"] = "Фильтр:"
    L["ALL"] = "Все"
    L["ITEMS"] = "Предметы"
    L["TOYS"] = "Игрушки"
    L["SPELLS"] = "Заклинания"

    -- Status Labels
    L["STATUS_READY"] = "ГОТОВО"
    L["STATUS_ON_CD"] = "ПЕРЕЗАР."
    L["STATUS_OWNED"] = "ЕСТЬ"
    L["STATUS_MISSING"] = "НЕТ"
    L["STATUS_NA"] = "Н/Д"

    -- Panels
    L["TELEPORT_INVENTORY"] = "Инвентарь телепортации"
    L["COPY_DEBUG_TITLE"] = "Копировать отладочную информацию (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "Вычисление..."
    L["SCANNING"] = "Сканирование..."
    L["IN_COMBAT"] = "В бою"
    L["CANNOT_USE_IN_COMBAT"] = "Нельзя использовать в бою"
    L["WAYPOINT_SET"] = "Путевая точка задана для %s"
    L["NO_PATH_FOUND"] = "Маршрут не найден"
    L["NO_DESTINATION"] = "Нет назначения для этого шага"
    L["CANNOT_FIND_LOCATION"] = "Невозможно найти местоположение %s"
    L["SET_WAYPOINT_HINT"] = "Задайте путевую точку для расчёта маршрута"
    L["PATH_CALCULATION_ERROR"] = "Ошибка расчёта маршрута"
    L["DESTINATION_NOT_REACHABLE"] = "Назначение недоступно с текущими телепортами"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "Режим отладки включён"
    L["DEBUG_MODE_DISABLED"] = "Режим отладки отключён"
    L["TRAVEL_GRAPH_BUILT"] = "Граф путешествий построен"
    L["FOUND_TELEPORTS"] = "Найдено %d способов телепортации"
    L["UI_INITIALIZED"] = "Интерфейс инициализирован"
    L["TELEPORT_PANEL_INITIALIZED"] = "Панель телепортации инициализирована"
    L["SECURE_BUTTONS_INITIALIZED"] = "Защищённые кнопки инициализированы: %d кнопок"
    L["POOL_EXHAUSTED"] = "Пул защищённых кнопок исчерпан (%d кнопок используется)"

    -- Summary
    L["SHOWING_TELEPORTS"] = "Показано %d телепортов | %d в наличии | %d готовых"
    L["ESTIMATED_TRAVEL_TIME"] = "%s расчётное время в пути"
    L["SOURCE"] = "Источник"
    L["SOURCE_MAP_PIN"] = "Метка на карте"
    L["SOURCE_MAP_CLICK"] = "Клик по карте"
    L["SOURCE_QUEST"] = "Цель задания"
    L["NO_ROUTE_HINT"] = "Попробуйте другое назначение или просканируйте телепорты (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "Цель:"
    L["WAYPOINT_AUTO"] = "Авто"
    L["WAYPOINT_MAP_PIN"] = "Метка"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "Задание"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "Выберите путевую точку для навигации"
    L["NO_WAYPOINTS_AVAILABLE"] = "Нет доступных путевых точек"

    -- Column Headers
    L["NAME"] = "Название"
    L["DESTINATION_HEADER"] = "Назначение"
    L["STATUS"] = "Статус"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "Пересчитать маршрут до путевой точки"
    L["TOOLTIP_DEBUG"] = "Скопировать отладочную информацию в буфер обмена"
    L["TOOLTIP_ZONE"] = "Скопировать информацию о зоне в буфер обмена"
    L["TOOLTIP_TELEPORTS"] = "Открыть панель инвентаря телепортации"
    L["TOOLTIP_NAV"] = "Установить навигационную точку к этому назначению"
    L["TOOLTIP_USE"] = "Использовать этот телепорт"

    -- Action Types
    L["ACTION_TELEPORT"] = "Телепорт"
    L["ACTION_WALK"] = "Пешком"
    L["ACTION_FLY"] = "Полёт"
    L["ACTION_PORTAL"] = "Портал"
    L["ACTION_HEARTHSTONE"] = "Камень возвращения"
    L["ACTION_USE_TELEPORT"] = "Использовать %s для телепортации в %s"
    L["ACTION_USE"] = "Использовать %s"
    L["ACTION_BOAT"] = "Корабль"
    L["ACTION_ZEPPELIN"] = "Дирижабль"
    L["ACTION_TRAM"] = "Трамвай"
    L["ACTION_TRAVEL"] = "Путешествие"
    L["COOLDOWN_SHORT"] = "ПЗ"

    -- Step Descriptions
    L["STEP_GO_TO"] = "Идти в %s"
    L["STEP_GO_TO_IN_ZONE"] = "Идти в %s в зоне %s"
    L["STEP_TAKE_PORTAL"] = "Войти в портал до %s"
    L["STEP_TAKE_BOAT"] = "Сесть на корабль до %s"
    L["STEP_TAKE_ZEPPELIN"] = "Сесть на дирижабль до %s"
    L["STEP_TAKE_TRAM"] = "Сесть на подземный поезд до %s"
    L["STEP_TELEPORT_TO"] = "Телепортироваться в %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "завершено"
    L["STEP_CURRENT"] = "текущий"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "Авто-точка: "
    L["AUTO_WAYPOINT_ON"] = "ВКЛ (установит TomTom/стандартную точку для первого шага)"
    L["AUTO_WAYPOINT_OFF"] = "ВЫКЛ (используется встроенная навигация WoW)"
    L["SETTINGS_GENERAL"] = "Общие"
    L["SETTINGS_NAVIGATION"] = "Навигация"
    L["SETTINGS_SHOW_MINIMAP"] = "Показать кнопку миникарты"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "Показать или скрыть кнопку миникарты"
    L["SETTINGS_AUTO_WAYPOINT"] = "Авто-установка точки для первого шага"
    L["SETTINGS_CONSIDER_CD"] = "Учитывать перезарядку при построении маршрута"
    L["SETTINGS_CONSIDER_CD_TT"] = "Учитывать время перезарядки телепортов при расчёте маршрута"
    L["SETTINGS_AUTO_DEST"] = "Авто-показ маршрута при отслеживании заданий"
    L["SETTINGS_AUTO_DEST_TT"] = "Автоматически рассчитывать и показывать маршрут при отслеживании нового задания"
    L["SETTINGS_ROUTING"] = "Маршрутизация"
    L["SETTINGS_MAX_COOLDOWN"] = "Макс. перезарядка (часы)"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "Исключить телепорты с перезарядкой больше указанного"
    L["SETTINGS_LOADING_TIME"] = "Время загрузки (секунды)"
    L["SETTINGS_LOADING_TIME_TT"] = "Добавляет указанные секунды к каждому телепорту/порталу при расчёте маршрута для экранов загрузки. Большие значения предпочитают ходьбу. Установите 0 для игнорирования."
    L["SETTINGS_APPEARANCE"] = "Внешний вид"
    L["SETTINGS_WINDOW_SCALE"] = "Масштаб окна"
    L["SETTINGS_WINDOW_SCALE_TT"] = "Масштаб окон маршрута и телепортации (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "Доберитесь до любого назначения максимально легко и быстро."
    L["SETTINGS_FEATURES"] = "Возможности"
    L["SETTINGS_FEAT_ROUTING"] = "Оптимальный маршрут"
    L["SETTINGS_FEAT_TELEPORTS"] = "Обозреватель телепортов"
    L["SETTINGS_FEAT_MAPBUTTON"] = "Кнопка карты мира"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "Кнопки отслеживания заданий"
    L["SETTINGS_FEAT_COLLAPSING"] = "Сворачивание маршрута"
    L["SETTINGS_FEAT_AUTODEST"] = "Авто-назначение"
    L["SETTINGS_FEAT_POIROUTING"] = "Маршрут по клику на карте"
    L["SETTINGS_FEAT_DESTGROUP"] = "Группировка по назначению"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "ЛКМ: Показать/скрыть окно маршрута"
    L["TOOLTIP_MINIMAP_RIGHT"] = "ПКМ: Инвентарь телепортации"
    L["TOOLTIP_MINIMAP_DRAG"] = "Перетащить: Переместить кнопку"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "СКМ: Быстрые телепорты"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "Быстрые телепорты"
    L["MINI_PANEL_NO_TELEPORTS"] = "Нет доступных телепортов"
    L["MINI_PANEL_SUMMON_MOUNT"] = "Призвать ездовое"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "Случайное избранное"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "Подземелья и рейды"
    L["DUNGEON_PICKER_SEARCH"] = "Поиск..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "Подземелья не найдены"
    L["DUNGEON_ROUTE_TO"] = "Маршрут ко входу"
    L["DUNGEON_ROUTE_TO_TT"] = "Рассчитать быстрейший маршрут ко входу в подземелье"
    L["DUNGEON_TAG"] = "Подземелье"
    L["DUNGEON_RAID_TAG"] = "Рейд"
    L["DUNGEON_ENTRANCE"] = "Вход в %s"
    L["EJ_ROUTE_BUTTON_TT"] = "Маршрут ко входу в эту инстанцию"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "Поиск направлений..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Активная точка маршрута"
    L["DEST_SEARCH_CITIES"] = "Города"
    L["DEST_SEARCH_DUNGEONS"] = "Подземелья и рейды"
    L["DEST_SEARCH_NO_RESULTS"] = "Направления не найдены"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "Нажмите для расчета маршрута"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "Аукцион"
    L["SERVICE_BANK"] = "Банк"
    L["SERVICE_VOID_STORAGE"] = "Хранилище Бездны"
    L["SERVICE_CRAFTING_TABLE"] = "Стол ремёсел"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "Ближайший аукцион"
    L["SERVICE_NEAREST_BANK"] = "Ближайший банк"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "Ближайшее хранилище Бездны"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "Ближайший ремесленный стол"
    L["DEST_SEARCH_SERVICES"] = "Сервисы"

    -- Errors / Hints
    L["UNKNOWN"] = "Неизвестно"
    L["UNKNOWN_VENDOR"] = "Неизвестный торговец"
    L["QUEST_FALLBACK"] = "Задание #%d"
    L["TELEPORT_FALLBACK"] = "Телепорт"
    L["NO_LIMIT"] = "Без ограничений"
    L["WAYPOINT_DETECTION_FAILED"] = "Не удалось определить путевую точку"
    L["TOOLTIP_RESCAN"] = "Пересканировать инвентарь на предмет телепортов"
    L["HOW_TO_OBTAIN"] = "Как получить:"
    L["HINT_CHECK_TOY_VENDORS"] = "Проверьте торговцев игрушками, мировые находки или достижения"
    L["HINT_REQUIRES_ENGINEERING"] = "Требуется профессия Инженерное дело"
    L["HINT_CHECK_WOWHEAD"] = "Подробности на Wowhead"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "Привязанное место"
    L["DEST_GARRISON"] = "Гарнизон"
    L["DEST_GARRISON_SHIPYARD"] = "Верфь гарнизона"
    L["DEST_CAMP_LOCATION"] = "Место лагеря"
    L["DEST_RANDOM"] = "Случайное место"
    L["DEST_ILLIDARI_CAMP"] = "Лагерь иллидари"
    L["DEST_RANDOM_NORTHREND"] = "Случайное место в Нордсколе"
    L["DEST_RANDOM_PANDARIA"] = "Случайное место в Пандарии"
    L["DEST_RANDOM_DRAENOR"] = "Случайное место в Дреноре"
    L["DEST_RANDOM_ARGUS"] = "Случайное место на Аргусе"
    L["DEST_RANDOM_KUL_TIRAS"] = "Случайное место в Кул-Тирасе"
    L["DEST_RANDOM_ZANDALAR"] = "Случайное место в Зандаларе"
    L["DEST_RANDOM_SHADOWLANDS"] = "Случайное место в Темных Землях"
    L["DEST_RANDOM_DRAGON_ISLES"] = "Случайное место на Островах Дракона"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "Случайное место в Каз Алгаре"
    L["DEST_HOMESTEAD"] = "Усадьба"
    L["DEST_RANDOM_WORLDWIDE"] = "Случайное место в мире"
    L["DEST_RANDOM_NATURAL"] = "Случайное природное место"
    L["DEST_RANDOM_BROKEN_ISLES"] = "Случайная лей-линия Расколотых островов"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "Награда за вступительную цепочку заданий Легиона"
    L["ACQ_WOD_INTRO"] = "Награда за вступительную цепочку заданий Warlords of Draenor"
    L["ACQ_KYRIAN"] = "Особенность ковенанта кирий"
    L["ACQ_VENTHYR"] = "Особенность ковенанта вентиров"
    L["ACQ_NIGHT_FAE"] = "Особенность ковенанта ночного народца"
    L["ACQ_NECROLORD"] = "Особенность ковенанта некролордов"
    L["ACQ_ARGENT_TOURNAMENT"] = "Превознесение у Серебряного Авангарда + Чемпион на Серебряном турнире"
    L["ACQ_HELLSCREAMS_REACH"] = "Превознесение у Длани Адского Крика (ежедневные Тол Барад)"
    L["ACQ_BARADINS_WARDENS"] = "Превознесение у Стражей Барадина (ежедневные Тол Барад)"
    L["ACQ_KARAZHAN_OPERA"] = "Добыча с Большого злого волка (Опера) в Каражане"
    L["ACQ_ICC_LK25"] = "Добыча с героического Короля-лича 25 в Цитадели Ледяной Короны"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "Репутация"
    L["REQ_QUEST"] = "Задание"
    L["REQ_ACHIEVEMENT"] = "Достижение"
    L["REQ_COMPLETE"] = "Выполнено"
    L["REQ_IN_PROGRESS"] = "В процессе"
    L["REQ_NOT_STARTED"] = "Не начато"
    L["REQ_CURRENT"] = "Текущий"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "Группировать по назначению"
    L["GROUP_BY_DEST_TT"] = "Группировать телепорты по зоне назначения"
    L["TELEPORTS_COUNT"] = "%d телепортов"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "Коллекция игрушек (для всего аккаунта)"
    L["LOC_IN_BAGS"] = "В сумках (Сумка %d, Ячейка %d)"
    L["LOC_IN_BANK_MAIN"] = "В банке (Основное)"
    L["LOC_IN_BANK_BAG"] = "В банке (Сумка %d)"
    L["LOC_BANK_OR_BAGS"] = "Расположение: Банк или сумки (посетите банк для проверки)"
    L["LOC_VENDOR"] = "Торговец:"
    L["LOC_LOCATION"] = "Расположение:"

    -- Availability filter
    L["AVAIL_ALL"] = "Показать все"
    L["AVAIL_USABLE"] = "Доступно сейчас"
    L["AVAIL_OBTAINABLE"] = "Получаемые"
    L["AVAIL_FILTER_TT"] = "Переключить фильтр: Все / Доступно сейчас (готовые, в наличии) / Получаемые (в наличии + доступные, кроме фракций/классов)"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - Окно маршрута | /qrteleports - Инвентарь | /qrtest graph - Запуск тестов"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "Кнопки-значки"
    L["SETTINGS_ICON_BUTTONS_TT"] = "Заменить текстовые подписи на значки для более компактного интерфейса"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "Левый клик: Использовать телепорт"
    L["MAP_BTN_RIGHT_CLICK"] = "Правый клик: Показать маршрут"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+ПКМ на карте: Маршрут к месту"
    L["QUEST_TRACK_HINT"] = "Shift+Клик на задание: Маршрут к цели"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "Нет телепортов для этой зоны"
    L["SIDEBAR_COLLAPSE_TT"] = "Нажмите, чтобы свернуть/развернуть"

    -- Main frame tabs
    L["TAB_ROUTE"] = "Маршрут"
    L["TAB_TELEPORTS"] = "Телепорты"
    L["FILTER_OPTIONS"] = "Параметры фильтра"
end

-------------------------------------------------------------------------------
-- Korean translations (koKR)
-------------------------------------------------------------------------------
if GetLocale() == "koKR" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s 로드됨"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute 오류:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute 경고|r: "
    L["ADDON_FIRST_RUN"] = "|cFFFFFF00/qr|r로 열기 또는 |cFFFFFF00/qrhelp|r로 명령어 확인."
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "미니맵 버튼 표시"
    L["MINIMAP_HIDDEN"] = "미니맵 버튼 숨김"
    L["PRIORITY_SET_TO"] = "경유지 우선순위가 '%s'(으)로 설정됨"
    L["PRIORITY_USAGE"] = "사용법: /qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "현재 우선순위"

    -- UI Elements
    L["DESTINATION"] = "목적지:"
    L["NO_WAYPOINT"] = "경유지가 설정되지 않음"
    L["REFRESH"] = "새로고침"
    L["COPY_DEBUG"] = "디버그 복사"
    L["ZONE_INFO"] = "지역 정보"
    L["INVENTORY"] = "보관함"
    L["NAV"] = "내비"
    L["USE"] = "사용"
    L["CLOSE"] = "닫기"
    L["FILTER"] = "필터:"
    L["ALL"] = "전체"
    L["ITEMS"] = "아이템"
    L["TOYS"] = "장난감"
    L["SPELLS"] = "주문"

    -- Status Labels
    L["STATUS_READY"] = "준비"
    L["STATUS_ON_CD"] = "재사용"
    L["STATUS_OWNED"] = "보유"
    L["STATUS_MISSING"] = "없음"
    L["STATUS_NA"] = "해당없음"

    -- Panels
    L["TELEPORT_INVENTORY"] = "순간이동 보관함"
    L["COPY_DEBUG_TITLE"] = "디버그 정보 복사 (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "계산 중..."
    L["SCANNING"] = "검색 중..."
    L["IN_COMBAT"] = "전투 중"
    L["CANNOT_USE_IN_COMBAT"] = "전투 중에는 사용할 수 없습니다"
    L["WAYPOINT_SET"] = "%s 경유지 설정됨"
    L["NO_PATH_FOUND"] = "경로를 찾을 수 없습니다"
    L["NO_DESTINATION"] = "이 단계에 대한 목적지 없음"
    L["CANNOT_FIND_LOCATION"] = "%s 위치를 찾을 수 없습니다"
    L["SET_WAYPOINT_HINT"] = "경로 계산을 위해 경유지를 설정하세요"
    L["PATH_CALCULATION_ERROR"] = "경로 계산 오류"
    L["DESTINATION_NOT_REACHABLE"] = "현재 순간이동으로 도달할 수 없는 목적지입니다"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "디버그 모드 활성화됨"
    L["DEBUG_MODE_DISABLED"] = "디버그 모드 비활성화됨"
    L["TRAVEL_GRAPH_BUILT"] = "여행 그래프 생성됨"
    L["FOUND_TELEPORTS"] = "%d개의 순간이동 수단 발견"
    L["UI_INITIALIZED"] = "UI 초기화됨"
    L["TELEPORT_PANEL_INITIALIZED"] = "순간이동 패널 초기화됨"
    L["SECURE_BUTTONS_INITIALIZED"] = "보안 버튼 %d개 초기화됨"
    L["POOL_EXHAUSTED"] = "보안 버튼 풀 소진 (%d개 사용 중)"

    -- Summary
    L["SHOWING_TELEPORTS"] = "%d개 순간이동 표시 | %d개 보유 | %d개 준비"
    L["ESTIMATED_TRAVEL_TIME"] = "%s 예상 이동 시간"
    L["SOURCE"] = "출처"
    L["SOURCE_MAP_PIN"] = "지도 핀"
    L["SOURCE_MAP_CLICK"] = "지도 클릭"
    L["SOURCE_QUEST"] = "퀘스트 목표"
    L["NO_ROUTE_HINT"] = "다른 목적지를 시도하거나 순간이동을 스캔하세요 (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "대상:"
    L["WAYPOINT_AUTO"] = "자동"
    L["WAYPOINT_MAP_PIN"] = "지도 핀"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "퀘스트"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "내비게이션 경유지 선택"
    L["NO_WAYPOINTS_AVAILABLE"] = "이용 가능한 경유지 없음"

    -- Column Headers
    L["NAME"] = "이름"
    L["DESTINATION_HEADER"] = "목적지"
    L["STATUS"] = "상태"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "경유지까지의 경로 재계산"
    L["TOOLTIP_DEBUG"] = "디버그 정보를 클립보드에 복사"
    L["TOOLTIP_ZONE"] = "지역 디버그 정보를 클립보드에 복사"
    L["TOOLTIP_TELEPORTS"] = "순간이동 보관함 패널 열기"
    L["TOOLTIP_NAV"] = "이 목적지로 내비게이션 경유지 설정"
    L["TOOLTIP_USE"] = "이 순간이동 사용"

    -- Action Types
    L["ACTION_TELEPORT"] = "순간이동"
    L["ACTION_WALK"] = "걷기"
    L["ACTION_FLY"] = "비행"
    L["ACTION_PORTAL"] = "차원문"
    L["ACTION_HEARTHSTONE"] = "귀환석"
    L["ACTION_USE_TELEPORT"] = "%s을(를) 사용하여 %s(으)로 순간이동"
    L["ACTION_USE"] = "%s 사용"
    L["ACTION_BOAT"] = "배"
    L["ACTION_ZEPPELIN"] = "비행선"
    L["ACTION_TRAM"] = "지하철"
    L["ACTION_TRAVEL"] = "여행"
    L["COOLDOWN_SHORT"] = "재사용"

    -- Step Descriptions
    L["STEP_GO_TO"] = "%s(으)로 이동"
    L["STEP_GO_TO_IN_ZONE"] = "%s %s(으)로 이동"
    L["STEP_TAKE_PORTAL"] = "%s행 차원문 이용"
    L["STEP_TAKE_BOAT"] = "%s행 배 이용"
    L["STEP_TAKE_ZEPPELIN"] = "%s행 비행선 이용"
    L["STEP_TAKE_TRAM"] = "%s행 깊은굴 지하철 이용"
    L["STEP_TELEPORT_TO"] = "%s(으)로 순간이동"

    -- Route Progress
    L["STEP_COMPLETED"] = "완료"
    L["STEP_CURRENT"] = "현재"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "자동 경유지: "
    L["AUTO_WAYPOINT_ON"] = "켜짐 (첫 단계에 TomTom/기본 경유지 설정)"
    L["AUTO_WAYPOINT_OFF"] = "꺼짐 (WoW 기본 내비게이션 사용)"
    L["SETTINGS_GENERAL"] = "일반"
    L["SETTINGS_NAVIGATION"] = "내비게이션"
    L["SETTINGS_SHOW_MINIMAP"] = "미니맵 버튼 표시"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "미니맵 버튼 표시 또는 숨기기"
    L["SETTINGS_AUTO_WAYPOINT"] = "첫 단계에 자동 경유지 설정"
    L["SETTINGS_CONSIDER_CD"] = "경로 계산 시 재사용 대기시간 고려"
    L["SETTINGS_CONSIDER_CD_TT"] = "경로 계산에 순간이동 재사용 대기시간 반영"
    L["SETTINGS_AUTO_DEST"] = "퀘스트 추적 시 자동 경로 표시"
    L["SETTINGS_AUTO_DEST_TT"] = "새 퀘스트 추적 시 경로를 자동으로 계산하여 표시"
    L["SETTINGS_ROUTING"] = "경로 계산"
    L["SETTINGS_MAX_COOLDOWN"] = "최대 재사용 대기시간 (시간)"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "이보다 긴 재사용 대기시간의 순간이동 제외"
    L["SETTINGS_LOADING_TIME"] = "로딩 화면 시간 (초)"
    L["SETTINGS_LOADING_TIME_TT"] = "경로 계산 시 각 순간이동/차원문에 이 초를 추가합니다. 높은 값은 걷기를 선호합니다. 0으로 설정하면 무시됩니다."
    L["SETTINGS_APPEARANCE"] = "외형"
    L["SETTINGS_WINDOW_SCALE"] = "창 크기"
    L["SETTINGS_WINDOW_SCALE_TT"] = "경로 및 순간이동 창의 크기 (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "가장 쉽고 빠른 방법으로 어디든 도달하세요."
    L["SETTINGS_FEATURES"] = "기능"
    L["SETTINGS_FEAT_ROUTING"] = "최적 경로"
    L["SETTINGS_FEAT_TELEPORTS"] = "순간이동 탐색기"
    L["SETTINGS_FEAT_MAPBUTTON"] = "세계 지도 버튼"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "퀘스트 추적기 버튼"
    L["SETTINGS_FEAT_COLLAPSING"] = "경로 축소"
    L["SETTINGS_FEAT_AUTODEST"] = "자동 목적지"
    L["SETTINGS_FEAT_POIROUTING"] = "지도 클릭 경로"
    L["SETTINGS_FEAT_DESTGROUP"] = "목적지별 그룹화"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "좌클릭: 경로 창 표시/숨기기"
    L["TOOLTIP_MINIMAP_RIGHT"] = "우클릭: 순간이동 보관함"
    L["TOOLTIP_MINIMAP_DRAG"] = "드래그: 버튼 이동"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "가운데 클릭: 빠른 순간이동"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "빠른 순간이동"
    L["MINI_PANEL_NO_TELEPORTS"] = "사용 가능한 순간이동이 없습니다"
    L["MINI_PANEL_SUMMON_MOUNT"] = "탈것 소환"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "무작위 즐겨찾기"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "던전 및 공격대"
    L["DUNGEON_PICKER_SEARCH"] = "검색..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "일치하는 인스턴스 없음"
    L["DUNGEON_ROUTE_TO"] = "입구까지 경로"
    L["DUNGEON_ROUTE_TO_TT"] = "이 던전 입구까지의 최적 경로를 계산합니다"
    L["DUNGEON_TAG"] = "던전"
    L["DUNGEON_RAID_TAG"] = "공격대"
    L["DUNGEON_ENTRANCE"] = "%s 입구"
    L["EJ_ROUTE_BUTTON_TT"] = "이 인스턴스 입구까지의 경로"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "목적지 검색..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "활성 경유지"
    L["DEST_SEARCH_CITIES"] = "도시"
    L["DEST_SEARCH_DUNGEONS"] = "던전 및 공격대"
    L["DEST_SEARCH_NO_RESULTS"] = "일치하는 목적지 없음"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "클릭하여 경로 계산"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "경매장"
    L["SERVICE_BANK"] = "은행"
    L["SERVICE_VOID_STORAGE"] = "공허 보관함"
    L["SERVICE_CRAFTING_TABLE"] = "제작대"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "가장 가까운 경매장"
    L["SERVICE_NEAREST_BANK"] = "가장 가까운 은행"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "가장 가까운 공허 보관소"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "가장 가까운 제작대"
    L["DEST_SEARCH_SERVICES"] = "서비스"

    -- Errors / Hints
    L["UNKNOWN"] = "알 수 없음"
    L["UNKNOWN_VENDOR"] = "알 수 없는 상인"
    L["QUEST_FALLBACK"] = "퀘스트 #%d"
    L["TELEPORT_FALLBACK"] = "텔레포트"
    L["NO_LIMIT"] = "제한 없음"
    L["WAYPOINT_DETECTION_FAILED"] = "경유지 감지 실패"
    L["TOOLTIP_RESCAN"] = "순간이동 아이템 재검색"
    L["HOW_TO_OBTAIN"] = "획득 방법:"
    L["HINT_CHECK_TOY_VENDORS"] = "장난감 상인, 월드 드롭 또는 업적을 확인하세요"
    L["HINT_REQUIRES_ENGINEERING"] = "기계공학 전문기술 필요"
    L["HINT_CHECK_WOWHEAD"] = "획득 상세 정보는 Wowhead를 확인하세요"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "귀환 장소"
    L["DEST_GARRISON"] = "주둔지"
    L["DEST_GARRISON_SHIPYARD"] = "주둔지 조선소"
    L["DEST_CAMP_LOCATION"] = "야영지"
    L["DEST_RANDOM"] = "무작위 장소"
    L["DEST_ILLIDARI_CAMP"] = "일리다리 야영지"
    L["DEST_RANDOM_NORTHREND"] = "무작위 노스렌드 장소"
    L["DEST_RANDOM_PANDARIA"] = "무작위 판다리아 장소"
    L["DEST_RANDOM_DRAENOR"] = "무작위 드레노어 장소"
    L["DEST_RANDOM_ARGUS"] = "무작위 아르거스 장소"
    L["DEST_RANDOM_KUL_TIRAS"] = "무작위 쿨 티라스 장소"
    L["DEST_RANDOM_ZANDALAR"] = "무작위 잔달라 장소"
    L["DEST_RANDOM_SHADOWLANDS"] = "무작위 어둠땅 장소"
    L["DEST_RANDOM_DRAGON_ISLES"] = "무작위 용의 섬 장소"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "무작위 카즈 알가르 장소"
    L["DEST_HOMESTEAD"] = "거주지"
    L["DEST_RANDOM_WORLDWIDE"] = "전 세계 무작위 장소"
    L["DEST_RANDOM_NATURAL"] = "무작위 자연 장소"
    L["DEST_RANDOM_BROKEN_ISLES"] = "무작위 부서진 섬 레이 라인"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "군단 도입 퀘스트 보상"
    L["ACQ_WOD_INTRO"] = "드레노어의 전쟁군주 도입 퀘스트 보상"
    L["ACQ_KYRIAN"] = "키리안 성약의 단 기능"
    L["ACQ_VENTHYR"] = "벤티르 성약의 단 기능"
    L["ACQ_NIGHT_FAE"] = "나이트 페이 성약의 단 기능"
    L["ACQ_NECROLORD"] = "강령군주 성약의 단 기능"
    L["ACQ_ARGENT_TOURNAMENT"] = "은빛십자군 확장 + 은빛대회 진영 용사"
    L["ACQ_HELLSCREAMS_REACH"] = "지옥파도의 영역 확장 (톨 바라드 일일퀘)"
    L["ACQ_BARADINS_WARDENS"] = "바라딘 파수대 확장 (톨 바라드 일일퀘)"
    L["ACQ_KARAZHAN_OPERA"] = "카라잔 오페라의 커다란 나쁜 늑대 드롭"
    L["ACQ_ICC_LK25"] = "얼음왕관 성채 영웅 리치 왕 25인 드롭"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "평판"
    L["REQ_QUEST"] = "퀘스트"
    L["REQ_ACHIEVEMENT"] = "업적"
    L["REQ_COMPLETE"] = "완료"
    L["REQ_IN_PROGRESS"] = "진행 중"
    L["REQ_NOT_STARTED"] = "시작 안 함"
    L["REQ_CURRENT"] = "현재"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "목적지별 그룹화"
    L["GROUP_BY_DEST_TT"] = "목적지 지역별로 순간이동 그룹화"
    L["TELEPORTS_COUNT"] = "순간이동 %d개"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "장난감 수집함 (계정 공유)"
    L["LOC_IN_BAGS"] = "가방 안 (가방 %d, 칸 %d)"
    L["LOC_IN_BANK_MAIN"] = "은행 (기본)"
    L["LOC_IN_BANK_BAG"] = "은행 (가방 %d)"
    L["LOC_BANK_OR_BAGS"] = "위치: 은행 또는 가방 (은행 방문하여 확인)"
    L["LOC_VENDOR"] = "상인:"
    L["LOC_LOCATION"] = "위치:"

    -- Availability filter
    L["AVAIL_ALL"] = "전체 표시"
    L["AVAIL_USABLE"] = "지금 사용 가능"
    L["AVAIL_OBTAINABLE"] = "획득 가능"
    L["AVAIL_FILTER_TT"] = "필터 전환: 전체 / 지금 사용 가능 (준비, 보유) / 획득 가능 (보유 + 획득 가능, 진영/직업 제외)"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - 경로 창 | /qrteleports - 보관함 | /qrtest graph - 테스트 실행"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "아이콘 버튼 사용"
    L["SETTINGS_ICON_BUTTONS_TT"] = "더 컴팩트한 UI를 위해 버튼의 텍스트 라벨을 아이콘으로 교체"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "좌클릭: 텔레포트 사용"
    L["MAP_BTN_RIGHT_CLICK"] = "우클릭: 경로 표시"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+우클릭 지도: 위치까지 경로"
    L["QUEST_TRACK_HINT"] = "Shift+클릭으로 퀘스트 경로 찾기"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "이 지역에 사용 가능한 텔레포트 없음"
    L["SIDEBAR_COLLAPSE_TT"] = "클릭하여 접기/펼치기"

    -- Main frame tabs
    L["TAB_ROUTE"] = "경로"
    L["TAB_TELEPORTS"] = "텔레포트"
    L["FILTER_OPTIONS"] = "필터 옵션"
end

-------------------------------------------------------------------------------
-- Simplified Chinese translations (zhCN)
-------------------------------------------------------------------------------
if GetLocale() == "zhCN" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s 已加载"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute 错误:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute 警告|r: "
    L["ADDON_FIRST_RUN"] = "输入 |cFFFFFF00/qr|r 打开，或 |cFFFFFF00/qrhelp|r 查看命令。"
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "小地图按钮已显示"
    L["MINIMAP_HIDDEN"] = "小地图按钮已隐藏"
    L["PRIORITY_SET_TO"] = "路径点优先级已设为 '%s'"
    L["PRIORITY_USAGE"] = "用法：/qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "当前优先级"

    -- UI Elements
    L["DESTINATION"] = "目的地："
    L["NO_WAYPOINT"] = "未设置路径点"
    L["REFRESH"] = "刷新"
    L["COPY_DEBUG"] = "复制调试"
    L["ZONE_INFO"] = "区域信息"
    L["INVENTORY"] = "背包"
    L["NAV"] = "导航"
    L["USE"] = "使用"
    L["CLOSE"] = "关闭"
    L["FILTER"] = "过滤："
    L["ALL"] = "全部"
    L["ITEMS"] = "物品"
    L["TOYS"] = "玩具"
    L["SPELLS"] = "法术"

    -- Status Labels
    L["STATUS_READY"] = "就绪"
    L["STATUS_ON_CD"] = "冷却中"
    L["STATUS_OWNED"] = "已拥有"
    L["STATUS_MISSING"] = "缺失"
    L["STATUS_NA"] = "不适用"

    -- Panels
    L["TELEPORT_INVENTORY"] = "传送背包"
    L["COPY_DEBUG_TITLE"] = "复制调试信息 (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "计算中..."
    L["SCANNING"] = "扫描中..."
    L["IN_COMBAT"] = "战斗中"
    L["CANNOT_USE_IN_COMBAT"] = "战斗中无法使用"
    L["WAYPOINT_SET"] = "已为 %s 设置路径点"
    L["NO_PATH_FOUND"] = "未找到路线"
    L["NO_DESTINATION"] = "此步骤无目的地"
    L["CANNOT_FIND_LOCATION"] = "无法找到 %s 的位置"
    L["SET_WAYPOINT_HINT"] = "设置一个路径点以计算路线"
    L["PATH_CALCULATION_ERROR"] = "路线计算错误"
    L["DESTINATION_NOT_REACHABLE"] = "当前传送方式无法到达目的地"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "调试模式已启用"
    L["DEBUG_MODE_DISABLED"] = "调试模式已禁用"
    L["TRAVEL_GRAPH_BUILT"] = "旅行图已构建"
    L["FOUND_TELEPORTS"] = "发现 %d 种传送方式"
    L["UI_INITIALIZED"] = "界面已初始化"
    L["TELEPORT_PANEL_INITIALIZED"] = "传送面板已初始化"
    L["SECURE_BUTTONS_INITIALIZED"] = "安全按钮已初始化，共 %d 个"
    L["POOL_EXHAUSTED"] = "安全按钮池已耗尽（%d 个正在使用）"

    -- Summary
    L["SHOWING_TELEPORTS"] = "显示 %d 个传送 | %d 个已拥有 | %d 个就绪"
    L["ESTIMATED_TRAVEL_TIME"] = "%s 预计旅行时间"
    L["SOURCE"] = "来源"
    L["SOURCE_MAP_PIN"] = "地图标记"
    L["SOURCE_MAP_CLICK"] = "地图点击"
    L["SOURCE_QUEST"] = "任务目标"
    L["NO_ROUTE_HINT"] = "尝试其他目的地或扫描传送 (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "目标："
    L["WAYPOINT_AUTO"] = "自动"
    L["WAYPOINT_MAP_PIN"] = "地图标记"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "任务"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "选择导航路径点"
    L["NO_WAYPOINTS_AVAILABLE"] = "没有可用的路径点"

    -- Column Headers
    L["NAME"] = "名称"
    L["DESTINATION_HEADER"] = "目的地"
    L["STATUS"] = "状态"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "重新计算到路径点的路线"
    L["TOOLTIP_DEBUG"] = "复制调试信息到剪贴板"
    L["TOOLTIP_ZONE"] = "复制区域调试信息到剪贴板"
    L["TOOLTIP_TELEPORTS"] = "打开传送背包面板"
    L["TOOLTIP_NAV"] = "设置导航路径点到此目的地"
    L["TOOLTIP_USE"] = "使用此传送"

    -- Action Types
    L["ACTION_TELEPORT"] = "传送"
    L["ACTION_WALK"] = "步行"
    L["ACTION_FLY"] = "飞行"
    L["ACTION_PORTAL"] = "传送门"
    L["ACTION_HEARTHSTONE"] = "炉石"
    L["ACTION_USE_TELEPORT"] = "使用 %s 传送到 %s"
    L["ACTION_USE"] = "使用 %s"
    L["ACTION_BOAT"] = "船"
    L["ACTION_ZEPPELIN"] = "飞艇"
    L["ACTION_TRAM"] = "矿道地铁"
    L["ACTION_TRAVEL"] = "旅行"
    L["COOLDOWN_SHORT"] = "冷却"

    -- Step Descriptions
    L["STEP_GO_TO"] = "前往 %s"
    L["STEP_GO_TO_IN_ZONE"] = "前往 %s 的 %s"
    L["STEP_TAKE_PORTAL"] = "穿过传送门前往 %s"
    L["STEP_TAKE_BOAT"] = "乘船前往 %s"
    L["STEP_TAKE_ZEPPELIN"] = "乘飞艇前往 %s"
    L["STEP_TAKE_TRAM"] = "乘矿道地铁前往 %s"
    L["STEP_TELEPORT_TO"] = "传送到 %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "已完成"
    L["STEP_CURRENT"] = "当前"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "自动路径点："
    L["AUTO_WAYPOINT_ON"] = "开启（将为第一步设置 TomTom/原生路径点）"
    L["AUTO_WAYPOINT_OFF"] = "关闭（使用 WoW 内置导航）"
    L["SETTINGS_GENERAL"] = "常规"
    L["SETTINGS_NAVIGATION"] = "导航"
    L["SETTINGS_SHOW_MINIMAP"] = "显示小地图按钮"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "显示或隐藏小地图按钮"
    L["SETTINGS_AUTO_WAYPOINT"] = "自动设置第一步路径点"
    L["SETTINGS_CONSIDER_CD"] = "路线计算时考虑冷却时间"
    L["SETTINGS_CONSIDER_CD_TT"] = "在路线计算中考虑传送冷却时间"
    L["SETTINGS_AUTO_DEST"] = "追踪任务时自动显示路线"
    L["SETTINGS_AUTO_DEST_TT"] = "追踪新任务时自动计算并显示路线"
    L["SETTINGS_ROUTING"] = "路线"
    L["SETTINGS_MAX_COOLDOWN"] = "最大冷却时间（小时）"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "排除冷却时间超过此值的传送"
    L["SETTINGS_LOADING_TIME"] = "加载画面时间（秒）"
    L["SETTINGS_LOADING_TIME_TT"] = "在路线计算中为每次传送/传送门添加此秒数以计算加载画面时间。较高值优先步行。设为0忽略。"
    L["SETTINGS_APPEARANCE"] = "外观"
    L["SETTINGS_WINDOW_SCALE"] = "窗口缩放"
    L["SETTINGS_WINDOW_SCALE_TT"] = "路线和传送窗口的缩放比例 (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "以最简便、最快捷的方式到达任何目的地。"
    L["SETTINGS_FEATURES"] = "功能"
    L["SETTINGS_FEAT_ROUTING"] = "最优路线"
    L["SETTINGS_FEAT_TELEPORTS"] = "传送浏览器"
    L["SETTINGS_FEAT_MAPBUTTON"] = "世界地图按钮"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "任务追踪按钮"
    L["SETTINGS_FEAT_COLLAPSING"] = "路线折叠"
    L["SETTINGS_FEAT_AUTODEST"] = "自动目的地"
    L["SETTINGS_FEAT_POIROUTING"] = "地图点击路线"
    L["SETTINGS_FEAT_DESTGROUP"] = "目的地分组"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "左键点击：显示/隐藏路线窗口"
    L["TOOLTIP_MINIMAP_RIGHT"] = "右键点击：传送背包"
    L["TOOLTIP_MINIMAP_DRAG"] = "拖动：移动按钮"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "中键点击：快速传送"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "快速传送"
    L["MINI_PANEL_NO_TELEPORTS"] = "没有可用的传送"
    L["MINI_PANEL_SUMMON_MOUNT"] = "召唤坐骑"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "随机最爱"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "地下城与团队副本"
    L["DUNGEON_PICKER_SEARCH"] = "搜索..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "没有匹配的副本"
    L["DUNGEON_ROUTE_TO"] = "前往入口的路线"
    L["DUNGEON_ROUTE_TO_TT"] = "计算前往此地下城入口的最快路线"
    L["DUNGEON_TAG"] = "地下城"
    L["DUNGEON_RAID_TAG"] = "团队副本"
    L["DUNGEON_ENTRANCE"] = "%s 入口"
    L["EJ_ROUTE_BUTTON_TT"] = "前往此副本入口的路线"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "搜索目的地..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "当前路径点"
    L["DEST_SEARCH_CITIES"] = "城市"
    L["DEST_SEARCH_DUNGEONS"] = "地下城与团队副本"
    L["DEST_SEARCH_NO_RESULTS"] = "没有匹配的目的地"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "点击计算路线"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "拍卖行"
    L["SERVICE_BANK"] = "银行"
    L["SERVICE_VOID_STORAGE"] = "虚空仓库"
    L["SERVICE_CRAFTING_TABLE"] = "制作台"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "最近的拍卖行"
    L["SERVICE_NEAREST_BANK"] = "最近的银行"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "最近的虚空仓库"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "最近的制作台"
    L["DEST_SEARCH_SERVICES"] = "服务"

    -- Errors / Hints
    L["UNKNOWN"] = "未知"
    L["UNKNOWN_VENDOR"] = "未知商人"
    L["QUEST_FALLBACK"] = "任务 #%d"
    L["TELEPORT_FALLBACK"] = "传送"
    L["NO_LIMIT"] = "无限制"
    L["WAYPOINT_DETECTION_FAILED"] = "路径点检测失败"
    L["TOOLTIP_RESCAN"] = "重新扫描背包中的传送物品"
    L["HOW_TO_OBTAIN"] = "获取方式："
    L["HINT_CHECK_TOY_VENDORS"] = "查看玩具商人、世界掉落或成就"
    L["HINT_REQUIRES_ENGINEERING"] = "需要工程学专业"
    L["HINT_CHECK_WOWHEAD"] = "在 Wowhead 查看获取详情"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "绑定位置"
    L["DEST_GARRISON"] = "要塞"
    L["DEST_GARRISON_SHIPYARD"] = "要塞船坞"
    L["DEST_CAMP_LOCATION"] = "营地位置"
    L["DEST_RANDOM"] = "随机位置"
    L["DEST_ILLIDARI_CAMP"] = "伊利达雷营地"
    L["DEST_RANDOM_NORTHREND"] = "随机诺森德位置"
    L["DEST_RANDOM_PANDARIA"] = "随机潘达利亚位置"
    L["DEST_RANDOM_DRAENOR"] = "随机德拉诺位置"
    L["DEST_RANDOM_ARGUS"] = "随机阿古斯位置"
    L["DEST_RANDOM_KUL_TIRAS"] = "随机库尔提拉斯位置"
    L["DEST_RANDOM_ZANDALAR"] = "随机赞达拉位置"
    L["DEST_RANDOM_SHADOWLANDS"] = "随机暗影界位置"
    L["DEST_RANDOM_DRAGON_ISLES"] = "随机巨龙群岛位置"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "随机卡兹阿加位置"
    L["DEST_HOMESTEAD"] = "家园"
    L["DEST_RANDOM_WORLDWIDE"] = "全球随机位置"
    L["DEST_RANDOM_NATURAL"] = "随机自然位置"
    L["DEST_RANDOM_BROKEN_ISLES"] = "随机破碎群岛魔网线"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "军团引导任务线奖励"
    L["ACQ_WOD_INTRO"] = "德拉诺之王引导任务线奖励"
    L["ACQ_KYRIAN"] = "格里恩盟约功能"
    L["ACQ_VENTHYR"] = "温西尔盟约功能"
    L["ACQ_NIGHT_FAE"] = "法夜盟约功能"
    L["ACQ_NECROLORD"] = "通灵领主盟约功能"
    L["ACQ_ARGENT_TOURNAMENT"] = "银色北伐军崇拜 + 银色锦标赛阵营勇士"
    L["ACQ_HELLSCREAMS_REACH"] = "地狱咆哮之手崇拜（托尔巴拉德日常）"
    L["ACQ_BARADINS_WARDENS"] = "巴拉丁典狱官崇拜（托尔巴拉德日常）"
    L["ACQ_KARAZHAN_OPERA"] = "卡拉赞歌剧院大灰狼掉落"
    L["ACQ_ICC_LK25"] = "冰冠堡垒英雄巫妖王25人掉落"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "声望"
    L["REQ_QUEST"] = "任务"
    L["REQ_ACHIEVEMENT"] = "成就"
    L["REQ_COMPLETE"] = "已完成"
    L["REQ_IN_PROGRESS"] = "进行中"
    L["REQ_NOT_STARTED"] = "未开始"
    L["REQ_CURRENT"] = "当前"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "按目的地分组"
    L["GROUP_BY_DEST_TT"] = "按目的地区域对传送进行分组"
    L["TELEPORTS_COUNT"] = "%d 个传送"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "玩具收藏（账号共享）"
    L["LOC_IN_BAGS"] = "在背包中（背包 %d，格 %d）"
    L["LOC_IN_BANK_MAIN"] = "在银行（主栏）"
    L["LOC_IN_BANK_BAG"] = "在银行（背包 %d）"
    L["LOC_BANK_OR_BAGS"] = "位置：银行或背包（前往银行查看）"
    L["LOC_VENDOR"] = "商人："
    L["LOC_LOCATION"] = "位置："

    -- Availability filter
    L["AVAIL_ALL"] = "显示全部"
    L["AVAIL_USABLE"] = "立即可用"
    L["AVAIL_OBTAINABLE"] = "可获取"
    L["AVAIL_FILTER_TT"] = "切换过滤：全部 / 立即可用（就绪且拥有）/ 可获取（已拥有+可获取，排除阵营/职业限制）"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - 路线窗口 | /qrteleports - 背包 | /qrtest graph - 运行测试"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "使用图标按钮"
    L["SETTINGS_ICON_BUTTONS_TT"] = "用图标替换按钮上的文字标签，使界面更紧凑"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "左键点击：使用传送"
    L["MAP_BTN_RIGHT_CLICK"] = "右键点击：显示路线"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+右键点击地图：路线到目的地"
    L["QUEST_TRACK_HINT"] = "Shift+点击任务：规划路线到目标"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "此区域无传送"
    L["SIDEBAR_COLLAPSE_TT"] = "点击折叠/展开"

    -- Main frame tabs
    L["TAB_ROUTE"] = "路线"
    L["TAB_TELEPORTS"] = "传送"
    L["FILTER_OPTIONS"] = "筛选选项"
end

-------------------------------------------------------------------------------
-- Traditional Chinese translations (zhTW)
-------------------------------------------------------------------------------
if GetLocale() == "zhTW" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s 已載入"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute 錯誤:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute 警告|r: "
    L["ADDON_FIRST_RUN"] = "輸入 |cFFFFFF00/qr|r 開啟，或 |cFFFFFF00/qrhelp|r 查看指令。"
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "小地圖按鈕已顯示"
    L["MINIMAP_HIDDEN"] = "小地圖按鈕已隱藏"
    L["PRIORITY_SET_TO"] = "路徑點優先級已設為 '%s'"
    L["PRIORITY_USAGE"] = "用法：/qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "目前優先級"

    -- UI Elements
    L["DESTINATION"] = "目的地："
    L["NO_WAYPOINT"] = "未設定路徑點"
    L["REFRESH"] = "重新整理"
    L["COPY_DEBUG"] = "複製偵錯"
    L["ZONE_INFO"] = "區域資訊"
    L["INVENTORY"] = "背包"
    L["NAV"] = "導航"
    L["USE"] = "使用"
    L["CLOSE"] = "關閉"
    L["FILTER"] = "篩選："
    L["ALL"] = "全部"
    L["ITEMS"] = "物品"
    L["TOYS"] = "玩具"
    L["SPELLS"] = "法術"

    -- Status Labels
    L["STATUS_READY"] = "就緒"
    L["STATUS_ON_CD"] = "冷卻中"
    L["STATUS_OWNED"] = "已擁有"
    L["STATUS_MISSING"] = "缺少"
    L["STATUS_NA"] = "不適用"

    -- Panels
    L["TELEPORT_INVENTORY"] = "傳送背包"
    L["COPY_DEBUG_TITLE"] = "複製偵錯資訊 (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "計算中..."
    L["SCANNING"] = "掃描中..."
    L["IN_COMBAT"] = "戰鬥中"
    L["CANNOT_USE_IN_COMBAT"] = "戰鬥中無法使用"
    L["WAYPOINT_SET"] = "已為 %s 設定路徑點"
    L["NO_PATH_FOUND"] = "未找到路線"
    L["NO_DESTINATION"] = "此步驟無目的地"
    L["CANNOT_FIND_LOCATION"] = "無法找到 %s 的位置"
    L["SET_WAYPOINT_HINT"] = "設定一個路徑點以計算路線"
    L["PATH_CALCULATION_ERROR"] = "路線計算錯誤"
    L["DESTINATION_NOT_REACHABLE"] = "目前的傳送方式無法到達目的地"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "偵錯模式已啟用"
    L["DEBUG_MODE_DISABLED"] = "偵錯模式已停用"
    L["TRAVEL_GRAPH_BUILT"] = "旅行圖已建立"
    L["FOUND_TELEPORTS"] = "發現 %d 種傳送方式"
    L["UI_INITIALIZED"] = "介面已初始化"
    L["TELEPORT_PANEL_INITIALIZED"] = "傳送面板已初始化"
    L["SECURE_BUTTONS_INITIALIZED"] = "安全按鈕已初始化，共 %d 個"
    L["POOL_EXHAUSTED"] = "安全按鈕池已耗盡（%d 個正在使用）"

    -- Summary
    L["SHOWING_TELEPORTS"] = "顯示 %d 個傳送 | %d 個已擁有 | %d 個就緒"
    L["ESTIMATED_TRAVEL_TIME"] = "%s 預估旅行時間"
    L["SOURCE"] = "來源"
    L["SOURCE_MAP_PIN"] = "地圖標記"
    L["SOURCE_MAP_CLICK"] = "地圖點擊"
    L["SOURCE_QUEST"] = "任務目標"
    L["NO_ROUTE_HINT"] = "嘗試其他目的地或掃描傳送 (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "目標："
    L["WAYPOINT_AUTO"] = "自動"
    L["WAYPOINT_MAP_PIN"] = "地圖標記"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "任務"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "選擇導航路徑點"
    L["NO_WAYPOINTS_AVAILABLE"] = "沒有可用的路徑點"

    -- Column Headers
    L["NAME"] = "名稱"
    L["DESTINATION_HEADER"] = "目的地"
    L["STATUS"] = "狀態"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "重新計算到路徑點的路線"
    L["TOOLTIP_DEBUG"] = "複製偵錯資訊到剪貼簿"
    L["TOOLTIP_ZONE"] = "複製區域偵錯資訊到剪貼簿"
    L["TOOLTIP_TELEPORTS"] = "開啟傳送背包面板"
    L["TOOLTIP_NAV"] = "設定導航路徑點到此目的地"
    L["TOOLTIP_USE"] = "使用此傳送"

    -- Action Types
    L["ACTION_TELEPORT"] = "傳送"
    L["ACTION_WALK"] = "步行"
    L["ACTION_FLY"] = "飛行"
    L["ACTION_PORTAL"] = "傳送門"
    L["ACTION_HEARTHSTONE"] = "爐石"
    L["ACTION_USE_TELEPORT"] = "使用 %s 傳送到 %s"
    L["ACTION_USE"] = "使用 %s"
    L["ACTION_BOAT"] = "船"
    L["ACTION_ZEPPELIN"] = "飛艇"
    L["ACTION_TRAM"] = "乘坐地鐵"
    L["ACTION_TRAVEL"] = "旅行"
    L["COOLDOWN_SHORT"] = "冷卻"

    -- Step Descriptions
    L["STEP_GO_TO"] = "前往 %s"
    L["STEP_GO_TO_IN_ZONE"] = "前往 %s 的 %s"
    L["STEP_TAKE_PORTAL"] = "穿過傳送門前往 %s"
    L["STEP_TAKE_BOAT"] = "搭船前往 %s"
    L["STEP_TAKE_ZEPPELIN"] = "搭飛船前往 %s"
    L["STEP_TAKE_TRAM"] = "搭乘乘礦道地鐵前往 %s"
    L["STEP_TELEPORT_TO"] = "傳送到 %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "已完成"
    L["STEP_CURRENT"] = "目前"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "自動路徑點："
    L["AUTO_WAYPOINT_ON"] = "開啟（將為第一步設定 TomTom/原生路徑點）"
    L["AUTO_WAYPOINT_OFF"] = "關閉（使用 WoW 內建導航）"
    L["SETTINGS_GENERAL"] = "一般"
    L["SETTINGS_NAVIGATION"] = "導航"
    L["SETTINGS_SHOW_MINIMAP"] = "顯示小地圖按鈕"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "顯示或隱藏小地圖按鈕"
    L["SETTINGS_AUTO_WAYPOINT"] = "自動設定第一步路徑點"
    L["SETTINGS_CONSIDER_CD"] = "路線計算時考慮冷卻時間"
    L["SETTINGS_CONSIDER_CD_TT"] = "在路線計算中考慮傳送冷卻時間"
    L["SETTINGS_AUTO_DEST"] = "追蹤任務時自動顯示路線"
    L["SETTINGS_AUTO_DEST_TT"] = "追蹤新任務時自動計算並顯示路線"
    L["SETTINGS_ROUTING"] = "路線"
    L["SETTINGS_MAX_COOLDOWN"] = "最大冷卻時間（小時）"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "排除冷卻時間超過此值的傳送"
    L["SETTINGS_LOADING_TIME"] = "載入畫面時間（秒）"
    L["SETTINGS_LOADING_TIME_TT"] = "在路線計算中為每次傳送/傳送門添加此秒數以計算載入畫面時間。較高值優先步行。設為0忽略。"
    L["SETTINGS_APPEARANCE"] = "外觀"
    L["SETTINGS_WINDOW_SCALE"] = "視窗縮放"
    L["SETTINGS_WINDOW_SCALE_TT"] = "路線和傳送視窗的縮放比例 (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "以最簡便、最快捷的方式到達任何目的地。"
    L["SETTINGS_FEATURES"] = "功能"
    L["SETTINGS_FEAT_ROUTING"] = "最佳路線"
    L["SETTINGS_FEAT_TELEPORTS"] = "傳送瀏覽器"
    L["SETTINGS_FEAT_MAPBUTTON"] = "世界地圖按鈕"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "任務追蹤按鈕"
    L["SETTINGS_FEAT_COLLAPSING"] = "路線摺疊"
    L["SETTINGS_FEAT_AUTODEST"] = "自動目的地"
    L["SETTINGS_FEAT_POIROUTING"] = "地圖點擊路線"
    L["SETTINGS_FEAT_DESTGROUP"] = "目的地分組"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "左鍵點擊：顯示/隱藏路線視窗"
    L["TOOLTIP_MINIMAP_RIGHT"] = "右鍵點擊：傳送背包"
    L["TOOLTIP_MINIMAP_DRAG"] = "拖曳：移動按鈕"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "中鍵點擊：快速傳送"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "快速傳送"
    L["MINI_PANEL_NO_TELEPORTS"] = "沒有可用的傳送"
    L["MINI_PANEL_SUMMON_MOUNT"] = "召喚坐騎"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "隨機最愛"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "地城與團隊副本"
    L["DUNGEON_PICKER_SEARCH"] = "搜尋..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "沒有符合的副本"
    L["DUNGEON_ROUTE_TO"] = "前往入口的路線"
    L["DUNGEON_ROUTE_TO_TT"] = "計算前往此地城入口的最快路線"
    L["DUNGEON_TAG"] = "地城"
    L["DUNGEON_RAID_TAG"] = "團隊副本"
    L["DUNGEON_ENTRANCE"] = "%s 入口"
    L["EJ_ROUTE_BUTTON_TT"] = "前往此副本入口的路線"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "搜尋目的地..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "目前路徑點"
    L["DEST_SEARCH_CITIES"] = "城市"
    L["DEST_SEARCH_DUNGEONS"] = "地城與團隊副本"
    L["DEST_SEARCH_NO_RESULTS"] = "沒有匹配的目的地"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "點擊計算路線"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "拍賣場"
    L["SERVICE_BANK"] = "銀行"
    L["SERVICE_VOID_STORAGE"] = "虛空倉庫"
    L["SERVICE_CRAFTING_TABLE"] = "製作檯"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "最近的拍賣場"
    L["SERVICE_NEAREST_BANK"] = "最近的銀行"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "最近的虛空倉庫"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "最近的製作檯"
    L["DEST_SEARCH_SERVICES"] = "服務"

    -- Errors / Hints
    L["UNKNOWN"] = "未知"
    L["UNKNOWN_VENDOR"] = "未知商人"
    L["QUEST_FALLBACK"] = "任務 #%d"
    L["TELEPORT_FALLBACK"] = "傳送"
    L["NO_LIMIT"] = "無限制"
    L["WAYPOINT_DETECTION_FAILED"] = "路徑點偵測失敗"
    L["TOOLTIP_RESCAN"] = "重新掃描背包中的傳送物品"
    L["HOW_TO_OBTAIN"] = "取得方式："
    L["HINT_CHECK_TOY_VENDORS"] = "查看玩具商人、世界掉落或成就"
    L["HINT_REQUIRES_ENGINEERING"] = "需要工程學專業"
    L["HINT_CHECK_WOWHEAD"] = "在 Wowhead 查看取得詳情"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "綁定位置"
    L["DEST_GARRISON"] = "要塞"
    L["DEST_GARRISON_SHIPYARD"] = "要塞船塢"
    L["DEST_CAMP_LOCATION"] = "營地位置"
    L["DEST_RANDOM"] = "隨機位置"
    L["DEST_ILLIDARI_CAMP"] = "伊利達瑞營地"
    L["DEST_RANDOM_NORTHREND"] = "隨機北裂境位置"
    L["DEST_RANDOM_PANDARIA"] = "隨機潘達利亞位置"
    L["DEST_RANDOM_DRAENOR"] = "隨機德拉諾位置"
    L["DEST_RANDOM_ARGUS"] = "隨機阿古斯位置"
    L["DEST_RANDOM_KUL_TIRAS"] = "隨機庫爾提拉斯位置"
    L["DEST_RANDOM_ZANDALAR"] = "隨機贊達拉位置"
    L["DEST_RANDOM_SHADOWLANDS"] = "隨機暗影界位置"
    L["DEST_RANDOM_DRAGON_ISLES"] = "隨機巨龍群島位置"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "隨機卡茲阿加位置"
    L["DEST_HOMESTEAD"] = "家園"
    L["DEST_RANDOM_WORLDWIDE"] = "全球隨機位置"
    L["DEST_RANDOM_NATURAL"] = "隨機自然位置"
    L["DEST_RANDOM_BROKEN_ISLES"] = "隨機破碎群島魔網線"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "軍臨天下引導任務線獎勵"
    L["ACQ_WOD_INTRO"] = "德拉諾之霸引導任務線獎勵"
    L["ACQ_KYRIAN"] = "琪瑞安盟約功能"
    L["ACQ_VENTHYR"] = "汎希爾盟約功能"
    L["ACQ_NIGHT_FAE"] = "暗夜妖精盟約功能"
    L["ACQ_NECROLORD"] = "死靈領主盟約功能"
    L["ACQ_ARGENT_TOURNAMENT"] = "銀白十字軍崇拜 + 銀白聯賽陣營勇士"
    L["ACQ_HELLSCREAMS_REACH"] = "地獄吼先鋒崇拜（托爾巴拉德日常）"
    L["ACQ_BARADINS_WARDENS"] = "巴拉丁鐵衛崇拜（托爾巴拉德日常）"
    L["ACQ_KARAZHAN_OPERA"] = "卡拉贊歌劇院大野狼掉落"
    L["ACQ_ICC_LK25"] = "冰冠城塞英雄巫妖王25人掉落"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "聲望"
    L["REQ_QUEST"] = "任務"
    L["REQ_ACHIEVEMENT"] = "成就"
    L["REQ_COMPLETE"] = "已完成"
    L["REQ_IN_PROGRESS"] = "進行中"
    L["REQ_NOT_STARTED"] = "未開始"
    L["REQ_CURRENT"] = "目前"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "按目的地分組"
    L["GROUP_BY_DEST_TT"] = "按目的地區域對傳送進行分組"
    L["TELEPORTS_COUNT"] = "%d 個傳送"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "玩具收藏（帳號共享）"
    L["LOC_IN_BAGS"] = "在背包中（背包 %d，格 %d）"
    L["LOC_IN_BANK_MAIN"] = "在銀行（主欄）"
    L["LOC_IN_BANK_BAG"] = "在銀行（背包 %d）"
    L["LOC_BANK_OR_BAGS"] = "位置：銀行或背包（前往銀行查看）"
    L["LOC_VENDOR"] = "商人："
    L["LOC_LOCATION"] = "位置："

    -- Availability filter
    L["AVAIL_ALL"] = "顯示全部"
    L["AVAIL_USABLE"] = "立即可用"
    L["AVAIL_OBTAINABLE"] = "可取得"
    L["AVAIL_FILTER_TT"] = "切換篩選：全部 / 立即可用（就緒且擁有）/ 可取得（已擁有+可取得，排除陣營/職業限制）"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - 路線視窗 | /qrteleports - 背包 | /qrtest graph - 執行測試"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "使用圖示按鈕"
    L["SETTINGS_ICON_BUTTONS_TT"] = "用圖示取代按鈕上的文字標籤，使介面更緊湊"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "左鍵點擊：使用傳送"
    L["MAP_BTN_RIGHT_CLICK"] = "右鍵點擊：顯示路線"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+右鍵點擊地圖：路線到目的地"
    L["QUEST_TRACK_HINT"] = "Shift+點擊任務：規劃路線到目標"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "此區域無傳送"
    L["SIDEBAR_COLLAPSE_TT"] = "點擊摺疊/展開"

    -- Main frame tabs
    L["TAB_ROUTE"] = "路線"
    L["TAB_TELEPORTS"] = "傳送"
    L["FILTER_OPTIONS"] = "篩選選項"
end

-------------------------------------------------------------------------------
-- Italian translations (itIT)
-------------------------------------------------------------------------------
if GetLocale() == "itIT" then
    -- General
    L["ADDON_TITLE"] = "QuickRoute"
    L["ADDON_LOADED"] = "|cFF00FF00QuickRoute|r v%s caricato"
    L["ERROR_PREFIX"] = "|cFFFF0000QuickRoute ERRORE:|r "
    L["WARNING_PREFIX"] = "|cFFFF6600QuickRoute ATTENZIONE|r: "
    L["ADDON_FIRST_RUN"] = "Digita |cFFFFFF00/qr|r per aprire o |cFFFFFF00/qrhelp|r per i comandi."
    L["DEBUG_PREFIX"] = "|cFF00FF00QuickRoute|r: "
    L["MINIMAP_SHOWN"] = "Pulsante minimappa mostrato"
    L["MINIMAP_HIDDEN"] = "Pulsante minimappa nascosto"
    L["PRIORITY_SET_TO"] = "Priorità waypoint impostata su '%s'"
    L["PRIORITY_USAGE"] = "Utilizzo: /qr priority mappin|quest|tomtom"
    L["PRIORITY_CURRENT"] = "Priorità attuale"

    -- UI Elements
    L["DESTINATION"] = "Destinazione:"
    L["NO_WAYPOINT"] = "Nessun punto di riferimento impostato"
    L["REFRESH"] = "Aggiorna"
    L["COPY_DEBUG"] = "Copia Debug"
    L["ZONE_INFO"] = "Info Zona"
    L["INVENTORY"] = "Inventario"
    L["NAV"] = "Nav"
    L["USE"] = "Usa"
    L["CLOSE"] = "Chiudi"
    L["FILTER"] = "Filtro:"
    L["ALL"] = "Tutti"
    L["ITEMS"] = "Oggetti"
    L["TOYS"] = "Giocattoli"
    L["SPELLS"] = "Incantesimi"

    -- Status Labels
    L["STATUS_READY"] = "PRONTO"
    L["STATUS_ON_CD"] = "IN RIC"
    L["STATUS_OWNED"] = "POSSEDUTO"
    L["STATUS_MISSING"] = "MANCANTE"
    L["STATUS_NA"] = "N/D"

    -- Panels
    L["TELEPORT_INVENTORY"] = "Inventario teletrasporto"
    L["COPY_DEBUG_TITLE"] = "Copia info di debug (Ctrl+C)"

    -- Status Messages
    L["CALCULATING"] = "Calcolo in corso..."
    L["SCANNING"] = "Scansione..."
    L["IN_COMBAT"] = "In combattimento"
    L["CANNOT_USE_IN_COMBAT"] = "Non utilizzabile in combattimento"
    L["WAYPOINT_SET"] = "Punto di riferimento impostato per %s"
    L["NO_PATH_FOUND"] = "Nessun percorso trovato"
    L["NO_DESTINATION"] = "Nessuna destinazione per questo passaggio"
    L["CANNOT_FIND_LOCATION"] = "Impossibile trovare la posizione di %s"
    L["SET_WAYPOINT_HINT"] = "Imposta un punto di riferimento per calcolare il percorso"
    L["PATH_CALCULATION_ERROR"] = "Errore nel calcolo del percorso"
    L["DESTINATION_NOT_REACHABLE"] = "Destinazione non raggiungibile con i teletrasporti attuali"

    -- Debug
    L["DEBUG_MODE_ENABLED"] = "Modalità debug attivata"
    L["DEBUG_MODE_DISABLED"] = "Modalità debug disattivata"
    L["TRAVEL_GRAPH_BUILT"] = "Grafo di viaggio costruito"
    L["FOUND_TELEPORTS"] = "%d metodi di teletrasporto trovati"
    L["UI_INITIALIZED"] = "Interfaccia inizializzata"
    L["TELEPORT_PANEL_INITIALIZED"] = "Pannello teletrasporto inizializzato"
    L["SECURE_BUTTONS_INITIALIZED"] = "Pulsanti sicuri inizializzati con %d pulsanti"
    L["POOL_EXHAUSTED"] = "Pool di pulsanti sicuri esaurito (%d pulsanti in uso)"

    -- Summary
    L["SHOWING_TELEPORTS"] = "%d teletrasporti mostrati | %d posseduti | %d pronti"
    L["ESTIMATED_TRAVEL_TIME"] = "%s tempo di viaggio stimato"
    L["SOURCE"] = "Fonte"
    L["SOURCE_MAP_PIN"] = "Segnaposto mappa"
    L["SOURCE_MAP_CLICK"] = "Clic sulla mappa"
    L["SOURCE_QUEST"] = "Obiettivo missione"
    L["NO_ROUTE_HINT"] = "Prova un'altra destinazione o scansiona i teletrasporti (/qrinv)"

    -- Waypoint Source Selector
    L["WAYPOINT_SOURCE"] = "Obiettivo:"
    L["WAYPOINT_AUTO"] = "Auto"
    L["WAYPOINT_MAP_PIN"] = "Segnaposto"
    L["WAYPOINT_TOMTOM"] = "TomTom"
    L["WAYPOINT_QUEST"] = "Missione"
    L["TOOLTIP_WAYPOINT_SOURCE"] = "Seleziona il punto di riferimento per la navigazione"
    L["NO_WAYPOINTS_AVAILABLE"] = "Nessun punto di riferimento disponibile"

    -- Column Headers
    L["NAME"] = "Nome"
    L["DESTINATION_HEADER"] = "Destinazione"
    L["STATUS"] = "Stato"

    -- Tooltips
    L["TOOLTIP_REFRESH"] = "Ricalcola il percorso verso il punto di riferimento"
    L["TOOLTIP_DEBUG"] = "Copia le informazioni di debug negli appunti"
    L["TOOLTIP_ZONE"] = "Copia le informazioni della zona negli appunti"
    L["TOOLTIP_TELEPORTS"] = "Apri il pannello inventario teletrasporto"
    L["TOOLTIP_NAV"] = "Imposta un punto di navigazione verso questa destinazione"
    L["TOOLTIP_USE"] = "Usa questo teletrasporto"

    -- Action Types
    L["ACTION_TELEPORT"] = "Teletrasporto"
    L["ACTION_WALK"] = "Cammina"
    L["ACTION_FLY"] = "Vola"
    L["ACTION_PORTAL"] = "Portale"
    L["ACTION_HEARTHSTONE"] = "Pietra del ritorno"
    L["ACTION_USE_TELEPORT"] = "Usa %s per teletrasportarti a %s"
    L["ACTION_USE"] = "Usa %s"
    L["ACTION_BOAT"] = "Nave"
    L["ACTION_ZEPPELIN"] = "Zeppelin"
    L["ACTION_TRAM"] = "Tram"
    L["ACTION_TRAVEL"] = "Viaggio"
    L["COOLDOWN_SHORT"] = "RIC"

    -- Step Descriptions
    L["STEP_GO_TO"] = "Vai a %s"
    L["STEP_GO_TO_IN_ZONE"] = "Vai a %s in %s"
    L["STEP_TAKE_PORTAL"] = "Prendi il portale per %s"
    L["STEP_TAKE_BOAT"] = "Prendi la nave per %s"
    L["STEP_TAKE_ZEPPELIN"] = "Prendi lo zeppelin per %s"
    L["STEP_TAKE_TRAM"] = "Prendi il Tram Sotterraneo per %s"
    L["STEP_TELEPORT_TO"] = "Teletrasportati a %s"

    -- Route Progress
    L["STEP_COMPLETED"] = "completato"
    L["STEP_CURRENT"] = "attuale"

    -- Settings
    L["AUTO_WAYPOINT_TOGGLE"] = "Punto auto: "
    L["AUTO_WAYPOINT_ON"] = "ATTIVO (imposterà punto TomTom/nativo per il primo passo)"
    L["AUTO_WAYPOINT_OFF"] = "DISATTIVO (navigazione integrata di WoW)"
    L["SETTINGS_GENERAL"] = "Generale"
    L["SETTINGS_NAVIGATION"] = "Navigazione"
    L["SETTINGS_SHOW_MINIMAP"] = "Mostra pulsante minimappa"
    L["SETTINGS_SHOW_MINIMAP_TT"] = "Mostra o nascondi il pulsante della minimappa"
    L["SETTINGS_AUTO_WAYPOINT"] = "Imposta automaticamente il punto per il primo passo"
    L["SETTINGS_CONSIDER_CD"] = "Considera i tempi di ricarica nel percorso"
    L["SETTINGS_CONSIDER_CD_TT"] = "Includere i tempi di ricarica dei teletrasporti nel calcolo del percorso"
    L["SETTINGS_AUTO_DEST"] = "Mostra percorso auto al tracciamento missioni"
    L["SETTINGS_AUTO_DEST_TT"] = "Calcola e mostra automaticamente il percorso quando tracci una nuova missione"
    L["SETTINGS_ROUTING"] = "Calcolo percorso"
    L["SETTINGS_MAX_COOLDOWN"] = "Ricarica massima (ore)"
    L["SETTINGS_MAX_COOLDOWN_TT"] = "Escludi teletrasporti con ricarica superiore"
    L["SETTINGS_LOADING_TIME"] = "Tempo schermata di caricamento (secondi)"
    L["SETTINGS_LOADING_TIME_TT"] = "Aggiunge questi secondi a ogni teletrasporto/portale nel calcolo del percorso per le schermate di caricamento. Valori più alti preferiscono camminare. Imposta 0 per ignorare."
    L["SETTINGS_APPEARANCE"] = "Aspetto"
    L["SETTINGS_WINDOW_SCALE"] = "Scala finestra"
    L["SETTINGS_WINDOW_SCALE_TT"] = "Scala delle finestre percorso e teletrasporto (75%-150%)"
    L["SETTINGS_DESCRIPTION"] = "Raggiungi qualsiasi destinazione nel modo più semplice e veloce possibile."
    L["SETTINGS_FEATURES"] = "Funzionalità"
    L["SETTINGS_FEAT_ROUTING"] = "Percorso ottimale"
    L["SETTINGS_FEAT_TELEPORTS"] = "Esploratore teletrasporti"
    L["SETTINGS_FEAT_MAPBUTTON"] = "Pulsante mappa del mondo"
    L["SETTINGS_FEAT_QUESTBUTTONS"] = "Pulsanti tracciamento missioni"
    L["SETTINGS_FEAT_COLLAPSING"] = "Compattamento percorso"
    L["SETTINGS_FEAT_AUTODEST"] = "Destinazione automatica"
    L["SETTINGS_FEAT_POIROUTING"] = "Percorso tramite clic sulla mappa"
    L["SETTINGS_FEAT_DESTGROUP"] = "Raggruppamento per destinazione"

    -- Minimap Button
    L["TOOLTIP_MINIMAP_LEFT"] = "Clic sinistro: Mostra/nascondi finestra percorso"
    L["TOOLTIP_MINIMAP_RIGHT"] = "Clic destro: Inventario teletrasporto"
    L["TOOLTIP_MINIMAP_DRAG"] = "Trascina: Sposta pulsante"
    L["TOOLTIP_MINIMAP_MIDDLE"] = "Clic centrale: Teletrasporti rapidi"

    -- Mini Teleport Panel
    L["MINI_PANEL_TITLE"] = "Teletrasporti rapidi"
    L["MINI_PANEL_NO_TELEPORTS"] = "Nessun teletrasporto disponibile"
    L["MINI_PANEL_SUMMON_MOUNT"] = "Evoca cavalcatura"
    L["MINI_PANEL_RANDOM_FAVORITE"] = "Preferito casuale"

    -- Dungeon/Raid routing
    L["DUNGEON_PICKER_TITLE"] = "Spedizioni e incursioni"
    L["DUNGEON_PICKER_SEARCH"] = "Cerca..."
    L["DUNGEON_PICKER_NO_RESULTS"] = "Nessuna istanza trovata"
    L["DUNGEON_ROUTE_TO"] = "Percorso verso l'ingresso"
    L["DUNGEON_ROUTE_TO_TT"] = "Calcola il percorso più veloce verso l'ingresso di questa spedizione"
    L["DUNGEON_TAG"] = "Spedizione"
    L["DUNGEON_RAID_TAG"] = "Incursione"
    L["DUNGEON_ENTRANCE"] = "Ingresso di %s"
    L["EJ_ROUTE_BUTTON_TT"] = "Percorso verso l'ingresso di questa istanza"

    -- Destination Search
    L["DEST_SEARCH_PLACEHOLDER"] = "Cerca destinazioni..."
    L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Punto di passaggio attivo"
    L["DEST_SEARCH_CITIES"] = "Citta"
    L["DEST_SEARCH_DUNGEONS"] = "Dungeon e Raid"
    L["DEST_SEARCH_NO_RESULTS"] = "Nessuna destinazione trovata"
    L["DEST_SEARCH_ROUTE_TO_TT"] = "Clicca per calcolare il percorso"

    -- Service POI routing
    L["SERVICE_AUCTION_HOUSE"] = "Casa d'aste"
    L["SERVICE_BANK"] = "Banca"
    L["SERVICE_VOID_STORAGE"] = "Deposito del Vuoto"
    L["SERVICE_CRAFTING_TABLE"] = "Tavolo da lavoro"
    L["SERVICE_NEAREST_AUCTION_HOUSE"] = "Casa d'aste più vicina"
    L["SERVICE_NEAREST_BANK"] = "Banca più vicina"
    L["SERVICE_NEAREST_VOID_STORAGE"] = "Deposito del Vuoto più vicino"
    L["SERVICE_NEAREST_CRAFTING_TABLE"] = "Tavolo da artigianato più vicino"
    L["DEST_SEARCH_SERVICES"] = "Servizi"

    -- Errors / Hints
    L["UNKNOWN"] = "Sconosciuto"
    L["UNKNOWN_VENDOR"] = "Venditore sconosciuto"
    L["QUEST_FALLBACK"] = "Missione #%d"
    L["TELEPORT_FALLBACK"] = "Teletrasporto"
    L["NO_LIMIT"] = "Nessun limite"
    L["WAYPOINT_DETECTION_FAILED"] = "Rilevamento punto di riferimento fallito"
    L["TOOLTIP_RESCAN"] = "Riscansiona l'inventario per oggetti di teletrasporto"
    L["HOW_TO_OBTAIN"] = "Come ottenerlo:"
    L["HINT_CHECK_TOY_VENDORS"] = "Controlla i venditori di giocattoli, i drop o gli obiettivi"
    L["HINT_REQUIRES_ENGINEERING"] = "Richiede la professione Ingegneria"
    L["HINT_CHECK_WOWHEAD"] = "Consulta Wowhead per i dettagli di acquisizione"
    -- Dynamic destination names
    L["DEST_BOUND_LOCATION"] = "Posizione vincolata"
    L["DEST_GARRISON"] = "Guarnigione"
    L["DEST_GARRISON_SHIPYARD"] = "Cantiere navale della guarnigione"
    L["DEST_CAMP_LOCATION"] = "Posizione del campo"
    L["DEST_RANDOM"] = "Posizione casuale"
    L["DEST_ILLIDARI_CAMP"] = "Campo illidari"
    L["DEST_RANDOM_NORTHREND"] = "Posizione casuale a Nordania"
    L["DEST_RANDOM_PANDARIA"] = "Posizione casuale a Pandaria"
    L["DEST_RANDOM_DRAENOR"] = "Posizione casuale a Draenor"
    L["DEST_RANDOM_ARGUS"] = "Posizione casuale su Argus"
    L["DEST_RANDOM_KUL_TIRAS"] = "Posizione casuale a Kul Tiras"
    L["DEST_RANDOM_ZANDALAR"] = "Posizione casuale a Zandalar"
    L["DEST_RANDOM_SHADOWLANDS"] = "Posizione casuale nelle Terreombre"
    L["DEST_RANDOM_DRAGON_ISLES"] = "Posizione casuale alle Isole dei Draghi"
    L["DEST_RANDOM_KHAZ_ALGAR"] = "Posizione casuale a Khaz Algar"
    L["DEST_HOMESTEAD"] = "Dimora"
    L["DEST_RANDOM_WORLDWIDE"] = "Posizione casuale mondiale"
    L["DEST_RANDOM_NATURAL"] = "Posizione naturale casuale"
    L["DEST_RANDOM_BROKEN_ISLES"] = "Linea di Ley casuale delle Isole Disperse"
    -- Acquisition text
    L["ACQ_LEGION_INTRO"] = "Ricompensa missione dell'introduzione di Legion"
    L["ACQ_WOD_INTRO"] = "Ricompensa missione dell'introduzione di Warlords of Draenor"
    L["ACQ_KYRIAN"] = "Funzionalità del patto dei kyrian"
    L["ACQ_VENTHYR"] = "Funzionalità del patto dei venthyr"
    L["ACQ_NIGHT_FAE"] = "Funzionalità del patto dei silfi della notte"
    L["ACQ_NECROLORD"] = "Funzionalità del patto dei necrosignori"
    L["ACQ_ARGENT_TOURNAMENT"] = "Osannato con la Crociata d'Argento + Campione al Torneo d'Argento"
    L["ACQ_HELLSCREAMS_REACH"] = "Osannato con la Portata di Urloinfernale (giornaliere di Tol Barad)"
    L["ACQ_BARADINS_WARDENS"] = "Osannato con i Guardiani di Baradin (giornaliere di Tol Barad)"
    L["ACQ_KARAZHAN_OPERA"] = "Drop dal Grande Lupo Cattivo (Opera) a Karazhan"
    L["ACQ_ICC_LK25"] = "Drop dal Re dei Lich eroico 25 nella Cittadella della Corona di Ghiaccio"

    -- Acquisition requirement labels
    L["REQ_REPUTATION"] = "Reputazione"
    L["REQ_QUEST"] = "Missione"
    L["REQ_ACHIEVEMENT"] = "Obiettivo"
    L["REQ_COMPLETE"] = "Completato"
    L["REQ_IN_PROGRESS"] = "In corso"
    L["REQ_NOT_STARTED"] = "Non iniziato"
    L["REQ_CURRENT"] = "Attuale"

    -- TeleportPanel grouping
    L["GROUP_BY_DEST"] = "Raggruppa per destinazione"
    L["GROUP_BY_DEST_TT"] = "Raggruppa i teletrasporti per zona di destinazione"
    L["TELEPORTS_COUNT"] = "%d teletrasporti"

    -- TeleportPanel location strings
    L["LOC_TOY_COLLECTION"] = "Collezione giocattoli (tutto l'account)"
    L["LOC_IN_BAGS"] = "Nelle borse (Borsa %d, Slot %d)"
    L["LOC_IN_BANK_MAIN"] = "In banca (Principale)"
    L["LOC_IN_BANK_BAG"] = "In banca (Borsa %d)"
    L["LOC_BANK_OR_BAGS"] = "Posizione: Banca o borse (visita la banca per verificare)"
    L["LOC_VENDOR"] = "Venditore:"
    L["LOC_LOCATION"] = "Posizione:"

    -- Availability filter
    L["AVAIL_ALL"] = "Mostra tutti"
    L["AVAIL_USABLE"] = "Utilizzabile ora"
    L["AVAIL_OBTAINABLE"] = "Ottenibile"
    L["AVAIL_FILTER_TT"] = "Cambia filtro: Tutti / Utilizzabile ora (pronto, posseduto) / Ottenibile (posseduto + ottenibile, esclusi fazione/classe)"

    -- Settings hint
    L["SETTINGS_COMMANDS_HINT"] = "/qr - Finestra percorso | /qrteleports - Inventario | /qrtest graph - Esegui test"

    -- Icon buttons
    L["SETTINGS_ICON_BUTTONS"] = "Usa pulsanti icona"
    L["SETTINGS_ICON_BUTTONS_TT"] = "Sostituisci le etichette di testo con icone per un'interfaccia più compatta"

    -- Map teleport button
    L["MAP_BTN_LEFT_CLICK"] = "Clic sinistro: Usa teletrasporto"
    L["MAP_BTN_RIGHT_CLICK"] = "Clic destro: Mostra percorso"
    L["MAP_BTN_CTRL_RIGHT"] = "Ctrl+Clic destro su mappa: Percorso alla posizione"
    L["QUEST_TRACK_HINT"] = "Shift+Clic su missione: Percorso verso obiettivo"

    -- Map sidebar panel
    L["SIDEBAR_TITLE"] = "QuickRoute"
    L["SIDEBAR_NO_TELEPORTS"] = "Nessun teletrasporto per questa zona"
    L["SIDEBAR_COLLAPSE_TT"] = "Clicca per comprimere/espandere"

    -- Main frame tabs
    L["TAB_ROUTE"] = "Percorso"
    L["TAB_TELEPORTS"] = "Teletrasporti"
    L["FILTER_OPTIONS"] = "Opzioni filtro"
end
