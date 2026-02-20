local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.PaneManager = CS.PaneManager or {}
local PaneManager = CS.PaneManager
local Utils = CS.Utils

---------------------------------------------------------------------------
-- CurrencyLayout accessor (loaded before PaneManager in TOC)
---------------------------------------------------------------------------
local function GetCL()
  return CS and CS.CurrencyLayout or nil
end

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local PENDING_PANE_MAX_RETRIES = 2
local CURRENCY_GUARD_MAX_RETRIES = 1

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
PaneManager._state = PaneManager._state or {
  paneSwitchDepth = 0,
  activePane = "character",
  nativeCurrencyMode = false,
  pendingPane = nil,
  pendingPaneAttempts = 0,
  pendingPaneRetryScheduled = false,
  pendingPaneRetryToken = 0,
  currencyPaneGuardToken = 0,
  originalSubFrameLayout = nil,
  subFrameHookMap = nil,
  subFrameHookedGlobals = false,
  hookBootstrapDone = false,
}

local function EnsureState(self)
  local s = self._state
  if not s.subFrameHookMap then
    s.subFrameHookMap = setmetatable({}, { __mode = "k" })
  end
  if not s.originalSubFrameLayout then
    s.originalSubFrameLayout = setmetatable({}, { __mode = "k" })
  end
  -- nil is a valid runtime sentinel (post-hide, resolved on next show).
  if s.activePane ~= nil and type(s.activePane) ~= "string" then
    s.activePane = "character"
  end
  if s.nativeCurrencyMode ~= true then
    s.nativeCurrencyMode = false
  end
  if type(s.pendingPane) ~= "string" then
    s.pendingPane = nil
  end
  s.pendingPaneAttempts = tonumber(s.pendingPaneAttempts) or 0
  if s.pendingPaneAttempts < 0 then
    s.pendingPaneAttempts = 0
  end
  if s.pendingPaneRetryScheduled ~= true then
    s.pendingPaneRetryScheduled = false
  end
  s.pendingPaneRetryToken = tonumber(s.pendingPaneRetryToken) or 0
  s.currencyPaneGuardToken = tonumber(s.currencyPaneGuardToken) or 0
  return s
end

---------------------------------------------------------------------------
-- Public state queries (replaces direct Layout._state access)
---------------------------------------------------------------------------
function PaneManager:GetActivePane()
  return self._state.activePane or "character"
end

function PaneManager:IsNativeCurrencyMode()
  return self._state.nativeCurrencyMode == true
end

function PaneManager:IsCharacterPaneActive()
  local s = self._state
  if s.nativeCurrencyMode == true then return false end
  local pane = s.activePane
  return pane == nil or pane == "" or pane == "character"
end

---------------------------------------------------------------------------
-- NormalizePane
---------------------------------------------------------------------------
local function NormalizePane(pane)
  local value = type(pane) == "string" and string.lower(pane) or nil
  if value == "tokenframepopup" then
    return nil
  end
  if value and (value:find("currencytransfer", 1, true) or value:find("transfermenu", 1, true)) then
    return nil
  end
  if value == "character" or value == "paperdoll" or value == "paperdollframe" then
    return "character"
  end
  if value == "reputation" or value == "reputationframe" then
    return "reputation"
  end
  if value == "currency"
    or value == "token"
    or value == "tokenframe"
    or value == "currencyframe"
    or value == "characterframetokenframe"
    or value == "tokenframetokenframe"
  then
    return "currency"
  end
  if value and (value:find("tokenframe", 1, true) or value:find("currencyframe", 1, true)) then
    return "currency"
  end
  return nil
end

PaneManager.NormalizePane = NormalizePane

---------------------------------------------------------------------------
-- Character-pane frame visibility (unified show/hide)
--
-- Every visual element that should ONLY appear on the character pane is
-- collected here.  Switching away from character calls HideCharacterPaneFrames();
-- switching to character calls ShowCharacterPaneFrames().  This replaces the
-- scattered per-element hide/show calls that were spread across SetActivePane,
-- the redundancy check, post-pcall recovery, and currency guard callbacks.
---------------------------------------------------------------------------
local function GetCharacterPaneFrames()
  local out = {}
  -- NOTE: CharacterModelScene is intentionally excluded — it is a Blizzard
  -- protected frame and calling Show/Hide on it from addon code during combat
  -- lockdown causes ADDON_ACTION_BLOCKED.  Blizzard's own tab-switching code
  -- manages its visibility; we only manage our own CreateFrame frames here.
  -- Character overlay: parent of MythicPanel, PortalPanel, specPanel, etc.
  local fState = Utils.GetFactoryState()
  local co = fState and fState.characterOverlay or nil
  if co then out[#out + 1] = co end
  -- GearDisplay root (gear item rows, slot info)
  local gear = CS and CS.GearDisplay or nil
  local gearRoot = gear and gear._state and gear._state.root or nil
  if gearRoot then out[#out + 1] = gearRoot end
  -- StatsPanel root (attributes, secondary stats, etc.)
  local sp = CS and CS.StatsPanel or nil
  local spRoot = sp and sp._state and sp._state.root or nil
  if spRoot then out[#out + 1] = spRoot end
  return out
end

local function ShowCharacterPaneFrames()
  for _, frame in ipairs(GetCharacterPaneFrames()) do
    if frame.Show then frame:Show() end
  end
  -- Trigger data refreshes for character sub-components.
  local gear = CS and CS.GearDisplay or nil
  if gear and gear.RequestUpdate then pcall(gear.RequestUpdate, gear, "pane_switch.character") end
  local rp = CS and CS.MythicPanel or nil
  if rp and rp.Update then pcall(rp.Update, rp, "pane_switch.character") end
  local pp = CS and CS.PortalPanel or nil
  if pp and pp.OnShow then pcall(pp.OnShow, pp, "pane_switch.character") end
end

local function HideCharacterPaneFrames()
  for _, frame in ipairs(GetCharacterPaneFrames()) do
    if frame.Hide then frame:Hide() end
  end
  -- Stop tickers for hidden sub-components.
  local rp = CS and CS.MythicPanel or nil
  if rp and rp._StopTicker then pcall(rp._StopTicker, rp) end
end

---------------------------------------------------------------------------
-- Base chrome: root + gradient + close-button styling.
-- These are the shared visual shell shown for ALL custom panes.
-- Root is visible for character/currency, hidden for reputation.
-- Gradient is ALWAYS visible while CharacterFrame is open.
---------------------------------------------------------------------------
local function ShowBaseChrome(pane)
  local fState = Utils.GetFactoryState()
  if not fState then return end
  -- Gradient: always visible while CharacterFrame is open.
  local gradient = fState.gradient
  if gradient and gradient.Show then gradient:Show() end
  -- Root: visible for character + currency (provides dark bg for our panels).
  local root = fState.root
  if root then
    if pane == "character" or pane == "currency" then
      root:Show()
    else
      root:Hide()
    end
  end
  -- Pane heading: "Currency" / "Reputation" / hidden for character.
  local heading = fState.leftPaneHeading
  if heading then
    if pane == "currency" then
      heading:SetText(CURRENCY or "Currency")
      heading:Show()
    elseif pane == "reputation" then
      heading:SetText(REPUTATION or "Reputation")
      heading:Show()
    else
      heading:SetText("")
      heading:Hide()
    end
  end
  -- Close button styling (idempotent, pcall-wrapped for taint safety).
  local Skin = CS and CS.Skin or nil
  if Skin and Skin.ApplyCloseButtonGlyph then pcall(Skin.ApplyCloseButtonGlyph) end
end

local function HideBaseChrome()
  local fState = Utils.GetFactoryState()
  if not fState then return end
  local gradient = fState.gradient
  if gradient and gradient.Hide then gradient:Hide() end
  local root = fState.root
  if root and root.Hide then root:Hide() end
  local heading = fState.leftPaneHeading
  if heading and heading.Hide then heading:SetText("") heading:Hide() end
end

-- Show chrome and character-pane frames/tickers for the given pane.
local function ApplyPaneChrome(pane)
  ShowBaseChrome(pane)
  if pane == "character" then ShowCharacterPaneFrames() else HideCharacterPaneFrames() end
end

---------------------------------------------------------------------------
-- Pane frame map (delegates currency resolution to CurrencyLayout)
---------------------------------------------------------------------------
function PaneManager.BuildPaneFrameMap()
  local cl = GetCL()
  local currencyFrame = cl and cl.GetCurrencyPaneFrame() or nil
  local unique = cl and cl.BuildCurrencyCandidateFrames(currencyFrame) or {}
  local selectedCurrency = nil
  for _, frame in ipairs(unique) do
    if Utils.IsFrameVisible(frame) then
      selectedCurrency = frame
      break
    end
  end
  if not selectedCurrency then
    selectedCurrency = currencyFrame or unique[1]
  end
  return {
    character = _G and _G.PaperDollFrame or nil,
    reputation = _G and _G.ReputationFrame or nil,
    currency = selectedCurrency,
    currencyCandidates = unique,
  }
end

---------------------------------------------------------------------------
-- Sub-frame layout capture / restore
---------------------------------------------------------------------------
local CaptureFrameLayout = CS.CurrencyLayout.CaptureFrameLayout

local function RestoreCapturedSubFrameLayout(state)
  if not (state and state.originalSubFrameLayout) then return end
  for frame, snapshot in pairs(state.originalSubFrameLayout) do
    if frame and snapshot then
      if frame.SetParent and snapshot.parent then frame:SetParent(snapshot.parent) end
      if frame.ClearAllPoints then
        frame:ClearAllPoints()
        local points = snapshot.points or {}
        if #points > 0 then
          for _, pt in ipairs(points) do
            frame:SetPoint(pt.point, pt.rel, pt.relPoint, pt.x, pt.y)
          end
        elseif snapshot.parent and frame.SetAllPoints then
          frame:SetAllPoints(snapshot.parent)
        end
      end
      if frame.SetFrameStrata and snapshot.strata then frame:SetFrameStrata(snapshot.strata) end
      if frame.SetFrameLevel and snapshot.level then frame:SetFrameLevel(snapshot.level) end
    end
  end
  wipe(state.originalSubFrameLayout)
end

---------------------------------------------------------------------------
-- Pane resolution helpers
---------------------------------------------------------------------------
local function ResolveActivePaneFromFrames(frames)
  if type(frames) ~= "table" then return "character" end
  if Utils.IsFrameVisible(frames.reputation) then return "reputation" end
  if Utils.IsFrameVisible(frames.currency) then return "currency" end
  for _, frame in ipairs(frames.currencyCandidates or {}) do
    if Utils.IsFrameVisible(frame) then return "currency" end
  end
  return "character"
end

local function ResolvePaneFromToken(token)
  if type(token) == "string" then return NormalizePane(token) end
  if type(token) == "table" and token.GetName then return NormalizePane(token:GetName()) end
  return nil
end

local function ResolveCurrencyToken(frames)
  local cl = GetCL()
  if cl and cl.ResolveCurrencyToken then return cl.ResolveCurrencyToken(frames) end
  return "TokenFrame"
end

local function ResolveSubFrameTokenForPane(pane, frames)
  local normalized = NormalizePane(pane) or "character"
  if normalized == "reputation" then return "ReputationFrame" end
  if normalized == "currency" then return ResolveCurrencyToken(frames) end
  return "PaperDollFrame"
end

---------------------------------------------------------------------------
-- Sub-frame placement
---------------------------------------------------------------------------
local function NormalizeSubFramePlacement(state, frame)
  if not (state and frame) then return false end
  local fState = Utils.GetFactoryState()
  local panels = fState and fState.panels or nil
  local leftPanel = panels and panels.left or nil
  if not leftPanel then return false end
  CaptureFrameLayout(state, frame)
  if frame.SetParent and frame:GetParent() ~= leftPanel then frame:SetParent(leftPanel) end
  if frame.ClearAllPoints then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -2)
    frame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -2, 2)
  end
  local root = fState and fState.root or nil
  if frame.SetFrameStrata and root then frame:SetFrameStrata(root:GetFrameStrata() or "HIGH") end
  if frame.SetFrameLevel then
    frame:SetFrameLevel(leftPanel.GetFrameLevel and tonumber(leftPanel:GetFrameLevel()) or 2)
  end
  return true
end

local function NormalizeSubFrameFullFrame(state, frame)
  if not (state and frame and CharacterFrame) then return false end
  CaptureFrameLayout(state, frame)
  if frame.SetParent and frame:GetParent() ~= CharacterFrame then frame:SetParent(CharacterFrame) end
  if frame.ClearAllPoints then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
    frame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -8, 44)
  end
  if frame.SetFrameStrata then frame:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH") end
  if frame.SetFrameLevel then frame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 30) end
  if frame.SetAlpha then frame:SetAlpha(1) end
  if frame.EnableMouse then frame:EnableMouse(true) end
  if frame.ScrollBox and frame.ScrollBox.ClearAllPoints and frame.ScrollBox.SetPoint then
    frame.ScrollBox:ClearAllPoints()
    frame.ScrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -34)
    frame.ScrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 0)
  end
  return true
end

---------------------------------------------------------------------------
-- Currency layout delegation (thin wrappers to CurrencyLayout)
---------------------------------------------------------------------------
function PaneManager:_ApplyCurrencyMythicPanelLayering()
  local state = EnsureState(self)
  local cl = GetCL()
  if cl then cl.SetCurrencyMythicPanelLayering(NormalizePane(state.activePane) == "currency") end
end

function PaneManager:_ApplyCurrencySizingDeferred(source)
  if Utils.IsAccountTransferBuild() then return false end
  local cl = GetCL()
  if cl then return cl.ApplyCurrencySizingDeferred(source) end
  return false
end

---------------------------------------------------------------------------
-- Tab visual updates
---------------------------------------------------------------------------
function PaneManager:_UpdatePaneTabsVisual(pane)
  local state = EnsureState(self)
  local normalized = NormalizePane(pane) or state.activePane or "character"
  local fState = Utils.GetFactoryState()
  local tabs = fState and fState.tabs or nil
  if not tabs then return end
  local function Apply(tab, active)
    if not tab then return end
    if tab.SetBackdropColor then
      tab:SetBackdropColor(0.03, 0.02, 0.05, 0.92)
      if active then
        tab:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.95)
      else
        tab:SetBackdropBorderColor(0.24, 0.18, 0.32, 0.95)
      end
    end
    if tab.label then
      if active then
        tab.label:SetTextColor(1.00, 0.82, 0.40, 1)
      else
        tab.label:SetTextColor(0.95, 0.95, 0.95, 1)
      end
    end
  end
  Apply(tabs.tabCharacter, normalized == "character")
  Apply(tabs.tabReputation, normalized == "reputation")
  Apply(tabs.tabCurrency, normalized == "currency")
end

---------------------------------------------------------------------------
-- Hook helpers
---------------------------------------------------------------------------
local function HookScriptOnce(state, frame, hookKey, scriptName, fn)
  if not (state and frame and hookKey and scriptName and type(fn) == "function") then return false end
  if not frame.HookScript then return false end
  local byKey = state.subFrameHookMap[frame]
  if type(byKey) ~= "table" then byKey = {}; state.subFrameHookMap[frame] = byKey end
  if byKey[hookKey] then return false end
  frame:HookScript(scriptName, fn)
  byKey[hookKey] = true
  return true
end

---------------------------------------------------------------------------
-- Pending pane / currency guard scheduling
---------------------------------------------------------------------------
local function ClearPendingPaneState(state)
  if not state then return end
  state.pendingPane = nil
  state.pendingPaneAttempts = 0
  state.pendingPaneRetryScheduled = false
  state.pendingPaneRetryToken = (tonumber(state.pendingPaneRetryToken) or 0) + 1
  state.currencyPaneGuardToken = (tonumber(state.currencyPaneGuardToken) or 0) + 1
end

function PaneManager:_SchedulePendingPaneRetry(pane)
  local state = EnsureState(self)
  if type(pane) ~= "string" or pane == "" or state.pendingPaneRetryScheduled then return false end
  state.pendingPaneRetryScheduled = true
  state.pendingPaneRetryToken = (tonumber(state.pendingPaneRetryToken) or 0) + 1
  local token = state.pendingPaneRetryToken
  local function retry()
    local ls = EnsureState(self)
    if ls.pendingPaneRetryToken ~= token then return end
    ls.pendingPaneRetryScheduled = false
    if ls.pendingPane ~= pane then return end
    if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then return end
    self:SetActivePane(pane, "pending_pane_retry")
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, retry) else retry() end
  return true
end

function PaneManager:_ScheduleCurrencyPaneGuard(_reason)
  if Utils.IsAccountTransferBuild() then return false end
  local state = EnsureState(self)
  local cl = GetCL()
  state.currencyPaneGuardToken = (tonumber(state.currencyPaneGuardToken) or 0) + 1
  local token = state.currencyPaneGuardToken
  local function enforce(attempt)
    local ls = EnsureState(self)
    if ls.currencyPaneGuardToken ~= token then return end
    if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then return end
    local activePane = NormalizePane(ls.activePane) or ResolveActivePaneFromFrames(PaneManager.BuildPaneFrameMap())
    if activePane ~= "currency" then return end
    local frames = PaneManager.BuildPaneFrameMap()
    local activeFrame = frames.currency
    if not activeFrame then
      if attempt < CURRENCY_GUARD_MAX_RETRIES and C_Timer and C_Timer.After then
        C_Timer.After(0, function() enforce(attempt + 1) end)
      end
      return
    end
    self:_ApplyCurrencySizingDeferred("currency_guard." .. tostring(attempt))
    if activeFrame.Show then activeFrame:Show() end
    if cl then cl.ShowCurrencyBackdrop(activeFrame) end
    HideCharacterPaneFrames()
    ShowBaseChrome("currency")
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() enforce(0) end)
  else
    enforce(0)
  end
  return true
end

---------------------------------------------------------------------------
-- SetActivePane (core pane switching)
---------------------------------------------------------------------------
function PaneManager:SetActivePane(pane, reason)
  local cl = GetCL()
  if cl and cl.GuardLayoutDuringTransfer("SetActivePane", tostring(pane), "SetActivePane", function()
    self:SetActivePane(pane, reason or "transfer_hidden")
  end) then
    return false
  end
  local state = EnsureState(self)
  if (state.paneSwitchDepth or 0) > 0 then return false end
  local requestedPane = NormalizePane(pane)
  local frames = PaneManager.BuildPaneFrameMap()
  local normalized = requestedPane
  if not normalized then
    if type(state.pendingPane) == "string" then
      normalized = state.pendingPane
    else
      normalized = ResolveActivePaneFromFrames(frames) or state.activePane or "character"
    end
  end
  if normalized == state.activePane and not state.pendingPane then
    -- Even on redundant pane switch, ensure visibility is correct.
    ApplyPaneChrome(normalized)
    return true
  end
  local fState = Utils.GetFactoryState()

  -- Account-transfer currency mode: Blizzard owns the currency sub-frames,
  -- but we still provide the dark background (root + gradient).
  if Utils.IsAccountTransferBuild() and normalized == "currency" then
    state.nativeCurrencyMode = true
    ClearPendingPaneState(state)
    HideCharacterPaneFrames()
    ShowBaseChrome("currency")
    state.activePane = "currency"
    local Skin = CS and CS.Skin or nil
    if Skin and Skin.ApplyNativeBottomTabSkin then Skin.ApplyNativeBottomTabSkin() end
    return true
  end

  if state.nativeCurrencyMode and normalized ~= "currency" then
    state.nativeCurrencyMode = false
  end

  -- Set activePane BEFORE the pcall so that post-pcall recovery code
  -- (heading, root visibility, gradient) always uses the intended pane,
  -- even if the pcall errors midway through.
  state.activePane = normalized

  state.paneSwitchDepth = (state.paneSwitchDepth or 0) + 1
  local ok, err = pcall(function()
    local activeFrame = nil
    if normalized == "character" then activeFrame = frames.character
    elseif normalized == "reputation" then activeFrame = frames.reputation
    else activeFrame = frames.currency end

    if not activeFrame and normalized ~= "character" then
      if cl then cl.ShowNativeSubFrame(normalized) end
      frames = PaneManager.BuildPaneFrameMap()
      activeFrame = normalized == "reputation" and frames.reputation or frames.currency
    end

    if normalized == "currency" and not activeFrame then
      state.pendingPane = "currency"
      state.pendingPaneAttempts = (tonumber(state.pendingPaneAttempts) or 0) + 1
      state.activePane = "currency"
      local currencyExists = type(frames.currencyCandidates) == "table" and #frames.currencyCandidates > 0
      if state.pendingPaneAttempts >= PENDING_PANE_MAX_RETRIES and not currencyExists then
        ClearPendingPaneState(state)
        normalized = "character"
        activeFrame = frames.character
      else
        self:_UpdatePaneTabsVisual("currency")
        local co = fState and fState.characterOverlay or nil
        if co then co:Hide() end
        self:_SchedulePendingPaneRetry("currency")
        return
      end
    else
      if normalized ~= "currency" or activeFrame then ClearPendingPaneState(state) end
    end

    if not activeFrame and normalized ~= "character" then
      normalized = "character"
      activeFrame = frames.character
    end

    state.activePane = normalized
    local accountTransferBuild = Utils.IsAccountTransferBuild()

    -- Hide all panes first
    if frames.character and frames.character ~= activeFrame and frames.character.Hide then frames.character:Hide() end
    if frames.reputation and frames.reputation ~= activeFrame and frames.reputation.Hide then frames.reputation:Hide() end
    if not accountTransferBuild then
      for _, frame in ipairs(frames.currencyCandidates or {}) do
        if frame and frame ~= activeFrame and frame.Hide then frame:Hide() end
      end
    end

    -- Position and show the active pane
    if activeFrame then
      if normalized == "character" then
        NormalizeSubFramePlacement(state, activeFrame)
      elseif normalized == "currency" then
        if accountTransferBuild or (cl and cl.IsTransferVisible()) then
          if cl then cl.DeferTransferOverlayTopmost(activeFrame) end
        elseif Utils.IsInLockdown() or Utils.IsSecureExecution() then
          self:_ApplyCurrencySizingDeferred("set_active_pane.transfer_deferred")
        else
          if cl then cl.NormalizeCurrencyFrameSafe(state, activeFrame, "set_active_pane." .. tostring(reason or "unknown")) end
        end
      else
        NormalizeSubFrameFullFrame(state, activeFrame)
      end
      if normalized ~= "currency" or not accountTransferBuild then activeFrame:Show() end
      if normalized == "currency" and not accountTransferBuild then
        self:_ScheduleCurrencyPaneGuard("set_active_pane")
      end
    end

    -- Currency backdrop
    if normalized == "currency" and activeFrame then
      if cl then cl.ShowCurrencyBackdrop(activeFrame) end
    else
      if cl then cl.HideCurrencyBackdrop() end
      if not accountTransferBuild and cl then
        cl.SetCurrencyDropdownVisible(frames.currency or activeFrame, false)
      end
    end

    -- Base chrome (root + gradient) and character-pane elements.
    ApplyPaneChrome(normalized)

    if cl then cl.EnsureCurrencyMythicPanelCreateHook() end
    self:_ApplyCurrencyMythicPanelLayering()
  end)

  state.paneSwitchDepth = math.max((state.paneSwitchDepth or 1) - 1, 0)

  -- Ensure visibility is correct even if pcall errored midway.
  local resolvedPane = state.activePane
  ApplyPaneChrome(resolvedPane)

  -- Always update heading, tabs, and skin outside pcall so they run
  -- even if an error occurred midway through the pane switch.
  self:_UpdatePaneTabsVisual(resolvedPane)
  local Skin = CS and CS.Skin or nil
  if Skin and Skin.ApplyNativeBottomTabSkin then Skin.ApplyNativeBottomTabSkin() end
  if not ok and NS and NS.Debug then
    NS:Debug("CharacterSheet subframe manager error:", tostring(reason or "unknown"), err)
  end
  return ok ~= false
end

function PaneManager:SetActivePaneFromToken(token, reason)
  local cl = GetCL()
  if cl and cl.GuardLayoutDuringTransfer("SetActivePaneFromToken", tostring(token), "SetActivePaneFromToken", function()
    self:SetActivePaneFromToken(token, reason or "transfer_hidden")
  end) then
    return false
  end
  local state = EnsureState(self)
  local pane = ResolvePaneFromToken(token)
  if not pane then
    pane = type(state.pendingPane) == "string" and state.pendingPane
      or ResolveActivePaneFromFrames(PaneManager.BuildPaneFrameMap())
      or state.activePane or "character"
  end
  local result = self:SetActivePane(pane, reason)
  if NormalizePane(pane) == "currency" then
    self:_ScheduleCurrencyPaneGuard("set_active_pane_from_token")
  end
  return result
end

function PaneManager:ShowPane(pane, reason)
  local cl = GetCL()
  if cl and cl.GuardLayoutDuringTransfer("ShowPane", tostring(pane), "ShowPane", function()
    self:ShowPane(pane, reason or "transfer_hidden")
  end) then
    return false
  end
  local normalized = NormalizePane(pane) or "character"
  local frames = PaneManager.BuildPaneFrameMap()
  local token = ResolveSubFrameTokenForPane(normalized, frames)
  if type(CharacterFrame_ShowSubFrame) == "function" then
    CharacterFrame_ShowSubFrame(token)
  end
  return self:SetActivePane(normalized, reason or "show_pane")
end

---------------------------------------------------------------------------
-- RestoreSubFrames
---------------------------------------------------------------------------
function PaneManager:RestoreSubFrames()
  local state = EnsureState(self)
  local cl = GetCL()
  state.nativeCurrencyMode = false
  RestoreCapturedSubFrameLayout(state)
  local factory = CS and CS.FrameFactory or nil
  if factory and factory.RestoreCharacterFrameSize then factory:RestoreCharacterFrameSize() end
  ClearPendingPaneState(state)
  local Skin = CS and CS.Skin or nil
  if Skin then
    Skin.RestoreBlizzardChrome()
    Skin.HideCustomHeader()
  end
  state.activePane = "character"
  CS._characterOverlay = nil
  ShowCharacterPaneFrames()
  if cl then cl.EnsureCurrencyMythicPanelCreateHook() end
  self:_ApplyCurrencyMythicPanelLayering()
  self:_UpdatePaneTabsVisual("character")
  if Skin and Skin.ApplyNativeBottomTabSkin then Skin.ApplyNativeBottomTabSkin() end
end

---------------------------------------------------------------------------
-- Hook installation (tab hooks, CharacterFrame_ShowSubFrame, ToggleCharacter)
---------------------------------------------------------------------------
function PaneManager:_HookCustomPaneTabs()
  if Utils.IsAccountTransferBuild() then return end
  local state = EnsureState(self)
  local cl = GetCL()
  local fState = Utils.GetFactoryState()
  local tabs = fState and fState.tabs or nil
  if not tabs then return end
  local function Hook(tab, pane, key)
    if not tab then return end
    tab:EnableMouse(true)
    HookScriptOnce(state, tab, key, "OnClick", function(_, button)
      if button and button ~= "LeftButton" then return end
      if pane == "currency" and type(tab._nativeTabName) == "string" and tab._nativeTabName ~= "" then return end
      if pane == "currency" then
        if cl then cl.ShowNativeSubFrame("currency") end
        self:_ScheduleCurrencyPaneGuard("button")
        return
      end
      if not (cl and cl.ShowNativeSubFrame(pane)) then
        self:SetActivePane(pane, "custom_tab_click.fallback")
      end
    end)
  end
  Hook(tabs.tabCharacter, "character", "custom_character_click")
  Hook(tabs.tabReputation, "reputation", "custom_reputation_click")
  Hook(tabs.tabCurrency, "currency", "custom_currency_click")
end

function PaneManager:_HookBlizzardPaneTabs()
  if Utils.IsAccountTransferBuild() then return end
  local state = EnsureState(self)
  local indexMap = { [1] = "character", [2] = "reputation", [3] = "currency" }
  for i = 1, 8 do
    local tab = _G and _G["CharacterFrameTab" .. i] or nil
    local pane = indexMap[i]
    if tab and pane then
      HookScriptOnce(state, tab, "blizzard_tab_" .. tostring(i), "OnClick", function()
        self:SetActivePane(pane, "CharacterFrameTab" .. tostring(i))
      end)
    end
  end
end

function PaneManager:_EnsureSubFrameHooks()
  local state = EnsureState(self)
  local cl = GetCL()
  self:_HookCustomPaneTabs()
  self:_HookBlizzardPaneTabs()
  if state.subFrameHookedGlobals then return end
  state.subFrameHookedGlobals = true

  if hooksecurefunc and type(CharacterFrame_ShowSubFrame) == "function" then
    hooksecurefunc("CharacterFrame_ShowSubFrame", function(subFrameToken)
      local core = CS and CS.Core or nil
      if core and core._OnShowSubFrame then pcall(core._OnShowSubFrame, core, subFrameToken) end
      if cl and cl.GuardLayoutDuringTransfer("ShowSubFrame.hook", tostring(subFrameToken), "ShowSubFrame.hook", function()
        self:SetActivePaneFromToken(subFrameToken, "CharacterFrame_ShowSubFrame.transfer_hidden")
        if ResolvePaneFromToken(subFrameToken) == "currency" then
          self:_ScheduleCurrencyPaneGuard("CharacterFrame_ShowSubFrame.transfer_hidden")
        end
      end) then
        return
      end
      if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then return end
      self:SetActivePaneFromToken(subFrameToken, "CharacterFrame_ShowSubFrame")
      if ResolvePaneFromToken(subFrameToken) == "currency" then
        self:_ApplyCurrencySizingDeferred("CharacterFrame_ShowSubFrame")
        self:_ScheduleCurrencyPaneGuard("CharacterFrame_ShowSubFrame")
      end
    end)
  end
end

function PaneManager:_EnsureBootstrapHooks()
  local state = EnsureState(self)
  local cl = GetCL()
  self:_EnsureSubFrameHooks()
  if cl then
    cl.EnsureCurrencyMythicPanelCreateHook()
    cl.InstallTransferVisibilityHooks()
  end
  if state.hookBootstrapDone then return end
  state.hookBootstrapDone = true

  if hooksecurefunc and type(ToggleCharacter) == "function" then
    local function dispatchSubModules(reason)
      -- Only dispatch to character-pane modules when on the character pane.
      if not self:IsCharacterPaneActive() then return end
      local gear = CS and CS.GearDisplay or nil
      if gear and gear.OnShow then pcall(gear.OnShow, gear, reason) end
      local stats = CS and CS.StatsPanel or nil
      if stats and stats.OnShow then pcall(stats.OnShow, stats, reason) end
      local right = CS and CS.MythicPanel or nil
      if right and right.OnShow then pcall(right.OnShow, right, reason) end
    end

    hooksecurefunc("ToggleCharacter", function(subFrameToken)
      local factory = CS and CS.FrameFactory or nil
      if cl and cl.GuardLayoutDuringTransfer("ToggleCharacter.hook", tostring(subFrameToken), "ToggleCharacter.hook", function()
        local parent = CharacterFrame
        if not parent then return end
        if factory and factory.CreateAll then factory:CreateAll() end
        if factory and factory._HookParent then factory:_HookParent(parent) end
        if parent.IsShown and parent:IsShown() then
          self:SetActivePaneFromToken(subFrameToken, "ToggleCharacter.transfer_hidden")
          if ResolvePaneFromToken(subFrameToken) == "currency" then
            self:_ScheduleCurrencyPaneGuard("ToggleCharacter.transfer_hidden")
          end
          if factory and factory._ScheduleBoundedApply then
            factory:_ScheduleBoundedApply("ToggleCharacter.transfer_hidden")
          end
          dispatchSubModules("ToggleCharacter.transfer_hidden")
        end
      end) then
        return
      end
      local parent = CharacterFrame
      if not parent then return end
      if factory and factory.CreateAll then factory:CreateAll() end
      if factory and factory._HookParent then factory:_HookParent(parent) end
      if parent.IsShown and parent:IsShown() then
        -- During combat lockdown, Show/Hide on frames parented to CharacterFrame
        -- is blocked by WoW from within the ToggleCharacter secure execution context.
        -- Skip frame visibility management here; PLAYER_REGEN_ENABLED will trigger
        -- a layout update that restores everything once combat ends.
        if Utils.IsInLockdown() then return end
        self:SetActivePaneFromToken(subFrameToken, "ToggleCharacter")
        if Utils.IsAccountTransferBuild() and state.nativeCurrencyMode then
          if factory and factory._ScheduleBoundedApply then
            factory:_ScheduleBoundedApply("ToggleCharacter.nativeCurrency")
          end
          dispatchSubModules("ToggleCharacter.nativeCurrency")
          return
        end
        if ResolvePaneFromToken(subFrameToken) == "currency" then
          self:_ApplyCurrencySizingDeferred("ToggleCharacter")
          self:_ScheduleCurrencyPaneGuard("ToggleCharacter")
        end
        if factory and factory._ScheduleBoundedApply then factory:_ScheduleBoundedApply("ToggleCharacter") end
        dispatchSubModules("ToggleCharacter")
      end
    end)
  end
end

---------------------------------------------------------------------------
-- Lifecycle protocol (called by Coordinator)
---------------------------------------------------------------------------
function PaneManager:OnShow()
  local state = EnsureState(self)
  -- If activePane was cleared on hide, resolve from current Blizzard frame
  -- visibility so IsCharacterPaneActive() returns the right value before
  -- Coordinator dispatches to sub-modules.
  if state.activePane == nil or state.activePane == "" then
    local frames = PaneManager.BuildPaneFrameMap()
    local resolved = ResolveActivePaneFromFrames(frames)
    state.activePane = resolved or "character"
  end
end

function PaneManager:OnHide()
  local state = EnsureState(self)
  ClearPendingPaneState(state)
  state.activePane = nil        -- resolved fresh on next OnShow
  state.nativeCurrencyMode = false
  HideBaseChrome()
  HideCharacterPaneFrames()
end
