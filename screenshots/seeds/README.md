# Regenerating the screenshots

The images in this directory are rendered by [wow-ui-sim](https://github.com/Osso/wow-ui-sim), which runs the real
Blizzard interface and this addon against the client's own item, spell and map
tables. Every name, icon, zone image and travel time in them is computed by the
addon; nothing is drawn by hand.

## What each file is for

`common.lua` gives the character a plausible collection — nine destinations,
which fills the card grid without a half-row — and holds two helpers: one drives
the addon's throttled `OnUpdate` handlers, which the three ticks of a screenshot
run never reach, and one hides the Blizzard frames that would otherwise read
through the semi-transparent panels.

`waypoint.lua` backs `C_Map.SetUserWaypoint` and its two readers with an
in-memory pin. The simulator has no user-waypoint store; this is the same
contract the client offers, and the route is still calculated entirely by the
addon.

`graph.lua` rescans the collection and rebuilds the travel graph. The graph is
built once at load, before the collection is visible here, so without this the
router has no player teleport edges and answers with portals only.

The `view-*.lua` files open one panel each.

## Rendering

Each render concatenates the shared parts with one view, in this order:

```bash
cat common.lua waypoint.lua graph.lua view-route.lua > /tmp/seed.lua
WOW_INSTALL_PATH="/path/to/World of Warcraft" \
WOW_SIM_ADDONS_PATH="/path/to/a/dir/symlinking/QuickRoute" \
wow-sim --no-saved-vars --exec-lua @/tmp/seed.lua \
  screenshot --output /tmp/route.png --width 2560 --height 1600 --ui-scale 1.6875
```

`view-teleports.lua`, `view-quick.lua` and `view-settings.lua` need only
`common.lua` before them.

Crop to the panel with the bounds `--dump-tree` reports, rather than by eye:

| Image | Frame | Crop |
|---|---|---|
| `route-panel.png` | `QuickRouteMainFrame` | 588, 493 → 1971, 1105 |
| `teleport-panel.png` | `QuickRouteMainFrame` | 588, 335 → 1971, 1263 |
| `destination-search.png` | `QRMiniTeleportPanel` | 1610, 179 → 2251, 663 |
| `quest-teleport.png` | window and quest tracker | 560, 420 → 2560, 1090 |
| `settings-panel.png` | Blizzard settings panel | 503, 141 → 2055, 1362 |

Those bounds hold for `--width 2560 --height 1600 --ui-scale 1.6875`. Re-read
them from `--dump-tree` after any change to a panel's size.
