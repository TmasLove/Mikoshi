Mikoshi 1.0.1 — a quest-repair and item menu for Cyberpunk 2077

**Requires [Cyber Engine Tweaks](https://www.nexusmods.com/cyberpunk2077/mods/107) 1.38.1+. Mikoshi is a Lua mod — without CET nothing appears and there is no key to bind.** Read `READ THIS FIRST.txt` in the download.

Built for game **2.5**. Download `Mikoshi-1.0.1.zip` and unzip into your Cyberpunk 2077 folder, then open the CET overlay and press *Reload All Mods*.

---

## The idea

A wrong item id in Cyberpunk does not throw an error. It silently does nothing — so you cannot tell "wrong code" from "code worked, quest still broken". That one fact shaped everything here.

Every id in the catalogue is checked against **your** TweakDB when the mod loads. Anything your build does not have is greyed out and labelled instead of being fired into nothing, and Diagnostics names exactly which ones and offers to search your own game for what they are called now.

Nothing reports success because a call did not raise. A call that returns nothing is reported as *not confirmed*, not as *OK*.

## What is in it

- **Quest fixes** — known fact repairs, read before written, already-applied ones disabled rather than left inviting a pointless write. Every fact can be sent to a live watch card with one click.
- **Shards** — the cyberpsycho and quest shards that fail to spawn on a body, including three that community lists had wrong.
- **Inventory** — eddies, perk/attribute/relic points, ammo, healing, crafting materials, iconics. Each row shows the item's real in-game name read from TweakDB.
- **World** — time of day, teleport with saved waypoints, an unstuck nudge, live rain readouts.
- **Browse** — 2074 clothing, 1828 weapon and 1379 vehicle records read live out of your install, searchable, with a filter for what V can actually obtain. Correct by construction for whatever patch you are on.
- **Diagnostics** — what your build actually exposes, the ids that failed, the watch list, and nine palettes.
- **Undo** — every fact write with its previous value.

## A watch card on a key

CET does not allow a mod to ship a default key, so bind one in the CET overlay under *Bindings* → "Mikoshi: pin the watch card".

It pins a small live card with the overlay **closed**, showing the current value of any quest facts you are watching, highlighted for six seconds when one changes. Pin the facts a quest should be setting, go do the thing, and watch which one never moves. That is the actual diagnostic.

## Updating

`tools/Check for Mikoshi updates.cmd` — double-click it. It asks GitHub for the newest version, backs up your `fixer` folder, installs over it, and carries your palette, watch list, blocked quests and folds across.

There is no button for this inside the mod because there cannot be: CET's Lua sandbox has no network stack. The Diagnostics → Updates row probes for one anyway and tells you what it finds, so if a future CET adds one it will show up there.

## What is deliberately not here

- **Force-completing a quest.** No undo, and its enum did not resolve on 2.5.
- **Setting an attribute directly.** It moved the number and left every perk that number gates locked. A command that looks like it worked and did not is the one thing this menu refuses. Attribute points remain — they go through the development system and unlock what they are supposed to.
- **Setting the weather.** `Game.GetWeatherSystem()` on 2.5 has no `SetWeather` at all; every method on it reads. The rain values it does expose are shown instead.

## Known

The "stop a quest taking focus" guard identifies the right quest now but does not reliably enforce the block on 2.5. It says so in those words rather than sitting there looking like it works, and the section is collapsed by default.

MIT licensed. Cyber Engine Tweaks is separate software under GPL-3.0 and is not included.
