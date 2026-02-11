local ADDON, NS = ...
local M = {}
NS:RegisterModule("charsheet", M)

M.active = false

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local hiddenRegions = {}
local styledFonts = {}
local statRows = {}
local slotSkins = {}
local panelSkins = {}
local skinFrame
local customCharacterFrame
local customNameText
local customLevelText
local customStatsFrame
local customGearFrame
local modelFillFrame
local modelBaseScale
local modelLockedCameraScale
local headerFrame
local slotDisplays = {}
local specButtons
local lootSpecButtons
local rightPanel
local originalCharacterSize
local originalLayoutByKey = {}
local layoutApplied = false
local ticker
local elapsedSinceTick = 0
local hookedShow = false
local hookedHide = false

local TICK_INTERVAL = 0.5
local DATA_REFRESH_INTERVAL = 2.0
local elapsedSinceData = 0
local portalSpellCache = {}
local lastMPlusSnapshot = {
  affixIDs = nil,
  runs = nil,
}
local ShowAffixTooltip
local ShowDungeonPortalTooltip
local pendingSecureUpdate = false

local CUSTOM_CHAR_WIDTH = 640
local CUSTOM_CHAR_HEIGHT = 620
local CUSTOM_STATS_WIDTH = 230
local CUSTOM_PANE_GAP = 6
local PRIMARY_SHEET_WIDTH = 640
local INTEGRATED_RIGHT_GAP = 8
local STAT_ROW_HEIGHT = 15
local STAT_SECTION_GAP = 6
local SIMPLE_BASE_PANEL_MODE = true
local SLOT_ICON_SIZE = 38
local MODEL_ZOOM_OUT_FACTOR = 0.80
local STAT_GRADIENT_SPLIT = 0.52
local STAT_TOPINFO_GRADIENT_SPLIT = 0.56
local STAT_BODY_GRADIENT_SPLIT = 0.74
local STAT_ROW_GRADIENT_SPLIT = 0.74
local STAT_HEADER_GRADIENT_ALPHA = 0.92
local STAT_BODY_GRADIENT_ALPHA = 0.52
local STAT_ROW_GRADIENT_ALPHA = 0.56

local ATTR_YELLOW = { 0.96, 0.96, 0.96, 1.0 }
local VALUE_WHITE = { 0.96, 0.96, 0.96, 1.0 }

local LEFT_GEAR_SLOTS = {
  "HeadSlot",
  "NeckSlot",
  "ShoulderSlot",
  "ShirtSlot",
  "ChestSlot",
  "WaistSlot",
  "LegsSlot",
  "FeetSlot",
}

local RIGHT_GEAR_SLOTS = {
  "BackSlot",
  "WristSlot",
  "HandsSlot",
  "Finger0Slot",
  "Finger1Slot",
  "Trinket0Slot",
  "Trinket1Slot",
  "MainHandSlot",
}

-- Slot index mapping for per-slot item display
local SLOT_NAME_TO_INDEX = {
  HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4,
  ChestSlot = 5, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8,
  WristSlot = 9, HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12,
  Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15,
  MainHandSlot = 16, SecondaryHandSlot = 17, TabardSlot = 19,
}

-- Right-column slots display text to the LEFT (Chonky convention)
local DISPLAY_TO_LEFT = {
  [6] = true, [7] = true, [8] = true, [10] = true,
  [11] = true, [12] = true, [13] = true, [14] = true,
  [16] = true, [17] = true,
}

-- Rarity gradient colors (from Chonky) - [rarity] = { inner_r, inner_g, inner_b, inner_a, outer_r, outer_g, outer_b, outer_a }
local RARITY_GRADIENT = {
  [1] = { 0.5, 0.5, 0.5, 0.8, 1, 1, 1, 1 },                     -- Common (white)
  [2] = { 0.06, 0.5, 0, 0.8, 0.12, 1, 0, 1 },                   -- Uncommon (green)
  [3] = { 0, 0.22, 0.435, 0.8, 0, 0.44, 0.87, 1 },              -- Rare (blue)
  [4] = { 0.32, 0.105, 0.465, 0.8, 0.64, 0.21, 0.93, 1 },       -- Epic (purple)
  [5] = { 0.5, 0.25, 0, 0.8, 1, 0.5, 0, 1 },                    -- Legendary (orange)
  [6] = { 0.45, 0.4, 0.25, 0.8, 0.9, 0.8, 0.5, 1 },             -- Artifact (tan)
  [7] = { 0, 0.4, 0.5, 0.8, 0, 0.8, 1, 1 },                     -- Heirloom (light blue)
  [0] = { 0.31, 0.31, 0.31, 0.8, 0.62, 0.62, 0.62, 1 },         -- Poor (gray)
}

-- Section background colors for stats panel
local SECTION_COLORS = {
  { 0.64, 0.47, 0.1, 0.4 },   -- Attributes (gold)
  { 0.16, 0.34, 0.08, 0.4 },  -- Secondary (green)
  { 0.41, 0, 0, 0.4 },        -- Attack (red)
  { 0, 0.13, 0.38, 0.4 },     -- Defense (blue)
  { 0.45, 0.45, 0.45, 0.4 },  -- General (gray)
}

-- All equippable slot indices (excluding ranged 18)
local ALL_SLOT_INDICES = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19 }

local function CaptureLayout(key, frame)
  if not key or not frame or originalLayoutByKey[key] then return end
  local points = {}
  if frame.GetNumPoints and frame.GetPoint then
    for i = 1, frame:GetNumPoints() do
      local p, rel, rp, x, y = frame:GetPoint(i)
      points[#points + 1] = { p = p, rel = rel, rp = rp, x = x, y = y }
    end
  end
  originalLayoutByKey[key] = {
    frame = frame,
    width = frame.GetWidth and frame:GetWidth() or nil,
    height = frame.GetHeight and frame:GetHeight() or nil,
    points = points,
  }
end

local function RestoreCapturedLayouts()
  for _, data in pairs(originalLayoutByKey) do
    local frame = data and data.frame
    if frame and frame.ClearAllPoints and data.points then
      frame:ClearAllPoints()
      for _, pt in ipairs(data.points) do
        frame:SetPoint(pt.p, pt.rel, pt.rp, pt.x, pt.y)
      end
    end
    if frame and frame.SetSize and data and data.width and data.height then
      frame:SetSize(data.width, data.height)
    end
  end
  wipe(originalLayoutByKey)
end

local PORTAL_ALIASES = {
  ["the motherlode"] = { common = { "the m o t h e r l o d e", "motherlode" } },
  ["the dawnbreaker"] = {
    common = { "dawnbreaker", "arathi flagship", "hero s path of the arathi flagship" },
  },
  ["siege of boralus"] = {
    alliance = { "siege of boralus" },
    horde = { "siege of boralus" },
  },
  ["mechagon junkyard"] = { common = { "junkyard", "mechagon junkyard" } },
  ["mechagon workshop"] = { common = { "workshop", "mechagon workshop" } },
}

local function SafeFrameLevel(frame, preferred)
  if not frame or not frame.SetFrameLevel then return end
  local level = tonumber(preferred) or 0
  if level < 0 then level = 0 end
  if level > 65535 then level = 65535 end
  frame:SetFrameLevel(level)
end

local function IsAddonLoadedCompat(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded(name)
  end
  if IsAddOnLoaded then
    return IsAddOnLoaded(name)
  end
  return false
end

local function LoadAddonCompat(name)
  if C_AddOns and C_AddOns.LoadAddOn then
    local ok = C_AddOns.LoadAddOn(name)
    return ok == true
  end
  if UIParentLoadAddOn then
    local ok = pcall(UIParentLoadAddOn, name)
    return ok == true
  end
  if LoadAddOn then
    local ok = pcall(LoadAddOn, name)
    return ok == true
  end
  return false
end

local function SaveAndHideRegion(region)
  if not region then return end
  if not hiddenRegions[region] then
    hiddenRegions[region] = {
      alpha = region.GetAlpha and region:GetAlpha() or 1,
      shown = region.IsShown and region:IsShown() or false,
    }
  end
  if region.SetAlpha then region:SetAlpha(0) end
  if region.Hide then region:Hide() end
end

local function ShouldHideTexture(region)
  if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then
    return false
  end
  local tex = region.GetTexture and region:GetTexture() or nil
  if type(tex) ~= "string" or tex == "" then
    return false
  end
  local t = string.lower(tex)
  if t:find("character") then return true end
  if t:find("paperdoll") then return true end
  if t:find("parchment") then return true end
  if t:find("ui%-frame") then return true end
  if t:find("ui%-panel") then return true end
  if t:find("ui%-dialogbox") then return true end
  return false
end

local function HideFrameTextureRegions(frame)
  if not frame or not frame.GetRegions then return end
  local regions = { frame:GetRegions() }
  for _, region in ipairs(regions) do
    if ShouldHideTexture(region) then
      SaveAndHideRegion(region)
    end
  end
end

local function AggressiveStripFrame(frame)
  if not frame or not frame.GetRegions then return end
  local regions = { frame:GetRegions() }
  for _, region in ipairs(regions) do
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
      SaveAndHideRegion(region)
    end
  end
end

local function AggressiveStripFrameRecursive(frame, depth)
  if not frame or depth <= 0 then return end
  AggressiveStripFrame(frame)
  if frame.GetChildren then
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
      AggressiveStripFrameRecursive(child, depth - 1)
    end
  end
end

local function RestoreHiddenRegions()
  for region, state in pairs(hiddenRegions) do
    if region then
      if region.SetAlpha and state.alpha ~= nil then
        region:SetAlpha(state.alpha)
      end
      if region.SetShown then
        region:SetShown(state.shown == true)
      elseif state.shown and region.Show then
        region:Show()
      end
    end
  end
  wipe(hiddenRegions)
end

local function BackupFont(fs)
  if not fs or styledFonts[fs] then return end
  local path, size, flags = fs:GetFont()
  styledFonts[fs] = {
    path = path,
    size = size,
    flags = flags,
  }
end

local function RestoreFonts()
  for fs, data in pairs(styledFonts) do
    if fs and data and data.path and fs.SetFont then
      fs:SetFont(data.path, data.size or 12, data.flags)
    end
  end
  wipe(styledFonts)
end

local function EnsureSlotSkin(slotButton)
  if not slotButton then return nil end
  if slotSkins[slotButton] then
    local existing = slotSkins[slotButton]
    existing:ClearAllPoints()
    existing:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
    existing:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
    return existing
  end

  local holder = CreateFrame("Frame", nil, slotButton, "BackdropTemplate")
  holder:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
  holder:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
  holder:SetFrameLevel(slotButton:GetFrameLevel() - 1)
  holder:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  holder:SetBackdropColor(0.05, 0.02, 0.08, 0.90)
  holder:SetBackdropBorderColor(0.35, 0.18, 0.55, 0.95)
  holder:Hide()

  slotSkins[slotButton] = holder
  return holder
end

local function EnsurePanelSkin(key, parent)
  if not key or not parent then return nil end
  if panelSkins[key] then return panelSkins[key] end

  local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  panel:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  panel:SetBackdropColor(0.03, 0.01, 0.06, 0.90)
  panel:SetBackdropBorderColor(0.30, 0.14, 0.48, 0.95)
  panel:Hide()
  panelSkins[key] = panel
  return panel
end

local function GetConfiguredFont(db)
  local fontPath
  if LSM and db and db.charsheet and db.charsheet.font then
    fontPath = LSM:Fetch("font", db.charsheet.font, true)
  end
  if not fontPath then
    fontPath = STANDARD_TEXT_FONT
  end
  local size = (db and db.charsheet and db.charsheet.fontSize) or 12
  local outline = db and db.charsheet and db.charsheet.fontOutline
  if outline == "NONE" then
    outline = nil
  end
  return fontPath, size, outline
end

local function EnsureSkinFrame()
  if not CharacterFrame then return nil end
  if skinFrame then return skinFrame end

  skinFrame = CreateFrame("Frame", nil, CharacterFrame, "BackdropTemplate")
  skinFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 1)
  skinFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
  skinFrame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", 0, 0)
  skinFrame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  skinFrame:SetBackdropColor(0.02, 0.01, 0.05, 0.93)
  skinFrame:SetBackdropBorderColor(0.34, 0.16, 0.52, 0.95)
  skinFrame:Hide()

  return skinFrame
end

local function EnsureCustomCharacterFrame()
  if not CharacterFrame then return nil end
  if customCharacterFrame then return customCharacterFrame end

  customCharacterFrame = CreateFrame("Frame", nil, CharacterFrame, "BackdropTemplate")
  customCharacterFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 1)
  customCharacterFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
  customCharacterFrame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", 0, 0)
  customCharacterFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  customCharacterFrame:SetBackdropColor(0, 0, 0, 0)
  customCharacterFrame:SetBackdropBorderColor(0.34, 0.17, 0.52, 0.95)
  customCharacterFrame:Hide()

  customCharacterFrame.innerGlow = customCharacterFrame:CreateTexture(nil, "BACKGROUND")
  customCharacterFrame.innerGlow:SetPoint("TOPLEFT", 1, -1)
  customCharacterFrame.innerGlow:SetPoint("BOTTOMRIGHT", -1, 1)
  customCharacterFrame.innerGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
  -- Keep this very subtle; modelFill handles the main panel gradient now.
  customCharacterFrame.innerGlow:SetVertexColor(0, 0, 0, 0)

  headerFrame = CreateFrame("Frame", nil, CharacterFrame)
  headerFrame:SetAllPoints(CharacterFrame)
  headerFrame:SetFrameStrata("HIGH")
  headerFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 40)

  customNameText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  customNameText:SetPoint("TOP", CharacterFrame, "TOP", 0, -8)
  customNameText:SetJustifyH("CENTER")
  customNameText:SetDrawLayer("OVERLAY", 7)
  customNameText:SetShadowOffset(1, -1)
  customNameText:SetShadowColor(0, 0, 0, 0.95)

  customLevelText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  customLevelText:SetPoint("TOP", customNameText, "BOTTOM", 0, -2)
  customLevelText:SetJustifyH("CENTER")
  customLevelText:SetDrawLayer("OVERLAY", 7)
  customLevelText:SetShadowOffset(1, -1)
  customLevelText:SetShadowColor(0, 0, 0, 0.95)

  return customCharacterFrame
end

local function EnsureModelFillFrame()
  if modelFillFrame then return modelFillFrame end
  if not CharacterFrame then return nil end

  modelFillFrame = CreateFrame("Frame", nil, CharacterFrame)
  modelFillFrame:SetFrameStrata(CharacterFrame:GetFrameStrata() or "MEDIUM")
  modelFillFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 1)
  modelFillFrame.base = modelFillFrame:CreateTexture(nil, "BACKGROUND")
  modelFillFrame.base:SetAllPoints()
  modelFillFrame.base:SetTexture("Interface\\Buttons\\WHITE8x8")
  modelFillFrame.base:SetColorTexture(0, 0, 0, 0.0)

  modelFillFrame.overlay = modelFillFrame:CreateTexture(nil, "BORDER")
  modelFillFrame.overlay:SetAllPoints()
  modelFillFrame.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
  -- Character panel gradient (reversed relative to M+): purple at top -> black at bottom.
  if modelFillFrame.overlay.SetGradient and CreateColor then
    modelFillFrame.overlay:SetGradient(
      "VERTICAL",
      CreateColor(0.08, 0.02, 0.12, 0.90),
      CreateColor(0, 0, 0, 0.90)
    )
  elseif modelFillFrame.overlay.SetGradientAlpha then
    modelFillFrame.overlay:SetGradientAlpha("VERTICAL", 0.08, 0.02, 0.12, 0.90, 0, 0, 0, 0.90)
  else
    modelFillFrame.overlay:SetColorTexture(0.08, 0.02, 0.12, 0.90)
  end
  modelFillFrame:Hide()
  return modelFillFrame
end

local function SuppressModelSceneBorderArt()
  local model = _G.CharacterModelScene
  if not model then return end

  local legacy = {
    _G.CharacterModelFrameBackgroundTopLeft,
    _G.CharacterModelFrameBackgroundTopRight,
    _G.CharacterModelFrameBackgroundBotLeft,
    _G.CharacterModelFrameBackgroundBotRight,
    _G.CharacterModelFrameBackgroundOverlay,
    model.Background,
    model.BG,
  }
  for _, region in ipairs(legacy) do
    SaveAndHideRegion(region)
  end

  -- Strip any texture regions attached directly to CharacterModelScene.
  if model.GetNumRegions and model.GetRegions then
    for i = 1, model:GetNumRegions() do
      local region = select(i, model:GetRegions())
      if region and region.GetObjectType and region:GetObjectType() == "Texture" then
        SaveAndHideRegion(region)
      end
    end
  end
end

local function EnsureBlizzardCharacterAnchors()
  if not CharacterFrame then return end

  local insetRight = _G.CharacterFrameInsetRight
  local stats = _G.CharacterStatsPane
  if insetRight and stats and stats.ClearAllPoints then
    stats:ClearAllPoints()
    stats:SetPoint("TOPLEFT", insetRight, "TOPLEFT", 0, 0)
    stats:SetPoint("BOTTOMRIGHT", insetRight, "BOTTOMRIGHT", 0, 0)
  end

  local insetLeft = _G.CharacterFrameInsetLeft
  local paper = _G.PaperDollFrame
  if insetLeft and paper and paper.ClearAllPoints then
    paper:ClearAllPoints()
    paper:SetPoint("TOPLEFT", insetLeft, "TOPLEFT", 0, 0)
    paper:SetPoint("BOTTOMRIGHT", insetLeft, "BOTTOMRIGHT", 0, 0)
  end
end

local function FormatNumber(n)
  n = tonumber(n) or 0
  return BreakUpLargeNumbers(math.floor(n + 0.5))
end

local function FormatPercent(v)
  v = tonumber(v) or 0
  return ("%.2f%%"):format(v)
end

local function GetPrimaryStatLabelAndValue()
  local _, classTag = UnitClass("player")
  local statIndex = LE_UNIT_STAT_STRENGTH or 1
  local label = "Strength"
  if classTag == "MAGE" or classTag == "PRIEST" or classTag == "WARLOCK" or classTag == "EVOKER" then
    statIndex = LE_UNIT_STAT_INTELLECT or 4
    label = "Intellect"
  elseif classTag == "ROGUE" or classTag == "HUNTER" or classTag == "MONK" or classTag == "DRUID" or classTag == "DEMONHUNTER" or classTag == "SHAMAN" then
    statIndex = LE_UNIT_STAT_AGILITY or 2
    label = "Agility"
  end
  local base, stat, posBuff, negBuff = UnitStat("player", statIndex)
  local value = stat or base or 0
  if value <= 0 then
    value = (base or 0) + (posBuff or 0) + (negBuff or 0)
  end
  return label, value
end

local function BuildCustomStatsData()
  local primaryLabel, primaryValue = GetPrimaryStatLabelAndValue()
  local _, stamina = UnitStat("player", LE_UNIT_STAT_STAMINA or 3)
  local _, effectiveArmor = UnitArmor("player")
  local gcdValue = 1.0
  if C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(61304)
    if type(cd) == "table" and type(cd.duration) == "number" and cd.duration > 0 then
      gcdValue = cd.duration
    end
  end

  local apBase, apPos, apNeg = UnitAttackPower("player")
  local attackPower = (apBase or 0) + (apPos or 0) + (apNeg or 0)
  local mhSpeed = UnitAttackSpeed("player")
  local spellPower = 0
  if GetSpellBonusDamage then
    spellPower = GetSpellBonusDamage(2) or 0
  end

  local moveSpeed = 0
  if GetUnitSpeed and BASE_MOVEMENT_SPEED then
    moveSpeed = (GetUnitSpeed("player") / BASE_MOVEMENT_SPEED) * 100
  end

  local sections = {
    {
      title = "Attributes",
      rows = {
        { primaryLabel, FormatNumber(primaryValue) },
        { "Stamina", FormatNumber(stamina or 0) },
        { "Armor", FormatNumber(effectiveArmor or 0) },
        { "GCD", ("%.2fs"):format(gcdValue or 1.0) },
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

  return sections
end

local function EnsureCustomStatsFrame()
  if customStatsFrame then return customStatsFrame end
  if not CharacterFrame then return nil end

  customStatsFrame = CreateFrame("Frame", nil, CharacterFrame)
  customStatsFrame:SetFrameStrata("HIGH")
  customStatsFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 20)
  customStatsFrame.sections = {}
  customStatsFrame:Hide()

  customStatsFrame.topInfo = CreateFrame("Frame", nil, customStatsFrame, "BackdropTemplate")
  customStatsFrame.topInfo:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  customStatsFrame.topInfo:SetBackdropColor(0.02, 0.02, 0.03, 0.75)
  customStatsFrame.topInfo:SetBackdropBorderColor(0.32, 0.18, 0.48, 0.9)
  customStatsFrame.topInfo:SetHeight(72)

  customStatsFrame.topInfo.ilvl = customStatsFrame.topInfo:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  customStatsFrame.topInfo.ilvl:SetPoint("TOP", customStatsFrame.topInfo, "TOP", 0, -4)
  customStatsFrame.topInfo.ilvl:SetTextColor(0.73, 0.27, 1.0, 1.0)
  customStatsFrame.topInfo.ilvl:SetText("0.00 / 0.00")

  customStatsFrame.topInfo.healthRow = CreateFrame("Frame", nil, customStatsFrame.topInfo)
  customStatsFrame.topInfo.healthRow:SetPoint("TOPLEFT", customStatsFrame.topInfo, "TOPLEFT", 8, -30)
  customStatsFrame.topInfo.healthRow:SetPoint("TOPRIGHT", customStatsFrame.topInfo, "TOPRIGHT", -8, -30)
  customStatsFrame.topInfo.healthRow:SetHeight(16)
  customStatsFrame.topInfo.healthRow.bg = customStatsFrame.topInfo.healthRow:CreateTexture(nil, "BACKGROUND")
  customStatsFrame.topInfo.healthRow.bg:SetAllPoints()
  customStatsFrame.topInfo.healthRow.bg:SetTexture("Interface/Buttons/WHITE8x8")
  customStatsFrame.topInfo.healthRow.left = customStatsFrame.topInfo.healthRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  customStatsFrame.topInfo.healthRow.left:SetPoint("LEFT", customStatsFrame.topInfo.healthRow, "LEFT", 4, 0)
  customStatsFrame.topInfo.healthRow.left:SetJustifyH("LEFT")
  customStatsFrame.topInfo.healthRow.right = customStatsFrame.topInfo.healthRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  customStatsFrame.topInfo.healthRow.right:SetPoint("RIGHT", customStatsFrame.topInfo.healthRow, "RIGHT", -4, 0)
  customStatsFrame.topInfo.healthRow.right:SetJustifyH("RIGHT")

  customStatsFrame.topInfo.powerRow = CreateFrame("Frame", nil, customStatsFrame.topInfo)
  customStatsFrame.topInfo.powerRow:SetPoint("TOPLEFT", customStatsFrame.topInfo.healthRow, "BOTTOMLEFT", 0, -3)
  customStatsFrame.topInfo.powerRow:SetPoint("TOPRIGHT", customStatsFrame.topInfo.healthRow, "TOPRIGHT", 0, -3)
  customStatsFrame.topInfo.powerRow:SetHeight(16)
  customStatsFrame.topInfo.powerRow.bg = customStatsFrame.topInfo.powerRow:CreateTexture(nil, "BACKGROUND")
  customStatsFrame.topInfo.powerRow.bg:SetAllPoints()
  customStatsFrame.topInfo.powerRow.bg:SetTexture("Interface/Buttons/WHITE8x8")
  customStatsFrame.topInfo.powerRow.left = customStatsFrame.topInfo.powerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  customStatsFrame.topInfo.powerRow.left:SetPoint("LEFT", customStatsFrame.topInfo.powerRow, "LEFT", 4, 0)
  customStatsFrame.topInfo.powerRow.left:SetJustifyH("LEFT")
  customStatsFrame.topInfo.powerRow.right = customStatsFrame.topInfo.powerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  customStatsFrame.topInfo.powerRow.right:SetPoint("RIGHT", customStatsFrame.topInfo.powerRow, "RIGHT", -4, 0)
  customStatsFrame.topInfo.powerRow.right:SetJustifyH("RIGHT")

  for i = 1, 5 do
    local sec = CreateFrame("Frame", nil, customStatsFrame, "BackdropTemplate")
    sec:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    sec:SetBackdropColor(0.02, 0.02, 0.03, 0.55)
    sec:SetBackdropBorderColor(0.22, 0.18, 0.08, 0.9)
    sec.tint = sec:CreateTexture(nil, "BACKGROUND")
    sec.tint:SetDrawLayer("BACKGROUND", 1)
    sec.tint:SetTexture("Interface/Buttons/WHITE8x8")
    sec.headerTint = sec:CreateTexture(nil, "ARTWORK")
    sec.headerTint:SetDrawLayer("ARTWORK", 1)
    sec.headerTint:SetTexture("Interface/Buttons/WHITE8x8")

    sec.title = sec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sec.title:SetPoint("TOP", sec, "TOP", 0, -3)
    sec.title:SetTextColor(1, 1, 1, 1)
    sec.title:SetText("Section")

    sec.rows = {}
    for r = 1, 5 do
      local row = CreateFrame("Frame", nil, sec)
      row:SetHeight(STAT_ROW_HEIGHT)
      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetDrawLayer("ARTWORK", 1)
      row.bg:SetTexture("Interface/Buttons/WHITE8x8")
      row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.left:SetPoint("LEFT", row, "LEFT", 8, 0)
      row.left:SetJustifyH("LEFT")
      row.left:SetTextColor(ATTR_YELLOW[1], ATTR_YELLOW[2], ATTR_YELLOW[3], ATTR_YELLOW[4])
      row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      row.right:SetJustifyH("RIGHT")
      row.right:SetTextColor(VALUE_WHITE[1], VALUE_WHITE[2], VALUE_WHITE[3], VALUE_WHITE[4])
      sec.rows[r] = row
    end
    customStatsFrame.sections[i] = sec
  end

  return customStatsFrame
end

local function SetHorizontalGradient(tex, fromR, fromG, fromB, fromA, toR, toG, toB, toA)
  if not tex then return end
  if tex.SetGradientAlpha then
    tex:SetGradientAlpha("HORIZONTAL", fromR, fromG, fromB, fromA, toR, toG, toB, toA)
  elseif tex.SetGradient and CreateColor then
    tex:SetGradient("HORIZONTAL", CreateColor(fromR, fromG, fromB, fromA), CreateColor(toR, toG, toB, toA))
  else
    tex:SetColorTexture(toR, toG, toB, toA)
  end
end

local function SetVerticalGradient(tex, topR, topG, topB, topA, bottomR, bottomG, bottomB, bottomA)
  if not tex then return end
  if tex.SetGradientAlpha then
    tex:SetGradientAlpha("VERTICAL", topR, topG, topB, topA, bottomR, bottomG, bottomB, bottomA)
  elseif tex.SetGradient and CreateColor then
    tex:SetGradient("VERTICAL", CreateColor(topR, topG, topB, topA), CreateColor(bottomR, bottomG, bottomB, bottomA))
  else
    tex:SetColorTexture(bottomR, bottomG, bottomB, bottomA)
  end
end

local function ApplyCustomStatsFont(db)
  if not customStatsFrame then return end
  local fontPath, size, outline = GetConfiguredFont(db)
  if customStatsFrame.topInfo and customStatsFrame.topInfo.ilvl and customStatsFrame.topInfo.ilvl.SetFont then
    customStatsFrame.topInfo.ilvl:SetFont(fontPath, size + 8, outline)
  end
  if customStatsFrame.topInfo then
    local topRows = { customStatsFrame.topInfo.healthRow, customStatsFrame.topInfo.powerRow }
    for _, row in ipairs(topRows) do
      if row and row.left and row.left.SetFont then
        row.left:SetFont(fontPath, size, outline)
      end
      if row and row.right and row.right.SetFont then
        row.right:SetFont(fontPath, size, outline)
      end
    end
  end
  for _, sec in ipairs(customStatsFrame.sections or {}) do
    if sec.title and sec.title.SetFont then
      sec.title:SetFont(fontPath, size + 2, outline)
    end
    for _, row in ipairs(sec.rows or {}) do
      if row.left and row.left.SetFont then
        row.left:SetFont(fontPath, size, outline)
      end
      if row.right and row.right.SetFont then
        row.right:SetFont(fontPath, size, outline)
      end
    end
  end
end

local function ApplyCoreCharacterFontAndName(db)
  local fontPath, size, outline = GetConfiguredFont(db)
  local name = UnitName("player") or ""
  local _, classTag = UnitClass("player")
  local c = (classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]) or NORMAL_FONT_COLOR
  local titleText = ""
  if GetCurrentTitle and GetTitleName then
    local current = GetCurrentTitle()
    if current and current > 0 then
      local raw = GetTitleName(current)
      if type(raw) == "string" then
        titleText = raw:gsub("%%s%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
      end
    end
  end
  local nameHex = ("|cff%02x%02x%02x"):format(
    math.floor((c.r or 1) * 255 + 0.5),
    math.floor((c.g or 1) * 255 + 0.5),
    math.floor((c.b or 1) * 255 + 0.5)
  )
  local titleHex = "|cfff5f5f5"
  local titlePart = (titleText ~= "" and (" " .. titleHex .. titleText .. "|r")) or ""

  if customNameText then
    if customNameText.SetFont then customNameText:SetFont(fontPath, size + 6, outline) end
    customNameText:SetText(nameHex .. name .. "|r" .. titlePart)
    customNameText:ClearAllPoints()
    customNameText:SetPoint("TOP", CharacterFrame, "TOP", 0, -8)
    customNameText:Show()
  end

  local title = _G.CharacterFrameTitleText
  if title and title.SetFont then
    BackupFont(title)
    title:SetFont(fontPath, size + 4, outline)
    title:SetTextColor(1, 1, 1, 1)
    title:ClearAllPoints()
    title:SetPoint("TOP", customNameText or CharacterFrame, "BOTTOM", 0, -2)
    title:SetText("")
    title:SetAlpha(0)
    if title.Hide then title:Hide() end
  end
  local levelText = _G.CharacterLevelText
  if levelText then
    local levelLine = levelText.GetText and levelText:GetText() or ""
    if (not levelLine) or levelLine == "" then
      local level = UnitLevel("player") or 0
      local className = UnitClass("player") or ""
      local specText = ""
      if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
          local _, specName = GetSpecializationInfo(specIndex)
          if type(specName) == "string" and specName ~= "" then
            specText = specName .. " "
          end
        end
      end
      levelLine = ("Level %d %s%s"):format(level, specText, className)
    end
    if customLevelText then
      if customLevelText.SetFont then customLevelText:SetFont(fontPath, size + 1, outline) end
      customLevelText:ClearAllPoints()
      customLevelText:SetPoint("TOP", customNameText or CharacterFrame, "BOTTOM", 0, -2)
      customLevelText:SetText(levelLine or "")
      customLevelText:SetTextColor(1, 1, 1, 1)
      customLevelText:SetAlpha(1)
      customLevelText:Show()
    end
  end
  if levelText and levelText.SetFont then
    BackupFont(levelText)
    levelText:SetFont(fontPath, size + 1, outline)
    levelText:ClearAllPoints()
    if customNameText then
      levelText:SetPoint("TOP", customNameText, "BOTTOM", 0, -2)
    else
      levelText:SetPoint("TOP", CharacterFrame, "TOP", 0, -28)
    end
    levelText:SetTextColor(1, 1, 1, 1)
    levelText:SetAlpha(0)
    if levelText.Hide then levelText:Hide() end
  end
end

local function HideDefaultCharacterStats()
  if _G.CharacterStatsPane then
    _G.CharacterStatsPane:SetAlpha(0)
    _G.CharacterStatsPane:EnableMouse(false)
  end
  if _G.CharacterFrameInsetRight then
    _G.CharacterFrameInsetRight:SetAlpha(0)
    _G.CharacterFrameInsetRight:EnableMouse(false)
  end
  SaveAndHideRegion(_G.PaperDollFrame and _G.PaperDollFrame.TitleText)
  SaveAndHideRegion(_G.CharacterLevelText)
  SaveAndHideRegion(_G.CharacterFrameTitleText)
  SaveAndHideRegion(_G.CharacterFrame and _G.CharacterFrame.NineSlice)
  SaveAndHideRegion(_G.CharacterFramePortrait)
  SaveAndHideRegion(_G.CharacterFrameInset)
  SaveAndHideRegion(_G.CharacterFrameInset and _G.CharacterFrameInset.Bg)
  SaveAndHideRegion(_G.CharacterFrameInset and _G.CharacterFrameInset.NineSlice)
  SaveAndHideRegion(_G.CharacterFrameInsetLeft)
  SaveAndHideRegion(_G.CharacterFrameInsetLeft and _G.CharacterFrameInsetLeft.Bg)
  SaveAndHideRegion(_G.CharacterFrameInsetLeft and _G.CharacterFrameInsetLeft.NineSlice)
  SaveAndHideRegion(_G.CharacterFrameInsetRight)
  SaveAndHideRegion(_G.CharacterFrameInsetRight and _G.CharacterFrameInsetRight.Bg)
  SaveAndHideRegion(_G.CharacterFrameInsetRight and _G.CharacterFrameInsetRight.NineSlice)
  SaveAndHideRegion(_G.CharacterStatsPane and _G.CharacterStatsPane.ClassBackground)
  SaveAndHideRegion(_G.CharacterStatsPane and _G.CharacterStatsPane.ItemLevelFrame and _G.CharacterStatsPane.ItemLevelFrame.Value)
  SaveAndHideRegion(_G.CharacterStatsPane and _G.CharacterStatsPane.ItemLevelFrame and _G.CharacterStatsPane.ItemLevelFrame.Title)
  SaveAndHideRegion(_G.CharacterStatsPaneItemLevelCategoryTitle)
  SaveAndHideRegion(_G.CharacterStatsPaneItemLevelCategoryValue)
  SaveAndHideRegion(_G.CharacterStatsPaneAttributesCategoryTitle)
  SaveAndHideRegion(_G.CharacterStatsPaneEnhancementsCategoryTitle)
  for i = 1, 80 do
    local row = _G["CharacterStatFrame" .. i]
    if row then
      SaveAndHideRegion(row)
      SaveAndHideRegion(row.Label or _G[row:GetName() .. "Label"])
      SaveAndHideRegion(row.Value or _G[row:GetName() .. "Value"])
    end
  end

  local slotFrameNames = {
    "CharacterBackSlotFrame",
    "CharacterChestSlotFrame",
    "CharacterFeetSlotFrame",
    "CharacterFinger0SlotFrame",
    "CharacterFinger1SlotFrame",
    "CharacterHandsSlotFrame",
    "CharacterHeadSlotFrame",
    "CharacterLegsSlotFrame",
    "CharacterMainHandSlotFrame",
    "CharacterNeckSlotFrame",
    "CharacterSecondaryHandSlotFrame",
    "CharacterShirtSlotFrame",
    "CharacterShoulderSlotFrame",
    "CharacterTabardSlotFrame",
    "CharacterTrinket0SlotFrame",
    "CharacterTrinket1SlotFrame",
    "CharacterWaistSlotFrame",
    "CharacterWristSlotFrame",
    "PaperDollInnerBorderBottom",
    "PaperDollInnerBorderBottom2",
    "PaperDollInnerBorderBottomLeft",
    "PaperDollInnerBorderBottomRight",
    "PaperDollInnerBorderLeft",
    "PaperDollInnerBorderRight",
    "PaperDollInnerBorderTop",
    "PaperDollInnerBorderTopLeft",
    "PaperDollInnerBorderTopRight",
  }
  for _, name in ipairs(slotFrameNames) do
    SaveAndHideRegion(_G[name])
  end

  if _G.CharacterModelScene and _G.CharacterModelScene.ControlFrame then
    SaveAndHideRegion(_G.CharacterModelScene.ControlFrame)
  end
end

local function ShowDefaultCharacterStats()
  if _G.CharacterStatsPane then
    _G.CharacterStatsPane:SetAlpha(1)
    _G.CharacterStatsPane:EnableMouse(true)
  end
  if _G.CharacterFrameInsetRight then
    _G.CharacterFrameInsetRight:SetAlpha(1)
    _G.CharacterFrameInsetRight:EnableMouse(true)
  end
  local function ShowRegion(r)
    if not r then return end
    if r.SetAlpha then r:SetAlpha(1) end
    if r.Show then r:Show() end
  end
  ShowRegion(_G.CharacterStatsPaneItemLevelCategoryTitle)
  ShowRegion(_G.CharacterStatsPaneItemLevelCategoryValue)
  ShowRegion(_G.CharacterStatsPaneAttributesCategoryTitle)
  ShowRegion(_G.CharacterStatsPaneEnhancementsCategoryTitle)
  for i = 1, 80 do
    local row = _G["CharacterStatFrame" .. i]
    if row then
      ShowRegion(row)
      ShowRegion(row.Label or _G[row:GetName() .. "Label"])
      ShowRegion(row.Value or _G[row:GetName() .. "Value"])
    end
  end
end

local function UpdateCustomStatsFrame(db)
  local frame = EnsureCustomStatsFrame()
  if not frame then return end
  if not CharacterFrame then return end

  -- Right-anchored compact stats column.
  local statsWidth = math.max(140, math.floor((CUSTOM_STATS_WIDTH * 0.9) + 0.5))
  local statsX = PRIMARY_SHEET_WIDTH - statsWidth - 8
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", statsX, -52)
  frame:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", statsX, 66)
  frame:SetWidth(statsWidth)

  local sections = BuildCustomStatsData()
  local width = frame:GetWidth()
  if not width or width < 120 then
    width = statsWidth
  end
  local gap = STAT_SECTION_GAP

  if frame.topInfo then
    frame.topInfo:ClearAllPoints()
    frame.topInfo:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.topInfo:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local avgOverall, avgEquipped
    if GetAverageItemLevel then
      avgOverall, avgEquipped = GetAverageItemLevel()
    end
    if type(avgOverall) == "number" and type(avgEquipped) == "number" then
      frame.topInfo.ilvl:SetText(("%.2f / %.2f"):format(avgEquipped, avgOverall))
    else
      frame.topInfo.ilvl:SetText("0.00 / 0.00")
    end

    local hp = UnitHealthMax and UnitHealthMax("player") or 0
    local hpText = BreakUpLargeNumbers and BreakUpLargeNumbers(hp) or tostring(hp or 0)
    frame.topInfo.healthRow.left:SetText(HEALTH or "Health")
    frame.topInfo.healthRow.right:SetText(hpText)
    frame.topInfo.healthRow.left:SetTextColor(1, 1, 1, 1)
    frame.topInfo.healthRow.right:SetTextColor(1, 1, 1, 1)
    frame.topInfo.healthRow.bg:ClearAllPoints()
    frame.topInfo.healthRow.bg:SetPoint("TOPLEFT", frame.topInfo.healthRow, "TOPLEFT", 1, 0)
    frame.topInfo.healthRow.bg:SetPoint("BOTTOMRIGHT", frame.topInfo.healthRow, "BOTTOMLEFT", math.floor(width * STAT_TOPINFO_GRADIENT_SPLIT), 0)
    SetHorizontalGradient(frame.topInfo.healthRow.bg, 0.55, 0.04, 0.04, 0.70, 0.55, 0.04, 0.04, 0.15)

    local powerType, powerToken = 0, "MANA"
    if UnitPowerType then
      powerType, powerToken = UnitPowerType("player")
    end
    local power = UnitPowerMax and UnitPowerMax("player", powerType) or 0
    local powerText = BreakUpLargeNumbers and BreakUpLargeNumbers(power) or tostring(power or 0)
    local powerLabel = (powerToken and _G[powerToken]) or _G.MANA or "Power"
    local info = (PowerBarColor and powerToken and PowerBarColor[powerToken]) or PowerBarColor and PowerBarColor["MANA"] or nil
    local pr, pg, pb = info and info.r or 0.2, info and info.g or 0.35, info and info.b or 0.95
    frame.topInfo.powerRow.left:SetText(powerLabel)
    frame.topInfo.powerRow.right:SetText(powerText)
    frame.topInfo.powerRow.left:SetTextColor(1, 1, 1, 1)
    frame.topInfo.powerRow.right:SetTextColor(1, 1, 1, 1)
    frame.topInfo.powerRow.bg:ClearAllPoints()
    frame.topInfo.powerRow.bg:SetPoint("TOPLEFT", frame.topInfo.powerRow, "TOPLEFT", 1, 0)
    frame.topInfo.powerRow.bg:SetPoint("BOTTOMRIGHT", frame.topInfo.powerRow, "BOTTOMLEFT", math.floor(width * STAT_TOPINFO_GRADIENT_SPLIT), 0)
    SetHorizontalGradient(frame.topInfo.powerRow.bg, pr, pg, pb, 0.70, pr, pg, pb, 0.15)
    frame.topInfo:Show()
  end

  local y = frame.topInfo and -(frame.topInfo:GetHeight() + gap + 1) or -2

  for i = 1, #frame.sections do
    local secFrame = frame.sections[i]
    local secData = sections[i] or { title = "", rows = {} }
    local rowCount = #secData.rows
    if rowCount < 1 then rowCount = 1 end
    local secHeight = 24 + (rowCount * STAT_ROW_HEIGHT) + 8

    secFrame:ClearAllPoints()
    secFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
    secFrame:SetSize(width, secHeight)
    secFrame.title:SetText(secData.title or "")
    local color = SECTION_COLORS[i] or SECTION_COLORS[#SECTION_COLORS]
    if color then
      secFrame:SetBackdropBorderColor(color[1] * 0.75, color[2] * 0.75, color[3] * 0.75, 0.95)
      if secFrame.headerTint then
        secFrame.headerTint:ClearAllPoints()
        secFrame.headerTint:SetPoint("TOPRIGHT", secFrame, "TOPRIGHT", -1, -1)
        secFrame.headerTint:SetPoint("BOTTOMLEFT", secFrame, "TOPLEFT", math.floor(width * (1 - STAT_GRADIENT_SPLIT)), -23)
        SetHorizontalGradient(secFrame.headerTint, 0, 0, 0, color[4] * 0.10, color[1], color[2], color[3], color[4] * STAT_HEADER_GRADIENT_ALPHA)
        secFrame.headerTint:Show()
      end
      if secFrame.tint then
        secFrame.tint:ClearAllPoints()
        secFrame.tint:SetPoint("TOPLEFT", secFrame, "TOPLEFT", 1, -23)
        secFrame.tint:SetPoint("BOTTOMRIGHT", secFrame, "BOTTOMLEFT", math.floor(width * STAT_BODY_GRADIENT_SPLIT), 1)
        SetHorizontalGradient(secFrame.tint, color[1], color[2], color[3], color[4] * STAT_BODY_GRADIENT_ALPHA, 0, 0, 0, color[4] * 0.04)
        secFrame.tint:Show()
      end
    else
      secFrame:SetBackdropBorderColor(0.22, 0.18, 0.08, 0.9)
      if secFrame.tint then secFrame.tint:SetColorTexture(0, 0, 0, 0) end
      if secFrame.headerTint then secFrame.headerTint:SetColorTexture(0, 0, 0, 0) end
    end

    local rowY = -24
    for r = 1, #secFrame.rows do
      local rowFrame = secFrame.rows[r]
      local rowData = secData.rows[r]
      rowFrame:ClearAllPoints()
      rowFrame:SetPoint("TOPLEFT", secFrame, "TOPLEFT", 0, rowY)
      rowFrame:SetPoint("TOPRIGHT", secFrame, "TOPRIGHT", 0, rowY)
      if rowData then
        if rowFrame.bg and color then
          local a = STAT_ROW_GRADIENT_ALPHA
          rowFrame.bg:ClearAllPoints()
          rowFrame.bg:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 1, 0)
          rowFrame.bg:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMLEFT", math.floor(width * STAT_ROW_GRADIENT_SPLIT), 0)
          SetHorizontalGradient(
            rowFrame.bg,
            color[1], color[2], color[3], a,
            0, 0, 0, a * 0.08
          )
          if rowFrame.bg.SetBlendMode then rowFrame.bg:SetBlendMode("BLEND") end
          if rowFrame.bg.SetAlpha then rowFrame.bg:SetAlpha(1) end
          rowFrame.bg:Show()
        elseif rowFrame.bg then
          rowFrame.bg:SetColorTexture(0, 0, 0, 0.12)
          rowFrame.bg:Show()
        end
        rowFrame.left:SetText(rowData[1] or "")
        rowFrame.right:SetText(rowData[2] or "")
        rowFrame:Show()
      else
        if rowFrame.bg then rowFrame.bg:Hide() end
        rowFrame:Hide()
      end
      rowY = rowY - STAT_ROW_HEIGHT
    end

    secFrame:Show()
    y = y - secHeight - gap
  end

  ApplyCustomStatsFont(db)
  frame:Show()
end

local function ParseEnchantName(itemLink)
  if type(itemLink) ~= "string" then return "" end
  local enchantID = tonumber(itemLink:match("^|?c?[^|]*|?Hitem:%d+:(%-?%d+)")) or 0
  if enchantID and enchantID > 0 then
    local name
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
      name = C_Spell.GetSpellName(enchantID)
    end
    if (not name or name == "") and type(GetSpellInfo) == "function" then
      name = GetSpellInfo(enchantID)
    end
    if name and name ~= "" then
      return name
    end
  end
  return ""
end

local function EnsureCustomGearFrame()
  if customGearFrame then return customGearFrame end
  if not CharacterFrame then return nil end

  customGearFrame = CreateFrame("Frame", nil, CharacterFrame)
  customGearFrame:SetFrameStrata("HIGH")
  customGearFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 15)
  customGearFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
  customGearFrame:SetSize(PRIMARY_SHEET_WIDTH - 16, CUSTOM_CHAR_HEIGHT - 102)
  customGearFrame:SetClipsChildren(true)
  customGearFrame:Hide()

  customGearFrame.topLeft = customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  customGearFrame.topLeft:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 40, -40)
  customGearFrame.topLeft:SetText("Mythic+ Rating:")
  customGearFrame.topLeftValue = customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  customGearFrame.topLeftValue:SetPoint("TOPLEFT", customGearFrame.topLeft, "BOTTOMLEFT", 0, -2)
  customGearFrame.topLeftValue:SetTextColor(1, 0.5, 0.1, 1)

  customGearFrame.topCenter = customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  customGearFrame.topCenter:SetPoint("TOP", CharacterFrame, "TOP", 0, -30)
  customGearFrame.topCenter:SetTextColor(1, 1, 1, 1)
  customGearFrame.topCenter:SetShadowOffset(1, -1)
  customGearFrame.topCenter:SetShadowColor(0, 0, 0, 1)
  customGearFrame.topSub = customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  customGearFrame.topSub:SetPoint("TOP", customGearFrame.topCenter, "BOTTOM", 0, -2)
  customGearFrame.topSub:SetTextColor(1, 1, 1, 1)

  customGearFrame.topRight = customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  customGearFrame.topRight:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -44, -38)
  customGearFrame.topRight:SetJustifyH("RIGHT")
  customGearFrame.topRight:SetTextColor(0.75, 0.75, 1, 1)

  customGearFrame.leftRows = {}
  customGearFrame.rightRows = {}
  for i = 1, #LEFT_GEAR_SLOTS do
    local row = CreateFrame("Frame", nil, customGearFrame)
    row:SetSize(240, 38)
    row:SetClipsChildren(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(true)
    row.bg:SetColorTexture(0.14, 0.02, 0.20, 0.32)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(222)
    row.name:SetMaxLines(1)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.name:SetTextColor(0.92, 0.46, 1.0, 1)
    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetWidth(222)
    row.meta:SetMaxLines(1)
    if row.meta.SetWordWrap then row.meta:SetWordWrap(false) end
    row.meta:SetTextColor(0.1, 1, 0.75, 1)
    customGearFrame.leftRows[i] = row
  end
  for i = 1, #RIGHT_GEAR_SLOTS do
    local row = CreateFrame("Frame", nil, customGearFrame)
    row:SetSize(240, 38)
    row:SetClipsChildren(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(true)
    row.bg:SetColorTexture(0.14, 0.02, 0.20, 0.32)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.name:SetJustifyH("RIGHT")
    row.name:SetWidth(222)
    row.name:SetMaxLines(1)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.name:SetTextColor(0.92, 0.46, 1.0, 1)
    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.meta:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -2)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetWidth(222)
    row.meta:SetMaxLines(1)
    if row.meta.SetWordWrap then row.meta:SetWordWrap(false) end
    row.meta:SetTextColor(0.1, 1, 0.75, 1)
    customGearFrame.rightRows[i] = row
  end

  return customGearFrame
end

local function UpdateGearRows(rows, slots, rightAlign)
  local anchorFrame = _G.PaperDollFrame or customGearFrame
  for i, slotName in ipairs(slots) do
    local row = rows[i]
    local btn = _G["Character" .. slotName]
    if row and btn then
      row:ClearAllPoints()
      row:SetWidth(210)
      if rightAlign then
        row:SetPoint("RIGHT", btn, "LEFT", -6, 0)
      else
        row:SetPoint("LEFT", btn, "RIGHT", 6, 0)
      end
      local invID = GetInventorySlotInfo(slotName)
      local link = invID and GetInventoryItemLink("player", invID) or nil
      if link then
        local name, _, quality = GetItemInfo(link)
        local ilvl = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link) or nil
        local enchant = ParseEnchantName(link)
        local r, g, b = 0.92, 0.46, 1.0
        if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
          r = ITEM_QUALITY_COLORS[quality].r
          g = ITEM_QUALITY_COLORS[quality].g
          b = ITEM_QUALITY_COLORS[quality].b
        end
        row.name:SetText(name or slotName)
        row.name:SetTextColor(r, g, b, 1)
        local meta = (ilvl and tostring(math.floor(ilvl + 0.5)) or "")
        if enchant ~= "" then
          if meta ~= "" then
            meta = meta .. "  "
          end
          meta = meta .. enchant
        end
        row.meta:SetText(meta)
        row:Show()
      else
        row.name:SetText("")
        row.meta:SetText("")
        row:Hide()
      end
    end
  end
end

local function UpdateCustomGearFrame(db)
  local frame = EnsureCustomGearFrame()
  if not frame then return end
  local paper = _G.PaperDollFrame or CharacterFrame
  if frame.topLeft and frame.topLeft.ClearAllPoints then
    frame.topLeft:ClearAllPoints()
    frame.topLeft:SetPoint("TOPLEFT", paper, "TOPLEFT", 34, -22)
  end
  if frame.topCenter and frame.topCenter.ClearAllPoints then
    frame.topCenter:ClearAllPoints()
    frame.topCenter:SetPoint("TOP", paper, "TOP", 0, -10)
  end
  if frame.topSub and frame.topSub.ClearAllPoints then
    frame.topSub:ClearAllPoints()
    frame.topSub:SetPoint("TOP", frame.topCenter, "BOTTOM", 0, -2)
  end
  if frame.topRight and frame.topRight.ClearAllPoints then
    frame.topRight:ClearAllPoints()
    frame.topRight:SetPoint("TOPRIGHT", paper, "TOPRIGHT", -34, -24)
  end

  local rating = 0
  if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
    local info = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    if type(info) == "table" then
      rating = info.currentSeasonScore or 0
    end
  end
  frame.topLeftValue:SetText(tostring(math.floor((rating or 0) + 0.5)))

  local name = UnitName("player") or ""
  local className = UnitClass("player") or ""
  local level = UnitLevel("player") or 0
  frame.topCenter:SetText(name)
  frame.topSub:SetText(("Level %d %s"):format(level, className))

  frame.topRight:SetText("")

  UpdateGearRows(frame.leftRows, LEFT_GEAR_SLOTS, false)
  UpdateGearRows(frame.rightRows, RIGHT_GEAR_SLOTS, true)

  local fontPath, size, outline = GetConfiguredFont(db)
  if frame.topLeft and frame.topLeft.SetFont then frame.topLeft:SetFont(fontPath, size + 1, outline) end
  if frame.topLeftValue and frame.topLeftValue.SetFont then frame.topLeftValue:SetFont(fontPath, size + 5, outline) end
  if frame.topCenter and frame.topCenter.SetFont then frame.topCenter:SetFont(fontPath, size + 2, outline) end
  if frame.topSub and frame.topSub.SetFont then frame.topSub:SetFont(fontPath, size + 1, outline) end
  if frame.topRight and frame.topRight.SetFont then frame.topRight:SetFont(fontPath, size + 1, outline) end
  for _, row in ipairs(frame.leftRows or {}) do
    if row.name and row.name.SetFont then row.name:SetFont(fontPath, math.max(10, size), outline) end
    if row.meta and row.meta.SetFont then row.meta:SetFont(fontPath, math.max(9, size - 1), outline) end
  end
  for _, row in ipairs(frame.rightRows or {}) do
    if row.name and row.name.SetFont then row.name:SetFont(fontPath, math.max(10, size), outline) end
    if row.meta and row.meta.SetFont then row.meta:SetFont(fontPath, math.max(9, size - 1), outline) end
  end

  frame:Show()
end

local function ApplyCustomCharacterLayout()
  if not CharacterFrame then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if not layoutApplied then
    CaptureLayout("character", CharacterFrame)
    CaptureLayout("inset", _G.CharacterFrameInset)
    CaptureLayout("insetRight", _G.CharacterFrameInsetRight)
    CaptureLayout("insetLeft", _G.CharacterFrameInsetLeft)
    CaptureLayout("paper", _G.PaperDollFrame)
    CaptureLayout("stats", _G.CharacterStatsPane)
    CaptureLayout("tab1", _G.CharacterFrameTab1)
    CaptureLayout("model", _G.CharacterModelScene)
    CaptureLayout("closeBtn", _G.CharacterFrameCloseButton)
  end

  CharacterFrame:SetSize(PRIMARY_SHEET_WIDTH, CUSTOM_CHAR_HEIGHT)

  local inset = _G.CharacterFrameInset
  if inset then
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
    inset:SetSize(PRIMARY_SHEET_WIDTH - 16, CUSTOM_CHAR_HEIGHT - 102)
  end

  local insetLeft = _G.CharacterFrameInsetLeft
  local leftWidth = PRIMARY_SHEET_WIDTH - CUSTOM_STATS_WIDTH - CUSTOM_PANE_GAP - 36
  if leftWidth < 320 then
    leftWidth = 320
  end
  if insetLeft then
    insetLeft:ClearAllPoints()
    insetLeft:SetPoint("TOPLEFT", inset or CharacterFrame, "TOPLEFT", 0, 0)
    insetLeft:SetPoint("BOTTOMLEFT", inset or CharacterFrame, "BOTTOMLEFT", 0, 0)
    insetLeft:SetWidth(leftWidth)
  end

  local insetRight = _G.CharacterFrameInsetRight
  if insetRight then
    insetRight:ClearAllPoints()
    insetRight:SetPoint("TOPLEFT", insetLeft or inset or CharacterFrame, "TOPRIGHT", 4, 0)
    insetRight:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -4, 44)
  end

  local paper = _G.PaperDollFrame
  if paper then
    paper:ClearAllPoints()
    paper:SetPoint("TOPLEFT", insetLeft or inset or CharacterFrame, "TOPLEFT", 0, 0)
    paper:SetPoint("BOTTOMRIGHT", insetLeft or inset or CharacterFrame, "BOTTOMRIGHT", 0, 0)
    paper:SetWidth(leftWidth)
  end

  local stats = _G.CharacterStatsPane
  if stats then
    stats:ClearAllPoints()
    stats:SetPoint("TOPLEFT", insetRight or inset or CharacterFrame, "TOPLEFT", 13, -3)
    stats:SetPoint("BOTTOMRIGHT", insetRight or inset or CharacterFrame, "BOTTOMRIGHT", -3, 2)
  end

  local tab1 = _G.CharacterFrameTab1
  if tab1 then
    tab1:ClearAllPoints()
    tab1:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 16, 10)
  end

  local closeBtn = _G.CharacterFrameCloseButton
  if closeBtn then
    closeBtn:ClearAllPoints()
    closeBtn:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -6, -3)
  end

  local panel = EnsureCustomCharacterFrame()
  if panel then
    panel:Show()
    SafeFrameLevel(panel, (CharacterFrame:GetFrameLevel() or 1) - 2)
  end
  layoutApplied = true
end

local function StyleStatRows(db)
  local stripeAlpha = (db and db.charsheet and db.charsheet.stripeAlpha) or 0.22
  local fontPath, size, outline = GetConfiguredFont(db)

  for i = 1, 80 do
    local row = _G["CharacterStatFrame" .. i]
    if row then
      if not statRows[row] then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
        statRows[row] = bg
      end

      local bg = statRows[row]
      local a = ((i % 2) == 0) and (stripeAlpha * 0.75) or stripeAlpha
      bg:SetColorTexture(0.12, 0.04, 0.18, a)
      bg:Show()

      local label = row.Label or _G[row:GetName() .. "Label"]
      local value = row.Value or _G[row:GetName() .. "Value"]
      if label and label.SetFont then
        BackupFont(label)
        label:SetFont(fontPath, size, outline)
      end
      if value and value.SetFont then
        BackupFont(value)
        value:SetFont(fontPath, size, outline)
      end
    end
  end
end

local function StyleStatsHeaders(db)
  local fontPath, size, outline = GetConfiguredFont(db)
  local statsPane = _G.CharacterStatsPane
  local headerNames = {
    "CharacterStatsPaneItemLevelFrameTitle",
    "CharacterStatsPaneItemLevelCategoryTitle",
    "CharacterStatsPaneAttributesCategoryTitle",
    "CharacterStatsPaneEnhancementsCategoryTitle",
  }
  local valueNames = {
    "CharacterStatsPaneItemLevelFrameValue",
    "CharacterStatsPaneItemLevelCategoryValue",
  }

  for _, name in ipairs(headerNames) do
    local fs = _G[name]
    if fs and fs.SetFont then
      BackupFont(fs)
      fs:SetFont(fontPath, size + 1, outline)
      fs:SetTextColor(0.95, 0.85, 0.35, 1)
    end
  end

  for _, name in ipairs(valueNames) do
    local fs = _G[name]
    if fs and fs.SetFont then
      BackupFont(fs)
      fs:SetFont(fontPath, size + 3, outline)
      fs:SetTextColor(0.98, 0.98, 0.98, 1)
    end
  end

  local cards = {
    (statsPane and (statsPane.ItemLevelCategory or statsPane.ItemLevelFrame)) or _G.CharacterStatsPaneItemLevelCategory or _G.CharacterStatsPaneItemLevelFrame,
    (statsPane and statsPane.AttributesCategory) or _G.CharacterStatsPaneAttributesCategory,
    (statsPane and statsPane.EnhancementsCategory) or _G.CharacterStatsPaneEnhancementsCategory,
  }
  for idx, card in ipairs(cards) do
    if card then
      local bg = EnsurePanelSkin("header_card_" .. idx, card)
      if bg then
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", card, "TOPLEFT", -8, 6)
        bg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 8, -6)
        SafeFrameLevel(bg, (card:GetFrameLevel() or 1) - 1)
        bg:SetBackdropColor(0.10, 0.04, 0.16, 0.90)
        bg:SetBackdropBorderColor(0.40, 0.24, 0.58, 0.95)
        bg:Show()
      end
    end
  end
end

local function StylePaperDollSlots()
  local slotNames = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
  }

  for _, name in ipairs(slotNames) do
    local btn = _G[name]
    if btn then
      if btn.SetSize then
        btn:SetSize(SLOT_ICON_SIZE, SLOT_ICON_SIZE)
      end
      if btn.SetSnapToPixelGrid then btn:SetSnapToPixelGrid(true) end
      if btn.SetTexelSnappingBias then btn:SetTexelSnappingBias(0) end
      if btn.SetScale then btn:SetScale(1) end
      local skin = EnsureSlotSkin(btn)
      if skin then skin:Show() end

      local icon = _G[name .. "IconTexture"] or btn.icon or btn.Icon
      if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(true) end
        if icon.SetTexelSnappingBias then icon:SetTexelSnappingBias(0) end
      end

      SaveAndHideRegion(_G[name .. "NormalTexture"])
      SaveAndHideRegion(_G[name .. "HighlightTexture"])
      SaveAndHideRegion(_G[name .. "Background"])

      if name == "CharacterMainHandSlot" or name == "CharacterSecondaryHandSlot" then
        SaveAndHideRegion(btn.BottomLeftSlotTexture)
        SaveAndHideRegion(btn.BottomRightSlotTexture)
        SaveAndHideRegion(btn.SlotTexture)
        SaveAndHideRegion(btn.IconOverlay)
        SaveAndHideRegion(btn.PopoutButton)
        SaveAndHideRegion(btn.ShadowOverlay)
        SaveAndHideRegion(btn.Border)
        SaveAndHideRegion(_G[name .. "PopoutButton"])
        SaveAndHideRegion(_G[name .. "SlotTexture"])
        SaveAndHideRegion(_G[name .. "ShadowOverlay"])
        SaveAndHideRegion(_G[name .. "IconOverlay"])
        SaveAndHideRegion(_G[name .. "Border"])

        if btn.GetChildren then
          for i = 1, select("#", btn:GetChildren()) do
            local child = select(i, btn:GetChildren())
            if child then
              local childName = child.GetName and child:GetName()
              if childName and childName:find("Popout") then
                SaveAndHideRegion(child)
                if child.EnableMouse then child:EnableMouse(false) end
              end
            end
          end
        end
        -- Strip any remaining Blizzard decorative textures on weapon/offhand slots.
        if btn.GetRegions then
          for i = 1, select("#", btn:GetRegions()) do
            local region = select(i, btn:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
              if region ~= icon and region ~= btn.IconBorder and region ~= btn.icon then
                SaveAndHideRegion(region)
              end
            end
          end
        end
      end
    end
  end
end

local function ApplyChonkySlotLayout()
  local anchor = _G.CharacterFrameBg or CharacterFrame
  if not anchor then return end

  SaveAndHideRegion(_G.CharacterFrame and _G.CharacterFrame.NineSlice)
  SaveAndHideRegion(_G.CharacterFramePortrait)
  SaveAndHideRegion(_G.CharacterFrameInsetRight and _G.CharacterFrameInsetRight.Bg)
  SaveAndHideRegion(_G.CharacterFrameInsetRight and _G.CharacterFrameInsetRight.NineSlice)

  local slotFrames = {
    "CharacterBackSlotFrame", "CharacterChestSlotFrame", "CharacterFeetSlotFrame",
    "CharacterFinger0SlotFrame", "CharacterFinger1SlotFrame", "CharacterHandsSlotFrame",
    "CharacterHeadSlotFrame", "CharacterLegsSlotFrame", "CharacterMainHandSlotFrame",
    "CharacterNeckSlotFrame", "CharacterSecondaryHandSlotFrame", "CharacterShirtSlotFrame",
    "CharacterShoulderSlotFrame", "CharacterTabardSlotFrame", "CharacterTrinket0SlotFrame",
    "CharacterTrinket1SlotFrame", "CharacterWaistSlotFrame", "CharacterWristSlotFrame",
  }
  for _, name in ipairs(slotFrames) do
    SaveAndHideRegion(_G[name])
  end

  local vpad = 18

  local head = _G.CharacterHeadSlot
  local neck = _G.CharacterNeckSlot
  local shoulder = _G.CharacterShoulderSlot
  local back = _G.CharacterBackSlot
  local chest = _G.CharacterChestSlot
  local shirt = _G.CharacterShirtSlot
  local tabard = _G.CharacterTabardSlot
  local wrist = _G.CharacterWristSlot
  local hands = _G.CharacterHandsSlot
  local waist = _G.CharacterWaistSlot
  local legs = _G.CharacterLegsSlot
  local feet = _G.CharacterFeetSlot
  local finger0 = _G.CharacterFinger0Slot
  local finger1 = _G.CharacterFinger1Slot
  local trinket0 = _G.CharacterTrinket0Slot
  local trinket1 = _G.CharacterTrinket1Slot
  local mainHand = _G.CharacterMainHandSlot
  local offHand = _G.CharacterSecondaryHandSlot

  if not (head and neck and shoulder and back and chest and shirt and tabard and wrist and hands and waist and legs and feet and finger0 and finger1 and trinket0 and trinket1 and mainHand and offHand) then
    return
  end

  head:ClearAllPoints()
  head:SetPoint("TOPLEFT", anchor, "TOPLEFT", 14, -60)
  neck:ClearAllPoints()
  neck:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -vpad)
  shoulder:ClearAllPoints()
  shoulder:SetPoint("TOPLEFT", neck, "BOTTOMLEFT", 0, -vpad)
  back:ClearAllPoints()
  back:SetPoint("TOPLEFT", shoulder, "BOTTOMLEFT", 0, -vpad)
  chest:ClearAllPoints()
  chest:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -vpad)
  shirt:ClearAllPoints()
  shirt:SetPoint("TOPLEFT", chest, "BOTTOMLEFT", 0, -vpad)
  tabard:ClearAllPoints()
  tabard:SetPoint("TOPLEFT", shirt, "BOTTOMLEFT", 0, -vpad)
  wrist:ClearAllPoints()
  wrist:SetPoint("TOPLEFT", tabard, "BOTTOMLEFT", 0, -vpad)

  hands:ClearAllPoints()
  -- Keep only a slight gap between right slot column and stats panel.
  local statsWidth = math.max(140, math.floor((CUSTOM_STATS_WIDTH * 0.9) + 0.5))
  local rightColumnX = PRIMARY_SHEET_WIDTH - statsWidth - 55
  hands:SetPoint("TOPLEFT", anchor, "TOPLEFT", rightColumnX, -60)
  waist:ClearAllPoints()
  waist:SetPoint("TOPLEFT", hands, "BOTTOMLEFT", 0, -vpad)
  legs:ClearAllPoints()
  legs:SetPoint("TOPLEFT", waist, "BOTTOMLEFT", 0, -vpad)
  feet:ClearAllPoints()
  feet:SetPoint("TOPLEFT", legs, "BOTTOMLEFT", 0, -vpad)
  finger0:ClearAllPoints()
  finger0:SetPoint("TOPLEFT", feet, "BOTTOMLEFT", 0, -vpad)
  finger1:ClearAllPoints()
  finger1:SetPoint("TOPLEFT", finger0, "BOTTOMLEFT", 0, -vpad)
  trinket0:ClearAllPoints()
  trinket0:SetPoint("TOPLEFT", finger1, "BOTTOMLEFT", 0, -vpad)
  trinket1:ClearAllPoints()
  trinket1:SetPoint("TOPLEFT", trinket0, "BOTTOMLEFT", 0, -vpad)

  local leftColumnX = 14
  local slotSize = SLOT_ICON_SIZE
  local pairGapX = 68 -- ~30% more spacing than 52 while keeping center alignment
  local leftColumnCenter = leftColumnX + (slotSize * 0.5)
  local rightColumnCenter = rightColumnX + (slotSize * 0.5)
  local centerX = math.floor(((leftColumnCenter + rightColumnCenter) * 0.5) + 0.5)
  local mainHandX = math.floor((centerX - (pairGapX * 0.5) - (slotSize * 0.5)) + 0.5)

  mainHand:ClearAllPoints()
  mainHand:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", mainHandX, 32)
  offHand:ClearAllPoints()
  offHand:SetPoint("TOPLEFT", mainHand, "TOPLEFT", pairGapX, 0)
end

local function ApplyChonkyModelLayout()
  local model = _G.CharacterModelScene
  if not model then return end

  local fill = EnsureModelFillFrame()
  local boxTop, boxBottom = -84, 46
  local boxWidth = 356
  local statsWidth = math.max(140, math.floor((CUSTOM_STATS_WIDTH * 0.9) + 0.5))
  local leftColumnX = 14
  local rightColumnX = PRIMARY_SHEET_WIDTH - statsWidth - 55
  local slotSize = SLOT_ICON_SIZE
  local leftColumnCenter = leftColumnX + (slotSize * 0.5)
  local rightColumnCenter = rightColumnX + (slotSize * 0.5)
  local slotMidX = (leftColumnCenter + rightColumnCenter) * 0.5
  local desiredCenterX = slotMidX
  local boxLeft = math.floor(desiredCenterX - (boxWidth * 0.5) + 0.5)
  local boxRight = boxLeft + boxWidth

  model:ClearAllPoints()
  -- Fill one explicit center box between gear columns.
  model:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", boxLeft, boxTop)
  model:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", boxRight, boxBottom)
  SuppressModelSceneBorderArt()

  if model.SetFrameLevel then
    model:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 3)
  end
  if model.EnableMouse then model:EnableMouse(true) end
  if model.EnableMouseWheel then model:EnableMouseWheel(false) end
  if model.SetScript then model:SetScript("OnMouseWheel", function() end) end
  if model.SetPropagateMouseClicks then model:SetPropagateMouseClicks(false) end
  if model.SetPropagateMouseMotion then model:SetPropagateMouseMotion(false) end
  if model.SetCameraTarget then pcall(model.SetCameraTarget, model, 0, 0, 0) end
  if model.ResetCamera then pcall(model.ResetCamera, model) end
  if model.ResetCameras then pcall(model.ResetCameras, model) end
  if model.ResetViewTranslation then pcall(model.ResetViewTranslation, model) end
  if model.RefreshCamera then pcall(model.RefreshCamera, model) end

  if model.SetCameraDistanceScale then
    modelLockedCameraScale = 1.32
    pcall(model.SetCameraDistanceScale, model, modelLockedCameraScale)
  end

  if model.ControlFrame then
    SaveAndHideRegion(model.ControlFrame)
    if model.ControlFrame.EnableMouse then model.ControlFrame:EnableMouse(true) end
    if model.ControlFrame.EnableMouseWheel then model.ControlFrame:EnableMouseWheel(false) end
    if model.ControlFrame.SetScript then model.ControlFrame:SetScript("OnMouseWheel", function() end) end
    if model.ControlFrame.GetChildren then
      for i = 1, select("#", model.ControlFrame:GetChildren()) do
        local child = select(i, model.ControlFrame:GetChildren())
        if child then
          SaveAndHideRegion(child)
          if child.EnableMouse then child:EnableMouse(false) end
          if child.EnableMouseWheel then child:EnableMouseWheel(false) end
          if child.SetScript then child:SetScript("OnMouseWheel", function() end) end
        end
      end
    end
  end
  if _G.PaperDollFrame and _G.PaperDollFrame.EnableMouseWheel then
    _G.PaperDollFrame:EnableMouseWheel(false)
  end

  if model.GetPlayerActor then
    local actor = model:GetPlayerActor()
    if actor and actor.GetModelScale and actor.SetModelScale then
      if not modelBaseScale then
        local s = actor:GetModelScale()
        if type(s) == "number" and s > 0 then
          modelBaseScale = s
        end
      end
      if modelBaseScale then
        actor:SetModelScale(modelBaseScale * MODEL_ZOOM_OUT_FACTOR)
      end
    end
    if actor and actor.SetPosition then
      pcall(actor.SetPosition, actor, 0, 0, 0)
    end
  end

  if fill then
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -2, 2)
    fill:Show()
  end
end

local function HideTabArt()
  local tabs = {
    _G.CharacterFrameTab1,
    _G.CharacterFrameTab2,
    _G.CharacterFrameTab3,
    _G.CharacterFrameTab4,
  }
  for _, tab in ipairs(tabs) do
    if tab then
      SaveAndHideRegion(_G[tab:GetName() .. "Left"])
      SaveAndHideRegion(_G[tab:GetName() .. "Middle"])
      SaveAndHideRegion(_G[tab:GetName() .. "Right"])
      SaveAndHideRegion(_G[tab:GetName() .. "LeftDisabled"])
      SaveAndHideRegion(_G[tab:GetName() .. "MiddleDisabled"])
      SaveAndHideRegion(_G[tab:GetName() .. "RightDisabled"])
    end
  end
end

local function HideCharacterTabsButtons()
  local tabs = {
    _G.CharacterFrameTab1,
    _G.CharacterFrameTab2,
    _G.CharacterFrameTab3,
    _G.CharacterFrameTab4,
  }
  for _, tab in ipairs(tabs) do
    if tab then
      SaveAndHideRegion(tab)
      if tab.EnableMouse then tab:EnableMouse(false) end
    end
  end
end

local function ApplyMinimalChonkyBase()
  -- Keep only the essential character foundation visible.
  local toHide = {
    _G.CharacterFrameBg,
    _G.CharacterFrameTitleBg,
    _G.CharacterFrameTopTileStreaks,
    _G.CharacterFrameTopBorder,
    _G.CharacterFrameBotLeft,
    _G.CharacterFrameBotRight,
    _G.CharacterFrame and _G.CharacterFrame.Bg,
    _G.CharacterFrame and _G.CharacterFrame.Background,
    _G.CharacterFrame and _G.CharacterFrame.NineSlice,
    _G.CharacterFramePortrait,
    _G.CharacterFrameTitleText,
    _G.CharacterLevelText,
    _G.CharacterFrameInset,
    _G.CharacterFrameInsetLeft,
    _G.CharacterFrameInsetRight,
    _G.CharacterFrameInset and _G.CharacterFrameInset.Bg,
    _G.CharacterFrameInset and _G.CharacterFrameInset.NineSlice,
    _G.CharacterFrameInsetLeft and _G.CharacterFrameInsetLeft.Bg,
    _G.CharacterFrameInsetLeft and _G.CharacterFrameInsetLeft.NineSlice,
    _G.CharacterFrameInsetRight and _G.CharacterFrameInsetRight.Bg,
    _G.CharacterFrameInsetRight and _G.CharacterFrameInsetRight.NineSlice,
    _G.CharacterStatsPane,
    _G.CharacterStatsPane and _G.CharacterStatsPane.Background,
    _G.CharacterStatsPane and _G.CharacterStatsPane.Bg,
    _G.CharacterStatsPane and _G.CharacterStatsPane.NineSlice,
    _G.CharacterStatsPane and _G.CharacterStatsPane.ClassBackground,
    _G.PaperDollInnerBorderBottom,
    _G.PaperDollInnerBorderBottom2,
    _G.PaperDollInnerBorderBottomLeft,
    _G.PaperDollInnerBorderBottomRight,
    _G.PaperDollInnerBorderLeft,
    _G.PaperDollInnerBorderRight,
    _G.PaperDollInnerBorderTop,
    _G.PaperDollInnerBorderTopLeft,
    _G.PaperDollInnerBorderTopRight,
    _G.CharacterModelFrameBackgroundTopLeft,
    _G.CharacterModelFrameBackgroundTopRight,
    _G.CharacterModelFrameBackgroundBotLeft,
    _G.CharacterModelFrameBackgroundBotRight,
    _G.CharacterModelFrameBackgroundOverlay,
    _G.CharacterModelScene and _G.CharacterModelScene.Background,
    _G.CharacterModelScene and _G.CharacterModelScene.BG,
  }
  for _, region in ipairs(toHide) do
    SaveAndHideRegion(region)
  end

  if _G.CharacterFrameInset then
    _G.CharacterFrameInset:SetAlpha(0)
    _G.CharacterFrameInset:EnableMouse(false)
  end
  if _G.CharacterFrameInsetLeft then
    _G.CharacterFrameInsetLeft:SetAlpha(0)
    _G.CharacterFrameInsetLeft:EnableMouse(false)
  end
  if _G.CharacterFrameInsetRight then
    _G.CharacterFrameInsetRight:SetAlpha(0)
    _G.CharacterFrameInsetRight:EnableMouse(false)
  end
  if _G.CharacterStatsPane then
    _G.CharacterStatsPane:SetAlpha(0)
    _G.CharacterStatsPane:EnableMouse(false)
  end
  if _G.CharacterModelScene and _G.CharacterModelScene.ControlFrame then
    SaveAndHideRegion(_G.CharacterModelScene.ControlFrame)
  end

  -- Strip any remaining default texture regions that create ghost borders.
  HideFrameTextureRegions(_G.CharacterFrame)
  HideFrameTextureRegions(_G.PaperDollFrame)
  HideFrameTextureRegions(_G.CharacterModelScene)
  AggressiveStripFrame(_G.CharacterModelScene)
end

local function StyleCorePanels()
  if not CharacterFrame then return end

  local modelAnchor = _G.PaperDollFrame or _G.CharacterModelScene
  local statsAnchor = _G.CharacterStatsPane
  local tabsAnchor = _G.CharacterFrameInset

  if modelAnchor then
    local modelPanel = EnsurePanelSkin("model_panel", CharacterFrame)
    if modelPanel then
      modelPanel:ClearAllPoints()
      modelPanel:SetPoint("TOPLEFT", modelAnchor, "TOPLEFT", 0, 0)
      modelPanel:SetPoint("BOTTOMRIGHT", modelAnchor, "BOTTOMRIGHT", 0, 0)
      SafeFrameLevel(modelPanel, (modelAnchor:GetFrameLevel() or 1) - 2)
      modelPanel:SetBackdropColor(0.03, 0.01, 0.06, 0.92)
      modelPanel:SetBackdropBorderColor(0.34, 0.17, 0.52, 0.95)
      modelPanel:Show()
    end
  end

  if statsAnchor then
    local statsPanel = EnsurePanelSkin("stats_panel", CharacterFrame)
    if statsPanel then
      statsPanel:ClearAllPoints()
      statsPanel:SetPoint("TOPLEFT", statsAnchor, "TOPLEFT", 0, 0)
      statsPanel:SetPoint("BOTTOMRIGHT", statsAnchor, "BOTTOMRIGHT", 0, 0)
      SafeFrameLevel(statsPanel, (statsAnchor:GetFrameLevel() or 1) - 2)
      statsPanel:SetBackdropColor(0.02, 0.01, 0.05, 0.94)
      statsPanel:SetBackdropBorderColor(0.34, 0.17, 0.52, 0.95)
      statsPanel:Show()
    end
  end

  if tabsAnchor then
    local tabsPanel = EnsurePanelSkin("tabs_panel", CharacterFrame)
    if tabsPanel then
      tabsPanel:ClearAllPoints()
      tabsPanel:SetPoint("TOPLEFT", tabsAnchor, "BOTTOMLEFT", 0, -4)
      tabsPanel:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -30, 8)
      SafeFrameLevel(tabsPanel, (tabsAnchor:GetFrameLevel() or 1) - 1)
      tabsPanel:SetBackdropColor(0.05, 0.02, 0.08, 0.92)
      tabsPanel:SetBackdropBorderColor(0.34, 0.17, 0.52, 0.95)
      tabsPanel:Show()
    end
  end
end

local function EnsureRightPanel(db)
  if rightPanel then return rightPanel end
  if not CharacterFrame then return nil end

  rightPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  rightPanel:SetSize(640, 620)
  rightPanel:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  rightPanel:SetBackdropColor(0, 0, 0, 0)
  rightPanel:SetBackdropBorderColor(0.34, 0.17, 0.52, 0.95)
  rightPanel:SetFrameStrata(CharacterFrame:GetFrameStrata() or "MEDIUM")
  rightPanel:SetClampedToScreen(true)
  rightPanel:SetMovable(false)

  rightPanel.bgGradient = rightPanel:CreateTexture(nil, "BACKGROUND")
  rightPanel.bgGradient:SetAllPoints()
  rightPanel.bgGradient:SetTexture("Interface/Buttons/WHITE8x8")
  -- M+ panel gradient: black at top -> purple at bottom.
  SetVerticalGradient(rightPanel.bgGradient, 0, 0, 0, 0.90, 0.08, 0.02, 0.12, 0.90)

  rightPanel.headerTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  rightPanel.headerTitle:SetPoint("TOPLEFT", 12, -8)
  rightPanel.headerTitle:SetText("Current Run")

  rightPanel.mplusTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  rightPanel.mplusTitle:SetPoint("TOP", rightPanel, "TOP", 0, -58)
  rightPanel.mplusTitle:SetText("Mythic+ Rating")

  rightPanel.mplusValue = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  rightPanel.mplusValue:SetPoint("TOP", rightPanel.mplusTitle, "BOTTOM", 0, -2)
  rightPanel.mplusValue:SetTextColor(1, 0.5, 0.1, 1)
  rightPanel.mplusValue:SetText("0")

  rightPanel.affixBar = CreateFrame("Frame", nil, rightPanel)
  rightPanel.affixBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -10, -8)
  rightPanel.affixBar:SetSize(220, 40)
  rightPanel.affixSlots = {}

  local affixBorderColors = {
    { 0.20, 0.80, 0.25, 1.0 }, -- 4
    { 0.95, 0.82, 0.22, 1.0 }, -- 7
    { 0.98, 0.56, 0.18, 1.0 }, -- 10
    { 0.92, 0.26, 0.22, 1.0 }, -- 12
  }
  local affixLevelLabels = { "4", "7", "10", "12" }

  for i = 1, 4 do
    local slot = CreateFrame("Frame", nil, rightPanel.affixBar, "BackdropTemplate")
    slot:SetSize(38, 38)
    slot:SetPoint("TOPRIGHT", rightPanel.affixBar, "TOPRIGHT", -((4 - i) * 54), 0)
    slot:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    slot:SetBackdropColor(0.02, 0.02, 0.03, 0.95)
    slot:SetBackdropBorderColor(affixBorderColors[i][1], affixBorderColors[i][2], affixBorderColors[i][3], affixBorderColors[i][4])

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    slot.level = rightPanel.affixBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slot.level:SetPoint("TOP", slot, "BOTTOM", 0, -1)
    slot.level:SetText(affixLevelLabels[i])
    slot.levelLabel = affixLevelLabels[i]

    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
      ShowAffixTooltip(self, self.affixID, self.levelLabel)
    end)
    slot:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)

    rightPanel.affixSlots[i] = slot
  end

  rightPanel.tableHeader = CreateFrame("Frame", nil, rightPanel)
  rightPanel.tableHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -106)
  rightPanel.tableHeader:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -8, -106)
  rightPanel.tableHeader:SetHeight(26)

  rightPanel.colDungeon = rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rightPanel.colDungeon:SetPoint("LEFT", 10, 0)
  rightPanel.colDungeon:SetWidth(340)
  rightPanel.colDungeon:SetJustifyH("CENTER")
  rightPanel.colDungeon:SetText("Dungeon")

  rightPanel.colLevel = rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rightPanel.colLevel:SetPoint("RIGHT", -196, 0)
  rightPanel.colLevel:SetWidth(64)
  rightPanel.colLevel:SetJustifyH("RIGHT")
  rightPanel.colLevel:SetText("Level")

  rightPanel.colRating = rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rightPanel.colRating:SetPoint("RIGHT", -126, 0)
  rightPanel.colRating:SetWidth(64)
  rightPanel.colRating:SetJustifyH("CENTER")
  rightPanel.colRating:SetText("Rating")

  rightPanel.colBest = rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rightPanel.colBest:SetPoint("RIGHT", -10, 0)
  rightPanel.colBest:SetWidth(112)
  rightPanel.colBest:SetJustifyH("CENTER")
  rightPanel.colBest:SetText("Best")

  rightPanel.rowContainer = CreateFrame("Frame", nil, rightPanel)
  rightPanel.rowContainer:SetPoint("TOPLEFT", rightPanel.tableHeader, "BOTTOMLEFT", 0, -2)
  rightPanel.rowContainer:SetPoint("TOPRIGHT", rightPanel.tableHeader, "BOTTOMRIGHT", 0, -2)
  rightPanel.rowContainer:SetHeight(282)
  rightPanel.rowContainer.rows = {}

  for i = 1, 8 do
    local row = CreateFrame("Frame", nil, rightPanel.rowContainer, "BackdropTemplate")
    row:SetHeight(32)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * 35))
    row:SetPoint("TOPRIGHT", 0, -((i - 1) * 35))
    row:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local a = ((i % 2) == 0) and 0.30 or 0.18
    row:SetBackdropColor(0.02, 0.03, 0.05, a)
    row:SetBackdropBorderColor(0.12, 0.16, 0.22, 0.5)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetTexture(134400)
    row.icon:EnableMouse(false)

    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetText(("Dungeon %d"):format(i))

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.level:SetPoint("RIGHT", -196, 0)
    row.level:SetWidth(64)
    row.level:SetJustifyH("RIGHT")
    row.level:SetText("-")

    row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.rating:SetPoint("RIGHT", -126, 0)
    row.rating:SetWidth(64)
    row.rating:SetJustifyH("CENTER")
    row.rating:SetText("-")

    row.best = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.best:SetPoint("RIGHT", -10, 0)
    row.best:SetWidth(112)
    row.best:SetJustifyH("CENTER")
    row.best:SetText("-")

    row.castBtn = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    row.castBtn:SetAllPoints(true)
    row.castBtn:SetFrameStrata(row:GetFrameStrata())
    row.castBtn:SetFrameLevel(row:GetFrameLevel() + 40)
    row.castBtn:EnableMouse(true)
    row.castBtn:RegisterForClicks("LeftButtonUp")
    row.castBtn:SetAttribute("useOnKeyDown", false)
    row.castBtn:SetAttribute("type", nil)
    row.castBtn:SetAttribute("type1", nil)
    row.castBtn:SetAttribute("spell", nil)
    row.castBtn:SetAttribute("spell1", nil)
    do
      local rowRef = row
      row.castBtn:SetScript("OnEnter", function(self)
        ShowDungeonPortalTooltip(self, rowRef.mapName, rowRef.mapID)
      end)
      row.castBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end

    row:EnableMouse(false)

    rightPanel.rowContainer.rows[i] = row
  end

  rightPanel.vaultTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  rightPanel.vaultTitle:SetPoint("BOTTOM", rightPanel, "BOTTOM", 0, 154)
  rightPanel.vaultTitle:SetText("Great Vault")

  rightPanel.vault = CreateFrame("Frame", nil, rightPanel)
  rightPanel.vault:SetSize(606, 126)
  rightPanel.vault:SetPoint("BOTTOM", rightPanel, "BOTTOM", 0, 20)
  rightPanel.vault.cards = {}

  for i = 1, 9 do
    local card = CreateFrame("Frame", nil, rightPanel.vault, "BackdropTemplate")
    card:SetSize(198, 38)
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    card:SetPoint("TOPLEFT", col * 204, -(row * 44))
    card:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    card:SetBackdropColor(0.08, 0.03, 0.14, 0.72)
    card:SetBackdropBorderColor(0.22, 0.16, 0.28, 0.85)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.title:SetPoint("TOPLEFT", 7, -6)
    card.title:SetJustifyH("LEFT")
    card.title:SetText("Vault")

    card.ilvl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.ilvl:SetPoint("TOPRIGHT", -7, -6)
    card.ilvl:SetJustifyH("RIGHT")
    card.ilvl:SetText("")

    card.difficulty = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.difficulty:SetPoint("BOTTOMLEFT", 7, 6)
    card.difficulty:SetJustifyH("LEFT")
    card.difficulty:SetText("")

    card.progress = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.progress:SetPoint("BOTTOMRIGHT", -7, 6)
    card.progress:SetJustifyH("RIGHT")
    card.progress:SetText("0 / 0")

    card.overlay = CreateFrame("Frame", nil, card)
    card.overlay:SetAllPoints(true)
    card.overlay:SetFrameLevel(card:GetFrameLevel() + 20)
    card.overlay:EnableMouse(false)

    card.dim = card.overlay:CreateTexture(nil, "BACKGROUND")
    card.dim:SetAllPoints(true)
    card.dim:SetColorTexture(0, 0, 0, 0.65)
    card.dim:Show()

    card.lock = card.overlay:CreateTexture(nil, "ARTWORK")
    card.lock:SetSize(24, 24)
    card.lock:SetPoint("CENTER", 0, 0)
    card.lock:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
    if not card.lock:GetTexture() then
      card.lock:SetTexture("Interface\\Common\\LockIcon")
    end
    card.lock:SetDesaturated(true)
    card.lock:SetVertexColor(0.95, 0.95, 0.95, 1)
    card.lock:Show()
    card.overlay:Show()

    rightPanel.vault.cards[i] = card
  end

  rightPanel.dragger = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
  rightPanel.dragger:SetAllPoints(true)
  rightPanel.dragger:SetFrameLevel(rightPanel:GetFrameLevel() + 100)
  rightPanel.dragger:EnableMouse(false)
  rightPanel.dragger:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  rightPanel.dragger:SetBackdropColor(0.02, 0.04, 0.08, 0.15)
  rightPanel.dragger:SetBackdropBorderColor(0.4, 0.6, 1.0, 0.5)
  rightPanel.dragger:Hide()

  rightPanel.dragger.label = rightPanel.dragger:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rightPanel.dragger.label:SetPoint("TOP", rightPanel.dragger, "TOP", 0, -6)
  rightPanel.dragger.label:SetText("Drag Mythic+ Panel")

  rightPanel.dragger:SetScript("OnDragStart", nil)
  rightPanel.dragger:SetScript("OnDragStop", nil)
  rightPanel.dragger:SetScript("OnMouseUp", function(_, button)
    if button ~= "RightButton" then return end
    local db = NS:GetDB()
    if not (db and db.charsheet) then return end
    db.charsheet.rightPanelDetached = false
    db.charsheet.rightPanelAnchor = "TOPLEFT"
    db.charsheet.rightPanelX = 0
    db.charsheet.rightPanelY = 0
  end)

  return rightPanel
end

local function GetRightPanelAnchorFrame()
  return CharacterFrame
end

local function PositionRightPanel(db)
  if not rightPanel or not db or not db.charsheet then return end
  if InCombatLockdown and InCombatLockdown() then return end
  rightPanel:ClearAllPoints()
  -- Fixed Mythic+ panel size: keep this stable.
  rightPanel:SetSize(640, 620)
  rightPanel:SetPoint(
    "TOPLEFT",
    CharacterFrame,
    "TOPRIGHT",
    db.charsheet.rightPanelOffsetX or INTEGRATED_RIGHT_GAP,
    db.charsheet.rightPanelOffsetY or 0
  )
end

local function ApplyRightPanelFont(db)
  if not rightPanel then return end
  local fontPath, size, outline = GetConfiguredFont(db)
  local function Apply(fs, s)
    if fs and fs.SetFont then
      BackupFont(fs)
      fs:SetFont(fontPath, s, outline)
    end
  end

  Apply(rightPanel.headerTitle, size + 1)
  Apply(rightPanel.mplusTitle, size + 2)
  Apply(rightPanel.mplusValue, size + 8)
  Apply(rightPanel.colDungeon, size)
  Apply(rightPanel.colLevel, size)
  Apply(rightPanel.colRating, size)
  Apply(rightPanel.colBest, size)
  Apply(rightPanel.vaultTitle, size + 2)
  if rightPanel.affixSlots then
    for _, slot in ipairs(rightPanel.affixSlots) do
      Apply(slot.level, size - 1)
    end
  end

  if rightPanel.rowContainer and rightPanel.rowContainer.rows then
    for _, row in ipairs(rightPanel.rowContainer.rows) do
      Apply(row.name, size + 1)
      Apply(row.level, size + 1)
      Apply(row.rating, size + 1)
      Apply(row.best, size + 1)
    end
  end
  if rightPanel.vault and rightPanel.vault.cards then
    for _, card in ipairs(rightPanel.vault.cards) do
      Apply(card.title, size)
      Apply(card.ilvl, size)
      Apply(card.difficulty, size - 1)
      Apply(card.progress, size - 1)
    end
  end
end

local function StarIconsText(stars)
  stars = tonumber(stars) or 0
  stars = math.max(0, math.min(3, math.floor(stars + 0.5)))
  if stars <= 0 then return "" end
  local star = "|cffffd100*|r"
  local out = ""
  for i = 1, stars do
    if i > 1 then out = out .. " " end
    out = out .. star
  end
  return out
end

local function GetDungeonMapIcon(mapID)
  if not mapID or mapID <= 0 then return 134400 end
  if not C_ChallengeMode or not C_ChallengeMode.GetMapUIInfo then
    return 134400
  end

  local ok, a, b, c, d, e = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
  if not ok then
    return 134400
  end

  -- Return shape differs between client versions; probe likely icon fields.
  if type(d) == "number" then return d end
  if type(e) == "number" then return e end
  if type(c) == "number" and c > 1000 then return c end
  if type(b) == "number" and b > 1000 then return b end
  if type(a) == "number" and a > 1000 then return a end
  return 134400
end

local function GetDungeonMapTimeLimitMS(mapID)
  if not mapID or mapID <= 0 then return nil end
  if not C_ChallengeMode or not C_ChallengeMode.GetMapUIInfo then return nil end

  local ok, a, b, c, d, e, f = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
  if not ok then return nil end

  local candidates = { a, b, c, d, e, f }
  for _, v in ipairs(candidates) do
    if type(v) == "number" then
      -- Most clients provide time limit in seconds; normalize to ms.
      if v >= 600 and v <= 7200 then
        return math.floor((v * 1000) + 0.5)
      end
      -- Some variants may provide ms directly.
      if v >= 600000 and v <= 7200000 then
        return math.floor(v + 0.5)
      end
    end
  end
  return nil
end

local function NormalizeName(s)
  if type(s) ~= "string" then return "" end
  s = string.lower(s)
  s = s:gsub("[%p]", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

local function IsSpellKnownCompat(spellID)
  if not spellID then return false end
  if IsSpellKnownOrOverridesKnown then
    return IsSpellKnownOrOverridesKnown(spellID)
  end
  if IsSpellKnown then
    return IsSpellKnown(spellID)
  end
  if IsPlayerSpell then
    return IsPlayerSpell(spellID)
  end
  return false
end

local function GetPortalAliases(mapName, mapID)
  local aliases = {}
  local seen = {}
  local function AddAlias(v)
    v = NormalizeName(v)
    if v ~= "" and not seen[v] then
      seen[v] = true
      aliases[#aliases + 1] = v
    end
  end
  if type(mapName) == "string" and mapName ~= "" then
    AddAlias(mapName)
  end
  if type(mapID) == "number" and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
    local uiName = C_ChallengeMode.GetMapUIInfo(mapID)
    if type(uiName) == "string" and uiName ~= "" then
      AddAlias(uiName)
    end
  end

  -- Common text mismatch: spell descriptions often omit a leading "The".
  for i = 1, #aliases do
    local a = aliases[i]
    if a:find("^the%s+") then
      AddAlias(a:gsub("^the%s+", ""))
    end
  end

  local key = aliases[1]
  local entry = key and PORTAL_ALIASES[key]
  if not entry then return aliases end

  local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
  faction = faction and string.lower(faction) or ""
  if entry.common then
    for _, v in ipairs(entry.common) do
      AddAlias(v)
    end
  end
  if faction ~= "" and entry[faction] then
    for _, v in ipairs(entry[faction]) do
      AddAlias(v)
    end
  end
  return aliases
end

local function PortalDestinationName(spellName)
  local dest = NormalizeName(spellName)
  if dest == "" then return "" end
  dest = dest:gsub("^teleport%s*:?%s*", "")
  dest = dest:gsub("^portal%s*:?%s*", "")
  dest = dest:gsub("^to%s+", "")
  dest = dest:gsub("%s+", " ")
  dest = dest:gsub("^%s+", "")
  dest = dest:gsub("%s+$", "")
  return dest
end

local function FindPortalSpellByMapName(mapName, mapID)
  if not mapName or mapName == "" then return nil end
  local cacheKey = ("%s|%s"):format(tostring(mapName), tostring(mapID or 0))
  if portalSpellCache[cacheKey] ~= nil then
    local cached = portalSpellCache[cacheKey]
    if type(cached) == "table" then
      return cached.spellID or nil, cached.actionID or nil
    end
    return cached or nil
  end

  local aliases = GetPortalAliases(mapName, mapID)
  local bestID
  local bestActionID
  local bestScore = 0
  local bestCastable = false
  local seen = {}
  local spellActionByID = {}
  local spellBookType = BOOKTYPE_SPELL or "spell"
  local spellBookBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or spellBookType

  local function ScoreCandidateSpell(spellID)
    if not spellID or seen[spellID] then return end
    seen[spellID] = true

    local rawName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or GetSpellInfo(spellID)
    local spellName = NormalizeName(rawName)
    local rawDesc = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)) or ""
    local spellDesc = NormalizeName(rawDesc)
    local tokenCastable = false
    if IsUsableSpell then
      local u1, m1 = IsUsableSpell(spellID)
      if u1 ~= nil or m1 ~= nil then
        tokenCastable = true
      elseif rawName and rawName ~= "" then
        local u2, m2 = IsUsableSpell(rawName)
        if u2 ~= nil or m2 ~= nil then
          tokenCastable = true
        end
      end
    end
    local looksLikeTravelSpell = (spellName ~= "" and (spellName:find("teleport") or spellName:find("portal") or spellName:find("path")))
      or (spellDesc ~= "" and (spellDesc:find("teleport") or spellDesc:find("portal") or spellDesc:find("entrance")))
    if not looksLikeTravelSpell then
      return
    end

    local dest = PortalDestinationName(spellName)
    for _, alias in ipairs(aliases) do
      if alias ~= "" then
        local score = 0
        if dest == alias then
          score = 1000 + #alias
        elseif #alias >= 5 and dest:find(alias, 1, true) then
          score = 500 + #alias
        elseif #dest >= 5 and alias:find(dest, 1, true) then
          score = 300 + #dest
        end
        if #alias >= 5 and spellDesc ~= "" and spellDesc:find(alias, 1, true) then
          score = math.max(score, 900 + #alias)
        end
        if score > bestScore or (score == bestScore and tokenCastable and not bestCastable) then
          bestScore = score
          bestID = spellID
          bestActionID = spellActionByID[spellID]
          bestCastable = tokenCastable
        end
      end
    end
  end

  local function IsItemType(itemType, want)
    if itemType == want then return true end
    if type(itemType) == "number" and Enum and Enum.SpellBookItemType then
      if want == "SPELL" and itemType == Enum.SpellBookItemType.Spell then return true end
      if want == "FLYOUT" and itemType == Enum.SpellBookItemType.Flyout then return true end
    end
    return false
  end

  local function UnpackSpellBookItemInfo(a, b)
    if type(a) == "table" then
      local itemType = a.itemType or a.spellType
      local id
      if IsItemType(itemType, "SPELL") then
        id = a.spellID or a.actionID
      elseif IsItemType(itemType, "FLYOUT") then
        id = a.flyoutID or a.actionID
      else
        id = a.spellID or a.flyoutID or a.actionID
      end
      return itemType, id
    end
    return a, b
  end

  local function GetSkillLineRange(tab)
    if type(tab) == "table" then
      local offset = tab.itemIndexOffset or tab.offset or tab.offSet
      local count = tab.numSpellBookItems or tab.numSlots or tab.numSpells
      if type(offset) == "number" and type(count) == "number" then
        return offset, count
      end
    end
    return nil, nil
  end

  local function GetFlyoutSlots(flyoutID)
    if not flyoutID then return 0 end
    if C_SpellBook and C_SpellBook.GetFlyoutInfo then
      local info = C_SpellBook.GetFlyoutInfo(flyoutID)
      if type(info) == "table" then
        return tonumber(info.numSlots) or tonumber(info.numKnownSlots) or 0
      end
      local _, _, numSlots = C_SpellBook.GetFlyoutInfo(flyoutID)
      return tonumber(numSlots) or 0
    end
    if GetFlyoutInfo then
      local _, _, numSlots = GetFlyoutInfo(flyoutID)
      return tonumber(numSlots) or 0
    end
    return 0
  end

  local function GetFlyoutSpellAt(flyoutID, slotIndex)
    if C_SpellBook and C_SpellBook.GetFlyoutSlotInfo then
      local a, b, c = C_SpellBook.GetFlyoutSlotInfo(flyoutID, slotIndex)
      if type(a) == "table" then
        local flySpellID = a.spellID
        local overrideSpellID = a.overrideSpellID
        local isKnown = a.isKnown
        return flySpellID, overrideSpellID, isKnown
      end
      local flySpellID, overrideSpellID, isKnown = a, b, c
      return flySpellID, overrideSpellID, isKnown
    end
    if GetFlyoutSlotInfo then
      local flySpellID, overrideSpellID, isKnown = GetFlyoutSlotInfo(flyoutID, slotIndex)
      return flySpellID, overrideSpellID, isKnown
    end
    return nil, nil, nil
  end

  local GetItemInfo = GetSpellBookItemInfo or (C_SpellBook and C_SpellBook.GetSpellBookItemInfo)

  local function ScanRange(offset, numSlots)
    offset = tonumber(offset) or 0
    numSlots = tonumber(numSlots) or 0
    for i = offset + 1, offset + numSlots do
      local rawA, rawB = GetItemInfo(i, spellBookBank)
      if rawA == nil and spellBookBank ~= spellBookType then
        rawA, rawB = GetItemInfo(i, spellBookType)
      end
      local spellType, spellID = UnpackSpellBookItemInfo(rawA, rawB)
      if IsItemType(spellType, "SPELL") and spellID then
        if type(rawA) == "table" and type(rawA.actionID) == "number" then
          spellActionByID[spellID] = rawA.actionID
        elseif type(i) == "number" then
          spellActionByID[spellID] = i
        end
        ScoreCandidateSpell(spellID)
      elseif IsItemType(spellType, "FLYOUT") and spellID then
        local numFlyoutSlots = GetFlyoutSlots(spellID)
        for s = 1, numFlyoutSlots do
          local flySpellID, overrideSpellID, isKnown = GetFlyoutSpellAt(spellID, s)
          if isKnown == nil or isKnown then
            if flySpellID then
              ScoreCandidateSpell(flySpellID)
            end
            if overrideSpellID and overrideSpellID ~= flySpellID then
              ScoreCandidateSpell(overrideSpellID)
            end
          end
        end
      end
    end
  end

  if GetItemInfo and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    for line = 1, numLines do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      local offset, numSlots = GetSkillLineRange(info)
      if offset == nil or numSlots == nil then
        local _, _, tupleOffset, tupleCount = C_SpellBook.GetSpellBookSkillLineInfo(line)
        offset = tupleOffset
        numSlots = tupleCount
      end
      ScanRange(offset, numSlots)
    end
  elseif GetItemInfo and GetNumSpellTabs and GetSpellTabInfo then
    for tab = 1, (GetNumSpellTabs() or 0) do
      local _, _, offset, numSlots = GetSpellTabInfo(tab)
      ScanRange(offset, numSlots)
    end
  end

  if bestID then
    portalSpellCache[cacheKey] = { spellID = bestID, actionID = bestActionID }
    return bestID, bestActionID
  end
  portalSpellCache[cacheKey] = false
  return nil, nil
end

local function UpdateRowSecureCast(row)
  if not row or not row.castBtn then return end

  local mapName = row.mapName
  local mapID = row.mapID
  local spellID, actionID
  if mapName and mapName ~= "" then
    spellID, actionID = FindPortalSpellByMapName(mapName, mapID)
  end
  local unlocked = spellID and IsSpellKnownCompat(spellID)
  local spellName = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or GetSpellInfo(spellID)) or nil

  row.portalSpellID = spellID
  row.portalActionID = actionID
  row.portalSpellName = spellName
  row.portalUnlocked = unlocked and true or false

  if InCombatLockdown and InCombatLockdown() then
    pendingSecureUpdate = true
    return
  end

  if unlocked and spellID then
    row.castBtn:SetAttribute("type", "spell")
    row.castBtn:SetAttribute("type1", "spell")
    row.castBtn:SetAttribute("spell", spellID)
    row.castBtn:SetAttribute("spell1", spellID)
    row.castBtn:SetAttribute("action", nil)
    row.castBtn:SetAttribute("action1", nil)
    row.castBtn:SetAttribute("macrotext", nil)
    row.castBtn:SetAttribute("macrotext1", nil)
  elseif unlocked and actionID then
    row.castBtn:SetAttribute("type", "action")
    row.castBtn:SetAttribute("type1", "action")
    row.castBtn:SetAttribute("action", actionID)
    row.castBtn:SetAttribute("action1", actionID)
    row.castBtn:SetAttribute("spell", nil)
    row.castBtn:SetAttribute("spell1", nil)
    row.castBtn:SetAttribute("macrotext", nil)
    row.castBtn:SetAttribute("macrotext1", nil)
  elseif unlocked and spellName and spellName ~= "" then
    local macro = "/dismount [mounted]\n/cast " .. spellName .. "\n/cast " .. tostring(spellID)
    row.castBtn:SetAttribute("type", "macro")
    row.castBtn:SetAttribute("type1", "macro")
    row.castBtn:SetAttribute("macrotext", macro)
    row.castBtn:SetAttribute("macrotext1", macro)
    row.castBtn:SetAttribute("action", nil)
    row.castBtn:SetAttribute("action1", nil)
    row.castBtn:SetAttribute("spell", nil)
    row.castBtn:SetAttribute("spell1", nil)
  else
    row.castBtn:SetAttribute("type", nil)
    row.castBtn:SetAttribute("type1", nil)
    row.castBtn:SetAttribute("action", nil)
    row.castBtn:SetAttribute("action1", nil)
    row.castBtn:SetAttribute("spell", nil)
    row.castBtn:SetAttribute("spell1", nil)
    row.castBtn:SetAttribute("macrotext", nil)
    row.castBtn:SetAttribute("macrotext1", nil)
  end
end

ShowAffixTooltip = function(owner, affixID, levelLabel)
  if not owner or not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if affixID and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
    local name, desc, icon = C_ChallengeMode.GetAffixInfo(affixID)
    if icon and name then
      GameTooltip:AddLine(("|T%d:16:16:0:0|t %s"):format(icon, name), 1, 1, 1)
    else
      GameTooltip:AddLine(name or "Affix", 1, 1, 1)
    end
    if levelLabel then
      GameTooltip:AddLine(("Activates at +%s"):format(levelLabel), 0.4, 0.9, 0.4)
    end
    if desc and desc ~= "" then
      GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true)
    end
  else
    GameTooltip:AddLine("Affix", 1, 1, 1)
    if levelLabel then
      GameTooltip:AddLine(("Activates at +%s"):format(levelLabel), 0.4, 0.9, 0.4)
    end
  end
  GameTooltip:Show()
end

ShowDungeonPortalTooltip = function(owner, mapName, mapID)
  if not owner or not GameTooltip then return end
  local spellID = FindPortalSpellByMapName(mapName, mapID)
  local spellName = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or GetSpellInfo(spellID)) or nil
  local unlocked = spellID and IsSpellKnownCompat(spellID)

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(mapName or "Dungeon", 1, 1, 1)
  if mapID then
    GameTooltip:AddLine(("Map ID: %d"):format(mapID), 0.7, 0.7, 0.7)
  end
  if spellID and unlocked then
    GameTooltip:AddLine(("Portal Ready: %s"):format(spellName or ("Spell " .. spellID)), 0.35, 1.0, 0.45)
    GameTooltip:AddLine("Left-click to cast", 0.9, 0.9, 0.9)
  elseif spellID then
    GameTooltip:AddLine(("Portal Found: %s"):format(spellName or ("Spell " .. spellID)), 1.0, 0.82, 0.3)
    GameTooltip:AddLine("Not learned on this character", 1.0, 0.45, 0.45)
  else
    GameTooltip:AddLine("Portal not found in spellbook", 1.0, 0.45, 0.45)
  end
  GameTooltip:Show()
end

local function FormatMS(ms)
  if not ms or ms <= 0 then return "-" end
  local total = math.floor((ms / 1000) + 0.5)
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  if h > 0 then
    return ("%d:%02d:%02d"):format(h, m, s)
  end
  return ("%02d:%02d"):format(m, s)
end

local function NormalizeDurationMS(value, keyName)
  if type(value) ~= "number" then return nil end
  local key = type(keyName) == "string" and string.lower(keyName) or ""
  if key:find("sec") and value < 100000 then
    return math.floor((value * 1000) + 0.5)
  end
  if value > 0 and value < 100000 then
    -- Treat likely seconds as milliseconds for best-time fields.
    return math.floor((value * 1000) + 0.5)
  end
  return math.floor(value + 0.5)
end

local function CoerceRunFromTable(tbl, mapID)
  if type(tbl) ~= "table" then return nil end

  local level = tbl.level or tbl.bestLevel or tbl.keystoneLevel or tbl.challengeLevel or tbl.bestRunLevel
  local score = tbl.score or tbl.rating or tbl.overallScore or tbl.currentSeasonScore or tbl.mapScore
  local duration = tbl.bestRunDurationMS or tbl.durationMS or tbl.runDurationMS or tbl.bestDurationMS
  local over = tbl.overTimeMS or tbl.overtimeMS or tbl.overTime or tbl.timeOverMS
  local stars = tbl.numKeystoneUpgrades or tbl.keystoneUpgradeLevels or tbl.numUpgrades or tbl.upgrades or tbl.keystoneUpgrades

  if not duration and type(tbl.bestRunDurationSec) == "number" then
    duration = tbl.bestRunDurationSec * 1000
  end
  if not duration and type(tbl.durationSec) == "number" then
    duration = tbl.durationSec * 1000
  end
  if not over and type(tbl.overTimeSec) == "number" then
    over = tbl.overTimeSec * 1000
  end

  if type(level) ~= "number" and type(tbl.keystone and tbl.keystone.level) == "number" then
    level = tbl.keystone.level
  end
  if type(score) ~= "number" and type(tbl.ratingInfo) == "table" then
    score = tbl.ratingInfo.score or tbl.ratingInfo.rating
  end
  if type(stars) ~= "number" and type(tbl.completedKeystoneLevel) == "number" and type(level) == "number" then
    stars = math.max(0, math.min(3, level - tbl.completedKeystoneLevel))
  end
  if type(stars) == "table" then
    stars = stars.numKeystoneUpgrades or stars.numUpgrades or stars.count or stars.level or stars.keystoneUpgrades
  end

  if type(level) ~= "number" and type(score) ~= "number" and type(duration) ~= "number" then
    return nil
  end

  local run = {
    mapChallengeModeID = mapID or tbl.mapChallengeModeID or tbl.mapID,
    level = (type(level) == "number") and math.floor(level + 0.5) or 0,
    score = (type(score) == "number") and score or 0,
    bestRunDurationMS = NormalizeDurationMS(duration, "duration"),
    overTimeMS = (type(over) == "number") and over or nil,
    stars = (type(stars) == "number") and math.max(0, math.min(3, math.floor(stars + 0.5))) or 0,
  }
  return run
end

local function ExtractRunsDeep(value, mapID, out, depth)
  if depth <= 0 then return end
  if type(value) ~= "table" then return end

  local run = CoerceRunFromTable(value, mapID)
  if run then
    out[#out + 1] = run
  end

  for k, v in pairs(value) do
    if type(v) == "table" then
      local childMapID = mapID
      if type(v.mapChallengeModeID) == "number" then
        childMapID = v.mapChallengeModeID
      elseif type(v.mapID) == "number" then
        childMapID = v.mapID
      elseif type(value.mapChallengeModeID) == "number" then
        childMapID = value.mapChallengeModeID
      elseif type(value.mapID) == "number" then
        childMapID = value.mapID
      end
      ExtractRunsDeep(v, childMapID, out, depth - 1)
    elseif type(v) == "number" then
      -- Secondary heuristic pass for tables that split values across keyed fields.
      local key = type(k) == "string" and string.lower(k) or ""
      if key:find("level") or key:find("score") or key:find("rating") or key:find("duration") then
        local synthetic = out[#out] or { mapChallengeModeID = mapID, level = 0, score = 0 }
        if key:find("level") and synthetic.level == 0 then
          synthetic.level = math.floor(v + 0.5)
        elseif (key:find("score") or key:find("rating")) and synthetic.score == 0 then
          synthetic.score = v
        elseif key:find("duration") and not synthetic.bestRunDurationMS then
          synthetic.bestRunDurationMS = NormalizeDurationMS(v, key)
        end
        out[#out] = synthetic
      end
    end
  end
end

local function MergeBestRunsByMap(runs)
  local byMap = {}
  for _, run in ipairs(runs or {}) do
    if type(run) == "table" then
      local mapID = run.mapChallengeModeID or run.mapID
      local key = mapID or ("idx_" .. tostring(_))
      local cur = byMap[key]
      if not cur then
        byMap[key] = run
      else
        local curScore = cur.score or 0
        local runScore = run.score or 0
        local curLevel = cur.level or 0
        local runLevel = run.level or 0
        if (runScore > curScore) or (runScore == curScore and runLevel > curLevel) then
          byMap[key] = run
        end
      end
    end
  end
  local merged = {}
  for _, run in pairs(byMap) do
    merged[#merged + 1] = run
  end
  return merged
end

local function ShallowCopyArray(src)
  if type(src) ~= "table" then return nil end
  local out = {}
  for i = 1, #src do
    out[i] = src[i]
  end
  return out
end

local function CopyRuns(runs)
  if type(runs) ~= "table" then return nil end
  local out = {}
  for i = 1, #runs do
    local r = runs[i]
    if type(r) == "table" then
      local c = {}
      for k, v in pairs(r) do
        c[k] = v
      end
      out[#out + 1] = c
    end
  end
  return out
end

local function GetRunDeltaMS(run)
  if not run then return nil end
  if type(run.overTimeMS) == "number" then
    return run.overTimeMS
  end
  if type(run.overTime) == "number" then
    if math.abs(run.overTime) > 10000 then
      return run.overTime
    end
    return run.overTime * 1000
  end
  if type(run.bestRunDurationMS) == "number" and type(run.parTimeMS) == "number" then
    return run.bestRunDurationMS - run.parTimeMS
  end
  return nil
end

local function RefreshRightPanelData()
  if not rightPanel then return end

  if C_MythicPlus and C_MythicPlus.RequestMapInfo then
    pcall(C_MythicPlus.RequestMapInfo)
  end

  local currentRunText = "No active key"
  if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or nil
    if mapID and mapID > 0 then
      local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
      currentRunText = ("%s (%s)"):format(name or ("Map " .. mapID), level and ("+" .. level) or "?")
    end
  end
  if rightPanel.headerTitle then
    rightPanel.headerTitle:SetText(currentRunText)
  end

  local affixIDs = {}
  if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
    local affixes = C_MythicPlus.GetCurrentAffixes()
    if type(affixes) == "table" then
      for _, entry in ipairs(affixes) do
        local affixID = type(entry) == "table" and (entry.id or entry.affixID or entry.keystoneAffixID) or entry
        if type(affixID) == "number" then
          affixIDs[#affixIDs + 1] = affixID
        end
      end
    end
  end
  if rightPanel.affixSlots then
    if #affixIDs == 0 and type(lastMPlusSnapshot.affixIDs) == "table" and #lastMPlusSnapshot.affixIDs > 0 then
      affixIDs = ShallowCopyArray(lastMPlusSnapshot.affixIDs) or affixIDs
    elseif #affixIDs > 0 then
      lastMPlusSnapshot.affixIDs = ShallowCopyArray(affixIDs)
    end

    for i, slot in ipairs(rightPanel.affixSlots) do
      local affixID = affixIDs[i]
      slot.affixID = affixID
      if affixID and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
        local _, _, icon = C_ChallengeMode.GetAffixInfo(affixID)
        slot.icon:SetTexture(icon or 134400)
      else
        slot.icon:SetTexture(134400)
      end
      slot:Show()
      slot.level:Show()
    end
  end

  local rating = 0
  if C_MythicPlus and C_MythicPlus.GetSeasonBestMythicRatingInfo then
    local info = C_MythicPlus.GetSeasonBestMythicRatingInfo()
    if type(info) == "table" then
      rating = info.currentSeasonScore or info.rating or 0
    elseif type(info) == "number" then
      rating = info
    end
  end
  if (not rating or rating <= 0) and C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local info = C_ChallengeMode.GetOverallDungeonScore()
    if type(info) == "table" then
      rating = info.currentSeasonScore or info.overallScore or info.dungeonScore or rating
    elseif type(info) == "number" then
      rating = info
    end
  end
  if rightPanel.mplusValue then
    rightPanel.mplusValue:SetText(("%d"):format(math.floor((rating or 0) + 0.5)))
  end

  local runs = {}
  if C_MythicPlus and C_MythicPlus.GetRunHistory then
    local calls = {
      function() return C_MythicPlus.GetRunHistory(false, true) end,
      function() return C_MythicPlus.GetRunHistory(true, true) end,
      function() return C_MythicPlus.GetRunHistory(false, false) end,
      function() return C_MythicPlus.GetRunHistory() end,
    }
    for _, fn in ipairs(calls) do
      local ok, history = pcall(fn)
      if ok and type(history) == "table" and #history > 0 then
        runs = history
        break
      end
    end
  end

  -- Fallback for clients where run history API is empty but map score APIs exist.
  if #runs == 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable then
    local mapTable = C_ChallengeMode.GetMapTable()
    if type(mapTable) == "table" then
      for _, mapID in ipairs(mapTable) do
        local row = { mapChallengeModeID = mapID }
        if C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
          local ok, info = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
          if ok and type(info) == "table" then
            local extracted = {}
            ExtractRunsDeep(info, mapID, extracted, 6)
            extracted = MergeBestRunsByMap(extracted)
            if #extracted > 0 then
              local best = extracted[1]
              row.score = best.score or 0
              row.level = best.level or 0
              row.bestRunDurationMS = best.bestRunDurationMS
              row.overTimeMS = best.overTimeMS
            else
              row.score = info.score or info.overallScore or info.dungeonScore or 0
              row.level = info.level or info.bestLevel or info.keystoneLevel or 0
              row.bestRunDurationMS = info.bestRunDurationMS or info.durationMS
              row.overTimeMS = info.overTimeMS or info.overTime
            end
          end
        end
        if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
          local ok, a, b, c, d, e = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
          if ok then
            if type(a) == "table" then
              local extracted = {}
              ExtractRunsDeep(a, mapID, extracted, 6)
              extracted = MergeBestRunsByMap(extracted)
              if #extracted > 0 then
                local best = extracted[1]
                row.score = row.score or best.score
                row.level = row.level or best.level
                row.bestRunDurationMS = row.bestRunDurationMS or best.bestRunDurationMS
                row.overTimeMS = row.overTimeMS or best.overTimeMS
              end
            else
              local tuple = { score = a, level = b, bestRunDurationMS = c, overTimeMS = d, mapChallengeModeID = mapID }
              local parsed = CoerceRunFromTable(tuple, mapID)
              if parsed then
                row.score = row.score or parsed.score
                row.level = row.level or parsed.level
                row.bestRunDurationMS = row.bestRunDurationMS or parsed.bestRunDurationMS
                row.overTimeMS = row.overTimeMS or parsed.overTimeMS
              end
            end
          end
        end
        if (row.score and row.score > 0) or (row.level and row.level > 0) then
          runs[#runs + 1] = row
        end
      end
    end
  end

  if #runs > 0 then
    local extracted = {}
    for _, r in ipairs(runs) do
      if type(r) == "table" then
        ExtractRunsDeep(r, r.mapChallengeModeID or r.mapID, extracted, 4)
      end
    end
    if #extracted > 0 then
      runs = MergeBestRunsByMap(extracted)
    else
      runs = MergeBestRunsByMap(runs)
    end
  end

  if #runs == 0 and type(lastMPlusSnapshot.runs) == "table" and #lastMPlusSnapshot.runs > 0 then
    runs = CopyRuns(lastMPlusSnapshot.runs) or runs
  elseif #runs > 0 then
    lastMPlusSnapshot.runs = CopyRuns(runs)
  end

  if rightPanel.rowContainer and rightPanel.rowContainer.rows then
    table.sort(runs, function(a, b)
      local al = a and (a.level or a.bestLevel or a.keystoneLevel or 0) or 0
      local bl = b and (b.level or b.bestLevel or b.keystoneLevel or 0) or 0
      if al ~= bl then return al > bl end
      local as = a and (a.score or a.rating or 0) or 0
      local bs = b and (b.score or b.rating or 0) or 0
      return as > bs
    end)

    for i, row in ipairs(rightPanel.rowContainer.rows) do
      local run = runs[i]
      if run then
        local mapID = run.mapChallengeModeID or run.mapID
        local name = (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and mapID) and C_ChallengeMode.GetMapUIInfo(mapID) or ("Dungeon " .. i)
        local mapIcon = GetDungeonMapIcon(mapID)
        local level = run.level or run.bestLevel or run.keystoneLevel or 0
        local score = run.score or run.rating or 0
        local stars = run.stars or run.numKeystoneUpgrades or 0
        local bestMS = run.bestRunDurationMS or run.durationMS
        local parMS = run.parTimeMS or GetDungeonMapTimeLimitMS(mapID)
        local best = FormatMS(bestMS)
        local deltaMS = GetRunDeltaMS(run)
        if not deltaMS and type(bestMS) == "number" and type(parMS) == "number" and parMS > 0 then
          deltaMS = bestMS - parMS
        end

        if (not stars or stars <= 0) and type(bestMS) == "number" and type(parMS) == "number" and parMS > 0 then
          if bestMS > parMS then
            stars = 0
          else
            local remainingPct = (parMS - bestMS) / parMS
            if remainingPct >= 0.40 then
              stars = 3
            elseif remainingPct >= 0.20 then
              stars = 2
            else
              stars = 1
            end
          end
        end

        if deltaMS and best ~= "-" then
          local absText = FormatMS(math.abs(deltaMS))
          if deltaMS <= 0 then
            row.best:SetText(best .. " |cff33ff99(-" .. absText .. ")|r")
            row.best:SetTextColor(0.95, 0.95, 0.95, 1)
          else
            row.best:SetText(best .. " |cffff6666(+" .. absText .. ")|r")
            row.best:SetTextColor(0.95, 0.95, 0.95, 1)
          end
        else
          row.best:SetText(best)
          row.best:SetTextColor(0.95, 0.95, 0.95, 1)
        end
        row.name:SetText(name or ("Dungeon " .. i))
        row.mapID = mapID
        row.mapName = name
        UpdateRowSecureCast(row)
        if row.icon then
          row.icon:SetTexture(mapIcon or 134400)
        end
        if level > 0 then
          local starsText = StarIconsText(stars)
          if starsText ~= "" then
            row.level:SetText(("%s +%d"):format(starsText, level))
          else
            row.level:SetText((" +%d"):format(level))
          end
        else
          row.level:SetText("-")
        end
        row.rating:SetText(score > 0 and tostring(math.floor(score + 0.5)) or "-")
        row.rating:SetTextColor(score > 0 and 1 or 0.85, score > 0 and 0.55 or 0.85, score > 0 and 0.2 or 0.85, 1)
      else
        row.name:SetText(("Dungeon %d"):format(i))
        row.mapID = nil
        row.mapName = nil
        UpdateRowSecureCast(row)
        if row.icon then
          row.icon:SetTexture(134400)
        end
        row.level:SetText("-")
        row.rating:SetText("-")
        row.best:SetText("-")
        row.best:SetTextColor(0.9, 0.9, 0.9, 1)
        row.rating:SetTextColor(0.9, 0.9, 0.9, 1)
      end
    end
    if not (InCombatLockdown and InCombatLockdown()) then
      pendingSecureUpdate = false
    end
  end

  local acts = {}
  if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
    local t = C_WeeklyRewards.GetActivities()
    if type(t) == "table" then
      acts = t
    end
  end

  local function ToNumber(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
      local n = tonumber(v)
      if n then return n end
    end
    return nil
  end

  local function GetActivityProgress(act)
    if type(act) ~= "table" then return 0 end
    return ToNumber(act.progress) or ToNumber(act.completedActivities) or ToNumber(act.currentProgress) or 0
  end

  local function GetActivityItemLevel(act)
    if type(act) ~= "table" then return nil end
    local direct = ToNumber(act.itemLevel) or ToNumber(act.rewardItemLevel) or ToNumber(act.rewardLevel) or ToNumber(act.ilvl)
    if direct and direct > 100 then
      return math.floor(direct + 0.5)
    end
    if C_WeeklyRewards and C_WeeklyRewards.GetActivityEncounterInfo and act.id then
      local ok, info = pcall(C_WeeklyRewards.GetActivityEncounterInfo, act.id)
      if ok and type(info) == "table" then
        local n = ToNumber(info.itemLevel) or ToNumber(info.rewardItemLevel) or ToNumber(info.ilvl)
        if n and n > 100 then
          return math.floor(n + 0.5)
        end
      end
    end
    return nil
  end

  local function GetRaidDifficultyLabel(act)
    if type(act) ~= "table" then return "Raid" end
    local diff = ToNumber(act.difficultyID) or ToNumber(act.difficulty) or ToNumber(act.level)
    local map = {
      [17] = "LFR",
      [14] = "Normal",
      [15] = "Heroic",
      [16] = "Mythic",
    }
    if diff and map[diff] then
      return map[diff]
    end
    return nil
  end

  local function GetHardestDifficultyLabel(trackType, act)
    if type(act) ~= "table" then return "" end

    if trackType == 1 then
      local raidDiff = GetRaidDifficultyLabel(act)
      if raidDiff and raidDiff ~= "" then
        return raidDiff
      end
      return ""
    end

    if trackType == 2 then
      local lvl = ToNumber(act.level) or ToNumber(act.keystoneLevel) or ToNumber(act.bestLevel) or ToNumber(act.bestRunLevel) or ToNumber(act.challengeLevel)
      if lvl and lvl > 0 then
        return ("+%d"):format(math.floor(lvl + 0.5))
      end
      return ""
    end

    if trackType == 3 then
      local tier = ToNumber(act.level) or ToNumber(act.tier) or ToNumber(act.tierID) or ToNumber(act.difficulty) or ToNumber(act.difficultyID)
      if tier and tier > 0 then
        return ("Tier %d"):format(math.floor(tier + 0.5))
      end
      return ""
    end

    return ""
  end

  if rightPanel.vault and rightPanel.vault.cards then
    local byType = {
      [1] = {},
      [2] = {},
      [3] = {},
    }
    for _, act in ipairs(acts) do
      local t = act and act.type
      if byType[t] then
        byType[t][#byType[t] + 1] = act
      end
    end

    local trackTypeByRow = { 2, 1, 3 } -- Mythic+, Raid, World/Delves
    local trackNameByType = {
      [1] = "Raid",
      [2] = "Mythic+",
      [3] = "World",
    }
    local thresholdsByType = {
      [2] = { 2, 4, 8 }, -- Mythic+
      [1] = { 1, 4, 6 }, -- Raid
      [3] = { 2, 4, 8 }, -- World
    }
    local trackColor = {
      [1] = { 0.05, 0.08, 0.16, 0.74, 0.20, 0.30, 0.55, 0.88 },
      [2] = { 0.12, 0.04, 0.18, 0.74, 0.38, 0.22, 0.56, 0.90 },
      [3] = { 0.06, 0.11, 0.08, 0.74, 0.20, 0.40, 0.26, 0.88 },
    }

    for i, card in ipairs(rightPanel.vault.cards) do
      local col = ((i - 1) % 3) + 1
      local row = math.floor((i - 1) / 3) + 1
      local trackType = trackTypeByRow[row] or 2
      local actList = byType[trackType] or {}
      local act = actList[col]

      local c = trackColor[trackType] or trackColor[2]
      card:SetBackdropColor(c[1], c[2], c[3], c[4])
      card:SetBackdropBorderColor(c[5], c[6], c[7], c[8])

      local label = trackNameByType[trackType] or "Vault"
      local target = (thresholdsByType[trackType] and thresholdsByType[trackType][col]) or 0
      local progress = GetActivityProgress(act)
      local complete = (target > 0 and progress >= target)

      card.title:SetText(label)
      card.progress:SetText(("%d / %d"):format(progress, target))

      local ilvl = GetActivityItemLevel(act)
      card.ilvl:SetText(ilvl and tostring(ilvl) or "")

      card.difficulty:SetText(GetHardestDifficultyLabel(trackType, act))

      if complete then
        card.title:SetTextColor(0.35, 1, 0.5, 1)
        card.ilvl:SetTextColor(0.35, 1, 0.5, 1)
        card.difficulty:SetTextColor(0.35, 1, 0.5, 1)
        card.progress:SetTextColor(0.35, 1, 0.5, 1)
        if card.overlay then card.overlay:Hide() end
      else
        card.title:SetTextColor(0.95, 0.95, 0.95, 1)
        card.ilvl:SetTextColor(0.95, 0.95, 0.95, 1)
        card.difficulty:SetTextColor(0.95, 0.95, 0.95, 1)
        card.progress:SetTextColor(0.95, 0.95, 0.95, 1)
        if card.overlay then card.overlay:Show() end
      end
    end
  end
end

local function HideArtwork(db)
  if not db or not db.charsheet or not db.charsheet.hideArt then
    return
  end

  local targets = {
    _G.CharacterFrameBg,
    _G.CharacterFrameTitleBg,
    _G.CharacterFrameTopTileStreaks,
    _G.CharacterFrameTopBorder,
    _G.CharacterFrameBotLeft,
    _G.CharacterFrameBotRight,
    _G.CharacterFrame and _G.CharacterFrame.Bg,
    _G.CharacterFrame and _G.CharacterFrame.Background,
    _G.CharacterFrame and _G.CharacterFrame.NineSlice,
    _G.CharacterFrameInset and _G.CharacterFrameInset.Bg,
    _G.CharacterFrameInset and _G.CharacterFrameInset.NineSlice,
    _G.PaperDollFrame and _G.PaperDollFrame.NineSlice,
    _G.PaperDollFrame and _G.PaperDollFrame.Bg,
    _G.CharacterFrameInsetRight,
    _G.CharacterStatsPane and _G.CharacterStatsPane.Background,
    _G.CharacterStatsPane and _G.CharacterStatsPane.Bg,
    _G.CharacterStatsPane and _G.CharacterStatsPane.NineSlice,
    _G.CharacterModelScene and _G.CharacterModelScene.Background,
    _G.CharacterModelScene and _G.CharacterModelScene.BG,
  }

  for _, region in ipairs(targets) do
    SaveAndHideRegion(region)
  end

  -- Catch remaining Blizzard frame textures that aren't exposed via stable globals.
  HideFrameTextureRegions(_G.CharacterFrame)
  HideFrameTextureRegions(_G.CharacterFrameInset)
  HideFrameTextureRegions(_G.PaperDollFrame)
  HideFrameTextureRegions(_G.CharacterStatsPane)

  -- Private-addon aggressive pass: strip all direct texture regions on core panes.
  AggressiveStripFrame(_G.CharacterFrame)
  AggressiveStripFrame(_G.CharacterFrameInset)
  AggressiveStripFrame(_G.PaperDollFrame)
  AggressiveStripFrame(_G.CharacterStatsPane)
  AggressiveStripFrameRecursive(_G.CharacterStatsPane, 4)
end

function M:Refresh()
  if not M.active then return end
  local db = NS:GetDB()
  if not db then return end
  if not CharacterFrame then return end

  if db.charsheet.styleStats then
    ApplyCustomCharacterLayout()
  else
    if layoutApplied then
      RestoreCapturedLayouts()
      layoutApplied = false
    end
    if customCharacterFrame then
      customCharacterFrame:Hide()
    end
    EnsureBlizzardCharacterAnchors()
  end

  local frame = EnsureSkinFrame()
  if frame then
    if db.charsheet.styleStats then
      frame:Hide()
    else
      frame:Show()
    end
  end
  if db.charsheet.hideArt then
    HideArtwork(db)
  else
    RestoreHiddenRegions()
  end

  if db.charsheet.styleStats then
    ApplyCoreCharacterFontAndName(db)
    if SIMPLE_BASE_PANEL_MODE then
      -- 1.0 baseline: one character base panel only, no extra stat/section sub-panels.
      StylePaperDollSlots()
      ApplyChonkySlotLayout()
      ApplyChonkyModelLayout()
      ApplyMinimalChonkyBase()
      HideTabArt()
      HideCharacterTabsButtons()
      if skinFrame then
        skinFrame:Hide()
      end
      for _, panel in pairs(panelSkins) do
        if panel and panel.Hide then
          panel:Hide()
        end
      end
      -- Re-enable custom stat panels on the right side of the character panel.
      UpdateCustomStatsFrame(db)
      if customGearFrame then
        customGearFrame:Hide()
      end
    else
      StyleCorePanels()
      StyleStatRows(db)
      StyleStatsHeaders(db)
      StylePaperDollSlots()
      ApplyChonkySlotLayout()
      ApplyChonkyModelLayout()
      HideTabArt()
      HideCharacterTabsButtons()
      HideDefaultCharacterStats()
      UpdateCustomStatsFrame(db)
      if customGearFrame then
        customGearFrame:Hide()
      end
    end
  else
    for _, bg in pairs(statRows) do
      if bg and bg.Hide then
        bg:Hide()
      end
    end
    for _, skin in pairs(slotSkins) do
      if skin and skin.Hide then
        skin:Hide()
      end
    end
    for _, panel in pairs(panelSkins) do
      if panel and panel.Hide then
        panel:Hide()
      end
    end
    if customStatsFrame then
      customStatsFrame:Hide()
    end
    if customGearFrame then
      customGearFrame:Hide()
    end
    if modelFillFrame then
      modelFillFrame:Hide()
    end
    ShowDefaultCharacterStats()
    RestoreFonts()
  end

  local showRight = db.charsheet.showRightPanel ~= false
  if showRight then
    local panel = EnsureRightPanel(db)
    if panel then
      PositionRightPanel(db)
      panel:Show()
      ApplyRightPanelFont(db)
      RefreshRightPanelData()
      self:SetLocked(db.general and db.general.framesLocked ~= false)
    end
  elseif rightPanel then
    rightPanel:Hide()
  end
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.charsheet or not db.charsheet.enabled then
    self:Disable()
    return
  end
  M.active = true

  if not IsAddonLoadedCompat("Blizzard_CharacterUI") then
    LoadAddonCompat("Blizzard_CharacterUI")
  end

  if CharacterFrame and not hookedShow then
    CharacterFrame:HookScript("OnShow", function()
      if M.active then
        M:Refresh()
      end
    end)
    hookedShow = true
  end
  if CharacterFrame and not hookedHide then
    CharacterFrame:HookScript("OnHide", function()
      if rightPanel then
        rightPanel:Hide()
      end
      if customCharacterFrame then
        customCharacterFrame:Hide()
      end
    end)
    hookedHide = true
  end

  if not ticker then
    ticker = CreateFrame("Frame")
  end
  elapsedSinceTick = 0
  elapsedSinceData = 0
  ticker:SetScript("OnUpdate", function(_, elapsed)
    if not M.active then return end
    elapsedSinceTick = elapsedSinceTick + (elapsed or 0)
    if elapsedSinceTick < TICK_INTERVAL then return end
    elapsedSinceTick = 0
    if CharacterFrame and CharacterFrame:IsShown() then
      M:Refresh()
    elseif rightPanel and rightPanel:IsShown() then
      rightPanel:Hide()
    end
    elapsedSinceData = elapsedSinceData + (elapsed or 0)
    if elapsedSinceData >= DATA_REFRESH_INTERVAL then
      elapsedSinceData = 0
      if rightPanel and rightPanel:IsShown() then
        RefreshRightPanelData()
      end
    end
    if pendingSecureUpdate and not (InCombatLockdown and InCombatLockdown()) then
      if rightPanel and rightPanel:IsShown() then
        RefreshRightPanelData()
      else
        pendingSecureUpdate = false
      end
    end
  end)

  self:Refresh()
end

function M:Disable()
  M.active = false
  if ticker then
    ticker:SetScript("OnUpdate", nil)
  end
  if skinFrame then
    skinFrame:Hide()
  end
  if customCharacterFrame then
    customCharacterFrame:Hide()
  end
  if customNameText then
    customNameText:Hide()
  end
  if customLevelText then
    customLevelText:Hide()
  end
  for _, bg in pairs(statRows) do
    if bg and bg.Hide then
      bg:Hide()
    end
  end
  for _, skin in pairs(slotSkins) do
    if skin and skin.Hide then
      skin:Hide()
    end
  end
  for _, panel in pairs(panelSkins) do
    if panel and panel.Hide then
      panel:Hide()
    end
  end
  if rightPanel then
    rightPanel:Hide()
  end
  if customStatsFrame then
    customStatsFrame:Hide()
  end
  if customGearFrame then
    customGearFrame:Hide()
  end
  if customNameText then
    customNameText:Hide()
  end
  if customLevelText then
    customLevelText:Hide()
  end
  if modelFillFrame then
    modelFillFrame:Hide()
  end
  ShowDefaultCharacterStats()
  RestoreCapturedLayouts()
  layoutApplied = false
  RestoreFonts()
  RestoreHiddenRegions()
end

function M:SetLocked(locked)
  if not rightPanel or not rightPanel.dragger then return end
  rightPanel.dragger:Hide()
end
