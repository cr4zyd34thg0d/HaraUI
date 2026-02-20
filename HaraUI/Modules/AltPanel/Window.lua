local ADDON, NS = ...

local AP = NS.AltPanel
if not AP then return end

AP.Window = AP.Window or {}
local Window = AP.Window

---------------------------------------------------------------------------
-- Layout constants
---------------------------------------------------------------------------
local LW_STATS    = 150  -- Character / Realm / Item Level / Rating / Keystone / Vault
local LW_DUNGEONS = 150  -- Dungeon rows (name + icon prefix)
local LW_RAID     = 150  -- Raid difficulty rows (LFR / Normal / Heroic / Mythic)
local LW_CURRENCY = 150  -- Currency rows (name + icon prefix)
local LABEL_WIDTH = math.max(LW_STATS, LW_DUNGEONS, LW_RAID, LW_CURRENCY)  -- window width
local CHAR_COL_WIDTH = 140
local ROW_HEIGHT     = 22
local ROW_GAP        = 3
local SECTION_HEIGHT = ROW_HEIGHT
local TITLE_HEIGHT   = 30
local MIN_WINDOW_W   = 420
local MAX_WINDOW_W   = 1200
local MIN_WINDOW_H   = 300
local MAX_WINDOW_H   = 900
local SCROLLBAR_W    = 4
local BOTTOM_PAD     = 8
local SECTION_GAP    = 14
local PANEL_MARGIN_X = 5   -- left/right gap between panel edge and window edge

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
Window._state = Window._state or {
  created      = false,
  frame        = nil,
  scrollFrame  = nil,
  scrollChild  = nil,
  rows         = {},    -- array of row frames (reusable pool)
  numRows      = 0,     -- how many rows are currently in use
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

local function SetVerticalGradient(tex, tR, tG, tB, tA, bR, bG, bB, bA)
  local Skin = GetSkin()
  if Skin and Skin.SetVerticalGradient then
    Skin.SetVerticalGradient(tex, tR, tG, tB, tA, bR, bG, bB, bA)
  else
    tex:SetColorTexture(bR, bG, bB, bA)
  end
end

local function ClassColor(classFile)
  if not classFile or classFile == "" then return 0.95, 0.95, 0.95 end
  local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if cc then return cc.r, cc.g, cc.b end
  return 0.95, 0.95, 0.95
end

local function RatingColor(rating)
  if not rating or rating <= 0 then return 0.40, 0.40, 0.40 end
  if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
    local c = C_ChallengeMode.GetDungeonScoreRarityColor(rating)
    if c then return c.r, c.g, c.b end
  end
  return 0.95, 0.95, 0.95
end

local function KeyLevelColor(level)
  if not level or level <= 0 then return 0.40, 0.40, 0.40 end
  if C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor then
    local c = C_ChallengeMode.GetKeystoneLevelRarityColor(level)
    if c then return c.r, c.g, c.b end
  end
  return 0.95, 0.95, 0.95
end

local DIFF_COLORS = {
  [17] = { 0.12, 0.75, 0.12 },  -- LFR: green
  [14] = { 0.12, 0.56, 1.00 },  -- Normal: blue
  [15] = { 0.78, 0.30, 0.98 },  -- Heroic: purple
  [16] = { 1.00, 0.50, 0.00 },  -- Mythic: orange
}

local SKULL_TEX   = "Interface/TargetingFrame/UI-TargetingFrame-Skull"
local SKULL_SIZE  = 20
local SKULL_GAP   = 0

local SKULL_COLOR_ALIVE = { 0.12, 0.75, 0.12 }
local SKULL_COLOR_DEAD  = { 0.70, 0.15, 0.15 }

local function SetupSkullBar(cell, numEncounters, lockout)
  if not cell.skulls then cell.skulls = {} end
  local size = math.min(SKULL_SIZE, math.floor(CHAR_COL_WIDTH / numEncounters))
  local startX = 0
  for i = 1, numEncounters do
    local tex = cell.skulls[i]
    if not tex then
      tex = cell:CreateTexture(nil, "ARTWORK")
      tex:SetTexture(SKULL_TEX)
      cell.skulls[i] = tex
    end
    tex:SetSize(size, size)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", cell, "TOPLEFT",
      startX + (i - 1) * (size + SKULL_GAP),
      -math.floor((ROW_HEIGHT - size) / 2))
    local killed = lockout and lockout.encounters
      and lockout.encounters[i] and lockout.encounters[i].killed
    local c = killed and SKULL_COLOR_DEAD or SKULL_COLOR_ALIVE
    tex:SetVertexColor(c[1], c[2], c[3], 1)
    tex:Show()
  end
  for i = numEncounters + 1, #cell.skulls do
    cell.skulls[i]:Hide()
  end
end

local function HideSkullBar(cell)
  if cell.skulls then
    for _, tex in ipairs(cell.skulls) do tex:Hide() end
  end
end

local STAR_ATLAS = {
  [1] = "Professions-Icon-Quality-Tier1-Small",
  [2] = "Professions-Icon-Quality-Tier2-Small",
  [3] = "Professions-Icon-Quality-Tier3-Small",
}

local function StarIcon(stars)
  stars = tonumber(stars) or 0
  stars = math.max(0, math.min(3, math.floor(stars + 0.5)))
  if stars <= 0 then return "" end
  local atlas = STAR_ATLAS[stars]
  if not atlas then return "" end
  return ("|A:%s:16:16|a"):format(atlas)
end

local function ComputeStars(bestMS, parMS)
  if type(bestMS) ~= "number" or type(parMS) ~= "number" or parMS <= 0 then return 0 end
  if bestMS > parMS then return 0 end
  local pct = (parMS - bestMS) / parMS
  return pct >= 0.40 and 3 or pct >= 0.20 and 2 or 1
end

---------------------------------------------------------------------------
-- Tooltip helpers
---------------------------------------------------------------------------
local function ShowTip(anchor, builder)
  GameTooltip:SetOwner(anchor, "ANCHOR_BOTTOMRIGHT", 4, ROW_HEIGHT)
  builder()
  GameTooltip:Show()
end

local function HideTip()
  GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Row pool — get or create a row frame with label + cell slots
---------------------------------------------------------------------------
local function EnsureCell(row, cellIndex)
  if row.cells[cellIndex] then return row.cells[cellIndex] end

  local cell = CreateFrame("Frame", nil, row)
  cell:SetHeight(ROW_HEIGHT)
  cell:EnableMouse(true)

  cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cell.text:SetPoint("LEFT", cell, "LEFT", 0, 0)
  cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
  cell.text:SetJustifyH("LEFT")
  cell.text:SetMaxLines(1)
  if cell.text.SetWordWrap then cell.text:SetWordWrap(false) end
  if cell.text.SetNonSpaceWrap then cell.text:SetNonSpaceWrap(false) end
  ApplyFont(cell.text, 11)

  -- Proxy text methods so callers can treat the cell like a FontString
  function cell:SetText(t) self.text:SetText(t) end
  function cell:SetTextColor(r, g, b, a) self.text:SetTextColor(r, g, b, a or 1) end
  function cell:GetText() return self.text:GetText() end

  -- Subtle highlight on hover
  cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
  cell.highlight:SetAllPoints()
  cell.highlight:SetColorTexture(1, 1, 1, 0.04)

  cell:SetScript("OnEnter", function(self)
    if self.tipFunc then self.tipFunc(self) end
  end)
  cell:SetScript("OnLeave", HideTip)
  cell:SetScript("OnMouseDown", function(self, button)
    if self.clickFunc then self.clickFunc(self, button) end
  end)

  row.cells[cellIndex] = cell
  return cell
end

local ROW_PANEL_BACKDROP = {
  bgFile = "Interface/Buttons/WHITE8x8",
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function GetRow(self, index)
  local s = self._state
  if s.rows[index] then return s.rows[index] end

  local row = CreateFrame("Frame", nil, s.scrollChild, "BackdropTemplate")
  row:SetHeight(ROW_HEIGHT)
  row.cells = {}

  -- Stripe background for alternating rows
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(0.06, 0.06, 0.10, 0.20)

  -- Label (left column)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.label:SetPoint("LEFT", PANEL_MARGIN_X + 9, 0)
  row.label:SetWidth(LABEL_WIDTH - 12)
  row.label:SetJustifyH("LEFT")
  row.label:SetMaxLines(1)
  if row.label.SetWordWrap then row.label:SetWordWrap(false) end
  ApplyFont(row.label, 11)


  -- Label area tooltip (fires when mouse is over the row but not a child cell)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if self.labelTip then
      ShowTip(self, function()
        GameTooltip:AddLine(self.labelTip, 0.98, 0.64, 0.14)
        if self.labelTipSub then
          GameTooltip:AddLine(self.labelTipSub, 0.70, 0.70, 0.70)
        end
      end)
    end
  end)
  row:SetScript("OnLeave", HideTip)

  s.rows[index] = row
  return row
end

---------------------------------------------------------------------------
-- Configure a row as a section header
---------------------------------------------------------------------------
local function ConfigureAsSection(row, text, yOffset)
  row:SetHeight(SECTION_HEIGHT)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", PANEL_MARGIN_X, yOffset)
  row:SetPoint("RIGHT", row:GetParent(), "RIGHT", -PANEL_MARGIN_X, 0)
  row:SetBackdrop(nil)
  row.stripe:SetColorTexture(0, 0, 0, 0)
  row.label:SetWidth(300)
  row.label:SetJustifyH("LEFT")
  row.label:SetText(text)
  row.label:SetTextColor(0.98, 0.64, 0.14, 1)
  ApplyFont(row.label, 12)
  row.labelTip = nil
  row.labelTipSub = nil
  -- Hide all cells
  for _, cell in pairs(row.cells) do
    cell:SetText("")
    cell:Hide()
  end
  row:Show()
end

---------------------------------------------------------------------------
-- Configure a row as a data row
---------------------------------------------------------------------------
local function ConfigureAsData(row, labelText, index, yOffset, labelColor, labelWidth, labelTextWidth)
  labelWidth = labelWidth or LABEL_WIDTH
  row:SetHeight(ROW_HEIGHT)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", PANEL_MARGIN_X, yOffset)
  row:SetPoint("RIGHT", row:GetParent(), "RIGHT", -PANEL_MARGIN_X, 0)

  -- Alternating stripe
  local a = ((index % 2) == 0) and 0.18 or 0.0
  row.stripe:SetColorTexture(0.06, 0.06, 0.10, a)

  row.label:SetWidth(labelTextWidth or (labelWidth - 12))
  row.label:SetJustifyH("LEFT")
  row.label:SetText(labelText or "")
  if labelColor then
    row.label:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
  else
    row.label:SetTextColor(0.72, 0.72, 0.72, 1)
  end
  ApplyFont(row.label, 11)

  row.labelTip = nil
  row.labelTipSub = nil

  row:SetBackdrop(ROW_PANEL_BACKDROP)
  row:SetBackdropColor(0.05, 0.05, 0.10, 0.80)

  row:Show()
end

---------------------------------------------------------------------------
-- Position a cell in a data row
---------------------------------------------------------------------------
local function PlaceCell(row, colIdx, labelWidth)
  labelWidth = labelWidth or LABEL_WIDTH
  local cell = EnsureCell(row, colIdx)
  cell:ClearAllPoints()
  cell:SetPoint("LEFT", row, "LEFT", labelWidth + ((colIdx - 1) * CHAR_COL_WIDTH), 0)
  cell:SetWidth(CHAR_COL_WIDTH)
  cell:SetHeight(row:GetHeight())
  -- Reset text anchoring to default (may have been overridden)
  cell.text:ClearAllPoints()
  cell.text:SetPoint("LEFT", cell, "LEFT", 0, 0)
  cell.text:SetPoint("RIGHT", cell, "RIGHT", -7, 0)
  cell.text:SetJustifyH("RIGHT")
  cell.tipFunc = nil
  cell.clickFunc = nil
  HideSkullBar(cell)
  if cell.currIcon then cell.currIcon:Hide() end
  cell:Show()
  return cell
end

---------------------------------------------------------------------------
-- Close button
---------------------------------------------------------------------------
local function CreateCloseButton(parent)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(20, 20)
  btn:SetPoint("TOPRIGHT", -6, -6)
  btn:SetFrameLevel(parent:GetFrameLevel() + 10)
  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetAllPoints()
  btn.bg:SetColorTexture(0.09, 0.09, 0.11, 0.90)
  btn.x = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  btn.x:SetPoint("CENTER", 0, 0)
  btn.x:SetText("x")
  btn.x:SetTextColor(0.98, 0.64, 0.14, 1)
  ApplyFont(btn.x, 13)
  btn:SetScript("OnClick", function() parent:Hide() end)
  btn:SetScript("OnEnter", function(self) self.x:SetTextColor(1, 0.85, 0.5, 1) end)
  btn:SetScript("OnLeave", function(self) self.x:SetTextColor(0.98, 0.64, 0.14, 1) end)
  return btn
end

---------------------------------------------------------------------------
-- Build main window frame (once)
---------------------------------------------------------------------------
function Window:Create()
  local s = self._state
  if s.created and s.frame then return s.frame end

  local f = CreateFrame("Frame", "HaraUI_AltPanel", UIParent, "BackdropTemplate")
  f:SetSize(MIN_WINDOW_W, MIN_WINDOW_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  f:SetBackdropColor(0, 0, 0, 0)
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel(100)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:Hide()

  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
  f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)

  if f.SetToplevel then f:SetToplevel(true) end
  tinsert(UISpecialFrames, "HaraUI_AltPanel")

  -- Hide equipment popup when main window closes
  f:SetScript("OnHide", function()
    local Equipment = AP.Equipment
    if Equipment and Equipment.Hide then Equipment:Hide() end
  end)

  -- Gradient background
  f.bgGradient = f:CreateTexture(nil, "BACKGROUND")
  f.bgGradient:SetAllPoints()
  f.bgGradient:SetTexture("Interface/Buttons/WHITE8x8")
  SetVerticalGradient(f.bgGradient, 0, 0, 0, 0.93, 0.06, 0.02, 0.10, 0.93)

  -- Title
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.title:SetPoint("TOPLEFT", 12, -8)
  f.title:SetText("Alts")
  f.title:SetTextColor(0.98, 0.64, 0.14, 1)
  ApplyFont(f.title, 14)

  CreateCloseButton(f)

  -- Title separator
  f.titleSep = f:CreateTexture(nil, "ARTWORK")
  f.titleSep:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -TITLE_HEIGHT)
  f.titleSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -TITLE_HEIGHT)
  f.titleSep:SetHeight(1)
  f.titleSep:SetColorTexture(0, 0, 0, 0)

  -- Scroll frame (vertical)
  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -TITLE_HEIGHT - 2)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLLBAR_W, BOTTOM_PAD)

  local scrollBar = scroll.ScrollBar
  if scrollBar then
    scrollBar:Hide()
    scrollBar:SetScript("OnShow", function(self) self:Hide() end)
  end

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(MIN_WINDOW_W - SCROLLBAR_W, 1)
  scroll:SetScrollChild(child)

  s.frame = f
  s.scrollFrame = scroll
  s.scrollChild = child
  s.rows = {}
  s.numRows = 0
  s.created = true

  return f
end

---------------------------------------------------------------------------
-- Refresh — rebuild all rows from data
---------------------------------------------------------------------------
function Window:Refresh()
  local s = self._state
  if not s.created or not s.frame then return end

  local Data = AP.Data
  if not Data then return end

  local characters = Data:GetCharacters()
  local db = Data.GetDB()
  local showRealms = db and db.showRealms ~= false
  local numChars = #characters

  local dungeons = Data:GetSeasonDungeons()
  local vaultTypes = Data.VAULT_TYPES

  ---------------------------------------------------------------------------
  -- Calculate window width based on character count
  ---------------------------------------------------------------------------
  local contentW = LABEL_WIDTH + (numChars * CHAR_COL_WIDTH) + SCROLLBAR_W + 4 + 2 * PANEL_MARGIN_X
  local windowW = math.max(MIN_WINDOW_W, math.min(contentW, MAX_WINDOW_W))
  s.frame:SetWidth(windowW)
  s.scrollChild:SetWidth(windowW - SCROLLBAR_W)

  ---------------------------------------------------------------------------
  -- Build row list
  ---------------------------------------------------------------------------
  local rowIdx = 0
  local yOff = 0

  -- Helper: advance to next row
  local function NextRow()
    rowIdx = rowIdx + 1
    return GetRow(self, rowIdx)
  end

  -- Store character list for click handlers
  s.characterList = characters


  ---------------------------------------------------------------------------
  -- Character name header
  ---------------------------------------------------------------------------
  local row = NextRow()
  ConfigureAsData(row, "Character", rowIdx, yOff, { 0.98, 0.64, 0.14 }, LW_STATS)
  for ci = 1, numChars do
    local cell = PlaceCell(row, ci, LW_STATS)
    local info = characters[ci].data.info or {}
    local cr, cg, cb = ClassColor(info.classFile)
    cell:SetText(info.name or "???")
    cell:SetTextColor(cr, cg, cb)
    ApplyFont(cell.text, 12)
    local guid = characters[ci].guid
    cell.clickFunc = function(_, button)
      if button == "LeftButton" then
        local Equipment = AP.Equipment
        if Equipment then Equipment:Toggle(guid) end
      end
    end
    cell.tipFunc = function(c)
      ShowTip(c, function()
        GameTooltip:AddLine(info.name or "???", cr, cg, cb)
        if info.className and info.className ~= "" then
          local lvl = info.level or 0
          GameTooltip:AddLine((lvl > 0 and ("Level " .. lvl .. " ") or "") .. info.className, 0.70, 0.70, 0.70)
        end
        local eq = info.ilvlEquipped or info.ilvl or 0
        if eq > 0 then
          GameTooltip:AddDoubleLine("Item Level", tostring(eq), 0.70, 0.70, 0.70, 0.95, 0.95, 0.95)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to view equipment", 0.50, 0.50, 0.50)
      end)
    end
  end
  yOff = yOff - ROW_HEIGHT - ROW_GAP

  ---------------------------------------------------------------------------
  -- Realm
  ---------------------------------------------------------------------------
  if showRealms then
    row = NextRow()
    ConfigureAsData(row, "Realm", rowIdx, yOff, { 0.98, 0.64, 0.14 }, LW_STATS)
    for ci = 1, numChars do
      local cell = PlaceCell(row, ci, LW_STATS)
      local info = characters[ci].data.info or {}
      cell:SetText(info.realm or "")
      local faction = info.faction or ""
      if faction == "Horde" then
        cell:SetTextColor(0.87, 0.18, 0.18)
      elseif faction == "Alliance" then
        cell:SetTextColor(0.20, 0.52, 0.93)
      else
        cell:SetTextColor(0.55, 0.55, 0.55)
      end
    end
    yOff = yOff - ROW_HEIGHT - ROW_GAP
  end

  ---------------------------------------------------------------------------
  -- Item Level
  ---------------------------------------------------------------------------
  row = NextRow()
  ConfigureAsData(row, "Item Level", rowIdx, yOff, { 0.98, 0.64, 0.14 }, LW_STATS)
  for ci = 1, numChars do
    local cell = PlaceCell(row, ci, LW_STATS)
    local info = characters[ci].data.info or {}
    local ilvl = info.ilvlEquipped or info.ilvl or 0
    if ilvl > 0 then
      cell:SetText(tostring(ilvl))
      cell:SetTextColor(0.95, 0.95, 0.95)
    else
      cell:SetText("-")
      cell:SetTextColor(0.40, 0.40, 0.40)
    end
    local eqIlvl = info.ilvlEquipped or 0
    local ovIlvl = info.ilvl or 0
    if eqIlvl > 0 or ovIlvl > 0 then
      cell.tipFunc = function(c)
        ShowTip(c, function()
          local nr, ng, nb = ClassColor(info.classFile)
          GameTooltip:AddLine(info.name or "???", nr, ng, nb)
          if eqIlvl > 0 then
            GameTooltip:AddDoubleLine("Equipped", tostring(eqIlvl), 0.70, 0.70, 0.70, 0.95, 0.95, 0.95)
          end
          if ovIlvl > 0 and ovIlvl ~= eqIlvl then
            GameTooltip:AddDoubleLine("Overall", tostring(ovIlvl), 0.70, 0.70, 0.70, 0.80, 0.80, 0.80)
          end
        end)
      end
    end
  end
  yOff = yOff - ROW_HEIGHT - ROW_GAP

  ---------------------------------------------------------------------------
  -- Rating
  ---------------------------------------------------------------------------
  row = NextRow()
  ConfigureAsData(row, "Rating", rowIdx, yOff, { 0.98, 0.64, 0.14 }, LW_STATS)
  for ci = 1, numChars do
    local cell = PlaceCell(row, ci, LW_STATS)
    local rating = characters[ci].data.mythicplus and characters[ci].data.mythicplus.rating or 0
    if rating > 0 then
      local rr, rg, rb = RatingColor(rating)
      cell:SetText(tostring(rating))
      cell:SetTextColor(rr, rg, rb)
      cell.tipFunc = function(c)
        ShowTip(c, function()
          local info = characters[ci].data.info or {}
          local nr, ng, nb = ClassColor(info.classFile)
          GameTooltip:AddLine(info.name or "???", nr, ng, nb)
          GameTooltip:AddDoubleLine("M+ Rating", tostring(rating), 0.70, 0.70, 0.70, rr, rg, rb)
        end)
      end
    else
      cell:SetText("-")
      cell:SetTextColor(0.40, 0.40, 0.40)
    end
  end
  yOff = yOff - ROW_HEIGHT - ROW_GAP

  ---------------------------------------------------------------------------
  -- Current Keystone
  ---------------------------------------------------------------------------
  row = NextRow()
  ConfigureAsData(row, "Current Keystone", rowIdx, yOff, { 0.98, 0.64, 0.14 }, LW_STATS)
  for ci = 1, numChars do
    local cell = PlaceCell(row, ci, LW_STATS)
    local ks = characters[ci].data.mythicplus and characters[ci].data.mythicplus.keystone
    if ks and ks.level and ks.level > 0 then
      local ksName = ks.name or ""
      if ksName == "" then ksName = "?" end
      local kr, kg, kb = KeyLevelColor(ks.level)
      cell:SetText(ksName .. " +" .. ks.level)
      cell:SetTextColor(kr, kg, kb)
      cell.tipFunc = function(c)
        ShowTip(c, function()
          local info = characters[ci].data.info or {}
          local nr, ng, nb = ClassColor(info.classFile)
          GameTooltip:AddLine(info.name or "???", nr, ng, nb)
          GameTooltip:AddLine(ksName .. " +" .. ks.level, kr, kg, kb)
        end)
      end
    else
      cell:SetText("-")
      cell:SetTextColor(0.40, 0.40, 0.40)
    end
  end
  yOff = yOff - ROW_HEIGHT - ROW_GAP

  yOff = yOff - SECTION_GAP

  ---------------------------------------------------------------------------
  -- Great Vault section
  ---------------------------------------------------------------------------
  row = NextRow()
  ConfigureAsSection(row, "Great Vault", yOff)
  yOff = yOff - SECTION_HEIGHT - ROW_GAP

  for _, vt in ipairs(vaultTypes) do
    row = NextRow()
    ConfigureAsData(row, "  " .. vt.label, rowIdx, yOff, nil, LW_STATS)
    for ci = 1, numChars do
      local cell = PlaceCell(row, ci, LW_STATS)
      local charData = characters[ci].data
      local vaultSlots = Data:GetVaultByType(charData, vt.id)
      local parts = {}
      for idx = 1, 3 do
        local slot = vaultSlots[idx]
        if slot and slot.progress >= slot.threshold then
          local ilvl = slot.rewardIlvl or 0
          if ilvl > 0 then
            parts[#parts + 1] = "|cff00cc00" .. ilvl .. "|r"
          else
            local lvl = slot.level or 0
            parts[#parts + 1] = lvl > 0
              and ("|cff00cc00+" .. lvl .. "|r")
              or "|cff00cc00✓|r"
          end
        else
          parts[#parts + 1] = "|cff444444-|r"
        end
      end
      cell:SetText(table.concat(parts, " "))
      local vtLabel = vt.label
      cell.tipFunc = function(c)
        ShowTip(c, function()
          local info = characters[ci].data.info or {}
          local nr, ng, nb = ClassColor(info.classFile)
          GameTooltip:AddLine(info.name or "???", nr, ng, nb)
          GameTooltip:AddLine(vtLabel .. " Vault", 0.98, 0.64, 0.14)
          for idx = 1, 3 do
            local slot = vaultSlots[idx]
            if slot then
              if slot.progress >= slot.threshold then
                local ilvl = slot.rewardIlvl or 0
                local reward = ilvl > 0
                  and (tostring(ilvl) .. " ilvl")
                  or "Complete"
                GameTooltip:AddDoubleLine(
                  "Slot " .. idx, reward,
                  0.70, 0.70, 0.70, 0, 0.80, 0)
              else
                local status = slot.progress .. "/" .. slot.threshold
                GameTooltip:AddDoubleLine(
                  "Slot " .. idx, status,
                  0.70, 0.70, 0.70, 0.50, 0.50, 0.50)
              end
            end
          end
        end)
      end
    end
    yOff = yOff - ROW_HEIGHT - ROW_GAP
  end

  yOff = yOff - SECTION_GAP

  ---------------------------------------------------------------------------
  -- Dungeons section
  ---------------------------------------------------------------------------
  if #dungeons > 0 then
    row = NextRow()
    ConfigureAsSection(row, "Dungeons", yOff)
    yOff = yOff - SECTION_HEIGHT - ROW_GAP

    for _, dungeon in ipairs(dungeons) do
      row = NextRow()
      local dName = dungeon.name or ""
      ConfigureAsData(row, "  " .. dName, rowIdx, yOff, nil, LW_DUNGEONS)
      for ci = 1, numChars do
        local cell = PlaceCell(row, ci, LW_DUNGEONS)
        local score = Data:GetDungeonScore(characters[ci].data, dungeon.challengeModeID)
        if score and score.bestRunLevel and score.bestRunLevel > 0 then
          local kr, kg, kb = KeyLevelColor(score.bestRunLevel)
          local sr, sg, sb = RatingColor(score.mapScore)
          local timed = score.finishedSuccess and "+" or ""
          local parMS = (dungeon.timeLimit or 0) * 1000
          local stars = ComputeStars(score.bestRunDurationMS, parMS)
          local starStr = StarIcon(stars)
          local levelStr = string.format("|cff%02x%02x%02x%s%d|r",
            kr * 255, kg * 255, kb * 255, timed, score.bestRunLevel)
          local scoreStr = string.format("|cff%02x%02x%02x%d|r",
            sr * 255, sg * 255, sb * 255, score.mapScore)
          local text = starStr ~= "" and (starStr .. " " .. levelStr) or levelStr
          cell:SetText(text .. "  " .. scoreStr)
          cell.tipFunc = function(c)
            ShowTip(c, function()
              local info = characters[ci].data.info or {}
              local nr, ng, nb = ClassColor(info.classFile)
              GameTooltip:AddLine(info.name or "???", nr, ng, nb)
              GameTooltip:AddLine(dName, 0.98, 0.64, 0.14)
              local lvlText = timed .. tostring(score.bestRunLevel)
              GameTooltip:AddDoubleLine("Best Level", lvlText, 0.70, 0.70, 0.70, kr, kg, kb)
              GameTooltip:AddDoubleLine("Score", tostring(score.mapScore), 0.70, 0.70, 0.70, sr, sg, sb)
            end)
          end
        else
          cell:SetText("|cff444444-|r")
        end
      end
      yOff = yOff - ROW_HEIGHT - ROW_GAP
    end
    yOff = yOff - SECTION_GAP
  end

  ---------------------------------------------------------------------------
  -- Raid lockout section
  ---------------------------------------------------------------------------
  local trackedRaids = Data:GetTrackedRaids()
  local raidDiffs = Data.RAID_DIFFICULTIES

  for _, raid in ipairs(trackedRaids) do
    row = NextRow()
    ConfigureAsSection(row, raid.name, yOff)
    yOff = yOff - SECTION_HEIGHT - ROW_GAP

    for _, diff in ipairs(raidDiffs) do
      row = NextRow()
      local dc = DIFF_COLORS[diff.id] or { 0.60, 0.60, 0.60 }
      ConfigureAsData(row, "  " .. diff.label, rowIdx, yOff, dc, LW_RAID)

      for ci = 1, numChars do
        local cell = PlaceCell(row, ci, LW_RAID)
        local lockout = Data:GetRaidLockout(characters[ci].data, raid.instanceID, diff.id)
        cell:SetText("")
        SetupSkullBar(cell, raid.numEncounters, lockout)
        local raidName = raid.name
        local diffLabel = diff.label
        local numEnc = raid.numEncounters
        cell.tipFunc = function(c)
          ShowTip(c, function()
            local info = characters[ci].data.info or {}
            local nr, ng, nb = ClassColor(info.classFile)
            GameTooltip:AddLine(info.name or "???", nr, ng, nb)
            GameTooltip:AddLine(raidName .. " - " .. diffLabel, 0.98, 0.64, 0.14)
            if lockout and lockout.encounters then
              for ei = 1, numEnc do
                local enc = lockout.encounters[ei]
                if enc then
                  if enc.killed then
                    GameTooltip:AddDoubleLine(enc.name, "Defeated", 0.70, 0.70, 0.70, dc[1], dc[2], dc[3])
                  else
                    GameTooltip:AddDoubleLine(enc.name, "Alive", 0.70, 0.70, 0.70, 0.35, 0.35, 0.35)
                  end
                end
              end
            else
              GameTooltip:AddLine("No lockout", 0.50, 0.50, 0.50)
            end
          end)
        end
      end
      yOff = yOff - ROW_HEIGHT - ROW_GAP
    end
    yOff = yOff - SECTION_GAP
  end

  ---------------------------------------------------------------------------
  -- Currency section
  ---------------------------------------------------------------------------
  local trackedCurrencies = Data:GetTrackedCurrencies()

  if #trackedCurrencies > 0 then
    row = NextRow()
    ConfigureAsSection(row, "Currency", yOff)
    yOff = yOff - SECTION_HEIGHT - ROW_GAP

    for _, curr in ipairs(trackedCurrencies) do
      row = NextRow()
      local icon = (curr.icon and curr.icon > 0)
        and ("|T" .. curr.icon .. ":14:14:0:0|t ") or "  "
      local cName = curr.name or ""
      local q = curr.quality or 1
      local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
      local labelColor = qc and { qc.r, qc.g, qc.b } or nil
      ConfigureAsData(row, icon .. cName, rowIdx, yOff, labelColor, LW_CURRENCY, 220)

      for ci = 1, numChars do
        local cell = PlaceCell(row, ci, LW_CURRENCY)
        local ca = Data:GetCurrencyAmount(characters[ci].data, curr.id)
        if ca then
          local qty = ca.quantity or 0
          local maxQ = ca.maxQuantity or 0
          if qty <= 0 then
            cell:SetText("|cff4444440|r")
          elseif maxQ > 0 and qty >= maxQ then
            cell:SetText("|cff00cc00" .. qty .. "|r")
          else
            cell:SetText(tostring(qty))
            cell:SetTextColor(0.95, 0.95, 0.95)
          end
        else
          cell:SetText("|cff444444-|r")
        end
        -- Fixed-position currency icon
        if curr.icon and curr.icon > 0 then
          if not cell.currIcon then
            cell.currIcon = cell:CreateTexture(nil, "ARTWORK")
            cell.currIcon:SetSize(14, 14)
          end
          cell.currIcon:ClearAllPoints()
          cell.currIcon:SetPoint("RIGHT", cell, "RIGHT", -50, 0)
          cell.currIcon:SetTexture(curr.icon)
          cell.currIcon:Show()
        end
        local currName = cName
        local currIcon = curr.icon
        cell.tipFunc = function(c)
          ShowTip(c, function()
            local info = characters[ci].data.info or {}
            local nr, ng, nb = ClassColor(info.classFile)
            GameTooltip:AddLine(info.name or "???", nr, ng, nb)
            if currIcon and currIcon > 0 then
              GameTooltip:AddLine("|T" .. currIcon .. ":16:16:0:0|t " .. currName, 0.98, 0.64, 0.14)
            else
              GameTooltip:AddLine(currName, 0.98, 0.64, 0.14)
            end
            if ca then
              local qty = ca.quantity or 0
              local maxQ = ca.maxQuantity or 0
              if maxQ > 0 then
                GameTooltip:AddDoubleLine("Amount", qty .. " / " .. maxQ, 0.70, 0.70, 0.70, 0.95, 0.95, 0.95)
              else
                GameTooltip:AddDoubleLine("Amount", tostring(qty), 0.70, 0.70, 0.70, 0.95, 0.95, 0.95)
              end
            else
              GameTooltip:AddLine("Not discovered", 0.50, 0.50, 0.50)
            end
          end)
        end
      end
      yOff = yOff - ROW_HEIGHT - ROW_GAP
    end
  end

  -- Hide any old section panels left over from previous implementation
  for _, p in ipairs(s.sectionPanels or {}) do p:Hide() end

  ---------------------------------------------------------------------------
  -- Hide unused rows
  ---------------------------------------------------------------------------
  s.numRows = rowIdx
  for i = rowIdx + 1, #s.rows do
    s.rows[i]:Hide()
  end

  -- Also hide unused cells in active rows
  for i = 1, rowIdx do
    local r = s.rows[i]
    for ci = numChars + 1, #r.cells do
      if r.cells[ci] then
        r.cells[ci]:SetText("")
        r.cells[ci]:Hide()
      end
    end
  end

  ---------------------------------------------------------------------------
  -- Size the scroll child and window height
  ---------------------------------------------------------------------------
  local totalContentH = math.abs(yOff)
  s.scrollChild:SetHeight(math.max(totalContentH, 1))

  local windowH = TITLE_HEIGHT + totalContentH + BOTTOM_PAD + 4
  windowH = math.max(MIN_WINDOW_H, math.min(windowH, MAX_WINDOW_H))
  s.frame:SetHeight(windowH)
end

---------------------------------------------------------------------------
-- Show / Hide / Toggle
---------------------------------------------------------------------------
function Window:ApplyScale()
  local s = self._state
  if not s.frame then return end
  local db = NS:GetDB()
  local scale = (db and db.altpanel and db.altpanel.scale) or 1.0
  s.frame:SetScale(scale)
end

function Window:Show()
  local f = self:Create()
  self:Refresh()
  self:ApplyScale()
  f:Show()
  f:Raise()
end

function Window:Hide()
  local s = self._state
  if s.frame then s.frame:Hide() end
  local Equipment = AP.Equipment
  if Equipment and Equipment.Hide then Equipment:Hide() end
end

function Window:Toggle()
  local s = self._state
  if s.frame and s.frame:IsShown() then
    self:Hide()
  else
    self:Show()
  end
end

function Window:IsShown()
  local s = self._state
  return s.frame and s.frame:IsShown() or false
end
