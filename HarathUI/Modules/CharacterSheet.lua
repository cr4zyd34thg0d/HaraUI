local ADDON, NS = ...
local M = {}
NS:RegisterModule("charsheet", M)

M.active = false
M._pendingNativeMode = nil
M._mirroringNativeSubframeSwitch = false
M._deferredNativeModeMirror = nil
M._deferredNativeModeRefreshQueued = false

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local S = {
  hiddenRegions = {},
  styledFonts = {},
  statRows = {},
  slotSkins = {},
  panelSkins = {},
  skinFrame = nil,
  customCharacterFrame = nil,
  customNameText = nil,
  customLevelText = nil,
  customStatsFrame = nil,
  customGearFrame = nil,
  modelFillFrame = nil,
  modelBaseScale = nil,
  modelLockedCameraScale = nil,
  headerFrame = nil,
  slotDisplays = {},
  specButtons = nil,
  lootSpecButtons = nil,
  rightPanel = nil,
  originalCharacterSize = nil,
  originalLayoutByKey = {},
  layoutApplied = false,
  ticker = nil,
  slotEnforcer = nil,
  slotEnforceUntil = 0,
  moduleEventFrame = nil,
  hookedShow = false,
  hookedHide = false,
  hookedSubFrame = false,
  suppressSubFrameRefresh = false,
  liveUpdateQueued = false,
  liveUpdateIncludeRightPanel = false,
  inventoryTooltipCache = {},
  pendingLootSpecID = nil,
  refreshInProgress = false,
  refreshQueuedAfterCurrent = false,
  elapsedSinceData = 0,
  portalSpellCache = {},
  lastMPlusSnapshot = {
    ownerKey = nil,
    affixIDs = nil,
    runs = nil,
  },
  pendingSecureUpdate = false,
}

local DATA_REFRESH_INTERVAL = 2.0
local EVENT_DEBOUNCE_INTERVAL = 0.06
local ShowAffixTooltip
local ShowDungeonPortalTooltip
local UpdateCustomStatsFrame
local UpdateCustomGearFrame
local ApplyCoreCharacterFontAndName
local RestorePaperDollSidebarButtons
local ApplyCustomCharacterLayout
local ShowNativeCharacterMode
local SyncCustomModeToNativePanel

local CFG = {
  CUSTOM_CHAR_HEIGHT = 675,
  BASE_PRIMARY_SHEET_WIDTH = 820,
  FRAME_RIGHT_EXPAND_FACTOR = 1.15,
  BASE_STATS_WIDTH = 230,
  CUSTOM_PANE_GAP = 6,
  INTEGRATED_RIGHT_GAP = 8,
  RIGHT_PANEL_CENTER_Y_BIAS = -12,
  STAT_ROW_HEIGHT = 16,
  STAT_ROW_GAP = 2,
  STAT_SECTION_GAP = 7,
  STAT_SECTION_BOTTOM_PAD = 2,
  SIMPLE_BASE_PANEL_MODE = true,
  SLOT_ICON_SIZE = 38,
  GEAR_ROW_WIDTH = 272,
  GEAR_ROW_HEIGHT = 46,
  GEAR_TEXT_GAP = 10,
  MODEL_ZOOM_OUT_FACTOR = 0.80,
  STAT_GRADIENT_SPLIT = 0.82,
  STAT_TOPINFO_GRADIENT_SPLIT = 0.86,
  STAT_BODY_GRADIENT_SPLIT = 0.90,
  STAT_ROW_GRADIENT_SPLIT = 0.92,
  STAT_HEADER_GRADIENT_ALPHA = 1.00,
  STAT_BODY_GRADIENT_ALPHA = 0.72,
  STAT_ROW_GRADIENT_ALPHA = 0.74,
  HEADER_TEXT_X_OFFSET = -144, -- shift header block ~20% left total
  ENCHANT_QUALITY_MARKUP_SIZE = 18,
  STATS_MODE_BUTTON_WIDTH = 86,
  STATS_MODE_BUTTON_HEIGHT = 30,
  STATS_MODE_BUTTON_GAP = 6,
  STATS_SIDEBAR_BUTTON_COUNT = 4,
  STATS_SIDEBAR_BUTTON_SIZE = 28,
  STATS_SIDEBAR_BUTTON_GAP = 4,
  STATS_MODE_BUTTON_PAD_Y = 8,
  STATS_MODE_LIST_ROW_HEIGHT = 26,
  STATS_MODE_LIST_ROW_GAP = 4,
  STATS_TITLES_FONT_DELTA = -3,

  ATTR_YELLOW = { 0.96, 0.96, 0.96, 1.0 },
  VALUE_WHITE = { 0.96, 0.96, 0.96, 1.0 },

  LEFT_GEAR_SLOTS = {
    "HeadSlot",
    "NeckSlot",
    "ShoulderSlot",
    "BackSlot",
    "ChestSlot",
    "ShirtSlot",
    "SecondaryHandSlot",
    "WristSlot",
  },

  RIGHT_GEAR_SLOTS = {
    "HandsSlot",
    "WaistSlot",
    "LegsSlot",
    "FeetSlot",
    "Finger0Slot",
    "Finger1Slot",
    "Trinket0Slot",
    "Trinket1Slot",
    "MainHandSlot",
  },

  -- Slot index mapping for per-slot item display.
  SLOT_NAME_TO_INDEX = {
    HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4,
    ChestSlot = 5, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8,
    WristSlot = 9, HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12,
    Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15,
    MainHandSlot = 16, SecondaryHandSlot = 17, TabardSlot = 19,
  },

  -- Right-column slots display text to the LEFT (Chonky convention).
  DISPLAY_TO_LEFT = {
    [6] = true, [7] = true, [8] = true, [10] = true,
    [11] = true, [12] = true, [13] = true, [14] = true,
    [16] = true, [17] = true,
  },

  -- Rarity gradient colors (from Chonky).
  -- [rarity] = { inner_r, inner_g, inner_b, inner_a, outer_r, outer_g, outer_b, outer_a }
  RARITY_GRADIENT = {
    [1] = { 0.5, 0.5, 0.5, 0.8, 1, 1, 1, 1 },                     -- Common (white)
    [2] = { 0.06, 0.5, 0, 0.8, 0.12, 1, 0, 1 },                   -- Uncommon (green)
    [3] = { 0, 0.22, 0.435, 0.8, 0, 0.44, 0.87, 1 },              -- Rare (blue)
    [4] = { 0.32, 0.105, 0.465, 0.8, 0.64, 0.21, 0.93, 1 },       -- Epic (purple)
    [5] = { 0.5, 0.25, 0, 0.8, 1, 0.5, 0, 1 },                    -- Legendary (orange)
    [6] = { 0.45, 0.4, 0.25, 0.8, 0.9, 0.8, 0.5, 1 },             -- Artifact (tan)
    [7] = { 0, 0.4, 0.5, 0.8, 0, 0.8, 1, 1 },                     -- Heirloom (light blue)
    [0] = { 0.31, 0.31, 0.31, 0.8, 0.62, 0.62, 0.62, 1 },         -- Poor (gray)
  },

  -- Section background colors for stats panel.
  SECTION_COLORS = {
    { 0.64, 0.47, 0.1, 0.4 },   -- Attributes (gold)
    { 0.16, 0.34, 0.08, 0.4 },  -- Secondary (green)
    { 0.41, 0, 0, 0.4 },        -- Attack (red)
    { 0, 0.13, 0.38, 0.4 },     -- Defense (blue)
    { 0.45, 0.45, 0.45, 0.4 },  -- General (gray)
  },

  -- All equippable slot indices (excluding ranged 18).
  ALL_SLOT_INDICES = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19 },
  CHARACTER_SLOT_BUTTON_NAMES = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterShirtSlot",
    "CharacterChestSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterBackSlot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
    "CharacterTabardSlot",
  },
}
CFG.PRIMARY_SHEET_WIDTH = math.floor((CFG.BASE_PRIMARY_SHEET_WIDTH * CFG.FRAME_RIGHT_EXPAND_FACTOR) + 0.5)
CFG.PRIMARY_EXTRA_WIDTH = CFG.PRIMARY_SHEET_WIDTH - CFG.BASE_PRIMARY_SHEET_WIDTH
CFG.CUSTOM_STATS_WIDTH = CFG.BASE_STATS_WIDTH + CFG.PRIMARY_EXTRA_WIDTH

local function SetCharacterSlotButtonsVisible(visible)
  for _, name in ipairs(CFG.CHARACTER_SLOT_BUTTON_NAMES) do
    local btn = _G[name]
    if btn then
      if visible then
        if btn.SetAlpha then btn:SetAlpha(1) end
        if btn.Show then btn:Show() end
        if btn.EnableMouse then btn:EnableMouse(true) end
      else
        if btn.EnableMouse then btn:EnableMouse(false) end
        if btn.SetAlpha then btn:SetAlpha(0) end
        if btn.Hide then btn:Hide() end
      end
    end
  end
end

local function CaptureLayout(key, frame)
  if not key or not frame or S.originalLayoutByKey[key] then return end
  local points = {}
  if frame.GetNumPoints and frame.GetPoint then
    for i = 1, frame:GetNumPoints() do
      local p, rel, rp, x, y = frame:GetPoint(i)
      points[#points + 1] = { p = p, rel = rel, rp = rp, x = x, y = y }
    end
  end
  S.originalLayoutByKey[key] = {
    frame = frame,
    width = frame.GetWidth and frame:GetWidth() or nil,
    height = frame.GetHeight and frame:GetHeight() or nil,
    points = points,
  }
end

local function RestoreCapturedLayouts()
  local function NormalizePoint(p)
    if p == "CENTERLEFT" then return "LEFT" end
    if p == "CENTERRIGHT" then return "RIGHT" end
    return p
  end

  for _, data in pairs(S.originalLayoutByKey) do
    local frame = data and data.frame
    if frame and frame.ClearAllPoints and data.points then
      frame:ClearAllPoints()
      for _, pt in ipairs(data.points) do
        frame:SetPoint(NormalizePoint(pt.p), pt.rel, NormalizePoint(pt.rp), pt.x, pt.y)
      end
    end
    if frame and frame.SetSize and data and data.width and data.height then
      frame:SetSize(data.width, data.height)
    end
  end
  wipe(S.originalLayoutByKey)
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
  ["mechagon junkyard"] = { common = { "junkyard", "mechagon junkyard", "operation mechagon", "mechagon" } },
  ["mechagon workshop"] = { common = { "workshop", "mechagon workshop", "operation mechagon", "mechagon" } },
  ["operation mechagon junkyard"] = { common = { "junkyard", "mechagon junkyard", "operation mechagon", "mechagon" } },
  ["operation mechagon workshop"] = { common = { "workshop", "mechagon workshop", "operation mechagon", "mechagon" } },
  ["tazavesh streets of wonder"] = {
    common = { "tazavesh", "veiled market", "streetwise merchant", "path of the streetwise merchant" },
  },
  ["tazavesh so leah s gambit"] = {
    common = { "tazavesh", "veiled market", "streetwise merchant", "path of the streetwise merchant" },
  },
  ["galakrond s fall"] = { common = { "dawn of the infinite" } },
  ["murozond s rise"] = { common = { "dawn of the infinite" } },
  ["dawn of the infinite galakrond s fall"] = { common = { "dawn of the infinite", "galakrond s fall" } },
  ["dawn of the infinite murozond s rise"] = { common = { "dawn of the infinite", "murozond s rise" } },
  ["lower karazhan"] = { common = { "return to karazhan", "karazhan" } },
  ["upper karazhan"] = { common = { "return to karazhan", "karazhan" } },
  ["return to karazhan lower"] = { common = { "return to karazhan", "karazhan" } },
  ["return to karazhan upper"] = { common = { "return to karazhan", "karazhan" } },
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
  if not S.hiddenRegions[region] then
    S.hiddenRegions[region] = {
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
  for region, state in pairs(S.hiddenRegions) do
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
  wipe(S.hiddenRegions)
end

local function BackupFont(fs)
  if not fs or S.styledFonts[fs] then return end
  local path, size, flags = fs:GetFont()
  S.styledFonts[fs] = {
    path = path,
    size = size,
    flags = flags,
  }
end

local function RestoreFonts()
  for fs, data in pairs(S.styledFonts) do
    if fs and data and data.path and fs.SetFont then
      fs:SetFont(data.path, data.size or 12, data.flags)
    end
  end
  wipe(S.styledFonts)
end

RestorePaperDollSidebarButtons = function()
  if not CharacterFrame then return end

  local function GetSidebarButton(index)
    local names = {
      ("PaperDollSidebarTab%d"):format(index),
      ("PaperDollSidebarButton%d"):format(index),
      ("CharacterFrameSidebarTab%d"):format(index),
      ("CharacterSidebarTab%d"):format(index),
    }
    for _, name in ipairs(names) do
      local btn = _G[name]
      if btn then
        return btn
      end
    end
    return nil
  end

  for i = 1, 8 do
    local btn = GetSidebarButton(i)
    if btn then
      if btn.SetAlpha then btn:SetAlpha(1) end
      if btn.Show then btn:Show() end
      if btn.Enable then btn:Enable() end
      if btn.EnableMouse then btn:EnableMouse(true) end

      if btn._haraSidebarSkin and btn._haraSidebarSkin.Hide then
        btn._haraSidebarSkin:Hide()
      end

      local icon = btn.Icon or btn.icon or (btn.GetName and _G[btn:GetName() .. "Icon"]) or nil
      if icon then
        if icon.SetAlpha then icon:SetAlpha(1) end
        if icon.Show then icon:Show() end
      end

      if btn.GetNormalTexture then
        local nt = btn:GetNormalTexture()
        if nt then
          if nt.SetAlpha then nt:SetAlpha(1) end
          if nt.Show then nt:Show() end
        end
      end
      if btn.GetPushedTexture then
        local pt = btn:GetPushedTexture()
        if pt then
          if pt.SetAlpha then pt:SetAlpha(1) end
          if pt.Show then pt:Show() end
        end
      end
      if btn.GetHighlightTexture then
        local ht = btn:GetHighlightTexture()
        if ht then
          if ht.SetAlpha then ht:SetAlpha(1) end
          if ht.Show then ht:Show() end
        end
      end
    end
  end
end

local function SetPaperDollSidebarButtonsMouseEnabled(enabled)
  local shouldEnable = enabled == true
  for i = 1, 8 do
    local names = {
      ("PaperDollSidebarTab%d"):format(i),
      ("PaperDollSidebarButton%d"):format(i),
      ("CharacterFrameSidebarTab%d"):format(i),
      ("CharacterSidebarTab%d"):format(i),
    }
    for _, name in ipairs(names) do
      local btn = _G[name]
      if btn then
        if btn.EnableMouse then
          btn:EnableMouse(shouldEnable)
        end
        break
      end
    end
  end
end

local function EnsureSlotSkin(slotButton)
  if not slotButton then return nil end
  if S.slotSkins[slotButton] then
    local existing = S.slotSkins[slotButton]
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

  S.slotSkins[slotButton] = holder
  return holder
end

local function EnsurePanelSkin(key, parent)
  if not key or not parent then return nil end
  if S.panelSkins[key] then return S.panelSkins[key] end

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
  S.panelSkins[key] = panel
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
  if S.skinFrame then return S.skinFrame end

  S.skinFrame = CreateFrame("Frame", nil, CharacterFrame, "BackdropTemplate")
  S.skinFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 1)
  S.skinFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
  S.skinFrame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", 0, 0)
  S.skinFrame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  S.skinFrame:SetBackdropColor(0.02, 0.01, 0.05, 0.93)
  S.skinFrame:SetBackdropBorderColor(0.34, 0.16, 0.52, 0.95)
  S.skinFrame:Hide()

  return S.skinFrame
end

local function EnsureCustomCharacterFrame()
  if not CharacterFrame then return nil end
  if S.customCharacterFrame then return S.customCharacterFrame end

  S.customCharacterFrame = CreateFrame("Frame", nil, CharacterFrame, "BackdropTemplate")
  S.customCharacterFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 1)
  S.customCharacterFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
  S.customCharacterFrame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", 0, 0)
  S.customCharacterFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  S.customCharacterFrame:SetBackdropColor(0, 0, 0, 0)
  S.customCharacterFrame:SetBackdropBorderColor(0, 0, 0, 0)
  S.customCharacterFrame:EnableMouse(true)
  S.customCharacterFrame:SetMovable(true)
  S.customCharacterFrame:RegisterForDrag("LeftButton")
  S.customCharacterFrame:SetScript("OnDragStart", function()
    if InCombatLockdown and InCombatLockdown() then return end
    if CharacterFrame and CharacterFrame.SetMovable then
      CharacterFrame:SetMovable(true)
    end
    if CharacterFrame and CharacterFrame.SetClampedToScreen then
      CharacterFrame:SetClampedToScreen(true)
    end
    if CharacterFrame and CharacterFrame.SetUserPlaced then
      CharacterFrame:SetUserPlaced(true)
    end
    if CharacterFrame and CharacterFrame.StartMoving then
      CharacterFrame:StartMoving()
    end
  end)
  S.customCharacterFrame:SetScript("OnDragStop", function()
    if CharacterFrame and CharacterFrame.StopMovingOrSizing then
      CharacterFrame:StopMovingOrSizing()
    end
  end)
  S.customCharacterFrame:Hide()

  S.customCharacterFrame.innerGlow = S.customCharacterFrame:CreateTexture(nil, "BACKGROUND")
  S.customCharacterFrame.innerGlow:SetPoint("TOPLEFT", 1, -1)
  S.customCharacterFrame.innerGlow:SetPoint("BOTTOMRIGHT", -1, 1)
  S.customCharacterFrame.innerGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
  -- Keep this very subtle; modelFill handles the main panel gradient now.
  S.customCharacterFrame.innerGlow:SetVertexColor(0, 0, 0, 0)

  S.headerFrame = CreateFrame("Frame", nil, CharacterFrame)
  S.headerFrame:SetAllPoints(CharacterFrame)
  S.headerFrame:SetFrameStrata("HIGH")
  S.headerFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 40)

  S.customNameText = S.headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.customNameText:SetPoint("TOP", CharacterFrame, "TOP", CFG.HEADER_TEXT_X_OFFSET, -8)
  S.customNameText:SetJustifyH("CENTER")
  S.customNameText:SetDrawLayer("OVERLAY", 7)
  S.customNameText:SetShadowOffset(1, -1)
  S.customNameText:SetShadowColor(0, 0, 0, 0.95)

  S.customLevelText = S.headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.customLevelText:SetPoint("TOP", S.customNameText, "BOTTOM", 0, -2)
  S.customLevelText:SetJustifyH("CENTER")
  S.customLevelText:SetDrawLayer("OVERLAY", 7)
  S.customLevelText:SetShadowOffset(1, -1)
  S.customLevelText:SetShadowColor(0, 0, 0, 0.95)

  return S.customCharacterFrame
end

local function EnsureModelFillFrame()
  if S.modelFillFrame then return S.modelFillFrame end
  if not CharacterFrame then return nil end

  S.modelFillFrame = CreateFrame("Frame", nil, CharacterFrame)
  S.modelFillFrame:SetFrameStrata(CharacterFrame:GetFrameStrata() or "MEDIUM")
  S.modelFillFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 1)
  S.modelFillFrame.base = S.modelFillFrame:CreateTexture(nil, "BACKGROUND")
  S.modelFillFrame.base:SetAllPoints()
  S.modelFillFrame.base:SetTexture("Interface\\Buttons\\WHITE8x8")
  S.modelFillFrame.base:SetColorTexture(0, 0, 0, 0.0)

  S.modelFillFrame.overlay = S.modelFillFrame:CreateTexture(nil, "BORDER")
  S.modelFillFrame.overlay:SetAllPoints()
  S.modelFillFrame.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
  -- Character panel gradient (reversed relative to M+): purple at top -> black at bottom.
  if S.modelFillFrame.overlay.SetGradient and CreateColor then
    S.modelFillFrame.overlay:SetGradient(
      "VERTICAL",
      CreateColor(0.08, 0.02, 0.12, 0.90),
      CreateColor(0, 0, 0, 0.90)
    )
  elseif S.modelFillFrame.overlay.SetGradientAlpha then
    S.modelFillFrame.overlay:SetGradientAlpha("VERTICAL", 0.08, 0.02, 0.12, 0.90, 0, 0, 0, 0.90)
  else
    S.modelFillFrame.overlay:SetColorTexture(0.08, 0.02, 0.12, 0.90)
  end
  S.modelFillFrame:Hide()
  return S.modelFillFrame
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

local STAT_TOOLTIP_SETTERS = {
  ["criticalstrike"] = "PaperDollFrame_SetCritChance",
  ["criticalstrikechance"] = "PaperDollFrame_SetCritChance",
  ["health"] = "PaperDollFrame_SetHealth",
  ["power"] = "PaperDollFrame_SetPower",
  ["itemlevel"] = "PaperDollFrame_SetItemLevel",
  ["averageitemlevel"] = "PaperDollFrame_SetItemLevel",
  ["haste"] = "PaperDollFrame_SetHaste",
  ["mastery"] = "PaperDollFrame_SetMastery",
  ["versatility"] = "PaperDollFrame_SetVersatility",
  ["attackpower"] = "PaperDollFrame_SetAttackPower",
  ["attackspeed"] = "PaperDollFrame_SetAttackSpeed",
  ["mainhandspeed"] = "PaperDollFrame_SetAttackSpeed",
  ["weaponspeed"] = "PaperDollFrame_SetAttackSpeed",
  ["spellpower"] = "PaperDollFrame_SetSpellPower",
  ["armor"] = "PaperDollFrame_SetArmor",
  ["dodge"] = "PaperDollFrame_SetDodge",
  ["parry"] = "PaperDollFrame_SetParry",
  ["block"] = "PaperDollFrame_SetBlock",
  ["stagger"] = "PaperDollFrame_SetStagger",
  ["leech"] = "PaperDollFrame_SetLifesteal",
  ["lifesteal"] = "PaperDollFrame_SetLifesteal",
  ["avoidance"] = "PaperDollFrame_SetAvoidance",
  ["speed"] = "PaperDollFrame_SetSpeed",
  ["movementspeed"] = "PaperDollFrame_SetMovementSpeed",
}

local STAT_TOOLTIP_PRIMARY_INDICES = {
  ["strength"] = LE_UNIT_STAT_STRENGTH or 1,
  ["agility"] = LE_UNIT_STAT_AGILITY or 2,
  ["stamina"] = LE_UNIT_STAT_STAMINA or 3,
  ["intellect"] = LE_UNIT_STAT_INTELLECT or 4,
}

local StatTooltipBridge = {
  scratch = nil,
}

function StatTooltipBridge.NormalizeText(text)
  if type(text) ~= "string" then
    return ""
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|r", "")
  text = text:gsub("|A.-|a", "")
  text = text:gsub("|T.-|t", "")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("%s+", " ")
  return text
end

function StatTooltipBridge.CanonicalLabel(text)
  local clean = StatTooltipBridge.NormalizeText(text)
  clean = clean:lower()
  clean = clean:gsub("[^%w]+", "")
  return clean
end

function StatTooltipBridge.ResolveSetter(label)
  local key = StatTooltipBridge.CanonicalLabel(label)
  if key == "" then
    return nil, nil
  end

  if key == "gcd" or key == "globalcooldown" or key == "globalcooldownreduction" then
    return "__CUSTOM_GCD", nil
  end

  local statIndex = STAT_TOOLTIP_PRIMARY_INDICES[key]
  if statIndex then
    return "PaperDollFrame_SetStat", statIndex
  end

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
  if StatTooltipBridge.scratch then
    return StatTooltipBridge.scratch
  end

  local parent = UIParent or CharacterFrame
  if not parent then
    return nil
  end

  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(1, 1)
  frame:EnableMouse(false)
  frame:SetAlpha(0)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", -10000, 10000)
  frame:Hide()
  frame.Label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.Value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if frame.Label and frame.Label.SetPoint then
    frame.Label:SetPoint("LEFT", frame, "LEFT", 0, 0)
  end
  if frame.Value and frame.Value.SetPoint then
    frame.Value:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
  end
  StatTooltipBridge.scratch = frame
  return frame
end

function StatTooltipBridge.BuildScratchStatFrame(label)
  local setterName, statIndex = StatTooltipBridge.ResolveSetter(label)
  if not setterName then
    return nil
  end

  local frame = StatTooltipBridge.EnsureScratchFrame()
  if not frame then
    return nil
  end

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
    frame.tooltip2 = ("Time between ability uses. Current haste: %.2f%%."):format(haste or 0)
    frame.tooltip3 = "Haste reduces global cooldown to your class minimum."
    return frame
  end

  local setter = _G[setterName]
  if type(setter) ~= "function" then
    return nil
  end

  local ok
  if statIndex then
    ok = pcall(setter, frame, "player", statIndex)
  else
    ok = pcall(setter, frame, "player")
  end
  if not ok then
    return nil
  end

  return frame
end

function StatTooltipBridge.Reanchor(row)
  if not (row and GameTooltip and GameTooltip:IsShown()) then
    return
  end
  if GameTooltip.ClearAllPoints then
    GameTooltip:ClearAllPoints()
    local ui = UIParent or row:GetParent()
    local uiScale = ui and ui.GetEffectiveScale and ui:GetEffectiveScale() or nil
    if ui and uiScale and type(GetCursorPosition) == "function" then
      local x, y = GetCursorPosition()
      x = x / uiScale
      y = y / uiScale
      GameTooltip:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", x + 16, y - 16)
    else
      GameTooltip:SetPoint("LEFT", row, "RIGHT", 8, 0)
    end
  end
end

function StatTooltipBridge.TryShowGeneratedTooltip(row)
  if not row then
    return false
  end

  local source = StatTooltipBridge.BuildScratchStatFrame(row._tooltipKey or row._tooltipLabel)
  if not source then
    return false
  end

  local handled = false
  if GameTooltip and GameTooltip:IsShown() then
    GameTooltip:Hide()
  end

  if type(source.onEnterFunc) == "function" then
    local ok = pcall(source.onEnterFunc, source)
    handled = ok and GameTooltip and GameTooltip:IsShown()
  end

  if not handled and type(PaperDollStatTooltip) == "function" and (source.tooltip or source.tooltip2 or source.tooltip3) then
    local ok = pcall(PaperDollStatTooltip, source)
    handled = ok and GameTooltip and GameTooltip:IsShown()
  end

  if not handled and GameTooltip and (source.tooltip or source.tooltip2 or source.tooltip3) then
    local nfc = NORMAL_FONT_COLOR or { r = 0.9, g = 0.9, b = 0.9 }
    local title = source.tooltip or StatTooltipBridge.NormalizeText(row._tooltipLabel)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if title and title ~= "" then
      GameTooltip:SetText(title)
    end
    if source.tooltip2 and source.tooltip2 ~= "" then
      GameTooltip:AddLine(source.tooltip2, nfc.r, nfc.g, nfc.b, true)
    end
    if source.tooltip3 and source.tooltip3 ~= "" then
      GameTooltip:AddLine(source.tooltip3, nfc.r, nfc.g, nfc.b, true)
    end
    GameTooltip:Show()
    handled = GameTooltip:IsShown()
  end

  if handled then
    source.UpdateTooltip = nil
    StatTooltipBridge.Reanchor(row)
  end
  return handled and true or false
end

function StatTooltipBridge.ShowFallback(row)
  if not (row and GameTooltip) then return end
  local label = StatTooltipBridge.NormalizeText(row._tooltipLabel or (row.left and row.left.GetText and row.left:GetText()) or "")
  local value = StatTooltipBridge.NormalizeText(row._tooltipValue or (row.right and row.right.GetText and row.right:GetText()) or "")
  if label == "" and value == "" then
    return
  end

  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  if label ~= "" then
    GameTooltip:AddLine(label, 1, 1, 1)
  end
  if value ~= "" then
    GameTooltip:AddLine(value, 0.9, 0.9, 0.9)
  end
  GameTooltip:Show()
end

function StatTooltipBridge.HandleEnter(row)
  if not row then return end

  if GameTooltip and GameTooltip:IsShown() then
    GameTooltip:Hide()
  end

  if not StatTooltipBridge.TryShowGeneratedTooltip(row) then
    StatTooltipBridge.ShowFallback(row)
  end
end

function StatTooltipBridge.HandleLeave(row)
  if not row then return end
  if GameTooltip and GameTooltip:IsShown() then
    GameTooltip:Hide()
  end
end

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
    return TrimText(replaced)
  end

  if playerName ~= "" and rawTitle:find(playerName, 1, true) then
    return TrimText(rawTitle)
  end

  local clean = TrimText(rawTitle)
  if clean == "" then
    return ""
  end
  if playerName == "" then
    return clean
  end

  -- WoW title data often signals prefix titles with trailing whitespace.
  -- Example: "Brawler " => "Brawler Name"
  if rawTitle:find("%s$") then
    return rawTitle:gsub("%s+$", " ") .. playerName
  end

  if clean:match("^[,%.:;!%?]") then
    return playerName .. clean
  end

  -- Default to Blizzard-style suffix when no explicit placeholder exists.
  -- Example: "Breaker of Chains" => "Name, Breaker of Chains"
  return playerName .. ", " .. clean
end

local function BuildKnownTitlesData()
  local rows = {}
  if not (GetNumTitles and GetTitleName and IsTitleKnown) then
    return rows
  end
  local playerName = UnitName and UnitName("player") or ""
  local current = GetCurrentTitle and GetCurrentTitle() or 0
  local total = GetNumTitles() or 0
  for i = 1, total do
    if IsTitleKnown(i) then
      local raw = GetTitleName(i)
      local clean = BuildContextualTitleText(raw, playerName)
      rows[#rows + 1] = {
        id = i,
        label = clean ~= "" and clean or ("Title " .. i),
        detail = (current == i) and "Active" or "",
        selected = false,
        icon = 133742,
      }
    end
  end
  table.sort(rows, function(a, b)
    return (a.label or ""):lower() < (b.label or ""):lower()
  end)
  return rows
end

local function BuildEquipmentSetsData(selectedSetID)
  local rows = {}
  if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetInfo) then
    return rows
  end
  local active = C_EquipmentSet.GetEquipmentSetForSpec and C_EquipmentSet.GetEquipmentSetForSpec(GetSpecialization and GetSpecialization() or 0) or nil
  local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
  for _, setID in ipairs(ids) do
    local name, icon, _, _, _, _, _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
    if type(name) == "string" and name ~= "" then
      local selected = (selectedSetID and selectedSetID == setID) or (isEquipped == true) or (active and active == setID) or false
      rows[#rows + 1] = {
        id = setID,
        label = name,
        detail = (isEquipped == true or (active and active == setID)) and "Active" or (selectedSetID and selectedSetID == setID and "Selected" or ""),
        selected = selected,
        icon = icon or 132627,
      }
    end
  end
  table.sort(rows, function(a, b)
    return (a.label or ""):lower() < (b.label or ""):lower()
  end)
  return rows
end

local function BuildReputationData()
  local rows = {}
  if not (GetNumFactions and GetFactionInfo) then
    return rows
  end
  local count = GetNumFactions() or 0
  for i = 1, count do
    local name, _, standingID, bottomValue, topValue, earnedValue, _, _, isHeader, _, hasRep, isWatched, _, _, _, _, _, isCollapsed = GetFactionInfo(i)
    if name and name ~= "" and not isHeader and hasRep ~= false and not isCollapsed then
      local span = (tonumber(topValue) or 0) - (tonumber(bottomValue) or 0)
      local earned = (tonumber(earnedValue) or 0) - (tonumber(bottomValue) or 0)
      local pct = (span > 0) and math.floor(((earned / span) * 100) + 0.5) or 0
      if pct < 0 then pct = 0 end
      if pct > 100 then pct = 100 end
      local standingText = (standingID and _G["FACTION_STANDING_LABEL" .. standingID]) or "Standing"
      rows[#rows + 1] = {
        factionIndex = i,
        label = name,
        detail = ("%s %d%%"):format(standingText, pct),
        selected = (isWatched == true),
        icon = 236681,
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.selected ~= b.selected then
      return a.selected == true
    end
    return (a.label or ""):lower() < (b.label or ""):lower()
  end)
  return rows
end

local function BuildCurrencyData()
  local rows = {}
  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo) then
    return rows
  end
  local count = C_CurrencyInfo.GetCurrencyListSize() or 0
  for i = 1, count do
    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
    if type(info) == "table" and not info.isHeader and not info.isTypeUnused then
      local name = info.name or ""
      if name ~= "" then
        local quantity = tonumber(info.quantity) or 0
        local maxQuantity = tonumber(info.maxQuantity) or 0
        rows[#rows + 1] = {
          label = name,
          detail = (maxQuantity > 0) and ("%d/%d"):format(quantity, maxQuantity) or tostring(quantity),
          selected = (info.isShowInBackpack == true),
          icon = info.iconFileID or 463446,
        }
      end
    end
  end
  table.sort(rows, function(a, b)
    local an = tonumber((a.detail or ""):match("^(%d+)")) or 0
    local bn = tonumber((b.detail or ""):match("^(%d+)")) or 0
    if an ~= bn then return an > bn end
    return (a.label or ""):lower() < (b.label or ""):lower()
  end)
  return rows
end

local function GetTopSidebarIconData(index)
  if index == 1 then
    local _, classTag = UnitClass("player")
    local coords = (classTag and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTag]) or nil
    if coords then
      return "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", coords[1], coords[2], coords[3], coords[4]
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark", 0.08, 0.92, 0.08, 0.92
  elseif index == 2 then
    return "Interface\\Icons\\INV_Scroll_03", 0.08, 0.92, 0.08, 0.92
  elseif index == 3 then
    return "Interface\\Icons\\INV_Chest_Plate12", 0.08, 0.92, 0.08, 0.92
  elseif index == 4 then
    return "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 0.0, 1.0, 0.0, 1.0
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark", 0.08, 0.92, 0.08, 0.92
end

local function EnsureCustomStatsFrame()
  if S.customStatsFrame then return S.customStatsFrame end
  if not CharacterFrame then return nil end

  S.customStatsFrame = CreateFrame("Frame", nil, CharacterFrame)
  S.customStatsFrame:SetFrameStrata("HIGH")
  S.customStatsFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 20)
  S.customStatsFrame.sections = {}
  S.customStatsFrame.modeButtons = {}
  S.customStatsFrame.activeMode = 1
  S.customStatsFrame.modeSelectedSetID = nil
  S.customStatsFrame:Hide()

  S.customStatsFrame.modeBar = CreateFrame("Frame", nil, CharacterFrame)
  S.customStatsFrame.modeBar:SetFrameLevel((S.customStatsFrame:GetFrameLevel() or 1) + 3)
  S.customStatsFrame.modeBar:SetSize((CFG.STATS_MODE_BUTTON_WIDTH * 3) + (CFG.STATS_MODE_BUTTON_GAP * 2), CFG.STATS_MODE_BUTTON_HEIGHT)
  S.customStatsFrame.sidebarBar = CreateFrame("Frame", nil, CharacterFrame)
  S.customStatsFrame.sidebarBar:SetFrameLevel((S.customStatsFrame:GetFrameLevel() or 1) + 6)
  S.customStatsFrame.sidebarBar:SetSize(
    (CFG.STATS_SIDEBAR_BUTTON_SIZE * CFG.STATS_SIDEBAR_BUTTON_COUNT) + (CFG.STATS_SIDEBAR_BUTTON_GAP * (CFG.STATS_SIDEBAR_BUTTON_COUNT - 1)),
    CFG.STATS_SIDEBAR_BUTTON_SIZE
  )
  S.customStatsFrame.sidebarButtons = {}

  local function GetSidebarTabButton(index)
    local candidates = {
      ("PaperDollSidebarTab%d"):format(index),
      ("PaperDollSidebarButton%d"):format(index),
      ("CharacterFrameSidebarTab%d"):format(index),
      ("CharacterSidebarTab%d"):format(index),
    }
    for _, name in ipairs(candidates) do
      local btn = _G[name]
      if btn then
        return btn
      end
    end
    return nil
  end

  local function ResolveModeIcon(index)
    if index == 2 then
      return "Interface\\Icons\\Achievement_Reputation_01"
    end
    if index == 3 then
      return "Interface\\Icons\\inv_misc_coin_02"
    end
    local tab = GetSidebarTabButton(index)
    if tab then
      local icon = tab.Icon or tab.icon or (tab.GetName and _G[tab:GetName() .. "Icon"]) or (tab.GetNormalTexture and tab:GetNormalTexture())
      if type(icon) == "string" or type(icon) == "number" then
        return icon
      elseif icon and icon.GetTexture then
        local tex = icon:GetTexture()
        if tex then
          return tex
        end
      end
    end
    local fallback = {
      [1] = 132089, -- stats
      [2] = 236681, -- reputation
      [3] = 463446, -- currency
    }
    return fallback[index] or 134400
  end


  S.customStatsFrame.modeList = CreateFrame("Frame", nil, S.customStatsFrame, "BackdropTemplate")
  S.customStatsFrame.modeList:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  S.customStatsFrame.modeList:SetBackdropColor(0.02, 0.02, 0.03, 0.75)
  S.customStatsFrame.modeList:SetBackdropBorderColor(0.30, 0.18, 0.48, 0.9)
  S.customStatsFrame.modeList:Hide()
  S.customStatsFrame.modeList.viewOffsetByMode = {}
  S.customStatsFrame.modeList.currentMode = nil
  S.customStatsFrame.modeList.maxOffset = 0

  S.customStatsFrame.modeList.header = S.customStatsFrame.modeList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  S.customStatsFrame.modeList.header:SetPoint("TOP", S.customStatsFrame.modeList, "TOP", 0, -5)
  S.customStatsFrame.modeList.header:SetTextColor(1, 1, 1, 1)
  S.customStatsFrame.modeList.header:SetText("")

  S.customStatsFrame.modeList.actions = CreateFrame("Frame", nil, S.customStatsFrame.modeList)
  S.customStatsFrame.modeList.actions:SetPoint("TOPLEFT", S.customStatsFrame.modeList, "TOPLEFT", 6, -26)
  S.customStatsFrame.modeList.actions:SetPoint("TOPRIGHT", S.customStatsFrame.modeList, "TOPRIGHT", -6, -26)
  S.customStatsFrame.modeList.actions:SetHeight(22)
  S.customStatsFrame.modeList.actions:Hide()

  local function DoEquipmentSetAction(action)
    if S.customStatsFrame.activeMode ~= 5 then return end
    if not C_EquipmentSet then return end
    if InCombatLockdown and InCombatLockdown() then
      if NS and NS.Print then
        NS.Print("Cannot manage equipment sets in combat.")
      end
      return
    end
    local selected = S.customStatsFrame.modeSelectedSetID
    if action == "equip" then
      if selected and C_EquipmentSet.UseEquipmentSet then
        pcall(C_EquipmentSet.UseEquipmentSet, selected)
      end
    elseif action == "save" then
      if selected and C_EquipmentSet.ModifyEquipmentSet then
        pcall(C_EquipmentSet.ModifyEquipmentSet, selected)
      end
    elseif action == "new" then
      if C_EquipmentSet.CreateEquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        local n = #(C_EquipmentSet.GetEquipmentSetIDs() or {}) + 1
        local name = ("Set %d"):format(n)
        local icon = 132627
        if GetInventoryItemTexture then
          icon = GetInventoryItemTexture("player", 16) or icon
        end
        pcall(C_EquipmentSet.CreateEquipmentSet, name, icon)
      end
    elseif action == "delete" then
      if selected and C_EquipmentSet.DeleteEquipmentSet then
        pcall(C_EquipmentSet.DeleteEquipmentSet, selected)
        S.customStatsFrame.modeSelectedSetID = nil
      end
    end
    if UpdateCustomStatsFrame and NS and NS.GetDB then
      UpdateCustomStatsFrame(NS:GetDB())
    end
  end

  local function CreateActionButton(parent, key, label, xOfs)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(48, 20)
    b:SetPoint("LEFT", parent, "LEFT", xOfs, 0)
    b:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    b:SetBackdropColor(0.05, 0.02, 0.08, 0.9)
    b:SetBackdropBorderColor(0.26, 0.18, 0.36, 0.95)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b.text:SetTextColor(0.95, 0.95, 0.95, 1)
    b._actionKey = key
    b:SetScript("OnClick", function(self)
      DoEquipmentSetAction(self._actionKey)
    end)
    return b
  end

  S.customStatsFrame.modeList.actionButtons = {
    CreateActionButton(S.customStatsFrame.modeList.actions, "equip", "Equip", 0),
    CreateActionButton(S.customStatsFrame.modeList.actions, "save", "Save", 54),
    CreateActionButton(S.customStatsFrame.modeList.actions, "new", "New", 108),
    CreateActionButton(S.customStatsFrame.modeList.actions, "delete", "Delete", 162),
  }

  S.customStatsFrame.modeList.rows = {}
  for i = 1, 14 do
    local row = CreateFrame("Button", nil, S.customStatsFrame.modeList, "BackdropTemplate")
    row:SetHeight(CFG.STATS_MODE_LIST_ROW_HEIGHT)
    row:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    row:SetBackdropColor(0.04, 0.02, 0.07, 0.65)
    row:SetBackdropBorderColor(0.18, 0.12, 0.26, 0.7)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetTexture(134400)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetTextColor(0.95, 0.95, 0.95, 1)

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.detail:SetJustifyH("RIGHT")
    row.detail:SetTextColor(0.95, 0.75, 0.30, 1)

    row:SetScript("OnClick", function(self)
      local data = self._data
      if type(data) ~= "table" then return end
      if S.customStatsFrame.activeMode == 2 then
        if SetWatchedFactionIndex and type(data.factionIndex) == "number" then
          pcall(SetWatchedFactionIndex, data.factionIndex)
          if UpdateCustomStatsFrame and NS and NS.GetDB then
            UpdateCustomStatsFrame(NS:GetDB())
          end
        end
      elseif S.customStatsFrame.activeMode == 4 then
        if SetCurrentTitle and type(data.id) == "number" then
          pcall(SetCurrentTitle, data.id)
          if UpdateCustomStatsFrame and NS and NS.GetDB then
            UpdateCustomStatsFrame(NS:GetDB())
          end
          if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
              if not (M and M.active and CharacterFrame and CharacterFrame:IsShown()) then return end
              if not (S.customStatsFrame and S.customStatsFrame.activeMode == 4) then return end
              if UpdateCustomStatsFrame and NS and NS.GetDB then
                UpdateCustomStatsFrame(NS:GetDB())
              end
            end)
          end
        end
      elseif S.customStatsFrame.activeMode == 5 then
        if type(data.id) == "number" then
          S.customStatsFrame.modeSelectedSetID = data.id
          if UpdateCustomStatsFrame and NS and NS.GetDB then
            UpdateCustomStatsFrame(NS:GetDB())
          end
        end
      end
    end)

    S.customStatsFrame.modeList.rows[i] = row
  end

  local function UpdateModeButtonVisuals(frame)
    if not frame or not frame.modeButtons then return end
    for _, btn in ipairs(frame.modeButtons) do
      if btn.SetBackdropBorderColor then
        btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
        btn:SetBackdropColor(0.03, 0.02, 0.05, 0.92)
      end
      if btn.label then
        btn.label:SetTextColor(0.92, 0.92, 0.92, 1)
      end
    end
  end

  local function UpdateSidebarButtonVisuals(frame)
    if not frame or not frame.sidebarButtons then return end
    local liveDB = NS and NS.GetDB and NS:GetDB() or nil
    local selectedByMode = {
      [1] = 1, -- stats
      [4] = 2, -- titles
      [5] = 3, -- equipment
    }
    local selected = selectedByMode[frame.activeMode or 1]
    for i, btn in ipairs(frame.sidebarButtons) do
      if btn and btn.SetBackdropBorderColor then
        if i == selected then
          btn:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.98)
        else
          btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
        end
      end
    end
  end

  for i = 1, 3 do
    local btn = CreateFrame("Button", nil, S.customStatsFrame.modeBar, "BackdropTemplate")
    btn:SetSize(CFG.STATS_MODE_BUTTON_WIDTH, CFG.STATS_MODE_BUTTON_HEIGHT)
    btn:SetPoint("LEFT", S.customStatsFrame.modeBar, "LEFT", (i - 1) * (CFG.STATS_MODE_BUTTON_WIDTH + CFG.STATS_MODE_BUTTON_GAP), 0)
    btn:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.03, 0.02, 0.05, 0.92)
    btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
    btn.modeIndex = i

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(14, 14)
    btn.icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetTexture(ResolveModeIcon(i))

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 5, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.label:SetJustifyH("LEFT")
    if i == 1 then
      btn.label:SetText("Character")
    elseif i == 2 then
      btn.label:SetText("Rep")
      btn.label:ClearAllPoints()
      btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
      btn.label:SetJustifyH("CENTER")
    else
      btn.label:SetText("Currency")
    end

    btn:SetScript("OnClick", function(self)
      local idx = self.modeIndex or 1
      M.SwitchMode(idx, "tab")
      UpdateModeButtonVisuals(S.customStatsFrame)
    end)

    S.customStatsFrame.modeButtons[i] = btn
  end
  UpdateModeButtonVisuals(S.customStatsFrame)

  for i = 1, CFG.STATS_SIDEBAR_BUTTON_COUNT do
    local btn = CreateFrame("Button", nil, S.customStatsFrame.sidebarBar, "BackdropTemplate")
    btn:SetSize(CFG.STATS_SIDEBAR_BUTTON_SIZE, CFG.STATS_SIDEBAR_BUTTON_SIZE)
    btn:SetPoint("LEFT", S.customStatsFrame.sidebarBar, "LEFT", (i - 1) * (CFG.STATS_SIDEBAR_BUTTON_SIZE + CFG.STATS_SIDEBAR_BUTTON_GAP), 0)
    btn:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.03, 0.02, 0.05, 0.92)
    btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
    btn.sidebarIndex = i

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    do
      local tex, l, r, t, b = GetTopSidebarIconData(i)
      btn.icon:SetTexture(tex)
      btn.icon:SetTexCoord(l, r, t, b)
    end
    btn.tooltipText = ({
      [1] = "Character Stats",
      [2] = "Titles",
      [3] = "Equipment Manager",
      [4] = "Hide Mythic Window",
    })[i]

    btn:SetScript("OnClick", function(self)
      local idx = self.sidebarIndex or 1
      M._pendingNativeMode = nil
      if idx == 1 then
        S.customStatsFrame.activeMode = 1
      elseif idx == 2 then
        S.customStatsFrame.activeMode = 4
      elseif idx == 3 then
        S.customStatsFrame.activeMode = 5
      elseif idx == 4 then
        local liveDB = NS and NS.GetDB and NS:GetDB() or nil
        if liveDB and liveDB.charsheet then
          liveDB.charsheet.rightPanelCollapsed = not (liveDB.charsheet.rightPanelCollapsed == true)
        end
      end
      UpdateSidebarButtonVisuals(S.customStatsFrame)
      if M and M.Refresh then
        M:Refresh()
      elseif UpdateCustomStatsFrame and NS and NS.GetDB then
        UpdateCustomStatsFrame(NS:GetDB())
      end
      if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
      end
    end)

    btn:SetScript("OnEnter", function(self)
      if self and self.SetBackdropBorderColor then
        if self.sidebarIndex ~= 4 then
          self:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.98)
        end
      end
      local text = self and self.tooltipText or nil
      if text and text ~= "" and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 6)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    btn:SetScript("OnLeave", function(self)
      if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
      end
      if S.customStatsFrame and S.customStatsFrame.sidebarButtons then
        UpdateSidebarButtonVisuals(S.customStatsFrame)
        return
      end
      if self and self.SetBackdropBorderColor then
        self:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
      end
    end)

    S.customStatsFrame.sidebarButtons[i] = btn
  end
  UpdateSidebarButtonVisuals(S.customStatsFrame)

  S.customStatsFrame.topInfo = CreateFrame("Frame", nil, S.customStatsFrame, "BackdropTemplate")
  S.customStatsFrame.topInfo:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  S.customStatsFrame.topInfo:SetBackdropColor(0.02, 0.02, 0.03, 0.75)
  S.customStatsFrame.topInfo:SetBackdropBorderColor(0, 0, 0, 0)
  S.customStatsFrame.topInfo:SetHeight(66)
  S.customStatsFrame.topInfo:EnableMouse(true)

  S.customStatsFrame.topInfo.ilvl = S.customStatsFrame.topInfo:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  S.customStatsFrame.topInfo.ilvl:SetPoint("TOP", S.customStatsFrame.topInfo, "TOP", 0, -4)
  S.customStatsFrame.topInfo.ilvl:SetTextColor(0.73, 0.27, 1.0, 1.0)
  S.customStatsFrame.topInfo.ilvl:SetText("0.00 / 0.00")
  S.customStatsFrame.topInfo.ilvlHit = CreateFrame("Frame", nil, S.customStatsFrame.topInfo)
  S.customStatsFrame.topInfo.ilvlHit:SetPoint("TOPLEFT", S.customStatsFrame.topInfo, "TOPLEFT", 0, 0)
  S.customStatsFrame.topInfo.ilvlHit:SetPoint("TOPRIGHT", S.customStatsFrame.topInfo, "TOPRIGHT", 0, 0)
  S.customStatsFrame.topInfo.ilvlHit:SetHeight(24)
  S.customStatsFrame.topInfo.ilvlHit:EnableMouse(true)
  S.customStatsFrame.topInfo.ilvlHit:SetScript("OnEnter", function(self)
    StatTooltipBridge.HandleEnter(self)
  end)
  S.customStatsFrame.topInfo.ilvlHit:SetScript("OnLeave", function(self)
    StatTooltipBridge.HandleLeave(self)
  end)

  S.customStatsFrame.topInfo.healthRow = CreateFrame("Frame", nil, S.customStatsFrame.topInfo)
  S.customStatsFrame.topInfo.healthRow:SetPoint("TOPLEFT", S.customStatsFrame.topInfo, "TOPLEFT", 0, -30)
  S.customStatsFrame.topInfo.healthRow:SetPoint("TOPRIGHT", S.customStatsFrame.topInfo, "TOPRIGHT", 0, -30)
  S.customStatsFrame.topInfo.healthRow:SetHeight(16)
  S.customStatsFrame.topInfo.healthRow:EnableMouse(true)
  S.customStatsFrame.topInfo.healthRow:SetScript("OnEnter", function(self)
    StatTooltipBridge.HandleEnter(self)
  end)
  S.customStatsFrame.topInfo.healthRow:SetScript("OnLeave", function(self)
    StatTooltipBridge.HandleLeave(self)
  end)
  S.customStatsFrame.topInfo.healthRow.bg = S.customStatsFrame.topInfo.healthRow:CreateTexture(nil, "BACKGROUND")
  S.customStatsFrame.topInfo.healthRow.bg:SetAllPoints()
  S.customStatsFrame.topInfo.healthRow.bg:SetTexture("Interface/Buttons/WHITE8x8")
  S.customStatsFrame.topInfo.healthRow.left = S.customStatsFrame.topInfo.healthRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  S.customStatsFrame.topInfo.healthRow.left:SetPoint("LEFT", S.customStatsFrame.topInfo.healthRow, "LEFT", 4, 0)
  S.customStatsFrame.topInfo.healthRow.left:SetJustifyH("LEFT")
  S.customStatsFrame.topInfo.healthRow.right = S.customStatsFrame.topInfo.healthRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  S.customStatsFrame.topInfo.healthRow.right:SetPoint("RIGHT", S.customStatsFrame.topInfo.healthRow, "RIGHT", -4, 0)
  S.customStatsFrame.topInfo.healthRow.right:SetJustifyH("RIGHT")

  S.customStatsFrame.topInfo.powerRow = CreateFrame("Frame", nil, S.customStatsFrame.topInfo)
  S.customStatsFrame.topInfo.powerRow:SetPoint("TOPLEFT", S.customStatsFrame.topInfo.healthRow, "BOTTOMLEFT", 0, -2)
  S.customStatsFrame.topInfo.powerRow:SetPoint("TOPRIGHT", S.customStatsFrame.topInfo.healthRow, "TOPRIGHT", 0, -2)
  S.customStatsFrame.topInfo.powerRow:SetHeight(16)
  S.customStatsFrame.topInfo.powerRow:EnableMouse(true)
  S.customStatsFrame.topInfo.powerRow:SetScript("OnEnter", function(self)
    StatTooltipBridge.HandleEnter(self)
  end)
  S.customStatsFrame.topInfo.powerRow:SetScript("OnLeave", function(self)
    StatTooltipBridge.HandleLeave(self)
  end)
  S.customStatsFrame.topInfo.powerRow.bg = S.customStatsFrame.topInfo.powerRow:CreateTexture(nil, "BACKGROUND")
  S.customStatsFrame.topInfo.powerRow.bg:SetAllPoints()
  S.customStatsFrame.topInfo.powerRow.bg:SetTexture("Interface/Buttons/WHITE8x8")
  S.customStatsFrame.topInfo.powerRow.left = S.customStatsFrame.topInfo.powerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  S.customStatsFrame.topInfo.powerRow.left:SetPoint("LEFT", S.customStatsFrame.topInfo.powerRow, "LEFT", 4, 0)
  S.customStatsFrame.topInfo.powerRow.left:SetJustifyH("LEFT")
  S.customStatsFrame.topInfo.powerRow.right = S.customStatsFrame.topInfo.powerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  S.customStatsFrame.topInfo.powerRow.right:SetPoint("RIGHT", S.customStatsFrame.topInfo.powerRow, "RIGHT", -4, 0)
  S.customStatsFrame.topInfo.powerRow.right:SetJustifyH("RIGHT")

  for i = 1, 5 do
    local sec = CreateFrame("Frame", nil, S.customStatsFrame, "BackdropTemplate")
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
    sec.title:SetText("Section")

    sec.rows = {}
    for r = 1, 5 do
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
      row.left:SetTextColor(CFG.ATTR_YELLOW[1], CFG.ATTR_YELLOW[2], CFG.ATTR_YELLOW[3], CFG.ATTR_YELLOW[4])
      row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      row.right:SetJustifyH("RIGHT")
      row.right:SetTextColor(CFG.VALUE_WHITE[1], CFG.VALUE_WHITE[2], CFG.VALUE_WHITE[3], CFG.VALUE_WHITE[4])
      row:SetScript("OnEnter", function(self)
        StatTooltipBridge.HandleEnter(self)
      end)
      row:SetScript("OnLeave", function(self)
        StatTooltipBridge.HandleLeave(self)
      end)
      sec.rows[r] = row
    end
    S.customStatsFrame.sections[i] = sec
  end

  return S.customStatsFrame
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
  if not S.customStatsFrame then return end
  local fontPath, size, outline = GetConfiguredFont(db)
  if S.customStatsFrame.topInfo and S.customStatsFrame.topInfo.ilvl and S.customStatsFrame.topInfo.ilvl.SetFont then
    S.customStatsFrame.topInfo.ilvl:SetFont(fontPath, size + 8, outline)
  end
  if S.customStatsFrame.topInfo then
    local topRows = { S.customStatsFrame.topInfo.healthRow, S.customStatsFrame.topInfo.powerRow }
    for _, row in ipairs(topRows) do
      if row and row.left and row.left.SetFont then
        row.left:SetFont(fontPath, size, outline)
      end
      if row and row.right and row.right.SetFont then
        row.right:SetFont(fontPath, size, outline)
      end
    end
  end
  if S.customStatsFrame.modeList then
    if S.customStatsFrame.modeList.header and S.customStatsFrame.modeList.header.SetFont then
      S.customStatsFrame.modeList.header:SetFont(fontPath, size + 2, outline)
    end
    for _, row in ipairs(S.customStatsFrame.modeList.rows or {}) do
      local rowFontSize = size
      local detailFontSize = math.max(9, size - 1)
      if row.label and row.label.SetFont then
        row.label:SetFont(fontPath, rowFontSize, outline)
      end
      if row.detail and row.detail.SetFont then
        row.detail:SetFont(fontPath, detailFontSize, outline)
      end
    end
  end
  for _, btn in ipairs(S.customStatsFrame.modeButtons or {}) do
    if btn and btn.label and btn.label.SetFont then
      btn.label:SetFont(fontPath, 9, outline)
    end
  end
  for _, sec in ipairs(S.customStatsFrame.sections or {}) do
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

local function BuildContextualTitleDisplayText(playerName, nameHex, titleHex)
  if type(playerName) ~= "string" then
    playerName = ""
  end
  local coloredName = nameHex .. playerName .. "|r"
  if playerName == "" then
    return coloredName
  end
  if not (GetCurrentTitle and GetTitleName) then
    return coloredName
  end

  local current = GetCurrentTitle()
  if not current or current <= 0 then
    return coloredName
  end

  local raw = GetTitleName(current)
  if type(raw) ~= "string" or raw == "" then
    return coloredName
  end
  local displayText = BuildContextualTitleText(raw, playerName)
  if displayText == "" then
    return coloredName
  end

  local function BuildColoredTextFromFormatted(displayText)
    if type(displayText) ~= "string" or displayText == "" then
      return coloredName
    end
    local escapedName = playerName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local parts = {}
    local cursor = 1
    while true do
      local startPos, endPos = displayText:find(escapedName, cursor)
      if not startPos then
        local tail = displayText:sub(cursor)
        if tail ~= "" then
          parts[#parts + 1] = titleHex .. tail .. "|r"
        end
        break
      end
      local chunk = displayText:sub(cursor, startPos - 1)
      if chunk ~= "" then
        parts[#parts + 1] = titleHex .. chunk .. "|r"
      end
      parts[#parts + 1] = coloredName
      cursor = endPos + 1
    end
    if #parts == 0 then
      return coloredName
    end
    return table.concat(parts)
  end
  return BuildColoredTextFromFormatted(displayText)
end

ApplyCoreCharacterFontAndName = function(db)
  local fontPath, size, outline = GetConfiguredFont(db)
  local headerAnchor = CharacterFrame
  local name = UnitName("player") or ""
  local _, classTag = UnitClass("player")
  local c = (classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]) or NORMAL_FONT_COLOR
  local nameHex = ("|cff%02x%02x%02x"):format(
    math.floor((c.r or 1) * 255 + 0.5),
    math.floor((c.g or 1) * 255 + 0.5),
    math.floor((c.b or 1) * 255 + 0.5)
  )
  local titleHex = "|cfff5f5f5"
  local headerNameText = BuildContextualTitleDisplayText(name, nameHex, titleHex)

  if S.customNameText then
    if S.customNameText.SetFont then S.customNameText:SetFont(fontPath, size + 6, outline) end
    S.customNameText:SetText(headerNameText)
    S.customNameText:ClearAllPoints()
    S.customNameText:SetPoint("TOP", headerAnchor, "TOP", CFG.HEADER_TEXT_X_OFFSET, -8)
    S.customNameText:Show()
  end

  local title = _G.CharacterFrameTitleText
  if title and title.SetFont then
    BackupFont(title)
    title:SetFont(fontPath, size + 4, outline)
    title:SetTextColor(1, 1, 1, 1)
    title:ClearAllPoints()
    title:SetPoint("TOP", S.customNameText or CharacterFrame, "BOTTOM", 0, -2)
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
    if S.customLevelText then
      if S.customLevelText.SetFont then S.customLevelText:SetFont(fontPath, size + 1, outline) end
      S.customLevelText:ClearAllPoints()
      S.customLevelText:SetPoint("TOP", S.customNameText or CharacterFrame, "BOTTOM", 0, -2)
      S.customLevelText:SetText(levelLine or "")
      S.customLevelText:SetTextColor(1, 1, 1, 1)
      S.customLevelText:SetAlpha(1)
      S.customLevelText:Show()
    end
  end
  if levelText and levelText.SetFont then
    BackupFont(levelText)
    levelText:SetFont(fontPath, size + 1, outline)
    levelText:ClearAllPoints()
    if S.customNameText then
      levelText:SetPoint("TOP", S.customNameText, "BOTTOM", 0, -2)
    else
      levelText:SetPoint("TOP", headerAnchor, "TOP", CFG.HEADER_TEXT_X_OFFSET, -28)
    end
    levelText:SetTextColor(1, 1, 1, 1)
    levelText:SetAlpha(0)
    if levelText.Hide then levelText:Hide() end
  end
end

local function HideDefaultCharacterStats()
  local function SetDefaultStatRowsMouseEnabled(enabled)
    local pane = _G.CharacterStatsPane
    if pane then
      if pane.EnableMouse then pane:EnableMouse(enabled) end
      if pane.SetMouseClickEnabled then pane:SetMouseClickEnabled(enabled) end
      if pane.SetMouseMotionEnabled then pane:SetMouseMotionEnabled(enabled) end
    end

    for i = 1, 80 do
      local row = _G["CharacterStatFrame" .. i]
      if row then
        if row.EnableMouse then row:EnableMouse(enabled) end
        if row.SetMouseClickEnabled then row:SetMouseClickEnabled(enabled) end
        if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(enabled) end
        if not enabled then
          if row.SetAlpha then row:SetAlpha(0) end
          if row.Hide then row:Hide() end
        end
      end
    end
  end

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
  SetDefaultStatRowsMouseEnabled(false)

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
  local function SetDefaultStatRowsMouseEnabled(enabled)
    local pane = _G.CharacterStatsPane
    if pane then
      if pane.EnableMouse then pane:EnableMouse(enabled) end
      if pane.SetMouseClickEnabled then pane:SetMouseClickEnabled(enabled) end
      if pane.SetMouseMotionEnabled then pane:SetMouseMotionEnabled(enabled) end
    end

    for i = 1, 80 do
      local row = _G["CharacterStatFrame" .. i]
      if row then
        if row.EnableMouse then row:EnableMouse(enabled) end
        if row.SetMouseClickEnabled then row:SetMouseClickEnabled(enabled) end
        if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(enabled) end
      end
    end
  end

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
  SetDefaultStatRowsMouseEnabled(true)
end

local function ApplyReputationPaneMode(db)
  local rep = _G.ReputationFrame
  if not rep or not CharacterFrame then return false end

  if _G.PaperDollFrame and _G.PaperDollFrame.Hide then _G.PaperDollFrame:Hide() end
  if _G.TokenFrame and _G.TokenFrame.Hide then _G.TokenFrame:Hide() end
  rep:Show()

  rep:ClearAllPoints()
  rep:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
  rep:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -8, 44)
  rep:SetAlpha(1)
  if rep.EnableMouse then rep:EnableMouse(true) end
  if rep.ScrollBox and rep.ScrollBox.ClearAllPoints and rep.ScrollBox.SetPoint then
    rep.ScrollBox:ClearAllPoints()
    rep.ScrollBox:SetPoint("TOPLEFT", rep, "TOPLEFT", 4, -34)
    rep.ScrollBox:SetPoint("BOTTOMRIGHT", rep, "BOTTOMRIGHT", -30, 0)
  end

  -- Keep Blizzard's base background bounds aligned to the active reputation pane.
  local bg = _G.CharacterFrameBg
  if bg and bg.ClearAllPoints and bg.SetPoint then
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", rep, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", rep, "BOTTOMRIGHT", 0, 0)
  end

  local repSkin = EnsurePanelSkin("reputation_full", rep)
  if repSkin then
    repSkin:ClearAllPoints()
    repSkin:SetPoint("TOPLEFT", rep, "TOPLEFT", 0, 0)
    repSkin:SetPoint("BOTTOMRIGHT", rep, "BOTTOMRIGHT", 0, 0)
    repSkin:SetBackdropColor(0.06, 0.02, 0.10, 0.92)
    repSkin:SetBackdropBorderColor(0, 0, 0, 0)
    repSkin:Show()
    SafeFrameLevel(repSkin, (rep:GetFrameLevel() or 1) - 1)
  end

  HideFrameTextureRegions(rep)
  if rep.NineSlice then HideFrameTextureRegions(rep.NineSlice) end
  if rep.Bg then SaveAndHideRegion(rep.Bg) end

  local fontPath, size, outline = GetConfiguredFont(db)
  local title = _G.ReputationFrameTitleText
  if title and title.SetFont then
    BackupFont(title)
    title:SetFont(fontPath, size + 2, outline)
    title:SetTextColor(1.0, 0.82, 0.20, 1)
  end
  if title and title.Hide then
    title:Hide()
  end

  if not rep._haraHeader then
    rep._haraHeader = CreateFrame("Frame", nil, CharacterFrame)
    rep._haraHeader:SetFrameStrata("DIALOG")
    rep._haraHeader:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 260)
    rep._haraHeader:EnableMouse(false)
  end
  rep._haraHeader:ClearAllPoints()
  rep._haraHeader:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
  rep._haraHeader:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", 0, 0)
  rep._haraHeader:SetHeight(52)
  rep._haraHeader:Show()

  if not rep._haraTitle then
    rep._haraTitle = rep._haraHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  elseif rep._haraTitle.GetParent and rep._haraTitle:GetParent() ~= rep._haraHeader then
    rep._haraTitle:SetParent(rep._haraHeader)
  end
  if rep._haraTitle and rep._haraTitle.SetFont then
    rep._haraTitle:SetFont(fontPath, size + 5, outline)
    rep._haraTitle:SetTextColor(1.0, 0.88, 0.25, 1)
    rep._haraTitle:SetText("Reputation")
    rep._haraTitle:SetJustifyH("CENTER")
    rep._haraTitle:ClearAllPoints()
    rep._haraTitle:SetPoint("TOP", rep._haraHeader, "TOP", 0, -18)
    rep._haraTitle:SetDrawLayer("OVERLAY", 7)
    rep._haraTitle:SetShadowOffset(1, -1)
    rep._haraTitle:SetShadowColor(0, 0, 0, 1)
    rep._haraTitle:SetAlpha(1)
    rep._haraTitle:Show()
  end

  local repFilters = {
    rep.filterDropdown,
    rep.FilterDropdown,
    rep.filterDropDown,
    rep.FilterDropDown,
    _G.ReputationFrameFilterDropdown,
    _G.ReputationFrameFilterDropDown,
    _G.ReputationFilterDropdown,
    _G.ReputationFilterDropDown,
  }
  for _, repFilter in ipairs(repFilters) do
    if repFilter then
      if repFilter.ClearAllPoints and repFilter.SetPoint then
        repFilter:ClearAllPoints()
        repFilter:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -38, -30)
      end
      if repFilter.SetAlpha then repFilter:SetAlpha(1) end
      if repFilter.EnableMouse then repFilter:EnableMouse(true) end
      if repFilter.Show then repFilter:Show() end
    end
  end

  return true
end

local function LeaveReputationPaneMode()
  if CloseDropDownMenus then
    CloseDropDownMenus()
  end
  if _G.ReputationFrame then
    if _G.ReputationFrame._haraHeader and _G.ReputationFrame._haraHeader.Hide then
      _G.ReputationFrame._haraHeader:Hide()
    end
    if _G.ReputationFrame._haraTitle and _G.ReputationFrame._haraTitle.Hide then
      _G.ReputationFrame._haraTitle:Hide()
    end
    local repFilter = _G.ReputationFrame.filterDropdown
      or _G.ReputationFrame.FilterDropdown
      or _G.ReputationFrame.filterDropDown
      or _G.ReputationFrame.FilterDropDown
      or _G.ReputationFrameFilterDropdown
      or _G.ReputationFrameFilterDropDown
    if repFilter then
      if repFilter.SetAlpha then repFilter:SetAlpha(1) end
      if repFilter.EnableMouse then repFilter:EnableMouse(true) end
      if repFilter.Hide then repFilter:Hide() end
    end
    if _G.ReputationFrame.Hide then _G.ReputationFrame:Hide() end
  end
  if _G.PaperDollFrame and _G.PaperDollFrame.Show then _G.PaperDollFrame:Show() end
end

local function GetCurrencyPaneFrame()
  local candidates = {
    _G.TokenFrame,
    _G.CurrencyFrame,
    _G.CharacterFrameTokenFrame,
  }
  for _, frame in ipairs(candidates) do
    if frame and frame.SetPoint and frame.ClearAllPoints then
      return frame
    end
  end
  return nil
end

local function ApplyCurrencyPaneMode(db)
  local token = GetCurrencyPaneFrame()
  if not token or not CharacterFrame then return false end

  if _G.PaperDollFrame and _G.PaperDollFrame.Hide then _G.PaperDollFrame:Hide() end
  if _G.ReputationFrame and _G.ReputationFrame.Hide then _G.ReputationFrame:Hide() end
  local repFilter = _G.ReputationFrame and (_G.ReputationFrame.filterDropdown
    or _G.ReputationFrame.FilterDropdown
    or _G.ReputationFrame.filterDropDown
    or _G.ReputationFrame.FilterDropDown
    or _G.ReputationFrameFilterDropdown
    or _G.ReputationFrameFilterDropDown)
  if repFilter and repFilter.Hide then
    repFilter:Hide()
  end
  token:Show()

  local function AlignCurrencyFrame(frame)
    if not frame then return end
    if frame.ClearAllPoints and frame.SetPoint then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
      frame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -8, 44)
    end
    if frame.SetAlpha then
      frame:SetAlpha(1)
    end
    if frame.EnableMouse then
      frame:EnableMouse(true)
    end
    if frame.ScrollBox and frame.ScrollBox.ClearAllPoints and frame.ScrollBox.SetPoint then
      frame.ScrollBox:ClearAllPoints()
      frame.ScrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -34)
      frame.ScrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 26)
    end
  end

  AlignCurrencyFrame(token)
  if _G.TokenFrame and _G.TokenFrame ~= token then
    AlignCurrencyFrame(_G.TokenFrame)
  end
  if _G.CurrencyFrame and _G.CurrencyFrame ~= token and _G.CurrencyFrame ~= _G.TokenFrame then
    AlignCurrencyFrame(_G.CurrencyFrame)
  end

  local tokenSkin = EnsurePanelSkin("currency_full", token)
  if tokenSkin then
    tokenSkin:ClearAllPoints()
    tokenSkin:SetPoint("TOPLEFT", token, "TOPLEFT", 0, 0)
    tokenSkin:SetPoint("BOTTOMRIGHT", token, "BOTTOMRIGHT", 0, 0)
    tokenSkin:SetBackdropColor(0.06, 0.02, 0.10, 0.92)
    tokenSkin:SetBackdropBorderColor(0, 0, 0, 0)
    tokenSkin:Show()
    SafeFrameLevel(tokenSkin, (token:GetFrameLevel() or 1) - 1)
  end

  HideFrameTextureRegions(token)
  if token.NineSlice then HideFrameTextureRegions(token.NineSlice) end
  if token.Bg then SaveAndHideRegion(token.Bg) end

  local fontPath, size, outline = GetConfiguredFont(db)
  local title = _G.TokenFrameTitleText
  if title and title.SetFont then
    BackupFont(title)
    title:SetFont(fontPath, size + 2, outline)
    title:SetTextColor(1.0, 0.82, 0.20, 1)
  end
  if title and title.Hide then
    title:Hide()
  end

  if not token._haraHeader then
    token._haraHeader = CreateFrame("Frame", nil, CharacterFrame)
    token._haraHeader:SetFrameStrata("DIALOG")
    token._haraHeader:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 260)
    token._haraHeader:EnableMouse(false)
  end
  token._haraHeader:ClearAllPoints()
  token._haraHeader:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
  token._haraHeader:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", 0, 0)
  token._haraHeader:SetHeight(52)
  token._haraHeader:Show()

  if not token._haraTitle then
    token._haraTitle = token._haraHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  elseif token._haraTitle.GetParent and token._haraTitle:GetParent() ~= token._haraHeader then
    token._haraTitle:SetParent(token._haraHeader)
  end
  if token._haraTitle and token._haraTitle.SetFont then
    token._haraTitle:SetFont(fontPath, size + 5, outline)
    token._haraTitle:SetTextColor(1.0, 0.88, 0.25, 1)
    token._haraTitle:SetText("Currency")
    token._haraTitle:SetJustifyH("CENTER")
    token._haraTitle:ClearAllPoints()
    token._haraTitle:SetPoint("TOP", token._haraHeader, "TOP", 0, -18)
    token._haraTitle:SetDrawLayer("OVERLAY", 7)
    token._haraTitle:SetShadowOffset(1, -1)
    token._haraTitle:SetShadowColor(0, 0, 0, 1)
    token._haraTitle:SetAlpha(1)
    token._haraTitle:Show()
  end

  local tokenFilters = {
    token.filterDropdown,
    token.FilterDropdown,
    token.filterDropDown,
    token.FilterDropDown,
    _G.TokenFrameFilterDropdown,
    _G.TokenFrameFilterDropDown,
    _G.CurrencyFrameFilterDropdown,
    _G.CurrencyFrameFilterDropDown,
    _G.TokenFrameDropdown,
    _G.TokenFrameDropDown,
    _G.CurrencyFrameDropdown,
    _G.CurrencyFrameDropDown,
  }
  for _, tokenFilter in ipairs(tokenFilters) do
    if tokenFilter then
      if tokenFilter.ClearAllPoints and tokenFilter.SetPoint then
        tokenFilter:ClearAllPoints()
        tokenFilter:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -38, -30)
      end
      if tokenFilter.SetAlpha then tokenFilter:SetAlpha(1) end
      if tokenFilter.EnableMouse then tokenFilter:EnableMouse(true) end
      if tokenFilter.Show then tokenFilter:Show() end
    end
  end

  return true
end

local function LeaveCurrencyPaneMode()
  if CloseDropDownMenus then
    CloseDropDownMenus()
  end
  local frames = { GetCurrencyPaneFrame(), _G.TokenFrame, _G.CurrencyFrame }
  local seen = {}
  for _, token in ipairs(frames) do
    if token and not seen[token] then
      seen[token] = true
      if _G.TokenFramePopup and _G.TokenFramePopup.Hide then
        _G.TokenFramePopup:Hide()
      end
      if token._haraHeader and token._haraHeader.Hide then
        token._haraHeader:Hide()
      end
      if token._haraTitle and token._haraTitle.Hide then
        token._haraTitle:Hide()
      end
      local tokenFilter = token.filterDropdown
        or token.FilterDropdown
        or token.filterDropDown
        or token.FilterDropDown
        or _G.TokenFrameFilterDropdown
        or _G.TokenFrameFilterDropDown
        or _G.CurrencyFrameFilterDropdown
        or _G.CurrencyFrameFilterDropDown
      if tokenFilter then
        if tokenFilter.SetAlpha then tokenFilter:SetAlpha(1) end
        if tokenFilter.EnableMouse then tokenFilter:EnableMouse(true) end
        if tokenFilter.Hide then tokenFilter:Hide() end
      end
      if token.Hide then token:Hide() end
    end
  end
  if _G.PaperDollFrame and _G.PaperDollFrame.Show then _G.PaperDollFrame:Show() end
end

local function SyncBottomModeButtonsVisibility(db)
  if not (S.customStatsFrame and S.customStatsFrame.modeBar and CharacterFrame) then return end
  local bar = S.customStatsFrame.modeBar
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 22, -1)
  if db and db.charsheet and db.charsheet.styleStats and CharacterFrame:IsShown() then
    bar:SetFrameStrata("DIALOG")
    bar:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 200)
    bar:Show()
  else
    bar:Hide()
  end
end

local function ResolveNativeCharacterMode()
  local token = GetCurrencyPaneFrame and GetCurrencyPaneFrame() or _G.TokenFrame
  if _G.ReputationFrame and _G.ReputationFrame.IsShown and _G.ReputationFrame:IsShown() then
    return 2
  end
  if token and token.IsShown and token:IsShown() then
    return 3
  end
  if _G.PaperDollFrame and _G.PaperDollFrame.IsShown and _G.PaperDollFrame:IsShown() then
    return 1
  end
  return nil
end

local function ResolveEffectiveCharacterMode()
  if M._pendingNativeMode == 1 or M._pendingNativeMode == 2 or M._pendingNativeMode == 3 then
    return M._pendingNativeMode
  end
  local mode = S.customStatsFrame and S.customStatsFrame.activeMode or 1
  if mode == 4 or mode == 5 then
    return mode
  end
  local nativeMode = ResolveNativeCharacterMode()
  if nativeMode == 1 or nativeMode == 2 or nativeMode == 3 then
    return nativeMode
  end
  if mode == 2 or mode == 3 then
    return mode
  end
  return 1
end

M._ResolveModeFromSubFrameToken = function(subFrameToken)
  local name = subFrameToken
  if type(name) == "table" and name.GetName then
    name = name:GetName()
  end
  if type(name) ~= "string" or name == "" then
    return ResolveNativeCharacterMode()
  end
  if name == "PaperDollFrame" then
    return 1
  end
  if name == "ReputationFrame" then
    return 2
  end
  if name == "TokenFrame" or name == "CurrencyFrame" or name == "CharacterFrameTokenFrame" then
    return 3
  end
  if name:find("PaperDoll", 1, true) then
    return 1
  end
  if name:find("Reputation", 1, true) then
    return 2
  end
  if name:find("Token", 1, true) or name:find("Currency", 1, true) then
    return 3
  end
  return ResolveNativeCharacterMode()
end

M.SwitchMode = function(mode, source, opts)
  mode = tonumber(mode)
  if mode ~= 1 and mode ~= 2 and mode ~= 3 then
    return false
  end

  local applyNative = true
  if type(opts) == "table" and opts.applyNative ~= nil then
    applyNative = opts.applyNative == true
  elseif source == "native" or source == "keybind" or source == "native-deferred" or source == "mirror" then
    applyNative = false
  end

  M._pendingNativeMode = mode
  if S.customStatsFrame then
    S.customStatsFrame.activeMode = mode
  end

  if applyNative then
    ShowNativeCharacterMode(mode)
  end

  if mode == 1 then
    local liveDB = NS and NS.GetDB and NS:GetDB() or nil
    if liveDB and liveDB.charsheet then
      liveDB.charsheet.rightPanelCollapsed = false
    end
  end

  if M and M.Refresh then
    M:Refresh()
  elseif UpdateCustomStatsFrame and NS and NS.GetDB then
    UpdateCustomStatsFrame(NS:GetDB())
  end
  return true
end

M._TriggerBottomModeButton = function(mode)
  M._mirroringNativeSubframeSwitch = true
  local ok, switched = pcall(M.SwitchMode, mode, "mirror", { applyNative = false })
  M._mirroringNativeSubframeSwitch = false
  return ok == true and switched == true
end

M._RunDeferredNativeModeMirror = function()
  M._deferredNativeModeRefreshQueued = false
  if not M.active then return end
  if S.suppressSubFrameRefresh or M._mirroringNativeSubframeSwitch then return end
  local liveDB = NS and NS.GetDB and NS:GetDB() or nil
  if not (liveDB and liveDB.charsheet and liveDB.charsheet.styleStats) then
    M._deferredNativeModeMirror = nil
    return
  end
  if not (CharacterFrame and CharacterFrame:IsShown()) then
    return
  end
  local mode = M._deferredNativeModeMirror
  if mode == 0 then
    mode = nil
  end
  if not mode then
    mode = ResolveNativeCharacterMode()
  end
  M._deferredNativeModeMirror = nil
  if mode and M._TriggerBottomModeButton(mode) then
    return
  end
  M._pendingNativeMode = nil
  SyncCustomModeToNativePanel()
  M:Refresh()
end

M._QueueDeferredNativeModeMirror = function()
  if M._deferredNativeModeRefreshQueued then return end
  if C_Timer and C_Timer.After then
    M._deferredNativeModeRefreshQueued = true
    C_Timer.After(0, M._RunDeferredNativeModeMirror)
  else
    M._RunDeferredNativeModeMirror()
  end
end

ShowNativeCharacterMode = function(mode)
  if not CharacterFrame_ShowSubFrame then
    return false
  end
  local function SafeShowSubFrame(name)
    S.suppressSubFrameRefresh = true
    local ok = pcall(CharacterFrame_ShowSubFrame, name)
    S.suppressSubFrameRefresh = false
    return ok
  end
  if mode == 1 then
    SafeShowSubFrame("PaperDollFrame")
    return true
  elseif mode == 2 then
    SafeShowSubFrame("ReputationFrame")
    return true
  elseif mode == 3 then
    local token = GetCurrencyPaneFrame and GetCurrencyPaneFrame() or _G.TokenFrame or _G.CurrencyFrame
    if token and token.GetName then
      local n = token:GetName()
      if n and n ~= "" then
        SafeShowSubFrame(n)
        return true
      end
    end
    SafeShowSubFrame("TokenFrame")
    return true
  end
  return false
end

SyncCustomModeToNativePanel = function()
  local requested = ResolveNativeCharacterMode()
  if not requested then return end
  if M._pendingNativeMode and (M._pendingNativeMode == 1 or M._pendingNativeMode == 2 or M._pendingNativeMode == 3) then
    if requested ~= M._pendingNativeMode then
      return
    end
    M._pendingNativeMode = nil
  end
  local stats = EnsureCustomStatsFrame and EnsureCustomStatsFrame() or S.customStatsFrame
  if not stats then return end
  if requested == 2 or requested == 3 then
    if stats.activeMode ~= requested then
      stats.activeMode = requested
    end
  elseif requested == 1 then
    if stats.activeMode ~= 4 and stats.activeMode ~= 5 then
      stats.activeMode = 1
    end
  end
end

UpdateCustomStatsFrame = function(db)
  local frame = EnsureCustomStatsFrame()
  if not frame then return end
  if not CharacterFrame then return end
  -- Re-assert custom frame geometry so mode switches cannot snap to Blizzard default sizes.
  local needsLayout = not S.layoutApplied
  if not needsLayout and CharacterFrame.GetWidth and CharacterFrame.GetHeight then
    local cw = CharacterFrame:GetWidth() or 0
    local ch = CharacterFrame:GetHeight() or 0
    if math.abs(cw - CFG.PRIMARY_SHEET_WIDTH) > 0.5 or math.abs(ch - CFG.CUSTOM_CHAR_HEIGHT) > 0.5 then
      needsLayout = true
    end
  end
  if needsLayout then
    ApplyCustomCharacterLayout()
  end

  -- Right-anchor so it tracks frame width changes automatically after tab transitions.
  local statsWidth = math.max(140, math.floor((CFG.CUSTOM_STATS_WIDTH * 0.9) + 0.5))
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -8, -52)
  frame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -8, 52)
  frame:SetWidth(statsWidth)

  local sections = BuildCustomStatsData()
  local width = frame:GetWidth()
  if not width or width < 120 then
    width = statsWidth
  end
  local gap = CFG.STAT_SECTION_GAP
  local mode = ResolveEffectiveCharacterMode()
  frame.activeMode = mode

  if frame.modeBar then
    frame.modeBar:SetFrameStrata("DIALOG")
    frame.modeBar:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 200)
    frame.modeBar:ClearAllPoints()
    frame.modeBar:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 22, -1)
    frame.modeBar:Show()
    for i, btn in ipairs(frame.modeButtons or {}) do
      if btn and btn.icon and btn.icon.SetTexture then
        local iconTex = btn.icon:GetTexture()
        if not iconTex or iconTex == 134400 then
          local tab = _G[("PaperDollSidebarTab%d"):format(i)]
          if tab then
            local icon = tab.Icon or tab.icon or (tab.GetName and _G[tab:GetName() .. "Icon"]) or (tab.GetNormalTexture and tab:GetNormalTexture())
            if type(icon) == "string" or type(icon) == "number" then
              btn.icon:SetTexture(icon)
            elseif icon and icon.GetTexture then
              local tex = icon:GetTexture()
              if tex then btn.icon:SetTexture(tex) end
            end
          end
        end
      end
    end
  end
  if frame.sidebarBar then
    frame.sidebarBar:SetParent(CharacterFrame)
    frame.sidebarBar:SetFrameStrata("DIALOG")
    frame.sidebarBar:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 205)
    frame.sidebarBar:ClearAllPoints()
    frame.sidebarBar:SetPoint("BOTTOM", frame, "TOP", 0, 8)
    frame.sidebarBar:Show()
    for i, btn in ipairs(frame.sidebarButtons or {}) do
      if btn and btn.icon and btn.icon.SetTexture then
        local tex, l, r, t, b = GetTopSidebarIconData(i)
        btn.icon:SetTexture(tex)
        btn.icon:SetTexCoord(l, r, t, b)
      end
    end
    local selectedByMode = {
      [1] = 1,
      [4] = 2,
      [5] = 3,
    }
    local selectedSidebar = selectedByMode[mode]
    for i, btn in ipairs(frame.sidebarButtons or {}) do
      if btn and btn.SetBackdropBorderColor then
        if i == selectedSidebar then
          btn:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.98)
        else
          btn:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
        end
      end
    end
  end

  if mode == 2 then
    if S.rightPanel and S.rightPanel:IsShown() then
      S.rightPanel:Hide()
    end
    if S.customGearFrame then
      S.customGearFrame:Hide()
      if S.customGearFrame.specPanel and S.customGearFrame.specPanel.Hide then
        S.customGearFrame.specPanel:Hide()
      end
    end
    local basePanel = EnsureCustomCharacterFrame and EnsureCustomCharacterFrame() or S.customCharacterFrame
    if basePanel and basePanel.Show then
      basePanel:Show()
    end
    if S.modelFillFrame and S.modelFillFrame.Show then
      S.modelFillFrame:Show()
    end
    SetCharacterSlotButtonsVisible(false)
    if S.customNameText then S.customNameText:Hide() end
    if S.customLevelText then S.customLevelText:Hide() end
    if frame.topInfo then frame.topInfo:Hide() end
    if frame.modeList then frame.modeList:Hide() end
    for _, secFrame in ipairs(frame.sections or {}) do
      if secFrame then secFrame:Hide() end
    end
    LeaveCurrencyPaneMode()
    ApplyReputationPaneMode(db)
    if frame.modeBar then frame.modeBar:Show() end
    if frame.sidebarBar then frame.sidebarBar:Hide() end
    ApplyCustomCharacterLayout()
    frame:Hide()
    return
  elseif mode == 3 then
    if S.rightPanel and S.rightPanel:IsShown() then
      S.rightPanel:Hide()
    end
    if S.customGearFrame then
      S.customGearFrame:Hide()
      if S.customGearFrame.specPanel and S.customGearFrame.specPanel.Hide then
        S.customGearFrame.specPanel:Hide()
      end
    end
    local basePanel = EnsureCustomCharacterFrame and EnsureCustomCharacterFrame() or S.customCharacterFrame
    if basePanel and basePanel.Show then
      basePanel:Show()
    end
    if S.modelFillFrame and S.modelFillFrame.Show then
      S.modelFillFrame:Show()
    end
    SetCharacterSlotButtonsVisible(false)
    if S.customNameText then S.customNameText:Hide() end
    if S.customLevelText then S.customLevelText:Hide() end
    if frame.topInfo then frame.topInfo:Hide() end
    if frame.modeList then frame.modeList:Hide() end
    for _, secFrame in ipairs(frame.sections or {}) do
      if secFrame then secFrame:Hide() end
    end
    LeaveReputationPaneMode()
    ApplyCurrencyPaneMode(db)
    if frame.modeBar then frame.modeBar:Show() end
    if frame.sidebarBar then frame.sidebarBar:Hide() end
    -- Re-assert final custom size/anchors after all blank-mode toggles.
    ApplyCustomCharacterLayout()
    frame:Hide()
    return
  else
    SetCharacterSlotButtonsVisible(true)
    LeaveReputationPaneMode()
    LeaveCurrencyPaneMode()
    -- Re-assert final custom size/anchors when returning from native subpanes.
    ApplyCustomCharacterLayout()
  end

  local function UpdateModeListRows(modeIndex)
    if not frame.modeList then return end
    local headerText = ""
    local rows = {}
    local rowStartY = -30
    if modeIndex == 2 then
      headerText = "Reputation"
      rows = BuildReputationData()
      frame.modeList.actions:Hide()
      if #rows == 0 then
        rows = {
          { label = "No reputation data", detail = "", icon = 236681, selected = false },
        }
      end
    elseif modeIndex == 3 then
      headerText = "Currency"
      rows = BuildCurrencyData()
      frame.modeList.actions:Hide()
      if #rows == 0 then
        rows = {
          { label = "No currency data", detail = "", icon = 463446, selected = false },
        }
      end
    elseif modeIndex == 4 then
      headerText = "Titles"
      rows = BuildKnownTitlesData()
      frame.modeList.actions:Hide()
      if #rows == 0 then
        rows = {
          { label = "No titles found", detail = "", icon = 133742, selected = false },
        }
      end
    elseif modeIndex == 5 then
      headerText = "Equipment"
      rows = BuildEquipmentSetsData(frame.modeSelectedSetID)
      frame.modeList.actions:Show()
      rowStartY = -56
      if #rows == 0 then
        rows = {
          { label = "No equipment sets", detail = "", icon = 132627, selected = false },
        }
      end
    else
      frame.modeList.actions:Hide()
    end

    frame.modeList.header:SetText(headerText)
    frame.modeList.currentMode = modeIndex
    local rowsPerPage = #(frame.modeList.rows or {})
    local maxOffset = math.max(0, #rows - rowsPerPage)
    local viewOffsetByMode = frame.modeList.viewOffsetByMode or {}
    frame.modeList.viewOffsetByMode = viewOffsetByMode
    local offset = viewOffsetByMode[modeIndex] or 0
    if offset < 0 then offset = 0 end
    if offset > maxOffset then offset = maxOffset end
    viewOffsetByMode[modeIndex] = offset
    frame.modeList.maxOffset = maxOffset
    local listY = rowStartY
    for i, rowFrame in ipairs(frame.modeList.rows or {}) do
      local rowData = rows[i + offset]
      rowFrame:ClearAllPoints()
      rowFrame:SetPoint("TOPLEFT", frame.modeList, "TOPLEFT", 6, listY)
      rowFrame:SetPoint("TOPRIGHT", frame.modeList, "TOPRIGHT", -6, listY)
      if rowData then
        rowFrame._data = rowData
        rowFrame.icon:SetTexture(rowData.icon or 134400)
        rowFrame.label:SetText(rowData.label or "")
        rowFrame.detail:SetText(rowData.detail or "")
        if rowData.selected then
          rowFrame:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.95)
          rowFrame:SetBackdropColor(0.08, 0.03, 0.10, 0.75)
          rowFrame.label:SetTextColor(1, 1, 1, 1)
        else
          rowFrame:SetBackdropBorderColor(0.18, 0.12, 0.26, 0.7)
          rowFrame:SetBackdropColor(0.04, 0.02, 0.07, 0.65)
          rowFrame.label:SetTextColor(0.95, 0.95, 0.95, 1)
        end
        rowFrame:Show()
      else
        rowFrame._data = nil
        rowFrame:Hide()
      end
      listY = listY - CFG.STATS_MODE_LIST_ROW_HEIGHT - CFG.STATS_MODE_LIST_ROW_GAP
    end

    if frame.modeList.actionButtons then
      local hasSelection = frame.modeSelectedSetID ~= nil
      for _, b in ipairs(frame.modeList.actionButtons) do
        if b and b._actionKey ~= "new" then
          b:SetEnabled(modeIndex == 5 and hasSelection)
          if b.text and b.text.SetTextColor then
            if modeIndex == 5 and hasSelection then
              b.text:SetTextColor(0.95, 0.95, 0.95, 1)
            else
              b.text:SetTextColor(0.55, 0.55, 0.55, 1)
            end
          end
        elseif b and b.text and b.text.SetTextColor then
          b:SetEnabled(modeIndex == 5)
          b.text:SetTextColor(modeIndex == 5 and 0.95 or 0.55, modeIndex == 5 and 0.95 or 0.55, modeIndex == 5 and 0.95 or 0.55, 1)
        end
      end
    end
  end

  if frame.modeList and not frame.modeList._haraWheelHooked then
    frame.modeList:EnableMouseWheel(true)
    frame.modeList:SetScript("OnMouseWheel", function(list, delta)
      if not list or not list.currentMode then return end
      local modeIndex = list.currentMode
      local offsets = list.viewOffsetByMode or {}
      local cur = offsets[modeIndex] or 0
      local maxOffset = list.maxOffset or 0
      local step = 1
      if delta < 0 then
        cur = math.min(maxOffset, cur + step)
      elseif delta > 0 then
        cur = math.max(0, cur - step)
      end
      offsets[modeIndex] = cur
      list.viewOffsetByMode = offsets
      UpdateModeListRows(modeIndex)
    end)
    frame.modeList._haraWheelHooked = true
  end

  if mode == 1 and frame.topInfo then
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
    if frame.topInfo.ilvlHit then
      frame.topInfo.ilvlHit._tooltipLabel = STAT_AVERAGE_ITEM_LEVEL or ITEM_LEVEL_ABBR or "Item Level"
      frame.topInfo.ilvlHit._tooltipValue = frame.topInfo.ilvl:GetText() or ""
      frame.topInfo.ilvlHit._tooltipKey = "itemlevel"
    end

    local hp = UnitHealthMax and UnitHealthMax("player") or 0
    local hpText = BreakUpLargeNumbers and BreakUpLargeNumbers(hp) or tostring(hp or 0)
    frame.topInfo.healthRow.left:SetText(HEALTH or "Health")
    frame.topInfo.healthRow.right:SetText(hpText)
    frame.topInfo.healthRow._tooltipLabel = HEALTH or "Health"
    frame.topInfo.healthRow._tooltipValue = hpText
    frame.topInfo.healthRow._tooltipKey = "health"
    frame.topInfo.healthRow.left:SetTextColor(1, 1, 1, 1)
    frame.topInfo.healthRow.right:SetTextColor(1, 1, 1, 1)
    frame.topInfo.healthRow.bg:ClearAllPoints()
    frame.topInfo.healthRow.bg:SetPoint("TOPLEFT", frame.topInfo.healthRow, "TOPLEFT", 0, 0)
    frame.topInfo.healthRow.bg:SetPoint("BOTTOMRIGHT", frame.topInfo.healthRow, "BOTTOMLEFT", math.floor(width * CFG.STAT_TOPINFO_GRADIENT_SPLIT), -1)
    SetHorizontalGradient(frame.topInfo.healthRow.bg, 0.55, 0.04, 0.04, 0.78, 0, 0, 0, 0.08)
    if frame.topInfo.healthRow.bg.SetBlendMode then frame.topInfo.healthRow.bg:SetBlendMode("BLEND") end
    if frame.topInfo.healthRow.bg.SetAlpha then frame.topInfo.healthRow.bg:SetAlpha(1) end

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
    frame.topInfo.powerRow._tooltipLabel = powerLabel or (_G.MANA or "Power")
    frame.topInfo.powerRow._tooltipValue = powerText
    frame.topInfo.powerRow._tooltipKey = "power"
    frame.topInfo.powerRow.left:SetTextColor(1, 1, 1, 1)
    frame.topInfo.powerRow.right:SetTextColor(1, 1, 1, 1)
    frame.topInfo.powerRow.bg:ClearAllPoints()
    frame.topInfo.powerRow.bg:SetPoint("TOPLEFT", frame.topInfo.powerRow, "TOPLEFT", 0, 1)
    frame.topInfo.powerRow.bg:SetPoint("BOTTOMRIGHT", frame.topInfo.powerRow, "BOTTOMLEFT", math.floor(width * CFG.STAT_TOPINFO_GRADIENT_SPLIT), 0)
    SetHorizontalGradient(frame.topInfo.powerRow.bg, pr, pg, pb, 0.78, 0, 0, 0, 0.08)
    if frame.topInfo.powerRow.bg.SetBlendMode then frame.topInfo.powerRow.bg:SetBlendMode("BLEND") end
    if frame.topInfo.powerRow.bg.SetAlpha then frame.topInfo.powerRow.bg:SetAlpha(1) end
    frame.topInfo:Show()
  elseif frame.topInfo then
    if frame.topInfo.ilvlHit then
      frame.topInfo.ilvlHit._tooltipLabel = nil
      frame.topInfo.ilvlHit._tooltipValue = nil
      frame.topInfo.ilvlHit._tooltipKey = nil
    end
    if frame.topInfo.healthRow then
      frame.topInfo.healthRow._tooltipLabel = nil
      frame.topInfo.healthRow._tooltipValue = nil
      frame.topInfo.healthRow._tooltipKey = nil
    end
    if frame.topInfo.powerRow then
      frame.topInfo.powerRow._tooltipLabel = nil
      frame.topInfo.powerRow._tooltipValue = nil
      frame.topInfo.powerRow._tooltipKey = nil
    end
    frame.topInfo:Hide()
  end

  if mode ~= 1 and frame.modeList then
    frame.modeList:ClearAllPoints()
    frame.modeList:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.modeList:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.modeList:Show()
    UpdateModeListRows(mode)
  elseif frame.modeList then
    frame.modeList:Hide()
  end

  local y = frame.topInfo and mode == 1 and -(frame.topInfo:GetHeight() + gap + 1) or -2

  for i = 1, #frame.sections do
    local secFrame = frame.sections[i]
    if mode ~= 1 then
      secFrame:Hide()
    else
    local secData = sections[i] or { title = "", rows = {} }
    local rowCount = #secData.rows
    if rowCount < 1 then rowCount = 1 end
    local secHeight = 24 + (rowCount * CFG.STAT_ROW_HEIGHT) + ((rowCount - 1) * CFG.STAT_ROW_GAP) + CFG.STAT_SECTION_BOTTOM_PAD

    secFrame:ClearAllPoints()
    secFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
    secFrame:SetSize(width, secHeight)
    secFrame.title:SetText(secData.title or "")
    local color = CFG.SECTION_COLORS[i] or CFG.SECTION_COLORS[#CFG.SECTION_COLORS]
    if color then
      secFrame:SetBackdropBorderColor(0, 0, 0, 0)
      if secFrame.headerTint then
        secFrame.headerTint:ClearAllPoints()
        secFrame.headerTint:SetPoint("TOPRIGHT", secFrame, "TOPRIGHT", -1, -1)
        secFrame.headerTint:SetPoint("BOTTOMLEFT", secFrame, "TOPLEFT", math.floor(width * (1 - CFG.STAT_GRADIENT_SPLIT)), -23)
        SetHorizontalGradient(secFrame.headerTint, 0, 0, 0, color[4] * 0.10, color[1], color[2], color[3], color[4] * CFG.STAT_HEADER_GRADIENT_ALPHA)
        secFrame.headerTint:Show()
      end
      if secFrame.tint then
        secFrame.tint:ClearAllPoints()
        secFrame.tint:SetPoint("TOPLEFT", secFrame, "TOPLEFT", 1, -23)
        secFrame.tint:SetPoint("BOTTOMRIGHT", secFrame, "BOTTOMLEFT", math.floor(width * CFG.STAT_BODY_GRADIENT_SPLIT), 1)
        SetHorizontalGradient(secFrame.tint, color[1], color[2], color[3], color[4] * CFG.STAT_BODY_GRADIENT_ALPHA, 0, 0, 0, color[4] * 0.04)
        secFrame.tint:Show()
      end
    else
      secFrame:SetBackdropBorderColor(0, 0, 0, 0)
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
          local a = CFG.STAT_ROW_GRADIENT_ALPHA
          local topBleed = (r > 1) and math.ceil(CFG.STAT_ROW_GAP * 0.5) or 0
          local bottomBleed = (r < rowCount) and math.floor((CFG.STAT_ROW_GAP + 1) * 0.5) or 0
          rowFrame.bg:ClearAllPoints()
          rowFrame.bg:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 1, topBleed)
          rowFrame.bg:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMLEFT", math.floor(width * CFG.STAT_ROW_GRADIENT_SPLIT), -bottomBleed)
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

  ApplyCustomStatsFont(db)
  RestorePaperDollSidebarButtons()
  if frame.sidebarBar then
    local showCustomSidebar = (mode ~= 2 and mode ~= 3)
    frame.sidebarBar:SetShown(showCustomSidebar)
    SetPaperDollSidebarButtonsMouseEnabled(not showCustomSidebar)
  else
    SetPaperDollSidebarButtonsMouseEnabled(true)
  end
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

local TIER_CLASS_COLOR_FALLBACK = { 0.20, 1.00, 0.60 }
local ENCHANT_QUALITY_ATLAS = {
  [1] = { "Professions-Quality-Tier1-Small", "Professions-Quality-Tier1", "Professions-ChatIcon-Quality-Tier1" },
  [2] = { "Professions-Quality-Tier2-Small", "Professions-Quality-Tier2", "Professions-ChatIcon-Quality-Tier2" },
  [3] = { "Professions-Quality-Tier3-Small", "Professions-Quality-Tier3", "Professions-ChatIcon-Quality-Tier3" },
}
local UPGRADE_TRACK_COLORS = {
  ["explorer"] = { 0.62, 0.62, 0.62 },   -- gray
  ["adventurer"] = { 0.12, 1.00, 0.12 }, -- green
  ["veteran"] = { 0.00, 0.44, 0.87 },    -- blue
  ["champion"] = { 0.64, 0.21, 0.93 },   -- purple
  ["hero"] = { 1.00, 0.50, 0.00 },       -- HaraUI orange
  ["myth"] = { 0.90, 0.12, 0.12 },       -- red
  ["mythic"] = { 0.90, 0.12, 0.12 },     -- red
}

local function Trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function StripColorAndTextureCodes(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  s = s:gsub("|A.-|a", "")
  s = s:gsub("|T.-|t", "")
  return Trim(s)
end

local function GetTooltipInfoLinesForInventorySlot(invID)
  if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem and invID) then
    return {}
  end
  local link = GetInventoryItemLink and GetInventoryItemLink("player", invID) or nil
  local cached = S.inventoryTooltipCache[invID]
  if cached and cached.link == link and type(cached.lines) == "table" then
    return cached.lines
  end
  local ok, info = pcall(C_TooltipInfo.GetInventoryItem, "player", invID)
  if not ok or type(info) ~= "table" or type(info.lines) ~= "table" then
    S.inventoryTooltipCache[invID] = { link = link, lines = {} }
    return {}
  end

  S.inventoryTooltipCache[invID] = { link = link, lines = info.lines }
  return info.lines
end

local function GetEnchantTextFromTooltip(invID)
  local lines = GetTooltipInfoLinesForInventorySlot(invID)
  if type(lines) ~= "table" or #lines == 0 then
    return ""
  end

  local localizedPattern = nil
  local template = _G and _G.ENCHANTED_TOOLTIP_LINE or nil
  if type(template) == "string" and template ~= "" then
    localizedPattern = "^" .. template
      :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      :gsub("%%%%s", "(.+)")
      .. "$"
  end

  for _, line in ipairs(lines) do
    if type(line) == "table" then
      local clean = StripColorAndTextureCodes(line.leftText)
      if clean ~= "" then
        local enchantName = nil
        if localizedPattern then
          enchantName = clean:match(localizedPattern)
        end
        if not enchantName then
          enchantName = clean:match("^Enchanted:%s*(.+)$")
        end
        if enchantName and enchantName ~= "" then
          return Trim(enchantName)
        end
      end
    end
  end

  return ""
end

local function GetUpgradeTrackText(invID)
  local lines = GetTooltipInfoLinesForInventorySlot(invID)
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      local candidates = { line.leftText, line.rightText }
      for _, raw in ipairs(candidates) do
        if type(raw) == "string" and raw ~= "" then
          local clean = StripColorAndTextureCodes(raw)
          if clean:find("%d+/%d+") then
            local inParens = clean:match("%(([^)]*%d+/%d+[^)]*)%)")
            if inParens and inParens ~= "" then
              return Trim(inParens)
            end
            local bare = clean:match("([%a][%a%s%-']-%d+/%d+)")
            if bare and bare ~= "" then
              return Trim(bare)
            end
          end
        end
      end
    end
  end
  return ""
end

local function GetEnchantQualityTier(invID)
  local function ParseTierToken(s)
    if type(s) ~= "string" then return nil end
    local tier = tonumber(s:match("Professions[^|]-Tier(%d)"))
      or tonumber(s:match("[Qq]uality%-Tier(%d)"))
      or tonumber(s:match("Tier(%d)"))
    if tier and tier >= 1 and tier <= 3 then
      return tier
    end
    return nil
  end

  local function ScanForTier(value, depth)
    depth = depth or 0
    if depth > 5 or value == nil then return nil end
    if type(value) == "string" then
      return ParseTierToken(value)
    end
    if type(value) == "table" then
      for _, v in pairs(value) do
        local tier = ScanForTier(v, depth + 1)
        if tier then return tier end
      end
    end
    return nil
  end

  local lines = GetTooltipInfoLinesForInventorySlot(invID)
  for _, line in ipairs(lines) do
    local tier = ScanForTier(line, 0)
    if tier then return tier end
  end
  return nil
end

local function GetEnchantQualityAtlasFromTooltip(invID)
  local function Scan(value, depth)
    depth = depth or 0
    if depth > 6 or value == nil then return nil end
    if type(value) == "string" then
      -- Inline texture markup: |A:Atlas-Name:...
      local atlas = value:match("|A:([^:|]+):")
      if atlas and (atlas:lower():find("quality", 1, true) or atlas:lower():find("tier", 1, true)) then
        return atlas
      end
      -- Bare atlas token in text payload.
      atlas = value:match("(Professions[%w%-_]*Quality[%w%-_]*)")
        or value:match("(Professions[%w%-_]*Tier[%w%-_]*)")
      if atlas then
        return atlas
      end
      return nil
    end
    if type(value) == "table" then
      for _, v in pairs(value) do
        local atlas = Scan(v, depth + 1)
        if atlas then return atlas end
      end
    end
    return nil
  end

  local lines = GetTooltipInfoLinesForInventorySlot(invID)
  for _, line in ipairs(lines) do
    local atlas = Scan(line, 0)
    if atlas then
      return atlas
    end
  end
  return nil
end

local function ResolveEnchantQualityAtlas(tier)
  local candidates = ENCHANT_QUALITY_ATLAS[tier]
  if type(candidates) ~= "table" then return nil end
  for _, atlas in ipairs(candidates) do
    if atlas and atlas ~= "" then
      if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if ok and info then
          return atlas
        end
      else
        return atlas
      end
    end
  end
  return candidates[1]
end

local function GetEnchantQualityAtlasMarkup(invID, enchantText, tierHint)
  if type(enchantText) ~= "string" or enchantText == "" then
    return ""
  end
  local tier = tierHint or GetEnchantQualityTier(invID) or 1
  if tier < 1 then tier = 1 end
  if tier > 3 then tier = 3 end

  local atlas = GetEnchantQualityAtlasFromTooltip(invID) or ResolveEnchantQualityAtlas(tier)
  if not atlas or atlas == "" then
    atlas = ("Professions-ChatIcon-Quality-Tier%d"):format(tier)
  end
  return (" |A:%s:%d:%d:0:0|a"):format(atlas, CFG.ENCHANT_QUALITY_MARKUP_SIZE, CFG.ENCHANT_QUALITY_MARKUP_SIZE)
end

local function HasSetBonusTooltipMarker(invID)
  local lines = GetTooltipInfoLinesForInventorySlot(invID)
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      local candidates = { line.leftText, line.rightText }
      for _, raw in ipairs(candidates) do
        if type(raw) == "string" and raw ~= "" then
          local clean = StripColorAndTextureCodes(raw)
          if clean:find("%(%d+/%d+%)") then
            local lower = clean:lower()
            if not lower:find("adventurer", 1, true)
              and not lower:find("veteran", 1, true)
              and not lower:find("champion", 1, true)
              and not lower:find("hero", 1, true)
              and not lower:find("myth", 1, true)
              and not lower:find("explorer", 1, true)
            then
              return true
            end
          end
        end
      end
    end
  end
  return false
end

local function GetUpgradeTrackColor(trackText)
  if type(trackText) ~= "string" or trackText == "" then
    return 0.98, 0.90, 0.35
  end
  local lower = trackText:lower()
  for key, color in pairs(UPGRADE_TRACK_COLORS) do
    if lower:find(key, 1, true) then
      return color[1], color[2], color[3]
    end
  end
  return 0.98, 0.90, 0.35
end

local function RGBToHex(r, g, b)
  local function Clamp255(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    return math.floor((v * 255) + 0.5)
  end
  return ("%02x%02x%02x"):format(Clamp255(r), Clamp255(g), Clamp255(b))
end

local function IsTierSetItem(itemLink, invID)
  if type(itemLink) ~= "string" or type(GetItemInfoInstant) ~= "function" then
    return invID and HasSetBonusTooltipMarker(invID) or false
  end
  local _, _, _, equipLoc, _, _, _, _, _, setID = GetItemInfoInstant(itemLink)
  if not setID or setID <= 0 then
    return invID and HasSetBonusTooltipMarker(invID) or false
  end
  -- Limit the override to typical tier slots.
  return equipLoc == "INVTYPE_HEAD"
    or equipLoc == "INVTYPE_SHOULDER"
    or equipLoc == "INVTYPE_CHEST"
    or equipLoc == "INVTYPE_ROBE"
    or equipLoc == "INVTYPE_HAND"
    or equipLoc == "INVTYPE_LEGS"
end

local function GetPlayerClassColor()
  local _, classTag = UnitClass("player")
  if classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag] then
    local c = RAID_CLASS_COLORS[classTag]
    return c.r or 1, c.g or 1, c.b or 1
  end
  if C_ClassColor and C_ClassColor.GetClassColor and classTag then
    local c = C_ClassColor.GetClassColor(classTag)
    if c then
      return c:GetRGB()
    end
  end
  return TIER_CLASS_COLOR_FALLBACK[1], TIER_CLASS_COLOR_FALLBACK[2], TIER_CLASS_COLOR_FALLBACK[3]
end

local function EnsureCustomGearFrame()
  if S.customGearFrame then return S.customGearFrame end
  if not CharacterFrame then return nil end

  S.customGearFrame = CreateFrame("Frame", nil, CharacterFrame)
  S.customGearFrame:SetFrameStrata("HIGH")
  S.customGearFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 15)
  S.customGearFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
  S.customGearFrame:SetSize(CFG.PRIMARY_SHEET_WIDTH - 16, CFG.CUSTOM_CHAR_HEIGHT - 102)
  S.customGearFrame:SetClipsChildren(true)
  S.customGearFrame:Hide()

  S.customGearFrame.topLeft = S.customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  S.customGearFrame.topLeft:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 40, -40)
  S.customGearFrame.topLeft:SetText("Mythic+ Rating:")
  S.customGearFrame.topLeftValue = S.customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  S.customGearFrame.topLeftValue:SetPoint("TOPLEFT", S.customGearFrame.topLeft, "BOTTOMLEFT", 0, -2)
  S.customGearFrame.topLeftValue:SetTextColor(1, 0.5, 0.1, 1)

  S.customGearFrame.topCenter = S.customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  S.customGearFrame.topCenter:SetPoint("TOP", CharacterFrame, "TOP", 0, -30)
  S.customGearFrame.topCenter:SetTextColor(1, 1, 1, 1)
  S.customGearFrame.topCenter:SetShadowOffset(1, -1)
  S.customGearFrame.topCenter:SetShadowColor(0, 0, 0, 1)
  S.customGearFrame.topSub = S.customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  S.customGearFrame.topSub:SetPoint("TOP", S.customGearFrame.topCenter, "BOTTOM", 0, -2)
  S.customGearFrame.topSub:SetTextColor(1, 1, 1, 1)

  S.customGearFrame.topRight = S.customGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  S.customGearFrame.topRight:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -44, -38)
  S.customGearFrame.topRight:SetJustifyH("RIGHT")
  S.customGearFrame.topRight:SetTextColor(0.75, 0.75, 1, 1)

  S.customGearFrame.leftRows = {}
  S.customGearFrame.rightRows = {}
  for i = 1, #CFG.LEFT_GEAR_SLOTS do
    local row = CreateFrame("Frame", nil, S.customGearFrame)
    row:SetSize(CFG.GEAR_ROW_WIDTH, CFG.GEAR_ROW_HEIGHT)
    row:SetClipsChildren(false)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture("Interface/Buttons/WHITE8x8")
    row.bg:SetDrawLayer("ARTWORK", 0)
    row.bg:SetAllPoints(true)
    row.bg:SetColorTexture(0.14, 0.02, 0.20, 0.32)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(CFG.GEAR_ROW_WIDTH - 16)
    row.name:SetMaxLines(1)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.name:SetTextColor(0.92, 0.46, 1.0, 1)
    row.track = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.track:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.track:SetJustifyH("LEFT")
    row.track:SetWidth(CFG.GEAR_ROW_WIDTH - 16)
    row.track:SetMaxLines(1)
    if row.track.SetWordWrap then row.track:SetWordWrap(false) end
    row.track:SetTextColor(0.98, 0.90, 0.35, 1)
    row.enchant = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.enchant:SetPoint("TOPLEFT", row.track, "BOTTOMLEFT", 0, -4)
    row.enchant:SetJustifyH("LEFT")
    row.enchant:SetWidth(CFG.GEAR_ROW_WIDTH - 30)
    row.enchant:SetMaxLines(1)
    if row.enchant.SetWordWrap then row.enchant:SetWordWrap(false) end
    row.enchant:SetTextColor(0.1, 1, 0.75, 1)
    row.enchantQualityIcon = row:CreateTexture(nil, "OVERLAY")
    row.enchantQualityIcon:SetDrawLayer("OVERLAY", 7)
    row.enchantQualityIcon:SetSize(24, 24)
    row.enchantQualityIcon:SetPoint("LEFT", row.enchant, "RIGHT", 2, 0)
    row.enchantQualityIcon:Hide()
    S.customGearFrame.leftRows[i] = row
  end
  for i = 1, #CFG.RIGHT_GEAR_SLOTS do
    local row = CreateFrame("Frame", nil, S.customGearFrame)
    row:SetSize(CFG.GEAR_ROW_WIDTH, CFG.GEAR_ROW_HEIGHT)
    row:SetClipsChildren(false)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture("Interface/Buttons/WHITE8x8")
    row.bg:SetDrawLayer("ARTWORK", 0)
    row.bg:SetAllPoints(true)
    row.bg:SetColorTexture(0.14, 0.02, 0.20, 0.32)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -4)
    row.name:SetJustifyH("RIGHT")
    row.name:SetWidth(CFG.GEAR_ROW_WIDTH - 16)
    row.name:SetMaxLines(1)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.name:SetTextColor(0.92, 0.46, 1.0, 1)
    row.track = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.track:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -4)
    row.track:SetJustifyH("RIGHT")
    row.track:SetWidth(CFG.GEAR_ROW_WIDTH - 16)
    row.track:SetMaxLines(1)
    if row.track.SetWordWrap then row.track:SetWordWrap(false) end
    row.track:SetTextColor(0.98, 0.90, 0.35, 1)
    row.enchant = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.enchant:SetPoint("TOPRIGHT", row.track, "BOTTOMRIGHT", 0, -4)
    row.enchant:SetJustifyH("RIGHT")
    row.enchant:SetWidth(CFG.GEAR_ROW_WIDTH - 30)
    row.enchant:SetMaxLines(1)
    if row.enchant.SetWordWrap then row.enchant:SetWordWrap(false) end
    row.enchant:SetTextColor(0.1, 1, 0.75, 1)
    row.enchantQualityIcon = row:CreateTexture(nil, "OVERLAY")
    row.enchantQualityIcon:SetDrawLayer("OVERLAY", 7)
    row.enchantQualityIcon:SetSize(24, 24)
    row.enchantQualityIcon:SetPoint("RIGHT", row.enchant, "LEFT", -2, 0)
    row.enchantQualityIcon:Hide()
    S.customGearFrame.rightRows[i] = row
  end

  S.customGearFrame.specPanel = CreateFrame("Frame", nil, CharacterFrame)
  S.customGearFrame.specPanel:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 36, -1)
  S.customGearFrame.specPanel:SetSize(376, 46)
  S.customGearFrame.specPanel:EnableMouse(true)

  S.customGearFrame.specPanel.title = S.customGearFrame.specPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.customGearFrame.specPanel.title:SetPoint("BOTTOM", S.customGearFrame.specButtonRow or S.customGearFrame.specPanel, "TOP", 0, 4)
  S.customGearFrame.specPanel.title:SetJustifyH("CENTER")
  S.customGearFrame.specPanel.title:SetText("Specialization")

  S.customGearFrame.specButtons = {}
  S.customGearFrame.specButtonRow = CreateFrame("Frame", nil, S.customGearFrame.specPanel)
  S.customGearFrame.specButtonRow:SetPoint("BOTTOMLEFT", S.customGearFrame.specPanel, "BOTTOMLEFT", 0, 9)
  S.customGearFrame.specButtonRow:SetSize(156, 28)
  S.customGearFrame.specPanel.title:ClearAllPoints()
  S.customGearFrame.specPanel.title:SetPoint("BOTTOM", S.customGearFrame.specButtonRow, "TOP", 0, 4)

  for i = 1, 4 do
    local btn = CreateFrame("Button", nil, S.customGearFrame.specButtonRow, "BackdropTemplate")
    btn:SetSize(28, 28)
    btn:SetPoint("LEFT", S.customGearFrame.specButtonRow, "LEFT", (i - 1) * 34, 0)
    btn:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.02, 0.02, 0.03, 0.95)
    btn:SetBackdropBorderColor(0.14, 0.14, 0.14, 0.95)
    btn.specIndex = i

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetTexture(134400)

    btn.glow = btn:CreateTexture(nil, "OVERLAY")
    btn.glow:SetPoint("TOPLEFT", -2, 2)
    btn.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    btn.glow:SetTexture("Interface/Buttons/WHITE8x8")
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetVertexColor(1.0, 0.70, 0.12, 0.30)
    btn.glow:Hide()

    btn:SetScript("OnClick", function(self)
      if InCombatLockdown and InCombatLockdown() then return end
      local idx = self.specIndex
      if not idx then return end
      if GetSpecialization and GetSpecialization() == idx then return end
      if SetSpecialization then
        pcall(SetSpecialization, idx)
      elseif C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
        pcall(C_SpecializationInfo.SetSpecialization, idx)
      end
    end)
    S.customGearFrame.specButtons[i] = btn
  end

  S.customGearFrame.lootTitle = S.customGearFrame.specPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.customGearFrame.lootTitle:SetPoint("BOTTOM", S.customGearFrame.specPanel, "BOTTOMLEFT", 210 + (170 * 0.5), 41)
  S.customGearFrame.lootTitle:SetJustifyH("CENTER")
  S.customGearFrame.lootTitle:SetText("Loot Specialization")

  S.customGearFrame.lootSpecButtonRow = CreateFrame("Frame", nil, S.customGearFrame.specPanel)
  S.customGearFrame.lootSpecButtonRow:SetPoint("BOTTOMLEFT", S.customGearFrame.specPanel, "BOTTOMLEFT", 210, 9)
  S.customGearFrame.lootSpecButtonRow:SetSize(170, 28)
  S.customGearFrame.lootTitle:ClearAllPoints()
  S.customGearFrame.lootTitle:SetPoint("BOTTOM", S.customGearFrame.lootSpecButtonRow, "TOP", -1, 4)
  S.customGearFrame.lootSpecButtons = {}
  S.lootSpecButtons = S.customGearFrame.lootSpecButtons

  for i = 1, 5 do
    local btn = CreateFrame("Button", nil, S.customGearFrame.lootSpecButtonRow, "BackdropTemplate")
    btn:SetSize(28, 28)
    btn:SetPoint("LEFT", S.customGearFrame.lootSpecButtonRow, "LEFT", (i - 1) * 34, 0)
    btn:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.02, 0.02, 0.03, 0.95)
    btn:SetBackdropBorderColor(0.14, 0.14, 0.14, 0.95)
    btn.lootIndex = i

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetTexture(134400)

    btn.glow = btn:CreateTexture(nil, "OVERLAY")
    btn.glow:SetPoint("TOPLEFT", -2, 2)
    btn.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    btn.glow:SetTexture("Interface/Buttons/WHITE8x8")
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetVertexColor(1.0, 0.70, 0.12, 0.30)
    btn.glow:Hide()

    btn:SetScript("OnClick", function(self)
      if InCombatLockdown and InCombatLockdown() then return end
      if not SetLootSpecialization then return end
      local index = self.lootIndex or 1
      local targetLootSpecID
      if index == 1 then
        targetLootSpecID = 0
      else
        local specID = self.specID
        if type(specID) ~= "number" then return end
        targetLootSpecID = specID
      end

      local ok = pcall(SetLootSpecialization, targetLootSpecID)
      if ok then
        S.pendingLootSpecID = targetLootSpecID
      end
      if M and M.Refresh then
        M:Refresh()
      elseif UpdateCustomGearFrame and NS and NS.GetDB then
        UpdateCustomGearFrame(NS:GetDB())
      end
    end)
    S.customGearFrame.lootSpecButtons[i] = btn
  end

  return S.customGearFrame
end

local function UpdateSpecializationButtons(db)
  if not S.customGearFrame or not S.customGearFrame.specPanel or not S.customGearFrame.specButtons or not S.customGearFrame.specButtonRow then
    return
  end

  local panel = S.customGearFrame.specPanel
  local row = S.customGearFrame.specButtonRow
  local buttons = S.customGearFrame.specButtons
  local lootRow = S.customGearFrame.lootSpecButtonRow
  local lootButtons = S.customGearFrame.lootSpecButtons
  if panel.Show then panel:Show() end
  if row.Show then row:Show() end
  if lootRow and lootRow.Show then lootRow:Show() end
  local current = GetSpecialization and GetSpecialization() or nil
  local actualLootSpecID = GetLootSpecialization and GetLootSpecialization() or 0
  local lootSpecID = actualLootSpecID
  if type(S.pendingLootSpecID) == "number" then
    lootSpecID = S.pendingLootSpecID
    if actualLootSpecID == S.pendingLootSpecID then
      S.pendingLootSpecID = nil
    end
  end
  local count = GetNumSpecializations and GetNumSpecializations(false, false) or 0
  if not count or count < 1 then
    count = GetNumSpecializations and GetNumSpecializations() or 0
  end
  if count < 1 then count = 1 end
  if count > #buttons then count = #buttons end

  local usedWidth = (count * 28) + ((count - 1) * 6)
  local lootUsedWidth = ((count + 1) * 28) + (count * 6)
  row:SetWidth(usedWidth)
  row:ClearAllPoints()
  row:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 9)
  if lootRow then
    lootRow:SetWidth(lootUsedWidth)
    lootRow:ClearAllPoints()
    lootRow:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 210, 9)
  end

  for i, btn in ipairs(buttons) do
    if i <= count then
      local specID, _, _, icon = GetSpecializationInfo(i)
      btn.specID = specID
      if btn.icon then
        btn.icon:SetTexture(icon or 134400)
      end
      btn:ClearAllPoints()
      btn:SetPoint("LEFT", row, "LEFT", (i - 1) * 34, 0)
      btn:Show()

      local isActive = (current == i)
      if isActive then
        btn:SetBackdropBorderColor(1.00, 0.70, 0.12, 1.00)
        if btn.glow then btn.glow:Show() end
      else
        btn:SetBackdropBorderColor(0.14, 0.14, 0.14, 0.95)
        if btn.glow then btn.glow:Hide() end
      end
    else
      btn:Hide()
    end
  end

  if lootButtons then
    for i, btn in ipairs(lootButtons) do
      if i <= (count + 1) then
        local specIndex = i - 1
        local specID, _, _, icon
        if specIndex == 0 then
          specID = 0
          if current and GetSpecializationInfo then
            icon = select(4, GetSpecializationInfo(current))
          end
          btn.specID = 0
        else
          specID, _, _, icon = GetSpecializationInfo(specIndex)
          btn.specID = specID
        end
        if btn.icon then
          btn.icon:SetTexture(icon or 134400)
        end
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", lootRow, "LEFT", (i - 1) * 34, 0)
        btn:Show()

        local isActive
        if specIndex == 0 then
          isActive = (lootSpecID == 0)
        else
          isActive = (lootSpecID == specID)
        end
        if isActive then
          btn:SetBackdropBorderColor(1.00, 0.70, 0.12, 1.00)
          if btn.glow then btn.glow:Show() end
        else
          btn:SetBackdropBorderColor(0.14, 0.14, 0.14, 0.95)
          if btn.glow then btn.glow:Hide() end
        end
      else
        btn:Hide()
      end
    end
  end

  local fontPath, size, outline = GetConfiguredFont(db)
  if panel.title and panel.title.SetFont then
    panel.title:SetFont(fontPath, math.max(10, size), outline)
  end
  if panel.title and panel.title.Show then
    panel.title:Show()
  end
  if S.customGearFrame.lootTitle and S.customGearFrame.lootTitle.SetFont then
    S.customGearFrame.lootTitle:SetFont(fontPath, math.max(10, size), outline)
  end
  if S.customGearFrame.lootTitle and S.customGearFrame.lootTitle.Show then
    S.customGearFrame.lootTitle:Show()
  end
end

local function UpdateGearRows(rows, slots, rightAlign)
  local anchorFrame = _G.PaperDollFrame or S.customGearFrame
  local classR, classG, classB = GetPlayerClassColor()
  for i, slotName in ipairs(slots) do
    local row = rows[i]
    local btn = _G["Character" .. slotName]
    if row and btn then
      row:ClearAllPoints()
      row:SetWidth(CFG.GEAR_ROW_WIDTH)
      if rightAlign then
        row:SetPoint("RIGHT", btn, "LEFT", -CFG.GEAR_TEXT_GAP, 0)
      else
        row:SetPoint("LEFT", btn, "RIGHT", CFG.GEAR_TEXT_GAP, 0)
      end
      local invID = GetInventorySlotInfo(slotName)
      local link = invID and GetInventoryItemLink("player", invID) or nil
      if link then
        local name, _, quality = GetItemInfo(link)
        local ilvl = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link) or nil
        local enchant = ParseEnchantName(link)
        if enchant == "" then
          enchant = GetEnchantTextFromTooltip(invID)
        end
        local upgradeTrack = GetUpgradeTrackText(invID)
        local enchantQualityTier = GetEnchantQualityTier(invID)
        local r, g, b = 0.92, 0.46, 1.0
        if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
          r = ITEM_QUALITY_COLORS[quality].r
          g = ITEM_QUALITY_COLORS[quality].g
          b = ITEM_QUALITY_COLORS[quality].b
        end
        local isTier = IsTierSetItem(link, invID)
        if isTier then
          r, g, b = classR, classG, classB
        end
        row.name:SetText(name or slotName)
        row.name:SetTextColor(r, g, b, 1)

        local skin = EnsureSlotSkin(btn)
        if skin and skin.SetBackdropBorderColor then
          if isTier then
            skin:SetBackdropBorderColor(classR, classG, classB, 0.98)
          elseif quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local qc = ITEM_QUALITY_COLORS[quality]
            skin:SetBackdropBorderColor(qc.r or 0.35, qc.g or 0.18, qc.b or 0.55, 0.95)
          else
            skin:SetBackdropBorderColor(0.35, 0.18, 0.55, 0.95)
          end
        end
        if skin and skin.SetBackdropColor then
          skin:SetBackdropColor(0.04, 0.02, 0.06, 0.92)
        end
        local iconBorder = btn.IconBorder or _G[btn:GetName() .. "IconBorder"]
        if iconBorder then
          if iconBorder.SetAlpha then iconBorder:SetAlpha(0) end
          if iconBorder.Hide then iconBorder:Hide() end
        end

        local ilvlText = ilvl and tostring(math.floor(ilvl + 0.5)) or ""
        local trackText = ""
        if upgradeTrack ~= "" then
          trackText = ("(%s)"):format(upgradeTrack)
        end
        local tr, tg, tb = GetUpgradeTrackColor(upgradeTrack)
        local ilvlPart = ilvlText ~= "" and ("|cffffffff%s|r"):format(ilvlText) or ""
        local trackPart = trackText ~= "" and ("|cff%s%s|r"):format(RGBToHex(tr, tg, tb), trackText) or ""
        local meta = ""
        if rightAlign then
          if trackPart ~= "" then
            meta = trackPart
          end
          if ilvlPart ~= "" then
            if meta ~= "" then
              meta = meta .. " "
            end
            meta = meta .. ilvlPart
          end
        else
          if ilvlPart ~= "" then
            meta = ilvlPart
          end
          if trackPart ~= "" then
            if meta ~= "" then
              meta = meta .. " "
            end
            meta = meta .. trackPart
          end
        end
        row.track:SetText(meta)
        row.track:SetTextColor(1, 1, 1, 1)

        local enchantText = enchant or ""
        local hasEnchant = Trim(enchantText) ~= ""
        local canHaveEnchant = false
        if slotName == "NeckSlot"
          or slotName == "BackSlot"
          or slotName == "ChestSlot"
          or slotName == "WristSlot"
          or slotName == "FeetSlot"
          or slotName == "Finger0Slot"
          or slotName == "Finger1Slot"
        then
          canHaveEnchant = true
        elseif slotName == "MainHandSlot" or slotName == "SecondaryHandSlot" then
          local _, _, _, equipLoc = GetItemInfoInstant(link)
          if slotName == "MainHandSlot" then
            canHaveEnchant = (equipLoc == "INVTYPE_WEAPON")
              or (equipLoc == "INVTYPE_2HWEAPON")
              or (equipLoc == "INVTYPE_WEAPONMAINHAND")
          else
            canHaveEnchant = (equipLoc == "INVTYPE_WEAPON")
              or (equipLoc == "INVTYPE_WEAPONOFFHAND")
              or (equipLoc == "INVTYPE_SHIELD")
          end
        end

        local enchantMarkup = hasEnchant and GetEnchantQualityAtlasMarkup(invID, enchantText, enchantQualityTier) or ""
        if hasEnchant then
          row.enchant:SetText(enchantText .. enchantMarkup)
        elseif canHaveEnchant then
          row.enchant:SetText("|cffff3a3a<enchant missing>|r")
        else
          row.enchant:SetText("")
        end
        if row.enchantQualityIcon then
          row.enchantQualityIcon:Hide()
        end

        if row.bg then
          local grad = CFG.RARITY_GRADIENT[quality or 1]
          local c1r, c1g, c1b, c1a
          if isTier then
            c1r, c1g, c1b, c1a = classR, classG, classB, 0.92
          else
            c1r, c1g, c1b, c1a = grad[5], grad[6], grad[7], 0.92
          end
          local split = math.floor((row:GetWidth() > 0 and row:GetWidth() or CFG.GEAR_ROW_WIDTH) * 0.96)
          local iconSpan = CFG.SLOT_ICON_SIZE + CFG.GEAR_TEXT_GAP + 2
          row.bg:ClearAllPoints()
          row.bg:SetColorTexture(c1r, c1g, c1b, 0.30)
          -- Keep bars slightly taller than icon while preserving overall slot cadence.
          local iconPad = math.max(2, math.floor((row:GetHeight() - CFG.SLOT_ICON_SIZE) * 0.35))
          if rightAlign then
            row.bg:SetPoint("TOPLEFT", row, "TOPRIGHT", -split, iconPad)
            row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", iconSpan, -iconPad)
            SetHorizontalGradient(row.bg, c1r, c1g, c1b, 0.00, c1r, c1g, c1b, 0.92)
          else
            row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", -iconSpan, iconPad)
            row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", split, -iconPad)
            SetHorizontalGradient(row.bg, c1r, c1g, c1b, 0.92, c1r, c1g, c1b, 0.00)
          end
          if row.bg.SetBlendMode then row.bg:SetBlendMode("BLEND") end
          if row.bg.SetAlpha then row.bg:SetAlpha(1) end
          row.bg:Show()
        end
        row:Show()
      else
        row.name:SetText("")
        row.track:SetText("")
        row.enchant:SetText("")
        if row.enchantQualityIcon then
          row.enchantQualityIcon:Hide()
        end
        row:Hide()
      end
    end
  end
end

UpdateCustomGearFrame = function(db)
  if S.customStatsFrame and (S.customStatsFrame.activeMode == 2 or S.customStatsFrame.activeMode == 3) then
    if S.customGearFrame then S.customGearFrame:Hide() end
    return
  end
  local frame = EnsureCustomGearFrame()
  if not frame then return end
  local w = CharacterFrame and CharacterFrame.GetWidth and CharacterFrame:GetWidth() or CFG.PRIMARY_SHEET_WIDTH
  frame:SetSize((tonumber(w) or CFG.PRIMARY_SHEET_WIDTH) - 16, CFG.CUSTOM_CHAR_HEIGHT - 102)
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

  frame.topLeft:SetText("")
  frame.topLeftValue:SetText("")
  frame.topCenter:SetText("")
  frame.topSub:SetText("")

  frame.topRight:SetText("")

  UpdateGearRows(frame.leftRows, CFG.LEFT_GEAR_SLOTS, false)
  UpdateGearRows(frame.rightRows, CFG.RIGHT_GEAR_SLOTS, true)
  UpdateSpecializationButtons(db)

  local fontPath, size, outline = GetConfiguredFont(db)
  if frame.topLeft and frame.topLeft.SetFont then frame.topLeft:SetFont(fontPath, size + 1, outline) end
  if frame.topLeftValue and frame.topLeftValue.SetFont then frame.topLeftValue:SetFont(fontPath, size + 5, outline) end
  if frame.topCenter and frame.topCenter.SetFont then frame.topCenter:SetFont(fontPath, size + 2, outline) end
  if frame.topSub and frame.topSub.SetFont then frame.topSub:SetFont(fontPath, size + 1, outline) end
  if frame.topRight and frame.topRight.SetFont then frame.topRight:SetFont(fontPath, size + 1, outline) end
  for _, row in ipairs(frame.leftRows or {}) do
    if row.name and row.name.SetFont then row.name:SetFont(fontPath, math.max(10, size), outline) end
    if row.track and row.track.SetFont then row.track:SetFont(fontPath, math.max(9, size - 1), outline) end
    if row.enchant and row.enchant.SetFont then row.enchant:SetFont(fontPath, math.max(9, size - 1), outline) end
  end
  for _, row in ipairs(frame.rightRows or {}) do
    if row.name and row.name.SetFont then row.name:SetFont(fontPath, math.max(10, size), outline) end
    if row.track and row.track.SetFont then row.track:SetFont(fontPath, math.max(9, size - 1), outline) end
    if row.enchant and row.enchant.SetFont then row.enchant:SetFont(fontPath, math.max(9, size - 1), outline) end
  end

  frame:Show()
end

ApplyCustomCharacterLayout = function()
  if not CharacterFrame then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if not S.layoutApplied then
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

  -- Preserve left edge so width growth extends to the right.
  local leftAbs = CharacterFrame.GetLeft and CharacterFrame:GetLeft() or nil
  local topAbs = CharacterFrame.GetTop and CharacterFrame:GetTop() or nil
  CharacterFrame:SetSize(CFG.PRIMARY_SHEET_WIDTH, CFG.CUSTOM_CHAR_HEIGHT)
  if leftAbs and topAbs and UIParent then
    CharacterFrame:ClearAllPoints()
    CharacterFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftAbs, topAbs)
  end

  local inset = _G.CharacterFrameInset
  if inset then
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
    inset:SetSize(CFG.PRIMARY_SHEET_WIDTH - 16, CFG.CUSTOM_CHAR_HEIGHT - 102)
  end

  local insetLeft = _G.CharacterFrameInsetLeft
  -- Keep left/model region at established width; push all new width into right panel.
  local leftWidth = CFG.BASE_PRIMARY_SHEET_WIDTH - CFG.BASE_STATS_WIDTH - CFG.CUSTOM_PANE_GAP - 36
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
    if closeBtn.SetSize then
      closeBtn:SetSize(22, 22)
    end
    local function ClearButtonTexture(tex)
      if not tex then return end
      if tex.SetTexture then tex:SetTexture(nil) end
      if tex.Hide then tex:Hide() end
      if tex.SetAlpha then tex:SetAlpha(0) end
    end
    if closeBtn.GetNormalTexture then ClearButtonTexture(closeBtn:GetNormalTexture()) end
    if closeBtn.GetPushedTexture then ClearButtonTexture(closeBtn:GetPushedTexture()) end
    if closeBtn.GetHighlightTexture then ClearButtonTexture(closeBtn:GetHighlightTexture()) end
    if closeBtn.GetDisabledTexture then ClearButtonTexture(closeBtn:GetDisabledTexture()) end

    if not closeBtn._haraX then
      closeBtn._haraX = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
      closeBtn._haraX:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
      closeBtn._haraX:SetText("X")
      closeBtn._haraX:SetShadowOffset(0, 0)
      closeBtn:HookScript("OnEnter", function(self)
        if self._haraX then
          self._haraX:SetTextColor(1.0, 0.60, 0.16, 1)
        end
      end)
      closeBtn:HookScript("OnLeave", function(self)
        if self._haraX then
          self._haraX:SetTextColor(0.949, 0.431, 0.031, 1)
        end
      end)
    end

    closeBtn._haraX:SetTextColor(0.949, 0.431, 0.031, 1)
    closeBtn._haraX:SetAlpha(1)
    closeBtn._haraX:Show()
  end

  local panel = EnsureCustomCharacterFrame()
  if panel then
    panel:Show()
    SafeFrameLevel(panel, (CharacterFrame:GetFrameLevel() or 1) - 2)
  end
  S.layoutApplied = true
end

local function StyleStatRows(db)
  local stripeAlpha = (db and db.charsheet and db.charsheet.stripeAlpha) or 0.22
  local fontPath, size, outline = GetConfiguredFont(db)

  for i = 1, 80 do
    local row = _G["CharacterStatFrame" .. i]
    if row then
      if not S.statRows[row] then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
        S.statRows[row] = bg
      end

      local bg = S.statRows[row]
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
        btn:SetSize(CFG.SLOT_ICON_SIZE, CFG.SLOT_ICON_SIZE)
      end
      if btn.SetFrameStrata then
        btn:SetFrameStrata("DIALOG")
      end
      if btn.SetSnapToPixelGrid then btn:SetSnapToPixelGrid(true) end
      if btn.SetTexelSnappingBias then btn:SetTexelSnappingBias(0) end
      if btn.SetScale then btn:SetScale(1) end
      local skin = EnsureSlotSkin(btn)
      if skin then skin:Show() end
      if skin and skin.SetFrameLevel and btn.GetFrameLevel then
        skin:SetFrameLevel(math.max(0, (btn:GetFrameLevel() or 1) - 1))
      end
      if btn.SetFrameLevel and S.customGearFrame and S.customGearFrame.GetFrameLevel then
        btn:SetFrameLevel((S.customGearFrame:GetFrameLevel() or 1) + 30)
      end

      local icon = _G[name .. "IconTexture"] or btn.icon or btn.Icon
      if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(true) end
        if icon.SetTexelSnappingBias then icon:SetTexelSnappingBias(0) end
      end
      if icon and icon.SetDrawLayer then
        icon:SetDrawLayer("ARTWORK", 7)
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
  local anchor = CharacterFrame
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

  local vpad = 24

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

  -- Pin every slot to a fixed size so Blizzard cannot resize them and
  -- collapse the chain.  Use absolute Y offsets from the anchor instead of
  -- chaining through BOTTOMLEFT, making layout immune to height changes.
  local stride = CFG.SLOT_ICON_SIZE + vpad
  local topY = -64
  local leftX = 14
  local statsWidth = math.max(140, math.floor((CFG.CUSTOM_STATS_WIDTH * 0.9) + 0.5))
  local rightColumnX = CFG.PRIMARY_SHEET_WIDTH - statsWidth - 55

  local leftSlots  = { head, neck, shoulder, back, chest, shirt, tabard, wrist }
  local rightSlots = { hands, waist, legs, feet, finger0, finger1, trinket0, trinket1 }

  for i, slot in ipairs(leftSlots) do
    slot:SetSize(CFG.SLOT_ICON_SIZE, CFG.SLOT_ICON_SIZE)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", anchor, "TOPLEFT", leftX, topY - stride * (i - 1))
  end
  for i, slot in ipairs(rightSlots) do
    slot:SetSize(CFG.SLOT_ICON_SIZE, CFG.SLOT_ICON_SIZE)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", anchor, "TOPLEFT", rightColumnX, topY - stride * (i - 1))
  end

  local leftColumnX = 14
  local slotSize = CFG.SLOT_ICON_SIZE
  local pairGapX = 68 -- ~30% more spacing than 52 while keeping center alignment
  local leftColumnCenter = leftColumnX + (slotSize * 0.5)
  local rightColumnCenter = rightColumnX + (slotSize * 0.5)
  local centerX = math.floor(((leftColumnCenter + rightColumnCenter) * 0.5) + 0.5)
  local mainHandX = math.floor((centerX - (pairGapX * 0.5) - (slotSize * 0.5)) + 0.5)

  mainHand:SetSize(CFG.SLOT_ICON_SIZE, CFG.SLOT_ICON_SIZE)
  mainHand:ClearAllPoints()
  mainHand:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", mainHandX, 66)
  offHand:SetSize(CFG.SLOT_ICON_SIZE, CFG.SLOT_ICON_SIZE)
  offHand:ClearAllPoints()
  offHand:SetPoint("TOPLEFT", mainHand, "TOPLEFT", pairGapX, 0)
end

local function ApplyChonkyModelLayout()
  local model = _G.CharacterModelScene
  if not model then return end

  local fill = EnsureModelFillFrame()
  local boxTop, boxBottom = -84, 46
  local boxWidth = 356
  local statsWidth = math.max(140, math.floor((CFG.CUSTOM_STATS_WIDTH * 0.9) + 0.5))
  local leftColumnX = 14
  local rightColumnX = CFG.PRIMARY_SHEET_WIDTH - statsWidth - 55
  local slotSize = CFG.SLOT_ICON_SIZE
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
    S.modelLockedCameraScale = 1.32
    pcall(model.SetCameraDistanceScale, model, S.modelLockedCameraScale)
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
      if not S.modelBaseScale then
        local s = actor:GetModelScale()
        if type(s) == "number" and s > 0 then
          S.modelBaseScale = s
        end
      end
      if S.modelBaseScale then
        actor:SetModelScale(S.modelBaseScale * CFG.MODEL_ZOOM_OUT_FACTOR)
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
  local function SuppressDefaultStatRows()
    for i = 1, 80 do
      local row = _G["CharacterStatFrame" .. i]
      if row then
        SaveAndHideRegion(row)
        SaveAndHideRegion(row.Label or _G[row:GetName() .. "Label"])
        SaveAndHideRegion(row.Value or _G[row:GetName() .. "Value"])
        if row.EnableMouse then row:EnableMouse(false) end
        if row.SetMouseClickEnabled then row:SetMouseClickEnabled(false) end
        if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(false) end
      end
    end
  end

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
    if _G.CharacterStatsPane.SetMouseClickEnabled then _G.CharacterStatsPane:SetMouseClickEnabled(false) end
    if _G.CharacterStatsPane.SetMouseMotionEnabled then _G.CharacterStatsPane:SetMouseMotionEnabled(false) end
  end
  SuppressDefaultStatRows()
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
  if S.rightPanel then return S.rightPanel end
  if not CharacterFrame then return nil end

  S.rightPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  S.rightPanel:SetSize(640, 620)
  S.rightPanel:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  S.rightPanel:SetBackdropColor(0, 0, 0, 0)
  S.rightPanel:SetBackdropBorderColor(0, 0, 0, 0)
  -- Keep Mythic+ panel above custom stats layers to avoid tooltip/hit-test bleed.
  S.rightPanel:SetFrameStrata("HIGH")
  SafeFrameLevel(S.rightPanel, (CharacterFrame:GetFrameLevel() or 1) + 80)
  S.rightPanel:EnableMouse(true)
  S.rightPanel:SetClampedToScreen(true)
  S.rightPanel:SetMovable(false)

  S.rightPanel.bgGradient = S.rightPanel:CreateTexture(nil, "BACKGROUND")
  S.rightPanel.bgGradient:SetAllPoints()
  S.rightPanel.bgGradient:SetTexture("Interface/Buttons/WHITE8x8")
  -- M+ panel gradient: black at top -> purple at bottom.
  SetVerticalGradient(S.rightPanel.bgGradient, 0, 0, 0, 0.90, 0.08, 0.02, 0.12, 0.90)

  S.rightPanel.headerTitle = S.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  S.rightPanel.headerTitle:SetPoint("TOPLEFT", 12, -8)
  S.rightPanel.headerTitle:SetText("Current Run")

  S.rightPanel.mplusTitle = S.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  S.rightPanel.mplusTitle:SetPoint("TOP", S.rightPanel, "TOP", 0, -58)
  S.rightPanel.mplusTitle:SetText("Mythic+ Rating")

  S.rightPanel.mplusValue = S.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  S.rightPanel.mplusValue:SetPoint("TOP", S.rightPanel.mplusTitle, "BOTTOM", 0, -2)
  S.rightPanel.mplusValue:SetTextColor(1, 0.5, 0.1, 1)
  S.rightPanel.mplusValue:SetText("0")

  S.rightPanel.affixBar = CreateFrame("Frame", nil, S.rightPanel)
  S.rightPanel.affixBar:SetPoint("TOPRIGHT", S.rightPanel, "TOPRIGHT", -10, -8)
  S.rightPanel.affixBar:SetSize(220, 40)
  S.rightPanel.affixSlots = {}

  local affixBorderColors = {
    { 0.20, 0.80, 0.25, 1.0 }, -- 4
    { 0.95, 0.82, 0.22, 1.0 }, -- 7
    { 0.98, 0.56, 0.18, 1.0 }, -- 10
    { 0.92, 0.26, 0.22, 1.0 }, -- 12
  }
  local affixLevelLabels = { "4", "7", "10", "12" }

  for i = 1, 4 do
    local slot = CreateFrame("Frame", nil, S.rightPanel.affixBar, "BackdropTemplate")
    slot:SetSize(38, 38)
    slot:SetPoint("TOPRIGHT", S.rightPanel.affixBar, "TOPRIGHT", -((4 - i) * 54), 0)
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

    slot.level = S.rightPanel.affixBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

    S.rightPanel.affixSlots[i] = slot
  end

  S.rightPanel.tableHeader = CreateFrame("Frame", nil, S.rightPanel)
  S.rightPanel.tableHeader:SetPoint("TOPLEFT", S.rightPanel, "TOPLEFT", 8, -106)
  S.rightPanel.tableHeader:SetPoint("TOPRIGHT", S.rightPanel, "TOPRIGHT", -8, -106)
  S.rightPanel.tableHeader:SetHeight(26)

  S.rightPanel.colDungeon = S.rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.rightPanel.colDungeon:SetPoint("LEFT", 10, 0)
  S.rightPanel.colDungeon:SetWidth(340)
  S.rightPanel.colDungeon:SetJustifyH("CENTER")
  S.rightPanel.colDungeon:SetText("Dungeon")

  S.rightPanel.colLevel = S.rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.rightPanel.colLevel:SetPoint("RIGHT", -240, 0)
  S.rightPanel.colLevel:SetWidth(64)
  S.rightPanel.colLevel:SetJustifyH("RIGHT")
  S.rightPanel.colLevel:SetText("Level")

  S.rightPanel.colRating = S.rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.rightPanel.colRating:SetPoint("RIGHT", -170, 0)
  S.rightPanel.colRating:SetWidth(64)
  S.rightPanel.colRating:SetJustifyH("CENTER")
  S.rightPanel.colRating:SetText("Rating")

  S.rightPanel.colBest = S.rightPanel.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.rightPanel.colBest:SetPoint("RIGHT", -10, 0)
  S.rightPanel.colBest:SetWidth(180)
  S.rightPanel.colBest:SetJustifyH("RIGHT")
  S.rightPanel.colBest:SetMaxLines(1)
  if S.rightPanel.colBest.SetWordWrap then S.rightPanel.colBest:SetWordWrap(false) end
  if S.rightPanel.colBest.SetNonSpaceWrap then S.rightPanel.colBest:SetNonSpaceWrap(false) end
  S.rightPanel.colBest:SetText("Best")

  S.rightPanel.rowContainer = CreateFrame("Frame", nil, S.rightPanel)
  S.rightPanel.rowContainer:SetPoint("TOPLEFT", S.rightPanel.tableHeader, "BOTTOMLEFT", 0, -2)
  S.rightPanel.rowContainer:SetPoint("TOPRIGHT", S.rightPanel.tableHeader, "BOTTOMRIGHT", 0, -2)
  S.rightPanel.rowContainer:SetHeight(282)
  S.rightPanel.rowContainer.rows = {}

  for i = 1, 8 do
    local row = CreateFrame("Frame", nil, S.rightPanel.rowContainer, "BackdropTemplate")
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
    row.level:SetPoint("RIGHT", -240, 0)
    row.level:SetWidth(64)
    row.level:SetJustifyH("RIGHT")
    row.level:SetText("-")

    row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.rating:SetPoint("RIGHT", -170, 0)
    row.rating:SetWidth(64)
    row.rating:SetJustifyH("CENTER")
    row.rating:SetText("-")

    row.best = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.best:SetPoint("RIGHT", -10, 0)
    row.best:SetWidth(180)
    row.best:SetJustifyH("RIGHT")
    row.best:SetMaxLines(1)
    if row.best.SetWordWrap then row.best:SetWordWrap(false) end
    if row.best.SetNonSpaceWrap then row.best:SetNonSpaceWrap(false) end
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

    S.rightPanel.rowContainer.rows[i] = row
  end

  S.rightPanel.vaultTitle = S.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  S.rightPanel.vaultTitle:SetPoint("BOTTOM", S.rightPanel, "BOTTOM", 0, 172)
  S.rightPanel.vaultTitle:SetText("Great Vault")

  S.rightPanel.vault = CreateFrame("Frame", nil, S.rightPanel)
  S.rightPanel.vault:SetSize(606, 144)
  S.rightPanel.vault:SetPoint("BOTTOM", S.rightPanel, "BOTTOM", 0, 20)
  S.rightPanel.vault.cards = {}

  for i = 1, 9 do
    local card = CreateFrame("Frame", nil, S.rightPanel.vault, "BackdropTemplate")
    card:SetSize(198, 44)
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    card:SetPoint("TOPLEFT", col * 204, -(row * 50))
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

    S.rightPanel.vault.cards[i] = card
  end

  S.rightPanel.dragger = CreateFrame("Frame", nil, S.rightPanel, "BackdropTemplate")
  S.rightPanel.dragger:SetAllPoints(true)
  S.rightPanel.dragger:SetFrameLevel(S.rightPanel:GetFrameLevel() + 100)
  S.rightPanel.dragger:EnableMouse(false)
  S.rightPanel.dragger:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  S.rightPanel.dragger:SetBackdropColor(0.02, 0.04, 0.08, 0.15)
  S.rightPanel.dragger:SetBackdropBorderColor(0.4, 0.6, 1.0, 0.5)
  S.rightPanel.dragger:Hide()

  S.rightPanel.dragger.label = S.rightPanel.dragger:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  S.rightPanel.dragger.label:SetPoint("TOP", S.rightPanel.dragger, "TOP", 0, -6)
  S.rightPanel.dragger.label:SetText("Drag Mythic+ Panel")

  S.rightPanel.dragger:SetScript("OnDragStart", nil)
  S.rightPanel.dragger:SetScript("OnDragStop", nil)
  S.rightPanel.dragger:SetScript("OnMouseUp", function(_, button)
    if button ~= "RightButton" then return end
    local db = NS:GetDB()
    if not (db and db.charsheet) then return end
    db.charsheet.rightPanelDetached = false
    db.charsheet.rightPanelAnchor = "TOPLEFT"
    db.charsheet.rightPanelX = 0
    db.charsheet.rightPanelY = 0
  end)

  return S.rightPanel
end

local function GetRightPanelAnchorFrame()
  return CharacterFrame
end

local function PositionRightPanel(db)
  if not S.rightPanel or not db or not db.charsheet then return end
  if InCombatLockdown and InCombatLockdown() then return end
  S.rightPanel:ClearAllPoints()
  -- Fixed Mythic+ panel size: keep this stable.
  S.rightPanel:SetSize(640, 620)
  -- Migrate legacy integrated gap defaults (8) to flush join (0).
  local xOffset = tonumber(db.charsheet.rightPanelOffsetX)
  if xOffset == nil then
    xOffset = 0
  elseif math.abs(xOffset - CFG.INTEGRATED_RIGHT_GAP) < 0.001 then
    xOffset = 0
    db.charsheet.rightPanelOffsetX = 0
  elseif xOffset < 0 then
    -- Keep integrated panel flush/right of CharacterFrame; no overlap into stats pane.
    xOffset = 0
    db.charsheet.rightPanelOffsetX = 0
  end
  S.rightPanel:SetPoint(
    "LEFT",
    CharacterFrame,
    "RIGHT",
    xOffset,
    (db.charsheet.rightPanelOffsetY or 0) + CFG.RIGHT_PANEL_CENTER_Y_BIAS
  )
end

local function ApplyRightPanelFont(db)
  if not S.rightPanel then return end
  local fontPath, size, outline = GetConfiguredFont(db)
  local function Apply(fs, s)
    if fs and fs.SetFont then
      BackupFont(fs)
      fs:SetFont(fontPath, s, outline)
    end
  end

  Apply(S.rightPanel.headerTitle, size + 1)
  Apply(S.rightPanel.mplusTitle, size + 2)
  Apply(S.rightPanel.mplusValue, size + 8)
  Apply(S.rightPanel.colDungeon, size)
  Apply(S.rightPanel.colLevel, size)
  Apply(S.rightPanel.colRating, size)
  Apply(S.rightPanel.colBest, size)
  Apply(S.rightPanel.vaultTitle, size + 2)
  if S.rightPanel.affixSlots then
    for _, slot in ipairs(S.rightPanel.affixSlots) do
      Apply(slot.level, size - 1)
    end
  end

  if S.rightPanel.rowContainer and S.rightPanel.rowContainer.rows then
    for _, row in ipairs(S.rightPanel.rowContainer.rows) do
      Apply(row.name, size + 1)
      Apply(row.level, size + 1)
      Apply(row.rating, size + 1)
      Apply(row.best, size + 1)
    end
  end
  if S.rightPanel.vault and S.rightPanel.vault.cards then
    for _, card in ipairs(S.rightPanel.vault.cards) do
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

  local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
  faction = faction and string.lower(faction) or ""

  -- Expand aliases from all matching keys so variant map names can chain to the same portal hints.
  local expanded = {}
  local i = 1
  while i <= #aliases do
    local key = aliases[i]
    if key and key ~= "" and not expanded[key] then
      expanded[key] = true
      local entry = PORTAL_ALIASES[key]
      if entry then
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
      end
    end
    i = i + 1
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
  if S.portalSpellCache[cacheKey] ~= nil then
    local cached = S.portalSpellCache[cacheKey]
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
    S.portalSpellCache[cacheKey] = { spellID = bestID, actionID = bestActionID }
    return bestID, bestActionID
  end
  S.portalSpellCache[cacheKey] = false
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
    S.pendingSecureUpdate = true
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

local RP = {}

function RP.FormatMS(ms)
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

function RP.NormalizeDurationMS(value, keyName)
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

function RP.CoerceRunFromTable(tbl, mapID)
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
    bestRunDurationMS = RP.NormalizeDurationMS(duration, "duration"),
    overTimeMS = (type(over) == "number") and over or nil,
    stars = (type(stars) == "number") and math.max(0, math.min(3, math.floor(stars + 0.5))) or 0,
  }
  return run
end

function RP.ExtractRunsDeep(value, mapID, out, depth)
  if depth <= 0 then return end
  if type(value) ~= "table" then return end

  local run = RP.CoerceRunFromTable(value, mapID)
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
      RP.ExtractRunsDeep(v, childMapID, out, depth - 1)
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
          synthetic.bestRunDurationMS = RP.NormalizeDurationMS(v, key)
        end
        out[#out] = synthetic
      end
    end
  end
end

function RP.MergeBestRunsByMap(runs)
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

function RP.ShallowCopyArray(src)
  if type(src) ~= "table" then return nil end
  local out = {}
  for i = 1, #src do
    out[i] = src[i]
  end
  return out
end

function RP.CopyRuns(runs)
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

function RP.GetPlayerSnapshotKey()
  local guid = UnitGUID and UnitGUID("player") or nil
  if type(guid) == "string" and guid ~= "" then
    return guid
  end
  local name, realm = UnitName and UnitName("player") or nil, GetRealmName and GetRealmName() or nil
  if type(name) == "string" and name ~= "" then
    return (name or "") .. "-" .. (realm or "")
  end
  return nil
end

function RP.GetRunDeltaMS(run)
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

function RP.VaultToNumber(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then
    local n = tonumber(v)
    if n then return n end
  end
  return nil
end

function RP.GetVaultActivityProgress(act)
  if type(act) ~= "table" then return 0 end
  return RP.VaultToNumber(act.progress) or RP.VaultToNumber(act.completedActivities) or RP.VaultToNumber(act.currentProgress) or 0
end

function RP.GetVaultActivityItemLevel(act)
  if type(act) ~= "table" then return nil end
  local direct = RP.VaultToNumber(act.itemLevel) or RP.VaultToNumber(act.rewardItemLevel) or RP.VaultToNumber(act.rewardLevel) or RP.VaultToNumber(act.ilvl)
  if direct and direct > 100 then
    return math.floor(direct + 0.5)
  end
  if C_WeeklyRewards and C_WeeklyRewards.GetActivityEncounterInfo and act.id then
    local ok, info = pcall(C_WeeklyRewards.GetActivityEncounterInfo, act.id)
    if ok and type(info) == "table" then
      local n = RP.VaultToNumber(info.itemLevel) or RP.VaultToNumber(info.rewardItemLevel) or RP.VaultToNumber(info.ilvl)
      if n and n > 100 then
        return math.floor(n + 0.5)
      end
    end
  end
  return nil
end

function RP.GetVaultRaidDifficultyLabel(act)
  if type(act) ~= "table" then return "Raid" end
  local diff = RP.VaultToNumber(act.difficultyID) or RP.VaultToNumber(act.difficulty) or RP.VaultToNumber(act.level)
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

function RP.GetVaultHardestDifficultyLabel(trackType, act)
  if type(act) ~= "table" then return "" end

  if trackType == 1 then
    local raidDiff = RP.GetVaultRaidDifficultyLabel(act)
    if raidDiff and raidDiff ~= "" then
      return raidDiff
    end
    return ""
  end

  if trackType == 2 then
    local lvl = RP.VaultToNumber(act.level) or RP.VaultToNumber(act.keystoneLevel) or RP.VaultToNumber(act.bestLevel) or RP.VaultToNumber(act.bestRunLevel) or RP.VaultToNumber(act.challengeLevel)
    if lvl and lvl > 0 then
      return ("+%d"):format(math.floor(lvl + 0.5))
    end
    return ""
  end

  if trackType == 3 then
    local tier = RP.VaultToNumber(act.level) or RP.VaultToNumber(act.tier) or RP.VaultToNumber(act.tierID) or RP.VaultToNumber(act.difficulty) or RP.VaultToNumber(act.difficultyID)
    if tier and tier > 0 then
      return ("Tier %d"):format(math.floor(tier + 0.5))
    end
    return ""
  end

  return ""
end

RP.VAULT_TRACK_TYPE_BY_ROW = { 2, 1, 3 } -- Dungeons, Raids, World
RP.VAULT_TRACK_NAME_BY_TYPE = {
  [1] = "Raids",
  [2] = "Dungeons",
  [3] = "World",
}
RP.VAULT_THRESHOLDS_BY_TYPE = {
  [2] = { 2, 4, 8 }, -- Dungeons
  [1] = { 1, 4, 6 }, -- Raids
  [3] = { 2, 4, 8 }, -- World
}
RP.VAULT_TRACK_COLOR = {
  [1] = { 0.05, 0.08, 0.16, 0.74, 0.20, 0.30, 0.55, 0.88 },
  [2] = { 0.12, 0.04, 0.18, 0.74, 0.38, 0.22, 0.56, 0.90 },
  [3] = { 0.06, 0.11, 0.08, 0.74, 0.20, 0.40, 0.26, 0.88 },
}

function RP.RefreshRightPanelHeaderAndAffixes(snapshotKey, sameSnapshotOwner)
  local currentRunText = "No active key"
  if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or nil
    if mapID and mapID > 0 then
      local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
      currentRunText = ("%s (%s)"):format(name or ("Map " .. mapID), level and ("+" .. level) or "?")
    end
  end
  if S.rightPanel and S.rightPanel.headerTitle then
    S.rightPanel.headerTitle:SetText(currentRunText)
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

  if S.rightPanel and S.rightPanel.affixSlots then
    if #affixIDs == 0 and sameSnapshotOwner and type(S.lastMPlusSnapshot.affixIDs) == "table" and #S.lastMPlusSnapshot.affixIDs > 0 then
      affixIDs = RP.ShallowCopyArray(S.lastMPlusSnapshot.affixIDs) or affixIDs
    elseif #affixIDs > 0 then
      S.lastMPlusSnapshot.ownerKey = snapshotKey
      S.lastMPlusSnapshot.affixIDs = RP.ShallowCopyArray(affixIDs)
    end

    for i, slot in ipairs(S.rightPanel.affixSlots) do
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
end

function RP.GetCurrentMythicRating()
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
  return rating or 0
end

function RP.GatherMythicRuns()
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

  if #runs == 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable then
    local mapTable = C_ChallengeMode.GetMapTable()
    if type(mapTable) == "table" then
      for _, mapID in ipairs(mapTable) do
        local row = { mapChallengeModeID = mapID }
        if C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
          local ok, info = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
          if ok and type(info) == "table" then
            local extracted = {}
            RP.ExtractRunsDeep(info, mapID, extracted, 6)
            extracted = RP.MergeBestRunsByMap(extracted)
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
              RP.ExtractRunsDeep(a, mapID, extracted, 6)
              extracted = RP.MergeBestRunsByMap(extracted)
              if #extracted > 0 then
                local best = extracted[1]
                row.score = row.score or best.score
                row.level = row.level or best.level
                row.bestRunDurationMS = row.bestRunDurationMS or best.bestRunDurationMS
                row.overTimeMS = row.overTimeMS or best.overTimeMS
              end
            else
              local tuple = { score = a, level = b, bestRunDurationMS = c, overTimeMS = d, mapChallengeModeID = mapID }
              local parsed = RP.CoerceRunFromTable(tuple, mapID)
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
  return runs
end

function RP.FilterAndNormalizeRuns(runs, rating)
  if #runs > 0 and (rating or 0) <= 0 then
    local hasPositiveRun = false
    for _, run in ipairs(runs) do
      if type(run) == "table" then
        local lvl = run.level or run.bestLevel or run.keystoneLevel or 0
        local scr = run.score or run.rating or 0
        if (type(lvl) == "number" and lvl > 0) or (type(scr) == "number" and scr > 0) then
          hasPositiveRun = true
          break
        end
      end
    end
    if hasPositiveRun then
      runs = {}
    end
  end

  if #runs > 0 then
    local extracted = {}
    for _, r in ipairs(runs) do
      if type(r) == "table" then
        RP.ExtractRunsDeep(r, r.mapChallengeModeID or r.mapID, extracted, 4)
      end
    end
    if #extracted > 0 then
      runs = RP.MergeBestRunsByMap(extracted)
    else
      runs = RP.MergeBestRunsByMap(runs)
    end
  end
  return runs
end

function RP.ApplyRunSnapshotCache(runs, snapshotKey, sameSnapshotOwner)
  if #runs == 0 and sameSnapshotOwner and type(S.lastMPlusSnapshot.runs) == "table" and #S.lastMPlusSnapshot.runs > 0 then
    return RP.CopyRuns(S.lastMPlusSnapshot.runs) or runs
  end
  if #runs > 0 then
    S.lastMPlusSnapshot.ownerKey = snapshotKey
    S.lastMPlusSnapshot.runs = RP.CopyRuns(runs)
  end
  return runs
end

function RP.RenderRunRows(runs)
  if not (S.rightPanel and S.rightPanel.rowContainer and S.rightPanel.rowContainer.rows) then
    return
  end

  table.sort(runs, function(a, b)
    local al = a and (a.level or a.bestLevel or a.keystoneLevel or 0) or 0
    local bl = b and (b.level or b.bestLevel or b.keystoneLevel or 0) or 0
    if al ~= bl then return al > bl end
    local as = a and (a.score or a.rating or 0) or 0
    local bs = b and (b.score or b.rating or 0) or 0
    return as > bs
  end)

  for i, row in ipairs(S.rightPanel.rowContainer.rows) do
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
      local best = RP.FormatMS(bestMS)
      local deltaMS = RP.GetRunDeltaMS(run)
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
        local absText = RP.FormatMS(math.abs(deltaMS))
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
    S.pendingSecureUpdate = false
  end
end

function RP.GetWeeklyVaultActivities()
  local acts = {}
  if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
    local t = C_WeeklyRewards.GetActivities()
    if type(t) == "table" then
      acts = t
    end
  end
  return acts
end

function RP.RenderVaultCards(acts)
  if not (S.rightPanel and S.rightPanel.vault and S.rightPanel.vault.cards) then
    return
  end
  local byType = {
    [1] = {},
    [2] = {},
    [3] = {},
  }
  for _, act in ipairs(acts or {}) do
    local t = act and act.type
    if byType[t] then
      byType[t][#byType[t] + 1] = act
    end
  end

  for i, card in ipairs(S.rightPanel.vault.cards) do
    local col = ((i - 1) % 3) + 1
    local row = math.floor((i - 1) / 3) + 1
    local trackType = RP.VAULT_TRACK_TYPE_BY_ROW[row] or 2
    local actList = byType[trackType] or {}
    local act = actList[col]

    local c = RP.VAULT_TRACK_COLOR[trackType] or RP.VAULT_TRACK_COLOR[2]
    card:SetBackdropColor(c[1], c[2], c[3], c[4])
    card:SetBackdropBorderColor(c[5], c[6], c[7], c[8])

    local label = RP.VAULT_TRACK_NAME_BY_TYPE[trackType] or "Vault"
    local target = (RP.VAULT_THRESHOLDS_BY_TYPE[trackType] and RP.VAULT_THRESHOLDS_BY_TYPE[trackType][col]) or 0
    local progress = RP.GetVaultActivityProgress(act)
    local complete = (target > 0 and progress >= target)

    card.title:SetText(label)
    card.progress:SetText(("%d / %d"):format(progress, target))

    local ilvl = RP.GetVaultActivityItemLevel(act)
    card.ilvl:SetText(ilvl and tostring(ilvl) or "")
    card.difficulty:SetText(RP.GetVaultHardestDifficultyLabel(trackType, act))

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

function RP.RefreshRightPanelData()
  if not S.rightPanel then return end
  local snapshotKey = RP.GetPlayerSnapshotKey()
  local sameSnapshotOwner = (snapshotKey ~= nil and S.lastMPlusSnapshot.ownerKey == snapshotKey)

  if snapshotKey ~= nil and not sameSnapshotOwner then
    -- Prevent cross-character bleed when opening on alts/new characters.
    S.lastMPlusSnapshot.ownerKey = snapshotKey
    S.lastMPlusSnapshot.affixIDs = nil
    S.lastMPlusSnapshot.runs = nil
  end

  if C_MythicPlus and C_MythicPlus.RequestMapInfo then
    pcall(C_MythicPlus.RequestMapInfo)
  end

  RP.RefreshRightPanelHeaderAndAffixes(snapshotKey, sameSnapshotOwner)
  local rating = RP.GetCurrentMythicRating()
  if S.rightPanel.mplusValue then
    S.rightPanel.mplusValue:SetText(("%d"):format(math.floor((rating or 0) + 0.5)))
  end

  local runs = RP.GatherMythicRuns()
  runs = RP.FilterAndNormalizeRuns(runs, rating)
  runs = RP.ApplyRunSnapshotCache(runs, snapshotKey, sameSnapshotOwner)
  RP.RenderRunRows(runs)

  local acts = RP.GetWeeklyVaultActivities()
  RP.RenderVaultCards(acts)
end

function RP.HideArtwork(db)
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
  if S.refreshInProgress then
    S.refreshQueuedAfterCurrent = true
    return
  end
  S.refreshInProgress = true
  SyncCustomModeToNativePanel()

  if db.charsheet.styleStats then
    ApplyCustomCharacterLayout()
  else
    if S.layoutApplied then
      RestoreCapturedLayouts()
      S.layoutApplied = false
    end
    if S.customCharacterFrame then
      S.customCharacterFrame:Hide()
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
    RP.HideArtwork(db)
  else
    RestoreHiddenRegions()
  end

  if db.charsheet.styleStats then
    ApplyCoreCharacterFontAndName(db)
    RestorePaperDollSidebarButtons()
    if CFG.SIMPLE_BASE_PANEL_MODE then
      -- 1.0 baseline: one character base panel only, no extra stat/section sub-panels.
      StylePaperDollSlots()
      ApplyChonkySlotLayout()
      ApplyChonkyModelLayout()
      ApplyMinimalChonkyBase()
      HideTabArt()
      HideCharacterTabsButtons()
      if S.skinFrame then
        S.skinFrame:Hide()
      end
      for _, panel in pairs(S.panelSkins) do
        if panel and panel.Hide then
          panel:Hide()
        end
      end
      -- Re-enable custom stat panels on the right side of the character panel.
      UpdateCustomStatsFrame(db)
      UpdateCustomGearFrame(db)
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
      UpdateCustomGearFrame(db)
    end
  else
    for _, bg in pairs(S.statRows) do
      if bg and bg.Hide then
        bg:Hide()
      end
    end
    for _, skin in pairs(S.slotSkins) do
      if skin and skin.Hide then
        skin:Hide()
      end
    end
    for _, panel in pairs(S.panelSkins) do
      if panel and panel.Hide then
        panel:Hide()
      end
    end
    if S.customStatsFrame then
      S.customStatsFrame:Hide()
    end
    if S.customGearFrame then
      S.customGearFrame:Hide()
    end
    if S.modelFillFrame then
      S.modelFillFrame:Hide()
    end
    ShowDefaultCharacterStats()
    RestoreFonts()
  end

  local activeMode = ResolveEffectiveCharacterMode()
  if S.customStatsFrame then
    S.customStatsFrame.activeMode = activeMode
  end
  local blankBottomMode = db.charsheet.styleStats and (activeMode == 2 or activeMode == 3)
  local rightCollapsed = db.charsheet.rightPanelCollapsed == true
  local charVisible = CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()
  local showRight = charVisible and (db.charsheet.showRightPanel ~= false) and not blankBottomMode and not rightCollapsed
  if showRight then
    local panel = EnsureRightPanel(db)
    if panel then
      PositionRightPanel(db)
      panel:Show()
      ApplyRightPanelFont(db)
      RP.RefreshRightPanelData()
      self:SetLocked(db.general and db.general.framesLocked ~= false)
    end
  elseif S.rightPanel then
    S.rightPanel:Hide()
  end

  SyncBottomModeButtonsVisibility(db)

  S.refreshInProgress = false
  if S.refreshQueuedAfterCurrent then
    S.refreshQueuedAfterCurrent = false
    self:Refresh()
  end
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.charsheet or not db.charsheet.enabled then
    self:Disable()
    return
  end
  M.active = true
  S.liveUpdateQueued = false
  S.liveUpdateIncludeRightPanel = false
  wipe(S.inventoryTooltipCache)

  if not IsAddonLoadedCompat("Blizzard_CharacterUI") then
    LoadAddonCompat("Blizzard_CharacterUI")
  end

  -- Build custom panes ahead of first open to avoid first-show hitching.
  if db.charsheet and db.charsheet.styleStats and CharacterFrame then
    EnsureCustomCharacterFrame()
    EnsureCustomStatsFrame()
    EnsureCustomGearFrame()
  end

  -- Unconditional slot-position enforcer: re-applies ApplyChonkySlotLayout
  -- every frame for a short window after the character frame is shown so that
  -- any late Blizzard re-anchoring is immediately corrected.
  if not S.slotEnforcer then
    S.slotEnforcer = CreateFrame("Frame")
    S.slotEnforcer:Hide()
    S.slotEnforcer:SetScript("OnUpdate", function(self)
      if GetTime() >= S.slotEnforceUntil then
        self:Hide()
        return
      end
      if not M.active or not S.layoutApplied then self:Hide() return end
      if not (CharacterFrame and CharacterFrame:IsShown()) then self:Hide() return end
      if InCombatLockdown and InCombatLockdown() then return end
      ApplyCustomCharacterLayout()
      ApplyChonkySlotLayout()
    end)
  end

  local function StartSlotEnforcer()
    if not S.slotEnforcer then return end
    S.slotEnforceUntil = GetTime() + 0.6
    S.slotEnforcer:Show()
  end
  local UpdateTickerState

  if CharacterFrame and not S.hookedShow then
    CharacterFrame:HookScript("OnShow", function()
      if S.rightPanel then
        S.rightPanel:Hide()
      end
      if M.active then
        local liveDB = NS and NS.GetDB and NS:GetDB() or nil
        if liveDB and liveDB.charsheet and liveDB.charsheet.styleStats then
          M._pendingNativeMode = nil
        end
        SyncCustomModeToNativePanel()
        M:Refresh()
        if C_Timer and C_Timer.After then
          C_Timer.After(0, function()
            if not (M.active and CharacterFrame and CharacterFrame:IsShown()) then return end
            local liveDB = NS and NS.GetDB and NS:GetDB() or nil
            if not (liveDB and liveDB.charsheet and liveDB.charsheet.styleStats) then return end
            ApplyCustomCharacterLayout()
          end)
        end
        -- Start the slot enforcer to overwrite any late Blizzard re-anchors.
        StartSlotEnforcer()
        if M._deferredNativeModeMirror ~= nil then
          M._QueueDeferredNativeModeMirror()
        end
      end
      if UpdateTickerState then
        UpdateTickerState(true)
      end
    end)
    S.hookedShow = true
  end
  if CharacterFrame and not S.hookedHide then
    CharacterFrame:HookScript("OnHide", function()
      if S.slotEnforcer then S.slotEnforcer:Hide() end
      if S.rightPanel then
        S.rightPanel:Hide()
      end
      LeaveReputationPaneMode()
      LeaveCurrencyPaneMode()
      if S.customStatsFrame and S.customStatsFrame.modeBar then
        S.customStatsFrame.modeBar:Hide()
      end
      if S.customCharacterFrame then
        S.customCharacterFrame:Hide()
      end
      M._deferredNativeModeMirror = nil
      M._deferredNativeModeRefreshQueued = false
      if UpdateTickerState then
        UpdateTickerState(false)
      end
    end)
    S.hookedHide = true
  end
  local function RefreshForNativeSubframeSwitch(subFrameToken)
    if not M.active then return end
    if S.suppressSubFrameRefresh or M._mirroringNativeSubframeSwitch then return end
    local liveDB = NS and NS.GetDB and NS:GetDB() or nil
    if not (liveDB and liveDB.charsheet and liveDB.charsheet.styleStats) then return end
    local requestedMode = M._ResolveModeFromSubFrameToken(subFrameToken)
    if requestedMode then
      M._deferredNativeModeMirror = requestedMode
    elseif M._deferredNativeModeMirror == nil then
      M._deferredNativeModeMirror = 0
    end
    if not (CharacterFrame and CharacterFrame:IsShown()) then
      M._QueueDeferredNativeModeMirror()
      return
    end
    if not requestedMode then
      requestedMode = ResolveNativeCharacterMode()
    end
    if requestedMode and M._TriggerBottomModeButton(requestedMode) then
      M._deferredNativeModeMirror = nil
      StartSlotEnforcer()
      return
    end
    M._pendingNativeMode = nil
    SyncCustomModeToNativePanel()
    M:Refresh()
    StartSlotEnforcer()
  end
  if not S.hookedSubFrame and hooksecurefunc and CharacterFrame_ShowSubFrame then
    hooksecurefunc("CharacterFrame_ShowSubFrame", function(subFrameToken)
      RefreshForNativeSubframeSwitch(subFrameToken)
    end)
    S.hookedSubFrame = true
  end
  if not M._hookedToggleCharacter and hooksecurefunc and ToggleCharacter then
    hooksecurefunc("ToggleCharacter", function(subFrameToken)
      RefreshForNativeSubframeSwitch(subFrameToken)
    end)
    M._hookedToggleCharacter = true
  end
  local repFrame = _G.ReputationFrame
  if repFrame and repFrame.HookScript and not repFrame._haraModeHooked then
    repFrame:HookScript("OnShow", function(self)
      RefreshForNativeSubframeSwitch(self)
    end)
    repFrame._haraModeHooked = true
  end
  local tokenFrame = GetCurrencyPaneFrame and GetCurrencyPaneFrame() or _G.TokenFrame or _G.CurrencyFrame
  if tokenFrame and tokenFrame.HookScript and not tokenFrame._haraModeHooked then
    tokenFrame:HookScript("OnShow", function(self)
      RefreshForNativeSubframeSwitch(self)
    end)
    tokenFrame._haraModeHooked = true
  end

  local function QueueLiveUpdate(includeRightPanel)
    if includeRightPanel then
      S.liveUpdateIncludeRightPanel = true
    end
    if S.liveUpdateQueued then return end
    S.liveUpdateQueued = true
    if C_Timer and C_Timer.After then
      C_Timer.After(EVENT_DEBOUNCE_INTERVAL, function()
        S.liveUpdateQueued = false
        if not M.active then
          S.liveUpdateIncludeRightPanel = false
          return
        end
        if not (CharacterFrame and CharacterFrame:IsShown()) then
          S.liveUpdateIncludeRightPanel = false
          return
        end
        local liveDB = NS:GetDB()
        if not (liveDB and liveDB.charsheet and liveDB.charsheet.styleStats) then
          S.liveUpdateIncludeRightPanel = false
          return
        end
        ApplyCoreCharacterFontAndName(liveDB)
        UpdateCustomStatsFrame(liveDB)
        UpdateCustomGearFrame(liveDB)
        if S.liveUpdateIncludeRightPanel and S.rightPanel and S.rightPanel:IsShown() then
          RP.RefreshRightPanelData()
        end
        S.liveUpdateIncludeRightPanel = false
      end)
    else
      S.liveUpdateQueued = false
    end
  end

  local function TickerShouldRun()
    if not M.active then
      return false
    end
    local charShown = CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()
    local rightShown = S.rightPanel and S.rightPanel.IsShown and S.rightPanel:IsShown()
    return charShown or rightShown
  end
  local function TickerOnUpdate(_, elapsed)
    if not TickerShouldRun() then
      if UpdateTickerState then
        UpdateTickerState(false)
      end
      return
    end
    if not (CharacterFrame and CharacterFrame:IsShown()) and S.rightPanel and S.rightPanel:IsShown() then
      S.rightPanel:Hide()
    end
    S.elapsedSinceData = S.elapsedSinceData + (elapsed or 0)
    if S.elapsedSinceData >= DATA_REFRESH_INTERVAL then
      S.elapsedSinceData = 0
      if S.rightPanel and S.rightPanel:IsShown() then
        RP.RefreshRightPanelData()
      end
    end
    if S.pendingSecureUpdate and not (InCombatLockdown and InCombatLockdown()) then
      if S.rightPanel and S.rightPanel:IsShown() then
        RP.RefreshRightPanelData()
      else
        S.pendingSecureUpdate = false
      end
    end
  end
  UpdateTickerState = function(resetElapsed)
    if not S.ticker then return end
    if TickerShouldRun() then
      if resetElapsed then
        S.elapsedSinceData = 0
      end
      if S.ticker.GetScript and S.ticker:GetScript("OnUpdate") ~= TickerOnUpdate then
        S.ticker:SetScript("OnUpdate", TickerOnUpdate)
      end
      return
    end
    if S.ticker.GetScript and S.ticker:GetScript("OnUpdate") ~= nil then
      S.ticker:SetScript("OnUpdate", nil)
    end
  end
  if not S.ticker then
    S.ticker = CreateFrame("Frame")
  end
  S.elapsedSinceData = 0
  UpdateTickerState(false)

  if not S.moduleEventFrame then
    S.moduleEventFrame = CreateFrame("Frame")
  end
  local function SafeRegisterEvent(frame, eventName)
    if not (frame and eventName and frame.RegisterEvent) then return end
    pcall(frame.RegisterEvent, frame, eventName)
  end
  local function SafeRegisterUnitEvent(frame, eventName, unit)
    if not (frame and eventName and unit and frame.RegisterUnitEvent) then return end
    pcall(frame.RegisterUnitEvent, frame, eventName, unit)
  end
  S.moduleEventFrame:UnregisterAllEvents()
  SafeRegisterEvent(S.moduleEventFrame, "PLAYER_EQUIPMENT_CHANGED")
  SafeRegisterEvent(S.moduleEventFrame, "PLAYER_SPECIALIZATION_CHANGED")
  SafeRegisterEvent(S.moduleEventFrame, "PLAYER_LOOT_SPEC_UPDATED")
  SafeRegisterEvent(S.moduleEventFrame, "ACTIVE_TALENT_GROUP_CHANGED")
  SafeRegisterEvent(S.moduleEventFrame, "PLAYER_LEVEL_UP")
  SafeRegisterEvent(S.moduleEventFrame, "KNOWN_TITLES_UPDATE")
  SafeRegisterEvent(S.moduleEventFrame, "PLAYER_TITLE_CHANGED")
  SafeRegisterEvent(S.moduleEventFrame, "UPDATE_FACTION")
  SafeRegisterEvent(S.moduleEventFrame, "CURRENCY_DISPLAY_UPDATE")
  SafeRegisterEvent(S.moduleEventFrame, "CURRENCY_LIST_UPDATE")
  SafeRegisterUnitEvent(S.moduleEventFrame, "UNIT_NAME_UPDATE", "player")
  SafeRegisterUnitEvent(S.moduleEventFrame, "UNIT_MAXHEALTH", "player")
  SafeRegisterUnitEvent(S.moduleEventFrame, "UNIT_MAXPOWER", "player")
  SafeRegisterUnitEvent(S.moduleEventFrame, "UNIT_STATS", "player")
  S.moduleEventFrame:SetScript("OnEvent", function(_, event, unitOrSlot)
    if not M.active then return end
    if event == "UNIT_MAXHEALTH" or event == "UNIT_MAXPOWER" or event == "UNIT_STATS" or event == "UNIT_NAME_UPDATE" then
      if unitOrSlot and unitOrSlot ~= "player" then return end
    end
    if event == "PLAYER_LOOT_SPEC_UPDATED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
      S.pendingLootSpecID = nil
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
      local slotID = tonumber(unitOrSlot)
      if slotID then
        S.inventoryTooltipCache[slotID] = nil
      else
        wipe(S.inventoryTooltipCache)
      end
    end
    if not (CharacterFrame and CharacterFrame:IsShown()) then return end
    local liveDB = NS:GetDB()
    if not (liveDB and liveDB.charsheet and liveDB.charsheet.styleStats) then return end
    QueueLiveUpdate(true)
  end)

  self:Refresh()
  UpdateTickerState(false)
end

function M:Disable()
  M.active = false
  S.liveUpdateQueued = false
  S.liveUpdateIncludeRightPanel = false
  S.pendingLootSpecID = nil
  wipe(S.inventoryTooltipCache)
  if S.ticker then
    S.ticker:SetScript("OnUpdate", nil)
  end
  if S.moduleEventFrame then
    S.moduleEventFrame:SetScript("OnEvent", nil)
    S.moduleEventFrame:UnregisterAllEvents()
  end
  if S.skinFrame then
    S.skinFrame:Hide()
  end
  if S.customCharacterFrame then
    S.customCharacterFrame:Hide()
  end
  if S.customNameText then
    S.customNameText:Hide()
  end
  if S.customLevelText then
    S.customLevelText:Hide()
  end
  for _, bg in pairs(S.statRows) do
    if bg and bg.Hide then
      bg:Hide()
    end
  end
  for _, skin in pairs(S.slotSkins) do
    if skin and skin.Hide then
      skin:Hide()
    end
  end
  for _, panel in pairs(S.panelSkins) do
    if panel and panel.Hide then
      panel:Hide()
    end
  end
  if S.rightPanel then
    S.rightPanel:Hide()
  end
  if S.customStatsFrame then
    S.customStatsFrame:Hide()
    if S.customStatsFrame.modeBar then
      S.customStatsFrame.modeBar:Hide()
    end
  end
  if S.customGearFrame then
    S.customGearFrame:Hide()
  end
  if S.customNameText then
    S.customNameText:Hide()
  end
  if S.customLevelText then
    S.customLevelText:Hide()
  end
  if S.modelFillFrame then
    S.modelFillFrame:Hide()
  end
  ShowDefaultCharacterStats()
  RestoreCapturedLayouts()
  S.layoutApplied = false
  RestoreFonts()
  RestoreHiddenRegions()
end

function M:SetLocked(locked)
  if not S.rightPanel or not S.rightPanel.dragger then return end
  S.rightPanel.dragger:Hide()
end
