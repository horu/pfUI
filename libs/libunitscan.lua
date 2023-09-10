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
--   GetUnitData(name, active)
--     Returns information of the given unitname. Returns nil if no match is found.
--     When nothing is found and the active flag is set, the autoscanner will
--     automatically pick it up and try to fill the missing entry by targetting the unit.
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

-- To remove faction names from npc info
local useless_npcinfo_list = {
  "s Pet",
  "s Minion",
  "Level",
}

local factionlist = { }
local function UpdateFactionList()
  for factionIndex = 1, GetNumFactions() do
    name = GetFactionInfo(factionIndex)
    factionlist[name] = true
  end
end

function GetUnitData(name, active)
  if units["players"][name] then
    local ret = units["players"][name]
    return ret.class, ret.level, ret.elite, true, ret.guild, nil, ret.playerinfo
  elseif units["mobs"][name] then
    local ret = units["mobs"][name]
    return ret.class, ret.level, ret.elite, nil, nil, ret.npcinfo
  elseif active then
    queue[name] = true
    libunitscan:Show()
  end
end

local function AddData(db, name, class, level, elite, guild, npcinfo, playerinfo)
  if not name or not db then return end
  units[db] = units[db] or {}
  units[db][name] = units[db][name] or {}
  units[db][name].class = class or units[db][name].class
  units[db][name].level = level or units[db][name].level
  units[db][name].elite = elite or units[db][name].elite
  units[db][name].guild = guild or units[db][name].guild
  units[db][name].npcinfo = npcinfo or units[db][name].npcinfo
  units[db][name].playerinfo = playerinfo or units[db][name].playerinfo
  queue[name] = nil
end

local function GetPlayerInfo(unit)
  if UnitIsPVP(unit) then
    return "pvp"
  end

  local _, guildRank = GetGuildInfo(unit)
  return guildRank
end

local function GetNpcInfo(unit)
  if UnitPlayerControlled(unit) then
    -- exclude player pets
    return
  end

  npcscanner:SetUnit(unit)
  local info = npcscanner:Line(2)
  if not info then
    return
  end

  if type(info) == "table" then
    info = (info[1] or "") .. (info[2] or "")
  end

  if factionlist[info] then
    -- exclude useless npc information about faction
    return
  end

  for _, useless_info in pairs(useless_npcinfo_list) do
    -- exclude useless npc information
    if string.find(info, useless_info) then
      return
    end
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
libunitscan:RegisterEvent("UPDATE_FACTION")
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
    local name, class, level, elite, guild, npcinfo, _
    if UnitIsPlayer(scan) then
      _, class = UnitClass(scan)
      level = UnitLevel(scan)
      name = UnitName(scan)
      guild = GetGuildInfo(scan)
      local playerinfo = GetPlayerInfo(scan)
      AddData("players", name, class, level, nil, guild, nil, playerinfo)
    else
      _, class = UnitClass(scan)
      elite = UnitClassification(scan)
      level = UnitLevel(scan)
      name = UnitName(scan)
      if not UnitIsEnemy(scan, "player") then
        npcinfo = GetNpcInfo(scan)
      end
      AddData("mobs", name, class, level, elite, nil, npcinfo)
    end
  elseif event == "UPDATE_FACTION" then
    UpdateFactionList()
  end
end)

-- since TargetByName can only be triggered within vanilla,
-- we can't auto-scan targets on further expansions.
if pfUI.client <= 11200 then
  -- setup ui function switches
  local Off = function() end
  local SoundOn = PlaySound
  local UiErrorOn = UIErrorsFrame.AddMessage

  libunitscan:SetScript("OnUpdate", function()
    -- don't scan when another unit is in target
    if UnitExists("target") or UnitName("target") then return end

    -- setup target function switches
    local targetFrame = pfUI.uf.target or TargetFrame
    local TargetOn = targetFrame.Show

    local name = next(queue)
    if name then
      -- disable sound/error messages/target frame
      _G.PlaySound = Off
      UIErrorsFrame.AddMessage = Off
      targetFrame.Show = Off

      -- try to target the unknown unit
      TargetByName(name, true)
      ClearTarget()

      -- enable sound/error messages/target frame
      _G.PlaySound = SoundOn
      UIErrorsFrame.AddMessage = UiErrorOn
      targetFrame.Show = TargetOn

      queue[name] = nil
    end

    this:Hide()
  end)
end

pfUI.api.libunitscan = libunitscan
