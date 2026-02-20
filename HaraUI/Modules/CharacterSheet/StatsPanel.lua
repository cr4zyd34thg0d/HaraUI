local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.StatsPanel = CS.StatsPanel or {}
local StatsPanel = CS.StatsPanel

local Skin, CFG -- resolved lazily

local MODE_LABELS = { stats = "Stats", titles = "Titles", equipment = "Equip" }

local EQUIPMENT_ROW_COUNT = 10
local EQUIPMENT_ROW_HEIGHT = 30
local EQUIPMENT_ROW_GAP = 4
local EQUIPMENT_ROW_START_Y = -70
local EQUIPMENT_LIST_TOP_GAP = 4
local EQUIPMENT_ACTION_BUTTON_WIDTH = 48
local EQUIPMENT_ACTION_BUTTON_HEIGHT = 20
local EQUIPMENT_ACTION_BUTTON_GAP = 6
local UPDATE_THROTTLE_INTERVAL = 0.06
local RESYNC_SETTLE_DELAY = 0.15
local TITLE_RESYNC_RETRY_DELAYS = { 0, RESYNC_SETTLE_DELAY, 0.35, 0.75 }
local SIDEBAR_TOP_INSET = 8
local MODEBAR_TOP_INSET = 6

StatsPanel._state = StatsPanel._state or {
  parent = nil,
  root = nil,
  created = false,
  mode = "stats",
  -- TopInfo
  topInfo = nil,
  -- 5 section frames
  sections = nil,
  -- mode bar
  buttons = nil,
  -- Equipment sets
  equipmentFrame = nil,
  equipmentRows = nil,
  equipmentActionButtons = nil,
  equipmentRowsData = nil,
  equipmentOffset = 0,
  selectedSetID = nil,
  equipmentFeedbackToken = 0,
  equipmentActionFeedback = nil,
  -- Titles
  titlesFrame = nil,
  titlesRows = nil,
  titlesRowsData = nil,
  titlesOffset = 0,
  titleResyncToken = 0,
  pendingTitleID = nil,
  -- hooks/events
  eventFrame = nil,
}

local function EnsureSkin()
  if not Skin then
    Skin = CS and CS.Skin or nil
    CFG = Skin and Skin.CFG or nil
  end
  return Skin ~= nil
end

local function IsNativeCurrencyMode()
  local pm = CS and CS.PaneManager or nil
  return pm ~= nil and pm:IsNativeCurrencyMode()
end

local function EnsureState(self)
  local s = self._state
  s.sections = s.sections or {}
  s.buttons = s.buttons or {}
  s.equipmentRows = s.equipmentRows or {}
  s.equipmentActionButtons = s.equipmentActionButtons or {}
  s.equipmentRowsData = s.equipmentRowsData or {}
  s.equipmentOffset = tonumber(s.equipmentOffset) or 0
  if s.equipmentOffset < 0 then s.equipmentOffset = 0 end
  s.titlesRows = s.titlesRows or {}
  s.titlesRowsData = s.titlesRowsData or {}
  s.titlesOffset = tonumber(s.titlesOffset) or 0
  if s.titlesOffset < 0 then s.titlesOffset = 0 end
  s.titleResyncToken = tonumber(s.titleResyncToken) or 0
  if type(s.pendingTitleID) ~= "number" then s.pendingTitleID = nil end
  if type(s.mode) ~= "string" or not MODE_LABELS[s.mode] then
    s.mode = "stats"
  end
  return s
end

local function ResolveParent()
  local fState = CS and CS.FrameFactory and CS.FrameFactory._state or nil
  local panels = fState and fState.panels or nil
  if panels and panels.rightTop then return panels.rightTop end
  return CharacterFrame
end

local function GetCharSheetDB()
  local db = nil
  if NS and NS.GetDB then
    db = NS:GetDB()
  elseif NS then
    db = NS.db
  end
  if type(db) ~= "table" then
    return nil
  end
  if type(db.charsheet) ~= "table" then
    db.charsheet = {}
  end
  return db.charsheet
end

local function IsMythicPanelPreferenceEnabled()
  local csdb = GetCharSheetDB()
  if type(csdb) ~= "table" then
    return true
  end
  return csdb.showRightPanel ~= false
end

local function SetMythicPanelPreferenceEnabled(enabled)
  local csdb = GetCharSheetDB()
  if type(csdb) == "table" then
    csdb.showRightPanel = enabled and true or false
  end
end

local function IsPortalPanelPreferenceEnabled()
  local csdb = GetCharSheetDB()
  if type(csdb) ~= "table" then
    return false
  end
  return csdb.showPortalPanel == true
end

local function SetPortalPanelPreferenceEnabled(enabled)
  local csdb = GetCharSheetDB()
  if type(csdb) == "table" then
    csdb.showPortalPanel = enabled and true or false
  end
end

local function ApplyMythicPanelPreference()
  local rp = CS and CS.MythicPanel or nil
  local rpRoot = rp and rp._state and rp._state.root or nil
  local shouldShow = IsMythicPanelPreferenceEnabled()
  if not rpRoot then
    return shouldShow
  end
  if shouldShow then
    if rpRoot.Show then rpRoot:Show() end
  else
    if rpRoot.Hide then rpRoot:Hide() end
  end
  return shouldShow
end

local function SuppressBlizzardStatsPane()
  local pane = _G and _G.CharacterStatsPane or nil
  if not pane then return end
  if pane.SetAlpha then pane:SetAlpha(0) end
  if pane.SetShown then
    pane:SetShown(false)
  elseif pane.Hide then
    pane:Hide()
  end
  if pane.EnableMouse then pane:EnableMouse(false) end
  if pane.SetMouseClickEnabled then pane:SetMouseClickEnabled(false) end
  if pane.SetMouseMotionEnabled then pane:SetMouseMotionEnabled(false) end
end

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------
local function FormatNumber(value)
  local n = tonumber(value) or 0
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(n + 0.5)) end
  return tostring(math.floor(n + 0.5))
end

local function FormatPercent(value)
  return ("%.2f%%"):format(tonumber(value) or 0)
end

---------------------------------------------------------------------------
-- StatTooltipBridge: show native Blizzard stat tooltips on hover
---------------------------------------------------------------------------
local STAT_TOOLTIP_SETTERS = {
  ["criticalstrike"]      = "PaperDollFrame_SetCritChance",
  ["criticalstrikechance"]= "PaperDollFrame_SetCritChance",
  ["health"]              = "PaperDollFrame_SetHealth",
  ["power"]               = "PaperDollFrame_SetPower",
  ["itemlevel"]           = "PaperDollFrame_SetItemLevel",
  ["averageitemlevel"]    = "PaperDollFrame_SetItemLevel",
  ["haste"]               = "PaperDollFrame_SetHaste",
  ["mastery"]             = "PaperDollFrame_SetMastery",
  ["versatility"]         = "PaperDollFrame_SetVersatility",
  ["attackpower"]         = "PaperDollFrame_SetAttackPower",
  ["attackspeed"]         = "PaperDollFrame_SetAttackSpeed",
  ["mainhandspeed"]       = "PaperDollFrame_SetAttackSpeed",
  ["spellpower"]          = "PaperDollFrame_SetSpellPower",
  ["armor"]               = "PaperDollFrame_SetArmor",
  ["dodge"]               = "PaperDollFrame_SetDodge",
  ["parry"]               = "PaperDollFrame_SetParry",
  ["block"]               = "PaperDollFrame_SetBlock",
  ["stagger"]             = "PaperDollFrame_SetStagger",
  ["leech"]               = "PaperDollFrame_SetLifesteal",
  ["lifesteal"]           = "PaperDollFrame_SetLifesteal",
  ["avoidance"]           = "PaperDollFrame_SetAvoidance",
  ["speed"]               = "PaperDollFrame_SetSpeed",
  ["movementspeed"]       = "PaperDollFrame_SetMovementSpeed",
}

local STAT_TOOLTIP_PRIMARY_INDICES = {
  ["strength"]  = 1, -- LE_UNIT_STAT_STRENGTH
  ["agility"]   = 2, -- LE_UNIT_STAT_AGILITY
  ["stamina"]   = 3, -- LE_UNIT_STAT_STAMINA
  ["intellect"] = 4, -- LE_UNIT_STAT_INTELLECT
}

local StatTooltipBridge = { scratch = nil }

local function NormalizeTooltipText(text)
  if type(text) ~= "string" then return "" end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", ""):gsub("|T.-|t", "")
  return text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function CanonicalLabel(text)
  return NormalizeTooltipText(text):lower():gsub("[^%w]+", "")
end

local function AnchorTooltipAtMouse(offsetX, offsetY)
  if not GameTooltip or not GameTooltip:IsShown() then return end
  if type(GetCursorPosition) ~= "function" then return end
  local parent = UIParent or CharacterFrame
  if not parent then return end
  local x, y = GetCursorPosition()
  local scale = parent:GetEffectiveScale() or 1
  x = x / scale
  y = y / scale
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x + (offsetX or 14), y + (offsetY or 14))
end

function StatTooltipBridge.ResolveSetter(label)
  local key = CanonicalLabel(label)
  if key == "" then return nil, nil end
  if key == "gcd" or key == "globalcooldown" or key == "globalcooldownreduction" then
    return "__CUSTOM_GCD", nil
  end
  local statIndex = STAT_TOOLTIP_PRIMARY_INDICES[key]
  if statIndex then return "PaperDollFrame_SetStat", statIndex end
  local setterName = STAT_TOOLTIP_SETTERS[key]
  if key == "movementspeed" and type(_G.PaperDollFrame_SetMovementSpeed) ~= "function" then
    setterName = "PaperDollFrame_SetSpeed"
  end
  if type(setterName) == "string" and type(_G[setterName]) == "function" then
    return setterName, nil
  end
  return nil, nil
end

function StatTooltipBridge.EnsureScratchFrame()
  if StatTooltipBridge.scratch then return StatTooltipBridge.scratch end
  local parent = UIParent or CharacterFrame
  if not parent then return nil end
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(1, 1)
  frame:EnableMouse(false)
  frame:SetAlpha(0)
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", -10000, 10000)
  frame:Hide()
  frame.Label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.Value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.Label:SetPoint("LEFT", frame, "LEFT", 0, 0)
  frame.Value:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
  StatTooltipBridge.scratch = frame
  return frame
end

function StatTooltipBridge.BuildScratchStatFrame(label)
  local setterName, statIndex = StatTooltipBridge.ResolveSetter(label)
  if not setterName then return nil end
  local frame = StatTooltipBridge.EnsureScratchFrame()
  if not frame then return nil end

  frame.tooltip = nil
  frame.tooltip2 = nil
  frame.tooltip3 = nil
  frame.onEnterFunc = nil
  frame.UpdateTooltip = nil
  frame.numericValue = nil

  if setterName == "__CUSTOM_GCD" then
    local gcdValue = 1.0
    if C_Spell and C_Spell.GetSpellCooldown then
      local cd = C_Spell.GetSpellCooldown(61304)
      if type(cd) == "table" and type(cd.duration) == "number" and cd.duration > 0 then
        gcdValue = cd.duration
      end
    end
    local haste = GetHaste and GetHaste() or 0
    local gcdLabel = GLOBAL_COOLDOWN_ABBR or GLOBAL_COOLDOWN or "Global Cooldown"
    frame.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, gcdLabel) .. " " .. ("%.2fs"):format(gcdValue) .. FONT_COLOR_CODE_CLOSE
    frame.tooltip2 = ("Time between ability uses. Current haste: %.2f%%."):format(haste)
    frame.tooltip3 = "Haste reduces global cooldown to your class minimum."
    return frame
  end

  local setter = _G[setterName]
  if type(setter) ~= "function" then return nil end
  local ok
  if statIndex then
    ok = pcall(setter, frame, "player", statIndex)
  else
    ok = pcall(setter, frame, "player")
  end
  if not ok then return nil end
  return frame
end

function StatTooltipBridge.HandleEnter(row)
  if not row then return end
  if GameTooltip and GameTooltip:IsShown() then GameTooltip:Hide() end

  local source = StatTooltipBridge.BuildScratchStatFrame(row._tooltipKey or row._tooltipLabel)
  if not source then
    -- Fallback: simple tooltip
    if GameTooltip then
      local label = NormalizeTooltipText(row._tooltipLabel or "")
      local value = NormalizeTooltipText(row._tooltipValue or "")
      if label ~= "" or value ~= "" then
        GameTooltip:SetOwner(row, "ANCHOR_NONE")
        GameTooltip:ClearLines()
        if label ~= "" then GameTooltip:AddLine(label, 1, 1, 1) end
        if value ~= "" then GameTooltip:AddLine(value, 0.9, 0.9, 0.9) end
        GameTooltip:Show()
        AnchorTooltipAtMouse()
      end
    end
    return
  end

  local handled = false
  if type(source.onEnterFunc) == "function" then
    local ok = pcall(source.onEnterFunc, source)
    handled = ok and GameTooltip and GameTooltip:IsShown()
    if handled then AnchorTooltipAtMouse() end
  end
  if not handled and type(PaperDollStatTooltip) == "function" and (source.tooltip or source.tooltip2) then
    local ok = pcall(PaperDollStatTooltip, source)
    handled = ok and GameTooltip and GameTooltip:IsShown()
    if handled then AnchorTooltipAtMouse() end
  end
  if not handled and GameTooltip and (source.tooltip or source.tooltip2) then
    local nfc = NORMAL_FONT_COLOR or { r = 0.9, g = 0.9, b = 0.9 }
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    if source.tooltip and source.tooltip ~= "" then GameTooltip:SetText(source.tooltip) end
    if source.tooltip2 and source.tooltip2 ~= "" then GameTooltip:AddLine(source.tooltip2, nfc.r, nfc.g, nfc.b, true) end
    if source.tooltip3 and source.tooltip3 ~= "" then GameTooltip:AddLine(source.tooltip3, nfc.r, nfc.g, nfc.b, true) end
    GameTooltip:Show()
    AnchorTooltipAtMouse()
  end
end

function StatTooltipBridge.HandleLeave()
  if GameTooltip and GameTooltip:IsShown() then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Data builder: 5 sections with stat rows
---------------------------------------------------------------------------
local function BuildSectionsData()
  -- Primary stat
  local primaryLabel, primaryValue = "Primary", 0
  if GetSpecialization and GetSpecializationInfo then
    local spec = GetSpecialization()
    if spec then
      local _, _, _, _, _, statID = GetSpecializationInfo(spec)
      if statID then
        local stat = SPEC_STAT_STRINGS and SPEC_STAT_STRINGS[statID]
        if type(stat) == "string" then primaryLabel = stat end
        if UnitStat then
          local _, val = UnitStat("player", statID)
          if type(val) == "number" then primaryValue = val end
        end
      end
    end
  end
  if (primaryLabel == "Primary" or primaryValue == 0) and UnitStat then
    -- Use class-based primary stat detection instead of picking the highest value
    local PRIMARY_STAT_MAP = {
      DEATHKNIGHT = { label = "Strength", index = 1 },
      DEMONHUNTER = { label = "Agility", index = 2 },
      DRUID       = { label = "Agility", index = 2 },
      EVOKER      = { label = "Intellect", index = 4 },
      HUNTER      = { label = "Agility", index = 2 },
      MAGE        = { label = "Intellect", index = 4 },
      MONK        = { label = "Agility", index = 2 },
      PALADIN     = { label = "Strength", index = 1 },
      PRIEST      = { label = "Intellect", index = 4 },
      ROGUE       = { label = "Agility", index = 2 },
      SHAMAN      = { label = "Agility", index = 2 },
      WARLOCK     = { label = "Intellect", index = 4 },
      WARRIOR     = { label = "Strength", index = 1 },
    }
    local _, classTag = UnitClass("player")
    local classMeta = classTag and PRIMARY_STAT_MAP[classTag]
    if classMeta then
      primaryLabel = classMeta.label
      local _, val = UnitStat("player", classMeta.index)
      if type(val) == "number" then primaryValue = val end
    else
      for i = 1, 4 do
        local _, val = UnitStat("player", i)
        if val and val > primaryValue then
          primaryValue = val
          primaryLabel = _G["SPELL_STAT" .. i .. "_NAME"] or primaryLabel
        end
      end
    end
  end

  local stamina = 0
  if UnitStat then
    local _, val = UnitStat("player", LE_UNIT_STAT_STAMINA or 3)
    if type(val) == "number" then stamina = val end
  end
  local effectiveArmor = 0
  if UnitArmor then
    local _, val = UnitArmor("player")
    if type(val) == "number" then effectiveArmor = val end
  end

  local gcdValue = 1.0
  if C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(61304)
    if type(cd) == "table" and type(cd.duration) == "number" and cd.duration > 0 then
      gcdValue = cd.duration
    end
  end

  local apBase, apPos, apNeg = UnitAttackPower and UnitAttackPower("player") or 0, 0, 0
  local attackPower = (apBase or 0) + (apPos or 0) + (apNeg or 0)
  local mhSpeed = UnitAttackSpeed and UnitAttackSpeed("player") or nil
  local spellPower = GetSpellBonusDamage and GetSpellBonusDamage(2) or 0

  local moveSpeed = 0
  if GetUnitSpeed and BASE_MOVEMENT_SPEED then
    moveSpeed = (GetUnitSpeed("player") / BASE_MOVEMENT_SPEED) * 100
  end

  return {
    {
      title = "Attributes",
      rows = {
        { primaryLabel, FormatNumber(primaryValue) },
        { "Stamina", FormatNumber(stamina or 0) },
        { "Armor", FormatNumber(effectiveArmor or 0) },
        { "GCD", ("%.2fs"):format(gcdValue) },
      },
    },
    {
      title = "Secondary",
      rows = {
        { "Critical Strike", FormatPercent(GetCritChance and GetCritChance() or 0) },
        { "Haste", FormatPercent(GetHaste and GetHaste() or 0) },
        { "Mastery", FormatPercent(GetMasteryEffect and GetMasteryEffect() or 0) },
        { "Versatility", FormatPercent(GetCombatRatingBonus and GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE or 29) or 0) },
      },
    },
    {
      title = "Attack",
      rows = {
        { "Attack Power", FormatNumber(attackPower) },
        { "Attack Speed", mhSpeed and ("%.2fs"):format(mhSpeed) or "" },
        { "Spell Power", FormatNumber(spellPower) },
      },
    },
    {
      title = "Defense",
      rows = {
        { "Armor", FormatNumber(effectiveArmor or 0) },
        { "Dodge", FormatPercent(GetDodgeChance and GetDodgeChance() or 0) },
        { "Parry", FormatPercent(GetParryChance and GetParryChance() or 0) },
        { "Block", FormatPercent(GetBlockChance and GetBlockChance() or 0) },
        { "Stagger", FormatPercent((C_PaperDollInfo and C_PaperDollInfo.GetStaggerPercentage and C_PaperDollInfo.GetStaggerPercentage("player")) or 0) },
      },
    },
    {
      title = "General",
      rows = {
        { "Leech", FormatPercent(GetLifesteal and GetLifesteal() or 0) },
        { "Avoidance", FormatPercent(GetAvoidance and GetAvoidance() or 0) },
        { "Speed", FormatPercent(GetSpeed and GetSpeed() or 0) },
        { "Movement Speed", FormatPercent(moveSpeed) },
      },
    },
  }
end

---------------------------------------------------------------------------
-- Frame creation helpers
---------------------------------------------------------------------------
local function CreateTopInfo(parent)
  local ti = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  ti:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  ti:SetBackdropColor(0.02, 0.02, 0.03, 0.75)
  ti:SetBackdropBorderColor(0, 0, 0, 0)
  ti:SetHeight(70)
  ti:EnableMouse(true)

  -- Item level (large purple)
  ti.ilvl = ti:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  ti.ilvl:SetPoint("TOP", ti, "TOP", 0, -4)
  ti.ilvl:SetTextColor(0.73, 0.27, 1.0, 1.0)
  ti.ilvl:SetText("0.00 / 0.00")
  if NS and NS.ApplyDefaultFont then NS:ApplyDefaultFont(ti.ilvl, 16) end

  ti.ilvlHit = CreateFrame("Frame", nil, ti)
  ti.ilvlHit:SetPoint("TOPLEFT", ti, "TOPLEFT", 0, 0)
  ti.ilvlHit:SetPoint("TOPRIGHT", ti, "TOPRIGHT", 0, 0)
  ti.ilvlHit:SetHeight(24)
  ti.ilvlHit:EnableMouse(true)
  ti.ilvlHit:SetScript("OnEnter", function(self) StatTooltipBridge.HandleEnter(self) end)
  ti.ilvlHit:SetScript("OnLeave", function() StatTooltipBridge.HandleLeave() end)

  -- Health row
  ti.healthRow = CreateFrame("Frame", nil, ti)
  ti.healthRow:SetPoint("TOPLEFT", ti, "TOPLEFT", 0, -30)
  ti.healthRow:SetPoint("TOPRIGHT", ti, "TOPRIGHT", 0, -30)
  ti.healthRow:SetHeight(18)
  ti.healthRow:EnableMouse(true)
  ti.healthRow:SetScript("OnEnter", function(self) StatTooltipBridge.HandleEnter(self) end)
  ti.healthRow:SetScript("OnLeave", function() StatTooltipBridge.HandleLeave() end)
  ti.healthRow.bg = ti.healthRow:CreateTexture(nil, "BACKGROUND")
  ti.healthRow.bg:SetAllPoints()
  ti.healthRow.bg:SetTexture("Interface/Buttons/WHITE8x8")
  ti.healthRow.left = ti.healthRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ti.healthRow.left:SetPoint("LEFT", ti.healthRow, "LEFT", 4, 0)
  ti.healthRow.left:SetJustifyH("LEFT")
  ti.healthRow.right = ti.healthRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ti.healthRow.right:SetPoint("RIGHT", ti.healthRow, "RIGHT", -4, 0)
  ti.healthRow.right:SetJustifyH("RIGHT")

  -- Power row
  ti.powerRow = CreateFrame("Frame", nil, ti)
  ti.powerRow:SetPoint("TOPLEFT", ti.healthRow, "BOTTOMLEFT", 0, -2)
  ti.powerRow:SetPoint("TOPRIGHT", ti.healthRow, "BOTTOMRIGHT", 0, -2)
  ti.powerRow:SetHeight(18)
  ti.powerRow:EnableMouse(true)
  ti.powerRow:SetScript("OnEnter", function(self) StatTooltipBridge.HandleEnter(self) end)
  ti.powerRow:SetScript("OnLeave", function() StatTooltipBridge.HandleLeave() end)
  ti.powerRow.bg = ti.powerRow:CreateTexture(nil, "BACKGROUND")
  ti.powerRow.bg:SetAllPoints()
  ti.powerRow.bg:SetTexture("Interface/Buttons/WHITE8x8")
  ti.powerRow.left = ti.powerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ti.powerRow.left:SetPoint("LEFT", ti.powerRow, "LEFT", 4, 0)
  ti.powerRow.left:SetJustifyH("LEFT")
  ti.powerRow.right = ti.powerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ti.powerRow.right:SetPoint("RIGHT", ti.powerRow, "RIGHT", -4, 0)
  ti.powerRow.right:SetJustifyH("RIGHT")

  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(ti.healthRow.left, 11)
    NS:ApplyDefaultFont(ti.healthRow.right, 11)
    NS:ApplyDefaultFont(ti.powerRow.left, 11)
    NS:ApplyDefaultFont(ti.powerRow.right, 11)
  end

  return ti
end

local function CreateSectionFrame(parent, maxRows)
  maxRows = maxRows or 5
  local sec = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  sec:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  sec:SetBackdropColor(0.02, 0.02, 0.03, 0.55)
  sec:SetBackdropBorderColor(0, 0, 0, 0)

  sec.tint = sec:CreateTexture(nil, "BACKGROUND")
  sec.tint:SetDrawLayer("BACKGROUND", 1)
  sec.tint:SetTexture("Interface/Buttons/WHITE8x8")

  sec.headerTint = sec:CreateTexture(nil, "ARTWORK")
  sec.headerTint:SetDrawLayer("ARTWORK", 1)
  sec.headerTint:SetTexture("Interface/Buttons/WHITE8x8")

  sec.title = sec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sec.title:SetPoint("TOP", sec, "TOP", 0, -3)
  sec.title:SetTextColor(1, 1, 1, 1)
  if NS and NS.ApplyDefaultFont then NS:ApplyDefaultFont(sec.title, 11) end

  sec.rows = {}
  for r = 1, maxRows do
    local row = CreateFrame("Frame", nil, sec)
    row:SetHeight(CFG.STAT_ROW_HEIGHT)
    row:EnableMouse(true)
    if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(true) end

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetDrawLayer("ARTWORK", 1)
    row.bg:SetTexture("Interface/Buttons/WHITE8x8")

    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.left:SetJustifyH("LEFT")
    row.left:SetTextColor(0.96, 0.96, 0.96, 1.0)

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetTextColor(0.96, 0.96, 0.96, 1.0)

    if NS and NS.ApplyDefaultFont then
      NS:ApplyDefaultFont(row.left, 10)
      NS:ApplyDefaultFont(row.right, 10)
    end

    row:SetScript("OnEnter", function(self) StatTooltipBridge.HandleEnter(self) end)
    row:SetScript("OnLeave", function() StatTooltipBridge.HandleLeave() end)

    sec.rows[r] = row
  end

  return sec
end

---------------------------------------------------------------------------
-- Sidebar icon helper (from Legacy GetTopSidebarIconData)
---------------------------------------------------------------------------
local function GetTopSidebarIconData(index)
  if index == 1 then
    local _, classTag = UnitClass("player")
    local coords = classTag and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTag] or nil
    if coords then
      return "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
        coords[1], coords[2], coords[3], coords[4]
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark", 0.08, 0.92, 0.08, 0.92
  elseif index == 2 then
    return "Interface\\Icons\\INV_Scroll_03", 0.08, 0.92, 0.08, 0.92
  elseif index == 3 then
    return "Interface\\Icons\\INV_Chest_Plate12", 0.08, 0.92, 0.08, 0.92
  elseif index == 4 then
    return "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 0.0, 1.0, 0.0, 1.0
  elseif index == 5 then
    return "Interface\\Icons\\Spell_Arcane_PortalDalaran", 0.08, 0.92, 0.08, 0.92
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark", 0.08, 0.92, 0.08, 0.92
end

local SIDEBAR_MODE_MAP = { [1] = "stats", [2] = "titles", [3] = "equipment" }
local SIDEBAR_SELECTED_BY_MODE = { stats = 1, titles = 2, equipment = 3 }
local SIDEBAR_TOOLTIPS = {
  [1] = "Character Stats",
  [2] = "Titles",
  [3] = "Equipment Manager",
  [4] = "Toggle Mythic+ Panel",
  [5] = "Toggle Dungeon Portals",
}

local function CreateSidebarButton(parent, index)
  if not EnsureSkin() then return nil end
  local size = CFG.STATS_SIDEBAR_BUTTON_SIZE or 34
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(size, size)
  btn:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  btn:SetBackdropColor(0.03, 0.02, 0.05, 0.92)
  btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
  btn.sidebarIndex = index

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
  btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
  local tex, l, r, t, b = GetTopSidebarIconData(index)
  btn.icon:SetTexture(tex)
  btn.icon:SetTexCoord(l, r, t, b)

  btn:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(SIDEBAR_TOOLTIPS[index] or "", 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  return btn
end

local function UpdateSidebarVisuals(state)
  if not state or not state.sidebarButtons then return end
  local selectedIdx = SIDEBAR_SELECTED_BY_MODE[state.mode] or 0
  for i, btn in ipairs(state.sidebarButtons) do
    if btn and btn.SetBackdropBorderColor then
      if i == selectedIdx then
        btn:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.95)
      elseif i == 4 then
        -- M+ toggle: red when collapsed, purple when expanded
        local rp = CS and CS.MythicPanel or nil
        local rpRoot = rp and rp._state and rp._state.root or nil
        local prefEnabled = IsMythicPanelPreferenceEnabled()
        local shown = prefEnabled and (not rpRoot or (rpRoot.IsShown and rpRoot:IsShown()))
        if shown then
          btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
        else
          btn:SetBackdropBorderColor(0.90, 0.12, 0.12, 0.95)
        end
      elseif i == 5 then
        -- Portal toggle: red when collapsed, purple when expanded
        local pp = CS and CS.PortalPanel or nil
        local ppRoot = pp and pp._state and pp._state.root or nil
        local ppShown = IsPortalPanelPreferenceEnabled() and (not ppRoot or (ppRoot.IsShown and ppRoot:IsShown()))
        if ppShown then
          btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
        else
          btn:SetBackdropBorderColor(0.90, 0.12, 0.12, 0.95)
        end
      else
        btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
      end
    end
  end
end


---------------------------------------------------------------------------
-- Equipment sets (kept from existing impl, minimal changes)
---------------------------------------------------------------------------
local function ResolveEquipmentSetName(setID)
  if not (setID and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo) then return nil end
  local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

local function BuildEquipmentSetsData(selectedSetID)
  local rows = {}
  if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetInfo) then
    return rows, nil
  end
  local active = C_EquipmentSet.GetEquipmentSetForSpec and C_EquipmentSet.GetEquipmentSetForSpec(GetSpecialization and GetSpecialization() or 0) or nil
  local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
  local defaultSelected = nil
  for _, setID in ipairs(ids) do
    local name, icon, _, _, _, _, _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
    if type(name) == "string" and name ~= "" then
      if not defaultSelected and (isEquipped == true or (active and active == setID)) then
        defaultSelected = setID
      end
      rows[#rows + 1] = {
        id = setID,
        label = name,
        detail = (isEquipped == true or (active and active == setID)) and "Active" or "",
        icon = icon or 132627,
      }
    end
  end
  if selectedSetID == nil then selectedSetID = defaultSelected end
  if selectedSetID == nil and rows[1] then selectedSetID = rows[1].id end
  local foundSelected = false
  for _, row in ipairs(rows) do
    if row.id == selectedSetID then foundSelected = true; break end
  end
  if not foundSelected then selectedSetID = defaultSelected or (rows[1] and rows[1].id) or nil end
  for _, row in ipairs(rows) do
    row.selected = (selectedSetID ~= nil and row.id == selectedSetID) or false
    if row.selected and row.detail == "" then row.detail = "Selected" end
  end
  return rows, selectedSetID
end

local function ApplyEquipmentActionButtonStyle(button, styleKey)
  if not button then return end
  local colors = {
    normal   = { bg = { 0.05, 0.02, 0.08, 0.90 }, border = { 0.26, 0.18, 0.36, 0.95 }, text = { 0.95, 0.95, 0.95, 1.0 } },
    hover    = { bg = { 0.08, 0.03, 0.11, 0.94 }, border = { 0.44, 0.28, 0.60, 0.98 }, text = { 1.00, 0.95, 0.85, 1.0 } },
    pressed  = { bg = { 0.12, 0.05, 0.16, 0.98 }, border = { 0.96, 0.64, 0.14, 1.0 }, text = { 1.00, 0.90, 0.70, 1.0 } },
    disabled = { bg = { 0.03, 0.02, 0.05, 0.85 }, border = { 0.14, 0.11, 0.20, 0.88 }, text = { 0.55, 0.55, 0.55, 1.0 } },
    success  = { bg = { 0.08, 0.15, 0.08, 0.98 }, border = { 0.36, 0.92, 0.50, 1.0 }, text = { 0.82, 1.00, 0.88, 1.0 } },
    fail     = { bg = { 0.16, 0.05, 0.05, 0.98 }, border = { 0.94, 0.34, 0.34, 1.0 }, text = { 1.00, 0.76, 0.76, 1.0 } },
  }
  local c = colors[styleKey or "normal"] or colors.normal
  if button.SetBackdropColor then button:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], c.bg[4]) end
  if button.SetBackdropBorderColor then button:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4]) end
  if button.text and button.text.SetTextColor then button.text:SetTextColor(c.text[1], c.text[2], c.text[3], c.text[4]) end
end

local function RefreshEquipmentActionButtonStyle(button)
  if not button then return end
  if button._flashStyle then ApplyEquipmentActionButtonStyle(button, button._flashStyle); return end
  if not (button.IsEnabled and button:IsEnabled()) then ApplyEquipmentActionButtonStyle(button, "disabled"); return end
  if button._isPressed then ApplyEquipmentActionButtonStyle(button, "pressed")
  elseif button._isHover then ApplyEquipmentActionButtonStyle(button, "hover")
  else ApplyEquipmentActionButtonStyle(button, "normal") end
end

local function FlashEquipmentActionButton(button, ok)
  if not button then return end
  button._flashToken = (button._flashToken or 0) + 1
  local token = button._flashToken
  button._flashStyle = ok and "success" or "fail"
  RefreshEquipmentActionButtonStyle(button)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.18, function()
      if not button or button._flashToken ~= token then return end
      button._flashStyle = nil
      RefreshEquipmentActionButtonStyle(button)
    end)
  else
    button._flashStyle = nil
    RefreshEquipmentActionButtonStyle(button)
  end
end

local function CreateEquipmentActionButton(parent, label, xOffset)
  local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
  button:SetSize(EQUIPMENT_ACTION_BUTTON_WIDTH, EQUIPMENT_ACTION_BUTTON_HEIGHT)
  button:SetPoint("LEFT", parent, "LEFT", xOffset, 0)
  button:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  button:SetBackdropColor(0.05, 0.02, 0.08, 0.90)
  button:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.text:SetPoint("CENTER")
  button.text:SetText(label)
  button.text:SetTextColor(0.95, 0.95, 0.95, 1)
  if NS and NS.ApplyDefaultFont then NS:ApplyDefaultFont(button.text, 10) end
  button:SetScript("OnEnter", function(self) self._isHover = true; RefreshEquipmentActionButtonStyle(self) end)
  button:SetScript("OnLeave", function(self) self._isHover = false; self._isPressed = false; RefreshEquipmentActionButtonStyle(self) end)
  button:SetScript("OnMouseDown", function(self) if self.IsEnabled and not self:IsEnabled() then return end; self._isPressed = true; RefreshEquipmentActionButtonStyle(self) end)
  button:SetScript("OnMouseUp", function(self) self._isPressed = false; RefreshEquipmentActionButtonStyle(self) end)
  button:HookScript("OnEnable", function(self) RefreshEquipmentActionButtonStyle(self) end)
  button:HookScript("OnDisable", function(self) RefreshEquipmentActionButtonStyle(self) end)
  RefreshEquipmentActionButtonStyle(button)
  return button
end

local function CreateEquipmentRow(parent)
  local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
  row:SetHeight(EQUIPMENT_ROW_HEIGHT)
  row:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  row:SetBackdropColor(0.04, 0.02, 0.07, 0.65)
  row:SetBackdropBorderColor(0.18, 0.12, 0.26, 0.70)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.icon:SetTexture(134400)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -42, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetTextColor(0.95, 0.95, 0.95, 1)
  row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.detail:SetJustifyH("RIGHT")
  row.detail:SetTextColor(0.95, 0.75, 0.30, 1)
  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(row.label, 11)
    NS:ApplyDefaultFont(row.detail, 10)
  end
  return row
end

local function ShowEquipmentActionFeedback(state, text, ok)
  local fs = state and state.equipmentActionFeedback or nil
  if not fs then return end
  if not text or text == "" then fs:SetText(""); fs:Hide(); return end
  if ok then fs:SetTextColor(0.45, 1.00, 0.62, 1.00)
  else fs:SetTextColor(1.00, 0.55, 0.55, 1.00) end
  fs:SetText(text)
  fs:Show()
  state.equipmentFeedbackToken = (state.equipmentFeedbackToken or 0) + 1
  local token = state.equipmentFeedbackToken
  if C_Timer and C_Timer.After then
    C_Timer.After(1.20, function()
      if not state or state.equipmentFeedbackToken ~= token then return end
      if state.equipmentActionFeedback then state.equipmentActionFeedback:SetText(""); state.equipmentActionFeedback:Hide() end
    end)
  end
end

---------------------------------------------------------------------------
-- Titles
---------------------------------------------------------------------------
local TITLE_ROW_COUNT = 20
local TITLE_ROW_HEIGHT = 26
local TITLE_ROW_GAP = 3
local TITLE_ROW_START_Y = -4

local function BuildContextualTitleText(rawTitle, playerName)
  if type(rawTitle) ~= "string" or rawTitle == "" then
    return ""
  end
  if type(playerName) ~= "string" then
    playerName = ""
  end

  local function TrimText(text)
    if type(text) ~= "string" then
      return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
  end

  local function EnsureNameComma(text)
    if type(text) ~= "string" or text == "" or playerName == "" then
      return text
    end
    local escapedName = playerName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local tail = text:match("^" .. escapedName .. "(.*)$")
    if not tail or tail == "" then
      return text
    end
    if tail:match("^%s*[,%.:;!%?]") then
      return text
    end
    tail = tail:gsub("^%s+", "")
    if tail == "" then
      return text
    end
    return playerName .. ", " .. tail
  end

  local replaced = rawTitle
  local replacedAny = false
  local count = 0
  replaced, count = replaced:gsub("%%(%d+)%$s", playerName)
  if count and count > 0 then
    replacedAny = true
  end
  replaced, count = replaced:gsub("%%s", playerName)
  if count and count > 0 then
    replacedAny = true
  end
  if replacedAny then
    return EnsureNameComma(TrimText(replaced))
  end

  if playerName ~= "" and rawTitle:find(playerName, 1, true) then
    return EnsureNameComma(TrimText(rawTitle))
  end

  local clean = TrimText(rawTitle)
  if clean == "" then
    return ""
  end
  if playerName == "" then
    return clean
  end
  if rawTitle:find("%s$") then
    return rawTitle:gsub("%s+$", " ") .. playerName
  end
  if clean:match("^[,%.:;!%?]") then
    return playerName .. clean
  end
  return playerName .. ", " .. clean
end

local function BuildKnownTitlesData()
  local rows = {}
  if not (GetNumTitles and GetTitleName and IsTitleKnown) then return rows end
  local playerName = UnitName and UnitName("player") or ""
  local current = GetCurrentTitle and GetCurrentTitle() or 0

  rows[#rows + 1] = {
    id = 0,
    label = "No Title",
    detail = (current == 0) and "Active" or "",
    selected = (current == 0),
    icon = 133742,
  }

  local total = GetNumTitles() or 0
  for i = 1, total do
    if IsTitleKnown(i) then
      local raw = GetTitleName(i)
      local clean = BuildContextualTitleText(raw, playerName)
      rows[#rows + 1] = {
        id = i,
        label = clean ~= "" and clean or ("Title " .. i),
        detail = (current == i) and "Active" or "",
        selected = (current == i),
        icon = 133742,
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.id == 0 then return true end
    if b.id == 0 then return false end
    return (a.label or ""):lower() < (b.label or ""):lower()
  end)
  return rows
end

local function ApplyTitleRowActiveStyle(row, active)
  if not row then return end
  if active then
    row:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.95)
    row:SetBackdropColor(0.08, 0.03, 0.10, 0.75)
    if row.label then row.label:SetTextColor(1, 1, 1, 1) end
  else
    row:SetBackdropBorderColor(0.18, 0.12, 0.26, 0.70)
    row:SetBackdropColor(0.04, 0.02, 0.07, 0.65)
    if row.label then row.label:SetTextColor(0.95, 0.95, 0.95, 1) end
  end
end

local function ApplyTitleRowPendingStyle(row)
  if not row then return end
  row:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.95)
  row:SetBackdropColor(0.08, 0.03, 0.10, 0.75)
  if row.label then row.label:SetTextColor(1, 1, 1, 1) end
end

local function ResolveTitleRowVisualState(rowData, currentTitleID, pendingTitleID)
  if type(rowData) ~= "table" then
    return "normal", ""
  end

  local rowID = rowData.id
  if type(rowID) ~= "number" then
    return "normal", ""
  end

  if type(pendingTitleID) == "number" then
    if pendingTitleID == rowID then
      if currentTitleID == rowID then
        return "active", "Active"
      end
      return "pending", "Pending"
    end
    -- Suppress stale active marking while a new title is pending confirmation.
    if currentTitleID ~= pendingTitleID and currentTitleID == rowID then
      return "normal", ""
    end
  end

  if currentTitleID == rowID then
    return "active", "Active"
  end
  return "normal", ""
end

local function CreateTitleRow(parent)
  local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
  row:SetHeight(TITLE_ROW_HEIGHT)
  row:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  row:SetBackdropColor(0.04, 0.02, 0.07, 0.65)
  row:SetBackdropBorderColor(0.18, 0.12, 0.26, 0.70)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -42, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetTextColor(0.95, 0.95, 0.95, 1)
  row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.detail:SetJustifyH("RIGHT")
  row.detail:SetTextColor(0.95, 0.75, 0.30, 1)
  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(row.label, 11)
    NS:ApplyDefaultFont(row.detail, 10)
  end
  return row
end

local function UpdateTitleRows(self, state, currentTitleID)
  local rows = BuildKnownTitlesData()
  if #rows == 0 then
    rows = { { id = nil, label = "No titles found", detail = "", selected = false, icon = 133742 } }
  end
  state.titlesRowsData = rows

  if type(currentTitleID) ~= "number" then
    currentTitleID = GetCurrentTitle and GetCurrentTitle() or 0
  end

  local pendingTitleID = state.pendingTitleID
  if type(pendingTitleID) == "number" then
    if pendingTitleID == currentTitleID then
      state.pendingTitleID = nil
      pendingTitleID = nil
    else
      local pendingFound = false
      for _, row in ipairs(rows) do
        if row and row.id == pendingTitleID then
          pendingFound = true
          break
        end
      end
      if not pendingFound then
        state.pendingTitleID = nil
        pendingTitleID = nil
      end
    end
  end

  local maxOffset = math.max(0, #rows - TITLE_ROW_COUNT)
  local offset = math.max(0, math.min(maxOffset, tonumber(state.titlesOffset) or 0))
  state.titlesOffset = offset
  for i = 1, TITLE_ROW_COUNT do
    local rowFrame = state.titlesRows[i]
    local rowData = rows[i + offset]
    if rowFrame then
      if rowData then
        rowFrame._data = rowData
        rowFrame.label:SetText(rowData.label or "")
        local visualState, detailText = ResolveTitleRowVisualState(rowData, currentTitleID, pendingTitleID)
        rowFrame.detail:SetText(detailText or "")
        if visualState == "active" then
          ApplyTitleRowActiveStyle(rowFrame, true)
        elseif visualState == "pending" then
          ApplyTitleRowPendingStyle(rowFrame)
        else
          ApplyTitleRowActiveStyle(rowFrame, false)
        end
        rowFrame:Show()
      else
        rowFrame._data = nil
        rowFrame:Hide()
      end
    end
  end
end

local function ApplyTitlesFromState(self, state)
  if not state then return end
  local currentTitleID = GetCurrentTitle and GetCurrentTitle() or 0
  if type(state.pendingTitleID) == "number" and state.pendingTitleID == currentTitleID then
    state.pendingTitleID = nil
  end
  UpdateTitleRows(self, state, currentTitleID)
  local skinRef = CS and CS.Skin or nil
  if skinRef and skinRef.ApplyCustomHeader then
    pcall(skinRef.ApplyCustomHeader, currentTitleID)
  end
end

local function RequestTitleResync(self, state, _reason)
  if not state then return end
  state.titleResyncToken = (tonumber(state.titleResyncToken) or 0) + 1
  local token = state.titleResyncToken

  ApplyTitlesFromState(self, state)
  if not (C_Timer and C_Timer.After) then return end

  for _, delay in ipairs(TITLE_RESYNC_RETRY_DELAYS) do
    C_Timer.After(delay, function()
      if not state or state.titleResyncToken ~= token then return end
      ApplyTitlesFromState(self, state)
    end)
  end
end

local function DoEquipmentSetAction(self, state, action, sourceButton)
  local okAction = false
  local feedbackText = nil
  if not C_EquipmentSet then
    feedbackText = "Equipment sets unavailable."
  elseif InCombatLockdown and InCombatLockdown() then
    feedbackText = "Cannot manage sets in combat."
  else
    local selected = state.selectedSetID
    local selectedName = ResolveEquipmentSetName(selected)
    if action == "equip" then
      if selected and C_EquipmentSet.UseEquipmentSet then
        okAction = pcall(C_EquipmentSet.UseEquipmentSet, selected) == true
        feedbackText = okAction and ("Equipped " .. (selectedName or "set")) or "Equip failed."
      else feedbackText = "Select a set first." end
    elseif action == "save" then
      if selected then
        local saved = false
        if C_EquipmentSet.SaveEquipmentSet then
          local icon = nil
          if C_EquipmentSet.GetEquipmentSetInfo then local _, ei = C_EquipmentSet.GetEquipmentSetInfo(selected); icon = ei end
          saved = pcall(C_EquipmentSet.SaveEquipmentSet, selected, icon) == true
        end
        if not saved and C_EquipmentSet.ModifyEquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then
          local en, ei = C_EquipmentSet.GetEquipmentSetInfo(selected)
          if type(en) == "string" and en ~= "" then saved = pcall(C_EquipmentSet.ModifyEquipmentSet, selected, en, ei) == true end
        end
        okAction = saved
        feedbackText = okAction and ("Saved " .. (selectedName or "set")) or "Save failed."
      else feedbackText = "Select a set first." end
    elseif action == "new" then
      if C_EquipmentSet.CreateEquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        local n = #(C_EquipmentSet.GetEquipmentSetIDs() or {}) + 1
        local name = ("Set %d"):format(n)
        local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", 16) or 132627
        okAction = pcall(C_EquipmentSet.CreateEquipmentSet, name, icon) == true
        feedbackText = okAction and ("Created " .. name) or "Create failed."
      else feedbackText = "Create unavailable." end
    elseif action == "delete" then
      if selected and C_EquipmentSet.DeleteEquipmentSet then
        okAction = pcall(C_EquipmentSet.DeleteEquipmentSet, selected) == true
        if okAction then state.selectedSetID = nil end
        feedbackText = okAction and ("Deleted " .. (selectedName or "set")) or "Delete failed."
      else feedbackText = "Select a set first." end
    else feedbackText = "Unknown action." end
  end
  if sourceButton then FlashEquipmentActionButton(sourceButton, okAction) end
  ShowEquipmentActionFeedback(state, feedbackText, okAction)
  self:RequestUpdate("equipment_action:" .. tostring(action))
end

local function UpdateEquipmentRows(self, state)
  local rows, selectedSetID = BuildEquipmentSetsData(state.selectedSetID)
  state.selectedSetID = selectedSetID
  if #rows == 0 then rows = { { id = nil, label = "No equipment sets", detail = "", icon = 132627, selected = false } } end
  state.equipmentRowsData = rows
  local maxOffset = math.max(0, #rows - EQUIPMENT_ROW_COUNT)
  local offset = math.max(0, math.min(maxOffset, tonumber(state.equipmentOffset) or 0))
  state.equipmentOffset = offset
  for i = 1, EQUIPMENT_ROW_COUNT do
    local rowFrame = state.equipmentRows[i]
    local rowData = rows[i + offset]
    if rowFrame then
      if rowData then
        rowFrame._data = rowData
        rowFrame.icon:SetTexture(rowData.icon or 132627)
        rowFrame.label:SetText(rowData.label or "")
        rowFrame.detail:SetText(rowData.detail or "")
        if rowData.selected then
          rowFrame:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.95)
          rowFrame:SetBackdropColor(0.08, 0.03, 0.10, 0.75)
          rowFrame.label:SetTextColor(1, 1, 1, 1)
        else
          rowFrame:SetBackdropBorderColor(0.18, 0.12, 0.26, 0.70)
          rowFrame:SetBackdropColor(0.04, 0.02, 0.07, 0.65)
          rowFrame.label:SetTextColor(0.95, 0.95, 0.95, 1)
        end
        rowFrame:Show()
      else
        rowFrame._data = nil
        rowFrame:Hide()
      end
    end
  end
  local hasSelection = state.selectedSetID ~= nil
  for key, button in pairs(state.equipmentActionButtons or {}) do
    if button then
      button:SetEnabled(key == "new" or hasSelection)
      RefreshEquipmentActionButtonStyle(button)
    end
  end
end

---------------------------------------------------------------------------
-- Create
---------------------------------------------------------------------------
function StatsPanel:Create(parent)
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
  state.root:SetFrameLevel((parent:GetFrameLevel() or 1) + 40)
  if state.root.SetClipsChildren then state.root:SetClipsChildren(true) end
  state.root:Hide()
  SuppressBlizzardStatsPane()

  -- Sidebar bar (4 square icon buttons above the stats panel)
  local sidebarSize = CFG.STATS_SIDEBAR_BUTTON_SIZE or 34
  local sidebarGap = CFG.STATS_SIDEBAR_BUTTON_GAP or 4
  local sidebarCount = CFG.STATS_SIDEBAR_BUTTON_COUNT or 4
  local barW = (sidebarSize * sidebarCount) + (sidebarGap * (sidebarCount - 1))

  state.sidebarBar = CreateFrame("Frame", nil, state.root)
  state.sidebarBar:SetSize(barW, sidebarSize)
  state.sidebarBar:SetPoint("TOP", state.root, "TOP", 0, -SIDEBAR_TOP_INSET)
  state.sidebarBar:SetFrameStrata("DIALOG")
  state.sidebarBar:SetFrameLevel((parent:GetFrameLevel() or 1) + 205)
  state.sidebarButtons = {}

  for i = 1, sidebarCount do
    local btn = CreateSidebarButton(state.sidebarBar, i)
    btn:SetPoint("LEFT", state.sidebarBar, "LEFT",
      (i - 1) * (sidebarSize + sidebarGap), 0)
    local sidebarIdx = i
    btn:SetScript("OnClick", function()
      local modeKey = SIDEBAR_MODE_MAP[sidebarIdx]
      if modeKey then
        self:SetMode(modeKey)
      elseif sidebarIdx == 4 then
        -- Button 4: toggle M+ panel
        local rp = CS and CS.MythicPanel or nil
        local rpRoot = rp and rp._state and rp._state.root or nil
        local nextVisible = true
        if rpRoot then
          nextVisible = not rpRoot:IsShown()
          if nextVisible then rpRoot:Show() else rpRoot:Hide() end
        else
          nextVisible = not IsMythicPanelPreferenceEnabled()
        end
        SetMythicPanelPreferenceEnabled(nextVisible)
        if rp and rp.MarkDirty then
          pcall(rp.MarkDirty, rp, "sidebar_toggle")
        end
        if nextVisible and rp and rp.RequestUpdate then
          pcall(rp.RequestUpdate, rp, "sidebar_toggle")
        end
        -- Re-anchor portal panel when M+ visibility changes
        local pp = CS and CS.PortalPanel or nil
        if pp and pp.UpdateAnchoring then
          pcall(pp.UpdateAnchoring, pp)
        end
      elseif sidebarIdx == 5 then
        -- Button 5: toggle Portal panel
        local pp = CS and CS.PortalPanel or nil
        local ppRoot = pp and pp._state and pp._state.root or nil
        local nextVisible = true
        if ppRoot then
          nextVisible = not ppRoot:IsShown()
          if nextVisible then ppRoot:Show() else ppRoot:Hide() end
        else
          nextVisible = not IsPortalPanelPreferenceEnabled()
        end
        SetPortalPanelPreferenceEnabled(nextVisible)
        if pp and pp.UpdateAnchoring then
          pcall(pp.UpdateAnchoring, pp)
        end
        if nextVisible and pp and pp.RequestUpdate then
          pcall(pp.RequestUpdate, pp, "sidebar_toggle")
        end
      end
      UpdateSidebarVisuals(state)
    end)
    state.sidebarButtons[i] = btn
  end

  -- Hidden placeholder for modeBar anchoring (stats container references it)
  state.modeBar = CreateFrame("Frame", nil, state.root)
  state.modeBar:SetPoint("TOPLEFT", state.root, "TOPLEFT", 4, -MODEBAR_TOP_INSET)
  state.modeBar:SetPoint("TOPRIGHT", state.root, "TOPRIGHT", -4, -MODEBAR_TOP_INSET)
  state.modeBar:SetHeight(1)
  state.modeBar:SetAlpha(0)

  local contentTopY = -(sidebarSize + SIDEBAR_TOP_INSET + 6)

  -- Stats container (TopInfo + 5 sections)
  state.statsContainer = CreateFrame("Frame", nil, state.root)
  state.statsContainer:SetPoint("TOPLEFT", state.root, "TOPLEFT", 0, contentTopY)
  state.statsContainer:SetPoint("TOPRIGHT", state.root, "TOPRIGHT", -4, contentTopY)
  state.statsContainer:SetPoint("BOTTOMRIGHT", state.root, "BOTTOMRIGHT", -4, 8)
  if state.statsContainer.SetClipsChildren then state.statsContainer:SetClipsChildren(true) end

  -- TopInfo
  state.topInfo = CreateTopInfo(state.statsContainer)
  state.topInfo:SetPoint("TOPLEFT", state.statsContainer, "TOPLEFT", 0, 0)
  state.topInfo:SetPoint("TOPRIGHT", state.statsContainer, "TOPRIGHT", 0, 0)

  -- 5 sections
  for i = 1, 5 do
    state.sections[i] = CreateSectionFrame(state.statsContainer, 5)
  end

  -- Equipment/Titles frame: keep a tight consistent top inset beneath sidebar.
  local equipTopY = contentTopY
  state.equipmentFrame = CreateFrame("Frame", nil, state.root)
  state.equipmentFrame:SetPoint("TOPLEFT", state.root, "TOPLEFT", 0, equipTopY)
  state.equipmentFrame:SetPoint("TOPRIGHT", state.root, "TOPRIGHT", 0, equipTopY)
  state.equipmentFrame:SetPoint("BOTTOMLEFT", state.root, "BOTTOMLEFT", 0, 8)
  state.equipmentFrame:SetPoint("BOTTOMRIGHT", state.root, "BOTTOMRIGHT", 0, 8)
  state.equipmentFrame:Hide()

  state.equipmentActions = CreateFrame("Frame", nil, state.equipmentFrame)
  state.equipmentActions:SetPoint("TOPLEFT", state.equipmentFrame, "TOPLEFT", 0, 0)
  state.equipmentActions:SetPoint("TOPRIGHT", state.equipmentFrame, "TOPRIGHT", 0, 0)
  state.equipmentActions:SetHeight(22)

  state.equipmentActionButtons.equip = CreateEquipmentActionButton(state.equipmentActions, "Equip", 0)
  state.equipmentActionButtons.save = CreateEquipmentActionButton(state.equipmentActions, "Save", 54)
  state.equipmentActionButtons.new = CreateEquipmentActionButton(state.equipmentActions, "New", 108)
  state.equipmentActionButtons.delete = CreateEquipmentActionButton(state.equipmentActions, "Delete", 162)

  local orderedEquipmentButtons = {
    state.equipmentActionButtons.equip,
    state.equipmentActionButtons.save,
    state.equipmentActionButtons.new,
    state.equipmentActionButtons.delete,
  }
  local step = EQUIPMENT_ACTION_BUTTON_WIDTH + EQUIPMENT_ACTION_BUTTON_GAP
  local startX = -((#orderedEquipmentButtons - 1) * step) * 0.5
  for i, button in ipairs(orderedEquipmentButtons) do
    button:ClearAllPoints()
    button:SetPoint("CENTER", state.equipmentActions, "CENTER", startX + ((i - 1) * step), 0)
  end

  for actionKey, button in pairs(state.equipmentActionButtons) do
    local boundAction = actionKey
    button:SetScript("OnClick", function(selfButton) DoEquipmentSetAction(self, state, boundAction, selfButton) end)
  end

  state.equipmentActionFeedback = state.equipmentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  state.equipmentActionFeedback:SetPoint("TOPLEFT", state.equipmentActions, "BOTTOMLEFT", 2, -3)
  state.equipmentActionFeedback:SetPoint("TOPRIGHT", state.equipmentActions, "BOTTOMRIGHT", -2, -3)
  state.equipmentActionFeedback:SetHeight(12)
  state.equipmentActionFeedback:SetJustifyH("CENTER")
  state.equipmentActionFeedback:SetText("")
  if NS and NS.ApplyDefaultFont then NS:ApplyDefaultFont(state.equipmentActionFeedback, 10) end
  state.equipmentActionFeedback:Hide()

  for i = 1, EQUIPMENT_ROW_COUNT do
    local row = CreateEquipmentRow(state.equipmentFrame)
    row:ClearAllPoints()
    if i == 1 then
      row:SetPoint("TOPLEFT", state.equipmentActionFeedback, "BOTTOMLEFT", -2, -EQUIPMENT_LIST_TOP_GAP)
      row:SetPoint("TOPRIGHT", state.equipmentActionFeedback, "BOTTOMRIGHT", 2, -EQUIPMENT_LIST_TOP_GAP)
    else
      row:SetPoint("TOPLEFT", state.equipmentRows[i - 1], "BOTTOMLEFT", 0, -EQUIPMENT_ROW_GAP)
      row:SetPoint("TOPRIGHT", state.equipmentRows[i - 1], "BOTTOMRIGHT", 0, -EQUIPMENT_ROW_GAP)
    end
    row:SetScript("OnClick", function(clickedRow)
      local data = clickedRow._data
      if type(data) ~= "table" or type(data.id) ~= "number" then return end
      state.selectedSetID = data.id
      self:RequestUpdate("equipment_select")
    end)
    state.equipmentRows[i] = row
  end

  state.equipmentFrame:EnableMouseWheel(true)
  state.equipmentFrame:SetScript("OnMouseWheel", function(_, delta)
    local eqRows = state.equipmentRowsData or {}
    local maxOffset = math.max(0, #eqRows - EQUIPMENT_ROW_COUNT)
    local cur = math.max(0, math.min(maxOffset, (tonumber(state.equipmentOffset) or 0) + (delta < 0 and 1 or -1)))
    if cur ~= state.equipmentOffset then
      state.equipmentOffset = cur
      self:RequestUpdate("equipment_scroll")
    end
  end)

  -- Titles frame (anchored below sidebar buttons to avoid clipping)
  state.titlesFrame = CreateFrame("Frame", nil, state.root)
  state.titlesFrame:SetPoint("TOPLEFT", state.root, "TOPLEFT", 0, equipTopY)
  state.titlesFrame:SetPoint("TOPRIGHT", state.root, "TOPRIGHT", 0, equipTopY)
  state.titlesFrame:SetPoint("BOTTOMLEFT", state.root, "BOTTOMLEFT", 0, 8)
  state.titlesFrame:SetPoint("BOTTOMRIGHT", state.root, "BOTTOMRIGHT", 0, 8)
  state.titlesFrame:Hide()

  for i = 1, TITLE_ROW_COUNT do
    local tRow = CreateTitleRow(state.titlesFrame)
    local yOffset = TITLE_ROW_START_Y - ((i - 1) * (TITLE_ROW_HEIGHT + TITLE_ROW_GAP))
    tRow:SetPoint("TOPLEFT", state.titlesFrame, "TOPLEFT", 0, yOffset)
    tRow:SetPoint("TOPRIGHT", state.titlesFrame, "TOPRIGHT", 0, yOffset)
    tRow:SetScript("OnClick", function(clickedRow)
      local data = clickedRow._data
      if type(data) ~= "table" then return end
      local titleID = data.id
      if type(titleID) == "number" and SetCurrentTitle then
        state.pendingTitleID = titleID
        ApplyTitleRowPendingStyle(clickedRow)
        local ok = pcall(SetCurrentTitle, titleID)
        if not ok and state.pendingTitleID == titleID then
          state.pendingTitleID = nil
        end
        RequestTitleResync(self, state, "title_select")
      end
    end)
    state.titlesRows[i] = tRow
  end

  state.titlesFrame:EnableMouseWheel(true)
  state.titlesFrame:SetScript("OnMouseWheel", function(_, delta)
    local tRows = state.titlesRowsData or {}
    local maxOffset = math.max(0, #tRows - TITLE_ROW_COUNT)
    local cur = math.max(0, math.min(maxOffset, (tonumber(state.titlesOffset) or 0) + (delta < 0 and 1 or -1)))
    if cur ~= state.titlesOffset then
      state.titlesOffset = cur
      self:RequestUpdate("title_scroll")
    end
  end)

  ApplyMythicPanelPreference()
  UpdateSidebarVisuals(state)
  state.created = true
  return state.root
end

---------------------------------------------------------------------------
-- Update: render TopInfo + sections with gradients, or equipment mode
---------------------------------------------------------------------------
function StatsPanel:UpdateStats()
  if not EnsureSkin() then return false end
  SuppressBlizzardStatsPane()

  local state = EnsureState(self)
  if not state.created or not state.root then return false end

  local mode = state.mode or "stats"
  ApplyMythicPanelPreference()
  UpdateSidebarVisuals(state)

  -- Hide all mode containers, then show the active one
  if state.statsContainer then state.statsContainer:Hide() end
  if state.equipmentFrame then state.equipmentFrame:Hide() end
  if state.titlesFrame then state.titlesFrame:Hide() end

  if mode == "equipment" then
    if state.equipmentFrame then state.equipmentFrame:Show() end
    UpdateEquipmentRows(self, state)
  elseif mode == "titles" then
    if state.titlesFrame then state.titlesFrame:Show() end
    ApplyTitlesFromState(self, state)
  else
    if state.statsContainer then state.statsContainer:Show() end

    local width = state.statsContainer:GetWidth()
    if width <= 0 then width = CFG.BASE_STATS_WIDTH end
    local gap = CFG.STAT_SECTION_GAP

    -- TopInfo: ilvl, health, power
    local ti = state.topInfo
    if ti then
      ti:ClearAllPoints()
      ti:SetPoint("TOPLEFT", state.statsContainer, "TOPLEFT", 0, 0)
      ti:SetPoint("TOPRIGHT", state.statsContainer, "TOPRIGHT", 0, 0)

      local avgOverall, avgEquipped
      if GetAverageItemLevel then avgOverall, avgEquipped = GetAverageItemLevel() end
      if type(avgOverall) == "number" and type(avgEquipped) == "number" then
        ti.ilvl:SetText(("%.2f / %.2f"):format(avgEquipped, avgOverall))
      else
        ti.ilvl:SetText("0.00 / 0.00")
      end
      ti.ilvlHit._tooltipLabel = STAT_AVERAGE_ITEM_LEVEL or ITEM_LEVEL_ABBR or "Item Level"
      ti.ilvlHit._tooltipValue = ti.ilvl:GetText() or ""
      ti.ilvlHit._tooltipKey = "itemlevel"

      local hp = UnitHealthMax and UnitHealthMax("player") or 0
      local hpText = FormatNumber(hp)
      ti.healthRow.left:SetText(HEALTH or "Health")
      ti.healthRow.right:SetText(hpText)
      ti.healthRow._tooltipLabel = HEALTH or "Health"
      ti.healthRow._tooltipValue = hpText
      ti.healthRow._tooltipKey = "health"
      ti.healthRow.left:SetTextColor(1, 1, 1, 1)
      ti.healthRow.right:SetTextColor(1, 1, 1, 1)
      ti.healthRow.bg:ClearAllPoints()
      ti.healthRow.bg:SetPoint("TOPLEFT", ti.healthRow, "TOPLEFT", 0, 0)
      ti.healthRow.bg:SetPoint("BOTTOMRIGHT", ti.healthRow, "BOTTOMLEFT", math.floor(width * CFG.STAT_TOPINFO_GRADIENT_SPLIT), -1)
      Skin.SetHorizontalGradient(ti.healthRow.bg, 0.55, 0.04, 0.04, 0.78, 0, 0, 0, 0.08)

      local powerType, powerToken = 0, "MANA"
      if UnitPowerType then powerType, powerToken = UnitPowerType("player") end
      local power = UnitPowerMax and UnitPowerMax("player", powerType) or 0
      local powerText = FormatNumber(power)
      local powerLabel = (powerToken and _G[powerToken]) or _G.MANA or "Power"
      local info = PowerBarColor and powerToken and PowerBarColor[powerToken] or nil
      local pr = info and info.r or 0.2
      local pg = info and info.g or 0.35
      local pb = info and info.b or 0.95
      ti.powerRow.left:SetText(powerLabel)
      ti.powerRow.right:SetText(powerText)
      ti.powerRow._tooltipLabel = powerLabel
      ti.powerRow._tooltipValue = powerText
      ti.powerRow._tooltipKey = "power"
      ti.powerRow.left:SetTextColor(1, 1, 1, 1)
      ti.powerRow.right:SetTextColor(1, 1, 1, 1)
      ti.powerRow.bg:ClearAllPoints()
      ti.powerRow.bg:SetPoint("TOPLEFT", ti.powerRow, "TOPLEFT", 0, 1)
      ti.powerRow.bg:SetPoint("BOTTOMRIGHT", ti.powerRow, "BOTTOMLEFT", math.floor(width * CFG.STAT_TOPINFO_GRADIENT_SPLIT), 0)
      Skin.SetHorizontalGradient(ti.powerRow.bg, pr, pg, pb, 0.78, 0, 0, 0, 0.08)
      ti:Show()
    end

    -- Sections
    local sections = BuildSectionsData()
    local y = ti and -(ti:GetHeight() + gap + 1) or -2

    for i = 1, 5 do
      local secFrame = state.sections[i]
      local secData = sections[i] or { title = "", rows = {} }
      if not secFrame then break end

      local rowCount = math.max(1, #secData.rows)
      local secHeight = 24 + (rowCount * CFG.STAT_ROW_HEIGHT) + ((rowCount - 1) * CFG.STAT_ROW_GAP) + CFG.STAT_SECTION_BOTTOM_PAD

      secFrame:ClearAllPoints()
      secFrame:SetPoint("TOPLEFT", state.statsContainer, "TOPLEFT", 0, y)
      secFrame:SetSize(width, secHeight)
      secFrame.title:SetText(secData.title or "")

      local color = CFG.SECTION_COLORS[i] or CFG.SECTION_COLORS[#CFG.SECTION_COLORS]
      secFrame:SetBackdropBorderColor(0, 0, 0, 0)

      -- Header gradient
      if secFrame.headerTint and color then
        secFrame.headerTint:ClearAllPoints()
        secFrame.headerTint:SetPoint("TOPRIGHT", secFrame, "TOPRIGHT", -1, -1)
        secFrame.headerTint:SetPoint("BOTTOMLEFT", secFrame, "TOPLEFT", math.floor(width * (1 - CFG.STAT_GRADIENT_SPLIT)), -23)
        Skin.SetHorizontalGradient(secFrame.headerTint, 0, 0, 0, color[4] * 0.10, color[1], color[2], color[3], color[4] * CFG.STAT_HEADER_GRADIENT_ALPHA)
        secFrame.headerTint:Show()
      end
      -- Body gradient
      if secFrame.tint and color then
        secFrame.tint:ClearAllPoints()
        secFrame.tint:SetPoint("TOPLEFT", secFrame, "TOPLEFT", 1, -23)
        secFrame.tint:SetPoint("BOTTOMRIGHT", secFrame, "BOTTOMLEFT", math.floor(width * CFG.STAT_BODY_GRADIENT_SPLIT), 1)
        Skin.SetHorizontalGradient(secFrame.tint, color[1], color[2], color[3], color[4] * CFG.STAT_BODY_GRADIENT_ALPHA, 0, 0, 0, color[4] * 0.04)
        secFrame.tint:Show()
      end

      -- Stat rows
      local rowY = -24
      for r = 1, #secFrame.rows do
        local rowFrame = secFrame.rows[r]
        local rowData = secData.rows[r]
        rowFrame:ClearAllPoints()
        rowFrame:SetPoint("TOPLEFT", secFrame, "TOPLEFT", 0, rowY)
        rowFrame:SetPoint("TOPRIGHT", secFrame, "TOPRIGHT", 0, rowY)
        if rowData then
          if rowFrame.bg and color then
            local a = CFG.STAT_ROW_GRADIENT_ALPHA
            local topBleed = (r > 1) and math.ceil(CFG.STAT_ROW_GAP * 0.5) or 0
            local bottomBleed = (r < rowCount) and math.floor((CFG.STAT_ROW_GAP + 1) * 0.5) or 0
            rowFrame.bg:ClearAllPoints()
            rowFrame.bg:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 1, topBleed)
            rowFrame.bg:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMLEFT", math.floor(width * CFG.STAT_ROW_GRADIENT_SPLIT), -bottomBleed)
            Skin.SetHorizontalGradient(rowFrame.bg, color[1], color[2], color[3], a, 0, 0, 0, a * 0.08)
            if rowFrame.bg.SetBlendMode then rowFrame.bg:SetBlendMode("BLEND") end
            rowFrame.bg:Show()
          end
          rowFrame.left:SetText(rowData[1] or "")
          rowFrame.right:SetText(rowData[2] or "")
          rowFrame._tooltipLabel = rowData[1] or ""
          rowFrame._tooltipValue = rowData[2] or ""
          rowFrame:Show()
        else
          if rowFrame.bg then rowFrame.bg:Hide() end
          rowFrame._tooltipLabel = nil
          rowFrame._tooltipValue = nil
          rowFrame:Hide()
        end
        rowY = rowY - CFG.STAT_ROW_HEIGHT - CFG.STAT_ROW_GAP
      end

      secFrame:Show()
      y = y - secHeight - gap
    end
  end

  -- Only show stats panel on the character (paperdoll) pane
  local pm = CS and CS.PaneManager or nil
  local activePane = pm and pm:GetActivePane() or "character"
  if activePane == "character" and CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown() then
    state.root:Show()
  else
    state.root:Hide()
  end

  return true
end

---------------------------------------------------------------------------
-- Mode switching
---------------------------------------------------------------------------
function StatsPanel:SetMode(mode)
  local state = EnsureState(self)
  if type(mode) ~= "string" then return false end
  if not MODE_LABELS[mode] then return false end
  if state.mode == mode then return true end
  state.mode = mode
  self:RequestUpdate("mode_switch:" .. mode)
  return true
end

function StatsPanel:GetMode()
  return EnsureState(self).mode
end

---------------------------------------------------------------------------
-- Request / hooks / events
---------------------------------------------------------------------------
function StatsPanel:RequestUpdate(_reason)
  local state = EnsureState(self)
  if not state.created then self:Create(ResolveParent() or state.parent) end
  local function runUpdate() self:UpdateStats() end
  local guards = CS and CS.Guards or nil
  if guards and guards.Throttle then
    guards:Throttle("stats_panel_update", UPDATE_THROTTLE_INTERVAL, runUpdate)
  elseif C_Timer and C_Timer.After then
    C_Timer.After(0, runUpdate)
  else
    runUpdate()
  end
  return true
end

function StatsPanel:OnShow(reason)
  local state = EnsureState(self)
  self:Create(ResolveParent())
  ApplyMythicPanelPreference()
  local pm = CS and CS.PaneManager or nil
  local pane = pm and pm:GetActivePane() or "character"
  if pane == "character" and state.root then state.root:Show() end
  self:RequestUpdate(reason or "CharacterFrame.OnShow")
end

function StatsPanel:OnHide()
  local state = EnsureState(self)
  if state.root then state.root:Hide() end
end


function StatsPanel:_EnsureEventFrame()
  local state = EnsureState(self)
  if state.eventFrame then return end
  state.eventFrame = CreateFrame("Frame")
  if state.eventFrame.RegisterUnitEvent then
    state.eventFrame:RegisterUnitEvent("UNIT_STATS", "player")
    state.eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    state.eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
  else
    state.eventFrame:RegisterEvent("UNIT_STATS")
    state.eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    state.eventFrame:RegisterEvent("UNIT_MAXPOWER")
  end
  state.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
  state.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  state.eventFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
  state.eventFrame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
  state.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  state.eventFrame:RegisterEvent("PLAYER_TITLE_CHANGED")
  state.eventFrame:RegisterEvent("KNOWN_TITLES_UPDATE")
  state.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  -- PLAYER_AVG_ITEM_LEVEL_UPDATE fires *after* ilvl recalculation completes;
  -- PLAYER_EQUIPMENT_CHANGED alone fires too early (stale GetAverageItemLevel).
  pcall(state.eventFrame.RegisterEvent, state.eventFrame, "PLAYER_AVG_ITEM_LEVEL_UPDATE")
  state.eventFrame:SetScript("OnEvent", function(_, event, unit)
    if (event == "UNIT_STATS" or event == "UNIT_MAXHEALTH" or event == "UNIT_MAXPOWER") and unit and unit ~= "player" then return end
    if event == "PLAYER_TITLE_CHANGED" or event == "KNOWN_TITLES_UPDATE" then
      RequestTitleResync(self, state, "event:" .. tostring(event))
      return
    end
    self:RequestUpdate("event:" .. tostring(event))
    -- GetAverageItemLevel may return stale data right after equipment changes;
    -- schedule multiple follow-up retries until the value actually changes.
    if (event == "PLAYER_EQUIPMENT_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" or event == "EQUIPMENT_SETS_CHANGED") then
      if C_Timer and C_Timer.After and GetAverageItemLevel then
        local snapOverall, snapEquipped = GetAverageItemLevel()
        local ILVL_RECHECK_DELAYS = { 0.15, 0.35, 0.6, 1.0, 1.5 }
        for _, delay in ipairs(ILVL_RECHECK_DELAYS) do
          C_Timer.After(delay, function()
            if not GetAverageItemLevel then return end
            local curOverall, curEquipped = GetAverageItemLevel()
            if curOverall ~= snapOverall or curEquipped ~= snapEquipped then
              self:RequestUpdate("ilvl_recheck")
            end
          end)
        end
      end
    end
  end)
end

function StatsPanel:Update(reason)
  local state = EnsureState(self)
  if IsNativeCurrencyMode() then
    if state.root then state.root:Hide() end
    return false
  end
  self:_EnsureEventFrame()
  self:Create(ResolveParent())
  return self:RequestUpdate(reason or "coordinator.stats")
end


