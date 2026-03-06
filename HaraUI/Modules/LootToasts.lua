--[[
  Loot Toasts Module

  Interface:
    M:Apply()        - Initialize/update with current settings
    M:Disable()      - Clean up and hide all toasts
    M:SetLocked()    - Toggle drag mode
    M:Preview()      - Show preview toasts

  Events Registered:
    - CHAT_MSG_LOOT
    - CHAT_MSG_MONEY
    - CHAT_MSG_CURRENCY
--]]

local ADDON, NS = ...
local M = {}
NS:RegisterModule("loot", M)
M.active = false

local state = {
  pool = {},
  active = {},
  anchorFrame = nil,
  toastTimers = {},
  eventFrame = nil,
}
local ShowItemTooltip
local LayoutToasts
local ReleaseToast
local RemoveActiveToast
local PLAYER_GUID = UnitGUID and UnitGUID("player") or nil
local issecretvalue = issecretvalue

local CACHED_LOOT_ITEM_CREATED
local CACHED_LOOT_ITEM_CREATED_MULTIPLE
local CACHED_LOOT_ITEM
local CACHED_LOOT_ITEM_MULTIPLE
local CACHED_LOOT_ITEM_PUSHED
local CACHED_LOOT_ITEM_PUSHED_MULTIPLE

local LOOT_ITEM_CREATED_PATTERN
local LOOT_ITEM_CREATED_MULTIPLE_PATTERN
local LOOT_ITEM_PATTERN
local LOOT_ITEM_MULTIPLE_PATTERN
local LOOT_ITEM_PUSHED_PATTERN
local LOOT_ITEM_PUSHED_MULTIPLE_PATTERN
local StripReceivePrefix

local TOAST_STYLE_DEFAULT = "default"
local TOAST_STYLE_UPGRADE = "upgrade"
local TOAST_STYLE_LEGENDARY = "legendary"
local TOAST_STYLE_CURRENCY = "currency"
local TOAST_STYLE_MONEY = "money"

local TOAST_STYLES = {
  [TOAST_STYLE_DEFAULT] = {
    bgTop = { 0.11, 0.12, 0.15, 0.98 },
    bgBottom = { 0.03, 0.04, 0.05, 0.98 },
    accent = { 0.95, 0.43, 0.03, 0.95 },
    title = { 1.0, 0.82, 0.28, 1.0 },
    text = { 1.0, 1.0, 1.0, 1.0 },
  },
  [TOAST_STYLE_UPGRADE] = {
    bgTop = { 0.27, 0.18, 0.06, 0.98 },
    bgBottom = { 0.08, 0.05, 0.02, 0.98 },
    accent = { 1.0, 0.73, 0.16, 1.0 },
    title = { 1.0, 0.88, 0.42, 1.0 },
    text = { 1.0, 0.97, 0.88, 1.0 },
  },
  [TOAST_STYLE_LEGENDARY] = {
    bgTop = { 0.30, 0.13, 0.04, 0.98 },
    bgBottom = { 0.09, 0.03, 0.01, 0.98 },
    accent = { 1.0, 0.57, 0.10, 1.0 },
    title = { 1.0, 0.78, 0.30, 1.0 },
    text = { 1.0, 0.96, 0.88, 1.0 },
  },
  [TOAST_STYLE_CURRENCY] = {
    bgTop = { 0.08, 0.12, 0.10, 0.98 },
    bgBottom = { 0.03, 0.06, 0.05, 0.98 },
    accent = { 0.38, 0.86, 0.54, 1.0 },
    title = { 0.72, 1.0, 0.80, 1.0 },
    text = { 0.95, 1.0, 0.97, 1.0 },
  },
  [TOAST_STYLE_MONEY] = {
    bgTop = { 0.12, 0.10, 0.04, 0.98 },
    bgBottom = { 0.05, 0.04, 0.01, 0.98 },
    accent = { 1.0, 0.84, 0.26, 1.0 },
    title = { 1.0, 0.92, 0.42, 1.0 },
    text = { 1.0, 0.98, 0.86, 1.0 },
  },
}

local ARROW_OFFSETS = {
  { delay = 0.00, x = 0 },
  { delay = 0.08, x = -8 },
  { delay = 0.16, x = 14 },
  { delay = 0.24, x = 7 },
  { delay = 0.32, x = -14 },
}

local function UpdateLootPatterns()
  if CACHED_LOOT_ITEM_CREATED ~= LOOT_ITEM_CREATED_SELF then
    LOOT_ITEM_CREATED_PATTERN = LOOT_ITEM_CREATED_SELF:gsub("%%s", "(.+)"):gsub("^", "^")
    CACHED_LOOT_ITEM_CREATED = LOOT_ITEM_CREATED_SELF
  end

  if CACHED_LOOT_ITEM_CREATED_MULTIPLE ~= LOOT_ITEM_CREATED_SELF_MULTIPLE then
    LOOT_ITEM_CREATED_MULTIPLE_PATTERN = LOOT_ITEM_CREATED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
    CACHED_LOOT_ITEM_CREATED_MULTIPLE = LOOT_ITEM_CREATED_SELF_MULTIPLE
  end

  if CACHED_LOOT_ITEM ~= LOOT_ITEM_SELF then
    LOOT_ITEM_PATTERN = LOOT_ITEM_SELF:gsub("%%s", "(.+)"):gsub("^", "^")
    CACHED_LOOT_ITEM = LOOT_ITEM_SELF
  end

  if CACHED_LOOT_ITEM_MULTIPLE ~= LOOT_ITEM_SELF_MULTIPLE then
    LOOT_ITEM_MULTIPLE_PATTERN = LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
    CACHED_LOOT_ITEM_MULTIPLE = LOOT_ITEM_SELF_MULTIPLE
  end

  if CACHED_LOOT_ITEM_PUSHED ~= LOOT_ITEM_PUSHED_SELF then
    LOOT_ITEM_PUSHED_PATTERN = LOOT_ITEM_PUSHED_SELF:gsub("%%s", "(.+)"):gsub("^", "^")
    CACHED_LOOT_ITEM_PUSHED = LOOT_ITEM_PUSHED_SELF
  end

  if CACHED_LOOT_ITEM_PUSHED_MULTIPLE ~= LOOT_ITEM_PUSHED_SELF_MULTIPLE then
    LOOT_ITEM_PUSHED_MULTIPLE_PATTERN = LOOT_ITEM_PUSHED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
    CACHED_LOOT_ITEM_PUSHED_MULTIPLE = LOOT_ITEM_PUSHED_SELF_MULTIPLE
  end
end

local function DelayedUpdateLootPatterns()
  if C_Timer and C_Timer.After then
    C_Timer.After(0.1, UpdateLootPatterns)
  end
end

-- Parser
local function ResolveToastItemData(toast)
  if not toast then return nil, nil end
  local itemID = toast._huiItemID
  local itemLink = toast._huiTooltipLink or toast._huiItemLink
  local itemName = toast._huiItemName

  if not itemLink and not itemID and itemName and itemName ~= "" then
    local _, link = GetItemInfo(itemName)
    if link then
      itemLink = link
    end
  end

  if not itemLink and toast.text and toast.text.GetText then
    local txt = toast.text:GetText()
    if txt and txt ~= "" then
      itemLink = txt:match("(|Hitem:.-|h%[.-%]|h)") or txt:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
      if not itemName then
        itemName = txt:match("%[(.-)%]")
      end
      if not itemLink and itemName and itemName ~= "" then
        local _, link = GetItemInfo(itemName)
        if link then
          itemLink = link
        end
      end
    end
  end

  if not itemID and itemLink then
    local id = itemLink:match("|Hitem:(%d+)")
    if id then
      itemID = tonumber(id)
    end
  end

  return itemID, itemLink
end

local function NormalizeItemLink(link)
  if type(link) ~= "string" or link == "" then
    return nil
  end
  return link:match("(|Hitem:.-|h%[.-%]|h)") or link:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or link
end

local function ExtractItemName(link)
  if type(link) ~= "string" or link == "" then
    return nil
  end
  return link:match("%[(.-)%]")
end

local function GetItemInfoInstantCompat(itemID)
  if not itemID or not C_Item or not C_Item.GetItemInfoInstant then
    return nil, nil
  end
  local _, _, _, equipLoc, icon = C_Item.GetItemInfoInstant(itemID)
  return icon, equipLoc
end

local function ColorizeText(text, quality)
  if type(text) ~= "string" or text == "" then
    return text
  end
  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    return ITEM_QUALITY_COLORS[quality].hex .. text .. "|r"
  end
  return text
end

local function BuildItemText(name, quality, ilvl)
  local label = ColorizeText(name or "Loot", quality)
  if ilvl and ilvl > 0 then
    local hex = (quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex) or "|cffffffff"
    return ("[%s%d|r] %s"):format(hex, ilvl, label)
  end
  return label
end

local function ApplyToastFont(fontString, size)
  if not fontString then return end
  NS:ApplyDefaultFont(fontString, size)
end

local function ApplyToastLayout(t, db)
  if not t or not db then return end
  local w = db.width or 224
  local h = db.height or 48
  local textOffset = 5
  t:SetSize(w, h)

  local iconSize = math.max(34, math.min(h - 6, 42))
  t.iconFrame:SetSize(iconSize, iconSize)
  t.icon:SetSize(iconSize, iconSize)

  local iconOffset = 3
  local minIconOffset = 6
  local maxIconOffset = math.max(minIconOffset, w - iconSize - 6)
  iconOffset = math.min(math.max(iconOffset, minIconOffset), maxIconOffset)
  t.iconFrame:ClearAllPoints()
  t.iconFrame:SetPoint("LEFT", t, "LEFT", iconOffset, 0)
  local textAreaLeft = iconOffset + iconSize + 8
  local textAreaRight = 6
  local textAreaWidth = math.max(120, w - textAreaLeft - textAreaRight)
  local textCenterX = ((textAreaLeft + (w - textAreaRight)) / 2) + textOffset

  t.title:ClearAllPoints()
  t.title:SetPoint("TOP", t, "TOP", textCenterX - (w / 2), -6)
  t.title:SetWidth(textAreaWidth)
  t.text:ClearAllPoints()
  t.text:SetPoint("BOTTOM", t, "BOTTOM", textCenterX - (w / 2), 6)
  t.text:SetWidth(textAreaWidth)
  t.textBG:ClearAllPoints()
  t.textBG:SetPoint("TOPLEFT", t, "TOPLEFT", textAreaLeft - 2 + textOffset, -5)
  t.textBG:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -textAreaRight, 5)
  if t.accentBar then
    t.accentBar:ClearAllPoints()
    t.accentBar:SetPoint("TOPLEFT", t.textBG, "TOPLEFT", 0, 0)
    t.accentBar:SetPoint("BOTTOMLEFT", t.textBG, "BOTTOMLEFT", 0, 0)
    t.accentBar:SetWidth(2)
  end
  if t.countBG then
    t.countBG:ClearAllPoints()
    t.countBG:SetPoint("BOTTOMLEFT", t.iconFrame, "BOTTOMLEFT", 0, 0)
    t.countBG:SetPoint("BOTTOMRIGHT", t.iconFrame, "BOTTOMRIGHT", 0, 0)
    t.countBG:SetHeight(14)
  end
  if t.countText then
    t.countText:ClearAllPoints()
    t.countText:SetPoint("BOTTOMRIGHT", t.iconFrame, "BOTTOMRIGHT", -3, 2)
  end
  if t.iconGlow then
    t.iconGlow:SetPoint("CENTER", t.iconFrame, "CENTER", 0, 0)
    t.iconGlow:SetSize(iconSize + 36, iconSize + 30)
  end
  if t.upgradeArrows then
    for index, arrow in ipairs(t.upgradeArrows) do
      local cfg = ARROW_OFFSETS[index]
      arrow:ClearAllPoints()
      arrow:SetPoint("CENTER", t.iconFrame, "BOTTOM", cfg.x, -2)
    end
  end
  if t.bg then t.bg:SetAllPoints(true) end
  if t.bgGradient then t.bgGradient:SetAllPoints(true) end
  if t.shine then t.shine:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, -2) end
  if t.borderTex then t.borderTex:SetAllPoints(true) end
end

local function EnsureAnchor()
  if state.anchorFrame then return state.anchorFrame end
  state.anchorFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  state.anchorFrame:SetSize(24, 24)
  state.anchorFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -220)
  state.anchorFrame:Hide()

  state.anchorFrame.tex = state.anchorFrame:CreateTexture(nil, "OVERLAY")
  state.anchorFrame.tex:SetAllPoints(true)
  state.anchorFrame.tex:SetColorTexture(1, 1, 1, 0.08)

  state.anchorFrame.label = state.anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  state.anchorFrame.label:SetPoint("CENTER")
  state.anchorFrame.label:SetText("Loot")
  ApplyToastFont(state.anchorFrame.label, 12)

  NS:MakeMovable(state.anchorFrame, "loot", "Loot Toasts (drag)")
  return state.anchorFrame
end

-- Pool
local function AcquireToast()
  local t = table.remove(state.pool)
  if t then return t end

  t = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  t:SetSize(224, 48)
  t:EnableMouse(true)
  if t.SetMouseClickEnabled then t:SetMouseClickEnabled(false) end
  if t.SetMouseMotionEnabled then t:SetMouseMotionEnabled(true) end

  -- Pixel-perfect positioning
  if t.SetSnapToPixelGrid then
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
  end

  t.bg = t:CreateTexture(nil, "BACKGROUND")
  t.bg:SetAllPoints(true)
  t.bg:SetColorTexture(0.04, 0.05, 0.06, 0.98)

  t.bgGradient = t:CreateTexture(nil, "BACKGROUND", nil, 1)
  t.bgGradient:SetAllPoints(true)
  t.bgGradient:SetTexture("Interface\\Buttons\\WHITE8x8")
  if t.bgGradient.SetGradient and CreateColor then
    t.bgGradient:SetGradient(
      "VERTICAL",
      CreateColor(0.12, 0.13, 0.16, 0.96),
      CreateColor(0.03, 0.04, 0.05, 0.96)
    )
  else
    t.bgGradient:SetColorTexture(0.08, 0.09, 0.10, 0.96)
  end

  t.borderGlow = t:CreateTexture(nil, "BACKGROUND", nil, 2)
  t.borderGlow:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow")
  t.borderGlow:SetTexCoord(5 / 512, 395 / 512, 5 / 256, 167 / 256)
  t.borderGlow:SetBlendMode("ADD")
  t.borderGlow:SetAlpha(0)
  t.borderGlow:SetPoint("CENTER", t, "CENTER", 0, 0)
  t.borderGlow:SetSize(318, 152)

  t.iconFrame = CreateFrame("Frame", nil, t)
  t.iconFrame:SetSize(42, 42)
  t.iconFrame:SetPoint("LEFT", t, "LEFT", 6, 0)
  t.iconFrame:EnableMouse(true)
  if t.iconFrame.SetMouseClickEnabled then t.iconFrame:SetMouseClickEnabled(false) end
  if t.iconFrame.SetMouseMotionEnabled then t.iconFrame:SetMouseMotionEnabled(true) end

  t.iconFrame.bg = t.iconFrame:CreateTexture(nil, "BACKGROUND")
  t.iconFrame.bg:SetAllPoints(true)
  t.iconFrame.bg:SetColorTexture(0.02, 0.02, 0.03, 0.95)

  t.icon = t.iconFrame:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(42, 42)
  t.icon:SetAllPoints(t.iconFrame)
  t.icon:SetTexCoord(4 / 64, 60 / 64, 4 / 64, 60 / 64)

  if t.icon.SetSnapToPixelGrid then
    t.icon:SetSnapToPixelGrid(false)
    t.icon:SetTexelSnappingBias(0)
  end

  t.iconGlow = t.iconFrame:CreateTexture(nil, "BACKGROUND", nil, 3)
  t.iconGlow:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow")
  t.iconGlow:SetTexCoord(5 / 512, 395 / 512, 5 / 256, 167 / 256)
  t.iconGlow:SetBlendMode("ADD")
  t.iconGlow:SetAlpha(0)
  t.iconGlow:SetPoint("CENTER", t.iconFrame, "CENTER", 0, 0)
  t.iconGlow:SetSize(74, 68)

  t.iconFrame:SetScript("OnEnter", function(self)
    local toast = self:GetParent()
    if not toast then return end
    ShowItemTooltip(self, toast)
  end)

  t.iconFrame:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  t:SetScript("OnEnter", function(self)
    ShowItemTooltip(self.iconFrame or self, self)
  end)

  t:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  t:SetScript("OnHide", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  t.title = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.title:SetPoint("TOP", t, "TOP", 0, -6)
  t.title:SetWidth(156)
  t.title:SetHeight(16)
  t.title:SetJustifyH("LEFT")
  t.title:SetJustifyV("MIDDLE")
  ApplyToastFont(t.title, 12)

  t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.text:SetPoint("BOTTOM", t, "BOTTOM", 0, 6)
  t.text:SetWidth(156)
  t.text:SetHeight(22)
  t.text:SetMaxLines(2)
  t.text:SetJustifyH("LEFT")
  t.text:SetJustifyV("MIDDLE")
  ApplyToastFont(t.text, 12)

  t.textBG = t:CreateTexture(nil, "BACKGROUND", nil, 1)
  t.textBG:SetPoint("TOPLEFT", 62, -12)
  t.textBG:SetPoint("BOTTOMRIGHT", -8, 12)
  t.textBG:SetTexture("Interface\\Buttons\\WHITE8x8")
  if t.textBG.SetGradient and CreateColor then
    t.textBG:SetGradient(
      "HORIZONTAL",
      CreateColor(0, 0, 0, 0.56),
      CreateColor(0, 0, 0, 0.18)
    )
  else
    t.textBG:SetColorTexture(0, 0, 0, 0.32)
  end

  t.accentBar = t:CreateTexture(nil, "BACKGROUND", nil, 2)
  t.accentBar:SetWidth(2)
  t.accentBar:SetColorTexture(1, 0.43, 0.03, 0.95)

  t.countBG = t.iconFrame:CreateTexture(nil, "BACKGROUND", nil, 4)
  t.countBG:SetTexture("Interface\\Buttons\\WHITE8x8")
  if t.countBG.SetGradient and CreateColor then
    t.countBG:SetGradient(
      "VERTICAL",
      CreateColor(0, 0, 0, 0),
      CreateColor(0, 0, 0, 0.88)
    )
  else
    t.countBG:SetColorTexture(0, 0, 0, 0.85)
  end
  t.countBG:Hide()

  t.countText = t.iconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.countText:SetPoint("BOTTOMRIGHT", t.iconFrame, "BOTTOMRIGHT", -3, 2)
  t.countText:SetJustifyH("RIGHT")
  t.countText:SetJustifyV("BOTTOM")
  ApplyToastFont(t.countText, 12)
  t.countText:SetText("")

  t.border = {}
  t.border.top = t:CreateTexture(nil, "OVERLAY")
  t.border.top:SetPoint("TOPLEFT")
  t.border.top:SetPoint("TOPRIGHT")
  t.border.top:SetHeight(1)
  t.border.top:SetColorTexture(1, 1, 1, 1)

  t.border.bottom = t:CreateTexture(nil, "OVERLAY")
  t.border.bottom:SetPoint("BOTTOMLEFT")
  t.border.bottom:SetPoint("BOTTOMRIGHT")
  t.border.bottom:SetHeight(1)
  t.border.bottom:SetColorTexture(1, 1, 1, 1)

  t.border.left = t:CreateTexture(nil, "OVERLAY")
  t.border.left:SetPoint("TOPLEFT")
  t.border.left:SetPoint("BOTTOMLEFT")
  t.border.left:SetWidth(1)
  t.border.left:SetColorTexture(1, 1, 1, 1)

  t.border.right = t:CreateTexture(nil, "OVERLAY")
  t.border.right:SetPoint("TOPRIGHT")
  t.border.right:SetPoint("BOTTOMRIGHT")
  t.border.right:SetWidth(1)
  t.border.right:SetColorTexture(1, 1, 1, 1)

  t.iconBorder = {}
  t.iconBorder.top = t.iconFrame:CreateTexture(nil, "OVERLAY")
  t.iconBorder.top:SetPoint("TOPLEFT", -1, 1)
  t.iconBorder.top:SetPoint("TOPRIGHT", 1, 1)
  t.iconBorder.top:SetHeight(1)
  t.iconBorder.top:SetColorTexture(1, 1, 1, 1)

  t.iconBorder.bottom = t.iconFrame:CreateTexture(nil, "OVERLAY")
  t.iconBorder.bottom:SetPoint("BOTTOMLEFT", -1, -1)
  t.iconBorder.bottom:SetPoint("BOTTOMRIGHT", 1, -1)
  t.iconBorder.bottom:SetHeight(1)
  t.iconBorder.bottom:SetColorTexture(1, 1, 1, 1)

  t.iconBorder.left = t.iconFrame:CreateTexture(nil, "OVERLAY")
  t.iconBorder.left:SetPoint("TOPLEFT", -1, 1)
  t.iconBorder.left:SetPoint("BOTTOMLEFT", -1, -1)
  t.iconBorder.left:SetWidth(1)
  t.iconBorder.left:SetColorTexture(1, 1, 1, 1)

  t.iconBorder.right = t.iconFrame:CreateTexture(nil, "OVERLAY")
  t.iconBorder.right:SetPoint("TOPRIGHT", 1, 1)
  t.iconBorder.right:SetPoint("BOTTOMRIGHT", 1, -1)
  t.iconBorder.right:SetWidth(1)
  t.iconBorder.right:SetColorTexture(1, 1, 1, 1)

  t.upgradeArrows = {}
  t.arrowAnim = t:CreateAnimationGroup()
  t.arrowAnim:SetToFinalAlpha(true)
  for index, cfg in ipairs(ARROW_OFFSETS) do
    local arrow = t.iconFrame:CreateTexture(nil, "OVERLAY", "LootUpgradeFrame_ArrowTemplate")
    arrow:SetAlpha(0)
    arrow:SetPoint("CENTER", t.iconFrame, "BOTTOM", cfg.x, -2)
    t.upgradeArrows[index] = arrow
    t["UpgradeArrow" .. index] = arrow

    local resetAlpha = t.arrowAnim:CreateAnimation("Alpha")
    resetAlpha:SetChildKey("UpgradeArrow" .. index)
    resetAlpha:SetOrder(1)
    resetAlpha:SetFromAlpha(1)
    resetAlpha:SetToAlpha(0)
    resetAlpha:SetDuration(0)

    local fadeIn = t.arrowAnim:CreateAnimation("Alpha")
    fadeIn:SetChildKey("UpgradeArrow" .. index)
    fadeIn:SetOrder(2)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetStartDelay(cfg.delay)
    fadeIn:SetDuration(0.22)

    local fadeOut = t.arrowAnim:CreateAnimation("Alpha")
    fadeOut:SetChildKey("UpgradeArrow" .. index)
    fadeOut:SetOrder(2)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(cfg.delay + 0.22)
    fadeOut:SetDuration(0.24)

    local rise = t.arrowAnim:CreateAnimation("Translation")
    rise:SetChildKey("UpgradeArrow" .. index)
    rise:SetOrder(2)
    rise:SetOffset(0, 44)
    rise:SetStartDelay(cfg.delay)
    rise:SetDuration(0.46)
  end

  t.introAnim = t:CreateAnimationGroup()
  t.introAnim:SetToFinalAlpha(true)
  local introAlpha = t.introAnim:CreateAnimation("Alpha")
  introAlpha:SetOrder(1)
  introAlpha:SetFromAlpha(0)
  introAlpha:SetToAlpha(1)
  introAlpha:SetDuration(0.16)

  local introMove = t.introAnim:CreateAnimation("Translation")
  introMove:SetOrder(1)
  introMove:SetOffset(-10, 0)
  introMove:SetDuration(0.16)

  local glowIn = t.introAnim:CreateAnimation("Alpha")
  glowIn:SetChildKey("borderGlow")
  glowIn:SetOrder(1)
  glowIn:SetFromAlpha(0)
  glowIn:SetToAlpha(0.55)
  glowIn:SetDuration(0.18)

  local glowOut = t.introAnim:CreateAnimation("Alpha")
  glowOut:SetChildKey("borderGlow")
  glowOut:SetOrder(2)
  glowOut:SetFromAlpha(0.55)
  glowOut:SetToAlpha(0)
  glowOut:SetDuration(0.55)

  t.shine = t:CreateTexture(nil, "OVERLAY")
  t.shine:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow")
  t.shine:SetTexCoord(403 / 512, 465 / 512, 14 / 256, 62 / 256)
  t.shine:SetBlendMode("ADD")
  t.shine:SetAlpha(0)
  t.shine:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, -2)
  t.shine:SetSize(66, 52)

  local shineIn = t.introAnim:CreateAnimation("Alpha")
  shineIn:SetChildKey("shine")
  shineIn:SetOrder(1)
  shineIn:SetFromAlpha(0)
  shineIn:SetToAlpha(1)
  shineIn:SetDuration(0.14)

  local shineMove = t.introAnim:CreateAnimation("Translation")
  shineMove:SetChildKey("shine")
  shineMove:SetOrder(2)
  shineMove:SetOffset(150, 0)
  shineMove:SetDuration(0.65)

  local shineOut = t.introAnim:CreateAnimation("Alpha")
  shineOut:SetChildKey("shine")
  shineOut:SetOrder(2)
  shineOut:SetFromAlpha(1)
  shineOut:SetToAlpha(0)
  shineOut:SetStartDelay(0.18)
  shineOut:SetDuration(0.45)

  t.outroAnim = t:CreateAnimationGroup()
  t.outroAnim:SetToFinalAlpha(true)

  local outroAlpha = t.outroAnim:CreateAnimation("Alpha")
  outroAlpha:SetOrder(1)
  outroAlpha:SetFromAlpha(1)
  outroAlpha:SetToAlpha(0)
  outroAlpha:SetDuration(0.28)

  local outroMove = t.outroAnim:CreateAnimation("Translation")
  outroMove:SetOrder(1)
  outroMove:SetOffset(12, 0)
  outroMove:SetDuration(0.28)

  t.outroAnim:SetScript("OnFinished", function(anim)
    local toast = anim:GetParent()
    RemoveActiveToast(toast)
    ReleaseToast(toast)
    LayoutToasts()
  end)

  t:Hide()
  return t
end

LayoutToasts = function()
  local db = NS:GetDB()
  local point, x, y = db.loot.anchor, db.loot.x, db.loot.y
  local scale = db.loot.scale or 1.0
  local anchor = EnsureAnchor()
  anchor:ClearAllPoints()
  anchor:SetPoint(point, UIParent, point, x, y)
  for i, t in ipairs(state.active) do
    t:ClearAllPoints()
    local height = (t.GetHeight and t:GetHeight()) or db.loot.height or 48
    t:SetPoint(point, anchor, point, 0, -((i - 1) * ((height + 6) * scale)))
  end
end

-- Timer
ReleaseToast = function(t)
  if t and t.SetScript then
    t:SetScript("OnUpdate", nil)
  end
  if GameTooltip and t and t.iconFrame and GameTooltip:IsOwned(t.iconFrame) then
    GameTooltip:Hide()
  end
  t:Hide()
  if state.toastTimers[t] then
    state.toastTimers[t]:Cancel()
    state.toastTimers[t] = nil
  end
  if t and t.introAnim then
    t.introAnim:Stop()
  end
  if t and t.outroAnim then
    t.outroAnim:Stop()
  end
  if t and t.arrowAnim then
    t.arrowAnim:Stop()
  end
  if t and t.borderGlow then
    t.borderGlow:SetAlpha(0)
  end
  if t and t.iconGlow then
    t.iconGlow:SetAlpha(0)
  end
  if t and t.shine then
    t.shine:SetAlpha(0)
  end
  if t and t.upgradeArrows then
    for _, arrow in ipairs(t.upgradeArrows) do
      arrow:SetAlpha(0)
    end
  end
  if t and t.countBG then
    t.countBG:Hide()
  end
  if t and t.countText then
    t.countText:SetText("")
  end
  if t then
    t:SetAlpha(1)
    t._huiIsFading = nil
    t._huiTooltipLink = nil
    t._huiItemStyle = nil
    t._huiQuality = nil
    t._huiCount = nil
  end
  table.insert(state.pool, t)
end

local function HexToRGB(hex)
  if not hex or #hex < 8 then return end
  local r = tonumber(hex:sub(3, 4), 16)
  local g = tonumber(hex:sub(5, 6), 16)
  local b = tonumber(hex:sub(7, 8), 16)
  if not r or not g or not b then return end
  return r / 255, g / 255, b / 255
end

local function SetToastBorderColor(toast, r, g, b, a)
  if toast.border then
    if toast.border.top then toast.border.top:SetColorTexture(r, g, b, a) end
    if toast.border.bottom then toast.border.bottom:SetColorTexture(r, g, b, a) end
    if toast.border.left then toast.border.left:SetColorTexture(r, g, b, a) end
    if toast.border.right then toast.border.right:SetColorTexture(r, g, b, a) end
  end
  if toast.iconBorder then
    if toast.iconBorder.top then toast.iconBorder.top:SetColorTexture(r, g, b, a) end
    if toast.iconBorder.bottom then toast.iconBorder.bottom:SetColorTexture(r, g, b, a) end
    if toast.iconBorder.left then toast.iconBorder.left:SetColorTexture(r, g, b, a) end
    if toast.iconBorder.right then toast.iconBorder.right:SetColorTexture(r, g, b, a) end
  end
end

local function UpdateCountBadge(toast, count)
  if not toast or not toast.countBG or not toast.countText then return end
  if count and count > 1 then
    toast.countText:SetText(count)
    toast.countBG:Show()
  else
    toast.countText:SetText("")
    toast.countBG:Hide()
  end
end

local function ApplyToastStyle(toast, payload)
  if not toast or not payload then return end

  local style = TOAST_STYLES[payload.style or TOAST_STYLE_DEFAULT] or TOAST_STYLES[TOAST_STYLE_DEFAULT]
  local r, g, b
  if payload.quality ~= nil and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[payload.quality] then
    local c = ITEM_QUALITY_COLORS[payload.quality]
    r, g, b = c.r, c.g, c.b
  elseif payload.linkColor then
    r, g, b = HexToRGB(payload.linkColor)
  end
  if not (r and g and b) then
    r, g, b = style.accent[1], style.accent[2], style.accent[3]
  end

  if toast.bgGradient then
    if toast.bgGradient.SetGradient and CreateColor then
      toast.bgGradient:SetGradient(
        "VERTICAL",
        CreateColor(style.bgTop[1], style.bgTop[2], style.bgTop[3], style.bgTop[4]),
        CreateColor(style.bgBottom[1], style.bgBottom[2], style.bgBottom[3], style.bgBottom[4])
      )
    else
      toast.bgGradient:SetColorTexture(style.bgTop[1], style.bgTop[2], style.bgTop[3], style.bgTop[4])
    end
  end

  if toast.accentBar then
    toast.accentBar:SetColorTexture(r, g, b, 0.95)
  end
  if toast.title then
    toast.title:SetTextColor(style.title[1], style.title[2], style.title[3], style.title[4])
  end
  if toast.text then
    toast.text:SetTextColor(style.text[1], style.text[2], style.text[3], style.text[4])
  end
  if toast.countText then
    toast.countText:SetTextColor(1, 1, 1, 1)
  end
  if toast.iconGlow then
    toast.iconGlow:SetVertexColor(r, g, b, 0.45)
  end
  if toast.borderGlow then
    toast.borderGlow:SetVertexColor(r, g, b, 0.70)
  end
  if toast.shine then
    toast.shine:SetVertexColor(r, g, b, 0.85)
  end
  SetToastBorderColor(toast, r, g, b, 1)
  UpdateCountBadge(toast, payload.count)
end

local function PlayToastIntro(toast, payload)
  if not toast then return end
  toast:SetAlpha(0)
  if toast.introAnim then
    toast.introAnim:Stop()
    toast.introAnim:Play()
  else
    toast:SetAlpha(1)
  end
  if payload and payload.isUpgraded and toast.arrowAnim then
    if LOOTUPGRADEFRAME_QUALITY_TEXTURES and payload.quality and toast.upgradeArrows then
      local upgradeTexture = LOOTUPGRADEFRAME_QUALITY_TEXTURES[payload.quality] or LOOTUPGRADEFRAME_QUALITY_TEXTURES[2]
      if upgradeTexture then
        for _, arrow in ipairs(toast.upgradeArrows) do
          arrow:SetAtlas(upgradeTexture.arrow, true)
        end
      end
    end
    toast.arrowAnim:Stop()
    toast.arrowAnim:Play()
  end
end

ShowItemTooltip = function(owner, toast)
  if not owner or not toast or not GameTooltip then return end
  local itemID, itemLink = ResolveToastItemData(toast)
  if not itemID and not itemLink then return end

  -- Toasts are commonly anchored near screen right; force tooltip to the left of icon.
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -8, 0)
  if itemID and GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(itemID)
  elseif itemLink then
    local hyperlink = itemLink:match("(|Hitem:.-|h%[.-%]|h)")
    GameTooltip:SetHyperlink(hyperlink or itemLink)
  end
  GameTooltip:Show()
end

RemoveActiveToast = function(toast)
  for i = #state.active, 1, -1 do
    if state.active[i] == toast then
      table.remove(state.active, i)
      return
    end
  end
end

local function FadeToastOut(toast)
  if not toast or toast._huiIsFading then return end
  toast._huiIsFading = true
  if state.toastTimers[toast] then
    state.toastTimers[toast]:Cancel()
    state.toastTimers[toast] = nil
  end
  if toast.introAnim then
    toast.introAnim:Stop()
  end
  if toast.arrowAnim then
    toast.arrowAnim:Stop()
  end
  if toast.outroAnim then
    toast.outroAnim:Stop()
    toast.outroAnim:Play()
  else
    RemoveActiveToast(toast)
    ReleaseToast(toast)
    LayoutToasts()
  end
end

local function RefreshToastTimer(toast, durationOverride)
  if not toast then return end
  local db = NS:GetDB()
  local duration = durationOverride or (db and db.loot and db.loot.duration) or 3.5
  if state.toastTimers[toast] then
    state.toastTimers[toast]:Cancel()
  end
  state.toastTimers[toast] = C_Timer.NewTimer(duration, function()
    FadeToastOut(toast)
  end)
end

local function EnforceMaxToasts(limit)
  local maxToasts = math.max(1, tonumber(limit) or 4)
  while #state.active > maxToasts do
    local oldest = table.remove(state.active)
    if oldest then
      ReleaseToast(oldest)
    end
  end
end

local function ParseLootChatItem(msg)
  if type(msg) ~= "string" or msg == "" then return nil, nil end
  local link, count = msg:match(LOOT_ITEM_MULTIPLE_PATTERN)
  if not link then
    link, count = msg:match(LOOT_ITEM_PUSHED_MULTIPLE_PATTERN)
  end
  if not link then
    link, count = msg:match(LOOT_ITEM_CREATED_MULTIPLE_PATTERN)
  end
  if not link then
    link, count = msg:match(LOOT_ITEM_PATTERN)
    count = count or 1
  end
  if not link then
    link, count = msg:match(LOOT_ITEM_PUSHED_PATTERN)
    count = count or 1
  end
  if not link then
    link, count = msg:match(LOOT_ITEM_CREATED_PATTERN)
    count = count or 1
  end
  if not link then
    link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    count = tonumber(msg:match("[xX](%d+)")) or 1
  end
  return NormalizeItemLink(link), tonumber(count) or 1
end

local function BuildItemPayload(link, count, opts)
  opts = opts or {}
  local normalizedLink = NormalizeItemLink(link)
  if not normalizedLink then
    return nil
  end

  local itemID = normalizedLink:match("|Hitem:(%d+)")
  itemID = itemID and tonumber(itemID) or nil

  local itemName, itemLink, quality, _, _, _, _, _, equipLoc, icon
  if C_Item and C_Item.GetItemInfo then
    itemName, itemLink, quality, _, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(normalizedLink)
  elseif GetItemInfo then
    itemName, itemLink, quality, _, _, _, _, _, equipLoc, icon = GetItemInfo(normalizedLink)
  end

  if not icon then
    icon, equipLoc = GetItemInfoInstantCompat(itemID)
  end

  local displayName = itemName or ExtractItemName(normalizedLink)
  if not displayName then
    return nil
  end

  local tooltipLink = itemLink or normalizedLink
  local ilvl = 0
  if tooltipLink and C_Item and C_Item.GetDetailedItemLevelInfo and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
    ilvl = C_Item.GetDetailedItemLevelInfo(tooltipLink) or 0
  end

  local qualityDesc = quality and _G["ITEM_QUALITY" .. quality .. "_DESC"] or nil
  local title = opts.title or "You received"
  local style = opts.style or TOAST_STYLE_DEFAULT
  local soundID = opts.soundID

  if opts.isLegendary or quality == 5 then
    title = "Legendary Item"
    style = TOAST_STYLE_LEGENDARY
    soundID = soundID or 63971
  elseif opts.isUpgraded then
    if opts.baseQuality and quality and opts.baseQuality < quality and qualityDesc then
      title = qualityDesc .. " Upgrade"
    else
      title = "Item Upgraded"
    end
    style = TOAST_STYLE_UPGRADE
    soundID = soundID or 51561
  end

  return {
    kind = "item",
    icon = icon or 134400,
    title = title,
    text = BuildItemText(displayName, quality, ilvl),
    quality = quality,
    linkColor = normalizedLink:match("|c(%x%x%x%x%x%x%x%x)"),
    count = tonumber(count) or 1,
    itemID = itemID,
    itemLink = NormalizeItemLink(tooltipLink),
    tooltipLink = tooltipLink,
    itemName = displayName,
    isUpgraded = opts.isUpgraded == true,
    style = style,
    soundID = soundID,
  }
end

local function BuildMoneyPayload(msg)
  local clean = StripReceivePrefix(msg)
  if not clean or clean == "" then
    clean = msg
  end
  return {
    kind = "money",
    icon = 133784,
    title = "You received",
    text = clean or "Money",
    style = TOAST_STYLE_MONEY,
    count = 1,
  }
end

local function BuildCurrencyPayload(msg)
  local curLink = msg and msg:match("(|c%x+|Hcurrency:.-|h%[.-%]|h|r)")
  if not curLink then
    return nil
  end
  local icon
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(curLink)
    if info and info.iconFileID then
      icon = info.iconFileID
    end
  end
  local clean = StripReceivePrefix(msg)
  return {
    kind = "currency",
    icon = icon or 463446,
    title = "You received",
    text = clean or curLink,
    linkColor = curLink:match("|c(%x%x%x%x%x%x%x%x)"),
    tooltipLink = curLink,
    style = TOAST_STYLE_CURRENCY,
    count = 1,
  }
end

StripReceivePrefix = function(msg)
  if not msg or msg == "" then return msg end
  local clean = msg
  clean = clean:gsub("^%s*You%s+receive%s+currency:%s*", "")
  clean = clean:gsub("^%s*You%s+receive%s+loot:%s*", "")
  clean = clean:gsub("^%s*You%s+receive%s+", "")
  clean = clean:gsub("^%s*You%s+loot:%s*", "")
  clean = clean:gsub("^%s*You%s+loot%s+", "")
  clean = clean:gsub("^%s*Received%s+", "")
  return clean
end

local function FindToastByItem(itemID, link)
  local normalizedLink = NormalizeItemLink(link)
  if normalizedLink then
    for _, t in ipairs(state.active) do
      if t._huiItemLink == normalizedLink or t._huiTooltipLink == normalizedLink then
        return t
      end
    end
  end
  local id = itemID and tonumber(itemID) or nil
  if id then
    for _, t in ipairs(state.active) do
      if t._huiItemID == id then
        return t
      end
    end
  end
  return nil
end

local function ApplyPayloadToToast(toast, payload)
  if not toast or not payload then return end
  local db = NS:GetDB()
  toast._huiIsFading = nil
  toast:SetAlpha(1)
  if toast.outroAnim then
    toast.outroAnim:Stop()
  end
  ApplyToastLayout(toast, db.loot)
  toast:SetScale(db.loot.scale or 1.0)
  ApplyToastFont(toast.title, 12)
  ApplyToastFont(toast.text, 12)
  ApplyToastFont(toast.countText, 12)
  toast.icon:SetTexture(payload.icon or 134400)
  toast.title:SetText(payload.title or "You received")
  toast.text:SetText(payload.text or "Loot")
  toast._huiItemID = payload.itemID and tonumber(payload.itemID) or nil
  toast._huiItemLink = payload.itemLink
  toast._huiTooltipLink = payload.tooltipLink or payload.itemLink
  toast._huiItemName = payload.itemName
  toast._huiCount = payload.count or 1
  toast._huiQuality = payload.quality
  toast._huiItemStyle = payload.style
  ApplyToastStyle(toast, payload)
end

local function ShowToast(payload, durationOverride)
  local db = NS:GetDB()
  if not db or not db.loot or not db.loot.enabled then
    return nil
  end
  local toast = AcquireToast()
  ApplyPayloadToToast(toast, payload)
  table.insert(state.active, 1, toast)
  EnforceMaxToasts(db.loot.maxToasts or 4)
  LayoutToasts()
  toast:Show()
  if payload.kind == "item" or payload.kind == "currency" then
    toast:SetScript("OnUpdate", function(self)
      if not self.iconFrame or not self.iconFrame.IsMouseOver then return end
      if self.iconFrame:IsMouseOver() then
        if not (GameTooltip and GameTooltip:IsOwned(self.iconFrame) and GameTooltip:IsShown()) then
          ShowItemTooltip(self.iconFrame, self)
        end
      elseif GameTooltip and GameTooltip:IsOwned(self.iconFrame) then
        GameTooltip:Hide()
      end
    end)
  else
    toast:SetScript("OnUpdate", nil)
  end
  PlayToastIntro(toast, payload)
  if db.loot.playSound then
    PlaySound(payload.soundID or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end
  RefreshToastTimer(toast, durationOverride)
  return toast
end

local function UpsertItemToast(payload, mergeCount)
  if not payload then return nil end
  local existing = FindToastByItem(payload.itemID, payload.itemLink)
  if existing then
    if mergeCount then
      payload.count = (existing._huiCount or 1) + (payload.count or 1)
    else
      payload.count = math.max(existing._huiCount or 1, payload.count or 1)
    end
    ApplyPayloadToToast(existing, payload)
    LayoutToasts()
    PlayToastIntro(existing, payload)
    RefreshToastTimer(existing)
    return existing
  end
  return ShowToast(payload)
end

local function OnLootWithRetries(msg, attempt)
  local db = NS:GetDB()
  if not db.loot.showItems then return end
  local link, count = ParseLootChatItem(msg)
  local payload = BuildItemPayload(link, count, {})
  if payload and payload.icon and payload.icon ~= 134400 then
    UpsertItemToast(payload, true)
    return
  end
  if attempt >= 3 then return end
  if link then
    C_Timer.After(1.5, function()
      OnLootWithRetries(msg, attempt + 1)
    end)
  end
end

local function OnSpecialLootWithRetries(link, quantity, attempt, opts)
  local db = NS:GetDB()
  if not db.loot.showItems then return end
  local payload = BuildItemPayload(link, quantity, opts)
  if payload and payload.icon and payload.icon ~= 134400 then
    UpsertItemToast(payload, false)
    return
  end
  if attempt >= 3 then return end
  if link then
    C_Timer.After(1.0, function()
      OnSpecialLootWithRetries(link, quantity, attempt + 1, opts)
    end)
  end
end

local function OnMoney(msg)
  local db = NS:GetDB()
  if not db.loot.showMoney then return end
  if not msg or msg == "" then return end
  ShowToast(BuildMoneyPayload(msg))
end

local function OnCurrency(msg)
  local db = NS:GetDB()
  if not db.loot.showCurrency then return end
  if not msg or msg == "" then return end
  local payload = BuildCurrencyPayload(msg)
  if payload then
    ShowToast(payload)
  end
end

local function HandleSpecialItemLoot(link, quantity, opts)
  if not link then return end
  OnSpecialLootWithRetries(link, quantity or 1, 1, opts or {})
end

local function IsPlayerLootEvent(guid)
  if guid == nil then
    return true
  end
  if issecretvalue and issecretvalue(guid) then
    return false
  end
  return not PLAYER_GUID or guid == PLAYER_GUID
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.loot or not db.loot.enabled then
    self:Disable()
    return
  end
  M.active = true

  if not state.eventFrame then
    state.eventFrame = CreateFrame("Frame")
    state.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    state.eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    state.eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    state.eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
    state.eventFrame:RegisterEvent("LOOT_ITEM_ROLL_WON")
    state.eventFrame:RegisterEvent("SHOW_LOOT_TOAST")
    state.eventFrame:RegisterEvent("SHOW_PVP_FACTION_LOOT_TOAST")
    state.eventFrame:RegisterEvent("SHOW_RATED_PVP_REWARD_TOAST")
    state.eventFrame:RegisterEvent("SHOW_LOOT_TOAST_LEGENDARY_LOOTED")
    state.eventFrame:RegisterEvent("SHOW_LOOT_TOAST_UPGRADE")
    state.eventFrame:SetScript("OnEvent", function(_, event, ...)
      if not M.active then return end
      if event == "PLAYER_ENTERING_WORLD" then
        PLAYER_GUID = UnitGUID and UnitGUID("player") or PLAYER_GUID
        DelayedUpdateLootPatterns()
      elseif event == "CHAT_MSG_LOOT" then
        local msg, _, _, _, _, _, _, _, _, _, _, guid = ...
        if issecretvalue and issecretvalue(msg) then
          msg = tostring(msg)
        end
        if not IsPlayerLootEvent(guid) then
          return
        end
        C_Timer.After(0.3, function()
          OnLootWithRetries(msg, 1)
        end)
      elseif event == "CHAT_MSG_MONEY" then
        local msg = ...
        if issecretvalue and issecretvalue(msg) then
          msg = tostring(msg)
        end
        OnMoney(msg)
      elseif event == "CHAT_MSG_CURRENCY" then
        local msg = ...
        if issecretvalue and issecretvalue(msg) then
          msg = tostring(msg)
        end
        OnCurrency(msg)
      elseif event == "LOOT_ITEM_ROLL_WON" then
        local link, quantity, _, _, isUpgraded = ...
        HandleSpecialItemLoot(link, quantity, { isUpgraded = isUpgraded == true })
      elseif event == "SHOW_LOOT_TOAST" then
        local typeID, link, quantity, _, _, _, _, _, isUpgraded, isCorrupted = ...
        if typeID == "item" and link then
          HandleSpecialItemLoot(link, quantity, {
            isUpgraded = isUpgraded == true,
            isCorrupted = isCorrupted == true,
          })
        end
      elseif event == "SHOW_PVP_FACTION_LOOT_TOAST" or event == "SHOW_RATED_PVP_REWARD_TOAST" then
        local typeID, link, quantity = ...
        if typeID == "item" and link then
          HandleSpecialItemLoot(link, quantity)
        end
      elseif event == "SHOW_LOOT_TOAST_LEGENDARY_LOOTED" then
        local link = ...
        HandleSpecialItemLoot(link, 1, { isLegendary = true })
      elseif event == "SHOW_LOOT_TOAST_UPGRADE" then
        local link, quantity, _, _, baseQuality = ...
        if link then
          HandleSpecialItemLoot(link, quantity, {
            isUpgraded = true,
            baseQuality = tonumber(baseQuality),
          })
        end
      end
    end)
  end

  UpdateLootPatterns()
  for _, t in ipairs(state.active) do
    ApplyToastLayout(t, db.loot)
    t:SetScale(db.loot.scale or 1.0)
  end
  M:SetLocked(db.general.framesLocked)
  LayoutToasts()
end

function M:SetLocked(locked)
  if not M.active then return end
  local anchor = EnsureAnchor()
  if locked then
    anchor._huiMover:Hide()
    anchor:Hide()
  else
    anchor:Show()
    anchor._huiMover:Show()
  end
end

function M:Preview()
  local db = NS:GetDB()
  if not db or not db.loot.enabled then return end
  self._previewUntil = GetTime() + 10
  local function PreviewToast(payload)
    ShowToast(payload, 10)
  end

  PreviewToast({
    kind = "money",
    icon = 133784,
    title = "You received",
    text = "827 Gold, 14 Silver",
    style = TOAST_STYLE_MONEY,
    count = 1,
  })
  PreviewToast({
    kind = "currency",
    icon = 463446,
    title = "You received",
    text = "58 Resonance Crystals",
    style = TOAST_STYLE_CURRENCY,
    count = 1,
  })
  PreviewToast({
    kind = "item",
    icon = 6098119,
    title = "You received",
    text = BuildItemText("Weathered Adventurer's Helm", 2, 584),
    quality = 2,
    count = 1,
    itemName = "Weathered Adventurer's Helm",
  })
  PreviewToast({
    kind = "item",
    icon = 6098119,
    title = "Epic Upgrade",
    text = BuildItemText("Champion's Storm-Singed Greathelm", 4, 619),
    quality = 4,
    count = 1,
    itemName = "Champion's Storm-Singed Greathelm",
    style = TOAST_STYLE_UPGRADE,
    isUpgraded = true,
  })
  PreviewToast({
    kind = "item",
    icon = 5779387,
    title = "Legendary Item",
    text = BuildItemText("Voice of the Silent Star", 5, 639),
    quality = 5,
    count = 1,
    itemName = "Voice of the Silent Star",
    style = TOAST_STYLE_LEGENDARY,
  })
end

function M:Disable()
  M.active = false
  if state.eventFrame then
    state.eventFrame:UnregisterAllEvents()
    state.eventFrame:SetScript("OnEvent", nil)
    state.eventFrame = nil
  end
  for i = #state.active, 1, -1 do
    ReleaseToast(state.active[i])
    table.remove(state.active, i)
  end
  for toast, timer in pairs(state.toastTimers) do
    if timer and timer.Cancel then timer:Cancel() end
    state.toastTimers[toast] = nil
  end
  if state.anchorFrame then
    state.anchorFrame:Hide()
  end
end
