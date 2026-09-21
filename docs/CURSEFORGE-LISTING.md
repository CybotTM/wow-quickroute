# Distribution listing

Ready-to-paste text for the CurseForge, WoWInterface and Wago pages. Only the
project owner can apply it; this file keeps it in the repository so it is
reviewed like anything else and does not drift from what the addon does.

## Why it is being replaced

The current listing leads with Dijkstra, teleport detection and waypoint
routing. That undersells what is in the addon today, because multi-stop trips,
phase-aware routes, conditional shortcuts, dungeon teleports, discovered flight
points, quest and NPC search, service and currency-vendor routing and the
acquisition help are all missing from it.

At the same time it oversells certainty. "Routes to any waypoint" and "knows all
portal connections" promise more than a deliberately conservative implementation
delivers, and the first player who meets a coverage gap reads that as a bug.

"Uses Dijkstra" is an implementation detail. It is not why anyone installs an
addon.

---

## Short description

Work out how to get there. QuickRoute turns a map pin, a quest, a dungeon or a
vendor into steps your character can actually take, and says plainly when it
cannot.

## Long description

**QuickRoute answers one question: how does this character get to that place?**

It reads the teleports, portals, boats, zeppelins, flight points and shortcuts
this character can use right now, and gives you the fastest route it can
justify, step by step.

### What you can point it at

- A map pin, your own or one from TomTom.
- A tracked quest, an unwatched quest in your log, or a known giver.
- A dungeon or raid entrance, including the Mythic+ teleports you have earned.
- A city, a zone or a travel hub, by name.
- An auction house, a bank, a void storage or a crafting table.
- A currency vendor, ranked by how long it takes you to reach one.
- A trip with up to twenty stops, pasted as `/way` lines or imported from
  TomTom, ordered for you.

### What it does about your character

Access is checked against this character, not a general answer. A portal you
have not unlocked, a flight point you have not discovered, a spell you do not
know and an engineering toy without the profession are not offered. Phase-
dependent entrances are handled, and where the phase of a remote zone cannot be
known, the route says so instead of guessing.

### When something does not work

A step you cannot use gets a "Cannot use" button. QuickRoute keeps the
destination, drops that connection for this route and looks for another way.
Right-clicking Refresh takes your refusals back. Nothing about your character is
recorded.

A route that cannot be produced tells you which kind of problem it was: your
position is not available yet, the route needs something you do not have, or
QuickRoute knows no connection at all. Those need different responses from you,
so they are not one message.

### What it does not do

It does not know the terrain. It routes between recorded points and cannot see a
cliff between two of them.

It does not know every connection in the game. Where the catalogue has a gap, it
says there is no known route rather than inventing one.

Travel times are estimates. Flight-path times are calculated from distance, not
measured, and a leg on a map you are not standing on is priced from what that
zone allows rather than from what the client reports.

### Works alongside

TomTom is optional and supported. Other addons can ask QuickRoute for a route
through `QuickRouteAPI` without it taking over your arrow.

---

## Screenshots to keep current

The gallery should show the route panel with a real multi-step route, the trip
window with a pasted guide section and its import preview, the destination
search with a query that has several matches, and a failure that names its
reason. A screenshot of an empty panel demonstrates nothing.
