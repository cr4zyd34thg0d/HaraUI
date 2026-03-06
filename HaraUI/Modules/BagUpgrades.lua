local ADDON, NS = ...
local M = {}
NS:RegisterModule("bagupgrades", M)
M.active = false

local state = {
  eventFrame = nil,
  hooked = false,
  buttons = setmetatable({}, { __mode = "k" }),
}

local CLASS_ARMOR_TYPE = {
  WARRIOR     = "Plate",
  PALADIN     = "Plate",
  DEATHKNIGHT = "Plate",
  HUNTER      = "Mail",
  SHAMAN      = "Mail",
  EVOKER      = "Mail",
  DRUID       = "Leather",
  MONK        = "Leather",
  ROGUE       = "Leather",
  DEMONHUNTER = "Leather",
  MAGE        = "Cloth",
  PRIEST      = "Cloth",
  WARLOCK     = "Cloth",
}

local PRIMARY_STAT_KEY = {
  [1] = "ITEM_MOD_STRENGTH_SHORT",
  [2] = "ITEM_MOD_AGILITY_SHORT",
  [3] = "ITEM_MOD_INTELLECT_SHORT",
}

local ACCESSORY_EQUIP_LOCS = {
  INVTYPE_NECK    = true,
  INVTYPE_FINGER  = true,
  INVTYPE_CLOAK   = true,
  INVTYPE_TRINKET = true,
}

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
  INVTYPE_SHIELD         = { 17 },
  INVTYPE_RANGED         = { 16 },
  INVTYPE_RANGEDRIGHT    = { 16 },
}

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

  local info = C_Container and C_Container.GetContainerItemInfo
    and C_Container.GetContainerItemInfo(bagID, slot) or nil
  local link = info and info.hyperlink
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

  local link = GetInventoryItemLink("player", invSlot)
  if link then
    local _, _, _, itemLevel = GetItemInfo(link)
    return itemLevel or 0
  end
  return 0
end

local function PickDualSlot(slotA, slotB)
  local a = GetEquippedIlvl(slotA)
  local b = GetEquippedIlvl(slotB)
  if a <= b then return slotA, a end
  return slotB, b
end

local function GetBagAndSlot(button)
  if type(button) ~= "table" then return nil, nil end

  local bag = button.GetBagID and button:GetBagID() or nil
  if bag == nil and button.GetParent then
    local parent = button:GetParent()
    if parent and parent.GetID then
      bag = parent:GetID()
    end
  end

  local slot = button.GetID and button:GetID() or nil
  if type(bag) ~= "number" or type(slot) ~= "number" then
    return nil, nil
  end
  return bag, slot
end

local function EnsureArrow(button)
  if button._huiUpgradeArrow then
    return button._huiUpgradeArrow
  end

  local arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
  arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
  arrow:SetSize(14, 14)
  arrow:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  arrow:SetRotation(-math.pi / 2)
  arrow:SetVertexColor(0.35, 1.00, 0.35, 0.95)
  arrow:Hide()
  button._huiUpgradeArrow = arrow
  return arrow
end

local function HideArrow(button)
  local arrow = button and button._huiUpgradeArrow
  if arrow then
    arrow:Hide()
  end
end

local function IsUsableUpgrade(link, itemType, subType, equipLoc, bagIlvl, equippedIlvl)
  if not link or not equipLoc or bagIlvl <= equippedIlvl then
    return false
  end

  if IsUsableItem then
    local usable = IsUsableItem(link)
    if usable == false then
      return false
    end
  end

  if ACCESSORY_EQUIP_LOCS[equipLoc] or itemType ~= "Armor" then
    return true
  end

  if subType ~= GetPlayerArmorType() then
    return false
  end

  local primaryStatKey = GetPlayerPrimaryStatKey()
  if not primaryStatKey then
    return true
  end

  local stats
  if C_Item and C_Item.GetItemStats then
    stats = C_Item.GetItemStats(link)
  elseif GetItemStats then
    stats = {}
    GetItemStats(link, stats)
  end

  if stats and not (stats[primaryStatKey] and stats[primaryStatKey] > 0) then
    return false
  end

  return true
end

local function IsBagItemUpgrade(bag, slot)
  if type(bag) ~= "number" or type(slot) ~= "number" then
    return false
  end

  local info = C_Container and C_Container.GetContainerItemInfo
    and C_Container.GetContainerItemInfo(bag, slot) or nil
  local link = info and info.hyperlink
  if not link then
    return false
  end

  local _, _, _, _, _, itemType, subType, _, equipLoc = GetItemInfo(link)
  local slots = equipLoc and EQUIP_LOC_TO_SLOTS[equipLoc] or nil
  if not slots then
    return false
  end

  local targetSlot, equippedIlvl
  if #slots == 2 then
    targetSlot, equippedIlvl = PickDualSlot(slots[1], slots[2])
  else
    targetSlot = slots[1]
    equippedIlvl = GetEquippedIlvl(targetSlot)
  end

  if not targetSlot then
    return false
  end

  local bagIlvl = GetEffectiveIlvl(bag, slot)
  return IsUsableUpgrade(link, itemType, subType, equipLoc, bagIlvl, equippedIlvl or 0)
end

local function UpdateButton(button)
  if not M.active then
    HideArrow(button)
    return
  end

  local bag, slot = GetBagAndSlot(button)
  if not bag or not slot then
    HideArrow(button)
    return
  end

  local arrow = EnsureArrow(button)
  if IsBagItemUpgrade(bag, slot) then
    arrow:Show()
  else
    arrow:Hide()
  end
end

local function RefreshTrackedButtons()
  for button in pairs(state.buttons) do
    UpdateButton(button)
  end
end

local function TrackButton(button)
  if type(button) ~= "table" then
    return
  end

  local bag, slot = GetBagAndSlot(button)
  if not bag or not slot then
    HideArrow(button)
    return
  end

  state.buttons[button] = true
  UpdateButton(button)
end

local function EnsureHooks()
  if state.hooked then
    return
  end

  hooksecurefunc("SetItemButtonQuality", function(button)
    TrackButton(button)
  end)

  if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnLoad then
    hooksecurefunc(ContainerFrameItemButtonMixin, "OnLoad", function(button)
      TrackButton(button)
    end)
  end

  state.hooked = true
end

local function EnsureEvents()
  if state.eventFrame then
    return
  end

  state.eventFrame = CreateFrame("Frame")
  state.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
  state.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  state.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  state.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  state.eventFrame:SetScript("OnEvent", function(_, _, unit)
    if not M.active then return end
    if unit and unit ~= "player" then return end
    C_Timer.After(0, RefreshTrackedButtons)
  end)
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.bagupgrades or db.bagupgrades.enabled == false then
    return self:Disable()
  end

  M.active = true
  EnsureHooks()
  EnsureEvents()
  RefreshTrackedButtons()
end

function M:Disable()
  M.active = false
  if state.eventFrame then
    state.eventFrame:UnregisterAllEvents()
    state.eventFrame:SetScript("OnEvent", nil)
    state.eventFrame = nil
  end

  for button in pairs(state.buttons) do
    HideArrow(button)
  end
end
