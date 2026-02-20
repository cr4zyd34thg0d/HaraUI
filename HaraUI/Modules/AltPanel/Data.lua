local ADDON, NS = ...

NS.AltPanel = NS.AltPanel or {}
local AP = NS.AltPanel

AP.Data = AP.Data or {}
local Data = AP.Data

---------------------------------------------------------------------------
-- Inventory slots
---------------------------------------------------------------------------
local INVENTORY_SLOTS = {
  { id = INVSLOT_HEAD,     name = "HEADSLOT" },
  { id = INVSLOT_NECK,     name = "NECKSLOT" },
  { id = INVSLOT_SHOULDER, name = "SHOULDERSLOT" },
  { id = INVSLOT_BACK,     name = "BACKSLOT" },
  { id = INVSLOT_CHEST,    name = "CHESTSLOT" },
  { id = INVSLOT_WRIST,    name = "WRISTSLOT" },
  { id = INVSLOT_HAND,     name = "HANDSSLOT" },
  { id = INVSLOT_WAIST,    name = "WAISTSLOT" },
  { id = INVSLOT_LEGS,     name = "LEGSSLOT" },
  { id = INVSLOT_FEET,     name = "FEETSLOT" },
  { id = INVSLOT_FINGER1,  name = "FINGER0SLOT" },
  { id = INVSLOT_FINGER2,  name = "FINGER1SLOT" },
  { id = INVSLOT_TRINKET1, name = "TRINKET0SLOT" },
  { id = INVSLOT_TRINKET2, name = "TRINKET1SLOT" },
  { id = INVSLOT_MAINHAND, name = "MAINHANDSLOT" },
  { id = INVSLOT_OFFHAND,  name = "SECONDARYHANDSLOT" },
}

---------------------------------------------------------------------------
-- Vault activity types (ordered for display)
---------------------------------------------------------------------------
local VAULT_TYPES = {
  { id = Enum.WeeklyRewardChestThresholdType.Raid,       label = "Raids" },
  { id = Enum.WeeklyRewardChestThresholdType.Activities, label = "Dungeons" },
  { id = Enum.WeeklyRewardChestThresholdType.World,      label = "World" },
}

---------------------------------------------------------------------------
-- Tracked currencies (covers multiple TWW seasons; auto-filtered)
---------------------------------------------------------------------------
local TRACKED_CURRENCIES = {
  -- TWW Season 3
  3290, 3288, 3286, 3284,
  -- TWW Season 2
  3110, 3109, 3108, 3107,
  -- Common across seasons
  3008,  -- Valorstones
  3028,  -- Restored Coffer Key
  3141,  -- Fractured Spark
  3278,  -- Ethereal Strands
  3269,  -- Catalyst (S3)
  3116,  -- Catalyst (S2)
}

---------------------------------------------------------------------------
-- Raid difficulty display order
---------------------------------------------------------------------------
local RAID_DIFFICULTIES = {
  { id = 17, label = "LFR" },
  { id = 14, label = "Normal" },
  { id = 15, label = "Heroic" },
  { id = 16, label = "Mythic" },
}

---------------------------------------------------------------------------
-- Current tier raids (always shown even with no lockout)
---------------------------------------------------------------------------
local TRACKED_RAIDS = {
  { instanceID = 2769, name = "Manaforge Omega", numEncounters = 8 },
}

---------------------------------------------------------------------------
-- Default character template
---------------------------------------------------------------------------
local DEFAULT_CHARACTER = {
  lastUpdate = 0,
  info = {
    name = "",
    realm = "",
    level = 0,
    classFile = "",
    className = "",
    classID = 0,
    ilvl = 0,
    ilvlEquipped = 0,
    faction = "",
  },
  mythicplus = {
    rating = 0,
    keystone = { mapID = 0, level = 0, name = "", challengeModeID = 0 },
    dungeons = {},
  },
  vault = {
    hasAvailable = false,
    slots = {},
  },
  equipment = {},
  currencies = {},
  raids = {},
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function DeepCopy(src)
  if type(src) ~= "table" then return src end
  local copy = {}
  for k, v in pairs(src) do
    copy[k] = DeepCopy(v)
  end
  return copy
end

local function GetDB()
  local db = NS:GetDB()
  return db and db.altpanel or nil
end

local function GetCharacterTable()
  local db = GetDB()
  if not db then return nil end
  if type(db.characters) ~= "table" then
    db.characters = {}
  end
  return db.characters
end

local function GetCurrentCharacter()
  local guid = UnitGUID("player")
  if not guid then return nil, nil end
  local chars = GetCharacterTable()
  if not chars then return nil, nil end
  if chars[guid] == nil then
    chars[guid] = DeepCopy(DEFAULT_CHARACTER)
  end
  return chars[guid], guid
end

---------------------------------------------------------------------------
-- Public accessors
---------------------------------------------------------------------------
Data.INVENTORY_SLOTS = INVENTORY_SLOTS
Data.VAULT_TYPES = VAULT_TYPES
Data.TRACKED_CURRENCIES = TRACKED_CURRENCIES
Data.RAID_DIFFICULTIES = RAID_DIFFICULTIES
Data.DEFAULT_CHARACTER = DEFAULT_CHARACTER
Data.GetDB = GetDB
Data.GetCharacterTable = GetCharacterTable
Data.GetCurrentCharacter = GetCurrentCharacter

function Data:GetCharacters()
  local chars = GetCharacterTable()
  if not chars then return {} end
  local db = GetDB()
  local showZero = db and db.showZeroRated ~= false

  local list = {}
  for guid, char in pairs(chars) do
    local keep = true
    if not showZero and char.mythicplus and char.mythicplus.rating and char.mythicplus.rating <= 0 then
      keep = false
    end
    if keep then
      list[#list + 1] = { guid = guid, data = char }
    end
  end

  table.sort(list, function(a, b)
    return (a.data.lastUpdate or 0) > (b.data.lastUpdate or 0)
  end)

  return list
end

---------------------------------------------------------------------------
-- Season dungeon cache (runtime only, not saved)
---------------------------------------------------------------------------
local seasonDungeonCache = nil

function Data:GetSeasonDungeons()
  if seasonDungeonCache then return seasonDungeonCache end

  local mapIDs = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
  if not mapIDs or #mapIDs == 0 then return {} end

  local dungeons = {}
  for _, cmID in ipairs(mapIDs) do
    local name, _, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(cmID)
    if name then
      dungeons[#dungeons + 1] = {
        challengeModeID = cmID,
        name = name,
        texture = texture or 0,
        timeLimit = timeLimit or 0,
      }
    end
  end

  table.sort(dungeons, function(a, b)
    return (a.name or "") < (b.name or "")
  end)

  seasonDungeonCache = dungeons
  return dungeons
end

function Data:InvalidateDungeonCache()
  seasonDungeonCache = nil
end

---------------------------------------------------------------------------
-- Lookup: get a character's score for a specific dungeon
---------------------------------------------------------------------------
function Data:GetDungeonScore(char, challengeModeID)
  if not char or not char.mythicplus or not char.mythicplus.dungeons then
    return nil
  end
  for _, d in ipairs(char.mythicplus.dungeons) do
    if d.challengeModeID == challengeModeID then
      return d
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Lookup: get a character's vault slots grouped by type
---------------------------------------------------------------------------
function Data:GetVaultByType(char, vaultTypeID)
  if not char or not char.vault or not char.vault.slots then return {} end
  local result = {}
  for _, slot in ipairs(char.vault.slots) do
    if slot.type == vaultTypeID then
      result[slot.index] = slot
    end
  end
  return result
end

---------------------------------------------------------------------------
-- Lookup: get a character's raid lockout for a specific instance+difficulty
---------------------------------------------------------------------------
function Data:GetRaidLockout(char, instanceID, difficultyID)
  if not char or not char.raids then return nil end
  for _, raid in ipairs(char.raids) do
    if raid.instanceID == instanceID and raid.difficultyID == difficultyID then
      return raid
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Lookup: get a character's currency amount
---------------------------------------------------------------------------
function Data:GetCurrencyAmount(char, currencyID)
  if not char or not char.currencies then return nil end
  for _, c in ipairs(char.currencies) do
    if c.id == currencyID then
      return c
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Aggregate: unique raids across all characters (for display)
---------------------------------------------------------------------------
function Data:GetTrackedRaids()
  local raidMap = {}

  -- Seed with static current-tier raids so they always appear
  for _, r in ipairs(TRACKED_RAIDS) do
    raidMap[r.instanceID] = {
      name = r.name,
      instanceID = r.instanceID,
      numEncounters = r.numEncounters,
    }
  end

  local list = {}
  for _, raid in pairs(raidMap) do
    list[#list + 1] = raid
  end
  table.sort(list, function(a, b)
    return (a.name or "") < (b.name or "")
  end)
  return list
end

---------------------------------------------------------------------------
-- Aggregate: currencies discovered by any character (for display)
---------------------------------------------------------------------------
function Data:GetTrackedCurrencies()
  local chars = GetCharacterTable()
  if not chars then return {} end

  local currMap = {}
  for _, char in pairs(chars) do
    if char.currencies then
      for _, c in ipairs(char.currencies) do
        if not currMap[c.id] then
          currMap[c.id] = {
            id = c.id,
            name = c.name,
            icon = c.icon,
            quality = c.quality or 1,
          }
        end
      end
    end
  end

  local orderMap = {}
  for i, id in ipairs(TRACKED_CURRENCIES) do
    orderMap[id] = i
  end

  local list = {}
  for _, c in pairs(currMap) do
    c.order = orderMap[c.id] or 999
    list[#list + 1] = c
  end
  table.sort(list, function(a, b)
    local qa, qb = (a.quality or 1), (b.quality or 1)
    if qa ~= qb then return qa < qb end
    return (a.order or 999) < (b.order or 999)
  end)
  return list
end

---------------------------------------------------------------------------
-- Data collection: Character info
---------------------------------------------------------------------------
function Data:UpdateCharacterInfo()
  local char = GetCurrentCharacter()
  if not char then return end

  local name = UnitName("player")
  local realm = GetRealmName()
  local level = UnitLevel("player")
  local className, classFile, classID = UnitClass("player")
  local avgIlvl, avgIlvlEquipped = GetAverageItemLevel()

  if name then char.info.name = name end
  if realm then char.info.realm = realm end
  if level then char.info.level = level end
  if className then char.info.className = className end
  if classFile then char.info.classFile = classFile end
  if classID then char.info.classID = classID end
  local faction = UnitFactionGroup("player")
  if faction then char.info.faction = faction end
  if avgIlvl then char.info.ilvl = math.floor(avgIlvl + 0.5) end
  if avgIlvlEquipped then char.info.ilvlEquipped = math.floor(avgIlvlEquipped + 0.5) end

  char.lastUpdate = GetServerTime()
end

---------------------------------------------------------------------------
-- Data collection: Equipment
---------------------------------------------------------------------------
function Data:UpdateEquipment()
  local char = GetCurrentCharacter()
  if not char then return end

  char.equipment = {}

  for _, slot in ipairs(INVENTORY_SLOTS) do
    local link = GetInventoryItemLink("player", slot.id)
    if link then
      local itemName, itemLink, itemQuality, itemLevel, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(link)
      if itemName then
        char.equipment[#char.equipment + 1] = {
          slotID    = slot.id,
          slotName  = slot.name,
          itemName  = itemName,
          itemLink  = itemLink or link,
          itemLevel = itemLevel or 0,
          quality   = itemQuality or 1,
          icon      = itemTexture or 0,
        }
      end
    end
  end
end

---------------------------------------------------------------------------
-- Data collection: Mythic+ rating and per-dungeon scores
---------------------------------------------------------------------------
function Data:UpdateMythicPlus()
  local char = GetCurrentCharacter()
  if not char then return end

  local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
  if summary and summary.currentSeasonScore then
    char.mythicplus.rating = summary.currentSeasonScore
  end

  char.mythicplus.dungeons = {}
  if summary and summary.runs then
    for _, run in ipairs(summary.runs) do
      char.mythicplus.dungeons[#char.mythicplus.dungeons + 1] = {
        challengeModeID    = run.challengeModeID,
        mapScore           = run.mapScore or 0,
        bestRunLevel       = run.bestRunLevel or 0,
        finishedSuccess    = run.finishedSuccess or false,
        bestRunDurationMS  = run.bestRunDurationMS or 0,
      }
    end
  end
end

---------------------------------------------------------------------------
-- Data collection: Keystone
---------------------------------------------------------------------------
function Data:UpdateKeystone()
  local char = GetCurrentCharacter()
  if not char then return end

  local mapID = C_MythicPlus.GetOwnedKeystoneMapID()
  local level = C_MythicPlus.GetOwnedKeystoneLevel()

  if mapID and level then
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    char.mythicplus.keystone = {
      mapID           = mapID,
      level           = level,
      name            = name or "",
      challengeModeID = mapID,
    }
  else
    char.mythicplus.keystone = DeepCopy(DEFAULT_CHARACTER.mythicplus.keystone)
  end
end

---------------------------------------------------------------------------
-- Data collection: Vault
---------------------------------------------------------------------------
function Data:UpdateVault()
  local char = GetCurrentCharacter()
  if not char then return end

  char.vault.slots = {}

  local activities = C_WeeklyRewards.GetActivities()
  if activities then
    for _, activity in ipairs(activities) do
      local rewardIlvl = 0
      if activity.progress >= activity.threshold
        and activity.id and activity.id > 0
        and C_WeeklyRewards.GetExampleRewardItemHyperlinks
      then
        local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
        if link then
          local ilvlFunc = C_Item and C_Item.GetDetailedItemLevelInfo
            or GetDetailedItemLevelInfo
          if ilvlFunc then
            rewardIlvl = ilvlFunc(link) or 0
          end
        end
      end
      char.vault.slots[#char.vault.slots + 1] = {
        type       = activity.type,
        index      = activity.index,
        threshold  = activity.threshold,
        progress   = activity.progress,
        level      = activity.level or 0,
        rewardIlvl = rewardIlvl,
        id         = activity.id,
      }
    end
  end

  local hasAvailable = C_WeeklyRewards.HasAvailableRewards()
  if hasAvailable ~= nil then
    char.vault.hasAvailable = hasAvailable
  end
end

---------------------------------------------------------------------------
-- Data collection: Currencies
---------------------------------------------------------------------------
function Data:UpdateCurrencies()
  local char = GetCurrentCharacter()
  if not char then return end

  char.currencies = {}

  if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return end

  for _, currencyID in ipairs(TRACKED_CURRENCIES) do
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info and info.name and info.name ~= "" and info.discovered ~= false then
      char.currencies[#char.currencies + 1] = {
        id          = currencyID,
        name        = info.name,
        icon        = info.iconFileID or 0,
        quantity    = info.quantity or 0,
        maxQuantity = info.maxQuantity or 0,
        quality     = info.quality or 1,
      }
    end
  end
end

---------------------------------------------------------------------------
-- Data collection: Raid lockouts
---------------------------------------------------------------------------
function Data:UpdateRaidLockouts()
  local char = GetCurrentCharacter()
  if not char then return end

  char.raids = {}

  if not GetNumSavedInstances then return end

  local numSaved = GetNumSavedInstances()
  for i = 1, numSaved do
    local name, _, reset, diffID, locked, _,
      _, isRaid, _, diffName, numEncounters, _,
      _, instanceID = GetSavedInstanceInfo(i)

    if isRaid and name and numEncounters and numEncounters > 0 then
      local encounters = {}
      for ei = 1, numEncounters do
        local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, ei)
        encounters[#encounters + 1] = {
          name   = bossName or "",
          killed = isKilled or false,
        }
      end

      char.raids[#char.raids + 1] = {
        name           = name,
        instanceID     = instanceID or 0,
        difficultyID   = diffID or 0,
        difficultyName = diffName or "",
        numEncounters  = numEncounters,
        encounters     = encounters,
        locked         = locked or false,
        expires        = (reset and reset > 0) and (reset + time()) or 0,
      }
    end
  end
end

---------------------------------------------------------------------------
-- Full update (all data sources)
---------------------------------------------------------------------------
function Data:UpdateAll()
  self:UpdateCharacterInfo()
  self:UpdateEquipment()
  self:UpdateMythicPlus()
  self:UpdateKeystone()
  self:UpdateVault()
  self:UpdateCurrencies()
  self:UpdateRaidLockouts()
end

---------------------------------------------------------------------------
-- Weekly reset detection
---------------------------------------------------------------------------
function Data:CheckWeeklyReset()
  local db = GetDB()
  if not db then return end

  local now = time()
  if type(db.weeklyReset) == "number" and db.weeklyReset > 0 and db.weeklyReset <= now then
    local chars = GetCharacterTable()
    if chars then
      for _, char in pairs(chars) do
        if char.vault then
          for _, slot in ipairs(char.vault.slots or {}) do
            if slot.progress >= slot.threshold then
              char.vault.hasAvailable = true
              break
            end
          end
          char.vault.slots = {}
        end
        if char.mythicplus then
          char.mythicplus.keystone = DeepCopy(DEFAULT_CHARACTER.mythicplus.keystone)
        end
      end
    end
  end

  if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    db.weeklyReset = now + C_DateAndTime.GetSecondsUntilWeeklyReset()
  end
end

---------------------------------------------------------------------------
-- Delete character
---------------------------------------------------------------------------
function Data:DeleteCharacter(guid)
  local chars = GetCharacterTable()
  if chars and guid then
    chars[guid] = nil
  end
end
