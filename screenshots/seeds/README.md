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
  screenshot --output /tmp/route.webp --width 2560 --height 1600
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

Those historical crops used a simulator build with UI scale 1.6875 at 2560×1600.
Re-read bounds from `--dump-tree` for the installed simulator and current panel size.


## Initial review windows (2026-09-05)

The initial local `wow-ui-sim` build accepted `--filter` and `--dump-tree`; it did not
accept the historical `--ui-scale` option used for the older gallery images. The new view
seeds set their own window scale explicitly. For these snapshots:

```bash
cat common.lua graph.lua view-multi.lua > /tmp/quickroute-multi.lua
WOW_INSTALL_PATH="/path/to/World of Warcraft" \
WOW_SIM_ADDONS_PATH="/path/to/addon-symlinks" \
wow-sim --no-saved-vars --exec-lua @/tmp/quickroute-multi.lua screenshot \
  --output /tmp/multi-route-review.webp --width 1600 --height 1200 \
  --filter QuickRouteMultiRouteFrame --dump-tree QuickRouteMultiRouteFrame
```

Use `view-phases.lua` and `QuickRoutePhaseFrame` for the phase selector.
The renderer writes WebP even if a different output extension was requested.
These images inspect actual addon controls; the simulator has baseline Blizzard
API errors and color/text-rendering differences, so they are not retail visual
or protected-action certification. The trip example contains pasted inputs and
has not started a route; its values are not fabricated route results.

## Follow-up with all four simulator PRs

The player workflow review uses a freshly built integration of PRs 7, 8, 9 and 10.
Exact source revisions, build features and the binary hash are recorded in the
[review provenance](../../docs/PLAYER-WORKFLOW-REVIEW-2026-09-05.md#visual-simulator-provenance).
That build supports native atlas sizes, UTF-8/named colors and `--ui-scale`.

From the addon repository, render the declared review scenes with:

```sh
python3 scripts/render_player_review.py \
  --sim-root /path/to/combined-wow-ui-sim \
  --wow-install '/path/to/World of Warcraft' \
  --output /tmp/quickroute-player-review
```

Use `--view settings`, `teleports-small`, `sidebar`, `sidebar-collapsed`, `acquisition-vendor`,
`acquisition-unknown`, `currency-empty`, `overlap-help`, `overlap-settings` or
`overlap-menu` to repeat one scene. The script creates
an addon symlink, Lua input and log beside each image. It injects QuickRoute's
actual German translations; native Blizzard labels and item names retain the
simulator locale. The acquisition and empty-vendor fixtures are explicit examples.

Keep the main-window scene unfiltered: secure icons are parented to UIParent,
and filtering only the main frame removes them. The unfiltered game UI also
reveals action-bar/window ordering that an isolated component image conceals.
