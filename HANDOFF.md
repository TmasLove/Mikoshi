# Handoff: a quest-fix mod menu for Cyberpunk 2077, on Cyber Engine Tweaks

Written 2026-11-07. Everything under "Verified on this machine" was checked
against the actual install, not recalled. Everything under "Unverified" is
exactly that, and the first job of whoever picks this up is to turn it into one
or the other.

## The ask

A CET mod menu that repairs bugged and soft-locked quests: force-complete a
stuck gig, set the quest facts the game failed to set, and hand over shards that
failed to spawn on a corpse. An overlay window with buttons, not console
copy-paste.

## Short answer: yes, and the hard part is not the menu

CET gives you a Lua runtime, an ImGui binding and full reflection over the
game's script functions. A window with buttons is an afternoon. The real work is
that **the quest ids, fact names and item codes circulating online are mostly
from patch 1.x**, and this game is on 2.5. A wrong id does not throw. It does
nothing, quietly, which is the worst possible behaviour in a tool whose entire
job is to tell you whether a quest got fixed.

So the architecture below is built around verification rather than around the UI.

## Verified on this machine

| | |
| --- | --- |
| Game | Cyberpunk 2077 **2.5**, `D:\SteamLibrary\steamapps\common\Cyberpunk 2077` |
| Game exe | 64 MB, last written 2026-11-03 |
| CET | **1.38.1**, `bin\x64\plugins\cyber_engine_tweaks.asi`, installed 2026-11-07 13:54 |
| CET load | Clean. Every hook reports "complete", zero `[error]` or `[warning]` lines in `cyber_engine_tweaks.log` |
| Overlay key | Already bound (`bindings.json` has `cet.overlay_key`) |
| Mods installed | **None.** `...\cyber_engine_tweaks\mods\` is empty |
| Console use | `scripting.log` shows manual console commands today, adding `Items.PerkPointSkillbook` in loops |
| RED4ext | **Not present anywhere in the game folder**, despite CET's README saying to install it first. CET 1.38.1 loads fine without it here |
| Source zip | `C:\Users\User1\Downloads\Game Mods\CET 1.38.1 - Game version 2.5 107 1.38.1 2026-10-26T01-28Z ozVyzbb0n.zip`, already installed, no need to unzip again |

CET 1.38.0 is the release that added patch 2.5 support, stated as game version
`3.0.88.46235`, and it says earlier patches are no longer supported. 1.38.1
followed on 2026-10-26 with only a RED4ext.SDK and RTTIHelper update. **CET
tracks game patches closely**: when the game updates, this mod stops running
until CET ships a matching build. Say so in the mod's own README.

### Two environment facts that shape the design

- **CET bundles `json.lua`** at `...\cyber_engine_tweaks\scripts\json\json.lua`, so
  settings and an undo log can be real JSON rather than hand-rolled.
- **TweakDB strings on disk are Kraken-compressed.** `tweakdb\tweakdbstr.kark`
  starts with the magic bytes `KARK` and greps clean for nothing. There is no
  offline way to check whether `Items.ma_wat_kab_08_onscreen_01` is real. It has
  to be asked of the live TweakDB, in game. That is why the probe below exists.

## CET API, confirmed against the current wiki

Docs moved: the old `wiki.redmodding.org/cyber-engine-tweaks` scripting pages are
deprecated and some 404. The live ones are under
`wiki.redmodding.org/scripting-cyberpunk/`.

**Layout.** `<game>\bin\x64\plugins\cyber_engine_tweaks\mods\<mod_name>\init.lua`.
`init.lua` is the only file loaded automatically; everything else is required
from it. No manifest file exists. `return mod` at the end exposes the table to
other mods via `GetMod()`. A mod has read and write access to its own folder
only.

**Lifecycle.** `registerForEvent(event, callback)`, registered in `init.lua`:

- `onTweak` fires before `onInit`, for TweakDB changes that must land early.
- `onInit` fires once when CET has loaded all mods, and is the earliest point the
  `Game` object is safe to touch. Register observers here. Also fires on
  "Reload all mods".
- `onUpdate(deltaTime)` every frame, ms. `onDraw` every frame, ImGui only.
- `onOverlayOpen` / `onOverlayClose` for overlay-only UI.
- `onShutdown` on exit or reload, for cleanup.

**Input.** `registerHotkey(slug, label, callback)` and
`registerInput(slug, label, callback)`, both at root level in `init.lua`, outside
any event. **Mods cannot ship default keybinds** — the user assigns every one in
the Bindings tab. `registerHotkey` fires on release and will not fire while a
game keybind is held, so prefer `registerInput`, whose callback takes
`keypress` (true on press, false on release) and runs twice if you ignore it.

**ImGui.** Draw only inside `onDraw`; anywhere else is prohibited. The pattern,
with `End()` outside the `if`:

```lua
if ImGui.Begin('Quest Fix', ImGuiWindowFlags.AlwaysAutoResize) then
    ImGui.Text('Hello')
end
ImGui.End()
```

Since 1.38.0, ImGui only receives mouse and keyboard while the overlay is open,
and `ImGuiWindowFlags.NoDocking` is available.

**Game access.** `Game.GetPlayer()`, `Game.AddToInventory("Items.money", 500)`,
`Game.GetTransactionSystem()`, and so on. Hooks are
`Observe("ClassName", "MethodName", function(self, ...) end)` — `self` first, it
is required. Do not touch `Game` or `GetMod()` before `onInit`. Do not cache the
player handle across sessions; clear it on
`Observe("QuestTrackerGameController", "OnUninitialize", ...)`.

**Testing.** The overlay's "Reload All Mods" button fires `onShutdown` then
`onInit`, so you never restart the game to test a change. Turn on "Enable ImGui
Assertions" in the dev options while building.

## About the snippets you pasted

The force-complete block is a real and widely used technique, but do not ship it
as written. Three problems:

**The magic numbers.** `ChangeEntryStateByHash(hash, 3, 2)` hard-codes an enum.
Use `gameJournalEntryState.Succeeded` and the notify enum by name. If CDPR
reorders that enum in a patch, `3` silently becomes something else, and a tool
that force-sets quest state to the wrong value is worse than no tool.

**The double `GetParentEntry`.** `GetParentEntry(GetParentEntry(tracked))`
assumes the tracked entry is always exactly two levels under the quest. For a
tracked sub-objective it is three, and you would force-complete the wrong node.
Walk up until the parent comes back nil, keeping the last non-nil, instead of
counting hops.

**The ids.** Every shard code and fact name in that list traces back to Reddit
and YouTube posts, most predating patch 2.0. `TweakDBID.new()` hashes any string
you give it, so it will happily build an id for a record that does not exist —
constructing one is not a validity test. `TweakDB:GetRecord(id)` is.

None of that makes the list useless. It makes it a list of candidates.

## The safety line this mod has to draw

There are two classes of operation here and they are not equally reversible:

- **Facts are reversible.** `GetFactStr(name)` before `SetFactStr(name, value)`
  gives you the prior value, so every fact write can be logged and undone. This
  is the same rule as Canary: capture prior state, emit an undo path.
- **Journal state changes are not.** Once a quest is forced to Succeeded there is
  no recorded previous state to restore, and quest objects downstream may already
  have reacted. The only undo is a save made beforehand.

So: two tiers in the UI, labelled honestly. Fact writes and item grants in the
normal tier with an undo list. Journal force-complete behind a confirmation that
says plainly that it cannot be undone and that the user should hard-save first.
Do not blur them into one "Fix" button.

Worth stating in the mod itself: force-completing a quest clears the objective
but does not replay whatever the quest would have done. For fixer gigs you also
have to set the gig's `_finished` fact or the fixer's counter stays wrong, which
is precisely the kind of half-fix that looks like success and is not.

## Build order

1. **Run the probe.** `probe\init.lua` in this folder is a read-only mod that
   checks which of these actually exist on this install: `GetQuestsSystem`,
   `SetFactStr` / `GetFactStr`, the journal manager methods, the
   `gameJournalEntryState` and notify enums, and each candidate shard record. It
   wraps every call in `pcall`, so a missing function prints as missing instead
   of killing the run. Copy it to
   `...\cyber_engine_tweaks\mods\questfix_probe\`, launch, open the overlay, read
   the console, paste the output back here. Delete it afterwards. **Do this
   before writing a line of the menu** — it converts every "unverified" above
   into a yes or a no in one game launch.
2. **Scaffold.** A mod that opens an overlay-only window with the version, the
   game patch, and nothing else. Prove load, draw and reload-all work.
3. **Diagnostics tab, read-only.** Show the tracked entry, the quest it resolves
   to after walking up the parents, its hash and current state, and the value of
   any facts the user types in. No writes at all. This alone is more than the
   console gives you, and it is how you confirm the parent-walk is correct before
   anything acts on it.
4. **Fact tier.** Read-before-write, an on-screen log of every change with its
   prior value, and an undo button per entry.
5. **Journal tier.** Force-complete behind confirmation, plus the matching
   `_finished` fact for gigs.
6. **Curated list.** Only entries whose records came back present in step 1. Mark
   anything unverified as unverified in the UI rather than hiding it.

## Open questions for whoever continues

- Which of the candidate shard ids survive step 1. Expect losses.
- Whether `SetFactStr` lives on the quests system, as a `Game.` global, or both
  in 2.5.
- Whether a quest actually needs fixing on the current save, or this is being
  built pre-emptively. If there is a specific stuck quest, name it: the fastest
  path is to fix that one by hand in the console first, then generalise what
  worked into the menu.
- Native Settings UI integration, if the menu grows settings worth persisting.

## Links

- Releases and version support: https://github.com/maximegmd/CyberEngineTweaks/releases
- Current scripting wiki: https://wiki.redmodding.org/scripting-cyberpunk/
- Mod structure: https://wiki.redmodding.org/scripting-cyberpunk/cyber-engine-tweaks/first-steps/mod-structure.md
- Events: https://wiki.redmodding.org/scripting-cyberpunk/cyber-engine-tweaks/cet-functions/events.md
- ImGui examples: https://wiki.redmodding.org/scripting-cyberpunk/cyber-engine-tweaks/cet-functions/ui-examples.md
- Official example mods: https://github.com/WolvenKit/cet-examples
- Game script reference: https://nativedb.red4ext.com/
