# Nexus description form, section by section

Paste each block into the matching field.

---

## Description

Daemon is a quest-repair and item menu for Cyberpunk 2077, built on Cyber Engine Tweaks.

It started with Letter of the Law: the quest would not register that I had gathered the information needed to proceed. Four ids from popular community lists turned out to be wrong, including one that reads perfectly in game but belongs to a different quest entirely.

So the rule here is that nothing fires blind. Every item id is checked against the live TweakDB when the mod loads. Anything your game does not recognise is greyed out and labelled rather than fired into nothing. Functions cannot be checked that way, so they are probed against the game object instead. Where neither is possible, the menu tells you it could not verify rather than implying success.

That matters because a wrong id does not throw an error. It does nothing, quietly, and you cannot tell "wrong code" from "code worked, quest still broken".

**Try this first.** If a Cyberpsycho Sighting will not close, open your shards and read the ones you already hold. A shard picked up long ago and never read keeps the objective open, and no console command is needed to fix it. That is how the sighting that started this mod actually got solved.

From that one quest it grew into the commands people actually ask for: eddies and points, ammo and components, weather and time of day, teleports with saved waypoints, and a browser that reads every clothing, weapon and vehicle id straight out of your own install.

---

## Installation instructions

1. Install Cyber Engine Tweaks first if you do not have it.
2. Unzip this mod into your Cyberpunk 2077 folder. It lands at `bin\x64\plugins\cyber_engine_tweaks\mods\fixer\`.
3. Open the CET overlay and press **Reload All Mods**, or restart the game.
4. The Daemon window appears whenever the overlay is open.

To bind a key: open the overlay, go to **Bindings**, find "Fixer: show menu", click the empty box, press your key, then Save. CET does not allow mods to ship a default key, so it starts unbound.

**To uninstall:** delete the `fixer` folder. It writes nothing outside its own directory apart from a one-line `theme.txt` beside itself holding your chosen colour palette.

---

## Main features

**Quest Fixes** — quest-fact repairs that read the old value before writing, so every change can be reversed from the Undo tab. Templates for fixer tier unlocks and gig counters. A reference list of all 17 Cyberpsycho Sightings with their districts and internal quest ids.

**Shards** — the conversation shards that fail to spawn on a body, which is the usual reason a sighting will not complete.

**Inventory** — eddies, perk and attribute points, ammo, consumables, crafting and quickhack components, iconics.

**World** — time of day, weather, teleport with saved waypoints, character level, attributes.

**Browse** — reads every clothing, weapon and vehicle record out of *your* running game, with search, readable names, rarity colours, and a filter for what V can actually obtain. On a 2.5 install that is roughly 2,000 clothing, 1,800 weapon and 1,400 vehicle records. Because they come from your game rather than a list, the ids are correct for whatever patch you are on.

**Diagnostics** — what your build actually exposes, manual record and fact checks, and six colour palettes.

**Undo** — every fact write with its previous value, one click from being restored.

### What it deliberately will not do

- **Force-complete a quest.** There is no previous state to restore, and on 2.5 the journal enum names do not resolve, so it would fall back to hard-coded numbers. A wrong number there is a permanently wrong quest.
- **Rewrite story facts.** Undoing a fact does not undo what the story already did because of it.
- **Teleport you somewhere you cannot leave.** The preset destinations stay disabled until you have saved a waypoint to return to.

---

## Requirements

- Cyberpunk 2077 **2.5**
- **Cyber Engine Tweaks 1.38.1** or later

Built and tested on 2.5 with CET 1.38.1. CET tracks game patches closely, so when the game updates this mod will not run until CET ships a matching build.

Some entries are community-reported ids that could not be confirmed. Those appear greyed out on installs where they do not resolve, which is the point of the verification: you can see which ones are real on your build rather than guessing.

---

## Shout outs

**Cyber Engine Tweaks** and everyone who maintains it. None of this exists without the scripting API and the TweakDB access it exposes.

**The RED Modding wiki**, particularly the quest-id reference, which supplied the verified ids for all 17 Cyberpsycho Sightings and corrected three ids I had wrong from community lists.

And whoever wrote the first "just use this console command" post, for being wrong in an interesting enough way that it turned into a tool.
