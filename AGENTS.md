# AGENTS.md — QuickRoute

> Last updated: 2026-08-30

World of Warcraft addon (Lua 5.1) for optimal travel routing using teleports, portals, spells, and items. Uses Dijkstra's algorithm. Namespace: `QR`.

## Commands (verified)

| Command | What it does | ~Time |
|---------|-------------|-------|
| `~/.local/bin/lua5.1 tests/run_tests.lua` | Run the suite (33 test files). Compare the assertion count to the previous run rather than to a number written down here | ~5s |
| `QR_TEST_ORDER=reverse ~/.local/bin/lua5.1 tests/run_tests.lua` | Same suite, files back to front. CI runs both; a file that borrows shared state and does not restore it fails here and nowhere else | ~5s |
| `./scripts/lint.sh` | Luacheck over `QuickRoute/` and `tests/`, native or via Docker. Fails when no linter is available | ~3s |
| `luacheck QuickRoute/ tests/ --config .luacheckrc` | Lint only, native luacheck 1.2.0 | ~2s |
| `docker run --rm -v "$(pwd):/src" -w /src ghcr.io/lunarmodules/luacheck:v1.2.0 QuickRoute/ tests/ --config .luacheckrc` | Lint without a native luacheck — same version CI pins | ~5s |
| `git config core.hooksPath scripts/hooks` | Install the pre-commit and pre-push hooks (one-time, per clone) | — |
| `cp -r QuickRoute/* "/mnt/f/World of Warcraft/_retail_/Interface/AddOns/QuickRoute/"` | Deploy to WoW | ~1s |

Tests run standalone outside WoW via `tests/mock_wow_api.lua` (full WoW API mock).

## File Map

```
QuickRoute/
  QuickRoute.lua          → Entry point, namespace setup, combat callbacks, slash commands
  QuickRoute.toc          → Load order manifest
  Localization.lua        → L10n for 10 locales (enUS, deDE, frFR, esES, esMX, ptBR, ruRU, koKR, zhCN, zhTW, itIT)
  Core/
    Graph.lua             → Dijkstra pathfinding graph (nodes, edges, shortest path)
    PathCalculator.lua    → Route calculation orchestrator (builds graph, finds path)
    TravelTime.lua        → Walking/flying time estimation between coordinates
  Data/
    TeleportItems.lua     → All teleport data (items, toys, spells, racials, class, general)
    Portals.lua           → Portal hub connections (boats, zeppelins, portals)
    ZoneAdjacency.lua     → Zone neighbor graph for overland travel
    DungeonEntrances.lua  → Static dungeon/raid entrance coordinates
    ServicePOIs.lua       → Vendor, bank, auction house and other service points
  Modules/
    MainFrame.lua         → Unified tabbed container (Route + Teleports tabs)
    UI.lua                → Route display tab (step list, use buttons, progress)
    TeleportPanel.lua     → Teleport inventory tab (grid/list, grouping, filtering)
    SecureButtons.lua     → SecureActionButtonTemplate overlay manager
    PlayerInventory.lua   → Inventory scanning (bags, toys, spells)
    CooldownTracker.lua   → Cooldown state tracking
    WaypointIntegration.lua → TomTom + native waypoint detection
    MinimapButton.lua     → Minimap/addon compartment button
    MiniTeleportPanel.lua → Compact teleport popup from minimap
    MapSidebar.lua        → World map sidebar panel
    MapTeleportButton.lua → World map teleport button overlay
    QuestTeleportButtons.lua → Quest tracker teleport buttons
    POIRouting.lua        → Ctrl+Right-click map routing
    DungeonData.lua       → Encounter Journal scan, instance list
    DungeonPicker.lua     → Dungeon/raid destination picker
    DestinationSearch.lua → Destination search dropdown (zones, dungeons, quests)
    ServiceRouter.lua     → Routing to service POIs
    EncounterJournalButton.lua → Teleport button in the Encounter Journal
    SettingsPanel.lua     → Settings UI (native Settings API, vertical layout)
  Utils/
    Colors.lua            → Color constants (QR.Colors)
    PlayerInfo.lua        → Cached player info (faction, class, engineering)
    WindowFactory.lua     → Standard window/frame creation
  Tests/
    TestGraph.lua         → In-game test runner (/qrtest graph)
tests/
  run_tests.lua           → Standalone test runner entry point
  mock_wow_api.lua        → Full WoW API mock (~2000 lines)
  addon_loader.lua        → Loads addon files in .toc order for tests
  test_*.lua              → 27 test files covering all modules
```

## Architecture

### Load Order
Defined in `QuickRoute.toc`. Localization → Utils → Data → Core → Modules → QuickRoute.lua → Tests.

A module loaded before `QuickRoute.lua` must not call into the `QR` namespace at
file scope — `QR:RegisterCombatCallback` and friends do not exist yet. Register
from `Initialize()` instead. The test runner fails the run when a file does not
load, which is what catches this.

### Key Patterns

| Pattern | Implementation |
|---------|---------------|
| Global caching | All files cache `string.format`, `table.insert`, `math.*` as locals at file top |
| Logging | `QR:Debug()`, `QR:Error()`, `QR:Warn()`, `QR:Print()` — never raw `print()` |
| Colors | `QR.Colors.*` from `Utils/Colors.lua` — never hardcoded hex/RGB |
| Player info | `QR.PlayerInfo:GetFaction()`, `:GetClass()`, `:HasEngineering()` — cached |
| Combat safety | `QR:RegisterCombatCallback(enterCb, leaveCb)` — centralized |
| Secure buttons | `SecureActionButtonTemplate` on UIParent, positioned via throttled OnUpdate |
| Frame pooling | UI.lua and TeleportPanel.lua use frame pools to prevent memory leaks |
| Localization | `QR.L["KEY"]` with metatable fallback to English |
| Tooltips | `QR.AddTooltipBranding(GameTooltip)` before `Show()`, `GameTooltip_Hide()` on leave |
| Debounce | `C_Timer.NewTimer` with `:Cancel()`, stored on module table |

### MainFrame Architecture
Single unified window with portrait header and tab bar. `UI.lua` and `TeleportPanel.lua` implement `CreateContent(parentFrame)` instead of standalone windows. Show/Hide/Toggle delegate to `QR.MainFrame`. Use `QR.MainFrame.isShowing` and `QR.MainFrame.activeTab` — never `QR.UI.isShowing` or `QR.TeleportPanel.isShowing`.

## Testing

- **Runner**: `~/.local/bin/lua5.1 tests/run_tests.lua`
- **File order**: `QR_TEST_ORDER` is `discovery` (default) or `reverse`. The files share one mock and one addon namespace, so a test that borrows a global -- a frame method, a `QR.db` key -- must put it back, or it breaks whichever file happens to run next.
- **Mock**: `tests/mock_wow_api.lua` provides full WoW API simulation (frames, events, tooltips, spells, items, C_Map, C_Timer, etc.)
- **Loader**: `tests/addon_loader.lua` loads addon in .toc order
- **In-game**: `/qrtest graph` runs graph tests inside WoW
- **UX enforcement**: `test_ux_consistency.lua` verifies 10 UX patterns across all modules
- **Layout tests**: `MockWoW:ComputeFrameBounds()` resolves anchor chains to absolute positions

### Test Contract
Files: `tests/test_<module>.lua`, discovered by the runner. Each file receives
`(T, QR, MockWoW)` as varargs — `local T, QR, MockWoW = ...` on the first line.

Register a test with `T:run("Module: behaviour", function(t) ... end)` and assert
through the `t` handle: `t:assert`, `t:assertEqual`, `t:assertNotNil`, `t:assertNil`,
`t:assertTrue`, `t:assertFalse`, `t:assertGreaterThan`, `t:assertTableCount`.

Never use bare `assert()`. It raises instead of recording, which aborts the rest
of the file and takes every later test in it with it.

Every assertion carries a message that names the observed value, so a failure
reads as a fact rather than a boolean.

### PlayerInfo in Tests
After changing `MockWoW.config.playerFaction`, call `QR.PlayerInfo:InvalidateCache()`.

## Code Style

- **Language**: Lua 5.1 (WoW runtime) — no `goto`, no bitwise ops, no `//` division
- **Indentation**: 4 spaces
- **Local caching**: First lines of every file cache globals as locals
- **Nil safety**: Always guard `C_Map and C_Map.FunctionName` before calling
- **Strings**: Double quotes preferred
- **Comments**: `-- Single line` and `--- Doc comment`

## Heuristics

| When | Do |
|------|----|
| Adding a teleport | Add to `TeleportItems.lua`, add `DEST_*` to all 10 locales in `Localization.lua`, add `DEST_L_KEYS` mapping in `TeleportPanel.lua` if needed |
| Adding a module | Add to `QuickRoute.toc` in correct section, create test file, add to `addon_loader.lua` if needed |
| Showing tooltip | `QR.AddTooltipBranding(GameTooltip)` before `Show()`, suppress `ShoppingTooltip1`/`ShoppingTooltip2` for items |
| Hiding tooltip | Always `GameTooltip_Hide()` (global function), never `GameTooltip:Hide()` |
| Click handler | Always include `PlaySound(SOUNDKIT.*)` |
| Movable frame | Always call `SetClampedToScreen(true)` |
| Combat-sensitive UI | Use `QR:RegisterCombatCallback(enterCb, leaveCb)` |
| Secure button needed | Use `SecureActionButtonTemplate`, anchor to UIParent, position via `QR.SecureButtons:AttachOverlay()` |
| Renaming with replace_all | Bulk replace catches declaration lines too — fix declarations after |

## Boundaries

### Always
- Run tests before deploying (`~/.local/bin/lua5.1 tests/run_tests.lua`)
- Guard against nil before WoW API calls
- Use `QR.Colors`, `QR.L`, `QR.PlayerInfo` (never hardcode)
- Check `InCombatLockdown()` before secure frame operations
- Validate `weight > 0` for graph edges (use epsilon 0.001 for same-zone)

### Ask First
- Changing load order in `.toc`
- Adding new SavedVariables fields
- Modifying graph/pathfinding algorithm
- Adding new slash commands

### Never
- Use Lua 5.2+ features (goto, bitwise, floor division)
- Call `SetPoint`/`SetParent` on SecureActionButtonTemplate to non-secure frames
- Use `table.insert(path, 1, x)` in hot paths (O(n^2))
- Share frame pool instances across modules
- Use raw `print()` instead of `QR:Debug()`/`QR:Print()`

## Codebase State

- **SavedVariables**: `QuickRouteDB` (DB_VERSION = 1)
- **Interface**: `120100` (WoW 12.1.0). The live retail build is the authority — check https://wago.tools/api/builds, not the wiki, which lags.
- **Dependencies**: none required. TomTom optional (`## OptionalDeps`). No libraries are vendored and there is no `embeds.xml`.
- **CI**: GitHub Actions — luacheck 1.2.0 over `QuickRoute/` and `tests/`, plus the full Lua 5.1 test suite, on push/PR to main. Actions are SHA-pinned and maintained by Dependabot.
- **Shipped since the last VISION revision**: dungeon/raid routing, destination search, service-POI routing, Encounter Journal button.
- **Planned features**: NPC/vendor routing, world events (see `docs/VISION.md`)

## Terminology

| Term | Means |
|------|-------|
| QR | QuickRoute namespace (global addon table) |
| SecureButton | WoW SecureActionButtonTemplate — clickable during combat |
| MainFrame | Unified tabbed window container |
| DEST_L_KEYS | Mapping from English destination names to localization keys |
| isDynamic | Teleport with variable destination (hearthstones, housing) |
| STATUS.READY/OWNED/ON_CD/MISSING/NA | Teleport availability states |
| POI | Point of Interest (world map) |
| LRU cache | Least Recently Used cache for spell/item info lookups |
