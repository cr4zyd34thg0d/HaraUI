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

NS.OptionsWidgets = NS.OptionsWidgets or {}
NS.OptionsWidgets.ApplyDarkBackdrop = ApplyDarkBackdrop
NS.OptionsWidgets.MakeSection = MakeSection
NS.OptionsWidgets.Title = Title
NS.OptionsWidgets.Small = Small
NS.OptionsWidgets.MakeButton = MakeButton
NS.OptionsWidgets.MakeCheckbox = MakeCheckbox
NS.OptionsWidgets.MakeSlider = MakeSlider
NS.OptionsWidgets.Round2 = Round2
NS.OptionsWidgets.OpenColorPickerRGB = OpenColorPickerRGB
NS.OptionsWidgets.MakeColorSwatch = MakeColorSwatch
