local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.Data = CS.Data or {}
local Data = CS.Data

local GEAR_SLOTS = {
  { slotID = 1, token = "HeadSlot" },
  { slotID = 2, token = "NeckSlot" },
  { slotID = 3, token = "ShoulderSlot" },
  { slotID = 4, token = "ShirtSlot" },
  { slotID = 5, token = "ChestSlot" },
  { slotID = 6, token = "WaistSlot" },
  { slotID = 7, token = "LegsSlot" },
  { slotID = 8, token = "FeetSlot" },
  { slotID = 9, token = "WristSlot" },
  { slotID = 10, token = "HandsSlot" },
  { slotID = 11, token = "Finger0Slot" },
  { slotID = 12, token = "Finger1Slot" },
  { slotID = 13, token = "Trinket0Slot" },
  { slotID = 14, token = "Trinket1Slot" },
  { slotID = 15, token = "BackSlot" },
  { slotID = 16, token = "MainHandSlot" },
  { slotID = 17, token = "SecondaryHandSlot" },
  { slotID = 19, token = "TabardSlot" },
}

local PRIMARY_STAT_BY_CLASS = {
  DEATHKNIGHT = { label = "Strength", index = LE_UNIT_STAT_STRENGTH or 1 },
  DEMONHUNTER = { label = "Agility", index = LE_UNIT_STAT_AGILITY or 2 },
  DRUID = { label = "Agility", index = LE_UNIT_STAT_AGILITY or 2 },
  EVOKER = { label = "Intellect", index = LE_UNIT_STAT_INTELLECT or 4 },
  HUNTER = { label = "Agility", index = LE_UNIT_STAT_AGILITY or 2 },
  MAGE = { label = "Intellect", index = LE_UNIT_STAT_INTELLECT or 4 },
  MONK = { label = "Agility", index = LE_UNIT_STAT_AGILITY or 2 },
  PALADIN = { label = "Strength", index = LE_UNIT_STAT_STRENGTH or 1 },
  PRIEST = { label = "Intellect", index = LE_UNIT_STAT_INTELLECT or 4 },
  ROGUE = { label = "Agility", index = LE_UNIT_STAT_AGILITY or 2 },
  SHAMAN = { label = "Agility", index = LE_UNIT_STAT_AGILITY or 2 },
  WARLOCK = { label = "Intellect", index = LE_UNIT_STAT_INTELLECT or 4 },
  WARRIOR = { label = "Strength", index = LE_UNIT_STAT_STRENGTH or 1 },
}

local function ToNumber(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end
  return nil
end

local function Round(v)
  local n = ToNumber(v) or 0
  return math.floor(n + 0.5)
end

local function CopyArray(src, limit)
  if type(src) ~= "table" then
    return {}
  end
  local out = {}
  local maxItems = tonumber(limit) or #src
  if maxItems < 0 then maxItems = 0 end
  for i = 1, math.min(#src, maxItems) do
    out[#out + 1] = src[i]
  end
  return out
end

local function ResolvePlayerSnapshotKey()
  local guid = UnitGUID and UnitGUID("player") or nil
  if type(guid) == "string" and guid ~= "" then
    return guid
  end
  local name = UnitName and UnitName("player") or nil
  local realm = GetRealmName and GetRealmName() or nil
  if type(name) == "string" and name ~= "" then
    return name .. "-" .. (realm or "")
  end
  return nil
end

local function ResolveWeeklyRewardType(name, fallback)
  local enumTable = Enum and Enum.WeeklyRewardChestThresholdType
  local value = enumTable and enumTable[name]
  if type(value) == "number" then
    return value
  end
  return fallback
end

local WEEKLY_REWARD_TYPE = {
  Raid = ResolveWeeklyRewardType("Raid", 1),
  Activities = ResolveWeeklyRewardType("Activities", 2),
  World = ResolveWeeklyRewardType("World", 3),
  RankedPvP = ResolveWeeklyRewardType("RankedPvP", 4),
}

local VAULT_THRESHOLDS = {
  raid = { 1, 4, 6 },
  dungeon = { 2, 4, 8 },
  world = { 2, 4, 8 },
  pvp = { 2, 4, 8 },
}

local function NormalizeVaultTrack(activityType)
  local t = ToNumber(activityType)
  if not t then return nil end
  if t == WEEKLY_REWARD_TYPE.Raid or t == 1 then return "raid" end
  if t == WEEKLY_REWARD_TYPE.Activities or t == 2 then return "dungeon" end
  if t == WEEKLY_REWARD_TYPE.World or t == 3 then return "world" end
  if t == WEEKLY_REWARD_TYPE.RankedPvP or t == 4 then return "pvp" end
  return nil
end

local function GetCurrentMythicRating()
  local rating = 0
  if C_MythicPlus and C_MythicPlus.GetSeasonBestMythicRatingInfo then
    local info = C_MythicPlus.GetSeasonBestMythicRatingInfo()
    if type(info) == "table" then
      rating = ToNumber(info.currentSeasonScore or info.rating) or rating
    elseif type(info) == "number" then
      rating = info
    end
  end
  if (not rating or rating <= 0) and C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local info = C_ChallengeMode.GetOverallDungeonScore()
    if type(info) == "table" then
      rating = ToNumber(info.currentSeasonScore or info.overallScore or info.dungeonScore) or rating
    elseif type(info) == "number" then
      rating = info
    end
  end
  return ToNumber(rating) or 0
end

local function GetWeeklyVaultActivities()
  if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then
    return {}
  end
  local activities = C_WeeklyRewards.GetActivities()
  if type(activities) == "table" then
    return activities
  end
  return {}
end

function Data:GetPlayerSnapshotKey()
  return ResolvePlayerSnapshotKey()
end

function Data:GetStatsSnapshot()
  local className, classTag = "Unknown", ""
  if UnitClass then
    className, classTag = UnitClass("player")
  end
  className = className or "Unknown"
  classTag = classTag or ""

  local primaryMeta = PRIMARY_STAT_BY_CLASS[classTag] or { label = "Strength", index = LE_UNIT_STAT_STRENGTH or 1 }
  local primary = 0
  if UnitStat then
    local _, value = UnitStat("player", primaryMeta.index)
    primary = ToNumber(value) or 0
  end

  local avgOverall, avgEquipped = 0, 0
  if GetAverageItemLevel then
    avgOverall, avgEquipped = GetAverageItemLevel()
  end

  local powerTypeID, powerTypeToken = 0, nil
  if UnitPowerType then
    powerTypeID, powerTypeToken = UnitPowerType("player")
  end

  return {
    snapshotKey = ResolvePlayerSnapshotKey(),
    className = className,
    classTag = classTag,
    level = UnitLevel and UnitLevel("player") or nil,
    spec = {},
    itemLevel = {
      overall = ToNumber(avgOverall) or 0,
      equipped = ToNumber(avgEquipped) or 0,
    },
    health = {
      current = UnitHealth and UnitHealth("player") or 0,
      max = UnitHealthMax and UnitHealthMax("player") or 0,
    },
    power = {
      typeID = powerTypeID,
      typeToken = powerTypeToken,
      current = UnitPower and UnitPower("player") or 0,
      max = UnitPowerMax and UnitPowerMax("player") or 0,
    },
    attributes = {
      primary = {
        label = primaryMeta.label,
        index = primaryMeta.index,
        value = primary,
      },
    },
    secondary = {},
    offense = {},
    defense = {},
    movement = {},
  }
end

function Data:GetGearSnapshot()
  local slots = {}
  local missingSlots = {}
  for _, def in ipairs(GEAR_SLOTS) do
    local invID = GetInventorySlotInfo and GetInventorySlotInfo(def.token) or def.slotID
    local link = GetInventoryItemLink and GetInventoryItemLink("player", invID) or nil
    local hasItem = type(link) == "string" and link ~= ""
    if not hasItem then
      missingSlots[#missingSlots + 1] = def.token
    end
    slots[#slots + 1] = {
      slotID = def.slotID,
      slotToken = def.token,
      inventorySlotID = invID,
      hasItem = hasItem,
      link = link,
      itemID = GetInventoryItemID and GetInventoryItemID("player", invID) or nil,
      icon = GetInventoryItemTexture and GetInventoryItemTexture("player", invID) or nil,
    }
  end

  local avgOverall, avgEquipped = 0, 0
  if GetAverageItemLevel then
    avgOverall, avgEquipped = GetAverageItemLevel()
  end

  return {
    slots = slots,
    summary = {
      slotCount = #GEAR_SLOTS,
      equippedCount = #GEAR_SLOTS - #missingSlots,
      missingSlots = missingSlots,
      averageItemLevel = ToNumber(avgOverall) or 0,
      averageEquippedItemLevel = ToNumber(avgEquipped) or 0,
      computedAverageItemLevel = ToNumber(avgEquipped) or 0,
      highestItemLevel = nil,
      lowestItemLevel = nil,
    },
  }
end

function Data:GetCurrencySummary(limit)
  local rows = {}
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
    local count = ToNumber(C_CurrencyInfo.GetCurrencyListSize()) or 0
    for i = 1, count do
      local info = C_CurrencyInfo.GetCurrencyListInfo(i)
      if type(info) == "table" and not info.isHeader and not info.isTypeUnused and not info.isHidden then
        local quantity = Round(info.quantity or 0)
        local maxQuantity = Round(info.maxQuantity or 0)
        rows[#rows + 1] = {
          index = i,
          currencyID = ToNumber(info.currencyTypesID or info.currencyTypeID),
          name = info.name or "",
          quantity = quantity,
          maxQuantity = maxQuantity,
          display = (maxQuantity > 0) and ("%d/%d"):format(quantity, maxQuantity) or tostring(quantity),
          icon = info.iconFileID or 463446,
          isShowInBackpack = info.isShowInBackpack == true,
        }
      end
    end
  end

  local watchedCount = 0
  local totalQuantity = 0
  for _, row in ipairs(rows) do
    totalQuantity = totalQuantity + (row.quantity or 0)
    if row.isShowInBackpack then
      watchedCount = watchedCount + 1
    end
  end

  local topLimit = tonumber(limit) or 12
  if topLimit < 0 then topLimit = 0 end
  return {
    rows = rows,
    top = CopyArray(rows, topLimit),
    count = #rows,
    watchedCount = watchedCount,
    totalQuantity = totalQuantity,
  }
end

function Data:GetMythicPlusSummary(limit)
  local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and ToNumber(C_MythicPlus.GetOwnedKeystoneChallengeMapID()) or nil
  local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and ToNumber(C_MythicPlus.GetOwnedKeystoneLevel()) or nil
  local mapName = mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID) or nil

  local activeKey = {
    mapID = mapID,
    mapName = mapName,
    level = level,
    display = (mapID and mapName) and ("%s (+%d)"):format(mapName, Round(level or 0)) or "No active key",
  }

  local affixes = {}
  if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
    local entries = C_MythicPlus.GetCurrentAffixes()
    if type(entries) == "table" then
      for _, entry in ipairs(entries) do
        local affixID = type(entry) == "table" and (entry.id or entry.affixID or entry.keystoneAffixID) or entry
        affixID = ToNumber(affixID)
        if affixID then
          local name, description, icon = nil, nil, nil
          if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
            name, description, icon = C_ChallengeMode.GetAffixInfo(affixID)
          end
          affixes[#affixes + 1] = { id = affixID, name = name, description = description, icon = icon }
        end
      end
    end
  end

  local runs = {}
  local topLimit = tonumber(limit) or 8
  if topLimit < 0 then topLimit = 0 end
  return {
    snapshotKey = ResolvePlayerSnapshotKey(),
    rating = GetCurrentMythicRating(),
    activeKeystone = activeKey,
    affixes = affixes,
    runs = runs,
    topRuns = CopyArray(runs, topLimit),
    runCount = #runs,
  }
end

function Data:GetVaultSummary()
  local activities = GetWeeklyVaultActivities()
  local cards = { raid = {}, dungeon = {}, world = {}, pvp = {} }
  local totalCount = 0
  local completeCount = 0

  for _, activity in ipairs(activities) do
    local track = NormalizeVaultTrack(activity and activity.type)
    if track and cards[track] then
      local progress = Round(activity.progress or activity.completedActivities or activity.currentProgress or 0)
      local threshold = Round(activity.threshold or activity.requiredProgress or 0)
      local rewards = (type(activity.rewards) == "table") and activity.rewards or {}
      local complete = (#rewards > 0) or (threshold > 0 and progress >= threshold)
      if complete then completeCount = completeCount + 1 end
      totalCount = totalCount + 1

      cards[track][#cards[track] + 1] = {
        id = activity.id,
        index = ToNumber(activity.index),
        track = track,
        threshold = threshold,
        progress = progress,
        progressDisplay = (threshold > 0) and math.min(math.max(progress, 0), threshold) or progress,
        rewardsCount = #rewards,
        complete = complete,
        itemLevel = nil,
        difficulty = "",
        activityTierID = ToNumber(activity.activityTierID),
        raw = activity,
      }
    end
  end

  return {
    activities = activities,
    cards = cards,
    totals = {
      total = totalCount,
      complete = completeCount,
      pending = math.max(0, totalCount - completeCount),
    },
  }
end

Data.VAULT_THRESHOLDS = VAULT_THRESHOLDS
Data.WEEKLY_REWARD_TYPE = WEEKLY_REWARD_TYPE
