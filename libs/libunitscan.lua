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


-- TODO: the problem - distance for similar units
function GetUnitData(name, active, explicitplayer)
  local dbarray = { "players", "mobs" }
  if explicitplayer == false then
    dbarray = { "mobs", "players" }
  end

  local ret = nil
  for _, db in pairs(dbarray) do
    ret = units[db][name]
    if ret then
      break
    end
  end

  local curtime = GetTime()
  if (ret and ret.time and curtime - ret.time > 1) or (not ret and active) or not ret.time then
    if ret then
      ret.time = curtime
    end
    queue[name] = true
    libunitscan:Show()
  end
  if ret then
    return ret.class, ret.level, ret.elite, ret.player, ret.guild, ret.distance, ret.npcinfo
  end
end

local function AddData(db, name, class, level, elite, guild, distance, npcinfo)
  if not name or not db then return end
  units[db] = units[db] or {}
  units[db][name] = units[db][name] or {}
  units[db][name].player = db == "player"
  units[db][name].class = class or units[db][name].class
  units[db][name].level = level or units[db][name].level
  units[db][name].elite = elite or units[db][name].elite
  units[db][name].guild = guild or units[db][name].guild
  units[db][name].distance = distance or units[db][name].distance
  units[db][name].npcinfo = npcinfo or units[db][name].npcinfo
  queue[name] = nil
end

RESCAN_TIMEOUT = 1
NAME_GROUP_LIMIT = 10

PLAYER_TYPE = "PLAYER_TYPE"
MOB_TYPE = "MOB_TYPE"

DISTANCE_OVER_30 = 30
DISTANCE_OVER_10 = 10
DISTANCE_OVER_0 = 0
local function GetDistance(unit)
  local distance = {}
  distance.change_time = GetTime()
  if CheckInteractDistance(unit, 4) then
    if CheckInteractDistance(unit, 2) then
      distance.value = DISTANCE_OVER_0
    else
      distance.value = DISTANCE_OVER_10
    end
  else
    distance.value = DISTANCE_OVER_30
  end
  return distance
end

local function GetNpcInfo(unit)
  if UnitPlayerControlled(unit) then
    -- exclude player pets
    return nil
  end

  npcscanner:SetUnit(unit)
  for i = 2,3 do
    local info = npcscanner:Line(i)
    if info then
      if type(info) == "table" then
        info = table.unpack(info)
      end

      if not string.find(info, "Level") then
        -- exclude poor npc information
        return info
      end
    end
  end
end


local pf_units = {}
local pf_units_by_names = {}

local pf_units_to_scan = {}

local function AddToScan(unit, active)
  if active then
    pf_units_to_scan[unit.name] = pf_units_by_names[unit.name] or {}
    libunitscan:Show()
  end
end

local scan_debug = 10

RegisterSlashCommand("SCANTEST", { "/sd" }, function(msg)
  print(msg)
  if msg == "d" then
    print("pf_units begin -----------------------------------------------------------")
    for name, units in pairs(pf_units_by_names) do
      for i, unit in pairs(units) do
        DebugPrint(1,
                string.format("[%-3d] [n=%-21s]", i, unit.name and string.sub(unit.name, 0, 10) or "nil"),
                PfUnit:ToString(unit))
      end
    end
    print("pf_units end -----------------------------------------------------------")
  else
    scan_debug = tonumber(msg)
  end
end)


PfUnit = {
  -- common
  name = "",
  type = nil,
  class = nil,
  level = nil,
  hp_max = nil,
  mana_max = nil,

  -- player
  guild = nil,

  -- npc
  elite = nil,
  npc_info = nil,

  -- tmp
  distance = nil,
}

function PfUnit:New()
  return {}
end

function PfUnit:ToString(unit)
  return string.format("[%s] [n=%-25s] [T=%-3s] [c=%-7s] [l=%-7d] [h=%-10d] [m=%-10d] [g=%-14s] [e=%-7s] [i=%-14s] [d=%-7d] [t=%-7d]",
          tostring(unit),
          unit.name and string.sub(unit.name, 0, 25) or "nil",
          unit.type and string.sub(unit.type, 0, 1) or "nil",
          unit.class and string.sub(unit.class, 0, 3) or "nil",
          unit.level or -1,
          unit.hp_max or -1,
          unit.mana_max or -1,
          unit.guild and string.sub(unit.guild, 0, 10) or "nil",
          unit.elite == nil and "n" or string.sub(tostring(unit.elite), 0, 1),
          unit.npc_info and string.sub(unit.npc_info, 0, 10) or "nil",
          unit.distance and unit.distance.value or -1,
          unit.distance and unit.distance.change_time or -1
  )
end

local function GetPfUnit(unit, add_in_not_found)
  local found_by_name = pf_units_by_names[unit.name]

  if found_by_name then
    for _, found_unit in pairs(found_by_name) do
      if
              (not unit.type or found_unit.type == unit.type) and
              (not unit.class or found_unit.class == unit.class) and
              (not unit.level or found_unit.level == unit.level) and
              (not unit.hp_max or found_unit.hp_max == unit.hp_max) and
              -- (not unit.guild or found_unit.guild == unit.guild) and
              (not unit.elite or found_unit.elite == unit.elite) and
              (not unit.npc_info or found_unit.npc_info == unit.npc_info) and
              (not unit.mana_max or found_unit.mana_max == unit.mana_max) and
              true then
        return found_unit
      end
    end
  end

  if add_in_not_found then

    DebugPrint(scan_debug >= 40, count, PfUnit:ToString(unit), "ADDED")
    pf_units[unit] = true
    pf_units_by_names[unit.name] = pf_units_by_names[unit.name] or {}
    local name_group = pf_units_by_names[unit.name]
    local count = 0
    for _, _ in pairs(name_group) do
      count = count + 1
    end
    if count >= NAME_GROUP_LIMIT then
      local remove_unit = table.remove(name_group, 1)
      DebugPrint(scan_debug >= 30, count, PfUnit:ToString(remove_unit), "REMOVED")
      pf_units[remove_unit] = nil
    end

    table.insert(name_group, unit)
    return unit
  end

  return nil
end

function FindPfUnit(unit, active)
  local found_unit = GetPfUnit(unit)

  if not found_unit then
    DebugPrint(scan_debug >= 70, count, PfUnit:ToString(unit), "NOT_FOUND_SCAN")
    AddToScan(unit, active)
  else
    local current_time = GetTime()
    if current_time - found_unit.distance.change_time > RESCAN_TIMEOUT then
      DebugPrint(scan_debug >= 70, count, PfUnit:ToString(unit), "TIMEOUT_SCAN")
      -- To prevent infinity loop create unavailable distance before real scan to set change_time
      found_unit.distance.change_time = GetTime()
      AddToScan(unit, active)
    end
  end

  return found_unit
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
    -- TODO: enable it
    -- units.players = pfUI_playerDB

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

    local _
    local unit = PfUnit:New()
    unit.name = UnitName(scan)
    if not unit.name or UnitIsDead(scan) then
      return
    end

    unit.type = UnitIsPlayer(scan) and PLAYER_TYPE or MOB_TYPE
    _, unit.class = UnitClass(scan)
    unit.level = UnitLevel(scan)
    unit.hp_max = UnitHealthMax(scan)
    unit.mana_max = UnitManaMax(scan)
    if unit.type == PLAYER_TYPE then
      unit.guild = GetGuildInfo(scan)
    else
      unit.elite = UnitClassification(scan)
      unit.npc_info = GetNpcInfo(scan)
    end

    unit = GetPfUnit(unit, true)
    old_distance = unit.distance
    unit.distance = GetDistance(scan)
    DebugPrint(scan_debug >= 42 and (not old_distance or old_distance.value ~= unit.distance.value),
            count, PfUnit:ToString(unit), "UPDATE")
    DebugPrint(scan_debug >= 60, PfUnit:ToString(unit), "SCANNED")
  end
end)

local SCAN_LIMIT_WARNING = 5
local pf_units_scan_debug = {}
local period_time = GetTime()
local function PfUnitsDebug(unit_name)
  pf_units_scan_debug[unit_name] = pf_units_scan_debug[unit_name] or 0
  pf_units_scan_debug[unit_name] = pf_units_scan_debug[unit_name] + 1
  current_time = GetTime()
  if current_time - period_time >= 1 then
    local all_count = 0
    for it_name, it_count in pairs(pf_units_scan_debug) do
      all_count = all_count + it_count
      if it_count >= SCAN_LIMIT_WARNING then
        DebugPrint(scan_debug >= 10, it_name, "SCAN_LIMIT_WARNING", it_count)
      end

      DebugPrint(scan_debug >= 50, it_name, "SCAN_STAT", it_count)
    end
    DebugPrint(scan_debug >= 45, "ALL", "SCAN_STAT", all_count)
    pf_units_scan_debug = {}
    period_time = current_time
  end
end

local function UpdateTarget(unit_name)
  local SoundOn = PlaySound
  local SoundOff = function() return end

  -- disable sound
  _G.PlaySound = SoundOff
  -- UIErrorsFrame:Hide()

  -- try to target the unknown unit
  last_name = UnitName("target")
  TargetByName(unit_name, true)
  if last_name then
    TargetLastTarget()
    if UnitName("target") ~= last_name then
      print(UnitName("target"))
      TargetByName(last_name, true)
    end
  else
    ClearTarget()
  end

  -- enable sound again
  _G.PlaySound = SoundOn
  -- UIErrorsFrame:Show()
end

-- since TargetByName can only be triggered within vanilla,
-- we can't auto-scan targets on further expansions.
if pfUI.client <= 11200 then
  -- setup sound function switches

  libunitscan:SetScript("OnUpdate", function()
    -- don't scan when another unit is in target
    -- if UnitExists("target") or UnitName("target") then return end
    if UnitAffectingCombat("player") or UnitIsEnemy("target", "player") then
      return
    end

    local unit_name, units = next(pf_units_to_scan)
    if units then
      for _, unit in pairs(units) do
        DebugPrint(scan_debug >= 60, PfUnit:ToString(unit), "SCAN")
      end
    end
    if unit_name then
      PfUnitsDebug(unit_name)
      UpdateTarget(unit_name)
      pf_units_to_scan[unit_name] = nil
    end
    --
    --local name = next(queue)
    --if name then
    --  -- print("SCAN "..name)
    --
    --  -- disable sound
    --  _G.PlaySound = SoundOff
    --
    --  -- try to target the unknown unit
    --  TargetByName(name, true)
    --  ClearTarget()
    --
    --  -- enable sound again
    --  _G.PlaySound = SoundOn
    --
    --  queue[name] = nil
    --end

    this:Hide()
  end)
end

pfUI.api.libunitscan = libunitscan
