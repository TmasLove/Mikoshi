--[[
  questfix_probe - a throwaway CET mod that answers "what actually exists on this
  install?" and nothing else. It changes no game state.

  Why this exists: almost every quest-fix snippet circulating on Reddit and
  YouTube was written for patch 1.x. Patch 2.x renamed, moved or deleted a lot of
  it, and a wrong TweakDB id fails SILENTLY - TweakDBID.new() hashes any string
  you hand it, valid or not, so constructing one proves nothing. The only honest
  test is asking the live TweakDB for the record.

  Install:
    copy this folder to
    <game>\bin\x64\plugins\cyber_engine_tweaks\mods\questfix_probe\
    then launch the game, open the CET overlay, and read the console.
    Delete the folder when done.
]]

local probe = {}

-- Every probe runs inside pcall: a missing function must be REPORTED, never
-- raised, or the first failure hides every result after it.
local function try(label, fn)
    local ok, res = pcall(fn)
    if not ok then
        print(string.format('  [ERR ] %-42s %s', label, tostring(res)))
        return nil, false
    end
    print(string.format('  [ %s ] %-42s %s',
        res ~= nil and 'ok ' or 'nil', label, tostring(res)))
    return res, res ~= nil
end

-- Item and record ids to confirm before any of them go in the real menu.
-- Source: community lists, UNVERIFIED. Expect some of these to come back nil.
local CANDIDATE_RECORDS = {
    'Items.money',                          -- control: this one must exist
    'Items.PerkPointSkillbook',             -- control: used from the console already
    'Items.ma_wat_kab_08_onscreen_01',      -- Lt. Mower shard
    'Items.ma_wat_kab_02_onscreen_01',      -- Demons of War shard
    'Items.ma_wbr_hil_01_onscreen_01',      -- Six Feet Under shard
    'Items.ma_wat_lch_06_onscreen_01',      -- Where the Bodies Hit the Floor shard
    'Items.ma_wat_nid_01_onscreen_01',      -- Blood Ritual shard
    'Items.ma_std_rcr_11_onscreen_01',      -- Discount Doc shard
}

registerForEvent('onInit', function()
    print('')
    print('=========== questfix probe ===========')

    print('[1] quest / fact api')
    try('Game.GetQuestsSystem()', function() return Game.GetQuestsSystem() end)
    try('  :SetFactStr exists', function()
        local qs = Game.GetQuestsSystem()
        return qs and type(qs.SetFactStr) ~= 'nil' and 'callable' or nil
    end)
    try('  :GetFactStr exists', function()
        local qs = Game.GetQuestsSystem()
        return qs and type(qs.GetFactStr) ~= 'nil' and 'callable' or nil
    end)
    -- read-only sample: a fact that is 0 on a fresh game is still a valid read
    try('  :GetFactStr("ig_phone_manager_off")', function()
        return Game.GetQuestsSystem():GetFactStr('ig_phone_manager_off')
    end)
    try('Game.SetFactStr (global shorthand)', function()
        return type(Game.SetFactStr) ~= 'nil' and 'callable' or nil
    end)

    print('[2] journal api')
    try('Game.GetJournalManager()', function() return Game.GetJournalManager() end)
    -- Fetched through pcall too: if this call throws rather than returning nil,
    -- an unprotected version would kill onInit and hide every probe below it.
    local okJm, jm = pcall(function() return Game.GetJournalManager() end)
    if not okJm then jm = nil end
    for _, m in ipairs({ 'GetTrackedEntry', 'GetParentEntry', 'GetEntryHash',
                         'ChangeEntryStateByHash', 'GetEntryState' }) do
        try('  :' .. m, function()
            return jm and type(jm[m]) ~= 'nil' and 'callable' or nil
        end)
    end
    try('  :GetTrackedEntry() right now', function()
        return jm and jm:GetTrackedEntry() end)

    print('[3] journal state enum (do NOT ship magic numbers)')
    for _, n in ipairs({ 'Succeeded', 'Failed', 'Active', 'Inactive' }) do
        try('gameJournalEntryState.' .. n, function()
            return gameJournalEntryState[n] end)
    end
    for _, n in ipairs({ 'Notify', 'DoNotNotify' }) do
        try('JournalNotifyOption.' .. n, function()
            return JournalNotifyOption[n] end)
    end

    print('[4] tweakdb record check (the only real id test)')
    for _, id in ipairs(CANDIDATE_RECORDS) do
        try(id, function()
            local r = TweakDB:GetRecord(id)
            return r and 'record present' or nil
        end)
    end

    print('[5] environment')
    try('json module', function()
        local j = require('json'); return j and 'loaded' or nil end)
    try('mod can write its own folder', function()
        local f = io.open('probe_touch.txt', 'w')
        if not f then return nil end
        f:write('ok'); f:close(); return 'yes'
    end)

    print('======= end of questfix probe =========')
    print('Copy the console output back to the handoff before writing the menu.')
    print('')
end)

return probe
