--[[
  Fixer - a categorised mod menu for Cyberpunk 2077, on Cyber Engine Tweaks.

  Built for game 2.5 / CET 1.38.1.

  Design rules, in order of importance:

  1. NOTHING FIRES BLIND. Every item id is checked against the live TweakDB when
     the mod loads. TweakDBID.new() hashes any string you hand it, valid or not,
     so building an id proves nothing - asking for the record does. Ids the game
     does not recognise are shown greyed out and labelled, not fired anyway.
  2. REVERSIBLE AND IRREVERSIBLE ARE NOT THE SAME TAB. Quest facts are read
     before they are written, so the Undo tab can put the old value back.
     Forcing a journal entry to Succeeded cannot be undone, so it sits behind an
     arming checkbox that says so.
  3. SAY "COULD NOT VERIFY" RATHER THAN PRETENDING. If an API or an enum is
     missing on this build, the button is disabled and the Diagnostics tab says
     which one and why.

  Install: copy this folder to
    <game>\bin\x64\plugins\cyber_engine_tweaks\mods\fixer\
  Open the CET overlay, bind "Fixer: toggle window" under Bindings if you want a
  hotkey. The window appears whenever the overlay is open.
]]

local mod = { ready = false }
local VERSION = '1.0'

-- The catalog lives in its own file so a typo there cannot stop the menu
-- loading. If it fails we carry on with an empty catalog and say so.
local data, dataErr = nil, nil
do
    local ok, res = pcall(require, 'data')
    if ok and type(res) == 'table' then data = res
    else dataErr = tostring(res); data = { everyday = {}, exp = {}, shards = {}, facts = {}, templates = {} } end
end

local state = {
    overlayOpen = false,
    show        = true,    -- show alongside the CET overlay
    pinned      = false,   -- keep on screen with the overlay closed (hotkey)
    tab         = 1,
    amounts     = {},      -- per-row amount boxes
    undo        = {},      -- { fact, prev, new, at }
    log         = {},      -- newest first, what just happened
    armed       = false,   -- force-complete safety
    records     = {},      -- id -> true/false, filled at onInit
    missing     = {},      -- the rows whose record is not on this build
    folds       = {},      -- section title -> open, persisted beside the mod
    -- The tracking guard. list holds { key, label } for quests that are not
    -- allowed to hold journal focus; lastGood is the entry focus goes back to.
    guard       = { on = false, list = {}, lastGood = nil, at = 0,
                    hits = 0, fails = 0, keySrc = nil, err = nil },
    found       = {},      -- missing id -> candidates read out of live TweakDB
    fields      = {},      -- template input boxes
    probe       = { fact = 'ig_phone_manager_off', item = 'Items.money' },
    icons       = true,
    theme       = 1,
    psy         = nil,
    psyShow     = false,
    showCoords  = false,
    watch       = { list = {}, prev = {}, changedAt = {}, input = "" },
    tp          = { cur = nil, text = '', name = '', saved = {} },
    weather     = nil,  -- filled on first use of the World tab
    weatherType = nil,
    browse      = { idx = 1, q = '', cache = {}, accessor = nil, desc = true, playableOnly = true },
    probeResult = '',
}

-- Forward declared: tabWorld (defined above the Browse section) calls both of
-- these, and a local declared further down the file would not be in scope
-- there. Lua would resolve them as globals and find nil at click time.
-- describe() reads an item's real display name out of TweakDB. It is defined
-- down with the Browse code because that is where it grew up, but grantRow --
-- six hundred lines above it -- needs it to put the in-game name on a row, and
-- a local declared below its caller resolves as a global and is nil when the
-- button is pressed. That has cost this file four separate bugs.
local verdict, recordName, describe

-- CET ships 7097 Material Design glyphs and the font to render them
-- (cyber_engine_tweaksontsmaterialdesignicons.ttf), so the menu can have
-- real icons instead of text-only labels. If the module is ever missing, ic()
-- returns an empty string and every label reads exactly as it did before.
-- The module file is IconGlyphs/icons.lua, so require('IconGlyphs') looks for
-- IconGlyphs.lua or IconGlyphs/init.lua and finds neither. That is why the
-- icons never appeared and the toggle looked dead: Icons was nil the whole
-- time. Try the real paths and record which one answered.
local Icons, iconPath, iconErr = nil, nil, nil
for _, p in ipairs({ 'IconGlyphs/icons', 'IconGlyphs.icons', 'IconGlyphs/icons.lua',
                     'IconGlyphs', 'icons', 'scripts/IconGlyphs/icons' }) do
    local ok, m = pcall(require, p)
    if ok and type(m) == 'table' and m.Wrench then Icons, iconPath = m, p; break end
    if not ok and not iconErr then iconErr = tostring(m) end
end
-- CET exposes IconGlyphs as a plain global in some builds, so try that too.
if not Icons then
    local loader = load or loadstring
    local f = loader and loader('return IconGlyphs')
    if f then
        local ok, m = pcall(f)
        if ok and type(m) == 'table' and m.Wrench then Icons, iconPath = m, 'global IconGlyphs' end
    end
end

local function ic(name)
    if not Icons or state.icons == false then return '' end
    local g = Icons[name]
    return g and (g .. '  ') or ''
end

local NAV_ICONS = { 'Wrench', 'Memory', 'Briefcase', 'Earth', 'Magnify', 'Pulse', 'Undo' }

-- The game's own rarity ladder, so a legendary reads as one at a glance
-- instead of every quality tag sharing the same accent colour.
local QUALITY = {
    common    = { 0.78, 0.78, 0.76, 1.0 },
    uncommon  = { 0.42, 0.85, 0.45, 1.0 },
    rare      = { 0.33, 0.62, 1.00, 1.0 },
    epic      = { 0.70, 0.42, 0.95, 1.0 },
    legendary = { 1.00, 0.72, 0.16, 1.0 },
    iconic    = { 1.00, 0.45, 0.15, 1.0 },
}
local function qualityCol(q)
    return QUALITY[tostring(q):lower()] or { 0.62, 0.62, 0.66, 1.0 }
end

local TABS = { 'QUEST FIXES', 'SHARDS', 'INVENTORY', 'WORLD', 'BROWSE', 'DIAGNOSTICS', 'UNDO' }

local COL = {
    ok     = { 0.36, 0.92, 0.55, 1.0 },
    warn   = { 1.00, 0.78, 0.20, 1.0 },
    bad    = { 1.00, 0.24, 0.35, 1.0 },  -- the game's own alert red
    dim    = { 0.55, 0.55, 0.58, 1.0 },
    accent = { 0.99, 0.93, 0.04, 1.0 },  -- Night City yellow
    cyan   = { 0.10, 0.85, 0.94, 1.0 },
}

-- ===========================================================================
-- capability detection: what this build of CET actually gives us
-- ===========================================================================

local caps, api = {}, {}

local function fnExists(tbl, name)
    if tbl == nil then return false end
    local ok, v = pcall(function() return tbl[name] end)
    return ok and v ~= nil
end

-- CET's Lua environment does not reliably expose its globals through the _G
-- table, so hasGlobal('ImGuiCol') answered false and the whole colour theme
-- was skipped. That is why the window was still ImGui default blue while the
-- drawn banner and coloured text worked: those never touched _G.
--
-- Compiling a chunk that simply returns the name resolves it against the real
-- global environment, which is the only check that tells the truth here.
local function hasGlobal(name)
    local loader = load or loadstring
    if not loader then return false end
    local f = loader('return ' .. name)
    if not f then return false end
    local ok, v = pcall(f)
    return ok and v ~= nil
end

local function detectImGui()
    for _, n in ipairs({ 'BeginTabBar', 'BeginTabItem', 'InputInt', 'InputText',
                         'TextColored', 'Separator', 'SameLine', 'TextWrapped',
                         'BeginChild', 'Checkbox', 'Spacing',
                         'PushStyleColor', 'PopStyleColor', 'PushStyleVar', 'PopStyleVar',
                         'SeparatorText', 'Dummy', 'Indent', 'Unindent', 'ProgressBar',
                         'SetWindowFontScale', 'GetWindowDrawList', 'GetCursorScreenPos', 'SetNextItemWidth',
                         'CollapsingHeader', 'PushTextWrapPos', 'PopTextWrapPos',
                         'GetContentRegionAvail', 'GetItemRectMin', 'GetItemRectMax', 'CalcTextSize' }) do
        caps[n] = fnExists(ImGui, n)
    end
    caps.tabs = caps.BeginTabBar and caps.BeginTabItem
    caps.style = caps.PushStyleColor and caps.PopStyleColor and hasGlobal('ImGuiCol')
    caps.stylevar = caps.PushStyleVar and caps.PopStyleVar and hasGlobal('ImGuiStyleVar')
end

-- Enums first by name, then by the community-reported numbers. Using a number
-- is a last resort and the UI says so, because if CDPR reorders the enum a
-- hard-coded 3 quietly becomes the wrong state.
local function resolveEnum(globals, key, fallback)
    for _, g in ipairs(globals) do
        local ok, v = pcall(function() return _G[g] and _G[g][key] end)
        if ok and v ~= nil then return v, g .. '.' .. key, true end
    end
    return fallback, 'hard-coded ' .. tostring(fallback), false
end

local function resolveApi()
    local qs; pcall(function() qs = Game.GetQuestsSystem() end)
    local jm; pcall(function() jm = Game.GetJournalManager() end)
    api.quests, api.journal = qs, jm

    if fnExists(qs, 'SetFactStr') then
        api.setFact, api.setFactSrc = function(n, v) qs:SetFactStr(n, v) end, 'QuestsSystem:SetFactStr'
    elseif fnExists(Game, 'SetFactStr') then
        api.setFact, api.setFactSrc = function(n, v) Game.SetFactStr(n, v) end, 'Game.SetFactStr'
    else
        api.setFactSrc = 'NOT FOUND'
    end

    if fnExists(qs, 'GetFactStr') then
        api.getFact, api.getFactSrc = function(n) return qs:GetFactStr(n) end, 'QuestsSystem:GetFactStr'
    elseif fnExists(Game, 'GetFactStr') then
        api.getFact, api.getFactSrc = function(n) return Game.GetFactStr(n) end, 'Game.GetFactStr'
    else
        api.getFactSrc = 'NOT FOUND'
    end

    api.journalOk = fnExists(jm, 'GetTrackedEntry') and fnExists(jm, 'GetParentEntry')
                and fnExists(jm, 'GetEntryHash') and fnExists(jm, 'ChangeEntryStateByHash')

    -- Re-tracking needs one more method than reading does, so it is probed
    -- separately: the guard can be missing while the rest of the journal
    -- tools work fine.
    api.trackOk = fnExists(jm, 'TrackEntry')

    api.stateSucceeded, api.stateSrc, api.stateNamed =
        resolveEnum({ 'gameJournalEntryState', 'JournalEntryState' }, 'Succeeded', 3)
    api.notify, api.notifySrc, api.notifyNamed =
        resolveEnum({ 'JournalNotifyOption', 'gameJournalNotifyOption' }, 'Notify', 2)
end

-- ===========================================================================
-- helpers
-- ===========================================================================

local function now()
    local ok, t = pcall(function() return os.date('%H:%M:%S') end)
    return ok and t or '--:--:--'
end

local function note(fmt, ...)
    local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
    table.insert(state.log, 1, now() .. '  ' .. msg)
    while #state.log > 60 do table.remove(state.log) end
    print('[Mikoshi] ' .. msg)
end

-- 10000 is unreadable at a glance and 1000000 is worse. Group the digits for
-- display only; the input box itself stays a plain integer field, because
-- InputInt will not parse a string with separators in it.
local function comma(n)
    local out = tostring(math.floor(tonumber(n) or 0))
    local hits
    repeat out, hits = out:gsub('^(-?%d+)(%d%d%d)', '%1,%2') until hits == 0
    return out
end

local function recordExists(id)
    local ok, r = pcall(function() return TweakDB:GetRecord(id) end)
    return ok and r ~= nil
end

local function verifyAll()
    local checked, found = 0, 0
    state.missing = {}
    -- Keep the rows that failed, not just the count. "24 of 32 verified" told
    -- you something was wrong and gave you no way to find out what, which is
    -- the same dead end a silent wrong id leaves you in.
    local function check(list, group)
        for _, row in ipairs(list or {}) do
            if row.record then
                local present = recordExists(row.record)
                state.records[row.record] = present
                checked = checked + 1
                if present then
                    found = found + 1
                else
                    state.missing[#state.missing + 1] = {
                        label  = row.label or row.record,
                        record = row.record,
                        group  = group,
                    }
                end
            end
        end
    end
    check(data.everyday, 'everyday'); check(data.shards, 'shards')
    check(data.ammo, 'ammo'); check(data.healing, 'healing')
    check(data.crafting, 'crafting'); check(data.iconics, 'iconics')
    state.idsFound, state.idsChecked = found, checked
    note('TweakDB check: %d of %d ids present on this build', found, checked)
    if #state.missing > 0 then
        note('%d id(s) are not on this build. Diagnostics names them.', #state.missing)
    end
end

-- ---------------------------------------------------------------------------
-- Reading an attribute back off the character.
--
-- The panel used to show a bare 15 beside the five attribute names. That was
-- the default value of the input box and nothing to do with the character --
-- a number sitting next to five attribute labels reads as a readout, and this
-- one was not one. So read the real values, and where they cannot be read say
-- that instead of printing a number that means nothing.
--
-- Three routes, tried in order, because none is guaranteed on a build. The
-- same readers serve street cred and XP, which is how those two report what
-- actually changed instead of whether a call raised.
-- ---------------------------------------------------------------------------
local ATTR_READERS = {
    { 'StatsSystem:GetStatValue', function(stat)
        local pl = Game.GetPlayer()
        return Game.GetStatsSystem():GetStatValue(pl:GetEntityID(), gamedataStatType[stat])
    end },
    { 'DevelopmentData:GetAttributeValue', function(stat)
        local pl = Game.GetPlayer()
        return PlayerDevelopmentSystem.GetInstance(pl):GetDevelopmentData(pl)
            :GetAttributeValue(gamedataStatType[stat])
    end },
    { 'DevelopmentData:GetAttributeLevel', function(stat)
        local pl = Game.GetPlayer()
        return PlayerDevelopmentSystem.GetInstance(pl):GetDevelopmentData(pl)
            :GetAttributeLevel(gamedataStatType[stat])
    end },
}

-- ---------------------------------------------------------------------------
-- Street cred and XP.
--
-- Game.AddExp is the pre-2.0 call. The two calls sitting beside it in this
-- file, Game.SetAttribute and Game.GiveDevPoints, were BOTH renamed at patch
-- 2.0, so AddExp failing on 2.5 is exactly what that pattern predicts. The
-- development system is the current route. AddExp is kept as a fallback for
-- an older build rather than deleted.
--
-- Neither call returns anything useful, and "it did not raise" has already
-- been mistaken for "it worked" twice in this file, so the amount is read
-- before and after and the DIFFERENCE is what gets reported. If the value
-- cannot be read, that is said plainly instead of claiming success.
-- ---------------------------------------------------------------------------
local readAttribute  -- forward declared: addExperience reads the value back

local function addExperience(kind, n)
    local was = readAttribute(kind)
    local tried = {}

    local did = false
    if hasGlobal('PlayerDevelopmentSystem') and hasGlobal('gamedataProficiencyType') then
        local ok, err = pcall(function()
            local pl = Game.GetPlayer()
            PlayerDevelopmentSystem.GetInstance(pl):GetDevelopmentData(pl)
                :AddExperience(n, gamedataProficiencyType[kind])
        end)
        tried[#tried + 1] = 'DevelopmentData:AddExperience ' .. (ok and 'ran' or ('raised ' .. tostring(err)))
        did = did or ok
    else
        tried[#tried + 1] = 'DevelopmentData:AddExperience unavailable'
    end

    if not did and fnExists(Game, 'AddExp') then
        local ok, err = pcall(function() Game.AddExp(kind, n) end)
        tried[#tried + 1] = 'Game.AddExp ' .. (ok and 'ran' or ('raised ' .. tostring(err)))
        did = did or ok
    end

    local now = readAttribute(kind)
    local how = table.concat(tried, '; ')

    if not did then return false, 'every route refused. ' .. how end
    if was == nil or now == nil then
        return true, ('the call ran but %s cannot be read back on this build, so it is NOT confirmed. %s')
            :format(kind, how)
    end
    if now == was then
        return false, ('%s did not move: still %d. %s'):format(kind, was, how)
    end
    return true, ('%s %d -> %d, up %d. %s'):format(kind, was, now, now - was, how)
end

function readAttribute(stat)
    for _, r in ipairs(ATTR_READERS) do
        local ok, v = pcall(r[2], stat)
        if ok and type(v) == 'number' and v > 0 then
            state.attrSrc = r[1]
            return math.floor(v + 0.5)
        end
    end
    return nil
end

-- Functions cannot be looked up in TweakDB the way item ids can, so they are
-- probed against the Game object instead. A missing one greys out its row
-- rather than throwing when you press the button.
local ACTIONS = {
    time = {
        probe = function() return fnExists(Game, 'GetTimeSystem') end,
        run   = function(h) return pcall(function() Game.GetTimeSystem():SetGameTimeByHMS(h, 0, 0) end) end,
        needs = 'Game.GetTimeSystem',
    },
    weather = {
        probe = function() return fnExists(Game, 'GetWeatherSystem') end,
        -- Capture the return. The first version reported OK whenever the call
        -- did not raise, which is why weather "worked" and nothing changed.
        run = function(s)
            local ok, res = pcall(function()
                return Game.GetWeatherSystem():SetWeather(s, 10.0, 0)
            end)
            return ok, res
        end,
        needs = 'Game.GetWeatherSystem',
    },
    -- Game.TeleportPlayerToPosition is DEPRECATED on the wiki's own teleport
    -- page. The teleportation facility is the current route, and it wants a
    -- Vector4 and Euler angles rather than three loose numbers.
    unstuck = {
        probe = function()
            return fnExists(Game, 'GetPlayer') and fnExists(Game, 'GetTeleportationFacility')
               and hasGlobal('ToVector4') and hasGlobal('ToEulerAngles')
        end,
        run = function()
            return pcall(function()
                local pl = Game.GetPlayer()
                local p  = pl:GetWorldPosition()
                Game.GetTeleportationFacility():Teleport(pl,
                    ToVector4{ x = p.x, y = p.y, z = p.z + 2.0, w = 1 },
                    ToEulerAngles{ roll = 0, pitch = 0, yaw = 0 })
            end)
        end,
        needs = 'Game.GetTeleportationFacility + ToVector4',
    },
    teleport = {
        probe = function()
            return fnExists(Game, 'GetPlayer') and fnExists(Game, 'GetTeleportationFacility')
               and hasGlobal('ToVector4') and hasGlobal('ToEulerAngles')
        end,
        run = function(x, y, z)
            local ok, res = pcall(function()
                local pl = Game.GetPlayer()
                return Game.GetTeleportationFacility():Teleport(pl,
                    ToVector4{ x = x, y = y, z = z, w = 1 },
                    ToEulerAngles{ roll = 0, pitch = 0, yaw = 0 })
            end)
            return ok, res
        end,
        needs = 'Game.GetTeleportationFacility',
    },
    -- Game.SetAttribute was renamed at 2.0. Only "Strength" is documented
    -- verbatim; the other four names are inferred and marked as such.
    setAttribute = {
        probe = function()
            return hasGlobal('PlayerDevelopmentSystem') and fnExists(Game, 'GetPlayer')
        end,
        run = function(attr, n)
            local ok, res = pcall(function()
                local pl = Game.GetPlayer()
                return PlayerDevelopmentSystem.GetInstance(pl):GetDevelopmentData(pl)
                    :SetAttribute(attr, n)
            end)
            return ok, res
        end,
        needs = 'PlayerDevelopmentSystem:SetAttribute',
    },
    -- Documented as Game.SetLevel("Level", 60, 1): three arguments, not two.
    -- Street cred through this call is NOT documented anywhere I could verify,
    -- so it is gone rather than left in looking official.
    setLevel = {
        probe = function() return fnExists(Game, 'SetLevel') end,
        run   = function(n) return pcall(function() Game.SetLevel('Level', n, 1) end) end,
        needs = 'Game.SetLevel',
    },
    -- Game.SetAttribute and Game.GiveDevPoints were BOTH renamed at patch 2.0.
    -- This is the current form, straight off the wiki.
    devPoints = {
        probe = function()
            return hasGlobal('PlayerDevelopmentSystem') and hasGlobal('gamedataDevelopmentPointType')
               and fnExists(Game, 'GetPlayer')
        end,
        -- Asking for 5 in one call lands 1, so ask for 1 five times and count
        -- what actually went through. Returns how many, not just whether it ran.
        run = function(n, kind)
            local given = 0
            for _ = 1, n do
                local ok = pcall(function()
                    local pl = Game.GetPlayer()
                    PlayerDevelopmentSystem.GetInstance(pl):GetDevelopmentData(pl)
                        :AddDevelopmentPoints(1, gamedataDevelopmentPointType[kind])
                end)
                if not ok then break end
                given = given + 1
            end
            return given > 0, given
        end,
        needs = 'PlayerDevelopmentSystem + gamedataDevelopmentPointType',
    },
    -- The vehicle system answered true on this install. The unlock method name
    -- is not in any documentation I could find, so it is discovered rather than
    -- assumed: if it is absent the Browse tab says so instead of throwing.
    vehicle = {
        probe = function()
            if not fnExists(Game, 'GetVehicleSystem') then return false end
            local vs; pcall(function() vs = Game.GetVehicleSystem() end)
            return fnExists(vs, 'EnablePlayerVehicle')
        end,
        -- EnablePlayerVehicle RETURNS a bool. The first version of this threw
        -- the return away and reported pcall's success instead, so a call that
        -- the game refused still printed OK. Capture both now: `ok` is "did it
        -- raise", `res` is "did the game accept it".
        run = function(id, makeActive)
            local ok, res = pcall(function()
                return Game.GetVehicleSystem():EnablePlayerVehicle(id, true, makeActive and true or false)
            end)
            return ok, res
        end,
        canSpawn = function()
            local vs; pcall(function() vs = Game.GetVehicleSystem() end)
            return fnExists(vs, 'SpawnPlayerVehicle')
        end,
        spawn = function(id)
            local vs; pcall(function() vs = Game.GetVehicleSystem() end)
            if not fnExists(vs, 'SpawnPlayerVehicle') then
                return false, 'SpawnPlayerVehicle does not exist on this build'
            end
            local ok, res = pcall(function() return vs:SpawnPlayerVehicle(id) end)
            return ok, res
        end,
        needs = 'VehicleSystem:EnablePlayerVehicle',
    },
}

-- Some records ignore the quantity argument entirely and hand over exactly one
-- no matter what you ask for. Skillbooks are the obvious case: asking for five
-- perk points gives one. For those, call once per unit instead, which is the
-- same workaround people end up typing by hand as a for loop in the console.
local function giveItem(id, qty, loop)
    if not state.records[id] and not recordExists(id) then
        return false, 'TweakDB has no record "' .. id .. '" on this build'
    end
    if loop then
        local given = 0
        for _ = 1, qty do
            if not pcall(function() Game.AddToInventory(id, 1) end) then break end
            given = given + 1
        end
        if given == 0 then return false, 'nothing was added for ' .. id end
        return true, string.format('gave %s x %s, one call each because this item ignores quantity', comma(given), id)
    end
    local ok, err = pcall(function() Game.AddToInventory(id, qty) end)
    if not ok then return false, tostring(err) end
    return true, string.format('gave %s x %s', comma(qty), id)
end

local function setFactLogged(name, value)
    if not api.setFact then return false, 'no SetFactStr on this build' end
    local prev
    if api.getFact then
        local ok, v = pcall(function() return api.getFact(name) end)
        if ok then prev = v end
    end
    local ok, err = pcall(function() api.setFact(name, value) end)
    if not ok then return false, tostring(err) end
    table.insert(state.undo, 1, { fact = name, prev = prev, new = value, at = now() })
    return true, string.format('%s: %s -> %s', name, tostring(prev), tostring(value))
end

-- ---------------------------------------------------------------------------
-- Identifying a journal entry well enough to block it.
--
-- Not by hash alone. GetEntryHash reads 0 for a top-level quest on this build
-- -- that is exactly why the old watch card showed a useless 0 -- and a key of
-- 0 would match everything or nothing depending on which way you squint. So
-- try the accessors in order, reject an answer that is empty or zero, and
-- record which one actually answered, the same way the record browser does
-- rather than assuming one and silently matching nothing.
-- ---------------------------------------------------------------------------
local ENTRY_KEYS = {
    { 'GetId()',        function(e) return e:GetId() end },
    { 'GetPath()',      function(e) return e:GetPath() end },
    { 'GetEntryHash()', function(e) return api.journal:GetEntryHash(e) end },
    -- Last resort. A displayed title is localised and is not an id, but it is
    -- unique enough to block one quest by and it is the one thing a journal
    -- entry will always give you. Better than a feature that cannot run.
    { 'GetTitle()',     function(e) return e:GetTitle(api.journal) end },
}

local function entryKey(e)
    if e == nil then return nil end
    for i, a in ipairs(ENTRY_KEYS) do
        local ok, v = pcall(a[2], e)
        if ok and v ~= nil then
            local s = tostring(v)
            if s ~= '' and s ~= '0' and s ~= 'nil' then
                state.guard.keySrc = ENTRY_KEYS[i][1]
                return s, i
            end
        end
    end
    return nil
end

-- A readable label for a blocked quest. The key may be a hash, which tells a
-- player nothing, so keep whatever the entry can give us alongside it.
local function entryLabel(e)
    for _, getter in ipairs({
        function() return e:GetTitle(api.journal) end,
        function() return e:GetId() end,
        function() return e:GetPath() end,
    }) do
        local ok, v = pcall(getter)
        if ok and v ~= nil and tostring(v) ~= '' then return tostring(v) end
    end
    return nil
end

-- Every node from the tracked entry up to the top, kept rather than walked
-- past.
local function trackedChain()
    if not api.journalOk then return nil, 'journal API unavailable' end
    local ok, tracked = pcall(function() return api.journal:GetTrackedEntry() end)
    if not ok or tracked == nil then return nil, 'nothing is being tracked' end
    local chain, node = { tracked }, tracked
    for _ = 1, 12 do
        local ok2, parent = pcall(function() return api.journal:GetParentEntry(node) end)
        if not ok2 or parent == nil then break end
        chain[#chain + 1] = parent
        node = parent
    end
    return chain
end

-- The quest, meaning the outermost node that can still say what it is.
--
-- The old version walked until GetParentEntry returned nil and used whatever
-- it landed on. That is the journal ROOT, not the quest. The root has no id
-- and hashes to zero, which is exactly why the tracked quest has been
-- displaying "hash: 0" since the day that line was written, and why Block
-- could not read an id for it: it was asking a container for its name.
--
-- Seven parents deep says the same thing. A quest is not seven levels above
-- its own objective.
--
-- So: take the chain, start at the top, and use the first node that gives a
-- usable key. The root falls out on its own because it cannot name itself,
-- and nothing here has to know the class names of a journal tree.
local function resolveTrackedQuest()
    local chain, err = trackedChain()
    if not chain then return nil, err, 0 end
    for i = #chain, 1, -1 do
        local key, which = entryKey(chain[i])
        if key then return chain[i], nil, i - 1, key, which end
    end
    return nil, ('nothing in the tracked chain of %d could identify itself'):format(#chain), 0
end

-- forceCompleteTracked was removed with the button that called it.


local function saveBlocked()
    pcall(function()
        local f = io.open('blocked.txt', 'w')
        if not f then return end
        for _, b in ipairs(state.guard.list) do
            f:write(b.key .. '\t' .. (b.label or '') .. '\n')
        end
        f:write('#on\t' .. tostring(state.guard.on) .. '\n')
        f:close()
    end)
end

local function loadBlocked()
    pcall(function()
        local f = io.open('blocked.txt', 'r')
        if not f then return end
        for line in f:lines() do
            local key, label = line:match('^([^\t]*)\t?(.*)$')
            if key == '#on' then
                state.guard.on = (label == 'true')
            elseif key and #key > 0 then
                state.guard.list[#state.guard.list + 1] = { key = key, label = label }
            end
        end
        f:close()
    end)
end

local function isBlocked(key)
    if key == nil then return false end
    for _, b in ipairs(state.guard.list) do
        if b.key == key then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The guard itself, run from onUpdate because the theft happens while you are
-- playing with no overlay open, which is precisely when onDraw is not running.
--
-- It does not touch quest state. TrackEntry moves which quest the HUD points
-- at and nothing else, so the worst case is the marker going to the wrong
-- place, and the fix is to track something in the journal yourself.
-- ---------------------------------------------------------------------------
local function guardTick(dt)
    local g = state.guard
    if not g.on or #g.list == 0 then return end
    if not (api.journalOk and api.trackOk) then return end

    -- Four times a second. The journal is not worth a per-frame walk, and the
    -- hand-over is not something a player can perceive inside 250ms.
    g.at = g.at + (dt or 0)
    if g.at < 0.25 then return end
    g.at = 0

    local ok, tracked = pcall(function() return api.journal:GetTrackedEntry() end)
    if not ok or tracked == nil then return end

    -- Match on the quest, not on the objective, because the game tracks an
    -- objective inside the quest and that is a different entry. Same
    -- resolution the Block button uses, so what you blocked is what is
    -- matched.
    local node = resolveTrackedQuest()
    if node == nil then return end

    if not isBlocked(entryKey(node)) then
        -- Whatever you were tracking when nothing was wrong is where focus
        -- goes back to. Captured here rather than asked for, so the guard
        -- needs no setup beyond naming the quest to block.
        g.lastGood = tracked
        return
    end

    if g.lastGood == nil then
        g.err = 'blocked quest is tracked, but nothing else has been tracked yet this session'
        return
    end

    local put = pcall(function() api.journal:TrackEntry(g.lastGood) end)
    if put then
        g.hits = g.hits + 1
        g.err = nil
    else
        -- A handle kept across frames can go stale. Rather than retry four
        -- times a second forever, stop and say so.
        g.fails = g.fails + 1
        if g.fails >= 5 then
            g.on = false
            g.err = 'TrackEntry failed five times, so the guard switched itself off'
            note('guard off: %s', g.err)
        end
    end
end

-- ===========================================================================
-- small ImGui helpers
-- ===========================================================================

local function textc(col, s)
    if caps.TextColored then ImGui.TextColored(col[1], col[2], col[3], col[4], tostring(s))
    else ImGui.Text(tostring(s)) end
end

local function wrapped(s)
    if caps.TextWrapped then ImGui.TextWrapped(tostring(s)) else ImGui.Text(tostring(s)) end
end

local function sep() if caps.Separator then ImGui.Separator() end end
local function same() if caps.SameLine then ImGui.SameLine() end end
-- Glyphs are not all the same advance width, so a label placed with a plain
-- SameLine starts at a different x on every row. An absolute offset puts them
-- all in one column.
--
-- But an absolute offset was measured against a wide window, and ImGui does
-- not push back: narrow the pane and a column at x=430 puts its content past
-- the right edge, where there is no horizontal scrollbar to go and find it. So
-- every column is clamped into the width that actually exists, leaving room
-- for whatever is about to be drawn at it. Columns collapse on a narrow
-- window instead of content disappearing off the side of it.
local function sameAt(x, keep)
    if not caps.SameLine then return end
    pcall(function()
        if caps.GetContentRegionAvail then
            local avail = ImGui.GetContentRegionAvail()
            if avail and avail > 0 then
                local maxX = avail - (keep or 90)
                if maxX < 30 then maxX = 30 end
                if x > maxX then x = maxX end
            end
        end
        ImGui.SameLine(x)
    end)
end

-- ---------------------------------------------------------------------------
-- Night City palette. ImGui's default is a grey system dialog, which looks
-- pasted on top of the game. Yellow on near-black, square corners, hard
-- borders.
--
-- Every push is counted and only counted when it succeeds, because ImGui pops
-- by COUNT. One enum member missing on a build, pushed blind, and every colour
-- after it shifts by one slot. So: look the member up first, push second,
-- count third.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Palettes. Night City is not one colour: the corpo districts are steel blue,
-- Arasaka is crimson, the netrunner screens are cyan and magenta, and Samurai
-- is the yellow. Each theme is a primary and a secondary; every other colour
-- in the window is derived from them, so adding a palette means two colours,
-- not thirty.
--
-- The default is a slightly deepened amber rather than full #FCEE0A, which
-- reads as a highlighter across a large filled bar.
-- ---------------------------------------------------------------------------
-- Three colours per palette, not two: an accent, a secondary, and the base the
-- whole window is built out of. The base is the one that was missing. Every
-- palette used to share one hardcoded charcoal body, so switching from Arasaka
-- to Netrunner recoloured the buttons and left the room identical. Now Arasaka
-- is a red-black room and Netrunner is an indigo one.
local THEMES = {
    { name = 'Samurai',   note = 'Chrome yellow on tar. The band on the jacket.',
      a = { 0.94, 0.82, 0.10 }, b = { 0.12, 0.80, 0.88 }, bg = { 0.042, 0.038, 0.026 } },
    { name = 'Arasaka',   note = 'Corporate black with one red stripe through it.',
      a = { 0.86, 0.13, 0.25 }, b = { 0.80, 0.82, 0.86 }, bg = { 0.054, 0.020, 0.024 } },
    { name = 'Militech',  note = 'Steel blue and gold. Military surplus.',
      a = { 0.26, 0.56, 0.92 }, b = { 0.96, 0.70, 0.20 }, bg = { 0.022, 0.034, 0.058 } },
    { name = 'Netrunner', note = 'Cyan and magenta, straight off a braindance deck.',
      a = { 0.10, 0.86, 0.94 }, b = { 0.96, 0.20, 0.62 }, bg = { 0.026, 0.028, 0.056 } },
    { name = 'Voodoo',    note = 'Pacifica. Jungle green under wet neon.',
      a = { 0.22, 0.86, 0.52 }, b = { 0.88, 0.26, 0.76 }, bg = { 0.018, 0.040, 0.032 } },
    { name = 'Nomad',     note = 'Badlands dust and rust. Warmer than the city.',
      a = { 0.94, 0.56, 0.20 }, b = { 0.80, 0.72, 0.52 }, bg = { 0.056, 0.038, 0.024 } },
    { name = 'Kang Tao',  note = 'Jade and brass.',
      a = { 0.28, 0.80, 0.50 }, b = { 0.88, 0.82, 0.32 }, bg = { 0.024, 0.038, 0.028 } },
    { name = 'Trauma',    note = 'Emergency white, alert red. Loud on purpose.',
      a = { 0.90, 0.92, 0.94 }, b = { 0.94, 0.18, 0.24 }, bg = { 0.046, 0.048, 0.056 } },
    { name = 'Corpo',     note = 'Plaza daylight. The only bright one.',
      a = { 0.09, 0.30, 0.56 }, b = { 0.74, 0.40, 0.08 }, bg = { 0.87, 0.88, 0.90 },
      light = true },
}

local function theme() return THEMES[state.theme] or THEMES[1] end
local function A() return theme().a end
local function B() return theme().b end

-- Text drawn on top of a filled block gets its colour CHOSEN for contrast
-- rather than assumed dark. The banner used to paint near-black letters on
-- whatever the accent happened to be: fine on Samurai yellow, close to
-- illegible on Arasaka red.
--
-- The choice is measured, not guessed from a brightness threshold. A plain
-- 0.299/0.587/0.114 average put Militech's blue just under the cut and so
-- picked white at 3.1:1, where black on the same blue gives 6.0:1. So:
-- WCAG relative luminance, sRGB linearised, and take whichever of the two
-- inks actually wins on this colour.
local function lin(v)
    if v <= 0.03928 then return v / 12.92 end
    return ((v + 0.055) / 1.055) ^ 2.4
end

local function relLum(c)
    return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end

local function contrast(f, b)
    local l1, l2 = relLum(f), relLum(b)
    if l2 > l1 then l1, l2 = l2, l1 end
    return (l1 + 0.05) / (l2 + 0.05)
end

local INK_DARK, INK_LIGHT = { 0.04, 0.04, 0.05 }, { 0.97, 0.97, 0.95 }
local function onCol(c)
    if contrast(INK_DARK, c) >= contrast(INK_LIGHT, c) then return INK_DARK end
    return INK_LIGHT
end

local function mix(c1, c2, t)
    return { c1[1] + (c2[1] - c1[1]) * t,
             c1[2] + (c2[2] - c1[2]) * t,
             c1[3] + (c2[3] - c1[3]) * t }
end

local function rgba(c, al) return { c[1], c[2], c[3], al or 1.0 } end

-- Every surface in the window comes from this: the palette's own base, lifted
-- toward white on a dark theme or pressed toward black on a light one, and
-- optionally leaned toward the accent. One function, so a new palette is still
-- three colours and not thirty.
local function surf(t, lean)
    local th = theme()
    local c = mix(th.bg, th.light and { 0, 0, 0 } or { 1, 1, 1 }, t)
    if lean and lean > 0 then c = mix(c, th.a, lean) end
    return c
end

local function txtCol()
    return theme().light and { 0.10, 0.11, 0.13 } or { 0.91, 0.91, 0.88 }
end

-- Green means good and red means bad on every palette, so these are not
-- themed. They are kept here, apart from COL, because COL is rebuilt from the
-- palette every frame and would otherwise darken its own darkening.
local SEM = {
    ok   = { 0.36, 0.92, 0.55 },
    warn = { 1.00, 0.78, 0.20 },
    bad  = { 1.00, 0.24, 0.35 },
}

-- Floats to ImGui's packed 0xAABBGGRR, which is byte order, not RGB.
local function pack(c, alpha)
    local r = math.floor(c[1] * 255 + 0.5)
    local g = math.floor(c[2] * 255 + 0.5)
    local bl = math.floor(c[3] * 255 + 0.5)
    local al = math.floor((alpha or 1) * 255 + 0.5)
    return al * 16777216 + bl * 65536 + g * 256 + r
end

local function mul(c, f) return { c[1] * f, c[2] * f, c[3] * f } end

-- The choice outlives a reload, stored beside the mod -- as the palette's
-- NAME, not its index. The file used to hold a number, which meant inserting a
-- palette moved anyone who had saved one onto a different theme without
-- telling them. A bare number still loads, for a theme.txt written by 1.0.
local function saveTheme()
    pcall(function()
        local f = io.open('theme.txt', 'w')
        if f then f:write(theme().name); f:close() end
    end)
end

local function loadTheme()
    local ok, s = pcall(function()
        local f = io.open('theme.txt', 'r')
        if not f then return nil end
        local v = f:read('*a'); f:close()
        return v
    end)
    if not ok or not s then return end
    s = tostring(s):match('^%s*(.-)%s*$')
    local n = tonumber(s)
    if n and THEMES[n] then state.theme = n; return end
    for i = 1, #THEMES do
        if THEMES[i].name == s then state.theme = i; return end
    end
end

local themeStack = { cols = 0, vars = 0 }

local function pushTheme()
    themeStack.cols, themeStack.vars = 0, 0
    local P, S = A(), B()
    if caps.style then
        local function pc(name, c, al)
            local idx
            if not pcall(function() idx = ImGuiCol[name] end) or idx == nil then return end
            if pcall(function() ImGui.PushStyleColor(idx, c[1], c[2], c[3], al or 1.0) end) then
                themeStack.cols = themeStack.cols + 1
            end
        end
        local th, TXT = theme(), txtCol()
        pc('WindowBg',             surf(0.000), 0.97)
        pc('ChildBg',              surf(0.030))
        pc('PopupBg',              surf(0.040), 0.98)
        pc('Border',               P, 0.45)
        pc('Text',                 TXT)
        pc('TextDisabled',         mix(TXT, th.bg, 0.55))
        pc('TextSelectedBg',       P, 0.35)
        pc('TitleBg',              surf(0.015))
        pc('TitleBgActive',        surf(0.050, 0.32))
        pc('FrameBg',              surf(0.065))
        pc('FrameBgHovered',       surf(0.090, 0.24))
        pc('FrameBgActive',        surf(0.130, 0.34))
        pc('Button',               surf(0.085))
        pc('ButtonHovered',        surf(0.110, 0.36))
        pc('ButtonActive',         surf(0.150, 0.58))
        pc('CheckMark',            P)
        pc('SliderGrab',           mul(P, 0.85))
        pc('SliderGrabActive',     P)
        pc('Separator',            P, 0.28)
        pc('SeparatorHovered',     P, 0.60)
        pc('Tab',                  surf(0.055))
        pc('TabHovered',           surf(0.100, 0.36))
        pc('TabActive',            surf(0.130, 0.50))
        pc('Header',               surf(0.060, 0.22))
        pc('HeaderHovered',        surf(0.100, 0.36))
        pc('HeaderActive',         surf(0.140, 0.48))
        pc('ScrollbarBg',          surf(0.012))
        pc('ScrollbarGrab',        surf(0.080, 0.30))
        pc('ScrollbarGrabHovered', surf(0.120, 0.45))
        pc('NavHighlight',         P, 0.50)
    end
    if caps.stylevar then
        local function pv(name, x, y)
            local idx
            if not pcall(function() idx = ImGuiStyleVar[name] end) or idx == nil then return end
            local ok = pcall(function()
                if y then ImGui.PushStyleVar(idx, x, y) else ImGui.PushStyleVar(idx, x) end
            end)
            if ok then themeStack.vars = themeStack.vars + 1 end
        end
        pv('WindowRounding', 0.0); pv('FrameRounding', 0.0); pv('TabRounding', 0.0)
        pv('GrabRounding', 0.0);   pv('ScrollbarRounding', 0.0)
        pv('WindowBorderSize', 1.0); pv('FrameBorderSize', 1.0)
        pv('FramePadding', 7.0, 4.0); pv('ItemSpacing', 8.0, 6.0)
    end
    -- COL is what every textc() call in the file reads, so it is rebuilt from
    -- the live palette here rather than staying the fixed set it was before.
    -- dim is tinted toward the base so grey text sits IN the window instead of
    -- floating on it, and the semantic colours are darkened on a light palette
    -- because full-saturation green on near-white cannot be read.
    local TXT = txtCol()
    local function sem(c) return rgba(theme().light and mul(c, 0.58) or c) end
    COL.accent = rgba(P)
    COL.cyan   = rgba(S)
    COL.dim    = rgba(mix(TXT, theme().bg, 0.42))
    COL.ok, COL.warn, COL.bad = sem(SEM.ok), sem(SEM.warn), sem(SEM.bad)
end

local function popTheme()
    if themeStack.vars > 0 then pcall(function() ImGui.PopStyleVar(themeStack.vars) end) end
    if themeStack.cols > 0 then pcall(function() ImGui.PopStyleColor(themeStack.cols) end) end
    themeStack.cols, themeStack.vars = 0, 0
end

-- A solid colour bar with centred dark text. Built from a styled Button
-- because that is the one widget guaranteed on every build to paint a filled
-- block the full width of the pane; a draw-list call would look better still
-- but is not something I can verify exists here.
local function bar(label, r, g, b, h)
    if not (caps.PushStyleColor and caps.PopStyleColor) then
        textc(COL.accent, label); return
    end
    local pushed = 0
    local function pc(n, rr, gg, bb, aa)
        local idx
        if not pcall(function() idx = ImGuiCol[n] end) or idx == nil then return end
        if pcall(function() ImGui.PushStyleColor(idx, rr, gg, bb, aa) end) then
            pushed = pushed + 1
        end
    end
    pc('Button',        r, g, b, 1.0)
    pc('ButtonHovered', r, g, b, 1.0)
    pc('ButtonActive',  r, g, b, 1.0)
    local ink = onCol({ r, g, b })
    pc('Text',          ink[1], ink[2], ink[3], 1.0)
    pcall(function() ImGui.Button(label, -1, h or 26) end)
    if pushed > 0 then pcall(function() ImGui.PopStyleColor(pushed) end) end
end

-- ---------------------------------------------------------------------------
-- The banner, drawn rather than laid out. ImGui gives one font at one size and
-- no images, so the only route to something that looks designed is the draw
-- list: real polygons, an angled cut, hazard stripes and a rule under it.
--
-- Colours are packed 0xAABBGGRR, which is ImGui's byte order and NOT RGB.
-- Everything is attempted once inside a single pcall; if any call is missing
-- on this build the whole thing is marked unavailable for the session and the
-- flat bar takes over, so a half-drawn banner is impossible.
-- ---------------------------------------------------------------------------
local function drawnBanner()
    if state.fancy == false then return false end
    if not (caps.GetWindowDrawList and caps.GetCursorScreenPos
            and caps.GetContentRegionAvail and caps.Dummy) then
        state.fancy = false; return false
    end
    local ok = pcall(function()
        local x, y = ImGui.GetCursorScreenPos()
        local w    = ImGui.GetContentRegionAvail()
        local dl   = ImGui.GetWindowDrawList()
        local th = theme()
        local h, cut = 44, 22
        local P, S = A(), B()
        local YEL, CYN, DIM = pack(P), pack(S), pack(S, 0.20)
        local INK = pack(onCol(P))
        local barW = math.max(210, w * 0.62)

        -- The accent block, graded dark-to-light across its width instead of
        -- being one flat fill, which was the flattest thing in the window.
        -- AddRectFilledMultiColor would do this in a single call but is not
        -- bound on every CET build, so it is banded by hand out of
        -- AddRectFilled, which this file has already proven exists here.
        local bands = 16
        for i = 0, bands - 1 do
            local t0 = i / bands
            dl:AddRectFilled(x + barW * t0, y,
                x + barW * ((i + 1) / bands) + 1, y + h,
                pack(mix(mul(P, 0.68), P, t0)))
        end
        dl:AddTriangleFilled(x + barW, y, x + barW + cut, y, x + barW, y + h, YEL)
        -- a lit hairline along the top edge, the way a panel catches a light
        dl:AddRectFilled(x, y, x + barW + cut, y + 2, pack(mix(P, { 1, 1, 1 }, 0.45)))

        -- Scanlines across the block: one dark line every third row at very low
        -- alpha. Close up it is texture, at a glance it is a CRT. The line
        -- shortens as it descends so it follows the slant instead of
        -- overhanging it.
        local sy = y + 3
        while sy < y + h - 1 do
            dl:AddLine(x, sy, x + barW + cut * ((y + h - sy) / h), sy,
                pack({ 0, 0, 0 }, 0.10), 1.0)
            sy = sy + 3
        end

        -- hazard stripes filling the gap to the right of the slant
        local sx = x + barW + cut + 6
        while sx < x + w - 10 do
            dl:AddLine(sx, y + h - 4, sx + 12, y + 6, DIM, 2.0)
            sx = sx + 9
        end

        -- rule under the whole header, plus a bright tick at the left
        dl:AddRectFilled(x, y + h + 3, x + w, y + h + 5, CYN)
        dl:AddRectFilled(x, y + h + 3, x + 46, y + h + 5, YEL)

        -- The title sits on the accent block, so its colour is whichever of
        -- black or white survives there, not black on principle.
        dl:AddText(x + 16, y + 13, INK, 'M I K O S H I')
        dl:AddText(x + barW + cut + 14, y + 13, CYN, 'NIGHT CITY TOOLKIT')
        -- the live palette, named on screen rather than only in Diagnostics
        local tw = (ImGui.CalcTextSize and select(1, ImGui.CalcTextSize(th.name)))
                   or (#th.name * 7)
        dl:AddText(x + w - tw - 4, y + h - 15, pack(S, 0.55), th.name)

        ImGui.Dummy(w, h + 10)
    end)
    if not ok then state.fancy = false end
    return ok
end

local function banner()
    if not drawnBanner() then
        -- Fallback: one font at one size, so scale it for the title line only.
        local scaled = caps.SetWindowFontScale and pcall(function() ImGui.SetWindowFontScale(1.45) end)
        bar('M I K O S H I', A()[1], A()[2], A()[3], scaled and 38 or 30)
        if scaled then pcall(function() ImGui.SetWindowFontScale(1.0) end) end
        textc(COL.accent, ic('ChevronRight') .. 'NIGHT CITY TOOLKIT')
    end
    textc(COL.cyan, string.format('%sv%s   %sgame 2.5   %sCET 1.38.1   %s%d/%d ids verified',
        ic('Wrench'), VERSION, ic('Gamepad'), ic('Chip'), ic('CheckCircle'),
        state.idsFound or 0, state.idsChecked or 0))
end

-- Colour the status strip by what actually happened, so a refusal is visible
-- without reading the sentence.
local function statusStrip()
    local last = state.log[1] or 'ready'
    local col = COL.dim
    if     last:find('OK') then col = COL.ok
    elseif last:find('FAIL') or last:find('ERROR') then col = COL.bad
    elseif last:find('REFUSED') or last:find('NO ANSWER') then col = COL.warn end
    textc(col, last)
end

-- ---------------------------------------------------------------------------
-- A filled block of colour WITHOUT the draw list.
--
-- CET 1.38.1 does not bind ImGui's draw list, so every AddRectFilled in this
-- file is dead on a real install and the window falls back to grey separators.
-- ProgressBar is the one widget that paints a filled rectangle of arbitrary
-- height, so a bar at 100% with its fill pushed to the accent IS a rule, and
-- the overlay string is emptied so it does not print "100%" across it.
-- ---------------------------------------------------------------------------
local function colourBar(c, w, h)
    if not (caps.ProgressBar and caps.PushStyleColor and caps.PopStyleColor) then
        return false
    end
    local pushed = 0
    local function pc(n, col, al)
        local idx
        if not pcall(function() idx = ImGuiCol[n] end) or idx == nil then return end
        if pcall(function() ImGui.PushStyleColor(idx, col[1], col[2], col[3], al or 1.0) end) then
            pushed = pushed + 1
        end
    end
    pc('PlotHistogram', c)
    pc('FrameBg', c, 0.0)
    local ok = pcall(function() ImGui.ProgressBar(1.0, w or -1, h or 3, '') end)
    if not ok then
        ok = pcall(function() ImGui.ProgressBar(1.0, w or -1, h or 3) end)
    end
    if pushed > 0 then pcall(function() ImGui.PopStyleColor(pushed) end) end
    return ok
end

-- Which sections are folded outlives a reload, beside the theme and the watch
-- list. Only the CLOSED ones are written: open is the default, so the file
-- stays empty until you actually fold something.
local function saveFolds()
    pcall(function()
        local f = io.open('folds.txt', 'w')
        if not f then return end
        for k, v in pairs(state.folds) do
            if v == false then f:write(k .. '\n') end
        end
        f:close()
    end)
end

local function loadFolds()
    pcall(function()
        local f = io.open('folds.txt', 'r')
        if not f then return end
        for line in f:lines() do
            local k = line:match('^%s*(.-)%s*$')
            if k and #k > 0 then state.folds[k] = false end
        end
        f:close()
    end)
end

-- A thin accent rule, drawn where the draw list exists. Section headers get a
-- hairline instead of relying on ImGui's own grey separator.
local function accentRule(alpha)
    if state.fancy == false then return false end
    local ok = pcall(function()
        local x, y = ImGui.GetCursorScreenPos()
        local w    = ImGui.GetContentRegionAvail()
        local dl   = ImGui.GetWindowDrawList()
        dl:AddRectFilled(x, y + 2, x + w, y + 3, alpha or pack(B(), 0.27))
        dl:AddRectFilled(x, y + 2, x + 28, y + 3, pack(A()))
        ImGui.Dummy(w, 6)
    end)
    return ok
end

-- A section folds, and returns whether it is open so the tab can skip its
-- body. A category runs to thirty rows and most of the time you want one of
-- them.
--
-- The header is a Button, not an ImGui CollapsingHeader. CollapsingHeader
-- cannot default to open without ImGuiTreeNodeFlags, and this file has already
-- been caught assuming a CET binding exists -- the entire draw list turned out
-- not to be bound. A Button is bound everywhere, defaults however we like, and
-- can be painted in the palette like the rest of the window.
local function section(title, icon)
    local open = state.folds[title]
    if open == nil then open = true end

    local marker
    if Icons and state.icons ~= false then
        marker = ic(open and 'ChevronDown' or 'ChevronRight')
    else
        marker = open and '[-] ' or '[+] '
    end
    local label = marker .. (icon and ic(icon) or '') .. string.upper(title)

    local pushed = 0
    if caps.style then
        local function pc(n, c, al)
            local idx
            if not pcall(function() idx = ImGuiCol[n] end) or idx == nil then return end
            if pcall(function() ImGui.PushStyleColor(idx, c[1], c[2], c[3], al or 1.0) end) then
                pushed = pushed + 1
            end
        end
        -- Transparent fill, so it still reads as a heading and not as one more
        -- button in a window already full of them. It lights up on hover,
        -- which is the only hint it needs that it can be clicked.
        pc('Button',        surf(0.03), 0.0)
        pc('ButtonHovered', surf(0.10, 0.30))
        pc('ButtonActive',  surf(0.14, 0.45))
        pc('Text',          COL.accent)
    end
    local hit = false
    pcall(function() hit = ImGui.Button(label .. '##sec_' .. title, -1, 0) end)
    if pushed > 0 then pcall(function() ImGui.PopStyleColor(pushed) end) end

    if hit then
        open = not open
        state.folds[title] = open
        saveFolds()
    end
    if not open then return false end

    if accentRule() then return true end
    -- No draw list, which is the normal case on CET. Two coloured segments
    -- still read as a rule, where ImGui's grey Separator reads as nothing.
    if colourBar(A(), 46, 3) then
        same()
        colourBar(B(), -1, 3)
        return true
    end
    if caps.SeparatorText then pcall(function() ImGui.Separator() end) end
    return true
end


local function amountBox(key, default, step)
    if state.amounts[key] == nil then state.amounts[key] = default or 1 end
    local v = state.amounts[key]
    if caps.InputInt then
        -- InputInt puts its own minus and plus INSIDE the item width, so the
        -- typing area is the width given minus two buttons. 118 was cutting
        -- five-figure numbers in half. Size it to the digits actually there.
        if caps.SetNextItemWidth then
            local digits = #tostring(math.floor(math.abs(v))) 
            local w = 150 + math.max(0, digits - 3) * 14
            pcall(function() ImGui.SetNextItemWidth(math.min(w, 260)) end)
        end
        local nv = ImGui.InputInt('##amt' .. key, v, step or 1)
        if type(nv) == 'number' then state.amounts[key] = math.max(0, nv) end
    else
        ImGui.Text(tostring(v))
        same()
        if ImGui.Button('-##' .. key) then
            state.amounts[key] = math.max(0, v - (step or 1))
        end
        same()
        if ImGui.Button('+##' .. key) then
            state.amounts[key] = v + (step or 1)
        end
    end
    -- The grouped form sits beside the box, where it is readable without
    -- interfering with typing.
    if state.amounts[key] >= 1000 then
        same(); textc(COL.dim, comma(state.amounts[key]))
    end
    return state.amounts[key]
end

-- ---------------------------------------------------------------------------
-- Compact presentation. The old rows carried a title, a text badge, a note, a
-- description and a separator each, which is documentation, not a HUD. A row
-- is now one line: status glyph, name, controls. Everything that used to be
-- prose lives behind a small ? you hover.
-- ---------------------------------------------------------------------------
local function glyph(name, fallback)
    if Icons and Icons[name] then return Icons[name] end
    return fallback or ''
end

local function statusIcon(kind)
    if kind == 'ok' then
        textc(COL.ok, glyph('CheckCircle', '[ok]'))
    elseif kind == 'warn' then
        textc(COL.warn, glyph('AlertCircle', '[?]'))
    else
        textc(COL.bad, glyph('CloseCircle', '[x]'))
    end
end

-- A hoverable ? rather than a paragraph nobody reads twice.
local function hint(text)
    if not text or text == '' then return end
    same()
    textc(COL.dim, glyph('HelpCircleOutline', '(?)'))
    if ImGui.IsItemHovered then
        pcall(function()
            if ImGui.IsItemHovered() then ImGui.SetTooltip(text) end
        end)
    end
end

-- A row that can only fire when its id is real.
-- Is one of these strings already saying what the other says? Used to decide
-- whether the in-game name adds anything to a row, so "Eddies [Eddies]" never
-- happens.
local function sameish(a, b)
    a, b = tostring(a):lower(), tostring(b):lower()
    if #a < 3 or #b < 3 then return a == b end
    return a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

local function grantRow(key, label, record, default, step, noteText, loop)
    local present = state.records[record]
    if present == nil then present = recordExists(record); state.records[record] = present end

    statusIcon(present and 'ok' or 'bad')
    sameAt(30); ImGui.Text(label)
    -- What the game will actually call this when it lands in your inventory.
    -- The catalogue label says what a row is FOR; this says what it IS, and it
    -- is the only way to tell FirstAidWhiffV1 from FirstAidWhiffV2 without
    -- giving one and going to look. Read from TweakDB and cached, so it costs
    -- a table lookup after the first frame.
    if present then
        local real = describe(record).name
        if real and not sameish(real, label) then
            same(); textc(COL.cyan, '[' .. real .. ']')
        end
    end
    if noteText then hint(noteText) end
    if not present then hint("Not in this build's TweakDB: " .. record) end

    same()
    local qty = amountBox(key, default, step)
    same()
    if present then
        if ImGui.Button(glyph('Download', '') .. ' Give##' .. key) then
            local ok, msg = giveItem(record, qty, loop)
            note((ok and 'OK  ' or 'FAIL ') .. msg)
        end
    else
        textc(COL.dim, 'unavailable')
    end
end

-- ===========================================================================
-- tabs
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- The watch list, which is what the pinned card is for.
--
-- Diagnosing a stuck quest comes down to one question: which fact is not
-- flipping? That cannot be answered from a menu, because the moment that
-- matters is while you are playing, doing the thing the quest wants. So pin
-- the facts you care about, play, and watch them live on the card. A value
-- that changes is highlighted for a few seconds so you catch it mid-fight.
-- ---------------------------------------------------------------------------
local function saveWatch()
    pcall(function()
        local f = io.open('watch.txt', 'w')
        if not f then return end
        for _, n in ipairs(state.watch.list) do f:write(n .. '\n') end
        f:close()
    end)
end

local function loadWatch()
    pcall(function()
        local f = io.open('watch.txt', 'r')
        if not f then return end
        for line in f:lines() do
            local n = line:match('^%s*(.-)%s*$')
            if n and #n > 0 and #state.watch.list < 12 then
                state.watch.list[#state.watch.list + 1] = n
            end
        end
        f:close()
    end)
end

local function addWatch(name)
    if not name or name == '' then return false, 'nothing to add' end
    if #state.watch.list >= 12 then return false, 'the card holds twelve at most' end
    for _, n in ipairs(state.watch.list) do
        if n == name then return false, name .. ' is already watched' end
    end
    state.watch.list[#state.watch.list + 1] = name
    saveWatch()
    return true, 'watching ' .. name
end

local function removeWatch(i)
    table.remove(state.watch.list, i)
    saveWatch()
end

-- Read every watched fact, remembering when each last changed.
local function readWatch()
    local now = 0
    pcall(function() now = os.clock() end)
    local out = {}
    for i, name in ipairs(state.watch.list) do
        local v
        if api.getFact then
            local ok, got = pcall(function() return api.getFact(name) end)
            if ok then v = got end
        end
        local prev = state.watch.prev[name]
        if prev ~= nil and v ~= nil and prev ~= v then
            state.watch.changedAt[name] = now
        end
        state.watch.prev[name] = v
        local at = state.watch.changedAt[name]
        out[i] = { name = name, value = v, fresh = (at ~= nil and (now - at) < 6) }
    end
    return out
end

-- One click to put a fact on the pinned card. Typing its name into
-- Diagnostics was the only way to add one before, which meant the watch list
-- worked only for someone who already knew the fact names: exactly the person
-- who does not need a diagnostic tool. Every fact the menu knows about can now
-- be sent to the card from the row it sits on.
local function watchButton(id, fact)
    if ImGui.Button(ic('Pulse') .. 'Watch##w' .. id) then
        local ok, msg = addWatch(fact)
        note((ok and 'OK  ' or 'FAIL ') .. msg)
    end
    hint('Puts ' .. fact .. ' on the pinned card, so you can watch it while you play. Press your Mikoshi key with the overlay closed to see the card.')
end

local function tabQuestFixes()
    textc(COL.dim, 'Track the broken quest in your journal, then use the tools below.')
    sep()

    local quest, err, depth, qkey = resolveTrackedQuest()
    ImGui.Text('Tracked quest')
    if quest then
        -- The name and the key it is known by. The hash that used to be
        -- printed here was the journal root's, and it was always zero.
        textc(COL.accent, entryLabel(quest) or '(no readable title)')
        textc(COL.dim, string.format('%d parent(s) up, identified by %s',
            depth, state.guard.keySrc or '?'))
        textc(COL.cyan, tostring(qkey))
    else
        textc(COL.warn, err or 'nothing tracked')
    end
    sep()

    if section('stop a quest taking focus', 'PinOff') then
        wrapped('Finishing anything hands the journal back to the main story, which is a problem when the main story is the one quest you are saving for last. A blocked quest cannot hold focus: the moment it takes it, focus goes back to whatever you were tracking before.')
        if not api.trackOk then
            textc(COL.bad, 'gameJournalManager:TrackEntry is not on this build, so focus cannot be handed back')
        else
            local g = state.guard
            g.on = ImGui.Checkbox('guard the tracked quest', g.on)
            same()
            if ImGui.Button('Save##guardsave') then saveBlocked(); note('guard settings saved') end

            -- Blocking by id typed from memory is how three shard ids ended up
            -- wrong in this project. Press it while the quest is tracked and the
            -- game supplies its own name for it.
            if ImGui.Button('Block the quest I am tracking now##guardadd') then
                local q, qerr, _, key = resolveTrackedQuest()
                if q == nil or key == nil then
                    note('FAIL %s', qerr or 'no entry in the tracked chain could identify itself')
                elseif isBlocked(key) then
                    note('that quest is already blocked')
                else
                    g.list[#g.list + 1] = { key = key, label = entryLabel(q) or key }
                    saveBlocked()
                    note('OK  blocked %s', g.list[#g.list].label)
                end
            end
            hint('Track the quest in your journal first, then press this. Mikoshi reads whatever your build calls it rather than guessing an id.')

            if #g.list == 0 then
                textc(COL.dim, 'Nothing blocked. Track Nocturne Op55N1, press the button, then track what you actually want to play.')
            else
                for i = #g.list, 1, -1 do
                    statusIcon(g.on and 'ok' or 'warn')
                    sameAt(30); ImGui.Text(g.list[i].label or g.list[i].key)
                    sameAt(340)
                    if ImGui.Button('Unblock##gub' .. i) then
                        table.remove(g.list, i); saveBlocked()
                    end
                end
                textc(COL.dim, string.format('%s key read via %s. Handed focus back %d time(s) this session.',
                    ic('Key'), g.keySrc or 'not read yet', g.hits))
                if g.err then textc(COL.warn, g.err) end
                if not g.on then
                    textc(COL.warn, 'The guard is off, so these are only remembered, not enforced.')
                end
            end
            textc(COL.dim, 'Tracking only. This moves the marker, it does not touch quest state, and nothing here appears in Undo because there is nothing to undo.')
        end
        sep()

        -- REMOVED: force-complete of the tracked quest. It wrote a journal state
        -- with no previous value to restore, and on this build the enum names did
        -- not resolve, so it fell back to the community's hard-coded 3 and 2. A
        -- wrong number there sets a quest to the wrong state permanently.
        textc(COL.dim, 'Force-complete removed: no undo, and its enum did not resolve on this build.')
        sep()
    end

    if section('known fact fixes', 'Wrench') then
        textc(COL.dim, 'Read before write. A fix already applied on this save cannot be pressed again.')
        textc(COL.dim, ic('Pulse') .. 'Watch puts a fact on the pinned card: press your Mikoshi key with the overlay closed, play, and see whether the game sets it on its own.')
        for i, f in ipairs(data.facts or {}) do
            -- Read the fact first. If it already holds the value this fix writes,
            -- the fix is a no-op on this save, so the button is replaced by a note
            -- rather than left there inviting a pointless write to the Undo log.
            local cur, readOk = nil, false
            if api.getFact then
                local ok, v = pcall(function() return api.getFact(f.fact) end)
                if ok then cur, readOk = v, true end
            end
            local applied = readOk and cur ~= nil and cur == f.value

            statusIcon(applied and 'ok' or (f.verified and 'ok' or 'warn'))
            sameAt(30); ImGui.Text(f.label)
            if f.note then hint(f.note) end

            if applied then
                same(); textc(COL.ok, 'already set to ' .. tostring(f.value) .. ', nothing to do')
            elseif api.setFact then
                if readOk and cur ~= nil then
                    same(); textc(COL.dim, 'currently ' .. tostring(cur))
                end
                if ImGui.Button('Apply##fact' .. i) then
                    local ok, msg = setFactLogged(f.fact, f.value)
                    note((ok and 'OK  ' or 'FAIL ') .. msg)
                end
                same()
                if ImGui.Button('Read##fact' .. i) then
                    note('%s = %s', f.fact, readOk and tostring(cur) or 'read failed')
                end
                same(); watchButton('f' .. i, f.fact)
            else
                textc(COL.bad, 'SetFactStr unavailable on this build, so this one cannot be written')
                -- Watching still works without write access, and read-only is the
                -- case where watching matters most: it is the only way left to see
                -- whether the game is setting the fact on its own.
                watchButton('f' .. i, f.fact)
            end
        end
        sep()

        -- Collapsed by default, and ImGui remembers the open state per window in
        -- its own layout file, so once you have finished the sightings it stays
        -- shut without the mod having to store anything.
        local psyOpen = false
        if caps.CollapsingHeader then
            local ok, open = pcall(function()
                return ImGui.CollapsingHeader(ic('AccountAlert') .. 'CYBERPSYCHO SIGHTINGS  (' ..
                    #(data.cyberpsychos or {}) .. ')')
            end)
            psyOpen = ok and open or false
            if not ok then psyOpen = state.psyShow == true end
        else
            state.psyShow = state.psyShow == true
            if ImGui.Button((state.psyShow and 'Hide' or 'Show') ..
                    ' the 17 cyberpsycho sightings##psytoggle') then
                state.psyShow = not state.psyShow
            end
            psyOpen = state.psyShow
        end

        if psyOpen then
            textc(COL.warn, 'Before anything else: open your shards and read the ones you already hold.')
            hint('A sighting often stays open because a shard you already picked up was never READ. That closes more of these than any command here. The list below is a reference for finding the one you have not done.')
            for i, p in ipairs(data.cyberpsychos or {}) do
                ImGui.Text(p.name)
                sameAt(260); textc(COL.dim, p.district)
                sameAt(470); textc(COL.dim, p.id)
            end
        end
        sep()

        ImGui.Text('Templates')
        for i, t in ipairs(data.templates or {}) do
            ImGui.Text(t.label)
            if t.note then hint(t.note) end
            local built = t.pattern
            for _, fld in ipairs(t.fields or {}) do
                local key = 'tpl' .. i .. fld.key
                state.fields[key] = state.fields[key] or ''
                if caps.InputText then
                    local v = ImGui.InputText(fld.key .. '##' .. key, state.fields[key], 64)
                    if type(v) == 'string' then state.fields[key] = v end
                else
                    ImGui.Text(fld.key .. ': ' .. state.fields[key])
                end
                same(); textc(COL.dim, fld.hint or '')
                built = built:gsub('{' .. fld.key .. '}', state.fields[key])
            end
            textc(COL.dim, 'will set: ' .. built .. ' = ' .. tostring(t.value))
            local complete = not built:find('{')
            if complete and api.setFact then
                if ImGui.Button('Apply##tpl' .. i) then
                    local ok, msg = setFactLogged(built, t.value)
                    note((ok and 'OK  ' or 'FAIL ') .. msg)
                end
            else
                textc(COL.dim, 'fill every field to enable')
            end
            sep()
        end
    end
end

local function tabShards()
    textc(COL.warn, 'Read the shards you already hold first. An unread one you picked up long ago closes more sightings than any button here.')
    wrapped('Shards that fail to spawn on a body. Granting the shard is what unsticks the objective in most reports. Greyed rows are ids this build does not recognise.')
    sep()
    for i, s in ipairs(data.shards or {}) do
        grantRow('shard' .. i, s.label, s.record, 1, 1, s.note)
    end
end

local function tabInventory()
    if section('eddies and points') then
        for i, e in ipairs(data.everyday or {}) do
            grantRow('day' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
        end
    end

    if section('experience') then
        textc(COL.dim, 'These are function calls, not items, so there is no record to pre-check. The value is read before and after instead, and what you get told is the difference.')
        for i, e in ipairs(data.exp or {}) do
            local cur = readAttribute(e.arg)
            ImGui.Text(e.label)
            sameAt(150); textc(cur and COL.cyan or COL.dim,
                               cur and tostring(cur) or 'cannot read this one')
            sameAt(260, 150)
            local qty = amountBox('exp' .. i, e.default, e.step)
            same()
            if ImGui.Button(('Add %d##exp%d'):format(qty, i)) then
                local ok, msg = addExperience(e.arg, qty)
                note((ok and 'OK  ' or 'FAIL ') .. msg)
            end
        end
        sep()
    end

    if section('ammo') then
        for i, e in ipairs(data.ammo or {}) do
            grantRow('ammo' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
        end
    end

    if section('consumables') then
        for i, e in ipairs(data.healing or {}) do
            grantRow('heal' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
        end
    end

    if section('iconics', 'Star') then
        for i, e in ipairs(data.iconics or {}) do
            grantRow('icon' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
        end
    end

    if section('crafting materials') then
        for i, e in ipairs(data.crafting or {}) do
            grantRow('craft' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
        end
    end
end

local function tabWorld()
    if section('time of day') then
        if ACTIONS.time.probe() then
            if state.amounts.hour == nil then state.amounts.hour = 12 end
            local h = amountBox('hour', 12, 1)
            if h < 0 then h = 0 elseif h > 23 then h = 23 end
            state.amounts.hour = h
            same()
            if ImGui.Button(('Set %02d:00##time'):format(h)) then
                local ok = ACTIONS.time.run(h)
                note(ok and ('OK  clock set to %02d:00'):format(h) or 'FAIL the time system refused')
            end
        else
            textc(COL.bad, ACTIONS.time.needs .. ' is not available on this build')
        end
        sep()
    end

    if section('weather') then
        if ACTIONS.weather.probe() then
            -- The eight names shipped here were community guesses and the official
            -- wiki documents no weather commands at all. So ask the game for the
            -- real record ids instead, the same way Browse does.
            if state.weather == nil then
                -- Try every type and keep the richest, instead of stopping at the
                -- first that answers at all. gamedataWeather_Record returns two
                -- records on 2.5, so breaking on "more than zero" settled for two
                -- weather states when the state list is the other type.
                local found = {}
                for _, t in ipairs({ 'gamedataWeatherState_Record', 'gamedataWeather_Record',
                                     'gamedataEnvironmentAreaType_Record' }) do
                    local got = {}
                    local ok, recs = pcall(function() return TweakDB:GetRecords(t) end)
                    if ok and recs then
                        pcall(function()
                            for _, r in ipairs(recs) do
                                local n = recordName(r)
                                if n then got[#got + 1] = n end
                            end
                        end)
                    end
                    if #got > #found then found, state.weatherType = got, t end
                end
                table.sort(found)
                state.weather = found
                note('weather records found: %d%s', #found,
                    state.weatherType and (' via ' .. state.weatherType) or ' (falling back to guessed names)')
            end

            local live = #state.weather > 0
            if live then
                textc(COL.ok, ('%d real state ids read from your install'):format(#state.weather))
            else
                textc(COL.warn, 'No weather records found. These names are unverified guesses.')
            end

            local list = live and state.weather or nil
            if list then
                for i = 1, math.min(#list, 24) do
                    if i > 1 and (i % 2) ~= 1 then same() end
                    if ImGui.Button(list[i] .. '##wl' .. i) then
                        local ok, res = ACTIONS.weather.run(list[i])
                        note(verdict('weather -> ' .. list[i], ok, res,
                            'Give it the ten second transition before deciding it failed.'))
                    end
                end
            else
                for i, w in ipairs(data.weather or {}) do
                    if i > 1 and (i % 3) ~= 1 then same() end
                    if ImGui.Button(w.label .. '##w' .. i) then
                        local ok, res = ACTIONS.weather.run(w.state)
                        note(verdict('weather -> ' .. w.state, ok, res, nil))
                    end
                end
            end

            if ImGui.Button('Dump the weather system to the log##dumpws') then
                local ok, out = pcall(function() return Dump(Game.GetWeatherSystem(), false) end)
                if ok then
                    print('[Mikoshi] weather system dump follows'); print(tostring(out))
                    note('OK  dumped the weather system. Check the console for the real method names.')
                else
                    note('FAIL Dump refused: ' .. tostring(out))
                end
            end
        else
            textc(COL.bad, ACTIONS.weather.needs .. ' is not available on this build')
        end
        sep()
    end

    if section('stuck in the world') then
        wrapped('Lifts V two metres straight up. For falling through geometry or wedging in a doorway, which is cheaper than reloading a save.')
        if ACTIONS.unstuck.probe() then
            if ImGui.Button('Nudge V upward##unstuck') then
                local ok = ACTIONS.unstuck.run()
                note(ok and 'OK  teleported two metres up' or 'FAIL teleport refused')
            end
        else
            textc(COL.bad, ACTIONS.unstuck.needs .. ' is not available on this build')
        end
        sep()
    end

    if section('teleport', 'MapMarker') then
        if ACTIONS.teleport.probe() then
            wrapped('Save where you are BEFORE you jump. Some destinations are sealed areas you cannot walk out of, which is the wiki\'s warning rather than mine.')
            if ImGui.Button('Read where I am now##tpread') then
                local ok, p = pcall(function() return Game.GetPlayer():GetWorldPosition() end)
                local x, y, z
                if ok and p then pcall(function() x, y, z = p.x, p.y, p.z end) end
                if x then
                    state.tp.cur = { x = x, y = y, z = z }
                    state.tp.text = string.format('%.4f, %.4f, %.4f', x, y, z)
                    note('position: %s', state.tp.text)
                else
                    note('FAIL could not read your position')
                end
            end
            same()
            if ImGui.Button('Save it as a waypoint##tpsave') then
                local p = state.tp.cur
                if p then
                    local nm = (state.tp.name ~= '' and state.tp.name)
                            or ('waypoint ' .. (#state.tp.saved + 1))
                    table.insert(state.tp.saved, 1, { name = nm, x = p.x, y = p.y, z = p.z })
                    state.tp.name = ''
                    note('saved "%s"', nm)
                else
                    note('Read your position first.')
                end
            end
            if caps.InputText then
                local nv = ImGui.InputText('name##tpn', state.tp.name, 48)
                if type(nv) == 'string' then state.tp.name = nv end
                local cv = ImGui.InputText('x, y, z##tpc', state.tp.text, 96)
                if type(cv) == 'string' then state.tp.text = cv end
            end
            if ImGui.Button('Teleport to those coordinates##tpgo') then
                local x, y, z = state.tp.text:match('(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)')
                if x then
                    local ok, res = ACTIONS.teleport.run(tonumber(x), tonumber(y), tonumber(z))
                    note(verdict('teleport', ok, res, 'Give the area a second to stream in.'))
                else
                    note('FAIL could not read three numbers out of that box')
                end
            end

            if #state.tp.saved > 0 then
                textc(COL.dim, 'your waypoints')
                for i = 1, #state.tp.saved do
                    local s = state.tp.saved[i]
                    ImGui.Text(string.format('%s  (%.0f, %.0f, %.0f)', s.name, s.x, s.y, s.z))
                    same()
                    if ImGui.Button('Go##tpg' .. i) then
                        local ok, res = ACTIONS.teleport.run(s.x, s.y, s.z)
                        note(verdict('teleport to ' .. s.name, ok, res, nil))
                    end
                    same()
                    if ImGui.Button('Forget##tpf' .. i) then table.remove(state.tp.saved, i); break end
                end
            end

            -- Interlock, not advice. Some of these are sealed interiors you cannot
            -- walk out of, so the jump stays disabled until a waypoint exists to
            -- come back to. That is the one way teleport can break a run.
            textc(COL.dim, 'known places, coordinates from the wiki')
            local haveReturn = #state.tp.saved > 0
            if not haveReturn then
                statusIcon('warn')
                sameAt(30)
                textc(COL.warn, 'Save a waypoint first. Several of these cannot be left on foot.')
            end
            for i, pl in ipairs(data.places or {}) do
                if haveReturn then
                    if ImGui.Button(pl.label .. '##tpp' .. i, -1, 0) then
                        local ok, res = ACTIONS.teleport.run(pl.x, pl.y, pl.z)
                        note(verdict('teleport to ' .. pl.label, ok, res,
                            'Use a waypoint to get back if you are stuck.'))
                    end
                else
                    textc(COL.dim, '   ' .. pl.label)
                end
            end
        else
            textc(COL.bad, ACTIONS.teleport.needs .. ' is not available on this build')
        end
        sep()
    end

    if section('attributes', 'ArmFlex') then
        if ACTIONS.setAttribute.probe() then
            textc(COL.dim, 'Current value on the left. The box is what a button will set it TO.')
            local n = amountBox('attrv', 15, 1)
            same(); textc(COL.dim, 'set to this')
            local anyRead = false
            for i, a in ipairs(data.attributes or {}) do
                local cur = readAttribute(a.arg)
                if cur then anyRead = true end
                statusIcon(cur and 'ok' or 'warn')
                sameAt(30);  ImGui.Text(a.label)
                sameAt(190); textc(cur and COL.cyan or COL.dim,
                                   cur and tostring(cur) or 'could not read')
                sameAt(250)
                -- The button says the number, so there is no way to press it
                -- thinking it does something else.
                if ImGui.Button(('Set to %d##at%d'):format(n, i)) then
                    local ok, res = ACTIONS.setAttribute.run(a.arg, n)
                    note(verdict(('%s %s -> %d'):format(a.label, tostring(cur or '?'), n), ok, res,
                        a.verified and '' or 'This attribute name is inferred, not documented.'))
                end
            end
            if anyRead then
                textc(COL.dim, ic('Eye') .. 'read via ' .. (state.attrSrc or 'unknown'))
            else
                textc(COL.warn, 'None of the three read routes answered on this build, so the values above are unknown rather than zero.')
            end
            textc(COL.dim, 'Only Body (Strength) has a documented internal name. The other four are inferred.')
        else
            textc(COL.bad, ACTIONS.setAttribute.needs .. ' is not available on this build')
        end
        sep()
    end
    if section('character level') then
        if ACTIONS.setLevel.probe() then
            local n = amountBox('lvl', 50, 1)
            same()
            if ImGui.Button('Set level##lvl') then
                local ok = ACTIONS.setLevel.run(n)
                note(ok and ('OK  level set to %d'):format(n) or 'FAIL Game.SetLevel refused')
            end
            textc(COL.dim, 'Street cred through this call is undocumented, so it is not offered here.')
        else
            textc(COL.bad, ACTIONS.setLevel.needs .. ' is not available on this build')
        end
        sep()
    end

    if section('perk and attribute points') then
        if ACTIONS.devPoints.probe() then
            local n = amountBox('dev', 5, 1)
            same()
            if ImGui.Button('Perk points##perk') then
                local ok, got = ACTIONS.devPoints.run(n, 'Primary')
                note(ok and ('OK  added %d of %d perk point(s)'):format(got, n)
                        or 'FAIL the development system refused')
            end
            same()
            if ImGui.Button('Attribute points##attr') then
                local ok, got = ACTIONS.devPoints.run(n, 'Attribute')
                note(ok and ('OK  added %d of %d attribute point(s)'):format(got, n)
                        or 'FAIL the development system refused')
            end

            -- Relic points. There is no skillbook for these on 2.5 -- the item id
            -- that used to be here is not in TweakDB at all -- so they come from
            -- the same development system as the other two. The enum member is
            -- looked up by name first, because the one thing worse than no button
            -- is a button that quietly adds the wrong kind of point.
            local relicKind
            for _, k in ipairs({ 'Relic', 'Espionage', 'Primary_Relic' }) do
                local okk, v = pcall(function() return gamedataDevelopmentPointType[k] end)
                if okk and v ~= nil then relicKind = k; break end
            end
            if relicKind then
                same()
                if ImGui.Button('Relic points##relic') then
                    local ok, got = ACTIONS.devPoints.run(n, relicKind)
                    note(ok and ('OK  added %d of %d relic point(s) as %s'):format(got, n, relicKind)
                            or 'FAIL the development system refused ' .. relicKind)
                end
                hint('Uses gamedataDevelopmentPointType.' .. relicKind
                     .. ', found on this build. Relic points are Phantom Liberty content, so this does nothing without it.')
            else
                textc(COL.dim, 'Relic points: no matching member of gamedataDevelopmentPointType on this build, so there is no safe call to make.')
            end
        else
            textc(COL.bad, ACTIONS.devPoints.needs .. ' is not available on this build')
        end
    end
end

-- ---------------------------------------------------------------------------
-- BROWSE: read the ids out of the running game instead of shipping a list.
-- 2074 clothing, 1828 weapon and 1379 vehicle records answered on this install,
-- so every id shown here is correct for whatever patch is actually loaded. No
-- community list can promise that.
--
-- The one unknown is how to read a readable name off a record, which is not
-- documented. So try every plausible accessor in turn and keep the first that
-- returns a real string. Diagnostics reports which one won.
-- ---------------------------------------------------------------------------
local BROWSE = {
    { label = 'Clothing', type = 'gamedataClothing_Record',   give = 'item' },
    { label = 'Weapons',  type = 'gamedataWeaponItem_Record', give = 'item' },
    { label = 'Vehicles', type = 'gamedataVehicle_Record',    give = 'vehicle' },
}
local ACCESSORS = {
    { 'GetID().value',       function(r) return r:GetID().value end },
    { 'GetRecordID().value', function(r) return r:GetRecordID().value end },
    { 'GetName()',           function(r) return r:GetName() end },
    { 'tostring(GetID())',   function(r) return tostring(r:GetID()) end },
}

-- Three outcomes, not two. Twice now I have reported success because a call
-- did not raise, when the game had either returned false or returned nothing
-- at all. A function that returns nil gives NO confirmation, and saying "OK"
-- there is how "spawned" ended up printed for a car that never appeared.
function verdict(what, raisedOk, res, hint)
    if not raisedOk then return 'ERROR   ' .. what .. ': ' .. tostring(res) end
    if res == false then return 'REFUSED ' .. what .. ' - the game returned false' end
    if res == nil then
        return 'NO ANSWER ' .. what .. ' - the call returned nothing, so it is not confirmed. '
            .. (hint or '')
    end
    return 'OK      ' .. what .. ' (returned ' .. tostring(res) .. '). ' .. (hint or '')
end

function recordName(r)
    for i = 1, #ACCESSORS do
        local ok, v = pcall(ACCESSORS[i][2], r)
        if ok and type(v) == 'string' and #v > 0 and not v:match('^userdata') then
            return v, i
        end
    end
    return nil
end

-- Raw ids like "Items.Vest_17_basic_01" tell you nothing. The readable name,
-- quality and description live on the record's flats as localisation keys, so
-- resolve them per visible row rather than for all 2074 at load.
local descCache = {}

local function asString(v)
    if v == nil then return nil end
    if type(v) == 'string' then return #v > 0 and v or nil end
    local ok, s = pcall(function() return v.value end)
    if ok and type(s) == 'string' and #s > 0 then return s end
    local ok2, s2 = pcall(function() return tostring(v) end)
    if ok2 and type(s2) == 'string' and #s2 > 0 and not s2:match('^userdata') then return s2 end
    return nil
end

local function localise(v)
    local s = asString(v)
    if not s then return nil end
    -- Only something shaped like LocKey#12345 is a key that can fail to
    -- resolve. Anything else is already the text.
    local isKey = s:find('^LocKey#') ~= nil
    if hasGlobal('GetLocalizedText') then
        local ok, t = pcall(function() return GetLocalizedText(s) end)
        if ok and type(t) == 'string' and #t > 0 then
            -- GetLocalizedText echoing its input back means the key did not
            -- resolve -- but ONLY when the input was a key. A displayName that
            -- is already plain text comes back unchanged because there is
            -- nothing to translate, and the old "t ~= s" rejected exactly
            -- that. Since the obtainable-by-V filter keeps an item only if it
            -- has a readable name, rejecting every plain name hid all 2074
            -- pieces of clothing and all 1828 weapons behind "0 obtainable".
            if t ~= s or not isKey then return t end
        end
    end
    if fnExists(Game, 'GetLocalizedTextByKey') then
        local ok, t = pcall(function() return Game.GetLocalizedTextByKey(v) end)
        if ok and type(t) == 'string' and #t > 0 then return t end
    end
    return nil
end

function describe(id)
    if descCache[id] then return descCache[id] end
    local function flat(suffix)
        local ok, v = pcall(function() return TweakDB:GetFlat(id .. suffix) end)
        return ok and v or nil
    end
    local d = {}
    d.name    = localise(flat('.displayName'))
    d.desc    = localise(flat('.localizedDescription'))
    d.quality = asString(flat('.quality'))
    if d.quality then d.quality = d.quality:gsub('^Quality%.', '') end
    if d.desc and #d.desc > 150 then d.desc = d.desc:sub(1, 147) .. '...' end
    descCache[id] = d
    return d
end

-- Enumerating a record type returns EVERYTHING the game has, including NPC
-- weapons, debug props and aerial craft from scripted scenes. None of that is
-- obtainable by V, and firing a Give at it is how you get a silent no-op.
--
-- There is no "player can have this" flag I could verify, so this filter uses
-- the best signals actually available at runtime:
--   vehicles       ground only, by the v_ prefix; av_ are scene aircraft
--   weapons/clothes a resolvable localised display name. Player-facing items
--                   are named for the UI; internal ones generally are not.
-- It is a heuristic, so the count of what it hid is always on screen and one
-- click turns it off.
local function computePlayable(i)
    local cache = state.browse.cache[i]
    if not cache or not cache.names then return end
    cache.playableTried = true
    local b, keep = BROWSE[i], {}
    for n = 1, #cache.names do
        local id  = cache.names[n]
        local low = id:lower()
        local ok  = not (low:find('debug') or low:find('_npc') or low:find('npc_')
                      or low:find('placeholder') or low:find('_test') or low:find('dummy'))
        if ok then
            if b.give == 'vehicle' then
                ok = low:find('%.v_') ~= nil
            else
                ok = describe(id).name ~= nil
            end
        end
        if ok then keep[#keep + 1] = id end
    end

    -- A filter that keeps nothing is a broken filter, not an empty category.
    -- The game does not ship 2074 pieces of clothing that V cannot wear. When
    -- that happens, show everything and say so, because a list with one wrong
    -- row in it is worth more than a list with no rows at all.
    if #keep == 0 and #cache.names > 0 then
        cache.playable = nil
        cache.filterBroke = string.format(
            'the obtainable-by-V filter matched none of the %d %s records, so it is being ignored',
            #cache.names, string.lower(b.label))
        note('%s: filter kept 0 of %d, ignoring it', b.label, #cache.names)
        return
    end
    cache.filterBroke = nil
    cache.playable = keep
    note('%s: %d of %d look obtainable by V', b.label, #keep, #cache.names)
end

-- Opt-in, because it touches every record of the type. Once it has run, the
-- search box matches readable names as well as raw ids.
local function resolveAll(i)
    local cache = state.browse.cache[i]
    if not cache or not cache.names then return end
    local got = 0
    for n = 1, #cache.names do
        local d = describe(cache.names[n])
        if d.name then got = got + 1 end
    end
    cache.resolved = true
    note('resolved %d readable names out of %d', got, #cache.names)
end

local function loadBrowse(i)
    local b = BROWSE[i]
    local ok, recs = pcall(function() return TweakDB:GetRecords(b.type) end)
    if not ok or recs == nil then
        state.browse.cache[i] = { err = 'TweakDB:GetRecords returned nothing for ' .. b.type }
        return
    end
    local names, acc, total = {}, nil, 0
    local walked = pcall(function()
        for _, r in ipairs(recs) do
            total = total + 1
            local n, which = recordName(r)
            if n then names[#names + 1] = n; acc = acc or which end
        end
    end)
    if not walked then
        state.browse.cache[i] = { err = 'could not iterate the record list' }
        return
    end
    table.sort(names)
    state.browse.cache[i] = { names = names, total = total, acc = acc }
    state.browse.accessor = acc and ACCESSORS[acc][1] or 'none worked'
    note('browse %s: read %d of %d names via %s', b.label, #names, total, state.browse.accessor)
end

-- ---------------------------------------------------------------------------
-- What does THIS build call it?
--
-- An id that is not in TweakDB is usually not an invention, it is a rename: a
-- patch moved MaxDoc, or the quickhack components stopped being items. The
-- answer is in the running game, so ask the running game. Sweep the record
-- types an item can live in, and keep the ones whose id contains the
-- distinctive tail of the one that failed.
--
-- GetRecords is per concrete type and some of these hold tens of thousands of
-- records, so this runs on a button press and never on a frame.
-- ---------------------------------------------------------------------------
local SEARCH_TYPES = {
    'gamedataConsumableItem_Record',
    'gamedataGenericItem_Record',
    'gamedataItem_Record',
    'gamedataAmmo_Record',
    'gamedataClothing_Record',
    'gamedataWeaponItem_Record',
    'gamedataCyberwareItem_Record',
    'gamedataGrenade_Record',
    'gamedataRecipeItem_Record',
    'gamedataItemBlueprint_Record',
    'gamedataAttachmentItem_Record',
    'gamedataEquipmentItem_Record',
}

-- Several needles, longest first, because one needle is a guess about HOW the
-- thing was renamed. Items.FirstAidWhiteOne searched as "firstaidwhiteone"
-- finds nothing the moment the tail changed; searched as "firstaid" it finds
-- the whole family. Underscore ids lose their trailing number, camel-case ids
-- lose their trailing words.
local function needlesFor(id)
    local tail = tostring(id):match('([^%.]+)$') or tostring(id)
    tail = tail:gsub('^CPO_', '')
    local out, seen = {}, {}
    local function add(s, min)
        if s and #s >= (min or 4) then
            s = s:lower()
            if not seen[s] then seen[s] = true; out[#out + 1] = s end
        end
    end
    -- Trimming a full id is specific, so four characters is enough.
    add(tail)
    add((tail:gsub('%d+$', '')))
    add((tail:gsub('_[^_]*$', '')))
    -- A single camel-case word is not. "BounceBack" gave up its last token as
    -- "back", which matched five backstory shards and a keycard and told us
    -- nothing. Six characters minimum for anything token-derived.
    local tok = {}
    for w in tail:gmatch('%u%l+') do tok[#tok + 1] = w end
    if #tok >= 2 then add(tok[1] .. tok[2], 6) end
    if #tok >= 1 then add(tok[1], 6) end
    if #tok >= 1 then add(tok[#tok], 6) end
    return out, tail
end

local function findLike(id)
    local needles, tail = needlesFor(id)
    if #needles == 0 then return {}, 'that id has nothing distinctive to search for' end

    -- Sweep once, keep every record name, then match. Re-reading tens of
    -- thousands of records per needle would be absurd.
    local pool, swept, total, answered = {}, 0, 0, {}
    for _, t in ipairs(SEARCH_TYPES) do
        local ok, recs = pcall(function() return TweakDB:GetRecords(t) end)
        if ok and recs ~= nil then
            local n0 = total
            pcall(function()
                for _, r in ipairs(recs) do
                    local n = recordName(r)
                    if n then total = total + 1; pool[#pool + 1] = tostring(n) end
                end
            end)
            if total > n0 then
                swept = swept + 1
                answered[#answered + 1] = string.format('%s %d', t:gsub('^gamedata', ''):gsub('_Record$', ''), total - n0)
            end
        end
    end

    -- "Searched and found nothing" and "could not search" are different
    -- answers and this used to report both as the first one. That is the same
    -- mistake as calling a nil return a success.
    if total == 0 then
        return {}, 'NOT SEARCHED: none of the ' .. #SEARCH_TYPES
            .. ' item record types returned anything, so this proves nothing about ' .. tail
    end

    for _, needle in ipairs(needles) do
        local hits, seen = {}, {}
        for _, n in ipairs(pool) do
            if not seen[n] and n:lower():find(needle, 1, true) then
                seen[n] = true; hits[#hits + 1] = n
                if #hits >= 24 then break end
            end
        end
        if #hits > 0 then
            table.sort(hits)
            return hits, string.format('matched "%s" in %d record(s) across %s',
                needle, total, table.concat(answered, ', '))
        end
    end
    return {}, string.format('no record out of %d contains any of: %s   [%s]',
        total, table.concat(needles, ', '), table.concat(answered, ', '))
end

local function tabBrowse()
    if section('source') then
        if state.browse.idx == 3 then
            textc(COL.warn, 'Vehicle prefixes: v_ is a ground vehicle, av_ is an aerial one used in scripted scenes. An av_ will not appear even when the call accepts it.')
        end
        for i = 1, #BROWSE do
            if i > 1 then same() end
            if ImGui.Button(BROWSE[i].label .. '##bt' .. i) then state.browse.idx = i end
        end
        sep()
    end

    -- Deliberately OUTSIDE the fold above. The search section below reads
    -- these, and these guards decide whether there is anything to search at
    -- all. Folding a header has to hide that section, not quietly disable the
    -- rest of the tab -- which is what happened when the fold was wrapped
    -- around them: cache went out of scope and resolved as a nil global.
    local i = state.browse.idx
    local b, cache = BROWSE[i], state.browse.cache[i]

    if not cache then
        textc(COL.dim, 'Not loaded. Reading a couple of thousand records takes a moment.')
        if ImGui.Button('Load ' .. b.label .. '##load') then loadBrowse(i) end
        return
    end
    if cache.err then textc(COL.bad, cache.err); return end
    if #cache.names == 0 then
        textc(COL.bad, ('Read %d records but could not get a name off any of them.'):format(cache.total))
        textc(COL.dim, 'Every accessor failed. The ids exist, but not in a form this build exposes to Lua.')
        return
    end

    if section('search') then
        if caps.InputText then
            local v = ImGui.InputText('##bq', state.browse.q, 64)
            if type(v) == 'string' then state.browse.q = v end
        end
        same()
        if ImGui.Button('Clear##bq') then state.browse.q = '' end
        same()
        state.browse.desc = ImGui.Checkbox('readable names', state.browse.desc)

        local wasFiltered = state.browse.playableOnly
        state.browse.playableOnly = ImGui.Checkbox('obtainable by V only', state.browse.playableOnly)
        -- Keyed on "have we tried", not on "is there a result". The filter is now
        -- allowed to come back with nothing usable, and keying on the result meant
        -- that outcome re-swept 2074 records, with a TweakDB:GetFlat on each, on
        -- every frame the tab was open.
        if state.browse.playableOnly and (not cache.playableTried or wasFiltered ~= true) then
            computePlayable(i)
        end

        -- The filtered list is what we page through when the box is ticked.
        local list = (state.browse.playableOnly and cache.playable) or cache.names
        if cache.filterBroke then
            textc(COL.warn, ic('AlertCircle') .. cache.filterBroke)
        elseif state.browse.playableOnly and cache.playable then
            textc(COL.dim, ('%d shown, %d hidden as NPC, debug or scene-only.')
                :format(#cache.playable, #cache.names - #cache.playable))
        else
            textc(COL.warn, ('Unfiltered: all %d records, most of which V cannot have.'):format(#cache.names))
        end
        if state.browse.desc and not cache.resolved then
            if ImGui.Button('Match search against names too##resolve') then resolveAll(i) end
        end
        sep()

        local q, shown, matches = state.browse.q:lower(), 0, 0
        for n = 1, #list do
            local name = list[n]
            local d = state.browse.desc and describe(name) or nil
            local hit = q == '' or name:lower():find(q, 1, true)
                     or (d and d.name and d.name:lower():find(q, 1, true)) and true or false
            if hit then
                matches = matches + 1
                if shown < 40 then
                    shown = shown + 1
                    -- Readable name first when we have one, raw id underneath,
                    -- because the id is what the Give button actually sends.
                    if d and d.name then
                        ImGui.Text(d.name)
                        if d.quality then same(); textc(qualityCol(d.quality), '[' .. d.quality .. ']') end
                        textc(COL.dim, name)
                        if d.desc then textc(COL.dim, d.desc) end
                    else
                        ImGui.Text(name)
                    end
                    if b.give == 'item' then
                        if ImGui.Button('Give##b' .. n) then
                            local ok, msg = giveItem(name, 1)
                            note((ok and 'OK  ' or 'FAIL ') .. msg)
                        end
                    elseif ACTIONS.vehicle.probe() then
                        -- "Add to list" rather than "Unlock": this puts the car in
                        -- your summonable list. It does NOT park one in front of
                        -- you, which is what the old label implied.
                        if ImGui.Button('Add to list##b' .. n) then
                            local ok, res = ACTIONS.vehicle.run(name, true)
                            note(verdict(name .. ' -> vehicle list', ok, res,
                                'Summon it from the phone; nothing spawns here.'))
                        end
                        if ACTIONS.vehicle.canSpawn() then
                            same()
                            if ImGui.Button('Spawn now##s' .. n) then
                                local ok, res = ACTIONS.vehicle.spawn(name)
                                note(verdict('spawn ' .. name, ok, res,
                                    'If nothing appeared, the call accepted it but the game did not place a car.'))
                            end
                        end
                    else
                        textc(COL.dim, 'vehicle system unavailable')
                    end
                    sep()
                end
            end
        end
        if matches > shown then
            textc(COL.dim, ('%d more match. Narrow the search.'):format(matches - shown))
        elseif matches == 0 then
            textc(COL.warn, 'nothing matches that')
        end
    end
end

-- ---------------------------------------------------------------------------
-- The palette picker, as chips instead of a row of grey buttons with faction
-- names on them. You could not see what a palette looked like until you were
-- already in it.
--
-- Each chip IS a Button with its fill pushed to that palette's own base, so
-- hover and click come free and the chip shows the body colour you are about
-- to get; the accent and secondary are painted across the bottom with the draw
-- list afterwards, using the button's own rectangle.
-- ---------------------------------------------------------------------------
local function paletteChip(i, w, h)
    local th = THEMES[i]
    local on = (state.theme == i)
    local pushed = 0
    local function pc(n, c, al)
        local idx
        if not pcall(function() idx = ImGuiCol[n] end) or idx == nil then return end
        if pcall(function() ImGui.PushStyleColor(idx, c[1], c[2], c[3], al or 1.0) end) then
            pushed = pushed + 1
        end
    end
    pc('Button',        th.bg)
    pc('ButtonHovered', mix(th.bg, th.a, 0.22))
    pc('ButtonActive',  mix(th.bg, th.a, 0.40))
    pc('Border',        th.a, on and 1.0 or 0.35)
    local clicked = ImGui.Button('##pal' .. i, w, h)
    if pushed > 0 then pcall(function() ImGui.PopStyleColor(pushed) end) end

    pcall(function()
        local x1, y1 = ImGui.GetItemRectMin()
        local x2, y2 = ImGui.GetItemRectMax()
        local dl = ImGui.GetWindowDrawList()
        -- accent and secondary as a strip along the bottom edge
        local split = x1 + (x2 - x1) * 0.62
        dl:AddRectFilled(x1, y2 - 9, split, y2, pack(th.a))
        dl:AddRectFilled(split, y2 - 9, x2, y2, pack(th.b))
        -- the name in whichever of black or white survives on that base
        dl:AddText(x1 + 7, y1 + 6, pack(onCol(th.bg)), th.name)
        if on then
            -- Corner brackets, so the live palette is marked by SHAPE. A
            -- coloured marker would be the one thing the palette just changed.
            local b, t, c = 10, 2, pack(th.a)
            dl:AddRectFilled(x1, y1, x1 + b, y1 + t, c)
            dl:AddRectFilled(x1, y1, x1 + t, y1 + b, c)
            dl:AddRectFilled(x2 - b, y1, x2, y1 + t, c)
            dl:AddRectFilled(x2 - t, y1, x2, y1 + b, c)
        end
    end)
    return clicked
end

local function paletteGrid()
    local plain = not (state.fancy ~= false and caps.style and caps.GetWindowDrawList
                   and caps.GetItemRectMin and caps.GetItemRectMax)
    for i = 1, #THEMES do
        if i > 1 and (i % 3) ~= 1 then same() end
        local hit
        if plain then
            -- Paint the button in the palette it selects. Without this the
            -- picker is nine identical grey buttons with faction names on
            -- them, which is exactly as much use as a list.
            local th, on = THEMES[i], (state.theme == i)
            local pushed = 0
            local function pc(n, c, al)
                local idx
                if not pcall(function() idx = ImGuiCol[n] end) or idx == nil then return end
                if pcall(function() ImGui.PushStyleColor(idx, c[1], c[2], c[3], al or 1.0) end) then
                    pushed = pushed + 1
                end
            end
            if caps.style then
                pc('Button',        on and th.a or mix(th.bg, th.a, 0.42))
                pc('ButtonHovered', mix(th.a, { 1, 1, 1 }, 0.22))
                pc('ButtonActive',  th.a)
                pc('Text',          onCol(on and th.a or mix(th.bg, th.a, 0.42)))
                pc('Border',        th.b, on and 1.0 or 0.35)
            end
            hit = ImGui.Button('  ' .. th.name .. '  ##th' .. i)
            if pushed > 0 then pcall(function() ImGui.PopStyleColor(pushed) end) end
        else
            hit = paletteChip(i, 136, 46)
        end
        if hit then
            state.theme = i; saveTheme()
            note('palette: %s. %s', THEMES[i].name, THEMES[i].note or '')
        end
    end
    textc(COL.cyan, theme().note or '')
end

local function tabDiagnostics()
    -- The ids that failed, named. This is the first thing in the tab because
    -- it is the only part of Diagnostics that is ever urgent.
    if section('ids not on this build', 'AlertCircle') then
        if #state.missing == 0 then
            textc(COL.ok, string.format('%s all %d ids verified against your TweakDB',
                ic('CheckCircle'), state.idsChecked or 0))
        else
            wrapped(string.format(
                '%d of %d ids are not in your TweakDB, so their rows are greyed out rather than fired into nothing. Usually a patch renamed them. Ask your own game what it calls them now.',
                #state.missing, state.idsChecked or 0))
            for i, m in ipairs(state.missing) do
                statusIcon('bad')
                sameAt(30); ImGui.Text(m.label)
                -- The record id is the longest thing on the row and the least
                -- willing to shorten, so it gets its own line rather than a
                -- column that runs off the edge on a narrow window.
                sameAt(300, 60); textc(COL.dim, m.group)
                ImGui.Indent(30); textc(COL.warn, m.record); ImGui.Unindent(30)
                if ImGui.Button('Find it on this build##find' .. i) then
                    local hits, how = findLike(m.record)
                    state.found[m.record] = hits
                    note('%s: %d candidate(s), %s', m.record, #hits, how)
                end
                local hits = state.found[m.record]
                if hits then
                    if #hits == 0 then
                        same(); textc(COL.dim, 'nothing similar in TweakDB either')
                    else
                        for _, h in ipairs(hits) do
                            textc(COL.cyan, '      ' .. tostring(h))
                        end
                    end
                end
            end
            if ImGui.Button('Print the whole list to the CET console##misslist') then
                -- print() lands in CET's own console, which is selectable text.
                -- That makes the list reportable without a screenshot.
                pcall(function()
                    print('[Mikoshi] ids not on this build (' .. #state.missing
                          .. ' of ' .. tostring(state.idsChecked) .. '):')
                    for _, m in ipairs(state.missing) do
                        print('  ' .. m.group .. '  ' .. m.record .. '  -- ' .. m.label)
                    end
                end)
                note('printed %d missing id(s) to the CET console', #state.missing)
            end
        end
        sep()
    end

    if section('watch list', 'Pulse') then
        wrapped('These appear on the pinned card, live, while you play. Pin the facts a quest should be setting, go do the thing, and watch which one never moves.')
        if caps.InputText then
            local v = ImGui.InputText('fact name##watchin', state.watch.input, 96)
            if type(v) == 'string' then state.watch.input = v end
            same()
            if ImGui.Button('Watch it##watchadd') then
                local ok, msg = addWatch(state.watch.input)
                if ok then state.watch.input = '' end
                note((ok and 'OK  ' or 'FAIL ') .. msg)
            end
        else
            textc(COL.bad, 'InputText unavailable, so facts cannot be added on this build')
        end

        if #state.watch.list == 0 then
            textc(COL.dim, 'Nothing watched. Try one of the quest fact names above.')
        else
            for i = #state.watch.list, 1, -1 do
                local name = state.watch.list[i]
                local v = state.watch.prev[name]
                ImGui.Text(name)
                sameAt(280); textc(COL.cyan, v == nil and '--' or tostring(v))
                same()
                if ImGui.Button('Drop##watchdrop' .. i) then removeWatch(i) end
            end
            textc(COL.dim, 'Saved beside the mod, so the list survives a reload.')
        end
        state.showCoords = ImGui.Checkbox('also show my coordinates on the card', state.showCoords)
        sep()
    end

    if section('appearance', 'Palette') then
        wrapped('A palette sets the whole window, not just the accent: the base, the panels, the buttons, the greys and the status colours are all derived from the three colours on the chip. The strip along the bottom of each chip is its accent and secondary; the body of the chip is the base you get.')
        paletteGrid()
        textc(COL.dim, ic('ContentSave') .. 'Saved by name beside the mod, so it survives a reload.')
        sep()

        if state.fancy == false then
            -- "draw list unavailable" was true and useless. Name the call that is
            -- missing, because the answer decides whether this is fixable here or
            -- a limit of CET itself.
            local miss = {}
            for _, n in ipairs({ 'GetWindowDrawList', 'GetCursorScreenPos',
                                 'GetContentRegionAvail', 'Dummy' }) do
                if not caps[n] then miss[#miss + 1] = n end
            end
            if #miss > 0 then
                textc(COL.warn, 'banner: flat fallback. CET does not bind ' .. table.concat(miss, ', '))
            else
                textc(COL.warn, 'banner: flat fallback. Every call is bound, so a draw call itself raised')
            end
            textc(COL.dim, 'Not a fault in your install. Rules, bars and the palette chips are built from widgets instead, which is why they still have colour.')
        else
            textc(COL.ok, 'banner: drawn with the ImGui draw list')
        end
        textc(Icons and COL.ok or COL.warn,
            'IconGlyphs: ' .. (Icons and ('loaded via require("' .. tostring(iconPath) .. '")')
                                     or ('every path failed: ' .. tostring(iconErr))))
        state.icons = ImGui.Checkbox('show icons', state.icons)
        textc(COL.dim, 'Turn this off if the icons render as empty boxes on your build.')
        sep()
    end

    if section('record names') then
        textc(state.browse.accessor and COL.ok or COL.dim,
            'id accessor: ' .. tostring(state.browse.accessor or 'not probed yet, open Browse'))
        textc(hasGlobal('GetLocalizedText') and COL.ok or COL.warn,
            'GetLocalizedText: ' .. (hasGlobal('GetLocalizedText') and 'present' or 'missing, names stay raw'))
        textc(COL.dim, 'Icons are not possible: ImGui needs a texture handle and CET exposes no loader for the game atlases.')
        sep()
    end

    if section('vehicle system') then
        wrapped('If "Add to list" reports refused, the record is not a player vehicle. Dump the system to see every method it really has, then tell me which one spawns.')
        if ImGui.Button('Dump vehicle system to the log##dumpvs') then
            local ok, out = pcall(function() return Dump(Game.GetVehicleSystem(), false) end)
            if ok then
                print('[Mikoshi] vehicle system dump follows')
                print(tostring(out))
                note('OK  dumped the vehicle system to the console and cyber_engine_tweaks.log')
            else
                note('FAIL Dump refused: ' .. tostring(out))
            end
        end
        textc(ACTIONS.vehicle.canSpawn() and COL.ok or COL.dim,
            'SpawnPlayerVehicle: ' .. (ACTIONS.vehicle.canSpawn() and 'present' or 'not on this build'))
        sep()
    end

    if section('keybind') then
        wrapped('CET does not allow a mod to ship a default key. Open the overlay, go to Bindings, find "Mikoshi: pin the watch card", click the empty box, press the key you want, then Save.')
        textc(state.pinned and COL.ok or COL.dim,
            state.pinned and 'pinned: the menu stays on screen with the overlay shut'
                           or 'not pinned: the menu shows only while the overlay is open')
        textc(COL.warn, 'Your key pins a small status card only. To USE the menu, open the CET overlay.')
        textc(COL.dim, 'CET sends mouse and keyboard to ImGui only while its overlay is showing, and a mod cannot open that overlay. Nothing to fix here.')
        sep()

        ImGui.Text('Resolved game API')
        textc(api.setFact and COL.ok or COL.bad, 'set fact:  ' .. tostring(api.setFactSrc))
        textc(api.getFact and COL.ok or COL.bad, 'read fact: ' .. tostring(api.getFactSrc))
        textc(api.journalOk and COL.ok or COL.bad, 'journal:   ' .. (api.journalOk and 'all four methods present' or 'incomplete'))
        textc(api.stateNamed and COL.ok or COL.warn, 'state enum: ' .. tostring(api.stateSrc))
        textc(api.notifyNamed and COL.ok or COL.warn, 'notify enum: ' .. tostring(api.notifySrc))
        sep()

        ImGui.Text('ImGui bindings')
        local missing = {}
        for k, v in pairs(caps) do if v == false then table.insert(missing, k) end end
        if #missing == 0 then textc(COL.ok, 'every widget this menu uses is present')
        else textc(COL.warn, 'missing: ' .. table.concat(missing, ', ')) end
        sep()

        if dataErr then textc(COL.bad, 'data.lua failed to load: ' .. dataErr); sep() end

        ImGui.Text('Check anything by hand')
        if caps.InputText then
            local v = ImGui.InputText('fact##probefact', state.probe.fact, 96)
            if type(v) == 'string' then state.probe.fact = v end
        end
        if ImGui.Button('Read fact##probe') and api.getFact then
            local ok, val = pcall(function() return api.getFact(state.probe.fact) end)
            state.probeResult = ok and (state.probe.fact .. ' = ' .. tostring(val))
                                  or ('read failed: ' .. tostring(val))
        end
        if caps.InputText then
            local v = ImGui.InputText('record##probeitem', state.probe.item, 96)
            if type(v) == 'string' then state.probe.item = v end
        end
        if ImGui.Button('Does this record exist?##probe') then
            state.probeResult = state.probe.item .. (recordExists(state.probe.item)
                and ' -> present in TweakDB' or ' -> NOT in TweakDB on this build')
        end
        if state.probeResult ~= '' then textc(COL.dim, state.probeResult) end
        sep()

        ImGui.Text('Activity')
        for i = 1, math.min(#state.log, 12) do textc(COL.dim, state.log[i]) end
    end
end

local function tabUndo()
    wrapped('Fact changes only. A forced journal state has no previous value to restore, so it never appears here.')
    sep()
    if #state.undo == 0 then textc(COL.dim, 'nothing changed yet'); return end
    for i, u in ipairs(state.undo) do
        ImGui.Text(string.format('%s  %s', u.at, u.fact))
        textc(COL.dim, string.format('%s -> %s', tostring(u.prev), tostring(u.new)))
        if u.prev ~= nil and api.setFact then
            if ImGui.Button('Put it back##undo' .. i) then
                local ok, err = pcall(function() api.setFact(u.fact, u.prev) end)
                note(ok and ('OK  reverted %s to %s'):format(u.fact, tostring(u.prev))
                         or ('FAIL ' .. tostring(err)))
                if ok then table.remove(state.undo, i); break end
            end
        else
            textc(COL.dim, 'no previous value was captured')
        end
        sep()
    end
end

local TAB_FN = { tabQuestFixes, tabShards, tabInventory, tabWorld, tabBrowse, tabDiagnostics, tabUndo }

-- A count beside each category, the way a trainer menu shows how much is behind
-- each entry. Undo is counted live because it grows as you use the thing.
local function navCount(i)
    if     i == 1 then return #(data.facts or {}) + #(data.templates or {}) + 1
    elseif i == 2 then return #(data.shards or {})
    elseif i == 3 then return #(data.everyday or {}) + #(data.exp or {}) + #(data.ammo or {})
                              + #(data.healing or {}) + #(data.crafting or {}) + #(data.iconics or {})
    elseif i == 4 then return 4 + #(data.places or {}) + #(data.attributes or {})
    elseif i == 5 then local c5 = state.browse.cache[state.browse.idx]
        if c5 then local l = (state.browse.playableOnly and c5.playable) or c5.names
            return l and #l or nil end
        return nil
    elseif i == 7 then return #state.undo end
    return nil
end

-- A button's label is one colour and cannot be right-aligned, so the count is
-- drawn over the button afterwards using its own rectangle. If the draw list
-- or the item-rect calls are missing, fall back to putting the count in the
-- label, which is what was clipping before the rail got wider.
local function navButton(i)
    local name, count = TABS[i], navCount(i)
    local on = (state.tab == i)
    local plain = not (state.fancy ~= false and caps.GetWindowDrawList
                   and caps.GetItemRectMin and caps.GetItemRectMax)
    local label = (plain and count) and (name .. '   ' .. count) or name

    -- The open tab has to look open. There was no selected state here at all:
    -- the highlight that shows up in screenshots is ImGui's hover, which
    -- follows the mouse rather than the page you are on, so the moment the
    -- pointer moved there was nothing saying where you were. The open one is
    -- filled with the accent, which is a lightness difference and not only a
    -- hue, so it still reads if the colour does not.
    local pushed = 0
    if on and caps.style then
        local function pc(n, c, al)
            local idx
            if not pcall(function() idx = ImGuiCol[n] end) or idx == nil then return end
            if pcall(function() ImGui.PushStyleColor(idx, c[1], c[2], c[3], al or 1.0) end) then
                pushed = pushed + 1
            end
        end
        local Pc = A()
        pc('Button',        Pc)
        pc('ButtonHovered', mix(Pc, { 1, 1, 1 }, 0.18))
        pc('ButtonActive',  Pc)
        pc('Text',          onCol(Pc))
    end
    if ImGui.Button(label .. '##nav' .. i, -1, 0) then state.tab = i end
    if pushed > 0 then pcall(function() ImGui.PopStyleColor(pushed) end) end
    if plain or not count then return end
    pcall(function()
        local x1, y1 = ImGui.GetItemRectMin()
        local x2, y2 = ImGui.GetItemRectMax()
        local txt = tostring(count)
        local w = (ImGui.CalcTextSize and select(1, ImGui.CalcTextSize(txt))) or (#txt * 8)
        ImGui.GetWindowDrawList():AddText(x2 - w - 10, y1 + ((y2 - y1) - 15) * 0.5,
            pack(A()), txt)
    end)
end

-- ===========================================================================
-- events
-- ===========================================================================

registerForEvent('onInit', function()
    detectImGui()
    loadTheme()
    loadWatch()
    loadBlocked()
    loadFolds()
    resolveApi()
    verifyAll()
    mod.ready = true
    note('Mikoshi ready. %s, %s.', api.setFactSrc or 'no fact API',
        api.journalOk and 'journal OK' or 'journal incomplete')
end)

-- The guard has to run with the overlay shut, which is when onDraw does not.
registerForEvent('onUpdate', function(dt)
    pcall(guardTick, dt)
end)

registerForEvent('onOverlayOpen',  function() state.overlayOpen = true  end)
registerForEvent('onOverlayClose', function() state.overlayOpen = false end)

registerForEvent('onDraw', function()
    if not mod.ready then return end

    -- Pinned with the overlay shut: CET sends no mouse or keyboard to ImGui
    -- then, and a mod cannot open the overlay itself. Drawing the full menu
    -- there just produces a window whose buttons ignore you. So the pin shows
    -- a small read-only card instead, and says how to actually use it.
    if state.pinned and not state.overlayOpen then
        pushTheme()
        -- A DIFFERENT window id from the full menu. Sharing 'MIKOSHI' meant
        -- ImGui restored the menu's saved geometry, which is why a card meant
        -- to be a few lines opened at a quarter of the screen.
        -- AlwaysAutoResize then shrinks it to exactly its contents.
        if ImGui.Begin('MIKOSHI WATCH##card', ImGuiWindowFlags.AlwaysAutoResize) then
            -- One accent rule, so the card belongs to the palette rather than
            -- looking like a stray tooltip.
            --
            -- Deliberately NOT accentRule(), which spans the content width and
            -- advances the cursor by that width. In an AlwaysAutoResize window
            -- the content decides the width, so a full-width rule would set the
            -- card's width from whatever ImGui guessed on the first frame and
            -- then hold it there. This one is a fixed 150px and advances by a
            -- single pixel, so the rows alone decide how wide the card is.
            pcall(function()
                local rx, ry = ImGui.GetCursorScreenPos()
                local rdl = ImGui.GetWindowDrawList()
                rdl:AddRectFilled(rx, ry + 2, rx + 150, ry + 3, pack(B(), 0.45))
                rdl:AddRectFilled(rx, ry + 2, rx + 26, ry + 3, pack(A()))
                ImGui.Dummy(1, 6)
            end)
            local rows = readWatch()
            if #rows == 0 then
                textc(COL.dim, ic('Pulse') .. 'nothing watched')
            else
                for _, r in ipairs(rows) do
                    -- Changed in the last six seconds reads in the accent
                    -- colour, so a fact flipping is visible at a glance.
                    textc(r.fresh and COL.accent or COL.dim, r.name)
                    sameAt(230)
                    textc(r.fresh and COL.ok or COL.cyan,
                        r.value == nil and '--' or tostring(r.value))
                end
            end
            if state.showCoords then
                local ok, p = pcall(function() return Game.GetPlayer():GetWorldPosition() end)
                if ok and p then
                    local x, y, z
                    pcall(function() x, y, z = p.x, p.y, p.z end)
                    if x then textc(COL.dim, string.format('%.0f  %.0f  %.0f', x, y, z)) end
                end
            end
        end
        ImGui.End()
        popTheme()
        return
    end

    if not (state.overlayOpen and state.show) then return end

    pushTheme()
    ImGui.SetNextWindowSize(640, 660, ImGuiCond.FirstUseEver)
    if ImGui.Begin('MIKOSHI') then
        banner()
        sep()

        local okNav = caps.BeginChild and
            pcall(function() ImGui.BeginChild('fx_nav', 198, -30, true) end)
        if okNav then
            for i = 1, #TABS do navButton(i) end
            ImGui.EndChild()
            same()
        else
            for i = 1, #TABS do
                if i > 1 then same() end
                if ImGui.Button(TABS[i] .. '##nav' .. i) then state.tab = i end
            end
            sep()
        end

        local okBody = caps.BeginChild and
            pcall(function() ImGui.BeginChild('fx_body', 0, -30, false) end)

        -- Wrap every piece of text in the pane at the content edge, once, here
        -- -- rather than hoping each of a few hundred call sites remembered to
        -- use TextWrapped. A plain Text does not wrap, it just keeps going
        -- past the right edge, and since nothing in this window scrolls
        -- sideways the end of the sentence was simply gone. PushTextWrapPos(0)
        -- means "wrap at the content region edge" and covers Text and
        -- TextColored alike.
        local wrapped_ = caps.PushTextWrapPos
            and pcall(function() ImGui.PushTextWrapPos(0) end)

        local fn = TAB_FN[state.tab]
        if fn then
            local ok, err = pcall(fn)
            if not ok then textc(COL.bad, 'category error: ' .. tostring(err)) end
        end

        if wrapped_ then pcall(function() ImGui.PopTextWrapPos() end) end
        if okBody then ImGui.EndChild() end

        sep()
        statusStrip()
    end
    ImGui.End()
    popTheme()
end)

registerForEvent('onShutdown', function()
    mod.ready = false
end)

-- Root level, outside any event: CET requires it there. CET does not let a mod
-- ship a default key, so this appears UNBOUND in the overlay's Bindings tab
-- until you assign one. Bindings > "Mikoshi: pin the watch card" > click > press a key >
-- Save.
--
-- Pinning draws the window with the overlay shut, which is the point of having
-- a key at all. Clicking still needs the overlay, because CET only routes mouse
-- and keyboard into ImGui while it is open. That is a CET rule, not a choice.
registerHotkey('fixer_toggle', 'Mikoshi: pin the watch card', function()
    state.pinned = not state.pinned
    if state.pinned then state.show = true end
end)

return mod

