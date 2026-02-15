local ADDON, NS = ...

local modules = NS and NS.Modules
local M = modules and modules.rotationhelper
if not M then return end
local K = M.Keybinds or {}
M.Keybinds = K

local LookupActionBySlot = {}
local KeybindBySpellID = {}
local CacheVersion = 0

local DefaultActionSlotMap = {
  { actionPrefix = "ACTIONBUTTON",          start = 1,  last = 12 },
  { actionPrefix = "ACTIONBUTTON",          start = 13, last = 24 },
  { actionPrefix = "MULTIACTIONBAR3BUTTON", start = 25, last = 36 },
  { actionPrefix = "MULTIACTIONBAR4BUTTON", start = 37, last = 48 },
  { actionPrefix = "MULTIACTIONBAR2BUTTON", start = 49, last = 60 },
  { actionPrefix = "MULTIACTIONBAR1BUTTON", start = 61, last = 72 },
  { actionPrefix = "ACTIONBUTTON",          start = 73, last = 84 },
  { actionPrefix = "ACTIONBUTTON",          start = 85, last = 96 },
  { actionPrefix = "ACTIONBUTTON",          start = 97, last = 108 },
  { actionPrefix = "ACTIONBUTTON",          start = 109,last = 120 },
  { actionPrefix = "ACTIONBUTTON",          start = 121,last = 132 },
  { actionPrefix = "MULTIACTIONBAR5BUTTON", start = 145,last = 156 },
  { actionPrefix = "MULTIACTIONBAR6BUTTON", start = 157,last = 168 },
  { actionPrefix = "MULTIACTIONBAR7BUTTON", start = 169,last = 180 },
}

local function GetButtonKeybind(btn)
  local name = btn and btn.GetName and btn:GetName()
  if not name then return nil end
  local key1, key2 = GetBindingKey(name)
  return key1 or key2
end

local function BuildActionSlotMap()
  if next(LookupActionBySlot) then return end
  for _, info in ipairs(DefaultActionSlotMap) do
    for slot = info.start, info.last do
      local index = slot - info.start + 1
      LookupActionBySlot[slot] = info.actionPrefix .. index
    end
  end
end

local function GetBindingForAction(action)
  if not action then return nil end
  local key = GetBindingKey(action)
  if not key then return nil end
  return GetBindingText(key, "KEY_")
end

local function InvalidateCache()
  wipe(KeybindBySpellID)
  CacheVersion = CacheVersion + 1
end

local function GetCacheVersion()
  return CacheVersion
end

local function GetKeyBindForSpellID(spellID)
  if not (C_ActionBar and C_ActionBar.FindSpellActionButtons and spellID) then return nil end
  local cached = KeybindBySpellID[spellID]
  if cached ~= nil then
    return cached or nil
  end
  BuildActionSlotMap()
  local slots = C_ActionBar.FindSpellActionButtons(spellID)
  if not slots then
    KeybindBySpellID[spellID] = false
    return nil
  end
  for _, slot in ipairs(slots) do
    local action = LookupActionBySlot[slot]
    local text = GetBindingForAction(action)
    if text then
      KeybindBySpellID[spellID] = text
      return text
    end
  end
  KeybindBySpellID[spellID] = false
  return nil
end

K.GetButtonKeybind = GetButtonKeybind
K.BuildActionSlotMap = BuildActionSlotMap
K.GetBindingForAction = GetBindingForAction
K.GetKeyBindForSpellID = GetKeyBindForSpellID
K.InvalidateCache = InvalidateCache
K.GetCacheVersion = GetCacheVersion
