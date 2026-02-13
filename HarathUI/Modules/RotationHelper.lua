--[[
  Rotation Helper Module

  Interface:
    M:Apply()        - Initialize/update with current settings
    M:Disable()      - Clean up and hide
    M:SetLocked()    - Toggle drag mode
    M:Preview()      - Show preview state

  Dependencies:
    - C_AssistedCombat API (WoW 12.0+)
    - C_ActionBar API for keybind detection
--]]

local ADDON, NS = ...
local M = {}
NS:RegisterModule("rotationhelper", M)
M.active = false

local frame
local previewActive = false
local previewKey = "1"
local previewIcon = "Interface\\Icons\\INV_Sword_04"
local LookupActionBySlot = {}
local lastSpellTex
local lastSpellKey

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
local function IsEnabled()
  local db = NS:GetDB()
  return db and db.rotationhelper and db.rotationhelper.enabled
end

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

local function GetKeyBindForSpellID(spellID)
  if not (C_ActionBar and C_ActionBar.FindSpellActionButtons and spellID) then return nil end
  BuildActionSlotMap()
  local slots = C_ActionBar.FindSpellActionButtons(spellID)
  if not slots then return nil end
  for _, slot in ipairs(slots) do
    local action = LookupActionBySlot[slot]
    local text = GetBindingForAction(action)
    if text then return text end
  end
  return nil
end

local function IsFramesUnlocked()
  local db = NS:GetDB()
  return db and db.general and db.general.framesLocked == false
end

local function ShowUnlockPlaceholder()
  if not frame then return end
  frame._huiUnlockPlaceholder = true
  frame.icon:SetTexture(134400)
  frame.keyText:SetText("")
  frame:Show()
end

local function UpdateFromAssist()
  if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then
    if frame then
      if IsFramesUnlocked() then
        ShowUnlockPlaceholder()
      else
        frame._huiUnlockPlaceholder = nil
        frame:Hide()
      end
    end
    return
  end
  local spellID = C_AssistedCombat.GetNextCastSpell()
  if not spellID or spellID == 0 then
    if frame and lastSpellTex then
      frame._huiUnlockPlaceholder = nil
      frame.icon:SetTexture(lastSpellTex)
      frame.keyText:SetText(lastSpellKey or "")
      frame:Show()
    elseif frame then
      if IsFramesUnlocked() then
        ShowUnlockPlaceholder()
      else
        frame._huiUnlockPlaceholder = nil
        frame:Hide()
      end
    end
    return
  end
  local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or GetSpellTexture(spellID)
  if not tex then
    if frame then
      if IsFramesUnlocked() then
        ShowUnlockPlaceholder()
      else
        frame._huiUnlockPlaceholder = nil
        frame:Hide()
      end
    end
    return
  end
  frame._huiUnlockPlaceholder = nil
  frame.icon:SetTexture(tex)
  frame.icon:SetVertexColor(1, 1, 1, 1)
  lastSpellTex = tex
  lastSpellKey = GetKeyBindForSpellID(spellID) or ""
  frame.keyText:SetText(lastSpellKey)
  frame:Show()
end

local function Create()
  frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  frame:SetSize(52, 52)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(200)

  -- Pixel-perfect background (1px border)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints(true)
  frame.bg:SetColorTexture(0, 0, 0, 1)

  -- Pixel-perfect icon with 1px inset on all sides
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  frame.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

  -- Disable texture filtering for crisp pixels
  if frame.icon.SetSnapToPixelGrid then
    frame.icon:SetSnapToPixelGrid(false)
  end
  if frame.icon.SetTexelSnappingBias then
    frame.icon:SetTexelSnappingBias(0)
  end

  -- Optional: Add subtle inner shadow/border for depth
  frame.border = frame:CreateTexture(nil, "OVERLAY")
  frame.border:SetAllPoints(frame.icon)
  frame.border:SetColorTexture(0, 0, 0, 0.3)
  frame.border:SetBlendMode("BLEND")
  frame.border:Hide() -- Start hidden, can enable for style

  frame.keyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.keyText:SetPoint("TOPRIGHT", -4, -3)
  frame.keyText:SetTextColor(1, 1, 1, 1)
  frame.keyText:SetShadowOffset(1, -1)
  frame.keyText:SetShadowColor(0, 0, 0, 1)
  frame.keyText:SetJustifyH("RIGHT")
  if GameFontNormalSmall and GameFontNormalSmall.GetFont then
    local fontPath = GameFontNormalSmall:GetFont()
    if fontPath then
      frame.keyText:SetFont(fontPath, 15, "THICKOUTLINE")
    end
  elseif STANDARD_TEXT_FONT then
    frame.keyText:SetFont(STANDARD_TEXT_FONT, 15, "THICKOUTLINE")
  end

  frame:Hide()

  NS:MakeMovable(frame, "rotationhelper", "Rotation Helper (drag)")
end

function M:SetLocked(locked)
  if not M.active or not frame or not frame._huiMover then return end
  if locked then
    frame:EnableMouse(false)
    frame._huiMover:Hide()
    if frame._huiUnlockPlaceholder and not previewActive then
      frame._huiUnlockPlaceholder = nil
      frame:Hide()
    end
  else
    frame:EnableMouse(true)
    frame._huiMover:Show()
    if not frame:IsShown() and not previewActive then
      ShowUnlockPlaceholder()
    end
  end
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.rotationhelper or not db.rotationhelper.enabled then
    self:Disable()
    return
  end
  M.active = true

  if not frame then Create() end

  BuildActionSlotMap()

  frame:SetSize(db.rotationhelper.width, db.rotationhelper.height)
  frame:SetScale(db.rotationhelper.scale)
  frame:ClearAllPoints()
  frame:SetPoint(db.rotationhelper.anchor, UIParent, db.rotationhelper.anchor, db.rotationhelper.x, db.rotationhelper.y)

  M:SetLocked(db.general.framesLocked)
  if previewActive then
    frame._huiUnlockPlaceholder = nil
    frame.icon:SetTexture(previewIcon)
    frame.keyText:SetText(previewKey)
    frame:Show()
  else
    UpdateFromAssist()
  end

  frame:SetScript("OnUpdate", function(_, elapsed)
    if not M.active or not IsEnabled() then return end
    if previewActive then return end
    UpdateFromAssist()
  end)
end

function M:Preview()
  previewActive = not previewActive
  M:Apply()
  return previewActive
end

function M:Disable()
  M.active = false
  previewActive = false
  if frame then frame:Hide() end
  if frame then
    frame._huiUnlockPlaceholder = nil
    frame:SetScript("OnUpdate", nil)
  end
end
