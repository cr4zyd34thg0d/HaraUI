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

local RAID_DIFFICULTY_LABELS = {
  [14] = "Normal",
  [15] = "Heroic",
  [16] = "Mythic",
  [17] = "LFR",
}

local VAULT_THRESHOLDS = {
  raid = { 1, 4, 6 },
  dungeon = { 2, 4, 8 },
  world = { 2, 4, 8 },
  pvp = { 2, 4, 8 },
}

local function ToNumber(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then
    local n = tonumber(v)
    if n then return n end
  end
  return nil
end

local function Round(v)
  local n = ToNumber(v) or 0
  return math.floor(n + 0.5)
end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, r1, r2, r3, r4, r5 = pcall(fn, ...)
  if not ok then
    return nil
  end
  return r1, r2, r3, r4, r5
end

local function CopyArray(src, limit)
  local out = {}
  if type(src) ~= "table" then
    return out
  end
  local maxItems = tonumber(limit) or #src
  if maxItems < 0 then maxItems = 0 end
  local count = math.min(#src, maxItems)
  for i = 1, count do
    out[#out + 1] = src[i]
  end
  return out
end

local function ResolveDetailedItemLevel(link)
  if type(link) ~= "string" or link == "" then
    return nil
  end
  local ilvl = ToNumber(SafeCall(C_Item and C_Item.GetDetailedItemLevelInfo, link))
  if not ilvl or ilvl <= 0 then
    ilvl = ToNumber(SafeCall(GetDetailedItemLevelInfo, link))
  end
  if (not ilvl or ilvl <= 0) and GetItemInfo then
    local _, _, _, fallback = SafeCall(GetItemInfo, link)
    ilvl = ToNumber(fallback)
  end
  if ilvl and ilvl > 0 then
    return Round(ilvl)
  end
  return nil
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

local function NormalizeVaultTrack(activityType)
  local t = ToNumber(activityType)
  if not t then return nil end
  if t == WEEKLY_REWARD_TYPE.Raid or t == 1 then
    return "raid"
  end
  if t == WEEKLY_REWARD_TYPE.Activities or t == 2 then
    return "dungeon"
  end
  if t == WEEKLY_REWARD_TYPE.World or t == 3 then
    return "world"
  end
  if t == WEEKLY_REWARD_TYPE.RankedPvP or t == 4 then
    return "pvp"
  end
  return nil
end

local function NormalizeMythicRun(raw)
  if type(raw) ~= "table" then
    return nil
  end

  local mapID = ToNumber(raw.mapChallengeModeID or raw.mapID or raw.challengeModeID)
  local level = ToNumber(raw.level or raw.bestLevel or raw.keystoneLevel or raw.bestRunLevel or raw.challengeLevel) or 0
  local score = ToNumber(raw.score or raw.rating or raw.currentSeasonScore or raw.overallScore or raw.dungeonScore) or 0
  local durationMS = ToNumber(raw.bestRunDurationMS or raw.durationMS)
  local overTimeMS = ToNumber(raw.overTimeMS)
  if not overTimeMS then
    local overTime = ToNumber(raw.overTime)
    if overTime then
      if math.abs(overTime) > 10000 then
        overTimeMS = overTime
      else
        overTimeMS = overTime * 1000
      end
    end
  end
  local stars = ToNumber(raw.stars or raw.numKeystoneUpgrades) or 0
  local mapName = nil
  if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
    mapName = C_ChallengeMode.GetMapUIInfo(mapID)
  end

  return {
    mapID = mapID,
    mapName = mapName,
    level = Round(level),
    score = score,
    stars = Round(stars),
    durationMS = durationMS,
    overTimeMS = overTimeMS,
    raw = raw,
  }
end

local function MergeBestRunsByMap(runs)
  local byKey = {}
  for index, run in ipairs(runs or {}) do
    if type(run) == "table" then
      local key = run.mapID or ("idx_" .. tostring(index))
      local current = byKey[key]
      if not current then
        byKey[key] = run
      else
        local bestLevel = ToNumber(current.level) or 0
        local nextLevel = ToNumber(run.level) or 0
        local bestScore = ToNumber(current.score) or 0
        local nextScore = ToNumber(run.score) or 0
        if (nextLevel > bestLevel) or (nextLevel == bestLevel and nextScore > bestScore) then
          byKey[key] = run
        end
      end
    end
  end
  local merged = {}
  for _, run in pairs(byKey) do
    merged[#merged + 1] = run
  end
  table.sort(merged, function(a, b)
    local aLevel = ToNumber(a and a.level) or 0
    local bLevel = ToNumber(b and b.level) or 0
    if aLevel ~= bLevel then
      return aLevel > bLevel
    end
    local aScore = ToNumber(a and a.score) or 0
    local bScore = ToNumber(b and b.score) or 0
    if aScore ~= bScore then
      return aScore > bScore
    end
    return (a.mapName or "") < (b.mapName or "")
  end)
  return merged
end

local function GetCurrentMythicRating()
  local rating = 0
  if C_MythicPlus and C_MythicPlus.GetSeasonBestMythicRatingInfo then
    local info = SafeCall(C_MythicPlus.GetSeasonBestMythicRatingInfo)
    if type(info) == "table" then
      rating = ToNumber(info.currentSeasonScore or info.rating) or rating
    elseif type(info) == "number" then
      rating = info
    end
  end
  if (not rating or rating <= 0) and C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local info = SafeCall(C_ChallengeMode.GetOverallDungeonScore)
    if type(info) == "table" then
      rating = ToNumber(info.currentSeasonScore or info.overallScore or info.dungeonScore) or rating
    elseif type(info) == "number" then
      rating = info
    end
  end
  return ToNumber(rating) or 0
end

local function GetWeeklyVaultActivities()
  local activities = {}
  if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then
    return activities
  end

  local direct = SafeCall(C_WeeklyRewards.GetActivities)
  if type(direct) == "table" and #direct > 0 then
    return direct
  end

  local dedupe = {}
  local types = {
    WEEKLY_REWARD_TYPE.Activities,
    WEEKLY_REWARD_TYPE.Raid,
    WEEKLY_REWARD_TYPE.World,
    WEEKLY_REWARD_TYPE.RankedPvP,
  }
  for _, rewardType in ipairs(types) do
    local subset = SafeCall(C_WeeklyRewards.GetActivities, rewardType)
    if type(subset) == "table" then
      for _, activity in ipairs(subset) do
        local id = activity and activity.id
        if id then
          if not dedupe[id] then
            dedupe[id] = true
            activities[#activities + 1] = activity
          end
        else
          activities[#activities + 1] = activity
        end
      end
    end
  end

  return activities
end

local function GetVaultRewards(activity)
  if type(activity) ~= "table" or type(activity.rewards) ~= "table" then
    return {}
  end
  return activity.rewards
end

local function ResolveVaultItemLevel(activity)
  if type(activity) ~= "table" then
    return nil
  end
  local direct = ToNumber(activity.itemLevel or activity.rewardItemLevel or activity.rewardLevel or activity.ilvl)
  if direct and direct > 0 then
    return Round(direct)
  end

  if C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink then
    for _, reward in ipairs(GetVaultRewards(activity)) do
      local itemDBID = reward and reward.itemDBID
      if itemDBID then
        local hyperlink = SafeCall(C_WeeklyRewards.GetItemHyperlink, itemDBID)
        local ilvl = ResolveDetailedItemLevel(hyperlink)
        if ilvl then
          return ilvl
        end
      end
    end
  end

  if C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks and activity.id then
    local example = SafeCall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, activity.id)
    if type(example) == "table" then
      for _, hyperlink in ipairs(example) do
        local ilvl = ResolveDetailedItemLevel(hyperlink)
        if ilvl then
          return ilvl
        end
      end
    else
      local ilvl = ResolveDetailedItemLevel(example)
      if ilvl then
        return ilvl
      end
    end
  end

  return nil
end

local function ResolveVaultDifficultyLabel(track, activity)
  if type(activity) ~= "table" then
    return ""
  end

  if track == "raid" then
    local difficultyID = ToNumber(activity.difficultyID or activity.difficulty or activity.level)
    if difficultyID and DifficultyUtil and DifficultyUtil.GetDifficultyName then
      local name = DifficultyUtil.GetDifficultyName(difficultyID)
      if type(name) == "string" and name ~= "" then
        return name
      end
    end
    return RAID_DIFFICULTY_LABELS[difficultyID] or ""
  end

  if track == "dungeon" then
    if C_WeeklyRewards and C_WeeklyRewards.GetDifficultyIDForActivityTier and activity.activityTierID and DifficultyUtil and DifficultyUtil.ID then
      local difficultyID = SafeCall(C_WeeklyRewards.GetDifficultyIDForActivityTier, activity.activityTierID)
      if difficultyID == DifficultyUtil.ID.DungeonHeroic then
        return "Heroic"
      end
    end
    local level = ToNumber(activity.level or activity.keystoneLevel or activity.bestLevel or activity.bestRunLevel or activity.challengeLevel)
    if level and level > 0 then
      return ("+%d"):format(Round(level))
    end
    return ""
  end

  if track == "pvp" and PVPUtil and PVPUtil.GetTierName then
    local tier = ToNumber(activity.level)
    if tier and tier > 0 then
      local tierName = PVPUtil.GetTierName(tier)
      if type(tierName) == "string" and tierName ~= "" then
        return tierName
      end
    end
  end

  local generic = ToNumber(activity.level or activity.tier or activity.tierID or activity.difficulty or activity.difficultyID)
  if generic and generic > 0 then
    return ("Tier %d"):format(Round(generic))
  end

  return ""
end

function Data:GetPlayerSnapshotKey()
  return ResolvePlayerSnapshotKey()
end

function Data:GetStatsSnapshot()
  local className, classTag = "Unknown", nil
  if UnitClass then
    className, classTag = UnitClass("player")
  end
  className = className or "Unknown"
  classTag = classTag or ""

  local primaryMeta = PRIMARY_STAT_BY_CLASS[classTag or ""] or { label = "Strength", index = LE_UNIT_STAT_STRENGTH or 1 }
  local primaryBase, primaryValue, primaryPos, primaryNeg = 0, 0, 0, 0
  if UnitStat then
    primaryBase, primaryValue, primaryPos, primaryNeg = UnitStat("player", primaryMeta.index)
  end
  local value = ToNumber(primaryValue) or ToNumber(primaryBase) or 0
  if value <= 0 then
    value = (ToNumber(primaryBase) or 0) + (ToNumber(primaryPos) or 0) + (ToNumber(primaryNeg) or 0)
  end

  local strBase, strValue = 0, 0
  local agiBase, agiValue = 0, 0
  local staBase, staValue = 0, 0
  local intBase, intValue = 0, 0
  if UnitStat then
    strBase, strValue = UnitStat("player", LE_UNIT_STAT_STRENGTH or 1)
    agiBase, agiValue = UnitStat("player", LE_UNIT_STAT_AGILITY or 2)
    staBase, staValue = UnitStat("player", LE_UNIT_STAT_STAMINA or 3)
    intBase, intValue = UnitStat("player", LE_UNIT_STAT_INTELLECT or 4)
  end

  local baseArmor, effectiveArmor, armor, armorPos, armorNeg = 0, 0, 0, 0, 0
  if UnitArmor then
    baseArmor, effectiveArmor, armor, armorPos, armorNeg = UnitArmor("player")
  end

  local attackBase, attackPos, attackNeg = 0, 0, 0
  if UnitAttackPower then
    attackBase, attackPos, attackNeg = UnitAttackPower("player")
  end

  local mainHandSpeed, offHandSpeed = nil, nil
  if UnitAttackSpeed then
    mainHandSpeed, offHandSpeed = UnitAttackSpeed("player")
  end

  local powerTypeID, powerTypeToken = 0, nil
  if UnitPowerType then
    powerTypeID, powerTypeToken = UnitPowerType("player")
  end

  local specIndex = GetSpecialization and GetSpecialization() or nil
  local specID, specName, _, specIcon, specRole = nil, nil, nil, nil, nil
  if specIndex and GetSpecializationInfo then
    specID, specName, _, specIcon, specRole = GetSpecializationInfo(specIndex)
  end

  local avgOverall, avgEquipped = 0, 0
  if GetAverageItemLevel then
    avgOverall, avgEquipped = GetAverageItemLevel()
  end
  local spellPower = GetSpellBonusDamage and (GetSpellBonusDamage(2) or 0) or 0
  local runSpeedPct = 0
  if GetUnitSpeed and BASE_MOVEMENT_SPEED and BASE_MOVEMENT_SPEED > 0 then
    runSpeedPct = (GetUnitSpeed("player") / BASE_MOVEMENT_SPEED) * 100
  end

  local versatility = 0
  if GetCombatRatingBonus then
    versatility = ToNumber(GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE or 29)) or 0
  elseif GetVersatilityBonus then
    versatility = ToNumber(GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE or 29)) or 0
  end

  local gcdSeconds = 1.0
  if C_Spell and C_Spell.GetSpellCooldown then
    local cooldown = SafeCall(C_Spell.GetSpellCooldown, 61304)
    if type(cooldown) == "table" and type(cooldown.duration) == "number" and cooldown.duration > 0 then
      gcdSeconds = cooldown.duration
    end
  end

  return {
    snapshotKey = ResolvePlayerSnapshotKey(),
    className = className,
    classTag = classTag,
    level = UnitLevel and UnitLevel("player") or nil,
    spec = {
      index = specIndex,
      id = specID,
      name = specName,
      role = specRole,
      icon = specIcon,
    },
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
      strength = ToNumber(strValue) or ToNumber(strBase) or 0,
      agility = ToNumber(agiValue) or ToNumber(agiBase) or 0,
      stamina = ToNumber(staValue) or ToNumber(staBase) or 0,
      intellect = ToNumber(intValue) or ToNumber(intBase) or 0,
      primary = {
        label = primaryMeta.label,
        index = primaryMeta.index,
        value = value,
      },
    },
    secondary = {
      crit = GetCritChance and (GetCritChance() or 0) or 0,
      haste = GetHaste and (GetHaste() or 0) or 0,
      mastery = GetMasteryEffect and (GetMasteryEffect() or 0) or 0,
      versatility = versatility,
      leech = GetLifesteal and (GetLifesteal() or 0) or 0,
      avoidance = GetAvoidance and (GetAvoidance() or 0) or 0,
      speedRating = GetSpeed and (GetSpeed() or 0) or 0,
    },
    offense = {
      attackPower = (ToNumber(attackBase) or 0) + (ToNumber(attackPos) or 0) + (ToNumber(attackNeg) or 0),
      mainHandSpeed = ToNumber(mainHandSpeed),
      offHandSpeed = ToNumber(offHandSpeed),
      spellPower = ToNumber(spellPower) or 0,
      gcdSeconds = gcdSeconds,
    },
    defense = {
      baseArmor = ToNumber(baseArmor) or 0,
      effectiveArmor = ToNumber(effectiveArmor) or ToNumber(armor) or 0,
      armorBuffPositive = ToNumber(armorPos) or 0,
      armorBuffNegative = ToNumber(armorNeg) or 0,
      dodge = GetDodgeChance and (GetDodgeChance() or 0) or 0,
      parry = GetParryChance and (GetParryChance() or 0) or 0,
      block = GetBlockChance and (GetBlockChance() or 0) or 0,
      stagger = (C_PaperDollInfo and C_PaperDollInfo.GetStaggerPercentage and C_PaperDollInfo.GetStaggerPercentage("player")) or 0,
    },
    movement = {
      runSpeedPct = runSpeedPct,
      movementSpeedPct = GetSpeed and (GetSpeed() or 0) or 0,
    },
  }
end

function Data:GetGearSnapshot()
  local slots = {}
  local missingSlots = {}
  local ilvlCount = 0
  local ilvlSum = 0
  local highestIlvl = nil
  local lowestIlvl = nil

  local avgOverall, avgEquipped = 0, 0
  if GetAverageItemLevel then
    avgOverall, avgEquipped = GetAverageItemLevel()
  end

  for _, def in ipairs(GEAR_SLOTS) do
    local invID = SafeCall(GetInventorySlotInfo, def.token) or def.slotID
    local link = GetInventoryItemLink and GetInventoryItemLink("player", invID) or nil
    local itemName, itemQuality, itemLevel, itemEquipLoc, itemIcon = nil, nil, nil, nil, nil
    if link and GetItemInfo then
      itemName, _, itemQuality, itemLevel, _, _, _, _, itemEquipLoc, itemIcon = GetItemInfo(link)
    end

    local itemID, instantEquipLoc = nil, nil
    if link and GetItemInfoInstant then
      itemID, _, _, instantEquipLoc = GetItemInfoInstant(link)
    end
    if not itemID and GetInventoryItemID then
      itemID = GetInventoryItemID("player", invID)
    end

    local detailedIlvl = ResolveDetailedItemLevel(link)
    if not detailedIlvl and itemLevel then
      detailedIlvl = Round(itemLevel)
    end

    if detailedIlvl and detailedIlvl > 0 then
      ilvlCount = ilvlCount + 1
      ilvlSum = ilvlSum + detailedIlvl
      highestIlvl = (not highestIlvl or detailedIlvl > highestIlvl) and detailedIlvl or highestIlvl
      lowestIlvl = (not lowestIlvl or detailedIlvl < lowestIlvl) and detailedIlvl or lowestIlvl
    end

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
      itemID = itemID,
      name = itemName,
      quality = ToNumber(itemQuality),
      itemLevel = detailedIlvl,
      equipLoc = instantEquipLoc or itemEquipLoc,
      icon = (GetInventoryItemTexture and GetInventoryItemTexture("player", invID)) or itemIcon,
    }
  end

  return {
    slots = slots,
    summary = {
      slotCount = #GEAR_SLOTS,
      equippedCount = #GEAR_SLOTS - #missingSlots,
      missingSlots = missingSlots,
      averageItemLevel = ToNumber(avgOverall) or 0,
      averageEquippedItemLevel = ToNumber(avgEquipped) or 0,
      computedAverageItemLevel = (ilvlCount > 0) and (ilvlSum / ilvlCount) or 0,
      highestItemLevel = highestIlvl,
      lowestItemLevel = lowestIlvl,
    },
  }
end

function Data:GetCurrencySummary(limit)
  local rows = {}
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
    local count = ToNumber(C_CurrencyInfo.GetCurrencyListSize()) or 0
    for i = 1, count do
      local info = C_CurrencyInfo.GetCurrencyListInfo(i)
      if type(info) == "table"
        and not info.isHeader
        and not info.isTypeUnused
        and not info.isHidden
      then
        local name = info.name or ""
        if name ~= "" then
          local quantity = Round(info.quantity or 0)
          local maxQuantity = Round(info.maxQuantity or 0)
          rows[#rows + 1] = {
            index = i,
            currencyID = ToNumber(info.currencyTypesID or info.currencyTypeID),
            name = name,
            quantity = quantity,
            maxQuantity = maxQuantity,
            display = (maxQuantity > 0) and ("%d/%d"):format(quantity, maxQuantity) or tostring(quantity),
            icon = info.iconFileID or 463446,
            isShowInBackpack = info.isShowInBackpack == true,
            canEarnPerWeek = ToNumber(info.canEarnPerWeek),
            totalEarned = ToNumber(info.totalEarned),
          }
        end
      end
    end
  end

  table.sort(rows, function(a, b)
    if (a.quantity or 0) ~= (b.quantity or 0) then
      return (a.quantity or 0) > (b.quantity or 0)
    end
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)

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
  local activeKey = {
    mapID = nil,
    mapName = nil,
    level = nil,
    display = "No active key",
  }

  if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
    local mapID = ToNumber(C_MythicPlus.GetOwnedKeystoneChallengeMapID())
    local level = ToNumber(C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or nil)
    if mapID and mapID > 0 then
      local mapName = (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)) or ("Map " .. tostring(mapID))
      activeKey = {
        mapID = mapID,
        mapName = mapName,
        level = level and Round(level) or nil,
        display = ("%s (%s)"):format(mapName, level and ("+" .. Round(level)) or "?"),
      }
    end
  end

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
          affixes[#affixes + 1] = {
            id = affixID,
            name = name,
            description = description,
            icon = icon,
          }
        end
      end
    end
  end

  local history = {}
  if C_MythicPlus and C_MythicPlus.GetRunHistory then
    local candidates = {
      function() return C_MythicPlus.GetRunHistory(false, true) end,
      function() return C_MythicPlus.GetRunHistory(true, true) end,
      function() return C_MythicPlus.GetRunHistory(false, false) end,
      function() return C_MythicPlus.GetRunHistory() end,
    }
    for _, fn in ipairs(candidates) do
      local runs = SafeCall(fn)
      if type(runs) == "table" and #runs > 0 then
        history = runs
        break
      end
    end
  end

  if #history == 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable and C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
    local mapTable = SafeCall(C_ChallengeMode.GetMapTable)
    if type(mapTable) == "table" then
      for _, mapID in ipairs(mapTable) do
        local info = SafeCall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
        if type(info) == "table" then
          history[#history + 1] = {
            mapChallengeModeID = mapID,
            score = info.score or info.overallScore or info.dungeonScore,
            level = info.level or info.bestLevel or info.keystoneLevel,
            bestRunDurationMS = info.bestRunDurationMS or info.durationMS,
            overTimeMS = info.overTimeMS or info.overTime,
          }
        end
      end
    end
  end

  local normalizedRuns = {}
  for _, run in ipairs(history) do
    local normalized = NormalizeMythicRun(run)
    if normalized then
      normalizedRuns[#normalizedRuns + 1] = normalized
    end
  end
  normalizedRuns = MergeBestRunsByMap(normalizedRuns)

  local runLimit = tonumber(limit) or 8
  if runLimit < 0 then runLimit = 0 end
  return {
    snapshotKey = ResolvePlayerSnapshotKey(),
    rating = GetCurrentMythicRating(),
    activeKeystone = activeKey,
    affixes = affixes,
    runs = normalizedRuns,
    topRuns = CopyArray(normalizedRuns, runLimit),
    runCount = #normalizedRuns,
  }
end

function Data:GetVaultSummary()
  local activities = GetWeeklyVaultActivities()
  local grouped = {
    raid = {},
    dungeon = {},
    world = {},
    pvp = {},
  }

  for _, activity in ipairs(activities) do
    local track = NormalizeVaultTrack(activity and activity.type)
    if track and grouped[track] then
      grouped[track][#grouped[track] + 1] = activity
    end
  end

  local cards = {
    raid = {},
    dungeon = {},
    world = {},
    pvp = {},
  }
  local totalCount = 0
  local completeCount = 0

  for track, list in pairs(grouped) do
    table.sort(list, function(a, b)
      local aIndex = ToNumber(a and a.index) or math.huge
      local bIndex = ToNumber(b and b.index) or math.huge
      if aIndex ~= bIndex then
        return aIndex < bIndex
      end
      local aThreshold = ToNumber(a and a.threshold) or math.huge
      local bThreshold = ToNumber(b and b.threshold) or math.huge
      return aThreshold < bThreshold
    end)

    for index, activity in ipairs(list) do
      local threshold = ToNumber(activity.threshold or activity.requiredProgress)
      if not threshold then
        threshold = VAULT_THRESHOLDS[track] and VAULT_THRESHOLDS[track][index] or 0
      end
      threshold = Round(threshold or 0)

      local progress = Round(activity.progress or activity.completedActivities or activity.currentProgress or 0)
      local rewards = GetVaultRewards(activity)
      local rewardsCount = #rewards
      local complete = (rewardsCount > 0) or (threshold > 0 and progress >= threshold)
      local difficulty = ResolveVaultDifficultyLabel(track, activity)
      local itemLevel = ResolveVaultItemLevel(activity)

      if complete then
        completeCount = completeCount + 1
      end
      totalCount = totalCount + 1

      cards[track][#cards[track] + 1] = {
        id = activity.id,
        index = ToNumber(activity.index),
        track = track,
        threshold = threshold,
        progress = progress,
        progressDisplay = threshold > 0 and math.min(math.max(progress, 0), threshold) or progress,
        rewardsCount = rewardsCount,
        complete = complete,
        itemLevel = itemLevel,
        difficulty = difficulty,
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

