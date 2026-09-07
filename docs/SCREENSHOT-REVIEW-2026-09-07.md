# Screenshot fidelity review

The player identified repeated frame corners, a Settings header inset, a Settings background unlike the native client, and a phase screenshot that did not demonstrate a useful workflow. The earlier visual review missed these defects. This pass separates addon geometry from renderer behavior and replaces the gallery with current, reproducible scenes.

## Causes and corrections

- **Repeated corners:** Blizzard's `Backdrop.lua` supplies explicit eight-coordinate texture crops for its border corners. The simulator treated axis-aligned crops as naturally sized tiles. A 16-unit corner rendered at 21 pixels was drawn as a full 16-pixel tile plus a repeated strip. The local renderer correction draws non-repeating explicit UVs once, preserves mirrored coordinates, and retains the existing repeat path for UVs beyond the texture range. QuickRoute's border artwork is unchanged.
- **Settings inset:** Blizzard places the settings container 16 UI units right of the category list and 12 units below the inner frame's top. QuickRoute now extends only the branding background into those gutters. Text, the native Defaults button, the route button, and the settings-list geometry retain their existing positions. Category/search/close restoration still removes the branding.
- **Settings opacity:** A native-client `/dump PANEL_BACKGROUND_COLOR:GetRGBA()` supplied RGB values equivalent to `31/255, 30/255, 33/255` and alpha `0.8`. The simulator had substituted `0.15, 0.15, 0.15, 1.0`. The corrected local renderer uses the observed native color. Native locale, the simulated world background, and the installed addon list can still differ from the player's environment.
- **Empty demonstrations:** The old trip capture only contained pasted text, and all phase rows were unknown. The replacement trip has completed one actual stop and displays the next computed leg. The phase pair targets classic Uldum with opposite session assumptions: the present-phase example includes a Zidormi transition; the past-phase example does not. No computed route steps or time estimates are mocked.
- **Clipped teleport cards:** The fresh gallery exposed a separate addon defect: grouped cards used the full panel width although its scroll viewport reserves 32 UI units for gutters. The final column exceeded the visible area by 22 units. Cards now use the viewport width; a 244-unit minimum preserves three complete columns and five icons per card at the default window size.
- **Repeated zone names:** Fresh route captures also exposed subtitles such as `Isle of Dorn (Isle of Dorn)`. Both ordinary and precomputed routes now display equal names once while retaining distinct destination and zone labels.

The native geometry comes from `Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml`, `Blizzard_SettingsList.xml`, and `Blizzard_SharedXML/Backdrop.lua` in the matching local Blizzard source. The user-provided native screenshots remain private and are not included in the repository.

## Reproducing the scenes

The local simulator combines the previously documented [PR 7–10 inputs](PLAYER-WORKFLOW-REVIEW-2026-09-05.md#visual-simulator-provenance), baseline tree `8c42da41c684f7c62bb1010f681ff69ab8cd9122`, with the [two-file renderer/color patch](rendering/wow-ui-sim-visual-fidelity.patch). The original simulator worktree is preserved; these corrections do not merge or publish third-party PRs.

| Recorded input | SHA / tree |
| --- | --- |
| Complete simulator tree after the patch | `e23c1b8c0ec523380fe8c2400c197b71394223e7` |
| Renderer/color patch SHA-256 | `00a99ba16c5544aadcbc9a54708da4919e71ec4ac04c3eda29456e86d76e4066` |
| Fresh `wow-sim` binary SHA-256 | `79450209eb01f39ae139e4ff5f8b9262a19f965de931920e5c7ed5e053df4db3` |

The binary was built with `cargo build --release --locked --no-default-features --features gui,client-ptr --bin wow-sim`. The existing repeat detector covers coordinates greater than one; negative UV wrapping remains an existing simulator limitation, outside this correction.

Run the four scripts from the repository with the corrected combined simulator and the local WoW assets:

```sh
python3 scripts/render_player_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/player
python3 scripts/render_att_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/att
python3 scripts/render_feature_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/features
python3 scripts/render_gallery_review.py --sim-root <simulator> --wow-install <WoW> --output <output>/gallery
```

Each script accepts `--view` for one declared scene. The shared renderer checks the loaded addon version against the current TOC, requires exactly one completed-scene marker in the simulator log, rejects execution errors and tracebacks, and writes the Lua scene, log and a `.provenance.txt` beside each image. The marker uses the simulator's console-only `A_Print`, so it adds no text to the game chat. Provenance records the addon and simulator commits, working-diff hashes, simulator binary hash, and scene/image hashes. Content hashes also cover every addon file and the four renderers plus common fixtures, including untracked files. Changed inputs during capture invalidate the output; changed addon/fixture inputs between scenes stop the run.

The screenshots come directly from the renderer. Borders are not removed or retouched, and the background is not replaced after rendering. Scenes explicitly simulate a character collection, position and optional ATT records; names, icons and the route calculation use the actual addon and client assets. They verify visible layout and those modeled workflows, not protected travel or complete native-client acceptance.

Some unowned actions still use the addon's visible data fallbacks: the simulator lacks spell 393222's icon record (Watcher's Legacy displays the question-mark texture), and the Vilo help uses `Fraktion 2478` when its faction name is unavailable. These captures do not certify complete simulator item/spell/localization data. The declared nine owned teleports and the quest recommendation retain their resolved icons.

## Verification

The new scaled-corner and mirrored-UV regressions failed before the renderer fix. Afterward, all **33 renderer tests passed**, including native corner crops at scales 0.75, 1 and 1.5, both mirror axes, a repeating rotated edge, and natural atlas tiling. The fresh binary passed a runtime probe of the measured native Settings color. Formatting and patch whitespace checks passed.

The addon passes **16,028 Lua 5.1 assertions in each of discovery and reverse order**, with no failures. Luacheck reports **zero warnings or errors across 120 files**, and **47 Python generator/packaging tests pass**. The new layout regression resolves the native scroll anchors at panel widths 500, 540, 820 and 1200; the old layout fails five card-boundary assertions. Settings tests cover the native header/gutter chain and category restoration. Subtitle tests exercise ordinary and precomputed routes.

Independent review also exercised a handled Lua error without a stack trace. The renderer previously accepted that faulty scene; it now rejects the capture and removes its image/provenance. Actual route and quest window heights remain at the product's normal 550 UI units, so the gallery does not imply an unavailable compact-window mode.

All 23 final images were visually inspected for connected frame corners, complete cards and actions, icon visibility and meaningful scene state. A second negative probe skipped the scene callback entirely; the missing completion marker also rejects the output. Both rejected probes leave neither an image nor a provenance record. All 58 relative links in the changed documentation resolve, and the gallery's hashes match the published files and unchanged renderer/addon inputs.

The [gallery manifest](../screenshots/render-provenance.txt) maps all 23 published images to their exact inputs and image hashes. The gallery replaces the five historical PNGs with current WebP captures and adds a second phase example. The reference captures identify the committed addon/renderer source; later gallery/documentation commits do not change those inputs.
