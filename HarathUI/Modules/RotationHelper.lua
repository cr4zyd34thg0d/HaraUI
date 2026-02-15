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
local lastSpellTex
local lastSpellKey
local K = NS.RotationHelperKeybinds
local function IsEnabled()
  local db = NS:GetDB()
  return db and db.rotationhelper and db.rotationhelper.enabled
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
  lastSpellKey = K.GetKeyBindForSpellID(spellID) or ""
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
  NS:ApplyDefaultFont(frame.keyText, 15)

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

  K.BuildActionSlotMap()

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
