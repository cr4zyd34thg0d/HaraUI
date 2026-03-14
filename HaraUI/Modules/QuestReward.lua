--[[
  Quest Reward Module

  Automatically selects the best quest reward 1.5 seconds after the quest
  completion UI appears, giving the player a moment to see the choices.

  Priority order:
    1. Same armor type + right primary stat + ilvl upgrade  → highest ilvl
    2. Same armor type + any stat    + ilvl upgrade         → highest ilvl
    3. Any equippable ilvl upgrade                          → highest ilvl
    4. Highest vendor sell price (best "gold equivalent")

  Events:
    QUEST_COMPLETE
--]]

local _, NS = ...
local M = {}
NS:RegisterModule("questreward", M)
M.active = false

local state = { eventFrame = nil }

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local CLASS_ARMOR_TYPE     = NS.ITEM_CLASS_ARMOR_TYPE
local PRIMARY_STAT_KEY     = NS.ITEM_PRIMARY_STAT_KEY
local ACCESSORY_EQUIP_LOCS = NS.ITEM_ACCESSORY_EQUIP_LOCS

-- Maps equipLoc → inventory slot ID (or first slot for dual-slot items).
local EQUIP_LOC_TO_SLOT = {
  INVTYPE_HEAD            = 1,
  INVTYPE_NECK            = 2,
  INVTYPE_SHOULDER        = 3,
  INVTYPE_CLOAK           = 15,
  INVTYPE_CHEST           = 5,
  INVTYPE_ROBE            = 5,
  INVTYPE_WRIST           = 9,
  INVTYPE_HAND            = 10,
  INVTYPE_WAIST           = 6,
  INVTYPE_LEGS            = 7,
  INVTYPE_FEET            = 8,
  INVTYPE_FINGER          = 11,
  INVTYPE_TRINKET         = 13,
  INVTYPE_2HWEAPON        = 16,
  INVTYPE_WEAPON          = 16,
  INVTYPE_WEAPONMAINHAND  = 16,
  INVTYPE_WEAPONOFFHAND   = 17,
  INVTYPE_HOLDABLE        = 17,
  INVTYPE_RANGED          = 18,
  INVTYPE_RELIC           = 18,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function GetPlayerArmorType()
  local _, classFile = UnitClass("player")
  return CLASS_ARMOR_TYPE[classFile or ""] or "Cloth"
end

local function GetPlayerPrimaryStatKey()
  if not GetSpecialization then return nil end
  local specIndex = GetSpecialization()
  if not specIndex then return nil end
  local _, _, _, _, _, primaryStat = GetSpecializationInfo(specIndex)
  return PRIMARY_STAT_KEY[primaryStat]
end

local function GetEquippedIlvl(slot)
  if not slot then return 0 end
  if C_Item and C_Item.GetCurrentItemLevel and ItemLocation then
    local loc = ItemLocation:CreateFromEquipmentSlot(slot)
    if loc and C_Item.DoesItemExist(loc) then
      return C_Item.GetCurrentItemLevel(loc) or 0
    end
  end
  local link = GetInventoryItemLink("player", slot)
  if link then
    local _, _, _, itemLevel = GetItemInfo(link)
    return itemLevel or 0
  end
  return 0
end

-- For dual-slot items (finger 11/12, trinket 13/14) return the lower ilvl slot.
local function GetDualSlotMinIlvl(slotA, slotB)
  local a = GetEquippedIlvl(slotA)
  local b = GetEquippedIlvl(slotB)
  if a <= b then
    return a
  end
  return b
end

-- Score a single quest reward choice.
-- Returns a numeric score (higher = better) or nil if this choice should be skipped.
local function ScoreChoice(idx, armorType, primaryStatKey)
  local _, _, _, _, isUsable = GetQuestItemInfo("choice", idx)
  local link = GetQuestItemLink("choice", idx)
  if not link then return nil end

  local _, _, _, itemLevel, _, _, subType, _, equipLoc, _, sellPrice =
    GetItemInfo(link)

  -- Non-equippable items: scored only by sell price, low priority.
  if not equipLoc or equipLoc == "" or not EQUIP_LOC_TO_SLOT[equipLoc] then
    return -1000 + (sellPrice or 0) * 0.0001
  end

  -- Must be usable by this character.
  if not isUsable then return nil end

  local slot = EQUIP_LOC_TO_SLOT[equipLoc]

  -- Equipped ilvl for this slot.
  local equippedIlvl
  if equipLoc == "INVTYPE_FINGER" then
    equippedIlvl = GetDualSlotMinIlvl(11, 12)
  elseif equipLoc == "INVTYPE_TRINKET" then
    equippedIlvl = GetDualSlotMinIlvl(13, 14)
  else
    equippedIlvl = GetEquippedIlvl(slot)
  end

  local ilvl = itemLevel or 0
  local ilvlDelta = ilvl - equippedIlvl

  -- Accessories skip armor-type and stat checks.
  if ACCESSORY_EQUIP_LOCS[equipLoc] then
    if ilvlDelta > 0 then
      return ilvlDelta
    end
    return -1000 + (sellPrice or 0) * 0.0001
  end

  -- Armor type check.
  local armorMatch = (subType == armorType)
  if not armorMatch then
    -- Wrong armor type: only worth considering if it's somehow an upgrade with no alternatives.
    if ilvlDelta > 0 then return ilvlDelta * 0.1 end
    return -1000 + (sellPrice or 0) * 0.0001
  end

  -- Primary stat check (on matching-armor items).
  local statMatch = false
  if primaryStatKey then
    local stats
    if C_Item and C_Item.GetItemStats then
      stats = C_Item.GetItemStats(link)
    elseif GetItemStats then
      stats = {}
      GetItemStats(link, stats)
    end
    if stats then
      statMatch = (stats[primaryStatKey] and stats[primaryStatKey] > 0)
    else
      statMatch = true  -- API unavailable; armor auto-adjusts primary stat
    end
  else
    statMatch = true  -- unknown spec, treat as match
  end

  -- Score by priority tier.
  if statMatch and ilvlDelta > 0 then
    return 2000 + ilvlDelta
  elseif ilvlDelta > 0 then
    return 1000 + ilvlDelta
  end

  -- No upgrade: score by sell price.
  return -1000 + (sellPrice or 0) * 0.0001
end

-- Check that GetItemInfo has cached data for all reward choices.
local function AreRewardItemsReady(numChoices)
  for i = 1, numChoices do
    local link = GetQuestItemLink("choice", i)
    if not link then return false end
    local _, _, _, itemLevel = GetItemInfo(link)
    if not itemLevel then return false end
  end
  return true
end

local function SelectBestReward()
  local numChoices = GetNumQuestChoices()
  if numChoices == 0 then return end
  if numChoices == 1 then
    GetQuestReward(1)
    return
  end

  -- Retry if item data isn't cached yet (async GetItemInfo).
  if not AreRewardItemsReady(numChoices) then
    C_Timer.After(0.1, function()
      if M.active and QuestFrame and QuestFrame:IsShown() then
        SelectBestReward()
      end
    end)
    return
  end

  local armorType      = GetPlayerArmorType()
  local primaryStatKey = GetPlayerPrimaryStatKey()

  local bestIdx   = nil
  local bestScore = nil

  for i = 1, numChoices do
    local score = ScoreChoice(i, armorType, primaryStatKey)
    if score and (bestScore == nil or score > bestScore) then
      bestScore = score
      bestIdx   = i
    end
  end

  -- Fallback: first usable item, then index 1.
  if not bestIdx then
    for i = 1, numChoices do
      local _, _, _, _, isUsable = GetQuestItemInfo("choice", i)
      if isUsable then bestIdx = i; break end
    end
    if not bestIdx then bestIdx = 1 end
  end

  GetQuestReward(bestIdx)
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function M:Apply()
  local db = NS:GetDB()
  if not db or not db.questreward or db.questreward.enabled == false then
    return self:Disable()
  end
  M.active = true

  if not state.eventFrame then
    state.eventFrame = CreateFrame("Frame")
    state.eventFrame:RegisterEvent("QUEST_COMPLETE")
    state.eventFrame:SetScript("OnEvent", function(_, event)
      if not M.active then return end
      if event ~= "QUEST_COMPLETE" then return end
      -- Delay so the player can see the reward choices for a moment.
      C_Timer.After(1.5, function()
        if not M.active then return end
        -- Guard: only fire if the quest frame is still visible.
        if QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then
          SelectBestReward()
        end
      end)
    end)
  end
end

function M:Disable()
  M.active = false
  if state.eventFrame then
    state.eventFrame:UnregisterAllEvents()
    state.eventFrame:SetScript("OnEvent", nil)
    state.eventFrame = nil
  end
end
