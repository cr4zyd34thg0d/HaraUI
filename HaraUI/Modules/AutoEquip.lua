--[[
  Auto Equip Module

  Scans bags whenever BAG_UPDATE_DELAYED fires and automatically equips any
  already-bound item that is an item-level upgrade for its slot, matches the
  player's armor type, and carries the player's primary stat.

  Conditions for auto-equip:
    • Item is soulbound (isBound == true) — avoids BoE dialog prompts.
    • Item is NOT locked (being traded / looted).
    • Not in combat lockdown.
    • Item ilvl > currently equipped ilvl for that slot.
    • For armor pieces: same armor type as player's class.
    • For armor pieces: carries the player's spec primary stat.
    • Accessories (neck, cloak, finger, trinket) skip armor/stat checks;
      only ilvl comparison applies.

  Events:
    BAG_UPDATE_DELAYED
--]]

local _, NS = ...
local M = {}
NS:RegisterModule("autoequip", M)
M.active = false

local state = {
  eventFrame  = nil,
  throttleKey = "autoequip_scan",
}

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local CLASS_ARMOR_TYPE      = NS.ITEM_CLASS_ARMOR_TYPE
local PRIMARY_STAT_KEY      = NS.ITEM_PRIMARY_STAT_KEY
local ACCESSORY_EQUIP_LOCS  = NS.ITEM_ACCESSORY_EQUIP_LOCS

-- Maps equipLoc → { primary slot, secondary slot or nil }
local EQUIP_LOC_TO_SLOTS = {
  INVTYPE_HEAD           = { 1  },
  INVTYPE_NECK           = { 2  },
  INVTYPE_SHOULDER       = { 3  },
  INVTYPE_CLOAK          = { 15 },
  INVTYPE_CHEST          = { 5  },
  INVTYPE_ROBE           = { 5  },
  INVTYPE_WRIST          = { 9  },
  INVTYPE_HAND           = { 10 },
  INVTYPE_WAIST          = { 6  },
  INVTYPE_LEGS           = { 7  },
  INVTYPE_FEET           = { 8  },
  INVTYPE_FINGER         = { 11, 12 },
  INVTYPE_TRINKET        = { 13, 14 },
  INVTYPE_2HWEAPON       = { 16 },
  INVTYPE_WEAPON         = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND  = { 17 },
  INVTYPE_HOLDABLE       = { 17 },
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

local function GetEffectiveIlvl(bagID, slot)
  if C_Item and C_Item.GetCurrentItemLevel and ItemLocation then
    local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
      return C_Item.GetCurrentItemLevel(loc) or 0
    end
  end
  -- Fallback: read ilvl from GetItemInfo on the link.
  local info = C_Container and C_Container.GetContainerItemInfo
    and C_Container.GetContainerItemInfo(bagID, slot) or nil
  local link = info and (info.hyperlink)
  if link then
    local _, _, _, itemLevel = GetItemInfo(link)
    return itemLevel or 0
  end
  return 0
end

local function GetEquippedIlvl(invSlot)
  if C_Item and C_Item.GetCurrentItemLevel and ItemLocation then
    local loc = ItemLocation:CreateFromEquipmentSlot(invSlot)
    if loc and C_Item.DoesItemExist(loc) then
      return C_Item.GetCurrentItemLevel(loc) or 0
    end
  end
  -- Fallback: read ilvl from the equipped item link.
  local link = GetInventoryItemLink("player", invSlot)
  if link then
    local _, _, _, itemLevel = GetItemInfo(link)
    return itemLevel or 0
  end
  return 0
end

-- For dual-slot items return the target slot (lower ilvl = best upgrade target).
local function PickDualSlot(slotA, slotB)
  local a = GetEquippedIlvl(slotA)
  local b = GetEquippedIlvl(slotB)
  if a <= b then return slotA, a end
  return slotB, b
end

---------------------------------------------------------------------------
-- Core scan: one pass through all bags
---------------------------------------------------------------------------
local function ScanAndEquip()
  if InCombatLockdown and InCombatLockdown() then return end

  local armorType      = GetPlayerArmorType()
  local primaryStatKey = GetPlayerPrimaryStatKey()

  for bag = 0, 4 do
    local numSlots = C_Container and C_Container.GetContainerNumSlots
      and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, numSlots do
      local info = C_Container and C_Container.GetContainerItemInfo
        and C_Container.GetContainerItemInfo(bag, slot) or nil

      -- Only consider already-bound, unlocked items.
      local link = info and (info.hyperlink)
      if info and info.isBound and not info.isLocked and link then
        local _, _, _, itemLevel, _, itemType, subType, _, equipLoc =
          GetItemInfo(link)

        -- Must be equippable and have a known slot mapping.
        local slots = equipLoc and EQUIP_LOC_TO_SLOTS[equipLoc] or nil
        if slots and itemLevel and itemLevel > 0 then

          -- Pick the best target inventory slot.
          local targetSlot, equippedIlvl
          if #slots == 2 then
            targetSlot, equippedIlvl = PickDualSlot(slots[1], slots[2])
          else
            targetSlot = slots[1]
            equippedIlvl = GetEquippedIlvl(targetSlot)
          end

          local bagIlvl = GetEffectiveIlvl(bag, slot)
          local isUpgrade = (bagIlvl > equippedIlvl)

          if isUpgrade then
            -- Accessory: skip armor/stat checks.
            local passesTypeCheck = true
            if not ACCESSORY_EQUIP_LOCS[equipLoc] and itemType == "Armor" then
              -- Armor-type check.
              passesTypeCheck = (subType == armorType)
              -- Primary stat check.
              if passesTypeCheck and primaryStatKey then
                local stats
                if C_Item and C_Item.GetItemStats then
                  stats = C_Item.GetItemStats(link)
                elseif GetItemStats then
                  stats = {}
                  GetItemStats(link, stats)
                end
                if stats and not (stats[primaryStatKey] and stats[primaryStatKey] > 0) then
                  passesTypeCheck = false
                end
                -- If neither API exists, pass the check; armor auto-adjusts primary stat.
              end
            end

            if passesTypeCheck then
              -- Equip the item.
              if C_Container and C_Container.PickupContainerItem then
                C_Container.PickupContainerItem(bag, slot)
              else
                PickupContainerItem(bag, slot)
              end
              if CursorHasItem and CursorHasItem() then
                EquipCursorItem(targetSlot)
              else
                if ClearCursor then ClearCursor() end
              end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function M:Apply()
  local db = NS:GetDB()
  if not db or not db.autoequip or db.autoequip.enabled == false then
    return self:Disable()
  end
  M.active = true

  if not state.eventFrame then
    state.eventFrame = CreateFrame("Frame")
    state.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    state.eventFrame:SetScript("OnEvent", function(_, event)
      if not M.active then return end
      if event ~= "BAG_UPDATE_DELAYED" then return end
      -- Throttle: at most once per second.
      if not state._nextScan or GetTime() >= state._nextScan then
        state._nextScan = GetTime() + 1.0
        C_Timer.After(0, function()
          if M.active then ScanAndEquip() end
        end)
      end
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
  state._nextScan = nil
end
