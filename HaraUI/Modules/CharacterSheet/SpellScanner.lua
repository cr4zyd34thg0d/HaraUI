local ADDON, NS = ...
NS.CharacterSheet = NS.CharacterSheet or {}
local CS = NS.CharacterSheet

CS.SpellScanner = CS.SpellScanner or {}
local SpellScanner = CS.SpellScanner

---------------------------------------------------------------------------
-- Shared spellbook scanning utilities.
--
-- Used by both MythicPanel (FindPortalSpellForMap) and PortalPanel
-- (ScanAllPortalSpells).  Previously each file had its own identical copy
-- of these 7 functions; they now live here.
--
-- Load order: must appear before MythicPanel.lua in the TOC.
---------------------------------------------------------------------------

--- Lowercase, collapse punctuation and whitespace, strip leading/trailing spaces.
function SpellScanner.NormalizeName(s)
  if type(s) ~= "string" then return "" end
  s = string.lower(s)
  s = s:gsub("[%p]", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

--- Cross-version IsSpellKnown: tries the three API variants in precedence order.
function SpellScanner.IsSpellKnownCompat(spellID)
  if not spellID then return false end
  if IsSpellKnownOrOverridesKnown then return IsSpellKnownOrOverridesKnown(spellID) end
  if IsSpellKnown then return IsSpellKnown(spellID) end
  if IsPlayerSpell then return IsPlayerSpell(spellID) end
  return false
end

--- True when itemType matches the "SPELL" or "FLYOUT" string token or numeric Enum value.
function SpellScanner.IsItemType(itemType, want)
  if itemType == want then return true end
  if type(itemType) == "number" and Enum and Enum.SpellBookItemType then
    if want == "SPELL"   and itemType == Enum.SpellBookItemType.Spell   then return true end
    if want == "FLYOUT"  and itemType == Enum.SpellBookItemType.Flyout  then return true end
  end
  return false
end

--- Unpack a GetSpellBookItemInfo result whether it returns a table (11.x) or two values (pre-11.x).
function SpellScanner.UnpackSpellBookItemInfo(a, b)
  if type(a) == "table" then
    local itemType = a.itemType or a.spellType
    local id
    if SpellScanner.IsItemType(itemType, "SPELL") then
      id = a.spellID or a.actionID
    elseif SpellScanner.IsItemType(itemType, "FLYOUT") then
      id = a.flyoutID or a.actionID
    else
      id = a.spellID or a.flyoutID or a.actionID
    end
    return itemType, id
  end
  return a, b
end

--- Extract (offset, count) from a GetSpellBookSkillLineInfo result (table or 4-value tuple).
function SpellScanner.GetSkillLineRange(tab)
  if type(tab) == "table" then
    local offset = tab.itemIndexOffset or tab.offset or tab.offSet
    local count  = tab.numSpellBookItems or tab.numSlots or tab.numSpells
    if type(offset) == "number" and type(count) == "number" then
      return offset, count
    end
  end
  return nil, nil
end

--- Return the number of slots in a flyout, handling both table and tuple API returns.
function SpellScanner.GetFlyoutSlots(flyoutID)
  if not flyoutID then return 0 end
  if C_SpellBook and C_SpellBook.GetFlyoutInfo then
    local info = C_SpellBook.GetFlyoutInfo(flyoutID)
    if type(info) == "table" then
      return tonumber(info.numSlots) or tonumber(info.numKnownSlots) or 0
    end
    local _, _, numSlots = C_SpellBook.GetFlyoutInfo(flyoutID)
    return tonumber(numSlots) or 0
  end
  if GetFlyoutInfo then
    local _, _, numSlots = GetFlyoutInfo(flyoutID)
    return tonumber(numSlots) or 0
  end
  return 0
end

--- Return (spellID, overrideSpellID, isKnown) for a flyout slot, handling table vs tuple returns.
function SpellScanner.GetFlyoutSpellAt(flyoutID, slotIndex)
  if C_SpellBook and C_SpellBook.GetFlyoutSlotInfo then
    local a, b, c = C_SpellBook.GetFlyoutSlotInfo(flyoutID, slotIndex)
    if type(a) == "table" then
      return a.spellID, a.overrideSpellID, a.isKnown
    end
    return a, b, c
  end
  if GetFlyoutSlotInfo then
    return GetFlyoutSlotInfo(flyoutID, slotIndex)
  end
  return nil, nil, nil
end
