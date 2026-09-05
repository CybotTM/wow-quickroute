# Player workflow review, 5 September 2026

The first review concentrated on transport topology, access data, protected actions and standalone regression tests. It did not sufficiently exercise the visible player workflows. Five reports from the installed client exposed that gap: missing header glyphs, an ambiguous vendor label, an account-owned racial toy marked usable by another race, acquisition help that was hard to find, and branding below the native Settings divider. Passing the earlier tests did not establish that these workflows were correct.

This follow-up reviews those five cases and neighboring behavior independently of the implementation author. It uses source inspection, small reproductions of state changes, Lua 5.1 regressions and rendering against Blizzard UI source and local client assets. User screenshots are evidence for the reported issues and are not included in the repository.

## Reported cases

| Player action | Correction | Evidence |
| --- | --- | --- |
| Open the map sidebar | Collapse and refresh controls use native textures/atlases, avoiding missing font glyphs | Sidebar component render; native Blizzard template references |
| Select a currency | “Am schnellsten erreichbar” describes estimated travel time, including available transport | Destination selection tests; German copy review |
| Open Teleports on a non-Worgen with account-owned Tess's Peacebloom | Race eligibility and the client's toy usability answer gate both status and actions | Worgen/non-Worgen, API refusal/error and stale inventory regressions |
| Click a missing item | Left click opens the item's ATT popout, falling back to QuickRoute help. Right click and the list's “So erhältlich” button open QuickRoute help directly | ATT-present/absent/error, row reuse and both click paths tested; help window renders |
| Open QuickRoute Settings | Compact branding occupies the native header above its divider; Defaults and Route have separate space | Settings category/search/close/reopen restoration tests; German header render |

The help window shows available requirements, a bounded preview of ATT source information and a copyable Wowhead URL. Routing requires a separately recorded source position; an unknown position produces an explanation. ATT remains optional. Its own popout contains the full source hierarchy and variants.

## Additional defects found by this pass

These cases were reproduced independently of the implementation author and covered by targeted regression tests. They complement, rather than replace, the retail cases below.

| Severity | Reproduced failure | Correction / verification |
| --- | --- | --- |
| P2 | At 150% scale the main window's bottom tabs can leave a small screen | Fit the preferred scale to available space at opening, slider changes and display changes; preserve the preference. Reproduced in a 1366 × 768 render and verified with small-screen tests and an after render |
| P1 | A waypoint-detection failure leaves the old route's actionable travel cards visible | Clear actionable cards and QuickRoute-owned guidance on detection, calculation and rendering failures |
| P2 | A delayed callback restores an old navigation arrow after clearing/replacing the route | Route generations invalidate queued guidance; closing the view also prevents a queued callback from publishing |
| P2 | Clearing QuickRoute's former native pin also clears a pin the player has since replaced | Compare the currently observable map and coordinates before removal; unknown or secret coordinates do not grant ownership |
| P2 | A selected quest search result routes to its cached old objective | Resolve the live quest target again at click time; report absence instead of using stale coordinates |
| P2 | A displayed currency vendor can retain an offer that a later merchant observation removes | Revalidate both explicit selections and asynchronous winners against current offers; an empty vendor list has no fastest-route action |
| P2 | Revamped Silvermoon services use coordinates copied from the old city map | Use surveyed positions on map 2393; distinguish shared services from the Horde enclave |
| P2 | Service routing offers engineering-only auctioneers to non-engineers, with incorrect positions in several cities | Correct individually sourced locations and profession gates; preserve public Northrend Dalaran services |
| P2 | A previously empty search continues to omit a name after the client supplies its translation | Invalidate cached refinements and share resolved names across records for the same NPC/quest; expose the remaining English-name/ID fallback |
| P2 | The new acquisition route can select an ATT item variant unavailable to the current character | Check ATT's settings-independent character filter on the complete bounded source ancestry; prefer `sourceParent` and keep the preview tied to the routed variant |
| P2 | Character filtering alone does not establish ATT source availability | Check supported prerequisite groups, level, reputation, renown, covenant and patch conditions through the existing catalogue evaluator. Unknown timed/dynamic conditions keep help available without an exact-source action |
| P2 | Known modern spellbook teleports appear missing in the panels | Share the retail spellbook probe with inventory scanning, including explicitly usable general actions |
| P2 | Cooldown changes leave stale availability in inventory/map controls | One debounced observer refreshes active views on actual state changes and schedules the nearest expiry; hidden views and combat avoid rebuilds |
| P2 | The sidebar omits resolved garrison/choice destinations, loses clicks after reopening, or displays the previous map after collapsing | Use resolved destinations with access and activation-zone checks; rebuild overlays on reopening and retain the newly viewed map while collapsed |
| P2 | QuickRoute's own tracking events and intermediate native pin can replace the chosen endpoint | Ignore internally generated tracking events and exclude an owned guidance pin from user-destination inputs; preserve genuine replacement pins |
| P2 | Native collapse artwork becomes a yellow square | Respect the minus atlas's native 13 × 4 size instead of stretching it to 14 × 14; verify both plus and minus against actual CASC artwork |
| P2 | German Settings labels are clipped by the native label column | Use concise option labels and keep detailed explanations in the native tooltips |
| P2 | Game controls cover the main window while its independently parented secure buttons cover secondary dialogs | Use native panel/dialog strata and keep each protected overlay just above its visible target. Unfiltered main/help/menu/Settings renders and combat/recycled-overlay regressions verify ordering |
| P2 | Text from the inventory remains visible behind acquisition help | Use an opaque native white texture tinted dark for main and secondary reading surfaces; verify the overlapping windows without hiding the underlying controls |

Known remaining search limitation: the client does not supply a complete localized global NPC/quest index. QuickRoute searches source names, IDs, active localized quests and translations already resolved during display. The UI explains the fallback; it does not imply every unseen German name is available. Fetching tens of thousands of translations on each search was not introduced.

A Shattrath spell coverage cross-check initially appeared to find a missing ID when inspecting only the handwritten teleport table. Spell 35715 was already loaded by the generated travel supplement. A learned-spell and routing-edge regression verifies that integration; no duplicate destination or invented faction rule was added.

## Visual simulator provenance

The early images used the local map-data build, without all four user PRs combined. The final visual pass corrects that verification gap. A separate worktree combines these exact inputs from [Osso/wow-ui-sim](https://github.com/Osso/wow-ui-sim):

| Input | Commit |
| --- | --- |
| [PR 7: retail UI rendering/manifest](https://github.com/Osso/wow-ui-sim/pull/7) | `972bd8f77376121d49e20a0f1282f42c7e59a9c4` |
| [PR 8: map data](https://github.com/Osso/wow-ui-sim/pull/8) | `11adf3ce13bd8583b9dd4a15f6351dda050baafc` |
| [PR 9: teleport items/spells](https://github.com/Osso/wow-ui-sim/pull/9) | `6b82c5435e1202dbc0b63b424376293a35001af7` |
| [PR 10: named colors](https://github.com/Osso/wow-ui-sim/pull/10) | `90bacf98a3f0f162d65ed11c08cc3cbd4426900b` |

The common base is `bbd591fe4225eab3a466c6a43904f268d6511dac`. Applying the base-to-PR 8/9/10 patches to PR 7 with `git apply --3way --index` produced tree `8c42da41c684f7c62bb1010f681ff69ab8cd9122`, without conflicts or manual source edits. Existing worktrees were preserved.

The release build used `--locked --no-default-features --features gui,client-ptr`, compiling `wow-sim` and `wow-cli` with rustc 1.98.1. The resulting `wow-sim` SHA-256 is `2195dc0fee507b8322f4d6ef0efe140bd6392fbbb4d3e3816f3704fd544f69c6`. Clean startup reported zero Lua errors; separate smoke checks verified UTF-8, map/item data, named colors and actual GPU rendering.

The [render script](../scripts/render_player_review.py) loads the current addon and its real German strings. Blizzard chrome and item/map names retain the simulator locale. A declared ATT-presence fixture and an empty-currency fixture exercise those views; they do not represent live ATT results. The small-screen scene retains the full game UI and secure overlays, so layering is visible. A subtree-only filter would hide the UIParent-owned secure buttons and miss that interaction.

## Final captures and verification

| View | What is visible |
| --- | --- |
| [Native Settings](../screenshots/settings-player-review.webp) | Branding above the divider, separate action buttons, concise German labels |
| [Small-screen inventory](../screenshots/teleports-small-player-review.webp) | Preferred 150% scale fitted to 1366 × 768; tabs and owned-item icons remain accessible above the HUD |
| [Help over inventory](../screenshots/overlap-help-player-review.webp) | Source text and route action remain readable above the main window and secure controls |
| [Filter menu](../screenshots/overlap-menu-player-review.webp) | Native dropdown covers the main window and item controls |
| [Map sidebar](../screenshots/sidebar-player-review.webp) / [collapsed](../screenshots/sidebar-collapsed-player-review.webp) | Native plus/minus dimensions and refresh artwork |
| [Known acquisition source](../screenshots/acquisition-vendor-player-review.webp) / [unknown position](../screenshots/acquisition-unknown-player-review.webp) | Optional ATT action, explicit available route or missing-location explanation |
| [Empty currency result](../screenshots/currency-empty-player-review.webp) | Return-to-currencies action and a wrapped explanation |

The script also opens native Settings from the visible teleport inventory without a subtree filter. Blizzard closes the registered QuickRoute window, and its secure item buttons are released.

Final local verification: **15,481 Lua 5.1 assertions passed in each of discovery and reverse file order**, with zero failures. **47 Python generator/packaging tests passed**. Luacheck 1.2.0 reported **zero warnings and errors across 108 files**; whitespace and documentation link checks passed. All ten declared render scenes completed without execution errors or Lua tracebacks.

## Evidence limits

The combined simulator resolves the earlier startup errors, but remains a model of the client. These checks do not execute protected travel on a real character or establish pixel-perfect behavior on every configuration. Installation and byte verification are separate from in-game acceptance. The [retail acceptance cases](RETAIL-ACCEPTANCE.md) specify what remains to be exercised in the client; an unchecked case is not reported as passed.

The addon still minimizes estimated cost through recorded, currently eligible connections. It cannot prove the fastest physical route around every terrain obstacle, moving NPC or hidden phase. See the [routing review and coverage limits](REVIEW-2026-09-05.md).

## Source references

- ATT's [popout API](https://github.com/ATTWoWAddon/AllTheThings/blob/8809863ca3e6e4cb4bf8f2cae1d18d52fc209235/src/UI/Window%20Definitions.lua), [indexed search](https://github.com/ATTWoWAddon/AllTheThings/blob/8809863ca3e6e4cb4bf8f2cae1d18d52fc209235/src/Cache.lua) and [global namespace](https://github.com/ATTWoWAddon/AllTheThings/blob/8809863ca3e6e4cb4bf8f2cae1d18d52fc209235/src/base.lua).
- ATT's installed `src/Modules/Filter.lua` defines `CurrentCharacterFilters` separately from account-wide collection display settings. Its recursive reference follows `sourceParent` before `parent`; QuickRoute uses a bounded equivalent with error handling.
- [Method's Silvermoon survey](https://www.method.gg/guides/location-of-the-auction-house-bank-notable-npcs-and-vendors-in-midnight-silvermoon-city), published 26 February 2026, supplies map 2393 service positions and the shared/enclave distinction. Individual engineering auctioneer sources are linked beside their records in `Data/ServicePOIs.lua`.
- Native Settings header lifecycle and icon atlases were inspected in the matching Blizzard UI source mirror. The live game remains the authority for protected-action behavior.
