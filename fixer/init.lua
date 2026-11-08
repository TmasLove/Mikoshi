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
    fields      = {},      -- template input boxes
    probe       = { fact = 'ig_phone_manager_off', item = 'Items.money' },
    icons       = true,
    theme       = 1,
    psy         = nil,
    psyShow     = false,
    tp          = { cur = nil, text = '', name = '', saved = {} },
    weather     = nil,  -- filled on first use of the World tab
    weatherType = nil,
    browse      = { idx = 1, q = '', cache = {}, accessor = nil, desc = true, playableOnly = true },
    probeResult = '',
}

-- Forward declared: tabWorld (defined above the Browse section) calls both of
-- these, and a local declared further down the file would not be in scope
-- there. Lua would resolve them as globals and find nil at click time.
local verdict, recordName

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
                         'CollapsingHeader',
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

local function recordExists(id)
    local ok, r = pcall(function() return TweakDB:GetRecord(id) end)
    return ok and r ~= nil
end

local function verifyAll()
    local checked, found = 0, 0
    local function check(list)
        for _, row in ipairs(list or {}) do
            if row.record then
                state.records[row.record] = recordExists(row.record)
                checked = checked + 1
                if state.records[row.record] then found = found + 1 end
            end
        end
    end
    check(data.everyday); check(data.shards)
    check(data.ammo); check(data.healing); check(data.crafting); check(data.iconics)
    state.idsFound, state.idsChecked = found, checked
    note('TweakDB check: %d of %d ids present on this build', found, checked)
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
        return true, string.format('gave %d x %s, one call each because this item ignores quantity', given, id)
    end
    local ok, err = pcall(function() Game.AddToInventory(id, qty) end)
    if not ok then return false, tostring(err) end
    return true, string.format('gave %d x %s', qty, id)
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

-- Walk to the top of the journal tree instead of assuming a fixed depth. The
-- snippet going round online calls GetParentEntry exactly twice, which is right
-- for a tracked objective and wrong for a tracked sub-objective.
local function resolveTrackedQuest()
    if not api.journalOk then return nil, 'journal API unavailable', 0 end
    local ok, tracked = pcall(function() return api.journal:GetTrackedEntry() end)
    if not ok or tracked == nil then return nil, 'nothing is being tracked', 0 end
    local node, depth = tracked, 0
    while depth < 8 do
        local ok2, parent = pcall(function() return api.journal:GetParentEntry(node) end)
        if not ok2 or parent == nil then break end
        node, depth = parent, depth + 1
    end
    return node, nil, depth
end

-- forceCompleteTracked was removed with the button that called it.

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
local function sameAt(x) if caps.SameLine then pcall(function() ImGui.SameLine(x) end) end end

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
local THEMES = {
    { name = 'Samurai',   a = { 0.92, 0.80, 0.10 }, b = { 0.12, 0.80, 0.88 } },
    { name = 'Arasaka',   a = { 0.84, 0.13, 0.25 }, b = { 0.78, 0.80, 0.84 } },
    { name = 'Militech',  a = { 0.24, 0.54, 0.90 }, b = { 0.95, 0.70, 0.20 } },
    { name = 'Netrunner', a = { 0.10, 0.86, 0.94 }, b = { 0.95, 0.20, 0.62 } },
    { name = 'Trauma',    a = { 0.90, 0.92, 0.94 }, b = { 0.90, 0.17, 0.23 } },
    { name = 'Kang Tao',  a = { 0.30, 0.78, 0.48 }, b = { 0.85, 0.85, 0.30 } },
}

local function theme() return THEMES[state.theme] or THEMES[1] end
local function A() return theme().a end
local function B() return theme().b end

-- Floats to ImGui's packed 0xAABBGGRR, which is byte order, not RGB.
local function pack(c, alpha)
    local r = math.floor(c[1] * 255 + 0.5)
    local g = math.floor(c[2] * 255 + 0.5)
    local bl = math.floor(c[3] * 255 + 0.5)
    local al = math.floor((alpha or 1) * 255 + 0.5)
    return al * 16777216 + bl * 65536 + g * 256 + r
end

local function mul(c, f) return { c[1] * f, c[2] * f, c[3] * f } end

-- The theme choice outlives a reload, stored as one number beside the mod.
local function saveTheme()
    pcall(function()
        local f = io.open('theme.txt', 'w')
        if f then f:write(tostring(state.theme)); f:close() end
    end)
end

local function loadTheme()
    local ok, v = pcall(function()
        local f = io.open('theme.txt', 'r')
        if not f then return nil end
        local s = f:read('*a'); f:close()
        return tonumber(s)
    end)
    if ok and v and THEMES[v] then state.theme = v end
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
        pc('WindowBg',       { 0.035, 0.035, 0.045 }, 0.97)
        pc('ChildBg',        { 0.050, 0.050, 0.060 })
        pc('PopupBg',        { 0.050, 0.050, 0.060 }, 0.98)
        pc('Border',         P, 0.42)
        pc('Text',           { 0.91, 0.91, 0.88 })
        pc('TextDisabled',   { 0.46, 0.46, 0.45 })
        pc('TitleBg',        { 0.07, 0.07, 0.08 })
        pc('TitleBgActive',  mul(P, 0.30))
        pc('FrameBg',        { 0.10, 0.10, 0.12 })
        pc('FrameBgHovered', mul(P, 0.22))
        pc('FrameBgActive',  mul(P, 0.32))
        pc('Button',         { 0.12, 0.12, 0.14 })
        pc('ButtonHovered',  mul(P, 0.34))
        pc('ButtonActive',   mul(P, 0.58))
        pc('CheckMark',      P)
        pc('SliderGrab',     mul(P, 0.85))
        pc('Separator',      P, 0.26)
        pc('Tab',            { 0.10, 0.10, 0.12 })
        pc('TabHovered',     mul(P, 0.34))
        pc('TabActive',      mul(P, 0.48))
        pc('Header',         mul(P, 0.20))
        pc('HeaderHovered',  mul(P, 0.34))
        pc('ScrollbarBg',    { 0.05, 0.05, 0.06 })
        pc('ScrollbarGrab',  mul(P, 0.28))
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
    COL.accent = { P[1], P[2], P[3], 1.0 }
    COL.cyan   = { S[1], S[2], S[3], 1.0 }
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
    pc('Text',          0.03, 0.03, 0.04, 1.0)
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
local DRK = 0xFF0C0A0A  -- banner colours now come from the active palette

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
        local h, cut = 44, 22
        local YEL, CYN, DIM = pack(A()), pack(B()), pack(B(), 0.20)
        local barW = math.max(210, w * 0.62)

        -- solid block with a slant off its right edge
        dl:AddRectFilled(x, y, x + barW, y + h, YEL)
        dl:AddTriangleFilled(x + barW, y, x + barW + cut, y, x + barW, y + h, YEL)

        -- hazard stripes filling the gap to the right of the slant
        local sx = x + barW + cut + 6
        while sx < x + w - 10 do
            dl:AddLine(sx, y + h - 4, sx + 12, y + 6, DIM, 2.0)
            sx = sx + 9
        end

        -- rule under the whole header, plus a bright tick at the left
        dl:AddRectFilled(x, y + h + 3, x + w, y + h + 5, CYN)
        dl:AddRectFilled(x, y + h + 3, x + 46, y + h + 5, YEL)

        -- title sits on the yellow, so it is drawn dark
        dl:AddText(x + 16, y + 13, DRK, 'M I K O S H I')
        dl:AddText(x + barW + cut + 14, y + 13, CYN, 'NIGHT CITY TOOLKIT')

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

local function section(title, icon)
    local label = ic(icon or 'ChevronRight') .. string.upper(title)
    -- A separator bar with the label inset reads as a section; a coloured line
    -- of text reads as one more row. Use the real widget where it exists.
    textc(COL.accent, label)
    if accentRule() then return end
    if caps.SeparatorText then pcall(function() ImGui.Separator() end) end
end

local function amountBox(key, default, step)
    if state.amounts[key] == nil then state.amounts[key] = default or 1 end
    if caps.InputInt then
        -- InputInt draws its OWN minus and plus when given a step, which is
        -- why every row had two pairs of them. Use those, and cap the width or
        -- the box eats the rest of the line and pushes Give off the edge.
        if caps.SetNextItemWidth then
            pcall(function() ImGui.SetNextItemWidth(118) end)
        end
        local v = ImGui.InputInt('##amt' .. key, state.amounts[key], step or 1)
        if type(v) == 'number' then state.amounts[key] = math.max(0, v) end
    else
        ImGui.Text(tostring(state.amounts[key]))
        same()
        if ImGui.Button('-##' .. key) then
            state.amounts[key] = math.max(0, state.amounts[key] - (step or 1))
        end
        same()
        if ImGui.Button('+##' .. key) then
            state.amounts[key] = state.amounts[key] + (step or 1)
        end
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
local function grantRow(key, label, record, default, step, noteText, loop)
    local present = state.records[record]
    if present == nil then present = recordExists(record); state.records[record] = present end

    statusIcon(present and 'ok' or 'bad')
    sameAt(30); ImGui.Text(label)
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

local function tabQuestFixes()
    textc(COL.dim, 'Track the broken quest in your journal, then use the tools below.')
    sep()

    local quest, err, depth = resolveTrackedQuest()
    ImGui.Text('Tracked quest')
    if quest then
        local ok, hash = pcall(function() return api.journal:GetEntryHash(quest) end)
        textc(COL.ok, string.format('resolved by walking %d parent(s)', depth))
        ImGui.Text('hash: ' .. (ok and tostring(hash) or 'unavailable'))
    else
        textc(COL.warn, err or 'nothing tracked')
    end
    sep()

    -- REMOVED: force-complete of the tracked quest. It wrote a journal state
    -- with no previous value to restore, and on this build the enum names did
    -- not resolve, so it fell back to the community's hard-coded 3 and 2. A
    -- wrong number there sets a quest to the wrong state permanently.
    textc(COL.dim, 'Force-complete removed: no undo, and its enum did not resolve on this build.')
    sep()

    section('known fact fixes', 'Wrench')
    textc(COL.dim, 'Read before write. A fix already applied on this save cannot be pressed again.')
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
        else
            textc(COL.bad, 'SetFactStr unavailable on this build')
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

local function tabShards()
    textc(COL.warn, 'Read the shards you already hold first. An unread one you picked up long ago closes more sightings than any button here.')
    wrapped('Shards that fail to spawn on a body. Granting the shard is what unsticks the objective in most reports. Greyed rows are ids this build does not recognise.')
    sep()
    for i, s in ipairs(data.shards or {}) do
        grantRow('shard' .. i, s.label, s.record, 1, 1, s.note)
    end
end

local function tabInventory()
    section('eddies and points')
    for i, e in ipairs(data.everyday or {}) do
        grantRow('day' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
    end

    section('experience')
    textc(COL.dim, 'Game.AddExp is a function, not an item, so there is no record to pre-check.')
    for i, e in ipairs(data.exp or {}) do
        ImGui.Text(e.label)
        local qty = amountBox('exp' .. i, e.default, e.step)
        same()
        if ImGui.Button('Add##exp' .. i) then
            local ok, err = pcall(function() Game.AddExp(e.arg, qty) end)
            note(ok and ('OK  added %d %s'):format(qty, e.arg)
                     or ('FAIL Game.AddExp: ' .. tostring(err)))
        end
        sep()
    end

    section('ammo')
    for i, e in ipairs(data.ammo or {}) do
        grantRow('ammo' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
    end

    section('consumables')
    for i, e in ipairs(data.healing or {}) do
        grantRow('heal' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
    end

    section('iconics', 'Star')
    for i, e in ipairs(data.iconics or {}) do
        grantRow('icon' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
    end

    section('crafting materials')
    for i, e in ipairs(data.crafting or {}) do
        grantRow('craft' .. i, e.label, e.record, e.default, e.step, e.note, e.loop)
    end
end

local function tabWorld()
    section('time of day')
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

    section('weather')
    if ACTIONS.weather.probe() then
        -- The eight names shipped here were community guesses and the official
        -- wiki documents no weather commands at all. So ask the game for the
        -- real record ids instead, the same way Browse does.
        if state.weather == nil then
            local found = {}
            for _, t in ipairs({ 'gamedataWeather_Record', 'gamedataWeatherState_Record' }) do
                local ok, recs = pcall(function() return TweakDB:GetRecords(t) end)
                if ok and recs then
                    pcall(function()
                        for _, r in ipairs(recs) do
                            local n = recordName(r)
                            if n then found[#found + 1] = n end
                        end
                    end)
                end
                if #found > 0 then state.weatherType = t; break end
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

    section('stuck in the world')
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

    section('teleport', 'MapMarker')
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

    section('attributes', 'ArmFlex')
    if ACTIONS.setAttribute.probe() then
        local n = amountBox('attrv', 15, 1)
        for i, a in ipairs(data.attributes or {}) do
            if i > 1 and (i % 3) ~= 1 then same() end
            if ImGui.Button(a.label .. '##at' .. i) then
                local ok, res = ACTIONS.setAttribute.run(a.arg, n)
                note(verdict(a.label .. ' -> ' .. n, ok, res,
                    a.verified and '' or 'This attribute name is inferred, not documented.'))
            end
        end
        textc(COL.dim, 'Only Body (Strength) has a documented internal name. The other four are inferred.')
    else
        textc(COL.bad, ACTIONS.setAttribute.needs .. ' is not available on this build')
    end
    sep()
    section('character level')
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

    section('perk and attribute points')
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
    else
        textc(COL.bad, ACTIONS.devPoints.needs .. ' is not available on this build')
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
    if hasGlobal('GetLocalizedText') then
        local ok, t = pcall(function() return GetLocalizedText(s) end)
        if ok and type(t) == 'string' and #t > 0 and t ~= s then return t end
    end
    if fnExists(Game, 'GetLocalizedTextByKey') then
        local ok, t = pcall(function() return Game.GetLocalizedTextByKey(v) end)
        if ok and type(t) == 'string' and #t > 0 then return t end
    end
    return nil
end

local function describe(id)
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

local function tabBrowse()
    section('source')
    if state.browse.idx == 3 then
        textc(COL.warn, 'Vehicle prefixes: v_ is a ground vehicle, av_ is an aerial one used in scripted scenes. An av_ will not appear even when the call accepts it.')
    end
    for i = 1, #BROWSE do
        if i > 1 then same() end
        if ImGui.Button(BROWSE[i].label .. '##bt' .. i) then state.browse.idx = i end
    end
    sep()

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

    section('search')
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
    if state.browse.playableOnly and (not cache.playable or wasFiltered ~= true) then
        computePlayable(i)
    end

    -- The filtered list is what we page through when the box is ticked.
    local list = (state.browse.playableOnly and cache.playable) or cache.names
    if state.browse.playableOnly and cache.playable then
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

local function tabDiagnostics()
    section('appearance', 'Palette')
    textc(COL.dim, 'Palette. Everything in the window is derived from these two colours.')
    for i = 1, #THEMES do
        if i > 1 and (i % 3) ~= 1 then same() end
        local on = (state.theme == i)
        if on then statusIcon('ok'); same() end
        if ImGui.Button(THEMES[i].name .. '##th' .. i) then
            state.theme = i; saveTheme()
            note('palette: %s', THEMES[i].name)
        end
    end
    textc(COL.dim, 'Saved beside the mod, so it survives a reload.')
    sep()

    textc(state.fancy == false and COL.warn or COL.ok,
        'banner: ' .. (state.fancy == false and 'flat fallback, draw list unavailable' or 'drawn with the ImGui draw list'))
    textc(Icons and COL.ok or COL.warn,
        'IconGlyphs: ' .. (Icons and ('loaded via require("' .. tostring(iconPath) .. '")')
                                 or ('every path failed: ' .. tostring(iconErr))))
    state.icons = ImGui.Checkbox('show icons', state.icons)
    textc(COL.dim, 'Turn this off if the icons render as empty boxes on your build.')
    sep()

    section('record names')
    textc(state.browse.accessor and COL.ok or COL.dim,
        'id accessor: ' .. tostring(state.browse.accessor or 'not probed yet, open Browse'))
    textc(hasGlobal('GetLocalizedText') and COL.ok or COL.warn,
        'GetLocalizedText: ' .. (hasGlobal('GetLocalizedText') and 'present' or 'missing, names stay raw'))
    textc(COL.dim, 'Icons are not possible: ImGui needs a texture handle and CET exposes no loader for the game atlases.')
    sep()

    section('vehicle system')
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

    section('keybind')
    wrapped('CET does not allow a mod to ship a default key. Open the overlay, go to Bindings, find "Mikoshi: show menu", click the empty box, press the key you want, then Save.')
    textc(state.pinned and COL.ok or COL.dim,
        state.pinned and 'pinned: the menu stays on screen with the overlay shut'
                       or 'not pinned: the menu shows only while the overlay is open')
    textc(COL.dim, 'Clicking always needs the overlay open. CET only routes input to ImGui then.')
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
    local plain = not (state.fancy ~= false and caps.GetWindowDrawList
                   and caps.GetItemRectMin and caps.GetItemRectMax)
    local label = (plain and count) and (name .. '   ' .. count) or name
    if ImGui.Button(label .. '##nav' .. i, -1, 0) then state.tab = i end
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
    resolveApi()
    verifyAll()
    mod.ready = true
    note('Mikoshi ready. %s, %s.', api.setFactSrc or 'no fact API',
        api.journalOk and 'journal OK' or 'journal incomplete')
end)

registerForEvent('onOverlayOpen',  function() state.overlayOpen = true  end)
registerForEvent('onOverlayClose', function() state.overlayOpen = false end)

registerForEvent('onDraw', function()
    -- Pinned draws with the overlay shut, which is what the hotkey is for.
    if not mod.ready then return end
    if not (state.pinned or (state.overlayOpen and state.show)) then return end

    pushTheme()
    ImGui.SetNextWindowSize(640, 660, ImGuiCond.FirstUseEver)
    if ImGui.Begin('MIKOSHI') then

        banner()
        if not state.overlayOpen then
            textc(COL.warn, 'Overlay closed. The menu is readable but nothing in it will click.')
        end
        sep()

        -- Sidebar of categories, content on the right. The two children are
        -- sized to leave 30px for the status strip at the bottom.
        local okNav = caps.BeginChild and
            pcall(function() ImGui.BeginChild('fx_nav', 198, -30, true) end)
        if okNav then
            for i = 1, #TABS do
                navButton(i)
            end
            ImGui.EndChild()
            same()
        else
            -- No child windows on this build: fall back to a row of buttons.
            for i = 1, #TABS do
                if i > 1 then same() end
                if ImGui.Button(TABS[i] .. '##nav' .. i) then state.tab = i end
            end
            sep()
        end

        local okBody = caps.BeginChild and
            pcall(function() ImGui.BeginChild('fx_body', 0, -30, false) end)
        local fn = TAB_FN[state.tab]
        if fn then
            -- A crash inside one category must not take the window with it.
            local ok, err = pcall(fn)
            if not ok then textc(COL.bad, 'category error: ' .. tostring(err)) end
        end
        if okBody then ImGui.EndChild() end

        sep()
        statusStrip()
    end
    ImGui.End()
    -- Pops must happen whether or not Begin returned true, or the stack leaks
    -- a frame's worth of colours every time the window is collapsed.
    popTheme()
end)

registerForEvent('onShutdown', function()
    mod.ready = false
end)

-- Root level, outside any event: CET requires it there. CET does not let a mod
-- ship a default key, so this appears UNBOUND in the overlay's Bindings tab
-- until you assign one. Bindings > "Mikoshi: show menu" > click > press a key >
-- Save.
--
-- Pinning draws the window with the overlay shut, which is the point of having
-- a key at all. Clicking still needs the overlay, because CET only routes mouse
-- and keyboard into ImGui while it is open. That is a CET rule, not a choice.
registerHotkey('fixer_toggle', 'Mikoshi: show menu', function()
    state.pinned = not state.pinned
    if state.pinned then state.show = true end
end)

return mod

