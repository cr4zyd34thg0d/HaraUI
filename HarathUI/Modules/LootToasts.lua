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
  pendingIcons = nil,
  toastTimers = {},
  eventFrame = nil,
}
local ShowItemTooltip

-- Parser
local function ResolveToastItemData(toast)
  if not toast then return nil, nil end
  local itemID = toast._huiItemID
  local itemLink = toast._huiItemLink
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

local function ApplyToastFont(fontString, size)
  if not fontString then return end
  NS:ApplyDefaultFont(fontString, size)
end

local function ApplyToastLayout(t, db)
  if not t or not db then return end
  local w = 340
  local h = 52
  t:SetSize(w, h)

  -- Icon block mirrors LS sizing.
  t.iconFrame:SetSize(40, 40)
  t.icon:SetSize(40, 40)

  local iconOffset = 5
  local minIconOffset = 6
  local maxIconOffset = math.max(minIconOffset, w - 40 - 6)
  iconOffset = math.min(math.max(iconOffset, minIconOffset), maxIconOffset)
  local leftPad = 62
  local rightPad = 8
  t.iconFrame:ClearAllPoints()
  t.iconFrame:SetPoint("LEFT", t, "LEFT", iconOffset, 0)
  local textAreaLeft = iconOffset + 40 + 6
  local textAreaRight = 6
  local textAreaWidth = math.max(120, w - textAreaLeft - textAreaRight)
  local textCenterX = (textAreaLeft + (w - textAreaRight)) / 2

  t.title:ClearAllPoints()
  t.title:SetPoint("TOP", t, "TOP", textCenterX - (w / 2), -6)
  t.title:SetWidth(textAreaWidth)
  t.text:ClearAllPoints()
  t.text:SetPoint("BOTTOM", t, "BOTTOM", textCenterX - (w / 2), 6)
  t.text:SetWidth(textAreaWidth)
  t.textBG:ClearAllPoints()
  t.textBG:SetPoint("TOPLEFT", t, "TOPLEFT", textAreaLeft, -10)
  t.textBG:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -textAreaRight, 10)
  if t.bg then t.bg:SetAllPoints(true) end
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
  t:SetSize(280, 32)
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
  t.bg:SetColorTexture(0.06, 0.06, 0.07, 0.92)

  t.iconFrame = CreateFrame("Frame", nil, t)
  t.iconFrame:SetSize(40, 40)
  t.iconFrame:SetPoint("LEFT", t, "LEFT", 10, 0)
  t.iconFrame:EnableMouse(true)
  if t.iconFrame.SetMouseClickEnabled then t.iconFrame:SetMouseClickEnabled(false) end
  if t.iconFrame.SetMouseMotionEnabled then t.iconFrame:SetMouseMotionEnabled(true) end

  -- No background on icon frame for cleaner look
  t.iconFrame.bg = t.iconFrame:CreateTexture(nil, "BACKGROUND")
  t.iconFrame.bg:SetAllPoints(true)
  t.iconFrame.bg:SetColorTexture(0.06, 0.06, 0.07, 0.92)

  t.icon = t.iconFrame:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(40, 40)
  t.icon:SetAllPoints(t.iconFrame)
  -- Match LS-style icon crop.
  t.icon:SetTexCoord(4 / 64, 60 / 64, 4 / 64, 60 / 64)

  -- Pixel-perfect icon rendering
  if t.icon.SetSnapToPixelGrid then
    t.icon:SetSnapToPixelGrid(false)
    t.icon:SetTexelSnappingBias(0)
  end

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
  t.title:SetWidth(200)
  t.title:SetHeight(16)
  t.title:SetJustifyH("CENTER")
  t.title:SetJustifyV("MIDDLE")
  ApplyToastFont(t.title, 12)

  t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.text:SetPoint("BOTTOM", t, "BOTTOM", 0, 6)
  t.text:SetWidth(200)
  t.text:SetHeight(22)
  t.text:SetMaxLines(1)
  t.text:SetJustifyH("CENTER")
  t.text:SetJustifyV("MIDDLE")
  ApplyToastFont(t.text, 12)

  t.textBG = t:CreateTexture(nil, "BACKGROUND", nil, 1)
  t.textBG:SetPoint("TOPLEFT", 62, -12)
  t.textBG:SetPoint("BOTTOMRIGHT", -8, 12)
  t.textBG:SetColorTexture(0, 0, 0, 0.3)

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

  t:Hide()
  return t
end

local function LayoutToasts()
  local db = NS:GetDB()
  local point, x, y = db.loot.anchor, db.loot.x, db.loot.y
  local anchor = EnsureAnchor()
  anchor:ClearAllPoints()
  anchor:SetPoint(point, UIParent, point, x, y)
  for i, t in ipairs(state.active) do
    t:ClearAllPoints()
    t:SetPoint(point, anchor, point, 0, -((i - 1) * 54))
  end
end

-- Timer
local function ReleaseToast(t)
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

local function ApplyToastRarity(toast, quality, hexColor)
  if not toast or not toast.text then return end
  local r, g, b
  if quality ~= nil and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    local c = ITEM_QUALITY_COLORS[quality]
    r, g, b = c.r, c.g, c.b
  elseif hexColor then
    r, g, b = HexToRGB(hexColor)
  end

  if r and g and b then
    if toast.title then
      toast.title:SetTextColor(r, g, b, 1)
    end
    toast.text:SetTextColor(1, 1, 1, 1)
    if toast.border then
      if toast.border.top then toast.border.top:SetColorTexture(r, g, b, 1) end
      if toast.border.bottom then toast.border.bottom:SetColorTexture(r, g, b, 1) end
      if toast.border.left then toast.border.left:SetColorTexture(r, g, b, 1) end
      if toast.border.right then toast.border.right:SetColorTexture(r, g, b, 1) end
    end
    if toast.iconBorder then
      if toast.iconBorder.top then toast.iconBorder.top:SetColorTexture(r, g, b, 1) end
      if toast.iconBorder.bottom then toast.iconBorder.bottom:SetColorTexture(r, g, b, 1) end
      if toast.iconBorder.left then toast.iconBorder.left:SetColorTexture(r, g, b, 1) end
      if toast.iconBorder.right then toast.iconBorder.right:SetColorTexture(r, g, b, 1) end
    end
  else
    if toast.title then
      toast.title:SetTextColor(1, 1, 1, 1)
    end
    toast.text:SetTextColor(1, 1, 1, 1)
    if toast.border then
      if toast.border.top then toast.border.top:SetColorTexture(1, 1, 1, 1) end
      if toast.border.bottom then toast.border.bottom:SetColorTexture(1, 1, 1, 1) end
      if toast.border.left then toast.border.left:SetColorTexture(1, 1, 1, 1) end
      if toast.border.right then toast.border.right:SetColorTexture(1, 1, 1, 1) end
    end
    if toast.iconBorder then
      if toast.iconBorder.top then toast.iconBorder.top:SetColorTexture(1, 1, 1, 1) end
      if toast.iconBorder.bottom then toast.iconBorder.bottom:SetColorTexture(1, 1, 1, 1) end
      if toast.iconBorder.left then toast.iconBorder.left:SetColorTexture(1, 1, 1, 1) end
      if toast.iconBorder.right then toast.iconBorder.right:SetColorTexture(1, 1, 1, 1) end
    end
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

-- Render
local function ShowToast(icon, text, durationOverride, itemID, itemLink, itemName)
  local db = NS:GetDB()
  if not db.loot.enabled then return nil end

  local t = AcquireToast()
  t._huiItemLink = itemLink
  t._huiItemID = itemID and tonumber(itemID) or nil
  t._huiItemName = itemName
  t._huiCount = nil
  ApplyToastLayout(t, db)
  t:SetScale(db.loot.scale or 1.0)
  t.icon:SetTexture(icon or 134400)
  t.title:SetText("You received")
  t.text:SetText(text or "Loot")
  ApplyToastRarity(t, nil, nil)

  -- Apply font settings to toast text
  ApplyToastFont(t.text, 12)

  table.insert(state.active, 1, t)

  LayoutToasts()
  t:Show()
  t:SetScript("OnUpdate", function(self)
    if not self.iconFrame or not self.iconFrame.IsMouseOver then return end
    if self.iconFrame:IsMouseOver() then
      if not (GameTooltip and GameTooltip:IsOwned(self.iconFrame) and GameTooltip:IsShown()) then
        ShowItemTooltip(self.iconFrame, self)
      end
    elseif GameTooltip and GameTooltip:IsOwned(self.iconFrame) then
      GameTooltip:Hide()
    end
  end)

  if db.loot.playSound then
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end

  local duration = durationOverride or db.loot.duration or 3.5
  if state.toastTimers[t] then
    state.toastTimers[t]:Cancel()
  end
  state.toastTimers[t] = C_Timer.NewTimer(duration, function()
    for i = #state.active, 1, -1 do
      if state.active[i] == t then
        table.remove(state.active, i)
        break
      end
    end
    ReleaseToast(t)
    LayoutToasts()
  end)

  return t
end

local function UpdateToastIcon(toast, itemID)
  if not toast or not toast.icon then return end

  local itemName, link, quality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
  if itemTexture then
    toast.icon:SetTexture(itemTexture)
    local linkColor = link and link:match("|c(%x%x%x%x%x%x%x%x)")
    ApplyToastRarity(toast, quality, linkColor)
    return true
  end
  return false
end

local function TryUpdatePending(itemID)
  if not state.pendingIcons then return true end
  local list = state.pendingIcons[itemID]
  if not list then return true end
  local anyUpdated = false
  for i = #list, 1, -1 do
    if UpdateToastIcon(list[i], itemID) then
      anyUpdated = true
    end
  end
  if anyUpdated then
    state.pendingIcons[itemID] = nil
    return true
  end
  return false
end

local function GetItemIconAndText(msg)
  -- Try to extract the full colored item link first
  local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")

  -- If no colored link found, the message might be in plain format
  -- WoW sometimes strips formatting in certain contexts
  if not link then
    -- Try to match just the item name in brackets and use GetItemInfo by name
    local itemName = msg:match("%[(.-)%]")
    if itemName then
      -- Try to get item info by name
      local _, _, quality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemName)
      if itemTexture then
        local count = msg:match("[xX]([0-9]+)")
        local displayText = count and string.format("[%s] x%s", itemName, count) or string.format("[%s]", itemName)
        return itemTexture, displayText, nil, nil, quality, nil, tonumber(count), itemName
      else
        -- Queue the item to be loaded by name
        GetItemInfo(itemName)
        local count = msg:match("[xX]([0-9]+)")
        local displayText = count and string.format("[%s] x%s", itemName, count) or string.format("[%s]", itemName)
        return 134400, displayText, nil, nil, nil, nil, tonumber(count), itemName
      end
    end

    return nil, nil, nil, nil, nil, nil, nil, nil
  end

  -- We have a full link, extract itemID
  local count = msg:match("[xX]([0-9]+)")
  local icon
  local itemID = link:match("|Hitem:(%d+)")
  local linkColor = link:match("|c(%x%x%x%x%x%x%x%x)")
  local quality
  local itemName

  if itemID then
    itemID = tonumber(itemID)

    -- Try GetItemInfo (works if item is cached)
    itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
    quality = itemQuality
    if itemTexture then
      icon = itemTexture
    else
      -- Queue item to be loaded
      GetItemInfo(itemID)
    end
  end

  -- Final fallback to default icon
  if not icon or icon == 0 then
    icon = 134400
  end

  local displayText
  if count then
    displayText = ("%s |cffffffffx%s|r"):format(link, count)
  else
    displayText = link
  end

  return icon, displayText, itemID, link, quality, linkColor, tonumber(count), itemName
end

local function GetCurrencyIconAndText(msg)
  local curLink = msg:match("(|c%x+|Hcurrency:.-|h%[.-%]|h|r)")
  if not curLink then return nil end
  local icon
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(curLink)
    if info and info.iconFileID then icon = info.iconFileID end
  end
  local linkColor = curLink:match("|c(%x%x%x%x%x%x%x%x)")
  return icon, curLink, linkColor
end

local function StripReceivePrefix(msg)
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
  local id = itemID and tonumber(itemID) or nil
  if id then
    for _, t in ipairs(state.active) do
      if t._huiItemID == id then
        return t
      end
    end
  end
  if not link then return nil end
  for _, t in ipairs(state.active) do
    if t._huiItemLink == link then
      return t
    end
  end
  return nil
end

local function UpdateToastCount(toast, link, count)
  if not toast or not link or not count then return end
  local base = toast._huiCount or 1
  toast._huiCount = base + count
  toast.text:SetText(("%s |cffffffffx%d|r"):format(link, toast._huiCount))

  -- Clean up old timer before creating new one
  if state.toastTimers[toast] then
    state.toastTimers[toast]:Cancel()
    state.toastTimers[toast] = nil
  end
end

local function OnLoot(msg)
  local db = NS:GetDB()
  if not db.loot.showItems then return end
  local icon, text, itemID, itemLink, quality, linkColor, count, itemName = GetItemIconAndText(msg)

  -- Ensure we always have valid icon and text
  if not icon or icon == 0 then
    icon = 134400
  end
  text = text or msg
  if icon == 134400 then
    return
  end

  if itemID or itemLink then
    local existing = FindToastByItem(itemID, itemLink)
    if existing then
      UpdateToastCount(existing, itemLink, count or 1)
      state.toastTimers[existing] = C_Timer.NewTimer(db.loot.duration or 3.5, function()
        for i = #state.active, 1, -1 do
          if state.active[i] == existing then
            table.remove(state.active, i)
            break
          end
        end
        ReleaseToast(existing)
        LayoutToasts()
      end)
      return
    end
  end

  local toast = ShowToast(icon, text, nil, itemID, itemLink, itemName)
  toast._huiCount = count or 1
  ApplyToastRarity(toast, quality, linkColor)
end

local function OnLootWithRetries(msg, attempt)
  OnLoot(msg)
  if attempt >= 3 then return end

  -- If OnLoot dropped due to uncached icon, try again.
  local icon = select(1, GetItemIconAndText(msg))
  if not icon or icon == 0 or icon == 134400 then
    C_Timer.After(1.5, function()
      OnLootWithRetries(msg, attempt + 1)
    end)
  end
end

local function OnSpecialLoot(link, quantity, isUpgraded)
  local db = NS:GetDB()
  if not db.loot.showItems then return end
  local icon, text, itemID, itemLink, quality, linkColor, _, itemName = GetItemIconAndText(link)
  if not icon or icon == 0 or icon == 134400 then return end

  if itemID or itemLink then
    local existing = FindToastByItem(itemID, itemLink)
    if existing then
      UpdateToastCount(existing, itemLink, quantity or 1)
      state.toastTimers[existing] = C_Timer.NewTimer(db.loot.duration or 3.5, function()
        for i = #state.active, 1, -1 do
          if state.active[i] == existing then
            table.remove(state.active, i)
            break
          end
        end
        ReleaseToast(existing)
        LayoutToasts()
      end)
      return
    end
  end

  local toast = ShowToast(icon, text, nil, itemID, itemLink, itemName)
  toast._huiCount = quantity or 1
  if toast then
    if isUpgraded then
      toast.title:SetText("Item Upgraded")
    elseif quality == 5 then
      toast.title:SetText("Item Legendary")
    else
      toast.title:SetText("You received")
    end
    ApplyToastRarity(toast, quality, linkColor)
  end
end

local function OnMoney(msg)
  local db = NS:GetDB()
  if not db.loot.showMoney then return end
  if not msg or msg == "" then return end
  local clean = StripReceivePrefix(msg)
  if not clean or clean == "" then
    clean = msg
  end
  ShowToast(133784, clean)
end

local function OnCurrency(msg)
  local db = NS:GetDB()
  if not db.loot.showCurrency then return end
  if not msg or msg == "" then return end
  local icon, text, linkColor = GetCurrencyIconAndText(msg)
  local clean = StripReceivePrefix(msg)
  local toast = ShowToast(icon or 463446, text or clean or msg)
  ApplyToastRarity(toast, nil, linkColor)
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
    state.eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    state.eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    state.eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
    state.eventFrame:RegisterEvent("SHOW_LOOT_TOAST")
    state.eventFrame:RegisterEvent("SHOW_LOOT_TOAST_UPGRADE")
    -- No GET_ITEM_INFO_RECEIVED handling; we drop uncached items like ls_Toasts.
    state.eventFrame:SetScript("OnEvent", function(_, event, ...)
      if not M.active then return end
      if event == "CHAT_MSG_LOOT" then
        local msg = ...
        C_Timer.After(0.3, function()
          OnLootWithRetries(msg, 1)
        end)
      elseif event == "CHAT_MSG_MONEY" then
        OnMoney(...)
      elseif event == "CHAT_MSG_CURRENCY" then
        OnCurrency(...)
      elseif event == "SHOW_LOOT_TOAST" then
        local typeID, link, quantity, _, _, _, _, _, isUpgraded = ...
        if typeID == "item" and link then
          OnSpecialLoot(link, quantity or 1, isUpgraded)
        end
      elseif event == "SHOW_LOOT_TOAST_UPGRADE" then
        local link, quantity = ...
        if link then
          OnSpecialLoot(link, quantity or 1, true)
        end
      end
    end)
  end

  for _, t in ipairs(state.active) do
    ApplyToastLayout(t, db)
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
  self._previewUntil = GetTime() + 20
  local function PreviewToast(icon, text, title, quality)
    local toast = ShowToast(icon, text, 20)
    if toast then
      toast.title:SetText(title or "You received")
      ApplyToastRarity(toast, quality, nil)
    end
  end

  PreviewToast(133784, "Loot Preview Money", "You received", nil)
  PreviewToast(134400, "Loot Preview Item", "You received", 1)
  PreviewToast(134400, "Loot Preview Item", "Uncommon Gear", 2)
  PreviewToast(134400, "Loot Preview Item", "Uncommon Upgrade", 2)
  PreviewToast(134400, "Loot Preview Item", "Rare Gear", 3)
  PreviewToast(134400, "Loot Preview Item", "Rare Upgrade", 3)
  PreviewToast(134400, "Loot Preview Item", "Epic Gear", 4)
  PreviewToast(134400, "Loot Preview Item", "Epic Upgrade", 4)
  PreviewToast(134400, "Loot Preview Item", "Legendary Gear", 5)
  PreviewToast(134400, "Loot Preview Item", "Legendary Upgrade", 5)
  PreviewToast(134400, "Loot Preview Item", "Achievement Earned", nil)
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
