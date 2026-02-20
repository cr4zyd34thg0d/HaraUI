local ADDON, NS = ...

local AP = NS.AltPanel
if not AP then return end

AP.Equipment = AP.Equipment or {}
local Equipment = AP.Equipment

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local POPUP_WIDTH  = 260
local POPUP_HEIGHT = 460
local SLOT_HEIGHT  = 24
local ICON_SIZE    = 20

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
Equipment._state = Equipment._state or {
  created    = false,
  frame      = nil,
  slotFrames = {},
  currentGUID = nil,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function ApplyFont(fs, size)
  if not fs then return end
  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(fs, size or 12)
  end
end

local function GetSkin()
  local cs = NS.CharacterSheet
  return cs and cs.Skin or nil
end

local function SetVerticalGradient(tex, topR, topG, topB, topA, botR, botG, botB, botA)
  local Skin = GetSkin()
  if Skin and Skin.SetVerticalGradient then
    Skin.SetVerticalGradient(tex, topR, topG, topB, topA, botR, botG, botB, botA)
  else
    tex:SetColorTexture(botR, botG, botB, botA)
  end
end

local QUALITY_COLORS = {
  [0] = { 0.62, 0.62, 0.62 }, -- Poor
  [1] = { 1.00, 1.00, 1.00 }, -- Common
  [2] = { 0.12, 1.00, 0.00 }, -- Uncommon
  [3] = { 0.00, 0.44, 0.87 }, -- Rare
  [4] = { 0.64, 0.21, 0.93 }, -- Epic
  [5] = { 1.00, 0.50, 0.00 }, -- Legendary
  [6] = { 0.90, 0.80, 0.50 }, -- Artifact
  [7] = { 0.00, 0.80, 1.00 }, -- Heirloom
}

local function GetQualityColor(quality)
  local c = QUALITY_COLORS[quality or 1]
  if c then return c[1], c[2], c[3] end
  return 1, 1, 1
end

---------------------------------------------------------------------------
-- Create slot row
---------------------------------------------------------------------------
local function CreateSlotRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(SLOT_HEIGHT)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON_SIZE, ICON_SIZE)
  row.icon:SetPoint("LEFT", 6, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.icon:SetTexture(134400)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -40, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetMaxLines(1)
  if row.name.SetWordWrap then row.name:SetWordWrap(false) end
  ApplyFont(row.name, 11)

  row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.ilvl:SetPoint("RIGHT", -8, 0)
  row.ilvl:SetWidth(32)
  row.ilvl:SetJustifyH("RIGHT")
  ApplyFont(row.ilvl, 11)

  -- Stripe background
  if (index % 2) == 0 then
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(0.08, 0.08, 0.12, 0.25)
  end

  -- Tooltip on hover (show itemLink if available)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if self._itemLink and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self._itemLink)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  return row
end

---------------------------------------------------------------------------
-- Build popup frame
---------------------------------------------------------------------------
function Equipment:Create()
  local s = self._state
  if s.created and s.frame then return s.frame end

  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
  f:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  f:SetBackdropColor(0, 0, 0, 0)
  f:SetBackdropBorderColor(0.58, 0.60, 0.70, 0.30)
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(120)
  f:EnableMouse(true)
  f:Hide()

  -- Gradient background
  f.bgGradient = f:CreateTexture(nil, "BACKGROUND")
  f.bgGradient:SetAllPoints()
  f.bgGradient:SetTexture("Interface/Buttons/WHITE8x8")
  SetVerticalGradient(f.bgGradient, 0.02, 0.02, 0.04, 0.95, 0.06, 0.02, 0.10, 0.95)

  -- Title
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.title:SetPoint("TOP", 0, -8)
  f.title:SetText("Equipment")
  f.title:SetTextColor(0.98, 0.64, 0.14, 1)
  ApplyFont(f.title, 13)

  -- Create 16 slot rows
  s.slotFrames = {}
  for i = 1, 16 do
    local row = CreateSlotRow(f, i)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(28 + (i - 1) * SLOT_HEIGHT))
    row:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    s.slotFrames[i] = row
  end

  -- Adjust popup height to fit content
  local totalH = 28 + (16 * SLOT_HEIGHT) + 8
  f:SetHeight(totalH)

  s.frame = f
  s.created = true

  return f
end

---------------------------------------------------------------------------
-- Populate with a character's equipment
---------------------------------------------------------------------------
function Equipment:ShowForCharacter(guid, anchorFrame)
  local f = self:Create()
  local s = self._state
  local Data = AP.Data
  if not Data then return end

  local chars = Data.GetCharacterTable()
  if not chars or not chars[guid] then return end

  local char = chars[guid]
  s.currentGUID = guid

  -- Title
  local name = char.info and char.info.name or "Unknown"
  f.title:SetText(name .. "'s Gear")

  -- Anchor to the main window's right edge
  f:ClearAllPoints()
  local mainWindow = AP.Window and AP.Window._state and AP.Window._state.frame
  if mainWindow then
    f:SetPoint("TOPLEFT", mainWindow, "TOPRIGHT", 4, 0)
  elseif anchorFrame then
    f:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
  end

  -- Populate slots
  local equip = char.equipment or {}
  for i = 1, 16 do
    local row = s.slotFrames[i]
    local item = equip[i]
    if item then
      row.icon:SetTexture(item.icon or 134400)
      row.name:SetText(item.itemName or "")
      local qr, qg, qb = GetQualityColor(item.quality)
      row.name:SetTextColor(qr, qg, qb)
      row.ilvl:SetText(item.itemLevel and item.itemLevel > 0 and tostring(item.itemLevel) or "")
      row.ilvl:SetTextColor(0.85, 0.85, 0.85)
      row._itemLink = item.itemLink
      row:Show()
    else
      row.icon:SetTexture(134400)
      row.name:SetText("")
      row.ilvl:SetText("")
      row._itemLink = nil
      row:Show()
    end
  end

  f:Show()
  f:Raise()
end

---------------------------------------------------------------------------
-- Toggle / Hide
---------------------------------------------------------------------------
function Equipment:Toggle(guid, anchorFrame)
  local s = self._state
  if s.frame and s.frame:IsShown() and s.currentGUID == guid then
    self:Hide()
  else
    self:ShowForCharacter(guid, anchorFrame)
  end
end

function Equipment:Hide()
  local s = self._state
  if s.frame then
    s.frame:Hide()
  end
  s.currentGUID = nil
end
