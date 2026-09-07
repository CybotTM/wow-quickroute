# Reproducing the screenshots

The gallery is rendered from QuickRoute controls by [wow-ui-sim](https://github.com/Osso/wow-ui-sim), using Blizzard interface source and local WoW assets. It is a simulated character and UI environment, not a native-game capture. Character inventory/position and optional ATT records are explicit fixtures; computed route steps, ordering and travel estimates are not replaced.

Use the corrected combined simulator described in the [screenshot fidelity review](../../docs/SCREENSHOT-REVIEW-2026-09-07.md). The original combined build repeated scaled backdrop corners and used an opaque substitute for the native Settings background. The documented patch corrects both; the original worktree remains intact.

From the addon repository:

```sh
python3 scripts/render_player_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/player
python3 scripts/render_att_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/att
python3 scripts/render_feature_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/features
python3 scripts/render_gallery_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/gallery
```

Each wrapper accepts `--view`; use `--help` for its exact scene names. Outputs include the generated Lua scene, renderer log, raw WebP and a provenance text file. The shared renderer checks the loaded addon version against the current TOC and rejects execution errors. Provenance records source, binary, scene and image hashes.

The [published manifest](../render-provenance.txt) contains the per-image records. Content hashes include untracked addon/fixture files; changed inputs and a missing completed-scene marker invalidate a capture.

## Scene groups

- **Player:** Settings, small-screen teleport inventory, overlapping help/menu/settings, map sidebar and acquisition/currency empty states.
- **ATT:** removed acquisition labels, icon badge, acquisition help, Vilo's purchase requirements, item search and vendor search.
- **Features:** a three-stop trip after completing its first stop, plus paired classic-Uldum routes with present/past phase assumptions. The present-phase route contains a Zidormi transition; the past-phase route does not.
- **Gallery:** a dungeon route, owned teleport inventory, compact teleport menu, and a quest route with a matching tracker button.

The Settings image and other simulated native frames retain the simulator locale and addon list. Its world background does not recreate the player's 3D scene. These differences are not evidence of an addon layout change.

## Shared seeds

`common.lua` supplies the explicit small collection and helpers for opening views and advancing QuickRoute's throttled overlay handlers. `graph.lua` rescans that collection and builds the actual travel graph. `waypoint.lua` provides the map-pin storage contract for the historical standalone view seeds.

The `view-*.lua` files preserve earlier individual scenarios. Current gallery production uses the four wrappers above: those exercise completed initialization and meaningful active states, rather than merely opening empty windows. No post-render cropping, border removal or image retouching is needed.

Keep activation-control views unfiltered: secure icons are parented to UIParent, so filtering only the main frame would remove them and conceal layering defects. The shared renderer also rejects active secure overlays still bound to UIParent's drawing level.
