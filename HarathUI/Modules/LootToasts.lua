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

local pool, active = {}, {}
local anchorFrame
local pendingIcons = nil
local toastTimers = {}

local function ApplyToastFont(fontString, size)
  if not fontString then return end
  local db = NS:GetDB()
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local fontName = (db and db.loot and db.loot.font) or NS.DEFAULT_FONT
  local outline = (db and db.loot and db.loot.fontOutline) or "NONE"
  if outline == "NONE" then outline = "" end

  local path = LSM and LSM:Fetch("font", fontName, true) or STANDARD_TEXT_FONT
  if path then
    fontString:SetFont(path, size or 12, outline)
  end
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
  if anchorFrame then return anchorFrame end
  anchorFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  anchorFrame:SetSize(24, 24)
  anchorFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -220)
  anchorFrame:Hide()

  anchorFrame.tex = anchorFrame:CreateTexture(nil, "OVERLAY")
  anchorFrame.tex:SetAllPoints(true)
  anchorFrame.tex:SetColorTexture(1, 1, 1, 0.08)

  anchorFrame.label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  anchorFrame.label:SetPoint("CENTER")
  anchorFrame.label:SetText("Loot")
  ApplyToastFont(anchorFrame.label, 12)

  NS:MakeMovable(anchorFrame, "loot", "Loot Toasts (drag)")
  return anchorFrame
end

local function AcquireToast()
  local t = table.remove(pool)
  if t then return t end

  t = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  t:SetSize(280, 32)

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
  for i, t in ipairs(active) do
    t:ClearAllPoints()
    t:SetPoint(point, anchor, point, 0, -((i - 1) * 54))
  end
end

local function ReleaseToast(t)
  t:Hide()
  if toastTimers[t] then
    toastTimers[t]:Cancel()
    toastTimers[t] = nil
  end
  table.insert(pool, t)
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

local function ShowToast(icon, text, durationOverride)
  local db = NS:GetDB()
  if not db.loot.enabled then return nil end

  local t = AcquireToast()
  ApplyToastLayout(t, db)
  t:SetScale(db.loot.scale or 1.0)
  t.icon:SetTexture(icon or 134400)
  t.title:SetText("You received")
  t.text:SetText(text or "Loot")
  ApplyToastRarity(t, nil, nil)

  -- Apply font settings to toast text
  ApplyToastFont(t.text, 12)

  table.insert(active, 1, t)

  LayoutToasts()
  t:Show()

  if db.loot.playSound then
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end

  local duration = durationOverride or db.loot.duration or 3.5
  if toastTimers[t] then
    toastTimers[t]:Cancel()
  end
  toastTimers[t] = C_Timer.NewTimer(duration, function()
    for i = #active, 1, -1 do
      if active[i] == t then
        table.remove(active, i)
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
  if not pendingIcons then return true end
  local list = pendingIcons[itemID]
  if not list then return true end
  local anyUpdated = false
  for i = #list, 1, -1 do
    if UpdateToastIcon(list[i], itemID) then
      anyUpdated = true
    end
  end
  if anyUpdated then
    pendingIcons[itemID] = nil
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
        return itemTexture, displayText, nil, nil, quality, nil
      else
        -- Queue the item to be loaded by name
        GetItemInfo(itemName)
        local count = msg:match("[xX]([0-9]+)")
        local displayText = count and string.format("[%s] x%s", itemName, count) or string.format("[%s]", itemName)
        return 134400, displayText, nil, nil, nil, nil
      end
    end

    return nil, nil, nil, nil, nil, nil, nil
  end

  -- We have a full link, extract itemID
  local count = msg:match("[xX]([0-9]+)")
  local icon
  local itemID = link:match("|Hitem:(%d+)")
  local linkColor = link:match("|c(%x%x%x%x%x%x%x%x)")
  local quality

  if itemID then
    itemID = tonumber(itemID)

    -- Try GetItemInfo (works if item is cached)
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
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

  return icon, displayText, itemID, link, quality, linkColor, tonumber(count)
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

local function FindToastByItem(itemID, link)
  local id = itemID and tonumber(itemID) or nil
  if id then
    for _, t in ipairs(active) do
      if t._huiItemID == id then
        return t
      end
    end
  end
  if not link then return nil end
  for _, t in ipairs(active) do
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
  if toastTimers[toast] then
    toastTimers[toast]:Cancel()
    toastTimers[toast] = nil
  end
end

local function OnLoot(msg)
  local db = NS:GetDB()
  if not db.loot.showItems then return end
  local icon, text, itemID, itemLink, quality, linkColor, count = GetItemIconAndText(msg)

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
      toastTimers[existing] = C_Timer.NewTimer(db.loot.duration or 3.5, function()
        for i = #active, 1, -1 do
          if active[i] == existing then
            table.remove(active, i)
            break
          end
        end
        ReleaseToast(existing)
        LayoutToasts()
      end)
      return
    end
  end

  local toast = ShowToast(icon, text)
  toast._huiItemLink = itemLink
  toast._huiItemID = itemID and tonumber(itemID) or nil
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
  local icon, text, itemID, itemLink, quality, linkColor = GetItemIconAndText(link)
  if not icon or icon == 0 or icon == 134400 then return end

  if itemID or itemLink then
    local existing = FindToastByItem(itemID, itemLink)
    if existing then
      UpdateToastCount(existing, itemLink, quantity or 1)
      toastTimers[existing] = C_Timer.NewTimer(db.loot.duration or 3.5, function()
        for i = #active, 1, -1 do
          if active[i] == existing then
            table.remove(active, i)
            break
          end
        end
        ReleaseToast(existing)
        LayoutToasts()
      end)
      return
    end
  end

  local toast = ShowToast(icon, text)
  toast._huiItemLink = itemLink
  toast._huiItemID = itemID and tonumber(itemID) or nil
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
  local clean = msg:gsub("^%s*You%s+loot%s+", "")
  ShowToast(133784, clean)
end

local function OnCurrency(msg)
  local db = NS:GetDB()
  if not db.loot.showCurrency then return end
  if not msg or msg == "" then return end
  local icon, text, linkColor = GetCurrencyIconAndText(msg)
  local toast = ShowToast(icon or 463446, text or msg)
  ApplyToastRarity(toast, nil, linkColor)
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.loot or not db.loot.enabled then
    self:Disable()
    return
  end
  M.active = true

  if not M.eventFrame then
    M.eventFrame = CreateFrame("Frame")
    M.eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    M.eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    M.eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
    M.eventFrame:RegisterEvent("SHOW_LOOT_TOAST")
    M.eventFrame:RegisterEvent("SHOW_LOOT_TOAST_UPGRADE")
    -- No GET_ITEM_INFO_RECEIVED handling; we drop uncached items like ls_Toasts.
    M.eventFrame:SetScript("OnEvent", function(_, event, ...)
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

  for _, t in ipairs(active) do
    ApplyToastLayout(t, db)
    t:SetScale(db.loot.scale or 1.0)
  end
  M:SetLocked(db.general.framesLocked)
  LayoutToasts()
end

function M:SetLocked(locked)
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
  if M.eventFrame then
    M.eventFrame:UnregisterAllEvents()
    M.eventFrame:SetScript("OnEvent", nil)
    M.eventFrame = nil
  end
  for i = #active, 1, -1 do
    ReleaseToast(active[i])
    table.remove(active, i)
  end
  for toast, timer in pairs(toastTimers) do
    if timer and timer.Cancel then timer:Cancel() end
    toastTimers[toast] = nil
  end
  if anchorFrame then
    anchorFrame:Hide()
  end
end
