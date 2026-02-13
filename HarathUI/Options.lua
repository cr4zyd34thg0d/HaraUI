--[[
  HarathUI Options Panel

  Structure:
    - Theme System & UI Helpers (lines 16-364)
    - Options Panel Initialization (lines 370+)
      - General Page
      - XP/Rep Bar Page
      - Cast Bar Page
      - Loot Toasts Page
      - Friendly Nameplates Page
      - Rotation Helper Page
      - Minimap Bar Page
      - Game Menu Page
--]]

local ADDON, NS = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local function GetAddonMetadataField(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, field)
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, field)
  end
  return nil
end

local function GetVersionStatus(info)
  if NS and NS.GetVersionStatus then
    return NS.GetVersionStatus(info)
  end
  if type(info) ~= "table" then return "unknown" end
  local cmp = info.cmp
  if cmp ~= nil then
    if cmp < 0 then return "out-of-date" end
    if cmp > 0 then return "ahead" end
    if cmp == 0 then return "up-to-date" end
  end
  return "unknown"
end

local function GetVersionInfo()
  if NS and NS.GetVersionInfo then
    return NS.GetVersionInfo()
  end
  local installed = GetAddonMetadataField("Version")
  local latest = installed
  local cmp = nil
  local status = GetVersionStatus({
    cmp = cmp,
  })
  return {
    installed = installed,
    latest = latest,
    cmp = cmp,
    status = status,
    source = "local-metadata",
    authoritative = false,
  }
end

local ORANGE = { 0.949, 0.431, 0.031 } -- #F26E08
local ORANGE_SIZE = 11
local CHECKBOX_GAP = -2
local CAST_CHECKBOX_GAP = CHECKBOX_GAP
-- Layout constants (global defaults)
local FIRST_CONTROL_Y = -128        -- First control below Enable Module
local GROUP_GAP = -48               -- Between major groups
local BUTTON_TO_SLIDER_GAP = GROUP_GAP
local SLIDER_GAP = -18              -- Between stacked sliders
local SLIDER_TO_CHECKBOX_GAP = GROUP_GAP
local DROPDOWN_GAP = -10            -- Between dropdown groups

-- =========================================================
-- Theme System
-- =========================================================

local function RegisterTheme(fn)
  NS._huiThemeRegistry = NS._huiThemeRegistry or {}
  table.insert(NS._huiThemeRegistry, fn)
end

local function ApplyThemeToRegistry()
  if not NS._huiThemeRegistry then return end
  for _, fn in ipairs(NS._huiThemeRegistry) do
    if type(fn) == "function" then fn(ORANGE) end
  end
end

local function SetThemeColor(r, g, b)
  ORANGE[1] = r or ORANGE[1]
  ORANGE[2] = g or ORANGE[2]
  ORANGE[3] = b or ORANGE[3]
  ApplyThemeToRegistry()
end

-- =========================================================
-- Font Utilities
-- =========================================================

local function GetUIFontPath()
  -- Settings UI font is fixed to Tahoma Bold; module-specific font selectors remain independent.
  local fontName = "Tahoma Bold"
  if LSM then
    local path = LSM:Fetch("font", fontName, true)
    if path then return path end
  end
  return STANDARD_TEXT_FONT
end

local function SetUIFont(fs, size, outline, color)
  if not fs then return end
  local path = GetUIFontPath()
  if path then
    fs:SetFont(path, size or 12, outline or "")
  end
  if color then
    fs:SetTextColor(color[1], color[2], color[3])
  end
end

local function ApplyUIFont(fs, size, outline, color)
  if not fs then return end
  SetUIFont(fs, size, outline, color)
  -- Track font objects so the Settings Font dropdown can update existing UI text.
  NS._huiFontRegistry = NS._huiFontRegistry or {}
  NS._huiFontRegistry[fs] = { size = size, outline = outline, color = color }
  if color == ORANGE then
    RegisterTheme(function(c)
      if fs and fs.SetTextColor then
        fs:SetTextColor(c[1], c[2], c[3])
      end
    end)
  end
end

local function ApplyDropdownFont(dd, size, color)
  if not dd then return end
  local text = dd.Text or (dd.GetName and _G[dd:GetName() .. "Text"])
  ApplyUIFont(text, size or 12, nil, color)
end

local function RightAlignDropdownText(dd)
  if not dd then return end
  if UIDropDownMenu_JustifyText then
    UIDropDownMenu_JustifyText(dd, "RIGHT")
    return
  end
  local text = dd.Text or (dd.GetName and _G[dd:GetName() .. "Text"])
  if text and text.SetJustifyH then
    text:SetJustifyH("RIGHT")
  end
end

-- =========================================================
-- UI Widget Builders (Sections, Buttons, Checkboxes, Sliders)
-- =========================================================

local function ApplyDarkBackdrop(frame)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints(true)
  frame.bg:SetColorTexture(0.06, 0.06, 0.07, 0.94)

  frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  frame.border:SetAllPoints(true)
  frame.border:SetBackdrop({
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame.border:SetBackdropBorderColor(0.22, 0.22, 0.26, 1.0)
end

local function MakeSection(parent, title)
  local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  section:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  section:SetBackdropColor(0.12, 0.12, 0.14, 0.6)
  section:SetBackdropBorderColor(0.2, 0.2, 0.22, 1)

  -- Orange accent line at top
  section.accent = section:CreateTexture(nil, "OVERLAY")
  section.accent:SetPoint("TOPLEFT", 0, 0)
  section.accent:SetPoint("TOPRIGHT", 0, 0)
  section.accent:SetHeight(2)
  section.accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
  RegisterTheme(function(c)
    if section.accent and section.accent.SetColorTexture then
      section.accent:SetColorTexture(c[1], c[2], c[3], 0.8)
    end
  end)

  if title and title ~= "" then
    section.title = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section.title:SetPoint("TOPLEFT", 12, -10)
    section.title:SetText(title)
    ApplyUIFont(section.title, ORANGE_SIZE, "OUTLINE", ORANGE)
  end

  return section
end

local function Title(parent, text)
  local t = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  t:SetText(text)
  ApplyUIFont(t, ORANGE_SIZE, "OUTLINE", ORANGE)
  return t
end

local function Small(parent, text)
  local t = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  t:SetText(text)
  t:SetJustifyH("LEFT")
  ApplyUIFont(t, 11, nil, { 0.9, 0.9, 0.9 })
  return t
end

local function MakeButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 160, h or 26)

  -- Modern button styling
  b:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  b:SetBackdropColor(0.12, 0.12, 0.14, 0.9)
  b:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.6)

  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("CENTER")
  b.text:SetText(text)
  ApplyUIFont(b.text, ORANGE_SIZE, "OUTLINE", ORANGE)

  RegisterTheme(function(c)
    if b and b.SetBackdropBorderColor then
      b:SetBackdropBorderColor(c[1], c[2], c[3], 0.6)
    end
    if b.text and b.text.SetTextColor then
      b.text:SetTextColor(c[1], c[2], c[3])
    end
  end)

  b:SetScript("OnEnter", function()
    b:SetBackdropColor(0.15, 0.15, 0.17, 1)
    b:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
  end)
  b:SetScript("OnLeave", function()
    b:SetBackdropColor(0.12, 0.12, 0.14, 0.9)
    b:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.6)
  end)

  function b:SetText(t)
    b.text:SetText(t)
  end
  function b:GetFontString()
    return b.text
  end

  return b
end

local function MakeCheckbox(parent, label, tooltip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb.Text:SetText(label)
  ApplyUIFont(cb.Text, 12, "OUTLINE", { 0.95, 0.95, 0.95 })

  -- Style the checkbox itself
  if cb.SetCheckedTexture then
    local checked = cb:GetCheckedTexture()
    if checked then checked:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1) end
  end
  RegisterTheme(function(c)
    if cb.GetCheckedTexture then
      local checked = cb:GetCheckedTexture()
      if checked then checked:SetVertexColor(c[1], c[2], c[3], 1) end
    end
  end)

  cb:SetScript("OnEnter", function()
    cb.Text:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    if tooltip then
      GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, ORANGE[1], ORANGE[2], ORANGE[3])
      GameTooltip:AddLine(tooltip, 0.95, 0.95, 0.95, true)
      GameTooltip:Show()
    end
  end)
  cb:SetScript("OnLeave", function()
    cb.Text:SetTextColor(0.95, 0.95, 0.95)
    GameTooltip:Hide()
  end)

  return cb
end

-- Sliders: centered text, no min/max, show only current value.
local function MakeSlider(parent, label, minv, maxv, step)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(minv, maxv)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(300)

  if s.Low then s.Low:Hide() end
  if s.High then s.High:Hide() end

  -- Style the slider thumb
  local thumb = s:GetThumbTexture()
  if thumb then
    thumb:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    thumb:SetSize(12, 20)
  end
  RegisterTheme(function(c)
    if thumb and thumb.SetColorTexture then
      thumb:SetColorTexture(c[1], c[2], c[3], 1)
    end
  end)

  s.Text:ClearAllPoints()
  s.Text:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -4)
  s.Text:SetJustifyH("RIGHT")
  ApplyUIFont(s.Text, 11, "OUTLINE", { 0.95, 0.95, 0.95 })

  -- Label above slider
  s.Label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  s.Label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
  s.Label:SetText(label)
  ApplyUIFont(s.Label, ORANGE_SIZE, "OUTLINE", ORANGE)

  function s:SetLabelValue(v, fmt)
    local f = fmt or "%.2f"
    self.Text:SetText(f:format(v))
  end

  return s
end

local function Round2(v) return tonumber(string.format("%.2f", v)) end

-- =========================================================
-- Color Picker & Color Swatches
-- =========================================================
local function OpenColorPickerRGB(initialR, initialG, initialB, onCommit, onCancel)
  local r, g, b = initialR or 1, initialG or 1, initialB or 1

  if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:SetFrameLevel(200)
    ColorPickerFrame:SetupColorPickerAndShow({
      r = r, g = g, b = b,
      hasOpacity = false,
      swatchFunc = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onCommit(nr, ng, nb)
      end,
      cancelFunc = function()
        if onCancel then onCancel(r, g, b) end
      end,
    })
    return
  end

  -- Legacy fallback (only if available)
  if not ColorPickerFrame then return end
  ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  ColorPickerFrame:SetFrameLevel(200)
  ColorPickerFrame.hasOpacity = false
  ColorPickerFrame.func = function()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    onCommit(nr, ng, nb)
  end
  ColorPickerFrame.cancelFunc = function()
    if onCancel then onCancel(r, g, b) end
  end
  if ColorPickerFrame.SetColorRGB then
    ColorPickerFrame:SetColorRGB(r, g, b)
  end
  ColorPickerFrame:Show()
end

local function MakeColorSwatch(parent, label, getColor, setColor)
  local labelFS = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  labelFS:SetText(label)
  ApplyUIFont(labelFS, ORANGE_SIZE, "OUTLINE", ORANGE)

  local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
  swatch:SetSize(28, 28)
  swatch:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 2,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  swatch:SetBackdropBorderColor(0.2, 0.2, 0.22, 1)

  swatch.colorTex = swatch:CreateTexture(nil, "ARTWORK")
  swatch.colorTex:SetTexture("Interface/Buttons/WHITE8x8")
  swatch.colorTex:SetPoint("TOPLEFT", 2, -2)
  swatch.colorTex:SetPoint("BOTTOMRIGHT", -2, 2)

  local function Refresh()
    local c = getColor()
    if not c then return end
    swatch.colorTex:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 1)
  end

  swatch:SetScript("OnEnter", function()
    swatch:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
  end)
  swatch:SetScript("OnLeave", function()
    swatch:SetBackdropBorderColor(0.2, 0.2, 0.22, 1)
  end)
  swatch:SetScript("OnClick", function()
    local c = getColor() or { r = 1, g = 1, b = 1 }
    OpenColorPickerRGB(c.r, c.g, c.b,
      function(r, g, b)
        setColor(r, g, b)
        Refresh()
      end,
      function(r, g, b)
        setColor(r, g, b)
        Refresh()
      end
    )
  end)

  Refresh()
  return labelFS, swatch, Refresh
end

-- =========================================================
-- =========================================================
--                   OPTIONS PANEL MAIN
-- =========================================================
-- =========================================================

function NS:InitOptions()
  local db = NS:GetDB()
  if not db then return end

  local function BuildFullUI(panel)
    -- Reset registries instead of appending to prevent memory growth
    NS._huiFontRegistry = {}
    NS._huiThemeRegistry = {}

    local UpdateNavIndicators = function() end

    if db and db.general then
      if not db.general.themeColor then
        db.general.themeColor = { r = ORANGE[1], g = ORANGE[2], b = ORANGE[3] }
      end
      SetThemeColor(db.general.themeColor.r, db.general.themeColor.g, db.general.themeColor.b)
    end
    ApplyDarkBackdrop(panel)

    -- Modern grey/orange theme
    -- Fully transparent backdrop so only the two panels are visible.
    panel.bg:SetColorTexture(0, 0, 0, 0)
    -- Remove outer border so each panel has its own rounded border.
    panel.border:SetBackdropBorderColor(0, 0, 0, 0)

    local nav = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", 0, 0)
    nav:SetWidth(200)
    ApplyDarkBackdrop(nav)
    nav.bg:SetColorTexture(0.15, 0.15, 0.16, 0.98)
    nav.border:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    RegisterTheme(function(c)
      if nav.border and nav.border.SetBackdropBorderColor then
        nav.border:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
      end
    end)

    local navHeader = CreateFrame("Frame", nil, nav, "BackdropTemplate")
    navHeader:SetPoint("TOPLEFT", 0, 0)
    navHeader:SetPoint("TOPRIGHT", -2, 0)
    navHeader:SetHeight(72)
    navHeader:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    -- Match header tone to the main nav panel.
    navHeader:SetBackdropColor(0.15, 0.15, 0.16, 0.98)
    navHeader:SetBackdropBorderColor(0, 0, 0, 0)

    -- Logo in header area (replaces text title).
    local navLogo = navHeader:CreateTexture(nil, "OVERLAY")
    navLogo:SetPoint("CENTER", 0, 0)
    -- Constrain logo to the padded header area.
    navLogo:SetSize(170, 56)
    navLogo:SetTexCoord(0, 1, 0, 1)
    navLogo:SetTexture("Interface\\AddOns\\HarathUI\\Media\\logo.tga")
    navLogo:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    RegisterTheme(function(c)
      if navLogo and navLogo.SetVertexColor then
        navLogo:SetVertexColor(c[1], c[2], c[3], 1)
      end
    end)

    local navLogoCaps = navHeader:CreateTexture(nil, "OVERLAY")
    navLogoCaps:SetPoint("TOPLEFT", navLogo, "TOPLEFT", 0, 0)
    navLogoCaps:SetPoint("BOTTOMRIGHT", navLogo, "BOTTOMRIGHT", 0, 0)
    navLogoCaps:SetTexCoord(0, 1, 0, 1)
    navLogoCaps:SetTexture("Interface\\AddOns\\HarathUI\\Media\\logoCaps.tga")

    -- Line under logo to match settings pages (inset, lower).
    local navLine = nav:CreateTexture(nil, "OVERLAY")
    navLine:SetPoint("TOPLEFT", 18, -80)
    navLine:SetPoint("TOPRIGHT", -18, -80)
    navLine:SetHeight(2)
    navLine:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    RegisterTheme(function(c)
      if navLine and navLine.SetColorTexture then
        navLine:SetColorTexture(c[1], c[2], c[3], 0.8)
      end
    end)

    local navVersion = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    navVersion:SetPoint("BOTTOMRIGHT", -12, 10)
    ApplyUIFont(navVersion, 10, "OUTLINE", ORANGE)

    local navGitIndicator = nav:CreateTexture(nil, "OVERLAY")
    navGitIndicator:SetSize(10, 10)
    navGitIndicator:SetPoint("RIGHT", navVersion, "LEFT", -6, 0)
    if navGitIndicator.EnableMouse then
      navGitIndicator:EnableMouse(true)
    end
    if navGitIndicator.SetScript then
      navGitIndicator:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local info = GetVersionInfo()
        local status = (info and (info.status or GetVersionStatus(info))) or "unknown"
        local source = tostring(info and info.source or "unknown")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Version Status", ORANGE[1], ORANGE[2], ORANGE[3])
        GameTooltip:AddLine(("Installed: v%s"):format(tostring(info and info.installed or "unknown")), 0.95, 0.95, 0.95)
        GameTooltip:AddLine(("Latest: v%s"):format(tostring(info and info.latest or "n/a")), 0.95, 0.95, 0.95)
        if info and info.peerName then
          GameTooltip:AddLine(("Peer: %s"):format(tostring(info.peerName)), 0.85, 0.85, 0.85)
        end
        if status == "out-of-date" then
          GameTooltip:AddLine("Status: Update available", 1.0, 0.35, 0.35)
        elseif status == "ahead" then
          GameTooltip:AddLine("Status: Local build is ahead", 0.95, 0.80, 0.35)
        elseif status == "up-to-date" then
          GameTooltip:AddLine("Status: Up to date", 0.35, 1.0, 0.45)
        else
          GameTooltip:AddLine("Status: Unknown", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(("Source: %s"):format(source), 0.7, 0.7, 0.7)
        if not (info and info.authoritative) then
          GameTooltip:AddLine("Waiting for peer version data.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
      end)
      navGitIndicator:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end

    local function UpdateVersionIndicator()
      local info = GetVersionInfo()
      local installed = info and info.installed or nil
      local status = (info and (info.status or GetVersionStatus(info))) or "unknown"

      navVersion:SetText("v" .. tostring(installed or "dev"))

      navGitIndicator:Show()
      if status == "out-of-date" then
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
      elseif status == "ahead" then
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Away")
      elseif status == "up-to-date" then
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
      else
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Away")
      end
    end

    UpdateVersionIndicator()
    if NS and NS.RegisterVersionInfoListener then
      NS:RegisterVersionInfoListener(UpdateVersionIndicator)
    end

    local content = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    -- Small gap so the two panel borders read as separate.
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 3, 0)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    ApplyDarkBackdrop(content)
    -- Match the left nav panel tone.
    content.bg:SetColorTexture(0.15, 0.15, 0.16, 0.98)
    content.border:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    RegisterTheme(function(c)
      if content.border and content.border.SetBackdropBorderColor then
        content.border:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
      end
    end)

    local pages = {}
    local function ShowPage(key)
      for k, p in pairs(pages) do
        p:SetShown(k == key)
      end
    end

    local function BuildTopRow(parent)
      local enable = MakeCheckbox(parent, "Enable HarathUI", "Toggle the whole UI suite on/off.")
      enable:SetPoint("TOPLEFT", 18, -96)
      enable:SetChecked(db.general.enabled)
      enable:SetScript("OnClick", function()
        db.general.enabled = enable:GetChecked()
        NS:ApplyAll()
        UpdateNavIndicators()
      end)

      local move = MakeCheckbox(parent, "Unlock Frames", "Show simple drag outlines for movable UI elements.")
      move:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
      move:SetChecked(not db.general.framesLocked)
      move:SetScript("OnClick", function()
        db.general.framesLocked = not move:GetChecked()
        if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
      end)

      local moveOptions = MakeCheckbox(parent, "Move Options", "Drag the Blizzard Settings window.")
      moveOptions:SetPoint("TOPLEFT", move, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
      moveOptions:SetChecked(db.general.moveOptions)
      moveOptions:SetScript("OnClick", function()
        db.general.moveOptions = moveOptions:GetChecked()
        NS:ApplyAll()
      end)

      local minimapBtn = MakeCheckbox(parent, "Minimap Button", "Show or hide the HarathUI minimap button.")
      minimapBtn:SetPoint("TOPLEFT", moveOptions, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
      minimapBtn:SetChecked(not (db.general.minimapButton and db.general.minimapButton.hide))
      minimapBtn:SetScript("OnClick", function()
        db.general.minimapButton = db.general.minimapButton or {}
        db.general.minimapButton.hide = not minimapBtn:GetChecked()
        if NS.UpdateMinimapButton then NS:UpdateMinimapButton() end
      end)

      if db.general.showSpellIDs == nil then
        db.general.showSpellIDs = false
      end
      local spellIdsCB = MakeCheckbox(parent, "Show Spell IDs", "Append spell IDs to spell tooltips.")
      spellIdsCB:SetPoint("TOPLEFT", minimapBtn, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
      spellIdsCB:SetChecked(db.general.showSpellIDs == true)
      spellIdsCB:SetScript("OnClick", function()
        db.general.showSpellIDs = spellIdsCB:GetChecked()
      end)

      local smallMenu = MakeCheckbox(parent, "Smaller Game Menu", "Use the compact game menu.")
      smallMenu:SetPoint("TOPLEFT", spellIdsCB, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
      smallMenu:SetChecked(db.gamemenu and db.gamemenu.enabled)
      smallMenu:SetScript("OnClick", function()
        db.gamemenu = db.gamemenu or {}
        db.gamemenu.enabled = smallMenu:GetChecked()
        NS:ApplyAll()
      end)

      db.summons = db.summons or {}
      if db.summons.enabled == nil then
        db.summons.enabled = true
      end

      local summonCB = MakeCheckbox(parent, "Auto Accept Summons", "Automatically accept incoming party/raid summons.")
      summonCB:SetPoint("TOPLEFT", smallMenu, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
      summonCB:SetChecked(db.summons.enabled == true)
      summonCB:SetScript("OnClick", function()
        db.summons.enabled = summonCB:GetChecked()
        NS:ApplyAll()
      end)

      local trackedBars = MakeCheckbox(parent, "Skin Tracked Bars", "Apply cast-bar style to Blizzard Cooldown Viewer tracked bars.")
      trackedBars:SetPoint("TOPLEFT", summonCB, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
      trackedBars:SetChecked(db.general.trackedBarsSkin == true)
      trackedBars:SetScript("OnClick", function()
        db.general.trackedBarsSkin = trackedBars:GetChecked()
        NS:ApplyAll()
      end)

      local resetAll = MakeButton(parent, "Reset All Positions", 160, 24)
      resetAll:SetPoint("TOPLEFT", trackedBars, "BOTTOMLEFT", 0, GROUP_GAP)
      resetAll:SetScript("OnClick", function()
        NS:ResetFramePosition("xpbar", NS.DEFAULTS.profile.xpbar)
        NS:ResetFramePosition("castbar", NS.DEFAULTS.profile.castbar)
        if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
      end)

      local themeLabel, themeSwatch = MakeColorSwatch(
        parent,
        "Theme",
        function()
          db.general.themeColor = db.general.themeColor or { r = ORANGE[1], g = ORANGE[2], b = ORANGE[3] }
          return db.general.themeColor
        end,
        function(r, g, b)
          db.general.themeColor = { r = r, g = g, b = b }
          SetThemeColor(r, g, b)
        end
      )
      themeLabel:SetPoint("TOPLEFT", resetAll, "BOTTOMLEFT", 0, GROUP_GAP)
      themeSwatch:SetPoint("LEFT", themeLabel, "RIGHT", 12, 0)
    end

    local function AddHeaderImage(page, baseName)
      if not baseName or baseName == "" then return end
      local sizes = {
        ["General"] = { 155, 56 },
        ["XP"] = { 229, 56 },
        ["CastBar"] = { 166, 56 },
        ["Nameplate"] = { 270, 56 },
        ["Helper"] = { 282, 56 },
        ["Minimap"] = { 231, 56 },
        ["Toasts"] = { 212, 56 },
        ["Menu"] = { 219, 56 },
      }
      local size = sizes[baseName]
      local tex = page:CreateTexture(nil, "OVERLAY")
      tex:SetPoint("TOPLEFT", 8, -12)
      if size then
        tex:SetSize(size[1], size[2])
      else
        tex:SetSize(200, 56)
      end
      tex:SetTexture("Interface\\AddOns\\HarathUI\\Media\\" .. baseName .. "White.tga")
      tex:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
      tex:SetAlpha(1)
      RegisterTheme(function(c)
        if tex and tex.SetVertexColor then
          tex:SetVertexColor(c[1], c[2], c[3], 1)
        end
      end)

      local caps = page:CreateTexture(nil, "OVERLAY", nil, 1)
      caps:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, 0)
      caps:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
      caps:SetTexture("Interface\\AddOns\\HarathUI\\Media\\" .. baseName .. "Caps.tga")
      caps:SetVertexColor(1, 1, 1, 1)
      caps:SetAlpha(1)
      caps:SetBlendMode("BLEND")

      return tex
    end

    local function MakeModuleHeader(page, key)
      local headerMap = {
        xpbar = "XP",
        castbar = "CastBar",
        charsheet = "General",
        friendlyplates = "Nameplate",
        rotation = "Helper",
        rotationhelper = "Helper",
        minimap = "Minimap",
        minimapbar = "Minimap",
        loot = "Toasts",
        gamemenu = "Menu",
      }
      AddHeaderImage(page, headerMap[key])

      -- Orange line under title position (title text removed).
      local line = page:CreateTexture(nil, "ARTWORK")
      line:SetPoint("TOPLEFT", 18, -80)
      line:SetPoint("TOPRIGHT", -18, -80)
      line:SetHeight(2)
      line:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
      RegisterTheme(function(c)
        if line and line.SetColorTexture then
          line:SetColorTexture(c[1], c[2], c[3], 0.8)
        end
      end)

      local en = MakeCheckbox(page, "Enable Module", "Enable or disable this module.")
      en:SetPoint("TOPLEFT", 18, -96)
      en:SetChecked(db[key] and db[key].enabled)
      en:SetScript("OnClick", function()
        db[key].enabled = en:GetChecked()
        NS:ApplyAll()
        UpdateNavIndicators()
      end)
      return en
    end

  -- =========================================================
  -- GENERAL PAGE
  -- =========================================================
    pages.general = CreateFrame("Frame", nil, content); pages.general:SetAllPoints(true)
    do
    AddHeaderImage(pages.general, "General")

    -- Orange line under title position (title text removed)
    local generalLine = pages.general:CreateTexture(nil, "ARTWORK")
    generalLine:SetPoint("TOPLEFT", 18, -80)
    generalLine:SetPoint("TOPRIGHT", -18, -80)
    generalLine:SetHeight(2)
    generalLine:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    RegisterTheme(function(c)
      if generalLine and generalLine.SetColorTexture then
        generalLine:SetColorTexture(c[1], c[2], c[3], 0.8)
      end
    end)

    BuildTopRow(pages.general)

    local card = MakeSection(pages.general, "Quick Commands")
    card:SetPoint("BOTTOMLEFT", 18, 18)
    card:SetPoint("BOTTOMRIGHT", -18, 18)
    card:SetHeight(110)
    -- No border, just the background fill.
    card:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = nil,
      edgeSize = 0,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    card:SetBackdropColor(0.12, 0.12, 0.14, 0.6)
    card:SetBackdropBorderColor(0, 0, 0, 0)

    local txt = Small(card, "- /hui (options)\n- /hui lock (toggle Unlock Frames)\n- /hui xp | cast | loot | summon\n")
    txt:SetPoint("TOPLEFT", 14, -32)
  end

  -- =========================================================
  -- XP / REP BAR PAGE
  -- =========================================================
    pages.xp = CreateFrame("Frame", nil, content); pages.xp:SetAllPoints(true)
    do
    local xpEnable = MakeModuleHeader(pages.xp, "xpbar")

    local preview = MakeButton(pages.xp, "Preview Bar", 160, 24)
    preview:SetPoint("TOPLEFT", 18, FIRST_CONTROL_Y)
    preview:SetScript("OnClick", function()
      if NS.Modules and NS.Modules.xpbar and NS.Modules.xpbar.Preview then
        NS.Modules.xpbar:Preview()
      end
    end)

    local scale = MakeSlider(pages.xp, "Scale", 0.6, 1.5, 0.05)
    scale:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, BUTTON_TO_SLIDER_GAP)
    scale:SetValue(db.xpbar.scale or 1.0)
    scale:SetLabelValue(db.xpbar.scale or 1.0, "%.2f")
    scale:SetScript("OnValueChanged", function(_, v)
      v = Round2(v)
      db.xpbar.scale = v
      scale:SetLabelValue(v, "%.2f")
      NS:ApplyAll()
    end)

    local width = MakeSlider(pages.xp, "Length", 200, 800, 10)
    width:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, SLIDER_GAP)
    width:SetValue(db.xpbar.width or 520)
    width:SetLabelValue(db.xpbar.width or 520, "%.0f")
    width:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.xpbar.width = v
      width:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
    end)

    local height = MakeSlider(pages.xp, "Height", 6, 26, 1)
    height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, SLIDER_GAP)
    height:SetValue(db.xpbar.height or 12)
    height:SetLabelValue(db.xpbar.height or 12, "%.0f")
    height:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.xpbar.height = v
      height:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
    end)

    local showText = MakeCheckbox(pages.xp, "Show Text", "Show exact progress numbers.")
    showText:SetPoint("TOPLEFT", height, "BOTTOMLEFT", 0, SLIDER_TO_CHECKBOX_GAP)
    showText:SetChecked(db.xpbar.showText)
    showText:SetScript("OnClick", function()
      db.xpbar.showText = showText:GetChecked()
      NS:ApplyAll()
    end)

    local showSession = MakeCheckbox(pages.xp, "Session Time", "Show time played this session.")
    showSession:SetPoint("TOPLEFT", showText, "BOTTOMLEFT", 0, -CHECKBOX_GAP)
    showSession:SetChecked(db.xpbar.showSessionTime)
    showSession:SetScript("OnClick", function()
      db.xpbar.showSessionTime = showSession:GetChecked()
      NS:ApplyAll()
    end)

    local showRate = MakeCheckbox(pages.xp, "TTL & Exp P/h", "Show ETA and XP per hour.")
    showRate:SetPoint("LEFT", showText, "RIGHT", 160, 0)
    showRate:SetChecked(db.xpbar.showRateText)
    showRate:SetScript("OnClick", function()
      db.xpbar.showRateText = showRate:GetChecked()
      NS:ApplyAll()
    end)

    local showQuest = MakeCheckbox(pages.xp, "Quest Exp", "Show completed quests and rested text.")
    showQuest:SetPoint("LEFT", showSession, "RIGHT", 160, 0)
    showQuest:SetChecked(db.xpbar.showQuestText)
    showQuest:SetScript("OnClick", function()
      db.xpbar.showQuestText = showQuest:GetChecked()
      NS:ApplyAll()
    end)

    local showAtMax = MakeCheckbox(pages.xp, "Show Bar at Max Level", "Keep XP bar visible at max level.")
    showAtMax:SetPoint("LEFT", xpEnable, "RIGHT", 160, 0)
    showAtMax:SetChecked(db.xpbar.showAtMaxLevel)
    showAtMax:SetScript("OnClick", function()
      db.xpbar.showAtMaxLevel = showAtMax:GetChecked()
      NS:ApplyAll()
    end)

    -- Font settings
    if not db.xpbar.font then db.xpbar.font = "BigNoodleTilting" end
    if not db.xpbar.fontOutline then db.xpbar.fontOutline = "NONE" end

    local xpFontLabel = pages.xp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    xpFontLabel:SetPoint("TOPLEFT", showSession, "BOTTOMLEFT", 0, GROUP_GAP)
    xpFontLabel:SetText("Font")
    ApplyUIFont(xpFontLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local xpFontDD = CreateFrame("Frame", "HarathUI_XPBarFontDropdown", pages.xp, "UIDropDownMenuTemplate")
    xpFontDD:SetPoint("TOPLEFT", xpFontLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(xpFontDD, 220)

    local xpFonts = {}
    if LSM then
      for _, name in ipairs(LSM:List("font")) do
        xpFonts[#xpFonts + 1] = name
      end
      table.sort(xpFonts)
    end

    local function RefreshXPFont()
      UIDropDownMenu_SetSelectedValue(xpFontDD, db.xpbar.font)
      UIDropDownMenu_SetText(xpFontDD, db.xpbar.font or "Default")
    end

    UIDropDownMenu_Initialize(xpFontDD, function(self, level)
      if not LSM then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "LibSharedMedia-3.0 not found"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        return
      end

      for _, name in ipairs(xpFonts) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (db.xpbar.font == name)
        info.func = function()
          db.xpbar.font = name
          RefreshXPFont()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(xpFontDD, 12, { 0.9, 0.9, 0.9 })
    RightAlignDropdownText(xpFontDD)
    RefreshXPFont()

    local xpOutlineLabel = pages.xp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    xpOutlineLabel:SetPoint("TOPLEFT", xpFontDD, "BOTTOMLEFT", 16, DROPDOWN_GAP)
    xpOutlineLabel:SetText("Outline")
    ApplyUIFont(xpOutlineLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local xpOutlineDD = CreateFrame("Frame", "HarathUI_XPBarOutlineDropdown", pages.xp, "UIDropDownMenuTemplate")
    xpOutlineDD:SetPoint("TOPLEFT", xpOutlineLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(xpOutlineDD, 180)

    local xpOutlines = {
      { name = "None", value = "NONE" },
      { name = "Outline", value = "OUTLINE" },
      { name = "Thick Outline", value = "THICKOUTLINE" },
      { name = "Mono + Outline", value = "MONOCHROME,OUTLINE" },
      { name = "Mono + Thick", value = "MONOCHROME,THICKOUTLINE" },
    }

    local function RefreshXPOutline()
      UIDropDownMenu_SetSelectedValue(xpOutlineDD, db.xpbar.fontOutline)
      UIDropDownMenu_SetText(xpOutlineDD, db.xpbar.fontOutline or "NONE")
    end

    UIDropDownMenu_Initialize(xpOutlineDD, function(self, level)
      for _, o in ipairs(xpOutlines) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = o.name
        info.checked = (db.xpbar.fontOutline == o.value)
        info.func = function()
          db.xpbar.fontOutline = o.value
          RefreshXPOutline()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(xpOutlineDD, 12, { 0.9, 0.9, 0.9 })
    RightAlignDropdownText(xpOutlineDD)
    RefreshXPOutline()
  end

  -- =========================================================
  -- CAST BAR PAGE
  -- =========================================================
    pages.cast = CreateFrame("Frame", nil, content); pages.cast:SetAllPoints(true)
    do
    local castEnable = MakeModuleHeader(pages.cast, "castbar")

    -- Layout constants for easier tuning.
    local castLeftX = 18
    local castRightX = 240
    local castEnableY = -96
    local castToggleGap = CAST_CHECKBOX_GAP

    local showIcon = MakeCheckbox(pages.cast, "Show Spell Icon", "Show the spell icon on the left.")
    showIcon:SetPoint("LEFT", castEnable, "RIGHT", 160, 0)
    showIcon:SetChecked(db.castbar.showIcon)
    showIcon:SetScript("OnClick", function()
      db.castbar.showIcon = showIcon:GetChecked()
      NS:ApplyAll()
    end)

    local previewBtn = MakeButton(pages.cast, "Preview Cast Bar", 160, 24)
    previewBtn:SetPoint("TOPLEFT", castLeftX, castEnableY - 32)
    previewBtn:SetScript("OnClick", function()
      if NS.Modules and NS.Modules.castbar and NS.Modules.castbar.Preview then
        NS.Modules.castbar:Preview()
      end
    end)

    local shield = MakeCheckbox(pages.cast, "Show Interrupt Shield", "Shield icon on uninterruptible casts.")
    shield:SetPoint("TOPLEFT", showIcon, "TOPLEFT", 0, -32)
    shield:SetChecked(db.castbar.showShield)
    shield:SetScript("OnClick", function()
      db.castbar.showShield = shield:GetChecked()
      NS:ApplyAll()
    end)

    local latency = MakeCheckbox(pages.cast, "Show Latency Spark", "Latency spark at the bar edge (best-effort).")
    latency:SetPoint("LEFT", shield, "RIGHT", 160, 0)
    latency:SetChecked(db.castbar.showLatencySpark)
    latency:SetScript("OnClick", function()
      db.castbar.showLatencySpark = latency:GetChecked()
      NS:ApplyAll()
    end)

    local scale = MakeSlider(pages.cast, "Scale", 0.6, 1.8, 0.05)
    scale:SetPoint("TOPLEFT", previewBtn, "BOTTOMLEFT", 0, BUTTON_TO_SLIDER_GAP)
    scale:SetValue(db.castbar.scale or 1.0)
    scale:SetLabelValue(db.castbar.scale or 1.0, "%.2f")
    scale:SetScript("OnValueChanged", function(_, v)
      v = Round2(v)
      db.castbar.scale = v
      scale:SetLabelValue(v, "%.2f")
      NS:ApplyAll()
    end)

    local width = MakeSlider(pages.cast, "Width", 220, 640, 10)
    width:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, SLIDER_GAP)
    width:SetValue(db.castbar.width or 320)
    width:SetLabelValue(db.castbar.width or 320, "%.0f")
    width:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.castbar.width = v
      width:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
    end)

    local height = MakeSlider(pages.cast, "Height", 12, 32, 1)
    height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, SLIDER_GAP)
    height:SetValue(db.castbar.height or 16)
    height:SetLabelValue(db.castbar.height or 16, "%.0f")
    height:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.castbar.height = v
      height:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
    end)

    -- toggles moved above sliders

    if not db.castbar.barTexture then db.castbar.barTexture = "Interface/TargetingFrame/UI-StatusBar" end
    if not db.castbar.barColor then db.castbar.barColor = { r = 0.5, g = 0.5, b = 1.0 } end

    local textures = {
      { name = "Flat",     path = "Interface/TargetingFrame/UI-StatusBar" },
      { name = "Blizzard", path = "Interface/RaidFrame/Raid-Bar-Hp-Fill" },
      { name = "White",    path = "Interface/Buttons/WHITE8x8" },
    }

    local function GetCastBarColor()
      return db.castbar.barColor
    end
    local function SetCastBarColor(r, g, b)
      db.castbar.barColor = { r = r, g = g, b = b }
      NS:ApplyAll()
    end
    local colorLabel, colorSwatch = MakeColorSwatch(pages.cast, "Bar Color", GetCastBarColor, SetCastBarColor)
    colorLabel:SetPoint("LEFT", width, "RIGHT", 30, 0)
    colorSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)

    if not db.castbar.textColor then db.castbar.textColor = { r = 1, g = 1, b = 1 } end
    local function GetCastTextColor()
      return db.castbar.textColor
    end
    local function SetCastTextColor(r, g, b)
      db.castbar.textColor = { r = r, g = g, b = b }
      NS:ApplyAll()
    end
    local textColorLabel, textColorSwatch = MakeColorSwatch(pages.cast, "Text Color", GetCastTextColor, SetCastTextColor)
    textColorLabel:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -14)
    textColorSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, -26)

    local textSize = MakeSlider(pages.cast, "Text Size", 8, 20, 1)
    textSize:SetPoint("TOPLEFT", height, "BOTTOMLEFT", 0, SLIDER_GAP)
    textSize:SetValue(db.castbar.textSize or 11)
    textSize:SetLabelValue(db.castbar.textSize or 11, "%.0f")
    textSize:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.castbar.textSize = v
      textSize:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
    end)

    local textFontLabel = pages.cast:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    textFontLabel:SetPoint("TOPLEFT", textSize, "BOTTOMLEFT", 0, GROUP_GAP)
    textFontLabel:SetText("Text Font")
    ApplyUIFont(textFontLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local textFontDD = CreateFrame("Frame", "HarathUI_CastBarTextFontDropdown", pages.cast, "UIDropDownMenuTemplate")
    textFontDD:SetPoint("TOPLEFT", textFontLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(textFontDD, 220)

    if not db.castbar.textFont then
      db.castbar.textFont = "BigNoodleTilting"
    end
    local textFonts = {}
    if LSM then
      for _, name in ipairs(LSM:List("font")) do
        textFonts[#textFonts + 1] = name
      end
      table.sort(textFonts)
    end

    local function RefreshTextFont()
      UIDropDownMenu_SetSelectedValue(textFontDD, db.castbar.textFont)
      UIDropDownMenu_SetText(textFontDD, db.castbar.textFont or "Default")
    end

    UIDropDownMenu_Initialize(textFontDD, function(self, level)
      if not LSM then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "LibSharedMedia-3.0 not found"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        return
      end

      for _, name in ipairs(textFonts) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (db.castbar.textFont == name)
        info.func = function()
          db.castbar.textFont = name
          RefreshTextFont()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(textFontDD, 12, { 0.9, 0.9, 0.9 })
    RefreshTextFont()

    local textOutlineLabel = pages.cast:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    textOutlineLabel:SetPoint("TOPLEFT", textFontDD, "BOTTOMLEFT", 16, DROPDOWN_GAP)
    textOutlineLabel:SetText("Text Outline")
    ApplyUIFont(textOutlineLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local textOutlineDD = CreateFrame("Frame", "HarathUI_CastBarTextOutlineDropdown", pages.cast, "UIDropDownMenuTemplate")
    textOutlineDD:SetPoint("TOPLEFT", textOutlineLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(textOutlineDD, 180)

    if not db.castbar.textOutline then
      db.castbar.textOutline = "NONE"
    end

    local textOutlines = {
      { name = "None", value = "NONE" },
      { name = "Outline", value = "OUTLINE" },
      { name = "Thick Outline", value = "THICKOUTLINE" },
      { name = "Mono + Outline", value = "MONOCHROME,OUTLINE" },
      { name = "Mono + Thick", value = "MONOCHROME,THICKOUTLINE" },
    }

    local function RefreshTextOutline()
      UIDropDownMenu_SetSelectedValue(textOutlineDD, db.castbar.textOutline)
      UIDropDownMenu_SetText(textOutlineDD, db.castbar.textOutline or "NONE")
    end

    UIDropDownMenu_Initialize(textOutlineDD, function(self, level)
      for _, o in ipairs(textOutlines) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = o.name
        info.checked = (db.castbar.textOutline == o.value)
        info.func = function()
          db.castbar.textOutline = o.value
          RefreshTextOutline()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(textOutlineDD, 12, { 0.9, 0.9, 0.9 })
    RefreshTextOutline()

    local texLabel = pages.cast:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    texLabel:SetPoint("TOPLEFT", textOutlineDD, "BOTTOMLEFT", 16, DROPDOWN_GAP)
    texLabel:SetText("Bar Texture")
    ApplyUIFont(texLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local texDD = CreateFrame("Frame", "HarathUI_CastBarTextureDropdown", pages.cast, "UIDropDownMenuTemplate")
    texDD:SetPoint("TOPLEFT", texLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(texDD, 180)

    local function GetTextureName(path)
      for _, t in ipairs(textures) do
        if t.path == path then return t.name end
      end
      return path
    end

    local function RefreshTex()
      UIDropDownMenu_SetSelectedValue(texDD, db.castbar.barTexture)
      UIDropDownMenu_SetText(texDD, GetTextureName(db.castbar.barTexture))
    end

    UIDropDownMenu_Initialize(texDD, function(self, level)
      for _, t in ipairs(textures) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = t.name
        info.checked = (db.castbar.barTexture == t.path)
        info.func = function()
          db.castbar.barTexture = t.path
          RefreshTex()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(texDD, 12, { 0.9, 0.9, 0.9 })
    RefreshTex()
  end

  -- =========================================================
  -- CHARACTER SHEET PAGE
  -- =========================================================
    pages.charsheet = CreateFrame("Frame", nil, content); pages.charsheet:SetAllPoints(true)
    do
    MakeModuleHeader(pages.charsheet, "charsheet")

    if not db.charsheet then
      db.charsheet = {}
    end
    if db.charsheet.hideArt == nil then
      db.charsheet.hideArt = true
    end
    if db.charsheet.styleStats == nil then
      db.charsheet.styleStats = true
    end
    if db.charsheet.showRightPanel == nil then
      db.charsheet.showRightPanel = true
    end
    if db.charsheet.rightPanelDetached == nil then
      db.charsheet.rightPanelDetached = false
    end
    if not db.charsheet.rightPanelAnchor then
      db.charsheet.rightPanelAnchor = "TOPLEFT"
    end
    if db.charsheet.rightPanelX == nil then
      db.charsheet.rightPanelX = 0
    end
    if db.charsheet.rightPanelY == nil then
      db.charsheet.rightPanelY = 0
    end
    if db.charsheet.rightPanelOffsetX == nil then
      db.charsheet.rightPanelOffsetX = 8
    end
    if db.charsheet.rightPanelOffsetY == nil then
      db.charsheet.rightPanelOffsetY = 0
    end
    if db.charsheet.stripeAlpha == nil then
      db.charsheet.stripeAlpha = 0.22
    end
    if not db.charsheet.font then
      db.charsheet.font = "BigNoodleTilting"
    end
    if not db.charsheet.fontSize then
      db.charsheet.fontSize = 12
    end
    if not db.charsheet.fontOutline then
      db.charsheet.fontOutline = "NONE"
    end

    local openChar = MakeButton(pages.charsheet, "Open Character", 160, 24)
    openChar:SetPoint("TOPLEFT", 18, FIRST_CONTROL_Y)
    openChar:SetScript("OnClick", function()
      if ToggleCharacter then
        ToggleCharacter("PaperDollFrame")
      elseif _G.ToggleCharacterFrame then
        _G.ToggleCharacterFrame()
      elseif CharacterFrame then
        if CharacterFrame:IsShown() then
          HideUIPanel(CharacterFrame)
        else
          ShowUIPanel(CharacterFrame)
        end
      end
    end)

    local fontLabel = pages.charsheet:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fontLabel:SetPoint("TOPLEFT", openChar, "BOTTOMLEFT", 0, GROUP_GAP)
    fontLabel:SetText("Stat Font")
    ApplyUIFont(fontLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local fontDD = CreateFrame("Frame", "HarathUI_CharacterSheetFontDropdown", pages.charsheet, "UIDropDownMenuTemplate")
    fontDD:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(fontDD, 220)

    local fonts = {}
    if LSM then
      for _, name in ipairs(LSM:List("font")) do
        fonts[#fonts + 1] = name
      end
      table.sort(fonts)
    end

    local function RefreshCharFont()
      UIDropDownMenu_SetSelectedValue(fontDD, db.charsheet.font)
      UIDropDownMenu_SetText(fontDD, db.charsheet.font or "Default")
    end

    UIDropDownMenu_Initialize(fontDD, function(self, level)
      if not LSM then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "LibSharedMedia-3.0 not found"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        return
      end

      for _, name in ipairs(fonts) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (db.charsheet.font == name)
        info.func = function()
          db.charsheet.font = name
          RefreshCharFont()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(fontDD, 12, { 0.9, 0.9, 0.9 })
    RightAlignDropdownText(fontDD)
    RefreshCharFont()

    local outlineLabel = pages.charsheet:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    outlineLabel:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 16, DROPDOWN_GAP)
    outlineLabel:SetText("Stat Outline")
    ApplyUIFont(outlineLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local outlineDD = CreateFrame("Frame", "HarathUI_CharacterSheetOutlineDropdown", pages.charsheet, "UIDropDownMenuTemplate")
    outlineDD:SetPoint("TOPLEFT", outlineLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(outlineDD, 180)

    local outlines = {
      { name = "None", value = "NONE" },
      { name = "Outline", value = "OUTLINE" },
      { name = "Thick Outline", value = "THICKOUTLINE" },
      { name = "Mono + Outline", value = "MONOCHROME,OUTLINE" },
      { name = "Mono + Thick", value = "MONOCHROME,THICKOUTLINE" },
    }

    local function RefreshCharOutline()
      UIDropDownMenu_SetSelectedValue(outlineDD, db.charsheet.fontOutline)
      UIDropDownMenu_SetText(outlineDD, db.charsheet.fontOutline or "NONE")
    end

    UIDropDownMenu_Initialize(outlineDD, function(self, level)
      for _, o in ipairs(outlines) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = o.name
        info.checked = (db.charsheet.fontOutline == o.value)
        info.func = function()
          db.charsheet.fontOutline = o.value
          RefreshCharOutline()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(outlineDD, 12, { 0.9, 0.9, 0.9 })
    RightAlignDropdownText(outlineDD)
    RefreshCharOutline()
  end

  -- =========================================================
  -- LOOT TOASTS PAGE
  -- =========================================================
    pages.loot = CreateFrame("Frame", nil, content); pages.loot:SetAllPoints(true)
    do
    MakeModuleHeader(pages.loot, "loot")

    local preview = MakeButton(pages.loot, "Preview Toasts", 160, 24)
    preview:SetPoint("TOPLEFT", 18, FIRST_CONTROL_Y)
    preview:SetScript("OnClick", function()
      if NS.Modules and NS.Modules.loot and NS.Modules.loot.Preview then
        NS.Modules.loot:Preview()
      end
    end)

    local scale = MakeSlider(pages.loot, "Scale", 0.6, 1.5, 0.05)
    scale:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, BUTTON_TO_SLIDER_GAP)
    scale:SetValue(db.loot.scale or 1.0)
    scale:SetLabelValue(db.loot.scale or 1.0, "%.2f")
    scale:SetScript("OnValueChanged", function(_, v)
      v = Round2(v)
      db.loot.scale = v
      scale:SetLabelValue(v, "%.2f")
      NS:ApplyAll()
    end)

    local duration = MakeSlider(pages.loot, "Duration (sec)", 1.0, 8.0, 0.5)
    duration:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, SLIDER_GAP)
    duration:SetValue(db.loot.duration or 3.5)
    duration:SetLabelValue(db.loot.duration or 3.5, "%.1f")
    duration:SetScript("OnValueChanged", function(_, v)
      v = Round2(v)
      db.loot.duration = v
      duration:SetLabelValue(v, "%.1f")
      NS:ApplyAll()
    end)

    -- Font settings
    if not db.loot.font then db.loot.font = "BigNoodleTilting" end
    if not db.loot.fontOutline then db.loot.fontOutline = "NONE" end

    local lootFontLabel = pages.loot:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lootFontLabel:SetPoint("TOPLEFT", duration, "BOTTOMLEFT", 0, GROUP_GAP)
    lootFontLabel:SetText("Text Font")
    ApplyUIFont(lootFontLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local lootFontDD = CreateFrame("Frame", "HarathUI_LootToastsFontDropdown", pages.loot, "UIDropDownMenuTemplate")
    lootFontDD:SetPoint("TOPLEFT", lootFontLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(lootFontDD, 220)

    local lootFonts = {}
    if LSM then
      for _, name in ipairs(LSM:List("font")) do
        lootFonts[#lootFonts + 1] = name
      end
      table.sort(lootFonts)
    end

    local function RefreshLootFont()
      UIDropDownMenu_SetSelectedValue(lootFontDD, db.loot.font)
      UIDropDownMenu_SetText(lootFontDD, db.loot.font or "Default")
    end

    UIDropDownMenu_Initialize(lootFontDD, function(self, level)
      if not LSM then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "LibSharedMedia-3.0 not found"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        return
      end

      for _, name in ipairs(lootFonts) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (db.loot.font == name)
        info.func = function()
          db.loot.font = name
          RefreshLootFont()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(lootFontDD, 12, { 0.9, 0.9, 0.9 })
    RefreshLootFont()

    local lootOutlineLabel = pages.loot:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lootOutlineLabel:SetPoint("TOPLEFT", lootFontDD, "BOTTOMLEFT", 16, DROPDOWN_GAP)
    lootOutlineLabel:SetText("Text Outline")
    ApplyUIFont(lootOutlineLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local lootOutlineDD = CreateFrame("Frame", "HarathUI_LootToastsOutlineDropdown", pages.loot, "UIDropDownMenuTemplate")
    lootOutlineDD:SetPoint("TOPLEFT", lootOutlineLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(lootOutlineDD, 180)

    local lootOutlines = {
      { name = "None", value = "NONE" },
      { name = "Outline", value = "OUTLINE" },
      { name = "Thick Outline", value = "THICKOUTLINE" },
      { name = "Mono + Outline", value = "MONOCHROME,OUTLINE" },
      { name = "Mono + Thick", value = "MONOCHROME,THICKOUTLINE" },
    }

    local function RefreshLootOutline()
      UIDropDownMenu_SetSelectedValue(lootOutlineDD, db.loot.fontOutline)
      UIDropDownMenu_SetText(lootOutlineDD, db.loot.fontOutline or "NONE")
    end

    UIDropDownMenu_Initialize(lootOutlineDD, function(self, level)
      for _, o in ipairs(lootOutlines) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = o.name
        info.checked = (db.loot.fontOutline == o.value)
        info.func = function()
          db.loot.fontOutline = o.value
          RefreshLootOutline()
          NS:ApplyAll()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(lootOutlineDD, 12, { 0.9, 0.9, 0.9 })
    RefreshLootOutline()
  end

  -- =========================================================
  -- FRIENDLY NAMEPLATES PAGE
  -- =========================================================
    pages.friendly = CreateFrame("Frame", nil, content); pages.friendly:SetAllPoints(true)
    do
    MakeModuleHeader(pages.friendly, "friendlyplates")

    if not db.friendlyplates.nameColor then
      db.friendlyplates.nameColor = { r = 1, g = 1, b = 1 }
    end
    if not db.friendlyplates.font then
      db.friendlyplates.font = "BigNoodleTilting"
    end
    if db.friendlyplates.classColor == nil then
      db.friendlyplates.classColor = false
    end
    if not db.friendlyplates.fontSize then
      db.friendlyplates.fontSize = 12
    end
    if not db.friendlyplates.fontOutline then
      db.friendlyplates.fontOutline = "NONE"
    end
    if not db.friendlyplates.yOffset then
      db.friendlyplates.yOffset = 0
    end

    local classColor = MakeCheckbox(pages.friendly, "Use Class Color", "Class colors override custom color.")
    classColor:SetPoint("TOPLEFT", 18, FIRST_CONTROL_Y)
    classColor:SetChecked(db.friendlyplates.classColor)
    classColor:SetScript("OnClick", function()
      db.friendlyplates.classColor = classColor:GetChecked()
      NS:ApplyAll()
      if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
        NS.Modules.friendlyplates:Refresh()
      end
    end)


    local function GetNameplateColor()
      return db.friendlyplates.nameColor
    end
    local function SetNameplateColor(r, g, b)
      db.friendlyplates.nameColor = { r = r, g = g, b = b }
      NS:ApplyAll()
      if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
        NS.Modules.friendlyplates:Refresh()
      end
    end
    local colorLabel, colorSwatch = MakeColorSwatch(pages.friendly, "Name Color", GetNameplateColor, SetNameplateColor)
    colorLabel:SetPoint("TOPLEFT", classColor, "BOTTOMLEFT", 0, GROUP_GAP)
    colorSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)

    local size = MakeSlider(pages.friendly, "Size", 8, 24, 1)
    size:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, GROUP_GAP)
    size:SetValue(db.friendlyplates.fontSize or 12)
    size:SetLabelValue(db.friendlyplates.fontSize or 12, "%.0f")
    size:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.friendlyplates.fontSize = v
      size:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
      if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
        NS.Modules.friendlyplates:Refresh()
      end
    end)

    local offset = MakeSlider(pages.friendly, "Y Offset", -30, 30, 1)
    offset:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, SLIDER_GAP)
    offset:SetValue(db.friendlyplates.yOffset or 0)
    offset:SetLabelValue(db.friendlyplates.yOffset or 0, "%.0f")
    offset:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.friendlyplates.yOffset = v
      offset:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
      if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
        NS.Modules.friendlyplates:Refresh()
      end
    end)

    local fontLabel = pages.friendly:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fontLabel:SetPoint("TOPLEFT", offset, "BOTTOMLEFT", 0, GROUP_GAP)
    fontLabel:SetText("Font")
    ApplyUIFont(fontLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local fontDD = CreateFrame("Frame", "HarathUI_FriendlyNameplateFontDropdown", pages.friendly, "UIDropDownMenuTemplate")
    fontDD:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(fontDD, 220)

    local fonts = {}
    if LSM then
      for _, name in ipairs(LSM:List("font")) do
        fonts[#fonts + 1] = name
      end
      table.sort(fonts)
    end

    local function RefreshFont()
      UIDropDownMenu_SetSelectedValue(fontDD, db.friendlyplates.font)
      UIDropDownMenu_SetText(fontDD, db.friendlyplates.font or "Default")
    end

    UIDropDownMenu_Initialize(fontDD, function(self, level)
      if not LSM then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "LibSharedMedia-3.0 not found"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        return
      end

      for _, name in ipairs(fonts) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (db.friendlyplates.font == name)
        info.func = function()
          db.friendlyplates.font = name
          RefreshFont()
          NS:ApplyAll()
          if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
            NS.Modules.friendlyplates:Refresh()
          end
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(fontDD, 12, { 0.9, 0.9, 0.9 })
    RefreshFont()

    local outlineLabel = pages.friendly:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    outlineLabel:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 16, DROPDOWN_GAP)
    outlineLabel:SetText("Outline")
    ApplyUIFont(outlineLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local outlineDD = CreateFrame("Frame", "HarathUI_FriendlyNameplateFontOutlineDropdown", pages.friendly, "UIDropDownMenuTemplate")
    outlineDD:SetPoint("TOPLEFT", outlineLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(outlineDD, 180)

    local outlines = {
      { name = "None", value = "NONE" },
      { name = "Outline", value = "OUTLINE" },
      { name = "Thick Outline", value = "THICKOUTLINE" },
      { name = "Mono + Outline", value = "MONOCHROME,OUTLINE" },
      { name = "Mono + Thick", value = "MONOCHROME,THICKOUTLINE" },
    }

    local function RefreshOutline()
      UIDropDownMenu_SetSelectedValue(outlineDD, db.friendlyplates.fontOutline)
      local label = db.friendlyplates.fontOutline or "NONE"
      UIDropDownMenu_SetText(outlineDD, label)
    end

    UIDropDownMenu_Initialize(outlineDD, function(self, level)
      for _, o in ipairs(outlines) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = o.name
        info.checked = (db.friendlyplates.fontOutline == o.value)
        info.func = function()
          db.friendlyplates.fontOutline = o.value
          RefreshOutline()
          NS:ApplyAll()
          if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
            NS.Modules.friendlyplates:Refresh()
          end
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    ApplyDropdownFont(outlineDD, 12, { 0.9, 0.9, 0.9 })
    RefreshOutline()

  end

  -- =========================================================
  -- ROTATION HELPER PAGE
  -- =========================================================
    pages.rotation = CreateFrame("Frame", nil, content); pages.rotation:SetAllPoints(true)
    do
    MakeModuleHeader(pages.rotation, "rotationhelper")

    if not db.rotationhelper then
      db.rotationhelper = {}
    end
    if db.rotationhelper.scale == nil then
      db.rotationhelper.scale = 1.0
    end
    if db.rotationhelper.width == nil then
      db.rotationhelper.width = 52
    end
    if db.rotationhelper.height == nil then
      db.rotationhelper.height = 52
    end

    local preview = MakeButton(pages.rotation, "Preview", 120, 24)
    preview:SetPoint("TOPLEFT", 18, FIRST_CONTROL_Y)
    preview:SetScript("OnClick", function()
      if NS.Modules and NS.Modules.rotationhelper and NS.Modules.rotationhelper.Preview then
        NS.Modules.rotationhelper:Preview()
      end
    end)

    local scale = MakeSlider(pages.rotation, "Scale", 0.6, 2.0, 0.05)
    scale:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, BUTTON_TO_SLIDER_GAP)
    scale:SetValue(db.rotationhelper.scale or 1.0)
    scale:SetLabelValue(db.rotationhelper.scale or 1.0, "%.2f")
    scale:SetScript("OnValueChanged", function(_, v)
      v = Round2(v)
      db.rotationhelper.scale = v
      scale:SetLabelValue(v, "%.2f")
      NS:ApplyAll()
    end)

    local width = MakeSlider(pages.rotation, "Width", 24, 200, 1)
    width:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, SLIDER_GAP)
    width:SetValue(db.rotationhelper.width or 52)
    width:SetLabelValue(db.rotationhelper.width or 52, "%.0f")
    width:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.rotationhelper.width = v
      width:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
    end)

    local height = MakeSlider(pages.rotation, "Height", 24, 200, 1)
    height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, SLIDER_GAP)
    height:SetValue(db.rotationhelper.height or 52)
    height:SetLabelValue(db.rotationhelper.height or 52, "%.0f")
    height:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v + 0.5)
      db.rotationhelper.height = v
      height:SetLabelValue(v, "%.0f")
      NS:ApplyAll()
    end)
  end

  -- =========================================================
  -- MINIMAP BAR PAGE
  -- =========================================================
    pages.minimap = CreateFrame("Frame", nil, content); pages.minimap:SetAllPoints(true)
    do
    MakeModuleHeader(pages.minimap, "minimapbar")

    if db.minimapbar.locked == nil then
      db.minimapbar.locked = false
    end
    if not db.minimapbar.orientation then
      db.minimapbar.orientation = "VERTICAL"
    end

    local lockCB = MakeCheckbox(pages.minimap, "Lock Bar", "Prevents dragging the minimap bar.")
    lockCB:SetPoint("TOPLEFT", 18, FIRST_CONTROL_Y)
    lockCB:SetChecked(db.minimapbar.locked == true)
    lockCB:SetScript("OnClick", function()
      db.minimapbar.locked = lockCB:GetChecked()
      if NS.Modules and NS.Modules.minimapbar and NS.Modules.minimapbar.SetLocked then
        NS.Modules.minimapbar:SetLocked(db.minimapbar.locked, true)
      end
    end)

    if db.minimapbar.popoutAlpha == nil then
      db.minimapbar.popoutAlpha = 0.85
    end
    local alpha = MakeSlider(pages.minimap, "Popout Opacity", 0.2, 1.0, 0.05)
    alpha:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 0, GROUP_GAP)
    alpha:SetValue(db.minimapbar.popoutAlpha or 0.85)
    alpha:SetLabelValue(db.minimapbar.popoutAlpha or 0.85, "%.2f")
    alpha:SetScript("OnValueChanged", function(_, v)
      v = Round2(v)
      db.minimapbar.popoutAlpha = v
      alpha:SetLabelValue(v, "%.2f")
      if NS.Modules and NS.Modules.minimapbar then
        if NS.Modules.minimapbar.ApplyPopoutAlpha then
          NS.Modules.minimapbar:ApplyPopoutAlpha()
        else
          NS:ApplyAll()
        end
      else
        NS:ApplyAll()
      end
    end)

    if db.minimapbar.popoutStay == nil then
      db.minimapbar.popoutStay = 2.0
    end
    local stay = MakeSlider(pages.minimap, "Popout Visibility (sec)", 1, 10, 0.5)
    stay:SetPoint("TOPLEFT", alpha, "BOTTOMLEFT", 0, SLIDER_GAP)
    stay:SetValue(db.minimapbar.popoutStay or 2.0)
    stay:SetLabelValue(db.minimapbar.popoutStay or 2.0, "%.1f")
    stay:SetScript("OnValueChanged", function(_, v)
      v = Round2(v)
      db.minimapbar.popoutStay = v
      stay:SetLabelValue(v, "%.1f")
    end)

  end

  -- =========================================================
  -- NAVIGATION MENU
  -- =========================================================
    local navItems = {
    { key="general", label="General" },
    { key="xp",      label="XP / Rep Bar" },
    { key="cast",    label="Cast Bar" },
    { key="charsheet", label="Character Sheet" },
    { key="friendly", label="Friendly Nameplates" },
    { key="rotation", label="Rotation Helper" },
    { key="minimap", label="Minimap Bar" },
    { key="loot",    label="Loot Toasts" },
    }

    local navKeyToDb = {
      general = "general",
      xp = "xpbar",
      cast = "castbar",
      charsheet = "charsheet",
      friendly = "friendlyplates",
      rotation = "rotationhelper",
      minimap = "minimapbar",
      loot = "loot",
    }

    local function IsNavEnabled(key)
      local dbKey = navKeyToDb[key]
      if not dbKey then return nil end
      if dbKey == "general" then
        return db.general and db.general.enabled ~= false
      end
      return db[dbKey] and db[dbKey].enabled ~= false
    end

    local y = -92
    for _, it in ipairs(navItems) do
      local b = CreateFrame("Button", nil, nav, "BackdropTemplate")
      b:SetSize(186, 28)
      b:SetPoint("TOPLEFT", 7, y)

      -- Backdrop for button
      b:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
      })
      b:SetBackdropColor(0, 0, 0, 0)
      b:SetBackdropBorderColor(0, 0, 0, 0)

      -- Left orange accent (hidden by default)
      b.accent = b:CreateTexture(nil, "OVERLAY")
      b.accent:SetPoint("TOPLEFT", 0, 0)
      b.accent:SetPoint("BOTTOMLEFT", 0, 0)
      b.accent:SetWidth(3)
      b.accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 1)
      b.accent:Hide()
      RegisterTheme(function(c)
        if b.accent and b.accent.SetColorTexture then
          b.accent:SetColorTexture(c[1], c[2], c[3], 1)
        end
      end)

      b.indicator = b:CreateTexture(nil, "OVERLAY")
      b.indicator:SetSize(10, 10)
      b.indicator:SetPoint("LEFT", 10, 0)

      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.label:SetPoint("LEFT", b.indicator, "RIGHT", 6, 0)
      b.label:SetText(it.label)
      b.label:SetTextColor(0.85, 0.85, 0.85)
      ApplyUIFont(b.label, 13, "OUTLINE", { 0.85, 0.85, 0.85 })
      b._key = it.key
      b:SetScript("OnEnter", function(self)
        if self._huiSelected then return end
        self:SetBackdropColor(0.2, 0.2, 0.22, 0.5)
        self.label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
      end)
      b:SetScript("OnLeave", function(self)
        if self._huiSelected then return end
        self:SetBackdropColor(0, 0, 0, 0)
        self.label:SetTextColor(0.85, 0.85, 0.85)
      end)
      y = y - 32
      b:SetScript("OnClick", function()
        ShowPage(it.key)
        for _, btn in ipairs(nav._huiButtons or {}) do
          btn._huiSelected = (btn._key == it.key)
          if btn._huiSelected then
            btn:SetBackdropColor(0.2, 0.2, 0.22, 0.7)
            btn:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.4)
            btn.label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
            btn.accent:Show()
          else
            btn:SetBackdropColor(0, 0, 0, 0)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            btn.label:SetTextColor(0.85, 0.85, 0.85)
            btn.accent:Hide()
          end
        end
      end)
      nav._huiButtons = nav._huiButtons or {}
      table.insert(nav._huiButtons, b)
    end

    UpdateNavIndicators = function()
      if not nav._huiButtons then return end
      for _, btn in ipairs(nav._huiButtons) do
        local enabled = IsNavEnabled(btn._key)
        if enabled == nil then
          btn.indicator:Hide()
        else
          btn.indicator:Show()
          btn.indicator:SetTexture(enabled and "Interface\\FriendsFrame\\StatusIcon-Online"
            or "Interface\\FriendsFrame\\StatusIcon-Offline")
        end
      end
      UpdateVersionIndicator()
    end

    UpdateNavIndicators()

    ShowPage("general")
    if nav._huiButtons then
      for _, btn in ipairs(nav._huiButtons) do
        if btn._key == "general" then
          btn._huiSelected = true
          btn:SetBackdropColor(0.2, 0.2, 0.22, 0.7)
          btn:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.4)
          btn.label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
          btn.accent:Show()
        end
      end
    end

    RegisterTheme(function(c)
      if not nav._huiButtons then return end
      for _, btn in ipairs(nav._huiButtons) do
        if btn._huiSelected then
          btn:SetBackdropBorderColor(c[1], c[2], c[3], 0.4)
          btn.label:SetTextColor(c[1], c[2], c[3])
        end
      end
    end)

    panel.refresh = function()
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end
  end

  -- =========================================================
  -- POPOUT WINDOW
  -- =========================================================
  local window = CreateFrame("Frame", "HaraUIOptionsWindow", UIParent, "BackdropTemplate")
  window:SetSize(900, 620)
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
        SetUIFont(fs, meta.size, meta.outline, meta.color)
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

