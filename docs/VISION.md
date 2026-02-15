# QuickRoute — Vision & Purpose

## Core Mission

**Help the player get to any destination as easily and as fast as possible.**

- **Easy**: Minimal clicks, no thinking required, obvious next action
- **Fast**: Optimal route using all available teleports, portals, items, and spells
- **Universal**: Works for ANY destination type the player might want to reach

## Design Principles

1. **Zero-thought UX**: The player should never have to figure out "what's my fastest way there?" — QuickRoute answers that instantly.
2. **One-click execution**: Every route step should be actionable with a single click (secure buttons for spells/items, waypoint arrows for walking).
3. **Context-aware**: Routes adapt to what the player actually has available (inventory, cooldowns, class, faction, engineering).
4. **Non-intrusive**: Show useful info where the player already looks (quest tracker, world map, minimap) — don't force them to open a separate window.

## Destination Types

### Currently Supported
- [x] **Map pins** — User-placed waypoints on the world map
- [x] **Quest targets** — Super-tracked quest objectives
- [x] **TomTom waypoints** — Integration with TomTom addon
- [x] **World map click** — Ctrl+Right-click on any map location (POI Routing)
- [x] **Slash command coordinates** — `/qrpath <mapID> <x> <y>`

### Planned / Missing
- [x] **Dungeons & Raids** — Route to dungeon/raid entrances from Dungeon Journal or LFG (v1.2.0)
- [x] **Cities & Towns** — Unified destination search with cities, dungeons, waypoints (v1.3.0)
- [x] **Service POIs** — Route to nearest AH, Bank, Void Storage, Crafting Table (v1.4.0)
- [ ] **NPCs & Vendors** — Route to specific NPCs (repair, transmog, quartermasters, trainers)
- [ ] **World Events** — Darkmoon Faire, holiday events, world boss locations
- [ ] **Flight Masters** — Nearest flight master for manual flight path usage
- [ ] **Group members** — Route to where your party/raid member is
- [ ] **Death run-back** — Optimal route from graveyard to corpse
- [ ] **Favorite locations** — User-saved destinations for quick access

## User Journeys

### "I need to get to [place]"
1. Player thinks of a destination
2. QuickRoute shows the optimal route with one action (click map, track quest, pick from list)
3. Player follows step-by-step instructions with one-click execution per step
4. Player arrives at destination

### "What teleport gets me closest?"
1. Player opens the world map to any zone
2. QuickRoute shows a teleport button for the best available teleport
3. Player clicks the button — done

### "I tracked a quest, how do I get there fast?"
1. Player tracks a quest
2. QuickRoute automatically shows the optimal route (auto-destination)
3. Teleport buttons appear next to quest entries in the tracker
4. Player clicks the closest teleport button and follows the route

### "I need to get to [dungeon] for my M+ key"
1. Player opens Dungeon Journal or has a keystone
2. QuickRoute shows optimal route to the dungeon entrance
3. One-click teleport if a portal/item gets close

## What Makes QuickRoute Unique

QuickRoute is the **only addon** that combines:
1. **Full Dijkstra pathfinding** — considers all possible routes, not just direct teleports
2. **Teleport browser** — see and use all available teleports in one panel
3. **One-click secure button execution** — cast spells and use items directly from the route
4. **Cooldown awareness** — factors in teleport cooldowns to find the actual fastest route
5. **Multi-source destinations** — works with map pins, quests, TomTom, map clicks, and more
6. **Route step collapsing** — clean, readable directions instead of verbose node-by-node paths

## Competition
See [FEATURE_PLAN.md](analysis/FEATURE_PLAN.md) for detailed competitive analysis.
