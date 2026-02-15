local ADDON, NS = ...

local ORANGE = { 0.949, 0.431, 0.031 } -- #F26E08
local ORANGE_SIZE = 11

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

local function GetUIFontPath()
  if NS and NS.GetDefaultFontPath then
    return NS:GetDefaultFontPath()
  end
  return STANDARD_TEXT_FONT
end

local function SetUIFont(fs, size, _, color)
  if not fs then return end
  local path = GetUIFontPath()
  if path then
    local flags = (NS and NS.GetDefaultFontFlags and NS:GetDefaultFontFlags()) or "OUTLINE"
    fs:SetFont(path, size or 12, flags)
  end
  if color then
    fs:SetTextColor(color[1], color[2], color[3])
  end
end

local function ApplyUIFont(fs, size, outline, color)
  if not fs then return end
  SetUIFont(fs, size, outline, color)
  -- Track font objects so the options UI can re-apply font styles after theme updates.
  NS._huiFontRegistry = NS._huiFontRegistry or {}
  NS._huiFontRegistry[fs] = { size = size, color = color }
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

NS.OptionsTheme = NS.OptionsTheme or {}
NS.OptionsTheme.ORANGE = ORANGE
NS.OptionsTheme.ORANGE_SIZE = ORANGE_SIZE
NS.OptionsTheme.RegisterTheme = RegisterTheme
NS.OptionsTheme.ApplyThemeToRegistry = ApplyThemeToRegistry
NS.OptionsTheme.SetThemeColor = SetThemeColor
NS.OptionsTheme.GetUIFontPath = GetUIFontPath
NS.OptionsTheme.SetUIFont = SetUIFont
NS.OptionsTheme.ApplyUIFont = ApplyUIFont
NS.OptionsTheme.ApplyDropdownFont = ApplyDropdownFont
NS.OptionsTheme.RightAlignDropdownText = RightAlignDropdownText
