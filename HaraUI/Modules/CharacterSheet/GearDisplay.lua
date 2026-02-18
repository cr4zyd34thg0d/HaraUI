local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.GearDisplay = CS.GearDisplay or {}
local GearDisplay = CS.GearDisplay

local Skin -- resolved lazily after Skin.lua loads
local CFG  -- alias for Skin.CFG

local UPDATE_THROTTLE_INTERVAL = 0.08
local RESYNC_SETTLE_DELAY = 0.15

GearDisplay._state = GearDisplay._state or {
  parent = nil,
  root = nil,
  created = false,
  leftRows = nil,
  rightRows = nil,
  eventFrame = nil,
  hooksInstalled = false,
  characterHookInstalled = false,
  specResyncToken = 0,
  lootResyncToken = 0,
  counters = {
    creates = 0,
    updateRequests = 0,
    updatesApplied = 0,
  },
}

local function EnsureSkin()
  if not Skin then
    Skin = CS and CS.Skin or nil
    CFG = Skin and Skin.CFG or nil
  end
  return Skin ~= nil
end

local function IsRefactorEnabled()
  return CS and CS.IsRefactorEnabled and CS:IsRefactorEnabled()
end

local function IsAccountTransferBuild()
  return C_CurrencyInfo and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function"
end

local function IsNativeCurrencyMode()
  local layoutState = CS and CS.Layout and CS.Layout._state or nil
  if not layoutState then
    return false
  end
  return layoutState.nativeCurrencyMode == true and layoutState.activePane == "currency"
end

local function EnsureState(self)
  local s = self._state
  s.leftRows = s.leftRows or {}
  s.rightRows = s.rightRows or {}
  s.specResyncToken = tonumber(s.specResyncToken) or 0
  s.lootResyncToken = tonumber(s.lootResyncToken) or 0
  s.counters = s.counters or { creates = 0, updateRequests = 0, updatesApplied = 0 }
  return s
end

local function ResolveSpecializationContext()
  local count = GetNumSpecializations and GetNumSpecializations(false, false) or 0
  if not count or count < 1 then
    count = GetNumSpecializations and GetNumSpecializations() or 0
  end
  if count < 1 then count = 1 end
  local currentIndex = GetSpecialization and GetSpecialization() or nil
  local currentSpecID = nil
  if type(currentIndex) == "number" and GetSpecializationInfo then
    currentSpecID = select(1, GetSpecializationInfo(currentIndex))
  end
  local lootSpecID = GetLootSpecialization and GetLootSpecialization() or 0
  return count, currentIndex, currentSpecID, lootSpecID
end

local function ApplyButtonActiveStyle(btn, active)
  if not btn then return end
  if active then
    btn:SetBackdropBorderColor(1.00, 0.70, 0.12, 1.00)
    if btn.glow then btn.glow:Show() end
  else
    btn:SetBackdropBorderColor(0.14, 0.14, 0.14, 0.95)
    if btn.glow then btn.glow:Hide() end
  end
end

local function ApplyPendingClickStyle(btn)
  if not btn then return end
  btn:SetBackdropBorderColor(0.95, 0.85, 0.22, 0.95)
  if btn.glow then btn.glow:Show() end
end

local function ResolveParent()
  local layoutState = CS and CS.Layout and CS.Layout._state or nil
  local panels = layoutState and layoutState.panels or nil
  if panels and panels.left then return panels.left end
  return CharacterFrame
end

local function ResolveClusterRowTuning(rightAlign)
  local cluster = rightAlign and (CFG and CFG.RightGearCluster) or (CFG and CFG.LeftGearCluster)
  if type(cluster) ~= "table" then
    cluster = {}
  end
  local textGap = tonumber(cluster.TextGap) or tonumber(CFG and CFG.GEAR_TEXT_GAP) or 10
  local textInset = tonumber(cluster.TextInset)
  if textInset == nil then
    textInset = rightAlign and -8 or 8
  end
  return textGap, textInset
end

---------------------------------------------------------------------------
-- Gem socket icon constants
---------------------------------------------------------------------------
local GEM_ICON_SIZE = 14
local GEM_ICON_GAP = 1
local GEM_PAD = 1.5                -- padding on each side of the gem icon
local MAX_GEM_SLOTS = 3

---------------------------------------------------------------------------
-- Row creation: 3-line rows (name, track/ilvl, enchant) with bg gradient
---------------------------------------------------------------------------
local function CreateGearRow(parent, rightAlign)
  if not CFG then return nil end

  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(CFG.GEAR_ROW_WIDTH, CFG.GEAR_ROW_HEIGHT)
  row:SetClipsChildren(false)

  -- Background texture for quality gradient
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetTexture("Interface/Buttons/WHITE8x8")
  row.bg:SetDrawLayer("ARTWORK", 0)
  row.bg:SetAllPoints(true)
  row.bg:SetColorTexture(0.14, 0.02, 0.20, 0.32)

  local justify = rightAlign and "RIGHT" or "LEFT"
  local _, textInset = ResolveClusterRowTuning(rightAlign)
  local xOff = textInset
  local nameAnchor = rightAlign and "TOPRIGHT" or "TOPLEFT"

  -- Line 1: item name
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint(nameAnchor, row, nameAnchor, xOff, -4)
  row.name:SetJustifyH(justify)
  row.name:SetWidth(CFG.GEAR_ROW_WIDTH - 16)
  row.name:SetMaxLines(1)
  if row.name.SetWordWrap then row.name:SetWordWrap(false) end
  row.name:SetTextColor(0.92, 0.46, 1.0, 1)

  -- Line 2: ilvl + upgrade track
  local trackAnchor = rightAlign and "BOTTOMRIGHT" or "BOTTOMLEFT"
  row.track = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.track:SetPoint(nameAnchor == "TOPRIGHT" and "TOPRIGHT" or "TOPLEFT", row.name, trackAnchor, 0, -4)
  row.track:SetJustifyH(justify)
  row.track:SetWidth(CFG.GEAR_ROW_WIDTH - 16)
  row.track:SetMaxLines(1)
  if row.track.SetWordWrap then row.track:SetWordWrap(false) end
  row.track:SetTextColor(0.98, 0.90, 0.35, 1)

  -- Line 3: enchant
  row.enchant = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.enchant:SetPoint(nameAnchor == "TOPRIGHT" and "TOPRIGHT" or "TOPLEFT", row.track, trackAnchor, 0, -4)
  row.enchant:SetJustifyH(justify)
  row.enchant:SetWidth(CFG.GEAR_ROW_WIDTH - 30)
  row.enchant:SetMaxLines(1)
  if row.enchant.SetWordWrap then row.enchant:SetWordWrap(false) end
  row.enchant:SetTextColor(0.1, 1, 0.75, 1)

  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(row.name, 11)
    NS:ApplyDefaultFont(row.track, 10)
    NS:ApplyDefaultFont(row.enchant, 10)
  end

  -- Gem socket icons (up to 3, positioned between slot icon and text)
  row.gems = {}
  for i = 1, MAX_GEM_SLOTS do
    local gem = CreateFrame("Button", nil, row)
    gem:SetSize(GEM_ICON_SIZE, GEM_ICON_SIZE)
    gem:Hide()
    gem.icon = gem:CreateTexture(nil, "ARTWORK")
    gem.icon:SetAllPoints()
    gem.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    gem:EnableMouse(true)
    gem:SetScript("OnEnter", function(self)
      if self.gemLink and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.gemLink)
        GameTooltip:Show()
      elseif self.isEmpty and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Empty Socket", 0.5, 0.5, 0.5)
        GameTooltip:Show()
      elseif self.missingSocket and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("No gem socket", 1, 0.3, 0.3)
        if self.socketHint then
          GameTooltip:AddLine("Use: " .. self.socketHint, 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
      end
    end)
    gem:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
    row.gems[i] = gem
  end

  row.rightAlign = rightAlign
  return row
end

---------------------------------------------------------------------------
-- Row update: populate a single gear row with item data
---------------------------------------------------------------------------
local function UpdateRow(row, slotName, rightAlign, classR, classG, classB)
  if not (row and slotName and Skin) then return end

  local btn = _G["Character" .. slotName]
  if not btn then
    row:Hide()
    return
  end

  -- Anchor row to Blizzard slot button
  row:ClearAllPoints()
  row:SetWidth(CFG.GEAR_ROW_WIDTH)
  local textGap = ResolveClusterRowTuning(rightAlign)
  if rightAlign then
    row:SetPoint("RIGHT", btn, "LEFT", -textGap, 0)
  else
    row:SetPoint("LEFT", btn, "RIGHT", textGap, 0)
  end

  local invID = GetInventorySlotInfo and GetInventorySlotInfo(slotName) or nil
  local link = invID and GetInventoryItemLink and GetInventoryItemLink("player", invID) or nil

  if not link then
    row.name:SetText("")
    row.track:SetText("")
    row.enchant:SetText("")
    for _, g in ipairs(row.gems) do g:Hide() end
    row:Hide()
    return
  end

  local name, _, quality = GetItemInfo(link)
  local ilvl = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link) or nil

  -- Enchant: try link parse first, fall back to tooltip scan
  local enchant = Skin.ParseEnchantName(link)
  if enchant == "" then
    enchant = Skin.GetEnchantFromTooltip(invID)
  end

  local upgradeTrack = Skin.GetUpgradeTrack(invID)

  -- Name color: quality or class color for tier
  local r, g, b = 0.92, 0.46, 1.0
  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    r = ITEM_QUALITY_COLORS[quality].r
    g = ITEM_QUALITY_COLORS[quality].g
    b = ITEM_QUALITY_COLORS[quality].b
  end
  local isTier = Skin.IsTierSetItem(link, invID)
  if isTier then
    r, g, b = classR, classG, classB
  end

  row.name:SetText(name or slotName)
  row.name:SetTextColor(r, g, b, 1)

  -- Update slot button border
  Skin.UpdateSlotBorder(btn, quality, isTier, classR, classG, classB)

  -- Hide blizzard icon border
  local iconBorder = btn.IconBorder or _G[btn:GetName() .. "IconBorder"]
  if iconBorder then
    if iconBorder.SetAlpha then iconBorder:SetAlpha(0) end
    if iconBorder.Hide then iconBorder:Hide() end
  end

  -- Track line: ilvl + upgrade track
  local ilvlText = ilvl and tostring(math.floor(ilvl + 0.5)) or ""
  local trackText = upgradeTrack ~= "" and ("(%s)"):format(upgradeTrack) or ""
  local tr, tg, tb = Skin.GetUpgradeTrackColor(upgradeTrack)
  local ilvlPart = ilvlText ~= "" and ("|cffffffff%s|r"):format(ilvlText) or ""
  local trackPart = trackText ~= "" and ("|cff%s%s|r"):format(Skin.RGBToHex(tr, tg, tb), trackText) or ""

  local meta = ""
  if rightAlign then
    if trackPart ~= "" then meta = trackPart end
    if ilvlPart ~= "" then
      meta = meta ~= "" and (meta .. " " .. ilvlPart) or ilvlPart
    end
  else
    if ilvlPart ~= "" then meta = ilvlPart end
    if trackPart ~= "" then
      meta = meta ~= "" and (meta .. " " .. trackPart) or trackPart
    end
  end
  row.track:SetText(meta)
  row.track:SetTextColor(1, 1, 1, 1)

  -- Enchant line
  local hasEnchant = enchant ~= nil and enchant ~= ""
  local canHaveEnchant = Skin.CanSlotHaveEnchant(slotName, link)
  if hasEnchant then
    local markup = Skin.GetEnchantQualityMarkup(invID, enchant)
    row.enchant:SetText(enchant .. markup)
  elseif canHaveEnchant then
    row.enchant:SetText("|cffff3a3a<enchant missing>|r")
  else
    row.enchant:SetText("")
  end

  -- Background gradient based on quality
  if row.bg then
    local grad = CFG.RARITY_GRADIENT[quality or 1]
    local c1r, c1g, c1b
    if isTier then
      c1r, c1g, c1b = classR, classG, classB
    else
      c1r, c1g, c1b = grad[5], grad[6], grad[7]
    end
    local rowW = row:GetWidth() > 0 and row:GetWidth() or CFG.GEAR_ROW_WIDTH
    local split = math.floor(rowW * 0.96)
    local iconSpan = CFG.SLOT_ICON_SIZE + textGap + 2
    local iconPad = math.max(2, math.floor((row:GetHeight() - CFG.SLOT_ICON_SIZE) * 0.35))
    row.bg:ClearAllPoints()
    row.bg:SetColorTexture(c1r, c1g, c1b, 0.30)
    if rightAlign then
      row.bg:SetPoint("TOPLEFT", row, "TOPRIGHT", -split, iconPad)
      row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", iconSpan, -iconPad)
      Skin.SetHorizontalGradient(row.bg, c1r, c1g, c1b, 0.00, c1r, c1g, c1b, 0.92)
    else
      row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", -(iconSpan + 2), iconPad)
      row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", split, -iconPad)
      Skin.SetHorizontalGradient(row.bg, c1r, c1g, c1b, 0.92, c1r, c1g, c1b, 0.00)
    end
    if row.bg.SetBlendMode then row.bg:SetBlendMode("BLEND") end
    if row.bg.SetAlpha then row.bg:SetAlpha(1) end
    row.bg:Show()
  end

  -- Gem socket icons
  local gemInfo = Skin.GetGemInfo and Skin.GetGemInfo(invID, link) or nil
  local gemCount = gemInfo and #gemInfo or 0
  local socketHint = Skin.CanSlotHaveGem and Skin.CanSlotHaveGem(slotName, invID, link)
  local showMissing = gemCount == 0 and socketHint

  -- Always reserve gem column space so all text rows align uniformly
  -- Layout: [GearIcon] -1.5px- [GemIcon] -1.5px- [Text...]
  -- Gems and text eat into the textGap so spacing is tight to the gear icon
  local textGapUsed = textGap
  local gemX = rightAlign and (textGapUsed - GEM_PAD) or -(textGapUsed - GEM_PAD)
  local textX = rightAlign
    and (textGapUsed - GEM_PAD - GEM_ICON_SIZE - GEM_PAD)
    or -(textGapUsed - GEM_PAD - GEM_ICON_SIZE - GEM_PAD)
  local nameAnchor = rightAlign and "TOPRIGHT" or "TOPLEFT"
  row.name:ClearAllPoints()
  row.name:SetPoint(nameAnchor, row, nameAnchor, textX, -4)
  local trackAnchor = rightAlign and "BOTTOMRIGHT" or "BOTTOMLEFT"
  row.track:ClearAllPoints()
  row.track:SetPoint(nameAnchor, row.name, trackAnchor, 0, -4)
  row.enchant:ClearAllPoints()
  row.enchant:SetPoint(nameAnchor, row.track, trackAnchor, 0, -4)

  for i = 1, MAX_GEM_SLOTS do
    local gem = row.gems[i]
    if i <= gemCount and gemInfo then
      local info = gemInfo[i]
      if info.empty then
        gem.icon:SetTexture(info.icon)
        gem.icon:SetDesaturated(false)
        gem.icon:SetVertexColor(1, 0.3, 0.3, 0.85)
        gem.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      else
        gem.icon:SetTexture(info.icon)
        gem.icon:SetDesaturated(false)
        gem.icon:SetVertexColor(1, 1, 1, 1)
        gem.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      end
      gem.gemLink = info.link
      gem.isEmpty = info.empty
      gem.missingSocket = false

      gem:ClearAllPoints()
      local totalH = gemCount * GEM_ICON_SIZE + (gemCount - 1) * GEM_ICON_GAP
      local topOffset = (row:GetHeight() - totalH) / 2
      local yOff = -(topOffset + (i - 1) * (GEM_ICON_SIZE + GEM_ICON_GAP))
      if rightAlign then
        gem:SetPoint("TOPRIGHT", row, "TOPRIGHT", gemX, yOff)
      else
        gem:SetPoint("TOPLEFT", row, "TOPLEFT", gemX, yOff)
      end
      gem:Show()
    else
      gem:Hide()
    end
  end

  -- Missing socket indicator: item can be gemmed but has no sockets
  if showMissing then
    local gem = row.gems[1]
    gem.icon:SetTexture("Interface/RAIDFRAME/ReadyCheck-NotReady")
    gem.icon:SetDesaturated(false)
    gem.icon:SetVertexColor(1, 1, 1, 0.85)
    gem.icon:SetTexCoord(0, 1, 0, 1)
    gem.gemLink = nil
    gem.isEmpty = false
    gem.missingSocket = true
    gem.socketHint = type(socketHint) == "string" and socketHint or nil
    gem:ClearAllPoints()
    local yOff = -(row:GetHeight() - GEM_ICON_SIZE) / 2
    if rightAlign then
      gem:SetPoint("TOPRIGHT", row, "TOPRIGHT", gemX, yOff)
    else
      gem:SetPoint("TOPLEFT", row, "TOPLEFT", gemX, yOff)
    end
    gem:Show()
  end

  row:Show()
end

---------------------------------------------------------------------------
-- Create / Layout
---------------------------------------------------------------------------
function GearDisplay:Create(parent)
  if not IsRefactorEnabled() then return nil end
  if not EnsureSkin() then return nil end

  local state = EnsureState(self)
  parent = parent or ResolveParent()
  if not parent then return nil end

  if state.created and state.root then
    if state.parent ~= parent then
      state.parent = parent
      if state.root:GetParent() ~= parent then
        state.root:SetParent(parent)
        state.root:ClearAllPoints()
        state.root:SetAllPoints(parent)
      end
    end
    return state.root
  end

  state.parent = parent
  state.root = CreateFrame("Frame", nil, parent)
  state.root:SetAllPoints(parent)
  state.root:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  state.root:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
  state.root:Hide()

  -- Create left rows (text to the RIGHT of slot button)
  for i = 1, #CFG.LEFT_GEAR_SLOTS do
    state.leftRows[i] = CreateGearRow(state.root, false)
  end

  -- Create right rows (text to the LEFT of slot button)
  for i = 1, #CFG.RIGHT_GEAR_SLOTS do
    state.rightRows[i] = CreateGearRow(state.root, true)
  end

  -- Specialization + Loot Specialization panel (bottom of CharacterFrame, above tab bar)
  local charFrame = CharacterFrame
  if charFrame then
    state.specPanel = CreateFrame("Frame", nil, charFrame)
    state.specPanel:SetPoint("BOTTOMLEFT", charFrame, "BOTTOMLEFT", 36, 8)
    state.specPanel:SetSize(376, 46)
    state.specPanel:EnableMouse(true)
    state.specPanel:SetFrameStrata("HIGH")
    state.specPanel:SetFrameLevel((charFrame:GetFrameLevel() or 1) + 42)

    -- Spec title
    state.specPanel.title = state.specPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    state.specPanel.title:SetJustifyH("CENTER")
    state.specPanel.title:SetText("Specialization")
    if NS and NS.ApplyDefaultFont then NS:ApplyDefaultFont(state.specPanel.title, 10) end

    -- Spec button row
    state.specButtonRow = CreateFrame("Frame", nil, state.specPanel)
    state.specButtonRow:SetPoint("BOTTOMLEFT", state.specPanel, "BOTTOMLEFT", 0, 9)
    state.specButtonRow:SetSize(156, 28)
    state.specPanel.title:ClearAllPoints()
    state.specPanel.title:SetPoint("BOTTOM", state.specButtonRow, "TOP", 0, 4)

    state.specButtons = {}
    for i = 1, 4 do
      local btn = CreateFrame("Button", nil, state.specButtonRow, "BackdropTemplate")
      btn:SetSize(28, 28)
      btn:SetPoint("LEFT", state.specButtonRow, "LEFT", (i - 1) * 34, 0)
      btn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
      })
      btn:SetBackdropColor(0.02, 0.02, 0.03, 0.95)
      btn:SetBackdropBorderColor(0.14, 0.14, 0.14, 0.95)
      btn.specIndex = i

      btn.icon = btn:CreateTexture(nil, "ARTWORK")
      btn.icon:SetPoint("TOPLEFT", 2, -2)
      btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
      btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      btn.icon:SetTexture(134400)

      btn.glow = btn:CreateTexture(nil, "OVERLAY")
      btn.glow:SetPoint("TOPLEFT", -2, 2)
      btn.glow:SetPoint("BOTTOMRIGHT", 2, -2)
      btn.glow:SetTexture("Interface/Buttons/WHITE8x8")
      btn.glow:SetBlendMode("ADD")
      btn.glow:SetVertexColor(1.0, 0.70, 0.12, 0.30)
      btn.glow:Hide()

      btn:SetScript("OnClick", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        local idx = self.specIndex
        if not idx then return end
        ApplyPendingClickStyle(self)
        if SetSpecialization then
          pcall(SetSpecialization, idx)
        elseif C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
          pcall(C_SpecializationInfo.SetSpecialization, idx)
        end
        GearDisplay:RequestSpecResync("spec_click")
      end)
      state.specButtons[i] = btn
    end

    -- Loot Specialization title
    state.lootTitle = state.specPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    state.lootTitle:SetJustifyH("CENTER")
    state.lootTitle:SetText("Loot Specialization")
    if NS and NS.ApplyDefaultFont then NS:ApplyDefaultFont(state.lootTitle, 10) end

    -- Loot spec button row
    state.lootSpecButtonRow = CreateFrame("Frame", nil, state.specPanel)
    state.lootSpecButtonRow:SetPoint("BOTTOMLEFT", state.specPanel, "BOTTOMLEFT", 210, 9)
    state.lootSpecButtonRow:SetSize(170, 28)
    state.lootTitle:ClearAllPoints()
    state.lootTitle:SetPoint("BOTTOM", state.lootSpecButtonRow, "TOP", -1, 4)

    state.lootSpecButtons = {}
    for i = 1, 5 do
      local btn = CreateFrame("Button", nil, state.lootSpecButtonRow, "BackdropTemplate")
      btn:SetSize(28, 28)
      btn:SetPoint("LEFT", state.lootSpecButtonRow, "LEFT", (i - 1) * 34, 0)
      btn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
      })
      btn:SetBackdropColor(0.02, 0.02, 0.03, 0.95)
      btn:SetBackdropBorderColor(0.14, 0.14, 0.14, 0.95)
      btn.lootIndex = i

      btn.icon = btn:CreateTexture(nil, "ARTWORK")
      btn.icon:SetPoint("TOPLEFT", 2, -2)
      btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
      btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      btn.icon:SetTexture(134400)

      btn.glow = btn:CreateTexture(nil, "OVERLAY")
      btn.glow:SetPoint("TOPLEFT", -2, 2)
      btn.glow:SetPoint("BOTTOMRIGHT", 2, -2)
      btn.glow:SetTexture("Interface/Buttons/WHITE8x8")
      btn.glow:SetBlendMode("ADD")
      btn.glow:SetVertexColor(1.0, 0.70, 0.12, 0.30)
      btn.glow:Hide()

      btn:SetScript("OnClick", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        if not SetLootSpecialization then return end
        local index = self.lootIndex or 1
        local targetLootSpecID
        if index == 1 then
          targetLootSpecID = 0
        else
          local specID = self.specID
          if type(specID) ~= "number" then return end
          targetLootSpecID = specID
        end
        ApplyPendingClickStyle(self)
        pcall(SetLootSpecialization, targetLootSpecID)
        GearDisplay:RequestLootSpecResync("loot_spec_click")
      end)
      state.lootSpecButtons[i] = btn
    end
  end

  state.created = true
  state.counters.creates = (state.counters.creates or 0) + 1
  return state.root
end

---------------------------------------------------------------------------
-- Update all gear rows
---------------------------------------------------------------------------
function GearDisplay:UpdateGear()
  if not IsRefactorEnabled() then return false end
  if not EnsureSkin() then return false end

  local state = EnsureState(self)
  local root = self:Create(ResolveParent() or state.parent)
  if not root then return false end

  -- Invalidate tooltip cache so we get fresh data
  Skin.InvalidateTooltipCache()

  local classR, classG, classB = Skin.GetPlayerClassColor()

  -- Update left rows
  for i, slotName in ipairs(CFG.LEFT_GEAR_SLOTS) do
    local row = state.leftRows[i]
    if row then
      UpdateRow(row, slotName, false, classR, classG, classB)
    end
  end

  -- Update right rows
  for i, slotName in ipairs(CFG.RIGHT_GEAR_SLOTS) do
    local row = state.rightRows[i]
    if row then
      UpdateRow(row, slotName, true, classR, classG, classB)
    end
  end

  -- Only show gear display on the character (paperdoll) pane
  local layoutState = CS and CS.Layout and CS.Layout._state or nil
  local activePane = layoutState and layoutState.activePane or "character"
  if activePane == "character" and CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown() then
    root:Show()
  else
    root:Hide()
  end

  -- Update specialization + loot spec buttons
  self:_UpdateSpecButtons(state)

  state.counters.updatesApplied = (state.counters.updatesApplied or 0) + 1
  return true
end

function GearDisplay:_ApplySpecFromState(state)
  if not state or not state.specPanel or not state.specButtons or not state.specButtonRow then return end
  local panel = state.specPanel
  local row = state.specButtonRow
  local buttons = state.specButtons
  if panel.Show then panel:Show() end
  if row.Show then row:Show() end

  local count, currentIndex = ResolveSpecializationContext()
  if count > #buttons then count = #buttons end

  local usedWidth = (count * 28) + ((count - 1) * 6)
  row:SetWidth(usedWidth)
  row:ClearAllPoints()
  row:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 9)

  for i, btn in ipairs(buttons) do
    if i <= count and GetSpecializationInfo then
      local specID, _, _, icon = GetSpecializationInfo(i)
      btn.specID = specID
      if btn.icon then btn.icon:SetTexture(icon or 134400) end
      btn:ClearAllPoints()
      btn:SetPoint("LEFT", row, "LEFT", (i - 1) * 34, 0)
      btn:Show()
      ApplyButtonActiveStyle(btn, currentIndex == i)
    else
      btn:Hide()
    end
  end
end

function GearDisplay:_ApplyLootSpecFromState(state)
  if not state or not state.specPanel or not state.lootSpecButtonRow or not state.lootSpecButtons then return end
  local panel = state.specPanel
  local row = state.lootSpecButtonRow
  local buttons = state.lootSpecButtons
  if row.Show then row:Show() end

  local count, currentIndex, _, lootSpecID = ResolveSpecializationContext()
  local maxSpecButtons = #buttons - 1
  if count > maxSpecButtons then count = maxSpecButtons end
  if count < 1 then count = 1 end

  local usedWidth = ((count + 1) * 28) + (count * 6)
  row:SetWidth(usedWidth)
  row:ClearAllPoints()
  row:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 210, 9)

  for i, btn in ipairs(buttons) do
    if i <= (count + 1) and GetSpecializationInfo then
      local specIndex = i - 1
      local specID, icon
      if specIndex == 0 then
        specID = 0
        if currentIndex then
          icon = select(4, GetSpecializationInfo(currentIndex))
        end
        btn.specID = 0
      else
        local sid, _, _, ic = GetSpecializationInfo(specIndex)
        specID = sid
        icon = ic
        btn.specID = specID
      end
      if btn.icon then btn.icon:SetTexture(icon or 134400) end
      btn:ClearAllPoints()
      btn:SetPoint("LEFT", row, "LEFT", (i - 1) * 34, 0)
      btn:Show()

      local isActive = (specIndex == 0 and lootSpecID == 0) or (specIndex > 0 and lootSpecID == specID)
      ApplyButtonActiveStyle(btn, isActive)
    else
      btn:Hide()
    end
  end
end

local function RequestGroupResync(self, tokenKey, applyFn)
  if not self or type(applyFn) ~= "function" then return end
  local state = EnsureState(self)
  state[tokenKey] = (tonumber(state[tokenKey]) or 0) + 1
  local token = state[tokenKey]

  applyFn()
  if not (C_Timer and C_Timer.After) then return end

  C_Timer.After(0, function()
    if not self or not self._state then return end
    if self._state[tokenKey] ~= token then return end
    applyFn()
  end)
  C_Timer.After(RESYNC_SETTLE_DELAY, function()
    if not self or not self._state then return end
    if self._state[tokenKey] ~= token then return end
    applyFn()
  end)
end

function GearDisplay:RequestSpecResync(_reason)
  local state = EnsureState(self)
  RequestGroupResync(self, "specResyncToken", function()
    self:_ApplySpecFromState(state)
  end)
end

function GearDisplay:RequestLootSpecResync(_reason)
  local state = EnsureState(self)
  RequestGroupResync(self, "lootResyncToken", function()
    self:_ApplyLootSpecFromState(state)
  end)
end

function GearDisplay:_UpdateSpecButtons(state)
  if not state or not state.specPanel then return end
  self:_ApplySpecFromState(state)
  self:_ApplyLootSpecFromState(state)
end

---------------------------------------------------------------------------
-- Request throttled update
---------------------------------------------------------------------------
function GearDisplay:RequestUpdate(reason)
  if not IsRefactorEnabled() then return false end

  local state = EnsureState(self)
  state.counters.updateRequests = (state.counters.updateRequests or 0) + 1

  local function runUpdate()
    self:UpdateGear()
  end

  local guards = CS and CS.Guards or nil
  if guards and guards.Throttle then
    guards:Throttle("gear_display_update", UPDATE_THROTTLE_INTERVAL, runUpdate)
  elseif C_Timer and C_Timer.After then
    C_Timer.After(0, runUpdate)
  else
    runUpdate()
  end
  return true
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
-- Called by Coordinator's consolidated CharacterFrame OnShow hook.
function GearDisplay:_OnCharacterFrameShow(reason)
  local state = EnsureState(self)
  self:Create(ResolveParent())
  local ls = CS and CS.Layout and CS.Layout._state or nil
  local pane = ls and ls.activePane or "character"
  if pane == "character" and state.root then state.root:Show() end
  self:RequestUpdate(reason or "CharacterFrame.OnShow")
end

-- Called by Coordinator's consolidated CharacterFrame OnHide hook.
function GearDisplay:_OnCharacterFrameHide()
  local state = EnsureState(self)
  if state.root then state.root:Hide() end
end

function GearDisplay:_EnsureHooks()
  local state = EnsureState(self)
  if state.hooksInstalled then return end
  state.hooksInstalled = true
end

-- Called by Layout's consolidated ToggleCharacter hook.
function GearDisplay:_OnToggleCharacter()
  if not IsRefactorEnabled() then return end
  if IsAccountTransferBuild() and IsNativeCurrencyMode() then return end
  local parent = ResolveParent()
  if parent then self:Create(parent) end
  if CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown() then
    self:RequestUpdate("ToggleCharacter")
  end
end

function GearDisplay:_EnsureEventFrame()
  local state = EnsureState(self)
  if state.eventFrame then return end

  state.eventFrame = CreateFrame("Frame")
  state.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  state.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  state.eventFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
  state.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
  if state.eventFrame.RegisterEvent then
    pcall(state.eventFrame.RegisterEvent, state.eventFrame, "TRAIT_CONFIG_UPDATED")
  end
  if state.eventFrame.RegisterUnitEvent then
    state.eventFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
  else
    state.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
  end
  state.eventFrame:SetScript("OnEvent", function(_, event, unit)
    if not IsRefactorEnabled() then return end
    if event == "UNIT_INVENTORY_CHANGED" and unit and unit ~= "player" then return end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
      if unit and unit ~= "player" then return end
      self:RequestSpecResync("event:" .. tostring(event))
      self:RequestLootSpecResync("event:" .. tostring(event))
      self:RequestUpdate("event:" .. tostring(event))
      return
    end
    if event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
      self:RequestSpecResync("event:" .. tostring(event))
      self:RequestLootSpecResync("event:" .. tostring(event))
      return
    end
    if event == "PLAYER_LOOT_SPEC_UPDATED" then
      self:RequestLootSpecResync("event:" .. tostring(event))
      return
    end
    self:RequestUpdate("event:" .. tostring(event))
  end)
end

function GearDisplay:_HandleCoordinatorGearFlush(reason)
  local state = EnsureState(self)
  if not IsRefactorEnabled() then
    if state.root then state.root:Hide() end
    if state.specPanel then state.specPanel:Hide() end
    return
  end
  if IsNativeCurrencyMode() then
    if state.root then state.root:Hide() end
    if state.specPanel then state.specPanel:Hide() end
    return
  end

  self:_EnsureHooks()
  self:_EnsureEventFrame()

  local parent = ResolveParent()
  if not parent then return end
  self:Create(parent)
  self:RequestUpdate(reason or "coordinator.gear")
end

function GearDisplay:Update(reason)
  local state = EnsureState(self)
  if not IsRefactorEnabled() then
    if state.root then state.root:Hide() end
    if state.specPanel then state.specPanel:Hide() end
    return false
  end
  if IsNativeCurrencyMode() then
    if state.root then state.root:Hide() end
    if state.specPanel then state.specPanel:Hide() end
    return false
  end

  self:_EnsureHooks()
  self:_EnsureEventFrame()

  local parent = ResolveParent()
  if not parent then return false end
  self:Create(parent)
  return self:RequestUpdate(reason or "coordinator.gear")
end

function GearDisplay:GetDebugCounters()
  local state = EnsureState(self)
  return {
    creates = state.counters.creates or 0,
    updateRequests = state.counters.updateRequests or 0,
    updatesApplied = state.counters.updatesApplied or 0,
  }
end

local coordinator = CS and CS.Coordinator or nil
if coordinator and coordinator.SetFlushHandler then
  coordinator:SetFlushHandler("gear", function(_, reason)
    GearDisplay:_HandleCoordinatorGearFlush(reason)
  end)
end
