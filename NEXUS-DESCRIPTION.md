# Nexus upload pack

Paste the description below into the Nexus mod page. Attach `docs/banner.png`
as the header image and the screenshots in `docs/` as the gallery. Upload
`dist/Daemon-1.0.zip` as the main file; it unpacks straight into the game
folder.

**You have to do the upload.** It needs your Nexus login, and I am not going to
sign in or post as you.

---

## Before you publish

1. **Check the name is free.** Search Nexus for "Daemon" in Cyberpunk 2077
   mods. It is a common word in this game's vocabulary and may already be
   taken. `Daemon - Night City Toolkit` is a safer title.
2. **Decide about the unverified ids.** Several shard entries are community
   leads with unconfirmed suffixes. In the menu they appear greyed out and
   labelled, so nothing fires blind, but a public user will see rows that do
   not work on their install. That is honest but it will draw comments. Either
   ship as is and say so in the description, or trim them to the confirmed set.
3. **Say which patch you tested.** 2.5 with CET 1.38.1, which is what the
   header image states.

---

## Description to paste

**Daemon is a quest-repair and item menu for Cyberpunk 2077, built on Cyber
Engine Tweaks.**

It exists because a cyberpsycho sighting would not close, and every fix list
online gave the wrong item id for it.

### What it does

- **Quest Fixes** — quest-fact repairs that read the old value before writing
  it, so every change can be put back from the Undo tab. Templates for fixer
  tier unlocks and gig counters. A checklist of all 17 Cyberpsycho Sightings
  with their districts and internal quest ids.
- **Shards** — conversation shards that fail to spawn on a body, which is the
  usual reason a sighting will not complete.
- **Inventory** — eddies, perk and attribute points, ammo, consumables,
  crafting and quickhack components, iconics.
- **World** — time of day, weather, teleport with saved waypoints, character
  level, attributes.
- **Browse** — reads every clothing, weapon and vehicle record out of *your*
  running game, with search, readable names, rarity colours, and a filter for
  what V can actually obtain. On a 2.5 install that is roughly 2,000 clothing,
  1,800 weapon and 1,400 vehicle records.
- **Diagnostics** — what your build actually exposes, plus six colour palettes.

### Why it is different

**Nothing fires blind.** Every item id is checked against the live TweakDB when
the mod loads. Anything your game does not recognise is greyed out and labelled
instead of being fired into nothing. Functions cannot be checked that way, so
they are probed against the game object instead. Where neither is possible, the
menu says it could not verify rather than implying success.

That matters because a wrong id does not throw an error. It does nothing,
quietly, and you cannot tell "wrong code" from "code worked, quest still
broken". While building this, four separate ids from popular community lists
turned out to be wrong, including one that reads perfectly in game but belongs
to a different quest entirely.

### What it deliberately will not do

- **Force-complete a quest.** No previous state to restore, and on 2.5 the
  journal enum names do not resolve, so it would fall back to hard-coded
  numbers. A wrong number there is a permanently wrong quest.
- **Rewrite story facts.** Undoing a fact does not undo what the story already
  did because of it.
- **Teleport you somewhere you cannot leave.** The preset destinations stay
  disabled until you have saved a waypoint to return to.

### Requirements

- Cyberpunk 2077 **2.5**
- [Cyber Engine Tweaks](https://www.nexusmods.com/cyberpunk2077/mods/107)
  **1.38.1** or later

### Installation

Unzip into your Cyberpunk 2077 folder. It lands at
`bin\x64\plugins\cyber_engine_tweaks\mods\fixer\`.

Open the CET overlay and press **Reload All Mods**, or restart the game.

To bind a key: overlay, **Bindings**, "Fixer: show menu". CET does not allow
mods to ship a default key, so it starts unbound.

### Uninstall

Delete the `fixer` folder. It writes nothing outside its own directory apart
from a one-line `theme.txt` beside itself for your chosen palette.

### Credits

Built on Cyber Engine Tweaks. Quest ids cross-checked against the RED Modding
wiki's quest-id reference.
