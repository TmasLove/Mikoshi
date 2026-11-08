--[[
  data.lua - the catalog. This is the file to edit when you want to add a fix.
  It holds no logic and calls nothing, so a typo here cannot break the menu.

  VERIFICATION. Every `record` string is checked against the live TweakDB when
  the mod loads. Anything the game does not recognise is shown greyed out and
  labelled, never fired blindly. Fact names cannot be verified this way (the
  quest system will happily read a fact that has never existed and return 0), so
  facts are marked by hand below:

    verified = true   confirmed working on game 2.5
    verified = false  community-reported, mostly patch 1.x era, treat as a lead
]]

return {

  -- ========================================================================
  -- EVERYDAY: the things you actually want at 2am without opening the console
  -- ========================================================================
  everyday = {
    -- loop = true: these hand over exactly one per call and ignore the
    -- quantity argument. Confirmed in game: asking for 5 perk points gave 1.
    { label = 'Eddies',            record = 'Items.money',                   default = 10000, step = 5000 },
    { label = 'Perk points',       record = 'Items.PerkPointSkillbook',      default = 5,     step = 1, loop = true },
    { label = 'Attribute points',  record = 'Items.AttributePointSkillbook', default = 1,     step = 1, loop = true },
    { label = 'Relic points',      record = 'Items.RelicPointSkillbook',     default = 1,     step = 1, loop = true,
      note = 'Phantom Liberty only.' },
    { label = 'Carry capacity shard', record = 'Items.CarryCapacityBooster', default = 1,  step = 1, loop = true },
  },

  -- Experience is a function call rather than an item, so it is handled
  -- separately. `kind` tells init.lua which path to take.
  exp = {
    { label = 'Street Cred', kind = 'exp', arg = 'StreetCred', default = 1000, step = 500 },
    { label = 'Level (XP)',  kind = 'exp', arg = 'Level',      default = 1000, step = 500 },
  },

  -- ========================================================================
  -- AMMO. Every id below is unconfirmed until the game checks it at load.
  -- ========================================================================
  -- CORRECTED 2026-11-07. These were shipped as "Items.HandgunAmmo" and that
  -- prefix is wrong: ammo lives under Ammo., per the official wiki's own
  -- frequently-required-items list. The TweakDB check would have caught it at
  -- load and greyed all five out.
  ammo = {
    { label = 'Handgun ammo',   record = 'Ammo.HandgunAmmo',     default = 500, step = 100 },
    { label = 'Rifle ammo',     record = 'Ammo.RifleAmmo',       default = 700, step = 100 },
    { label = 'Shotgun shells', record = 'Ammo.ShotgunAmmo',     default = 100, step = 50 },
    { label = 'Sniper rounds',  record = 'Ammo.SniperRifleAmmo', default = 100, step = 50 },
  },

  -- ========================================================================
  -- CONSUMABLES
  -- ========================================================================
  healing = {
    { label = 'Medkit, common',   record = 'Items.FirstAidWhiteOne',   default = 10, step = 5 },
    { label = 'Medkit, uncommon', record = 'Items.FirstAidWhiteTwo',   default = 10, step = 5 },
    { label = 'Medkit, rare',     record = 'Items.FirstAidWhiteThree', default = 10, step = 5 },
    { label = 'MaxDoc, rare',     record = 'Items.CPO_MaxDoc',         default = 10, step = 5 },
    { label = 'Bounce Back, rare',record = 'Items.CPO_BounceBack',     default = 10, step = 5 },
  },

  -- ========================================================================
  -- CRAFTING MATERIALS
  -- ========================================================================
  crafting = {
    { label = 'Common components',    record = 'Items.CommonMaterial1',    default = 500, step = 100 },
    { label = 'Uncommon components',  record = 'Items.UncommonMaterial1',  default = 500, step = 100 },
    { label = 'Rare components',      record = 'Items.RareMaterial1',      default = 500, step = 100 },
    { label = 'Epic components',      record = 'Items.EpicMaterial1',      default = 300, step = 50 },
    { label = 'Legendary components', record = 'Items.LegendaryMaterial1', default = 100, step = 25 },
    { label = 'Quickhack, uncommon',  record = 'Items.QuickHackUncommonMaterial1',  default = 500, step = 100 },
    { label = 'Quickhack, rare',      record = 'Items.QuickHackRareMaterial1',      default = 500, step = 100 },
    { label = 'Quickhack, epic',      record = 'Items.QuickHackEpicMaterial1',      default = 300, step = 50 },
    { label = 'Quickhack, legendary', record = 'Items.QuickHackLegendaryMaterial1', default = 100, step = 25 },
  },

  -- ========================================================================
  -- THE 17 CYBERPSYCHO SIGHTINGS, ids and names verbatim from the RED Modding
  -- quest-id reference. District is read off the id code: bls=Badlands,
  -- cct=City Center, hey=Heywood, pac=Pacifica, std=Santo Domingo, wat=Watson.
  --
  -- This list also corrected three ids I had shipped from a community list:
  -- Six Feet Under is wat_nid_22 (I had wbr_hil_01), Bloody Ritual is
  -- wat_nid_15 (I had wat_nid_01), and the "unidentified" wat_lch_06 is
  -- Ticket to the Major Leagues.
  -- ========================================================================
  cyberpsychos = {
    { id = 'ma_wat_kab_02',     name = 'Demons of War',                 district = 'Watson, Kabuki' },
    { id = 'ma_wat_kab_08',     name = 'Lt. Mower',                     district = 'Watson, Kabuki' },
    { id = 'ma_wat_lch_06',     name = 'Ticket to the Major Leagues',   district = 'Watson, Little China' },
    { id = 'ma_wat_nid_03',     name = 'Where the Bodies Hit the Floor',district = 'Watson, Northside' },
    { id = 'ma_wat_nid_15',     name = 'Bloody Ritual',                 district = 'Watson, Northside' },
    { id = 'ma_wat_nid_22',     name = 'Six Feet Under',                district = 'Watson, Northside' },
    { id = 'ma_hey_spr_04',     name = 'Seaside Cafe',                  district = 'Heywood, Wellsprings' },
    { id = 'ma_hey_spr_06',     name = 'Letter of the Law',             district = 'Heywood, Wellsprings' },
    { id = 'ma_cct_dtn_03',     name = 'On Deaf Ears',                  district = 'City Center, Downtown' },
    { id = 'ma_cct_dtn_07',     name = 'Phantom of Night City',         district = 'City Center, Downtown' },
    { id = 'ma_pac_cvi_08',     name = 'Smoke on the Water',            district = 'Pacifica, Coastview' },
    { id = 'ma_pac_cvi_15',     name = 'Lex Talionis',                  district = 'Pacifica, Coastview' },
    { id = 'ma_std_arr_06',     name = 'Under the Bridge',              district = 'Santo Domingo, Arroyo' },
    { id = 'ma_std_rcr_11',     name = 'Discount Doc',                  district = 'Santo Domingo, Rancho Coronado' },
    { id = 'ma_bls_ina_se1_07', name = 'The Wasteland',                 district = 'Badlands' },
    { id = 'ma_bls_ina_se1_08', name = 'House on a Hill',               district = 'Badlands' },
    { id = 'ma_bls_ina_se1_22', name = 'Second Chances',                district = 'Badlands, Inland Avenue' },
  },

  -- ========================================================================
  -- TELEPORT. Coordinates lifted verbatim from the RED Modding wiki's
  -- teleport-locations table. The CALL they are passed to is the current
  -- teleportation facility, not the deprecated helper that page documents.
  --
  -- The wiki's own warning, worth repeating: teleporting into an otherwise
  -- sealed area can leave you unable to walk out. Save your spot first, which
  -- is what the "where I am now" button above the list is for.
  -- ========================================================================
  places = {
    { label = "V's Mansion",        x = -1341.383545, y = 1242.970337, z = 111.100006 },
    { label = 'Konpeki Plaza',      x = -2229.413818, y = 1769.449707, z = 21.000000 },
    { label = 'Peralez apartment',  x = -75.815399,   y = -113.607819, z = 111.161728 },
    { label = 'Akulov penthouse',   x = -1218.135986, y = 1409.635010, z = 113.524445 },
    { label = 'Nomad start, outside the city', x = -3235.881592, y = -6146.751465, z = 96.834175 },
    { label = 'Badlands tunnel',    x = -1255.622437, y = 126.991272,  z = -43.753677 },
    { label = 'Badlands tunnel entrance', x = 185.345749, y = 2365.449707, z = 67.081177 },
  },

  -- ========================================================================
  -- ATTRIBUTES. Only "Strength" (Body) appears verbatim in the documentation.
  -- The other four are the obvious readings of the in-game names and are
  -- marked accordingly, so a silent no-op is expected rather than surprising.
  -- ========================================================================
  attributes = {
    { label = 'Body',              arg = 'Strength',         verified = true },
    { label = 'Reflexes',          arg = 'Reflexes',         verified = false },
    { label = 'Technical Ability', arg = 'TechnicalAbility', verified = false },
    { label = 'Intelligence',      arg = 'Intelligence',     verified = false },
    { label = 'Cool',              arg = 'Cool',             verified = false },
  },

  -- ========================================================================
  -- ICONICS people ask for by name. Documented on the wiki.
  -- ========================================================================
  iconics = {
    { label = "Johnny's Samurai jacket", record = 'Items.SQ031_Samurai_Jacket', default = 1, step = 1 },
  },

  -- ========================================================================
  -- STORY FACTS. These change the plot. Every one is read before it is
  -- written, so the Undo tab can put it back, but the consequences downstream
  -- are not something an undo can reach.
  -- ========================================================================
  -- storyFacts removed: Johnny relationship, Skippy mode and the Takemura
  -- flag all change the plot rather than repair it, and no undo reaches what
  -- the story does next because of them.


  -- ========================================================================
  -- WEATHER. Passed to the weather system by name. The system itself is
  -- capability-checked at load; these state names are not, so a wrong one
  -- simply does nothing.
  -- ========================================================================
  weather = {
    { label = 'Sunny',        state = '24h_weather_sunny' },
    { label = 'Light clouds', state = '24h_weather_light_clouds' },
    { label = 'Cloudy',       state = '24h_weather_cloudy' },
    { label = 'Rain',         state = '24h_weather_rain' },
    { label = 'Toxic rain',   state = '24h_weather_toxic_rain' },
    { label = 'Pollution',    state = '24h_weather_pollution' },
    { label = 'Fog',          state = '24h_weather_fog' },
    { label = 'Sandstorm',    state = '24h_weather_sandstorm' },
  },

  -- ========================================================================
  -- SHARDS: cyberpsycho and gig shards that fail to spawn on the body.
  -- Granting the shard is what unsticks the objective in most reports.
  --
  -- Granting it is not reading it. These objectives want the shard READ, so
  -- open it in the journal afterwards.
  --
  -- Finding an id: search the quest prefix in the CET TweakDB Editor, e.g.
  -- "wat_nid_03", and read the whole family. Do NOT guess by incrementing a
  -- number and do NOT search the shard's displayed title. See the three
  -- lessons recorded further down this section.
  -- ========================================================================
  shards = {
    { label = 'Lt. Mower',                      record = 'Items.ma_wat_kab_08_onscreen_01' },
    { label = 'Demons of War (Matt Liaw)',      record = 'Items.ma_wat_kab_02_onscreen_01' },
    -- 2026-11-08, read off the live TweakDB rather than off a list: _01 is
    -- not on 2.5 and _02 is the ONLY ma_wat_nid_22 shard that is. So the
    -- suffix is _02 here, even though _02 was the wrong guess for kab_08.
    -- That is the whole point of checking each one against the game.
    { label = 'Six Feet Under (Lely Hein)',     record = 'Items.ma_wat_nid_22_onscreen_02',
      note = 'District corrected to wat_nid_22, and the suffix read off this build: _01 does not exist on 2.5, _02 is the only one that does.' },
    -- Where the Bodies Hit the Floor needs TWO conversations read:
    -- "Hoof and Sanders" and "Brick and Ellis". Confirmed working in game
    -- 2.5 on 2026-11-07:
    { label = 'Where the Bodies Hit the Floor: Brick and Ellis',
      record = 'Items.ma_wat_nid_03_brick_and_elly_conversation',
      note = 'Confirmed readable in game 2.5. Grant both shards for this quest and read both.' },
    { label = 'Where the Bodies Hit the Floor: Hoof and Sanders',
      record = 'Items.ma_wat_nid_03_go_clean_after_elly',
      note = 'Confirmed readable in game 2.5. The id does not resemble the shard title at all.' },

    -- THREE THINGS THIS QUEST TAUGHT US, which apply to every lookup below:
    --
    -- 1. The ids are descriptive, not numbered. "..._brick_and_elly_conversation",
    --    not "..._onscreen_02". Guessing the next number finds nothing.
    -- 2. The id often has NOTHING to do with the displayed title. "Brick and
    --    Ellis" is stored as "brick_and_elly", a misspelling you could guess,
    --    but "Hoof and Sanders" is stored as "go_clean_after_elly", which you
    --    could not. Searching by shard title is a dead end. Search the quest
    --    prefix in the TweakDB Editor and read the whole family.
    -- 3. The district code in the community list was simply wrong. This quest
    --    is wat_nid (Northside) 03, not wat_lch 06. Which means the entry
    --    below, taken from that same list, is probably a different quest's
    --    shard that happens to be readable.
    { label = 'Ticket to the Major Leagues',
      record = 'Items.ma_wat_lch_06_onscreen_01',
      note = 'Identified: wat_lch_06 is this sighting, not Where the Bodies Hit the Floor as the community list claimed.' },
    -- Bloody Ritual. _01 is not on 2.5, and the live TweakDB holds THREE
    -- ma_wat_nid_15 shards. Nothing in an id says which one carries readable
    -- text -- "go_clean_after_elly" above is the standing proof of that -- so
    -- all three are offered instead of one being picked and quietly being the
    -- wrong one for the third time in this file.
    { label = 'Bloody Ritual (psycho)',
      record = 'Items.ma_wat_nid_15_onscreen_psycho',
      note = 'One of three ma_wat_nid_15 shards on this build. Likeliest of the three for a cyberpsycho sighting. If it reads blank, try the other two.' },
    { label = 'Bloody Ritual (mls)',
      record = 'Items.ma_wat_nid_15_onscreen_mls',
      note = 'One of three ma_wat_nid_15 shards on this build. Try this if the psycho one reads blank.' },
    { label = 'Bloody Ritual (02)',
      record = 'Items.ma_wat_nid_15_onscreen_02',
      note = 'One of three ma_wat_nid_15 shards on this build. The plain numbered suffix, which is the one that rendered blank for kab_08.' },
    { label = 'Discount Doc (Chase Coley)',     record = 'Items.ma_std_rcr_11_onscreen_01' },
  },

  -- ========================================================================
  -- QUEST FACTS: every one of these is a read-before-write, so the Undo tab
  -- can put the old value back. Safe to experiment with.
  -- ========================================================================
  facts = {
    {
      label = 'Unstick phone calls',
      fact = 'ig_phone_manager_off', value = 0, verified = false,
      note = 'For when Takemura or a fixer never rings. Sets the phone manager back on.',
    },
    {
      label = 'Skippy: trigger "Machine Gun" return',
      fact = 'mq007_skippy_goes_emo', value = 1, verified = false,
      note = 'Forces Skippy\'s follow-up quest to become available.',
    },
    {
      label = 'Letter of the Law: mark email read',
      fact = 'ma_hey_spr_06_mail_read', value = 1, verified = false,
      note = 'The terminal email that fails to register as read.',
    },
  },

  -- Templates the user fills in. The {n} / {prefix} placeholders are replaced
  -- by the UI before anything is written.
  templates = {
    {
      label = 'Fixer tier unlock',
      pattern = 'sts_{district}_tier_{n}', value = 1, verified = false,
      fields = { { key = 'district', hint = 'wat_kab, wbr_hil, std_rcr ...' },
                 { key = 'n',        hint = '1 to 4' } },
      note = 'When a fixer\'s next tier refuses to unlock after finishing their gigs.',
    },
    {
      label = 'Gig counter sync',
      pattern = '{gig}_finished', value = 1, verified = false,
      fields = { { key = 'gig', hint = 'internal gig id, e.g. ina_05' } },
      note = 'Gig shows complete in the journal but does not count toward the fixer total.',
    },
  },
}
