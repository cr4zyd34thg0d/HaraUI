local ADDON, NS = ...

local Theme = NS.OptionsTheme or {}
local ORANGE = Theme.ORANGE
local ORANGE_SIZE = Theme.ORANGE_SIZE
local RegisterTheme = Theme.RegisterTheme
local ApplyUIFont = Theme.ApplyUIFont

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

local function MakeGlassCard(parent, title)
  local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  card:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  card:SetBackdropColor(0, 0, 0, 0.58)
  card:SetBackdropBorderColor(0.58, 0.60, 0.70, 0.22)

  card.bgGradient = card:CreateTexture(nil, "BACKGROUND")
  card.bgGradient:SetPoint("TOPLEFT", 1, -1)
  card.bgGradient:SetPoint("BOTTOMRIGHT", -1, 1)
  card.bgGradient:SetTexture("Interface/Buttons/WHITE8x8")
  -- Reverse of the options panel gradient: purple at top -> black at bottom.
  if card.bgGradient.SetGradient and CreateColor then
    card.bgGradient:SetGradient(
      "VERTICAL",
      CreateColor(0.08, 0.02, 0.12, 0.46),
      CreateColor(0, 0, 0, 0.62)
    )
  elseif card.bgGradient.SetGradientAlpha then
    card.bgGradient:SetGradientAlpha("VERTICAL", 0.08, 0.02, 0.12, 0.46, 0, 0, 0, 0.62)
  else
    card.bgGradient:SetColorTexture(0.08, 0.02, 0.12, 0.40)
  end

  card.innerTop = card:CreateTexture(nil, "ARTWORK")
  card.innerTop:SetPoint("TOPLEFT", 1, -1)
  card.innerTop:SetPoint("TOPRIGHT", -1, -1)
  card.innerTop:SetHeight(1)
  card.innerTop:SetColorTexture(1, 1, 1, 0.08)

  card.innerBottom = card:CreateTexture(nil, "ARTWORK")
  card.innerBottom:SetPoint("BOTTOMLEFT", 1, 1)
  card.innerBottom:SetPoint("BOTTOMRIGHT", -1, 1)
  card.innerBottom:SetHeight(1)
  card.innerBottom:SetColorTexture(0, 0, 0, 0.30)

  if title and title ~= "" then
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 12, -10)
    card.title:SetText(title)
    ApplyUIFont(card.title, ORANGE_SIZE, "OUTLINE", ORANGE)
  end

  card.content = CreateFrame("Frame", nil, card)
  card.content:SetPoint("TOPLEFT", 12, (card.title and -30) or -12)
  card.content:SetPoint("BOTTOMRIGHT", -12, 12)
  card.content:SetFrameLevel(card:GetFrameLevel() + 1)

  return card
end

local function MakeAccentDivider(parent)
  local line = CreateFrame("Frame", nil, parent)
  line:SetHeight(2)

  line.base = line:CreateTexture(nil, "ARTWORK")
  line.base:SetPoint("TOPLEFT", 0, 0)
  line.base:SetPoint("TOPRIGHT", 0, 0)
  line.base:SetHeight(1)
  line.base:SetColorTexture(1, 1, 1, 0.10)

  line.accent = line:CreateTexture(nil, "OVERLAY")
  line.accent:SetPoint("BOTTOMLEFT", 0, 0)
  line.accent:SetPoint("BOTTOMRIGHT", 0, 0)
  line.accent:SetHeight(1)
  line.accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.40)
  RegisterTheme(function(c)
    if line.accent and line.accent.SetColorTexture then
      line.accent:SetColorTexture(c[1], c[2], c[3], 0.40)
    end
  end)

  return line
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

local function ApplyToggleSkin(cb)
  if not cb or cb._huiToggleSkinned then return cb end
  cb._huiToggleSkinned = true

  local normal = cb.GetNormalTexture and cb:GetNormalTexture() or nil
  local pushed = cb.GetPushedTexture and cb:GetPushedTexture() or nil
  local highlight = cb.GetHighlightTexture and cb:GetHighlightTexture() or nil
  local checked = cb.GetCheckedTexture and cb:GetCheckedTexture() or nil
  local disabledChecked = cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture() or nil
  local disabled = cb.GetDisabledTexture and cb:GetDisabledTexture() or nil

  if normal then normal:SetAlpha(0) end
  if pushed then pushed:SetAlpha(0) end
  if highlight then highlight:SetAlpha(0) end
  if checked then checked:SetAlpha(0) end
  if disabledChecked then disabledChecked:SetAlpha(0) end
  if disabled then disabled:SetAlpha(0) end

  local toggle = CreateFrame("Frame", nil, cb, "BackdropTemplate")
  toggle:SetPoint("LEFT", cb, "LEFT", 0, 0)
  toggle:SetSize(36, 18)
  toggle:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  toggle:SetFrameLevel(cb:GetFrameLevel() + 1)

  toggle.fill = toggle:CreateTexture(nil, "ARTWORK")
  toggle.fill:SetPoint("TOPLEFT", 1, -1)
  toggle.fill:SetPoint("BOTTOMRIGHT", -1, 1)
  toggle.fill:SetTexture("Interface/Buttons/WHITE8x8")

  toggle.knob = toggle:CreateTexture(nil, "OVERLAY")
  toggle.knob:SetSize(12, 12)
  toggle.knob:SetTexture("Interface/Buttons/WHITE8x8")
  toggle.knob:SetColorTexture(0.96, 0.96, 0.98, 1)

  cb._huiToggle = toggle

  if cb.Text then
    cb.Text:ClearAllPoints()
    cb.Text:SetPoint("LEFT", toggle, "RIGHT", 8, 0)
    cb.Text:SetJustifyH("LEFT")
    ApplyUIFont(cb.Text, 12, "OUTLINE", { 0.95, 0.95, 0.95 })
  end

  local function Refresh()
    local isChecked = cb:GetChecked()
    if isChecked then
      toggle:SetBackdropColor(0.14, 0.12, 0.09, 0.96)
      toggle:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.90)
      toggle.fill:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.26)
      toggle.knob:ClearAllPoints()
      toggle.knob:SetPoint("RIGHT", toggle, "RIGHT", -3, 0)
    else
      toggle:SetBackdropColor(0.10, 0.11, 0.13, 0.96)
      toggle:SetBackdropBorderColor(0.52, 0.54, 0.60, 0.35)
      toggle.fill:SetColorTexture(0.28, 0.30, 0.36, 0.18)
      toggle.knob:ClearAllPoints()
      toggle.knob:SetPoint("LEFT", toggle, "LEFT", 3, 0)
    end

    if cb:IsEnabled() then
      toggle:SetAlpha(1)
    else
      toggle:SetAlpha(0.5)
    end
  end

  RegisterTheme(function()
    Refresh()
  end)

  cb:HookScript("OnClick", Refresh)
  cb:HookScript("OnShow", Refresh)
  if cb.HasScript and cb:HasScript("OnEnable") then
    cb:HookScript("OnEnable", Refresh)
  end
  if cb.HasScript and cb:HasScript("OnDisable") then
    cb:HookScript("OnDisable", Refresh)
  end
  cb:HookScript("OnEnter", function()
    if not cb:GetChecked() then
      toggle:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.65)
    end
  end)
  cb:HookScript("OnLeave", Refresh)

  Refresh()
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

local function MakeValueChip(parent, width, height)
  local chip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  chip:SetSize(width or 50, height or 20)
  chip:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  chip:SetBackdropColor(0.08, 0.09, 0.11, 0.92)
  chip:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.45)

  chip.shine = chip:CreateTexture(nil, "ARTWORK")
  chip.shine:SetPoint("TOPLEFT", 1, -1)
  chip.shine:SetPoint("TOPRIGHT", -1, -1)
  chip.shine:SetHeight((height or 20) * 0.48)
  chip.shine:SetTexture("Interface/Buttons/WHITE8x8")
  if chip.shine.SetGradientAlpha then
    chip.shine:SetGradientAlpha("VERTICAL", 1, 1, 1, 0.10, 1, 1, 1, 0.00)
  else
    chip.shine:SetColorTexture(1, 1, 1, 0.05)
  end

  chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  chip.text:SetPoint("CENTER", 0, 0)
  ApplyUIFont(chip.text, 11, "OUTLINE", { 0.92, 0.92, 0.94 })

  function chip:SetValue(v, fmt)
    if type(v) == "number" and fmt then
      self.text:SetText(string.format(fmt, v))
    else
      self.text:SetText(tostring(v))
    end
  end

  RegisterTheme(function(c)
    if chip and chip.SetBackdropBorderColor then
      chip:SetBackdropBorderColor(c[1], c[2], c[3], 0.45)
    end
  end)

  return chip
end

NS.OptionsWidgets = NS.OptionsWidgets or {}
NS.OptionsWidgets.ApplyDarkBackdrop = ApplyDarkBackdrop
NS.OptionsWidgets.MakeSection = MakeSection
NS.OptionsWidgets.MakeGlassCard = MakeGlassCard
NS.OptionsWidgets.MakeAccentDivider = MakeAccentDivider
NS.OptionsWidgets.Title = Title
NS.OptionsWidgets.Small = Small
NS.OptionsWidgets.MakeButton = MakeButton
NS.OptionsWidgets.MakeCheckbox = MakeCheckbox
NS.OptionsWidgets.ApplyToggleSkin = ApplyToggleSkin
NS.OptionsWidgets.MakeSlider = MakeSlider
NS.OptionsWidgets.Round2 = Round2
NS.OptionsWidgets.OpenColorPickerRGB = OpenColorPickerRGB
NS.OptionsWidgets.MakeColorSwatch = MakeColorSwatch
NS.OptionsWidgets.MakeValueChip = MakeValueChip
