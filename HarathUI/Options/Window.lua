local ADDON, NS = ...

local Theme = NS.OptionsTheme or {}
local Widgets = NS.OptionsWidgets or {}
local ORANGE = Theme.ORANGE
local ORANGE_SIZE = Theme.ORANGE_SIZE
local RegisterTheme = Theme.RegisterTheme
local ApplyUIFont = Theme.ApplyUIFont
local SetUIFont = Theme.SetUIFont
local ApplyDarkBackdrop = Widgets.ApplyDarkBackdrop
local Title = Widgets.Title
local Small = Widgets.Small
local MakeButton = Widgets.MakeButton

function NS:BuildOptionsWindow(BuildFullUI, db)
  -- =========================================================
  -- POPOUT WINDOW
  -- =========================================================
  local window = CreateFrame("Frame", "HaraUIOptionsWindow", UIParent, "BackdropTemplate")
  window:SetSize(720, 620)
  window:SetPoint("CENTER")
  window:Hide()
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:SetToplevel(true)
  window:SetFrameStrata("FULLSCREEN_DIALOG")
  window:SetFrameLevel(100)

  local titleBar = CreateFrame("Frame", nil, window)
  titleBar:SetPoint("TOPLEFT", 8, -6)
  titleBar:SetPoint("TOPRIGHT", -40, -6)
  titleBar:SetHeight(28)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() window:StartMoving() end)
  titleBar:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

  local icon = window:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("LEFT", titleBar, "LEFT", 4, 0)
  icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

  local close = CreateFrame("Button", nil, window)
  close:SetPoint("TOPRIGHT", -10, -10)
  close:SetSize(28, 28)
  close:SetFrameStrata("FULLSCREEN_DIALOG")
  close:SetFrameLevel(window:GetFrameLevel() + 5)
  window.closeButton = close

  close.bg = close:CreateTexture(nil, "BACKGROUND")
  close.bg:SetAllPoints(true)
  close.bg:SetColorTexture(0.08, 0.08, 0.09, 0.95)

  close.border = close:CreateTexture(nil, "ARTWORK")
  close.border:SetAllPoints(true)

  close.glow = close:CreateTexture(nil, "OVERLAY")
  close.glow:SetAllPoints(true)
  close.glow:SetBlendMode("ADD")
  close.glow:Hide()

  close.diag = close:CreateTexture(nil, "OVERLAY")
  close.diag:SetSize(12, 2)
  close.diag:SetPoint("CENTER", 0, 0)
  close.diag:SetTexture("Interface/Buttons/WHITE8x8")
  close.diag:SetRotation(math.rad(45))
  close.diag:Hide()

  close.x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  close.x:SetPoint("CENTER", 0, 0)
  close.x:SetText("X")
  ApplyUIFont(close.x, ORANGE_SIZE, "OUTLINE", ORANGE)

  function close:ApplyStyle(style)
    self._style = style or self._style or "round"
    local s = self._style
    self.glow:Hide()
    self.diag:Hide()
    self.bg:SetAlpha(1)

    if s == "round" then
      self:SetSize(30, 30)
      self.bg:SetColorTexture(0.08, 0.08, 0.09, 0.95)
      self.border:SetTexture("Interface\\AddOns\\HarathUI\\Media\\thin_round_border.tga")
      self.border:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
      self.glow:SetTexture("Interface\\AddOns\\HarathUI\\Media\\thin_round_border.tga")
      self.glow:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.4)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "angled" then
      self:SetSize(30, 26)
      self.bg:SetColorTexture(0.09, 0.09, 0.11, 0.95)
      self.border:SetTexture("Interface/Buttons/WHITE8x8")
      self.border:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
      self.border:SetAllPoints(true)
      self.diag:Show()
      self.diag:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "minimal" then
      self:SetSize(24, 24)
      self.bg:SetAlpha(0)
      self.border:SetTexture(nil)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "bigx" then
      self:SetSize(34, 34)
      self.bg:SetAlpha(0)
      self.border:SetTexture(nil)
      self.x:SetText("X")
      ApplyUIFont(self.x, ORANGE_SIZE + 6, "OUTLINE", ORANGE)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "double" then
      self:SetSize(30, 30)
      self.bg:SetColorTexture(0.07, 0.07, 0.08, 0.95)
      self.border:SetTexture("Interface\\AddOns\\HarathUI\\Media\\thin_round_border.tga")
      self.border:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
      self.glow:SetTexture("Interface\\AddOns\\HarathUI\\Media\\thin_round_border.tga")
      self.glow:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.65)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "pill" then
      self:SetSize(36, 20)
      self.bg:SetColorTexture(0.08, 0.08, 0.1, 0.95)
      self.border:SetTexture("Interface/Buttons/WHITE8x8")
      self.border:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
      self.diag:Show()
      self.diag:SetRotation(math.rad(0))
      self.diag:SetSize(10, 2)
      self.diag:SetPoint("RIGHT", -6, 0)
      self.diag:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "cut" then
      self:SetSize(30, 26)
      self.bg:SetColorTexture(0.09, 0.09, 0.11, 0.95)
      self.border:SetTexture("Interface/Buttons/WHITE8x8")
      self.border:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.6)
      self.diag:Show()
      self.diag:SetRotation(math.rad(45))
      self.diag:SetSize(12, 2)
      self.diag:SetPoint("TOPRIGHT", -6, -6)
      self.diag:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "crosshair" then
      self:SetSize(26, 26)
      self.bg:SetAlpha(0)
      self.border:SetTexture(nil)
      self.diag:Show()
      self.diag:SetRotation(math.rad(0))
      self.diag:SetSize(14, 2)
      self.diag:SetPoint("CENTER", 0, 0)
      self.diag:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif s == "slash" then
      self:SetSize(28, 28)
      self.bg:SetColorTexture(0.08, 0.08, 0.1, 0.95)
      self.border:SetTexture("Interface/Buttons/WHITE8x8")
      self.border:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.5)
      self.diag:Show()
      self.diag:SetRotation(math.rad(55))
      self.diag:SetSize(16, 2)
      self.diag:SetPoint("CENTER", 0, 0)
      self.diag:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    end
  end

  close:SetScript("OnEnter", function(self)
    if self._style == "minimal" then
      self.x:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
      return
    end
    self.glow:Show()
  end)
  close:SetScript("OnLeave", function(self)
    self.glow:Hide()
  end)
  close:SetScript("OnClick", function()
    window:Hide()
  end)
  close:SetScript("OnMouseDown", function(self, button)
    if button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
      local styles = { "round", "angled", "minimal", "bigx", "double", "pill", "cut", "crosshair", "slash" }
      local cur = self._style or "round"
      local idx = 1
      for i, v in ipairs(styles) do
        if v == cur then idx = i break end
      end
      local nextStyle = styles[(idx % #styles) + 1]
      if db and db.general then db.general.closeStyle = nextStyle end
      self:ApplyStyle(nextStyle)
    end
  end)

  close:ApplyStyle((db and db.general and db.general.closeStyle) or "round")
  RegisterTheme(function()
    if close and close.ApplyStyle then
      close:ApplyStyle(close._style)
    end
  end)

  BuildFullUI(window)
  NS.OptionsWindow = window
  function NS:RefreshOptionsFonts()
    if not NS._huiFontRegistry then return end
    for fs, meta in pairs(NS._huiFontRegistry) do
      if fs and fs.SetFont then
        SetUIFont(fs, meta.size, nil, meta.color)
      end
    end
  end
  function NS:OpenOptionsWindow()
    window:Show()
    window:Raise()
    if SettingsPanel then SettingsPanel:Hide() end
    if SettingsFrame then SettingsFrame:Hide() end
    if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
    if GameMenuFrame then GameMenuFrame:Hide() end
  end
  window:EnableKeyboard(true)
  window:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      window:Hide()
      if GameMenuFrame then GameMenuFrame:Hide() end
      self:SetPropagateKeyboardInput(false)
    else
      -- Allow all other keys (slash, enter, etc.) to pass through to chat
      self:SetPropagateKeyboardInput(true)
    end
  end)
  tinsert(UISpecialFrames, "HaraUIOptionsWindow")

  -- =========================================================
  -- BLIZZARD SETTINGS INTEGRATION (Minimal Panel)
  -- =========================================================
  local panel = CreateFrame("Frame", ADDON .. "OptionsPanel", UIParent)
  panel.name = "HaraUI"
  ApplyDarkBackdrop(panel)

  local header = Title(panel, "HaraUI")
  header:SetPoint("TOPLEFT", 22, -18)

  local sub = Small(panel, "Open the HaraUI window for full settings.\nSlash: /hui")
  sub:SetPoint("TOPLEFT", 22, -44)
  sub:SetWidth(760)

  local openBtn = MakeButton(panel, "Open HaraUI Window", 200, 26)
  openBtn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
  openBtn:SetScript("OnClick", function()
    if NS.OpenOptionsWindow then NS:OpenOptionsWindow() end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    local categoryID = category:GetID()
    function NS:OpenOptions()
      if NS.OpenOptionsWindow then
        NS:OpenOptionsWindow()
      else
        Settings.OpenToCategory(categoryID)
      end
    end
  else
    function NS:OpenOptions()
      if NS.OpenOptionsWindow then
        NS:OpenOptionsWindow()
      elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
      end
    end
  end
end
