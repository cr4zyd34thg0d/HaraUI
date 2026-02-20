local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.FrameFactory = CS.FrameFactory or {}
local FrameFactory = CS.FrameFactory
local Utils = CS.Utils

---------------------------------------------------------------------------
-- Constants (exposed for other modules that need creation-time values)
---------------------------------------------------------------------------
local EXPANDED_WIDTH = math.floor(820 * 1.15 + 0.5)   -- ~943
local EXPANDED_HEIGHT = 675
local PANE_HEADING_TOP_INSET = -8
local PANE_HEADING_FONT_SIZE = 36
local PANE_HEADING_LEVEL_BOOST = 50

---------------------------------------------------------------------------
-- State — frame tree only, no layout/lifecycle fields
---------------------------------------------------------------------------
FrameFactory._state = FrameFactory._state or {
  parent = nil,
  root = nil,
  gradient = nil,
  tabs = nil,
  panels = nil,
  characterOverlay = nil,
  leftPaneHeadingHost = nil,
  leftPaneHeading = nil,
  created = false,
  blizzardPanelAttributes = nil, -- captured before our first SetAttribute call
}

---------------------------------------------------------------------------
-- Shared helpers (used by CreateAll)
---------------------------------------------------------------------------
local function SetAllPointsColor(tex, r, g, b, a)
  if not tex then return end
  tex:SetAllPoints()
  tex:SetColorTexture(r, g, b, a)
end

local function CreateBorder(frame, r, g, b, a)
  if not frame or frame._huiBorder then return end
  local top = frame:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", 0, 0)
  top:SetHeight(1)
  top:SetColorTexture(r, g, b, a)

  local bottom = frame:CreateTexture(nil, "BORDER")
  bottom:SetPoint("BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", 0, 0)
  bottom:SetHeight(1)
  bottom:SetColorTexture(r, g, b, a)

  local left = frame:CreateTexture(nil, "BORDER")
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", 0, 0)
  left:SetWidth(1)
  left:SetColorTexture(r, g, b, a)

  local right = frame:CreateTexture(nil, "BORDER")
  right:SetPoint("TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)
  right:SetWidth(1)
  right:SetColorTexture(r, g, b, a)

  frame._huiBorder = { top = top, bottom = bottom, left = left, right = right }
end

local function ApplyVerticalGradient(tex, topR, topG, topB, topA, botR, botG, botB, botA)
  if not tex then return end
  if tex.SetGradientAlpha then
    tex:SetGradientAlpha("VERTICAL", topR, topG, topB, topA, botR, botG, botB, botA)
  elseif tex.SetGradient and CreateColor then
    tex:SetGradient("VERTICAL", CreateColor(topR, topG, topB, topA), CreateColor(botR, botG, botB, botA))
  else
    tex:SetColorTexture(botR, botG, botB, botA)
  end
end

local function ApplyLabelStyle(label, size, r, g, b)
  if not label then return end
  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(label, size)
  end
  label:SetTextColor(r, g, b, 1)
  label:SetShadowColor(0, 0, 0, 1)
  label:SetShadowOffset(1, -1)
end

local function CreatePanel(parent, titleText)
  local panel = CreateFrame("Frame", nil, parent)
  panel.bg = panel:CreateTexture(nil, "BACKGROUND")
  SetAllPointsColor(panel.bg, 0.08, 0.08, 0.09, 0.80)
  CreateBorder(panel, 1, 1, 1, 0.10)

  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  panel.title:SetPoint("TOPLEFT", 8, -8)
  panel.title:SetText(titleText or "Panel")
  ApplyLabelStyle(panel.title, 12, 1.0, 0.67, 0.28)

  panel.body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.body:SetPoint("LEFT", panel, "LEFT", 8, 0)
  panel.body:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
  panel.body:SetJustifyH("CENTER")
  panel.body:SetText("")
  ApplyLabelStyle(panel.body, 10, 0.85, 0.85, 0.85)
  return panel
end

local function ResolveModeIcon(index)
  if index == 2 then return "Interface\\Icons\\Achievement_Reputation_01" end
  if index == 3 then return "Interface\\Icons\\inv_misc_coin_02" end
  local fallback = { [1] = 132089, [2] = 236681, [3] = 463446 }
  return fallback[index] or 134400
end

local function CreateTab(parent, text, tabIndex)
  local Skin = CS and CS.Skin or nil
  local CFG = Skin and Skin.CFG or {}
  local template = Utils.IsAccountTransferBuild()
    and "BackdropTemplate"
    or "SecureActionButtonTemplate,BackdropTemplate"
  local tab = CreateFrame("Button", nil, parent, template)
  tab:SetSize(CFG.STATS_MODE_BUTTON_WIDTH or 86, CFG.STATS_MODE_BUTTON_HEIGHT or 30)
  tab:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  tab:SetBackdropColor(0.03, 0.02, 0.05, 0.92)
  tab:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
  tab.modeIndex = tabIndex

  tab.icon = tab:CreateTexture(nil, "ARTWORK")
  tab.icon:SetSize(14, 14)
  tab.icon:SetPoint("LEFT", tab, "LEFT", 8, 0)
  tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  tab.icon:SetTexture(ResolveModeIcon(tabIndex))

  tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tab.label:SetPoint("LEFT", tab.icon, "RIGHT", 5, 0)
  tab.label:SetPoint("RIGHT", tab, "RIGHT", -6, 0)
  tab.label:SetJustifyH("LEFT")
  tab.label:SetText(text)
  ApplyLabelStyle(tab.label, 10, 0.95, 0.95, 0.95)
  return tab
end

---------------------------------------------------------------------------
-- Escape registration (pure utility, no hooks/timers)
---------------------------------------------------------------------------
local function EnsureSpecialFrameEntry(frameName)
  if type(frameName) ~= "string" or frameName == "" then
    return false
  end
  if type(UISpecialFrames) ~= "table" then
    UISpecialFrames = {}
  end
  for _, name in ipairs(UISpecialFrames) do
    if name == frameName then
      return true
    end
  end
  table.insert(UISpecialFrames, frameName)
  return true
end

function FrameFactory.EnsureCharacterEscapeCloseRegistration()
  if CharacterFrame and CharacterFrame.GetName then
    local ok, name = pcall(CharacterFrame.GetName, CharacterFrame)
    if ok and type(name) == "string" and name ~= "" then
      return EnsureSpecialFrameEntry(name)
    end
  end
  return EnsureSpecialFrameEntry("CharacterFrame")
end

---------------------------------------------------------------------------
-- CreateAll: one-time frame creation
--
-- Returns the root frame. Safe to call multiple times (returns early after
-- the first successful creation).  NO hooks, NO timers, NO lifecycle.
---------------------------------------------------------------------------
function FrameFactory:CreateAll(parent)
  local state = self._state
  parent = parent or CharacterFrame
  if not parent then
    return nil
  end

  -- Create-once guard: if already created, just update parent if needed.
  -- Also backfill gradient if missing (e.g. first /reload after code update).
  if state.created and state.root then
    if state.parent ~= parent then
      state.parent = parent
      if state.root:GetParent() ~= parent then
        state.root:SetParent(parent)
      end
    end
    if not state.gradient then
      local baseLevel = (parent:GetFrameLevel() or 1)
      state.gradient = CreateFrame("Frame", nil, parent)
      state.gradient:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
      state.gradient:SetFrameLevel(baseLevel + 2)
      state.gradient:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
      state.gradient:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
      state.gradient:Hide()
      state.gradient.base = state.gradient:CreateTexture(nil, "BACKGROUND")
      state.gradient.base:SetAllPoints()
      state.gradient.base:SetColorTexture(0, 0, 0, 0.0)
      state.gradient.overlay = state.gradient:CreateTexture(nil, "BORDER")
      state.gradient.overlay:SetAllPoints()
      state.gradient.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
      ApplyVerticalGradient(state.gradient.overlay, 0.08, 0.02, 0.12, 0.90, 0, 0, 0, 0.90)
    end
    return state.root
  end

  state.parent = parent

  local baseLevel = (parent:GetFrameLevel() or 1)

  -- Root overlay (dark background, level+1)
  state.root = CreateFrame("Frame", "HaraUI_CharSheetRoot", parent)
  state.root:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  state.root:SetFrameLevel(baseLevel + 1)
  state.root:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
  state.root:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
  state.root:Hide()

  state.root.bg = state.root:CreateTexture(nil, "BACKGROUND")
  SetAllPointsColor(state.root.bg, 0.03, 0.03, 0.04, 0.92)
  CreateBorder(state.root, 1, 1, 1, 0.06)

  -- Gradient overlay (purple→black, level+2)
  state.gradient = CreateFrame("Frame", nil, parent)
  state.gradient:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  state.gradient:SetFrameLevel(baseLevel + 2)
  state.gradient:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
  state.gradient:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
  state.gradient:Hide()

  state.gradient.base = state.gradient:CreateTexture(nil, "BACKGROUND")
  state.gradient.base:SetAllPoints()
  state.gradient.base:SetColorTexture(0, 0, 0, 0.0)

  state.gradient.overlay = state.gradient:CreateTexture(nil, "BORDER")
  state.gradient.overlay:SetAllPoints()
  state.gradient.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
  ApplyVerticalGradient(state.gradient.overlay, 0.08, 0.02, 0.12, 0.90, 0, 0, 0, 0.90)

  -- Tab bar: parented to CharacterFrame, positioned below it
  state.tabs = CreateFrame("Frame", nil, parent)
  state.tabs:SetFrameStrata("DIALOG")
  state.tabs:SetFrameLevel(baseLevel + 200)

  state.tabs.tabCharacter = CreateTab(state.tabs, "Character", 1)
  state.tabs.tabReputation = CreateTab(state.tabs, "Rep", 2)
  state.tabs.tabCurrency = CreateTab(state.tabs, "Currency", 3)

  -- Panels
  local right = CreateFrame("Frame", nil, state.root)

  local leftPanel = CreatePanel(state.root, "")
  leftPanel.bg:SetColorTexture(0, 0, 0, 0)
  leftPanel.title:SetText("")
  leftPanel.title:Hide()
  leftPanel.body:SetText("")
  leftPanel.body:Hide()
  if leftPanel._huiBorder then
    leftPanel._huiBorder.top:SetAlpha(0)
    leftPanel._huiBorder.bottom:SetAlpha(0)
    leftPanel._huiBorder.left:SetAlpha(0)
    leftPanel._huiBorder.right:SetAlpha(0)
  end

  local rightTopPanel = CreatePanel(right, "")
  rightTopPanel.bg:SetColorTexture(0, 0, 0, 0)
  rightTopPanel.title:SetText("")
  rightTopPanel.title:Hide()
  rightTopPanel.body:SetText("")
  rightTopPanel.body:Hide()
  if rightTopPanel._huiBorder then
    rightTopPanel._huiBorder.top:SetAlpha(0)
    rightTopPanel._huiBorder.bottom:SetAlpha(0)
    rightTopPanel._huiBorder.left:SetAlpha(0)
    rightTopPanel._huiBorder.right:SetAlpha(0)
  end

  local rightBottomPanel = CreatePanel(right, "")
  rightBottomPanel.bg:SetColorTexture(0, 0, 0, 0)
  rightBottomPanel.title:Hide()
  rightBottomPanel.body:Hide()
  if rightBottomPanel._huiBorder then
    rightBottomPanel._huiBorder.top:SetAlpha(0)
    rightBottomPanel._huiBorder.bottom:SetAlpha(0)
    rightBottomPanel._huiBorder.left:SetAlpha(0)
    rightBottomPanel._huiBorder.right:SetAlpha(0)
  end

  state.panels = {
    left = leftPanel,
    right = right,
    rightTop = rightTopPanel,
    rightBottom = rightBottomPanel,
  }

  -- Pane heading
  state.leftPaneHeadingHost = CreateFrame("Frame", nil, parent)
  state.leftPaneHeadingHost:SetAllPoints(parent)
  if state.leftPaneHeadingHost.EnableMouse then
    state.leftPaneHeadingHost:EnableMouse(false)
  end
  state.leftPaneHeadingHost:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  state.leftPaneHeadingHost:SetFrameLevel((parent:GetFrameLevel() or 1) + PANE_HEADING_LEVEL_BOOST)

  state.leftPaneHeading = state.leftPaneHeadingHost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  state.leftPaneHeading:SetPoint("TOP", state.leftPaneHeadingHost, "TOP", 0, PANE_HEADING_TOP_INSET)
  state.leftPaneHeading:SetJustifyH("CENTER")
  state.leftPaneHeading:SetDrawLayer("OVERLAY", 7)
  ApplyLabelStyle(state.leftPaneHeading, PANE_HEADING_FONT_SIZE, 1.00, 0.82, 0.40)
  state.leftPaneHeading:SetText("")
  state.leftPaneHeading:Hide()

  -- Character overlay: contains all character-pane-only frames.
  -- When hidden, all children are automatically hidden.
  state.characterOverlay = CreateFrame("Frame", nil, parent)
  state.characterOverlay:SetAllPoints(parent)
  state.characterOverlay:EnableMouse(false)
  state.characterOverlay:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  state.characterOverlay:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
  state.characterOverlay:Hide()
  CS._characterOverlay = state.characterOverlay

  state.created = true

  return state.root
end

---------------------------------------------------------------------------
-- Getters
---------------------------------------------------------------------------
function FrameFactory:GetRoot() return self._state.root end
function FrameFactory:GetGradient() return self._state.gradient end
function FrameFactory:GetParent() return self._state.parent end
function FrameFactory:GetTabs() return self._state.tabs end
function FrameFactory:GetPanels() return self._state.panels end
function FrameFactory:GetCharacterOverlay() return self._state.characterOverlay end
function FrameFactory:GetHeadingHost() return self._state.leftPaneHeadingHost end
function FrameFactory:GetHeading() return self._state.leftPaneHeading end
function FrameFactory:IsCreated() return self._state.created == true end

-- Expose constants for other modules
FrameFactory.EXPANDED_WIDTH = EXPANDED_WIDTH
FrameFactory.EXPANDED_HEIGHT = EXPANDED_HEIGHT
FrameFactory.PANE_HEADING_LEVEL_BOOST = PANE_HEADING_LEVEL_BOOST

---------------------------------------------------------------------------
-- Layout constants (moved from Layout.lua, Phase 5)
---------------------------------------------------------------------------
local RETRY_DELAYS            = { 0, 0.05, 0.15 }
local STATS_COLUMN_WIDTH_BONUS = 28
local RIGHT_PANEL_TOP_RAISE   = 38

-- Backfill state fields added in Phase 5 (safe after first /reload cycle).
FrameFactory._state.retryToken = FrameFactory._state.retryToken or 0

---------------------------------------------------------------------------
-- Module-level flags (file-local; reset each /reload intentionally)
---------------------------------------------------------------------------
local _sizeGuardInstalled = false
local _sizeGuardActive    = false
local _dragRegistered     = false

---------------------------------------------------------------------------
-- EnsureApplyState: lazily initialises ephemeral apply-time fields
---------------------------------------------------------------------------
local function EnsureApplyState(state)
  if state.retryToken == nil then state.retryToken = 0 end
  state.metrics = state.metrics or {}
  if not state.hookedParents then
    state.hookedParents = setmetatable({}, { __mode = "k" })
  end
  return state
end

---------------------------------------------------------------------------
-- PresetFrameAttributes: called at PLAYER_LOGIN (before any combat) so the
-- UIPanelLayout attributes are already expanded when CharacterFrame first
-- opens.  WoW's C-level panel system reads these attributes directly —
-- SetSize alone cannot override that read — so pre-setting them here is the
-- only reliable fix for the "opens small during combat" case.
---------------------------------------------------------------------------
function FrameFactory.PresetFrameAttributes()
  local cf = CharacterFrame
  if not (cf and cf.SetAttribute) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local state = FrameFactory._state
  -- Capture true Blizzard originals once, before we overwrite them.
  if not state.blizzardPanelAttributes then
    state.blizzardPanelAttributes = {
      width   = cf:GetAttribute("UIPanelLayout-width"),
      height  = cf:GetAttribute("UIPanelLayout-height"),
      defined = cf:GetAttribute("UIPanelLayout-defined"),
    }
  end
  cf:SetAttribute("UIPanelLayout-width",   EXPANDED_WIDTH)
  cf:SetAttribute("UIPanelLayout-height",  EXPANDED_HEIGHT)
  cf:SetAttribute("UIPanelLayout-defined", true)
end

-- Synchronously enforce expanded size. Called directly from CharacterFrame:OnShow.
-- Skipped during combat lockdown — CharacterFrame:SetSize() is a protected call
-- that WoW blocks from addon code during combat.  PLAYER_REGEN_ENABLED will
-- trigger a layout update that resizes the frame after combat ends.
--
-- NOTE: Both SyncExpandSize (here) and ExpandCharacterFrame (below) install
-- SetSize/SetWidth post-hooks behind the shared _sizeGuardInstalled flag.
-- SyncExpandSize runs from Coordinator's CharacterFrame:OnShow hook (immediate,
-- before Apply).  ExpandCharacterFrame runs from Apply (deferred via retries).
-- Whichever fires first installs the hooks; the other path is a no-op for hooks
-- but still calls SetSize to enforce the expanded dimensions.
function FrameFactory.SyncExpandSize()
  if InCombatLockdown and InCombatLockdown() then return end
  local state = FrameFactory._state
  local parent = (state and state.parent) or CharacterFrame
  if not (parent and parent.SetSize) then return end
  _sizeGuardActive = false
  parent:SetSize(EXPANDED_WIDTH, EXPANDED_HEIGHT)
  _sizeGuardActive = true
  if not _sizeGuardInstalled and hooksecurefunc then
    _sizeGuardInstalled = true
    hooksecurefunc(parent, "SetSize", function(_, w, h)
      if not _sizeGuardActive then return end
      if InCombatLockdown and InCombatLockdown() then return end
      if w < EXPANDED_WIDTH or h < EXPANDED_HEIGHT then
        parent:SetSize(EXPANDED_WIDTH, EXPANDED_HEIGHT)
      end
    end)
    hooksecurefunc(parent, "SetWidth", function(_, w)
      if not _sizeGuardActive then return end
      if InCombatLockdown and InCombatLockdown() then return end
      if w < EXPANDED_WIDTH then parent:SetWidth(EXPANDED_WIDTH) end
    end)
  end
end

---------------------------------------------------------------------------
-- CharacterFrame expansion / restore
---------------------------------------------------------------------------
local function ExpandCharacterFrame(state, parent)
  if not (parent and parent.GetWidth and parent.SetSize) then return end
  if not state.originalFrameSize then
    state.originalFrameSize = {
      w          = parent:GetWidth(),
      h          = parent:GetHeight(),
      panelWidth  = parent.GetAttribute and parent:GetAttribute("UIPanelLayout-width")  or nil,
      panelHeight = parent.GetAttribute and parent:GetAttribute("UIPanelLayout-height") or nil,
    }
  end
  local isTransfer = Utils.IsAccountTransferBuild()
  if not isTransfer and parent.SetAttribute
     and not (InCombatLockdown and InCombatLockdown()) then
    -- Capture Blizzard originals if PresetFrameAttributes didn't already.
    if not state.blizzardPanelAttributes then
      state.blizzardPanelAttributes = {
        width   = parent:GetAttribute("UIPanelLayout-width"),
        height  = parent:GetAttribute("UIPanelLayout-height"),
        defined = parent:GetAttribute("UIPanelLayout-defined"),
      }
    end
    parent:SetAttribute("UIPanelLayout-width",   EXPANDED_WIDTH)
    parent:SetAttribute("UIPanelLayout-height",  EXPANDED_HEIGHT)
    parent:SetAttribute("UIPanelLayout-defined", true)
  end
  _sizeGuardActive = false
  if not (InCombatLockdown and InCombatLockdown()) then
    parent:SetSize(EXPANDED_WIDTH, EXPANDED_HEIGHT)
  end
  _sizeGuardActive = true
  -- ClearAllPoints / SetPoint on CharacterFrame are protected during combat.
  if not (InCombatLockdown and InCombatLockdown()) then
    local db   = NS and NS.GetDB and NS:GetDB() or nil
    local csDB = db and db.charsheet or nil
    if csDB and csDB.frameAnchor and csDB.frameX and csDB.frameY and UIParent then
      parent:ClearAllPoints()
      parent:SetPoint(csDB.frameAnchor, UIParent, csDB.frameAnchor, csDB.frameX, csDB.frameY)
    else
      local leftAbs = parent.GetLeft and parent:GetLeft() or nil
      local topAbs  = parent.GetTop  and parent:GetTop()  or nil
      if leftAbs and topAbs and UIParent then
        parent:ClearAllPoints()
        parent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftAbs, topAbs)
      end
    end
  end
  if not isTransfer and UpdateUIPanelPositions
     and not (InCombatLockdown and InCombatLockdown()) then
    pcall(UpdateUIPanelPositions, parent)
  end
  if not _sizeGuardInstalled and hooksecurefunc then
    _sizeGuardInstalled = true
    hooksecurefunc(parent, "SetSize", function(_, w, h)
      if not _sizeGuardActive then return end
      if InCombatLockdown and InCombatLockdown() then return end
      if w < EXPANDED_WIDTH or h < EXPANDED_HEIGHT then
        parent:SetSize(EXPANDED_WIDTH, EXPANDED_HEIGHT)
      end
    end)
    hooksecurefunc(parent, "SetWidth", function(_, w)
      if not _sizeGuardActive then return end
      if InCombatLockdown and InCombatLockdown() then return end
      if w < EXPANDED_WIDTH then parent:SetWidth(EXPANDED_WIDTH) end
    end)
  end
  local inset = _G and _G.CharacterFrameInset or nil
  if inset then
    if inset.SetAlpha  then inset:SetAlpha(0)        end
    if inset.EnableMouse then inset:EnableMouse(false) end
  end
end

local function RestoreCharacterFrame(state)
  _sizeGuardActive = false
  local parent = (state and state.parent) or CharacterFrame
  local orig   = state and state.originalFrameSize or nil
  local isTransfer = Utils.IsAccountTransferBuild()

  -- Restore UIPanelLayout attributes in all cases (covers pre-set-only path
  -- where frame was never visually expanded but attributes were changed).
  if not isTransfer and parent and parent.SetAttribute then
    local blizzOrig = state and state.blizzardPanelAttributes
    if blizzOrig then
      -- Prefer true Blizzard originals captured before our first SetAttribute.
      if blizzOrig.width  then parent:SetAttribute("UIPanelLayout-width",  blizzOrig.width)  end
      if blizzOrig.height then parent:SetAttribute("UIPanelLayout-height", blizzOrig.height) end
      parent:SetAttribute("UIPanelLayout-defined", blizzOrig.defined or false)
    elseif orig then
      -- Fall back to values captured at first expand (pre-set was not run).
      if orig.panelWidth  then parent:SetAttribute("UIPanelLayout-width",  orig.panelWidth)  end
      if orig.panelHeight then parent:SetAttribute("UIPanelLayout-height", orig.panelHeight) end
    end
  end

  if not (parent and orig and parent.SetSize) then return end
  parent:SetSize(orig.w, orig.h)
  if not isTransfer and UpdateUIPanelPositions then
    pcall(UpdateUIPanelPositions, parent)
  end
  local inset = _G and _G.CharacterFrameInset or nil
  if inset then
    if inset.SetAlpha    then inset:SetAlpha(1)        end
    if inset.EnableMouse then inset:EnableMouse(true)  end
  end
  state.originalFrameSize = nil
end

---------------------------------------------------------------------------
-- Tab secure bindings
---------------------------------------------------------------------------
local function GetNativeTabButton(index)
  local i = tonumber(index)
  if i ~= 1 and i ~= 2 and i ~= 3 then return nil end
  local btn = _G[("CharacterFrameTab%d"):format(i)]
           or _G[("PaperDollFrameTab%d"):format(i)]
  if btn then return btn end
  local tabs = CharacterFrame and CharacterFrame.Tabs
  if tabs and tabs[i] then return tabs[i] end
  return nil
end

local function BindTabToNativeTab(btn, index)
  if not (btn and btn.SetAttribute) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  local nativeTab = GetNativeTabButton(index)
  local name = nativeTab and nativeTab.GetName and nativeTab:GetName() or nil
  if type(name) == "string" and name ~= "" then
    btn._nativeTabName = name
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type",       "macro")
    btn:SetAttribute("macrotext",  "/click " .. name)
    btn:SetAttribute("type1",      "macro")
    btn:SetAttribute("macrotext1", "/click " .. name)
    return true
  end
  btn._nativeTabName = nil
  btn:SetAttribute("useOnKeyDown", nil)
  btn:SetAttribute("type",         nil)
  btn:SetAttribute("macrotext",    nil)
  btn:SetAttribute("type1",        nil)
  btn:SetAttribute("macrotext1",   nil)
  return false
end

local function RefreshTabSecureBindings(tabs)
  if not tabs then return end
  local buttons = { tabs.tabCharacter, tabs.tabReputation, tabs.tabCurrency }
  if Utils.IsAccountTransferBuild() then
    for _, btn in ipairs(buttons) do
      if btn and btn.SetAttribute then
        btn._nativeTabName = nil
        btn:SetAttribute("useOnKeyDown", nil)
        btn:SetAttribute("type",         nil)
        btn:SetAttribute("macrotext",    nil)
        btn:SetAttribute("type1",        nil)
        btn:SetAttribute("macrotext1",   nil)
      end
    end
    return
  end
  local anyFailed = false
  for i, btn in ipairs(buttons) do
    if not BindTabToNativeTab(btn, i) then anyFailed = true end
  end
  if anyFailed and C_Timer and C_Timer.After then
    C_Timer.After(0.5, function()
      if InCombatLockdown and InCombatLockdown() then return end
      for i, btn in ipairs(buttons) do
        if not btn._nativeTabName then BindTabToNativeTab(btn, i) end
      end
    end)
  end
end

---------------------------------------------------------------------------
-- Position save/restore + drag support
---------------------------------------------------------------------------
local function SaveFramePosition(parent)
  local db = NS and NS.GetDB and NS:GetDB() or nil
  local cs = db and db.charsheet or nil
  if not cs then return end
  local point, _, _, x, y = parent:GetPoint(1)
  if point then
    cs.frameAnchor = point
    cs.frameX = math.floor((x or 0) + 0.5)
    cs.frameY = math.floor((y or 0) + 0.5)
  end
end

local function RestoreFramePosition(parent)
  if InCombatLockdown and InCombatLockdown() then return end
  local db = NS and NS.GetDB and NS:GetDB() or nil
  local cs = db and db.charsheet or nil
  if not (cs and cs.frameAnchor and cs.frameX and cs.frameY) then return end
  if not (UIParent and parent.ClearAllPoints) then return end
  parent:ClearAllPoints()
  parent:SetPoint(cs.frameAnchor, UIParent, cs.frameAnchor, cs.frameX, cs.frameY)
end

local function RegisterDragOnFrame(frame, moveTarget)
  if not (frame and frame.EnableMouse) then return end
  frame:EnableMouse(true)
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  frame:SetScript("OnDragStart", function()
    if InCombatLockdown and InCombatLockdown() then return end
    if moveTarget.StartMoving then moveTarget:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function()
    if moveTarget.StopMovingOrSizing then moveTarget:StopMovingOrSizing() end
    SaveFramePosition(moveTarget)
  end)
end

local function ApplyMovableProps(parent)
  -- SetMovable and SetClampedToScreen ARE restricted on CharacterFrame during combat.
  if InCombatLockdown and InCombatLockdown() then return end
  if parent.SetMovable         then parent:SetMovable(true)          end
  if parent.SetClampedToScreen then parent:SetClampedToScreen(true)  end
end

local function EnsureDragSupport(state, parent)
  if not (state and parent) then return end
  ApplyMovableProps(parent)
  RestoreFramePosition(parent)
  if _dragRegistered then return end
  _dragRegistered = true
  RegisterDragOnFrame(state.root, parent)
  local panels = state.panels
  if panels then
    RegisterDragOnFrame(panels.left,     parent)
    RegisterDragOnFrame(panels.right,    parent)
    RegisterDragOnFrame(panels.rightTop, parent)
  end
end

---------------------------------------------------------------------------
-- Layout helpers
---------------------------------------------------------------------------
local function ComputeLeftPanelWidth(root)
  if not root then return 240 end
  local w = math.floor((root:GetWidth() or 0) + 0.5)
  if w <= 0 then return 240 end
  local skinCFGRef = (CS and CS.Skin and CS.Skin.CFG) or {}
  local statsW = math.max(230, (skinCFGRef.BASE_STATS_WIDTH or 230) + STATS_COLUMN_WIDTH_BONUS)
  local gap_lr = 16
  return math.max(240, w - gap_lr - statsW)
end

local function ApplyTabLayout(state)
  local root = state.root
  local tabs = state.tabs
  if not (root and tabs) then return end
  local w = math.floor((root:GetWidth() or 0) + 0.5)
  local h = math.floor((root:GetHeight() or 0) + 0.5)
  if w <= 0 or h <= 0 then return end
  local m = state.metrics or {}
  if m.lastW == w and m.lastH == h then return end
  local skinCFG = (CS and CS.Skin and CS.Skin.CFG) or {}
  local tabW   = skinCFG.STATS_MODE_BUTTON_WIDTH  or 86
  local tabH   = skinCFG.STATS_MODE_BUTTON_HEIGHT or 30
  local tabGap = skinCFG.STATS_MODE_BUTTON_GAP    or 6
  tabs.tabCharacter:ClearAllPoints()
  tabs.tabCharacter:SetPoint("LEFT", tabs, "LEFT", 0, 0)
  tabs.tabCharacter:SetSize(tabW, tabH)
  tabs.tabReputation:ClearAllPoints()
  tabs.tabReputation:SetPoint("LEFT", tabs.tabCharacter, "RIGHT", tabGap, 0)
  tabs.tabReputation:SetSize(tabW, tabH)
  tabs.tabCurrency:ClearAllPoints()
  tabs.tabCurrency:SetPoint("LEFT", tabs.tabReputation, "RIGHT", tabGap, 0)
  tabs.tabCurrency:SetSize(tabW, tabH)
  m.lastW = w
  m.lastH = h
  state.metrics = m
end

local function ApplyAnchors(state)
  local parent = state.parent
  local root   = state.root
  local tabs   = state.tabs
  local panels = state.panels
  if not (parent and root and tabs and panels and panels.right) then return end

  ExpandCharacterFrame(state, parent)

  local Skin = CS and CS.Skin or nil
  if Skin then
    Skin.HideBlizzardChrome()
    Skin.SkinAllSlotButtons()
    Skin.ApplyCustomHeader()
    Skin.ApplyHaraSlotLayout()
    Skin.ApplyHaraModelLayout()
    Skin.StartSlotEnforcer()
  end

  local baseLevel = (parent:GetFrameLevel() or 1)
  root:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  root:SetFrameLevel(baseLevel + 1)
  panels.left:SetFrameLevel(baseLevel + 2)
  panels.right:SetFrameLevel(baseLevel + 12)
  panels.rightTop:SetFrameLevel(baseLevel + 12)
  panels.rightBottom:SetFrameLevel(baseLevel + 12)
  if panels.right.SetClipsChildren    then panels.right:SetClipsChildren(true)    end
  if panels.rightTop.SetClipsChildren then panels.rightTop:SetClipsChildren(true) end

  EnsureDragSupport(state, parent)

  local CFG  = (CS and CS.Skin and CS.Skin.CFG) or {}
  local btnW = CFG.STATS_MODE_BUTTON_WIDTH  or 86
  local btnH = CFG.STATS_MODE_BUTTON_HEIGHT or 30
  local btnGap = CFG.STATS_MODE_BUTTON_GAP  or 6
  local barW = btnW * 3 + btnGap * 2
  tabs:ClearAllPoints()
  tabs:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 22, -1)
  tabs:SetSize(barW, btnH)
  RefreshTabSecureBindings(tabs)
  if Utils.IsAccountTransferBuild() then
    if tabs.Hide then tabs:Hide() end
  else
    if tabs.Show then tabs:Show() end
  end
  if Skin and Skin.ApplyNativeBottomTabSkin then Skin.ApplyNativeBottomTabSkin() end

  panels.left:ClearAllPoints()
  panels.left:SetPoint("TOPLEFT",     root, "TOPLEFT",    8, -40)
  panels.left:SetPoint("BOTTOMLEFT",  root, "BOTTOMLEFT", 8,   8)

  panels.right:ClearAllPoints()
  panels.right:SetPoint("TOPLEFT",     panels.left, "TOPRIGHT",    4, RIGHT_PANEL_TOP_RAISE)
  panels.right:SetPoint("BOTTOMRIGHT", root,         "BOTTOMRIGHT",-4, 8)

  panels.rightTop:ClearAllPoints()
  panels.rightTop:SetPoint("TOPLEFT",     panels.right, "TOPLEFT",     0, 0)
  panels.rightTop:SetPoint("BOTTOMRIGHT", panels.right, "BOTTOMRIGHT", 0, 0)

  panels.rightBottom:ClearAllPoints()
  panels.rightBottom:SetPoint("TOPLEFT",     panels.rightTop, "BOTTOMLEFT",  0, -8)
  panels.rightBottom:SetPoint("BOTTOMRIGHT", panels.right,    "BOTTOMRIGHT", 0,  0)
  panels.rightBottom:Hide()

  FrameFactory.EnsureCharacterEscapeCloseRegistration()
end

---------------------------------------------------------------------------
-- FrameFactory:Apply (moved from Layout:Apply)
---------------------------------------------------------------------------
function FrameFactory:Apply(reason)
  local state = self._state
  EnsureApplyState(state)
  local pm = CS and CS.PaneManager or nil
  local cl = CS and CS.CurrencyLayout or nil

  -- Transfer + native-currency mode: expand frame and show chrome but let
  -- Blizzard own the sub-frame content; do not run the full anchor pass.
  if Utils.IsAccountTransferBuild() and pm and pm:IsNativeCurrencyMode() then
    ExpandCharacterFrame(state, state.parent or CharacterFrame)
    -- ExpandCharacterFrame hides CharacterFrameInset; restore it so Blizzard's
    -- native currency background is visible.
    local inset = _G and _G.CharacterFrameInset or nil
    if inset then
      if inset.SetAlpha   then inset:SetAlpha(1)       end
      if inset.EnableMouse then inset:EnableMouse(true) end
    end
    -- Delegate chrome + skin to PaneManager (it owns ShowBaseChrome).
    if pm then pm:SetActivePane("currency", "ff.apply.nativeCurrency") end
    return false
  end

  if cl and cl.GuardLayoutDuringTransfer("Apply", tostring(reason), "Apply", function()
    self:_ScheduleBoundedApply("Apply.transfer_hidden")
  end) then
    return false
  end

  local root = self:CreateAll(state.parent or CharacterFrame)
  if not root then return false end
  if pm then pm:_EnsureSubFrameHooks() end

  local csDB = NS:GetDB() and NS:GetDB().charsheet
  local scale = csDB and csDB.scale or 1.0
  local parent = state.parent or CharacterFrame
  if parent and parent.SetScale then parent:SetScale(scale) end

  ApplyAnchors(state)

  local w = math.floor((root:GetWidth() or 0) + 0.5)
  local h = math.floor((root:GetHeight() or 0) + 0.5)
  if w <= 0 or h <= 0 then return false end

  state.panels.left:SetWidth(ComputeLeftPanelWidth(state.root))
  ApplyTabLayout(state)

  -- During combat, CombatPanel manages frame visibility.  Avoid SetActivePane
  -- which calls Show/Hide on frames parented to CharacterFrame (blocked by
  -- combat lockdown).  Just show root + gradient so the dark background and
  -- purple overlay are visible; CombatPanel suppresses everything else.
  if InCombatLockdown and InCombatLockdown() then
    if state.root and state.root.Show then state.root:Show() end
    if state.gradient and state.gradient.Show then state.gradient:Show() end
  else
    -- Resolve active pane via PaneManager and delegate full visibility.
    local pmState    = pm and pm._state or nil
    local pendingPane = pmState and pmState.pendingPane or nil
    local activePane  = pmState and (pmState.activePane or "character") or "character"
    if pendingPane == "currency" then
      if pm then pm:SetActivePane("currency", "ff.apply.pending") end
    elseif type(activePane) == "string" then
      if pm then pm:SetActivePane(activePane, "ff.apply.active") end
    else
      if pm then pm:SetActivePaneFromToken(nil, "ff.apply") end
    end
  end

  return true
end

function FrameFactory:_ScheduleBoundedApply(reason)
  local state = self._state
  EnsureApplyState(state)
  state.retryToken = (state.retryToken or 0) + 1
  local myToken = state.retryToken

  local function invoke()
    if myToken ~= state.retryToken then return end
    if not (state.parent and state.parent.IsShown and state.parent:IsShown()) then return end
    self:Apply(reason)
  end

  if not (C_Timer and C_Timer.After) then
    invoke()
    return
  end
  if Utils.IsAccountTransferBuild() then
    C_Timer.After(0, invoke)
    return
  end
  for _, delay in ipairs(RETRY_DELAYS) do
    C_Timer.After(delay, invoke)
  end
end

function FrameFactory:_HookParent(parent)
  local state = self._state
  EnsureApplyState(state)
  if not (parent and parent.HookScript) then return end
  if state.hookedParents[parent] then return end

  parent:HookScript("OnShow", function()
    if Utils.IsAccountTransferBuild() and C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if not (state.parent and state.parent.IsShown and state.parent:IsShown()) then return end
        self:_ScheduleBoundedApply("CharacterFrame.OnShow.deferred")
      end)
      return
    end
    self:_ScheduleBoundedApply("CharacterFrame.OnShow")
  end)

  parent:HookScript("OnHide", function()
    local Skin = CS and CS.Skin or nil
    if Skin and Skin.StopSlotEnforcer then Skin.StopSlotEnforcer() end
  end)

  state.hookedParents[parent] = true
end

function FrameFactory.RestoreCharacterFrameSize()
  RestoreCharacterFrame(FrameFactory._state)
end

-- Thin delegation wrappers so Coordinator/PaneManager can call these
-- without needing a direct reference to PaneManager.
function FrameFactory:_EnsureSubFrameHooks()
  local pm = CS and CS.PaneManager or nil
  if pm and pm._EnsureSubFrameHooks then pm:_EnsureSubFrameHooks() end
end

function FrameFactory:_EnsureBootstrapHooks()
  local pm = CS and CS.PaneManager or nil
  if pm and pm._EnsureBootstrapHooks then pm:_EnsureBootstrapHooks() end
end
