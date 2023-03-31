-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libunitscan ]]--
-- A pfUI library that detects and saves all kind of unit related informations.
-- Such as level, class, elite-state and playertype. Each query causes the library
-- to automatically scan for the target if not already existing. Player-data is
-- persisted within the pfUI_playerDB where the mob data is a throw-away table.
-- The automatic target scanner is only working for vanilla due to client limitations
-- on further expansions.
--
-- External functions:
--   GetUnitData(name, active, explicitplayer)
--     Returns information of the given unitname. Returns nil if no match is found.
--     When nothing is found and the active flag is set, the autoscanner will
--     automatically pick it up and try to fill the missing entry by targetting the unit.
--     explicitplayer defines the order to search unit by name:
--       true or nil - search unit in player db first
--       false - search unit in mobs db first.
--
--     class[String] - The class of the unit
--     level[Number] - The level of the unit
--     elite[String] - The elite state of the unit (See UnitClassification())
--     player[Boolean] - Returns true if unit is a player
--     guild[String] - Returns guild name of unit is a player
--     npcinfo[String] - Returns additional npc info is a npc (Trainer, Merchant and other)
--
-- Internal functions:
--   libunitscan:AddData(db, name, class, level, elite)
--     Adds unit data to a given db. Where db should be either "players" or "mobs"
--

-- return instantly when another libunitscan is already active
if pfUI.api.libunitscan then return end

local units = { players = {}, mobs = {} }
local queue = { }
local npcscanner = libtipscan:GetScanner("libunitscan")

function GetUnitData(name, active, explicitplayer)
  local checkarray = {
    { db = "players", player = true},
    { db = "mobs", player = nil},
  }
  if explicitplayer == false then
    local first = checkarray[1]
    checkarray[1] = checkarray[2]
    checkarray[2] = first
  end

  for _, check in pairs(checkarray) do
    local ret = units[check.db][name]
    if ret then
      return ret.class, ret.level, ret.elite, check.player, ret.guild, ret.npcinfo
    end
  end

  if active then
    queue[name] = true
    libunitscan:Show()
  end
end

local function AddData(db, name, class, level, elite, guild, npcinfo)
  if not name or not db then return end
  units[db] = units[db] or {}
  units[db][name] = units[db][name] or {}
  units[db][name].class = class or units[db][name].class
  units[db][name].level = level or units[db][name].level
  units[db][name].elite = elite or units[db][name].elite
  units[db][name].guild = guild or units[db][name].guild
  units[db][name].npcinfo = npcinfo or units[db][name].npcinfo
  queue[name] = nil
end

local function GetNpcInfo(unit)
  if UnitPlayerControlled(unit) then
    -- exclude player pets
    return nil
  end

  npcscanner:SetUnit(unit)
  info = npcscanner:Line(2)

  if type(info) == "table" then
    info = table.unpack(info)
  end

  if info and string.find(info, "Level") then
    -- exclude poor npc information
    return nil
  end

  return info
end

local libunitscan = CreateFrame("Frame", "pfUnitScan", UIParent)
libunitscan:RegisterEvent("PLAYER_ENTERING_WORLD")
libunitscan:RegisterEvent("FRIENDLIST_UPDATE")
libunitscan:RegisterEvent("GUILD_ROSTER_UPDATE")
libunitscan:RegisterEvent("RAID_ROSTER_UPDATE")
libunitscan:RegisterEvent("PARTY_MEMBERS_CHANGED")
libunitscan:RegisterEvent("PLAYER_TARGET_CHANGED")
libunitscan:RegisterEvent("WHO_LIST_UPDATE")
libunitscan:RegisterEvent("CHAT_MSG_SYSTEM")
libunitscan:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
libunitscan:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then

    -- load pfUI_playerDB
    units.players = pfUI_playerDB

    -- update own character details
    local name = UnitName("player")
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local guild = GetGuildInfo("player")
    AddData("players", name, class, level, nil, guild)

  elseif event == "FRIENDLIST_UPDATE" then
    local name, class, level
    for i = 1, GetNumFriends() do
      name, level, class = GetFriendInfo(i)
      class = L["class"][class] or nil
      -- friendlist updates due to friend going off-line return level 0, let's not overwrite good older values
      level = level > 0 and level or nil
      AddData("players", name, class, level)
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    local name, class, level, _, guild
    for i = 1, GetNumGuildMembers() do
      name, _, _, level, class = GetGuildRosterInfo(i)
      guild = GetGuildInfo("player")
      class = L["class"][class] or nil
      AddData("players", name, class, level, nil, guild)
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    local name, class, SubGroup, level, _
    for i = 1, GetNumRaidMembers() do
      name, _, SubGroup, level, class = GetRaidRosterInfo(i)
      class = L["class"][class] or nil
      AddData("players", name, class, level)
    end

  elseif event == "PARTY_MEMBERS_CHANGED" then
    local name, class, level, unit, _, guild
    for i = 1, GetNumPartyMembers() do
      unit = "party" .. i
      _, class = UnitClass(unit)
      name = UnitName(unit)
      level = UnitLevel(unit)
      guild = GetGuildInfo(unit)
      AddData("players", name, class, level, nil, guild)
    end

  elseif event == "WHO_LIST_UPDATE" or event == "CHAT_MSG_SYSTEM" then
    local name, class, level, _
    for i = 1, GetNumWhoResults() do
      name, guild, level, _, class, _ = GetWhoInfo(i)
      class = L["class"][class] or nil
      AddData("players", name, class, level, nil, guild)
    end

  elseif event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
    local scan = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
    local name, class, level, elite, _
    if UnitIsPlayer(scan) then
      _, class = UnitClass(scan)
      level = UnitLevel(scan)
      name = UnitName(scan)
      guild = GetGuildInfo(scan)
      AddData("players", name, class, level, nil, guild)
    else
      _, class = UnitClass(scan)
      elite = UnitClassification(scan)
      level = UnitLevel(scan)
      name = UnitName(scan)
      npcinfo = GetNpcInfo(scan)
      AddData("mobs", name, class, level, elite, nil, npcinfo)
    end
  end
end)

-- since TargetByName can only be triggered within vanilla,
-- we can't auto-scan targets on further expansions.
if pfUI.client <= 11200 then
  -- setup sound function switches
  local SoundOn = PlaySound
  local SoundOff = function() return end

  libunitscan:SetScript("OnUpdate", function()
    -- don't scan when another unit is in target
    if UnitExists("target") or UnitName("target") then return end

    local name = next(queue)
    if name then
      -- disable sound
      _G.PlaySound = SoundOff

      -- try to target the unknown unit
      TargetByName(name, true)
      ClearTarget()

      -- enable sound again
      _G.PlaySound = SoundOn

      queue[name] = nil
    end

    this:Hide()
  end)
end

pfUI.api.libunitscan = libunitscan
