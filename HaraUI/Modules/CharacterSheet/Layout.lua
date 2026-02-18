local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.Layout = CS.Layout or {}
local Layout = CS.Layout

local RETRY_DELAYS = { 0, 0.05, 0.15, 0.5 }
local PENDING_PANE_MAX_RETRIES = 2
local CURRENCY_GUARD_MAX_RETRIES = 1
local CURRENCY_INNER_PAD_LEFT = 6
local CURRENCY_INNER_PAD_RIGHT = -6
local CURRENCY_INNER_TOP = -34
local CURRENCY_INNER_BOTTOM = 6
local CURRENCY_DROPDOWN_OFFSET_X = -14
local CURRENCY_DROPDOWN_OFFSET_Y = 26
local CURRENCY_DROPDOWN_NEAR_TRANSFER_GAP_X = -8
local CURRENCY_DROPDOWN_NEAR_TRANSFER_GAP_Y = 0
local CURRENCY_DROPDOWN_LEVEL_BOOST = 50
local CURRENCY_SCROLLBAR_EDGE_X = -6
local CURRENCY_SCROLLBAR_EDGE_TOP = -2
local CURRENCY_SCROLLBAR_EDGE_BOTTOM = 2
local CURRENCY_TRANSFER_POPUP_GAP_X = -10
local CURRENCY_TRANSFER_POPUP_GAP_Y = -1
local CURRENCY_TRANSFER_MENU_GAP_Y = -6
local CURRENCY_TRANSFER_LOG_GAP_Y = -6
local CURRENCY_POPUP_STRATA = "FULLSCREEN_DIALOG"
local CURRENCY_POPUP_LEVEL = 2000
local CURRENCY_DROPDOWN_LIST_LEVEL = 3000
local STATS_COLUMN_WIDTH_BONUS = 28
local RIGHT_PANEL_TOP_RAISE = 38
local PANE_HEADING_TOP_INSET = -8
local PANE_HEADING_FONT_SIZE = 36
local PANE_HEADING_LEVEL_BOOST = 210
-- CharacterFrame expansion to fit two-panel layout (matches Legacy.lua CFG)
local EXPANDED_WIDTH = math.floor(820 * 1.15 + 0.5)   -- ~943
local EXPANDED_HEIGHT = 675

Layout._state = Layout._state or {
  parent = nil,
  root = nil,
  tabs = nil,
  panels = nil,
  created = false,
  hookedParents = nil,
  hookBootstrapDone = false,
  retryToken = 0,
  metrics = nil,
  originalFrameSize = nil,
  subFrameHookMap = nil,
  subFrameHookedGlobals = false,
  paneSwitchDepth = 0,
  activePane = "character",
  nativeCurrencyMode = false,
  pendingPane = nil,
  pendingPaneAttempts = 0,
  pendingPaneRetryScheduled = false,
  pendingPaneRetryToken = 0,
  currencyPaneGuardToken = 0,
  currencySizingToken = 0,
  transferDeferredQueue = nil,
  originalSubFrameLayout = nil,
}

local function IsRefactorEnabled()
  return CS and CS.IsRefactorEnabled and CS:IsRefactorEnabled()
end

local function EnsureState(self)
  local s = self._state
  if not s.hookedParents then
    s.hookedParents = setmetatable({}, { __mode = "k" })
  end
  if not s.subFrameHookMap then
    s.subFrameHookMap = setmetatable({}, { __mode = "k" })
  end
  if not s.originalSubFrameLayout then
    s.originalSubFrameLayout = setmetatable({}, { __mode = "k" })
  end
  if type(s.activePane) ~= "string" then
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
  s.currencySizingToken = tonumber(s.currencySizingToken) or 0
  s.metrics = s.metrics or {}
  s.transferDeferredQueue = s.transferDeferredQueue or {}
  return s
end

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

local function IsFrameVisible(frame)
  return frame and frame.IsShown and frame:IsShown()
end

local _transferFrameHookMap = setmetatable({}, { __mode = "k" })
local _transferVisibilityKnownVisible = false
local _transferVisibleFrameName = nil

local function IsFrameShownSafe(frame)
  if not (frame and frame.IsShown) then
    return false
  end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown == true
end

local function GetFrameNameOrNil(frame)
  if not (frame and frame.GetName) then
    return nil
  end
  local ok, name = pcall(frame.GetName, frame)
  if not ok or type(name) ~= "string" or name == "" then
    return nil
  end
  return name
end

local function BuildTransferFrameCandidates(active)
  return {
    _G and _G.AccountCurrencyTransferFrame or nil,
    _G and _G.CurrencyTransferFrame or nil,
    _G and _G.CurrencyTransferMenu or nil,
    _G and _G.CurrencyTransferLog or nil,
    _G and _G.TokenFramePopup or nil,
    active and active.TokenFramePopup or nil,
  }
end

local function IsTransferVisible(active)
  local seen = setmetatable({}, { __mode = "k" })
  for _, frame in ipairs(BuildTransferFrameCandidates(active)) do
    if frame and not seen[frame] then
      seen[frame] = true
      if IsFrameShownSafe(frame) then
        return true, frame
      end
    end
  end
  return false, nil
end

local function QueueDeferredAfterTransferHide(layout, key, callback)
  if type(callback) ~= "function" then
    return false
  end
  local target = layout or Layout
  local state = EnsureState(target)
  if type(state.transferDeferredQueue) ~= "table" then
    state.transferDeferredQueue = {}
  end
  local token = type(key) == "string" and key ~= "" and key or ("callback." .. tostring(#state.transferDeferredQueue + 1))
  state.transferDeferredQueue[token] = callback
  return true
end

local function FlushDeferredAfterTransferHide(layout, source)
  local target = layout or Layout
  local state = EnsureState(target)
  local queue = state.transferDeferredQueue
  if type(queue) ~= "table" or next(queue) == nil then
    return false
  end
  state.transferDeferredQueue = {}
  local function run()
    for _, callback in pairs(queue) do
      if type(callback) == "function" then
        pcall(callback)
      end
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, run)
  else
    run()
  end
  return true
end

local function InstallTransferVisibilityHooks()
  if C_CurrencyInfo
    and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function"
  then
    return false
  end

  local function HookFrame(frame)
    if not (frame and frame.HookScript) then
      return false
    end
    if _transferFrameHookMap[frame] then
      return false
    end
    frame:HookScript("OnShow", function(self)
      local visible, activeFrame = IsTransferVisible(self)
      if visible and not _transferVisibilityKnownVisible then
        _transferVisibilityKnownVisible = true
        _transferVisibleFrameName = GetFrameNameOrNil(activeFrame) or GetFrameNameOrNil(self) or "<unnamed>"
      elseif visible then
        _transferVisibleFrameName = GetFrameNameOrNil(activeFrame) or _transferVisibleFrameName
      end
    end)
    frame:HookScript("OnHide", function(self)
      local visible = IsTransferVisible(self)
      if not visible then
        _transferVisibilityKnownVisible = false
        _transferVisibleFrameName = nil
        FlushDeferredAfterTransferHide(Layout, "transfer.hide")
        if Layout and Layout._ApplyCurrencySizingDeferred then
          Layout:_ApplyCurrencySizingDeferred("transfer_hide")
        end
      end
    end)
    _transferFrameHookMap[frame] = true
    return true
  end

  for _, frame in ipairs(BuildTransferFrameCandidates()) do
    HookFrame(frame)
  end
end

local function GuardLayoutDuringTransfer(layout, entrypoint, detail, deferredKey, deferredFn)
  local accountTransferBuild = C_CurrencyInfo
    and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function"

  if accountTransferBuild then
    local visible = IsTransferVisible()
    if not visible then
      return false
    end

    return true
  end

  InstallTransferVisibilityHooks()
  local visible = IsTransferVisible()
  if not visible then
    return false
  end

  if type(deferredFn) == "function" then
    QueueDeferredAfterTransferHide(layout, deferredKey or entrypoint, deferredFn)
  end
  return true
end

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

local function EnsureCharacterEscapeCloseRegistration()
  -- Ensure Escape consistently closes Character/Rep/Currency panes.
  if CharacterFrame and CharacterFrame.GetName then
    local ok, name = pcall(CharacterFrame.GetName, CharacterFrame)
    if ok and type(name) == "string" and name ~= "" then
      return EnsureSpecialFrameEntry(name)
    end
  end
  return EnsureSpecialFrameEntry("CharacterFrame")
end

---------------------------------------------------------------------------
-- Currency pane helpers (match Legacy: use native Blizzard frames)
---------------------------------------------------------------------------
local _currencyBackdrop = nil
local NativeGetCurrencyPaneFrame = _G and type(_G.GetCurrencyPaneFrame) == "function" and _G.GetCurrencyPaneFrame or nil

local function HasAccountCurrencyTransfer()
  return C_CurrencyInfo
    and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function"
end

local function IsAccountTransferBuild()
  return HasAccountCurrencyTransfer() == true
end

local function IsAccountCurrencyTransferMode()
  local visible = IsTransferVisible()
  if visible then
    return true
  end
  return IsAccountTransferBuild()
end

local function GetFrameNameSafe(frame)
  if not (frame and frame.GetName) then
    return nil
  end
  local ok, name = pcall(frame.GetName, frame)
  if not ok or type(name) ~= "string" or name == "" then
    return nil
  end
  return name
end

local function IsDescendantOf(frame, ancestor)
  if not frame or not ancestor or not frame.GetParent then
    return false
  end
  local cursor = frame
  while cursor and cursor.GetParent do
    local ok, parent = pcall(cursor.GetParent, cursor)
    if not ok then
      return false
    end
    if parent == ancestor then
      return true
    end
    cursor = parent
  end
  return false
end

local function IsCurrencyTransferAuxFrame(frame)
  if not frame then return false end
  if frame == _G.CurrencyTransferMenu or frame == _G.CurrencyTransferLog or frame == _G.TokenFramePopup then
    return true
  end
  local name = GetFrameNameSafe(frame)
  if not name then return false end
  local lower = string.lower(name)
  if lower:find("currencytransfer", 1, true) then return true end
  if lower:find("transfermenu", 1, true) then return true end
  if lower:find("tokenframepopup", 1, true) then return true end
  return false
end

local function IsLikelyCharacterCurrencyPane(frame, expectedName)
  if not frame then return false end
  if IsFrameForbidden and IsFrameForbidden(frame) then return false end
  if IsCurrencyTransferAuxFrame(frame) then return false end
  if not (frame.SetPoint and frame.ClearAllPoints) then return false end

  local name = GetFrameNameSafe(frame)
  if expectedName and name ~= expectedName then
    local expectedIsToken = expectedName == "TokenFrame"
    local tokenAliasMatch = expectedIsToken and name and name:find("TokenFrame", 1, true)
    if not tokenAliasMatch then
      return false
    end
  end

  if name and (name:find("Transfer", 1, true) or name:find("Popup", 1, true)) then
    return false
  end

  if CharacterFrame and IsDescendantOf(frame, CharacterFrame) then
    return true
  end

  if not name then
    return false
  end
  if name == "CharacterFrameTokenFrame" or name == "CurrencyFrame" then
    return true
  end
  return name:find("TokenFrame", 1, true) ~= nil
end

local function GetCurrencyPaneFrame()
  local token = _G.TokenFrame
  if IsLikelyCharacterCurrencyPane(token, "TokenFrame") then
    return token
  end

  local characterToken = _G.CharacterFrameTokenFrame
  if IsLikelyCharacterCurrencyPane(characterToken, "CharacterFrameTokenFrame") then
    return characterToken
  end

  local currency = _G.CurrencyFrame
  if IsLikelyCharacterCurrencyPane(currency, "CurrencyFrame") then
    return currency
  end

  if NativeGetCurrencyPaneFrame then
    local ok, nativeFrame = pcall(NativeGetCurrencyPaneFrame)
    if ok and IsLikelyCharacterCurrencyPane(nativeFrame) then
      return nativeFrame
    end
  end

  local tokenAlias = _G.TokenFrameTokenFrame
  if IsLikelyCharacterCurrencyPane(tokenAlias, "TokenFrameTokenFrame") then
    return tokenAlias
  end

  return nil
end

local function BuildCurrencyCandidateFrames(resolvedFrame)
  local unique = {}
  local seen = setmetatable({}, { __mode = "k" })
  local function Add(frame, expectedName)
    if not frame or seen[frame] then
      return
    end
    if not IsLikelyCharacterCurrencyPane(frame, expectedName) then
      return
    end
    seen[frame] = true
    unique[#unique + 1] = frame
  end

  Add(_G and _G.TokenFrame, "TokenFrame")
  Add(_G and _G.CharacterFrameTokenFrame, "CharacterFrameTokenFrame")
  Add(_G and _G.CurrencyFrame, "CurrencyFrame")
  Add(_G and _G.TokenFrameTokenFrame, "TokenFrameTokenFrame")
  Add(resolvedFrame)
  return unique
end

local function EnsureCurrencyBackdrop()
  if _currencyBackdrop then return _currencyBackdrop end
  if not CharacterFrame then return nil end
  _currencyBackdrop = CreateFrame("Frame", nil, CharacterFrame, "BackdropTemplate")
  _currencyBackdrop:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  _currencyBackdrop:SetBackdropColor(0.06, 0.02, 0.10, 0.92)
  _currencyBackdrop:SetBackdropBorderColor(0, 0, 0, 0)
  _currencyBackdrop:Hide()
  return _currencyBackdrop
end

local function ShowCurrencyBackdrop(tokenFrame)
  local backdrop = EnsureCurrencyBackdrop()
  if not backdrop or not CharacterFrame then return end
  local anchor = tokenFrame or CharacterFrame
  backdrop:ClearAllPoints()
  if anchor == CharacterFrame then
    backdrop:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
    backdrop:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -8, 44)
  else
    backdrop:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    backdrop:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
  end
  local tokenLevel = tokenFrame and tokenFrame.GetFrameLevel and tokenFrame:GetFrameLevel()
    or ((CharacterFrame:GetFrameLevel() or 1) + 30)
  backdrop:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH")
  backdrop:SetFrameLevel(math.max(1, tokenLevel - 1))
  backdrop:Show()
end

local function HideCurrencyBackdrop()
  if _currencyBackdrop and _currencyBackdrop.Hide then
    _currencyBackdrop:Hide()
  end
end

local function BuildPaneFrameMap()
  local currencyFrame = GetCurrencyPaneFrame()
  local unique = BuildCurrencyCandidateFrames(currencyFrame)

  local selectedCurrency = nil
  for _, frame in ipairs(unique) do
    if IsFrameVisible(frame) then
      selectedCurrency = frame
      break
    end
  end
  if not selectedCurrency then
    selectedCurrency = currencyFrame or unique[1]
  end

  -- No custom fallback — native frame is created by Blizzard when tab is clicked.
  -- selectedCurrency may be nil on first open; the secure tab click will create it.

  return {
    character = _G and _G.PaperDollFrame or nil,
    reputation = _G and _G.ReputationFrame or nil,
    currency = selectedCurrency,
    currencyCandidates = unique,
  }
end

local function CaptureFrameLayout(state, frame)
  if not (state and frame) then
    return
  end
  if state.originalSubFrameLayout[frame] then
    return
  end

  local points = {}
  if frame.GetNumPoints and frame.GetPoint then
    local count = frame:GetNumPoints() or 0
    for i = 1, count do
      local point, rel, relPoint, x, y = frame:GetPoint(i)
      points[#points + 1] = {
        point = point,
        rel = rel,
        relPoint = relPoint,
        x = x,
        y = y,
      }
    end
  end

  state.originalSubFrameLayout[frame] = {
    parent = frame.GetParent and frame:GetParent() or nil,
    strata = frame.GetFrameStrata and frame:GetFrameStrata() or nil,
    level = frame.GetFrameLevel and frame:GetFrameLevel() or nil,
    points = points,
  }
end

local function RestoreCapturedSubFrameLayout(state)
  if not (state and state.originalSubFrameLayout) then
    return
  end

  for frame, snapshot in pairs(state.originalSubFrameLayout) do
    if frame and snapshot then
      if frame.SetParent and snapshot.parent then
        frame:SetParent(snapshot.parent)
      end
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
      if frame.SetFrameStrata and snapshot.strata then
        frame:SetFrameStrata(snapshot.strata)
      end
      if frame.SetFrameLevel and snapshot.level then
        frame:SetFrameLevel(snapshot.level)
      end
    end
  end

  wipe(state.originalSubFrameLayout)
end

local function ResolveActivePaneFromFrames(frames)
  if type(frames) ~= "table" then
    return "character"
  end
  if IsFrameVisible(frames.reputation) then
    return "reputation"
  end
  if IsFrameVisible(frames.currency) then
    return "currency"
  end
  for _, frame in ipairs(frames.currencyCandidates or {}) do
    if IsFrameVisible(frame) then
      return "currency"
    end
  end
  if IsFrameVisible(frames.character) then
    return "character"
  end
  return "character"
end

local function ResolvePaneFromToken(token)
  if type(token) == "string" then
    return NormalizePane(token)
  end
  if type(token) == "table" and token.GetName then
    return NormalizePane(token:GetName())
  end
  return nil
end


local _sizeGuardInstalled = false
local _sizeGuardActive = false
local _currencyMethodHookMap = setmetatable({}, { __mode = "k" })
local _currencyWidthHookMap = setmetatable({}, { __mode = "k" })
local _currencyGlobalHookMap = {}
local _currencyOverlayHookMap = setmetatable({}, { __mode = "k" })
local _rightPanelCreateHookInstalled = false

local function ExpandCharacterFrame(state, parent)
  if not (parent and parent.GetWidth and parent.SetSize) then
    return
  end

  -- Save original size once so we can restore on disable
  if not state.originalFrameSize then
    state.originalFrameSize = {
      w = parent:GetWidth(),
      h = parent:GetHeight(),
      panelWidth = parent.GetAttribute and parent:GetAttribute("UIPanelLayout-width") or nil,
      panelHeight = parent.GetAttribute and parent:GetAttribute("UIPanelLayout-height") or nil,
    }
  end

  -- Avoid writing UIPanelLayout attributes in account-currency-transfer builds.
  -- Those writes can taint panel-managed secure transfer flows.
  if not IsAccountTransferBuild() and parent.SetAttribute then
    parent:SetAttribute("UIPanelLayout-width", EXPANDED_WIDTH)
    parent:SetAttribute("UIPanelLayout-height", EXPANDED_HEIGHT)
    parent:SetAttribute("UIPanelLayout-defined", true)
  end

  _sizeGuardActive = false -- temporarily disable guard while we set size
  parent:SetSize(EXPANDED_WIDTH, EXPANDED_HEIGHT)
  _sizeGuardActive = true

  -- Restore saved position if the user has dragged the frame, otherwise
  -- preserve the left-edge position so width growth extends to the right.
  local db = NS and NS.GetDB and NS:GetDB() or nil
  local csDB = db and db.charsheet or nil
  if csDB and csDB.frameAnchor and csDB.frameX and csDB.frameY
     and UIParent then
    parent:ClearAllPoints()
    parent:SetPoint(csDB.frameAnchor, UIParent, csDB.frameAnchor,
                    csDB.frameX, csDB.frameY)
  else
    local leftAbs = parent.GetLeft and parent:GetLeft() or nil
    local topAbs = parent.GetTop and parent:GetTop() or nil
    if leftAbs and topAbs and UIParent then
      parent:ClearAllPoints()
      parent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftAbs, topAbs)
    end
  end

  -- Avoid panel-manager relayout calls in account transfer builds.
  if not IsAccountTransferBuild() and UpdateUIPanelPositions then
    pcall(UpdateUIPanelPositions, parent)
  end

  -- Hook SetSize/SetWidth/SetHeight to prevent Blizzard from shrinking us back.
  -- In account-transfer builds these hooksecurefunc hooks taint the execution
  -- context when Blizzard's CharacterFrameMixin:UpdateSize() calls SetWidth(),
  -- which propagates through UpdateUIPanelPositions into the CurrencyTransfer
  -- secure flow.  Skip hook installation and re-apply size via Apply() instead.
  if not _sizeGuardInstalled and hooksecurefunc and not IsAccountTransferBuild() then
    _sizeGuardInstalled = true
    hooksecurefunc(parent, "SetSize", function(_, w, h)
      if not _sizeGuardActive then return end
      if not IsRefactorEnabled() then return end
      if w < EXPANDED_WIDTH or h < EXPANDED_HEIGHT then
        parent:SetSize(EXPANDED_WIDTH, EXPANDED_HEIGHT)
      end
    end)
    hooksecurefunc(parent, "SetWidth", function(_, w)
      if not _sizeGuardActive then return end
      if not IsRefactorEnabled() then return end
      if w < EXPANDED_WIDTH then
        parent:SetWidth(EXPANDED_WIDTH)
      end
    end)
  end

  -- Hide the Blizzard inset entirely (our custom panels replace it)
  local inset = _G and _G.CharacterFrameInset or nil
  if inset then
    if inset.SetAlpha then inset:SetAlpha(0) end
    if inset.EnableMouse then inset:EnableMouse(false) end
  end
end

local function RestoreCharacterFrame(state)
  _sizeGuardActive = false
  local parent = state and state.parent or CharacterFrame
  local orig = state and state.originalFrameSize or nil
  if not (parent and orig and parent.SetSize) then
    return
  end
  parent:SetSize(orig.w, orig.h)
  if not IsAccountTransferBuild() and parent.SetAttribute then
    if orig.panelWidth then
      parent:SetAttribute("UIPanelLayout-width", orig.panelWidth)
    end
    if orig.panelHeight then
      parent:SetAttribute("UIPanelLayout-height", orig.panelHeight)
    end
  end
  if not IsAccountTransferBuild() and UpdateUIPanelPositions then
    pcall(UpdateUIPanelPositions, parent)
  end
  -- Re-show the Blizzard inset
  local inset = _G and _G.CharacterFrameInset or nil
  if inset then
    if inset.SetAlpha then inset:SetAlpha(1) end
    if inset.EnableMouse then inset:EnableMouse(true) end
  end
  state.originalFrameSize = nil
end

local function NormalizeSubFramePlacement(state, frame)
  if not (state and frame) then
    return false
  end

  local panels = state.panels
  local leftPanel = panels and panels.left or nil
  if not leftPanel then
    return false
  end

  CaptureFrameLayout(state, frame)

  if frame.SetParent and frame:GetParent() ~= leftPanel then
    frame:SetParent(leftPanel)
  end

  if frame.ClearAllPoints then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -2)
    frame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -2, 2)
  end

  if frame.SetFrameStrata and state.root then
    frame:SetFrameStrata(state.root:GetFrameStrata() or "HIGH")
  end
  if frame.SetFrameLevel then
    local leftLevel = leftPanel.GetFrameLevel and tonumber(leftPanel:GetFrameLevel()) or 2
    frame:SetFrameLevel(leftLevel)
  end

  return true
end

local function HookScriptOnce(state, frame, hookKey, scriptName, fn)
  if not (state and frame and hookKey and scriptName and type(fn) == "function") then
    return false
  end
  if not frame.HookScript then
    return false
  end

  local byKey = state.subFrameHookMap[frame]
  if type(byKey) ~= "table" then
    byKey = {}
    state.subFrameHookMap[frame] = byKey
  end
  if byKey[hookKey] then
    return false
  end

  frame:HookScript(scriptName, fn)
  byKey[hookKey] = true
  return true
end

local function ResolveCurrencyToken(frames)
  if _G and _G.TokenFrame and IsLikelyCharacterCurrencyPane(_G.TokenFrame, "TokenFrame") then
    return "TokenFrame"
  end
  if _G and _G.CharacterFrameTokenFrame and IsLikelyCharacterCurrencyPane(_G.CharacterFrameTokenFrame, "CharacterFrameTokenFrame") then
    return "CharacterFrameTokenFrame"
  end
  if _G and _G.CurrencyFrame and IsLikelyCharacterCurrencyPane(_G.CurrencyFrame, "CurrencyFrame") then
    return "CurrencyFrame"
  end

  local function NameFromFrame(frame)
    if frame and frame.GetName then
      local name = frame:GetName()
      if type(name) == "string" and name ~= "" then
        return name
      end
    end
    return nil
  end

  local resolved = GetCurrencyPaneFrame()
  local resolvedName = NameFromFrame(resolved)
  if resolvedName then
    return resolvedName
  end

  if type(frames) == "table" then
    local selectedName = NameFromFrame(frames.currency)
    if selectedName then
      return selectedName
    end
    for _, frame in ipairs(frames.currencyCandidates or {}) do
      local dynamicName = NameFromFrame(frame)
      if dynamicName then
        return dynamicName
      end
    end
  end

  return "TokenFrame"
end

local function ResolveSubFrameTokenForPane(pane, frames)
  local normalized = NormalizePane(pane) or "character"
  if normalized == "reputation" then
    return "ReputationFrame"
  end
  if normalized == "currency" then
    return ResolveCurrencyToken(frames)
  end
  return "PaperDollFrame"
end

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
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "/click " .. name)
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("macrotext1", "/click " .. name)
    return true
  end
  btn._nativeTabName = nil
  btn:SetAttribute("useOnKeyDown", nil)
  btn:SetAttribute("type", nil)
  btn:SetAttribute("macrotext", nil)
  btn:SetAttribute("type1", nil)
  btn:SetAttribute("macrotext1", nil)
  return false
end

local function RefreshTabSecureBindings(tabs)
  if not tabs then return end
  local buttons = { tabs.tabCharacter, tabs.tabReputation, tabs.tabCurrency }
  if IsAccountTransferBuild() then
    for _, btn in ipairs(buttons) do
      if btn and btn.SetAttribute then
        btn._nativeTabName = nil
        btn:SetAttribute("useOnKeyDown", nil)
        btn:SetAttribute("type", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("macrotext1", nil)
      end
    end
    return
  end
  for i, btn in ipairs(buttons) do
    BindTabToNativeTab(btn, i)
  end
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
  local template = IsAccountTransferBuild()
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

local function UpdateLeftPaneHeading(state, pane)
  if not state then
    return
  end
  local heading = state.leftPaneHeading
  if not heading then
    return
  end
  local normalized = NormalizePane(pane) or NormalizePane(state.activePane) or "character"
  local text = nil
  if normalized == "reputation" then
    text = REPUTATION or "Reputation"
  elseif normalized == "currency" then
    text = CURRENCY or "Currency"
  end

  if not text or text == "" then
    heading:SetText("")
    heading:Hide()
    return
  end

  local anchor = nil
  if normalized == "currency" then
    anchor = state.panels and state.panels.left or nil
  elseif normalized == "reputation" then
    anchor = _G and _G.ReputationFrame or nil
  end
  if not anchor then
    anchor = state.leftPaneHeadingHost or CharacterFrame
  end

  local topAnchor = CharacterFrame or state.leftPaneHeadingHost or anchor
  local xOffset = 0
  if topAnchor == CharacterFrame and anchor and anchor.GetCenter and topAnchor.GetCenter then
    local anchorCenterX = select(1, anchor:GetCenter())
    local frameCenterX = select(1, topAnchor:GetCenter())
    if anchorCenterX and frameCenterX then
      xOffset = anchorCenterX - frameCenterX
    end
  else
    topAnchor = anchor
  end

  heading:ClearAllPoints()
  heading:SetPoint("TOP", topAnchor, "TOP", xOffset, PANE_HEADING_TOP_INSET)
  heading:SetJustifyH("CENTER")
  if heading.SetWidth and anchor and anchor.GetWidth then
    local width = anchor:GetWidth() or 0
    if width > 0 then
      heading:SetWidth(width - 20)
    end
  end
  heading:SetText(text)
  heading:Show()
end

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
  if frame.RegisterForDrag then
    frame:RegisterForDrag("LeftButton")
  end
  frame:SetScript("OnDragStart", function()
    if InCombatLockdown and InCombatLockdown() then return end
    if moveTarget.StartMoving then
      moveTarget:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function()
    if moveTarget.StopMovingOrSizing then
      moveTarget:StopMovingOrSizing()
    end
    SaveFramePosition(moveTarget)
  end)
end

local _dragRegistered = false

local function EnsureDragSupport(state, parent)
  if not (state and parent) then return end
  if parent.SetMovable then
    parent:SetMovable(true)
  end
  if parent.SetClampedToScreen then
    parent:SetClampedToScreen(true)
  end

  RestoreFramePosition(parent)

  if _dragRegistered then return end
  _dragRegistered = true

  -- Register drag on the root overlay and sub-panels so the entire visible
  -- area is draggable.  Child frames with their own mouse handling (buttons,
  -- icons, etc.) naturally intercept clicks before the parent sees them, so
  -- interactive elements keep working.
  RegisterDragOnFrame(state.root, parent)
  local panels = state.panels
  if panels then
    RegisterDragOnFrame(panels.left, parent)
    RegisterDragOnFrame(panels.right, parent)
    RegisterDragOnFrame(panels.rightTop, parent)
  end
end

local function EnsurePaneHeadingOverlay(state, parent)
  if not (state and parent and CreateFrame) then
    return
  end

  local host = state.leftPaneHeadingHost
  if not host then
    host = CreateFrame("Frame", nil, parent)
    if host.EnableMouse then
      host:EnableMouse(false)
    end
    state.leftPaneHeadingHost = host
  elseif host.GetParent and host:GetParent() ~= parent then
    host:SetParent(parent)
  end

  host:ClearAllPoints()
  host:SetAllPoints(parent)
  if host.SetFrameStrata then
    host:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  end
  if host.SetFrameLevel then
    host:SetFrameLevel((parent:GetFrameLevel() or 1) + PANE_HEADING_LEVEL_BOOST)
  end

  local heading = state.leftPaneHeading
  if heading then
    if heading.SetParent and heading:GetParent() ~= host then
      heading:SetParent(host)
    end
  end
end

function Layout:Create(parent)
  if not IsRefactorEnabled() then
    return nil
  end

  local state = EnsureState(self)
  parent = parent or CharacterFrame
  if not parent then
    return nil
  end

  if state.created and state.root then
    if state.parent ~= parent then
      state.parent = parent
      if state.root:GetParent() ~= parent then
        state.root:SetParent(parent)
      end
      state.metrics.anchorsApplied = false
    end
    return state.root
  end

  state.parent = parent
  state.root = CreateFrame("Frame", "HaraUI_CharSheetRoot", parent)
  state.root:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  state.root:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
  state.root:Hide()

  state.root.bg = state.root:CreateTexture(nil, "BACKGROUND")
  SetAllPointsColor(state.root.bg, 0.03, 0.03, 0.04, 0.92)
  CreateBorder(state.root, 1, 1, 1, 0.06)

  -- Tab bar (modeBar): parented to CharacterFrame, positioned below it
  state.tabs = CreateFrame("Frame", nil, parent)
  state.tabs:SetFrameStrata("DIALOG")
  state.tabs:SetFrameLevel((parent:GetFrameLevel() or 1) + 200)

  state.tabs.tabCharacter = CreateTab(state.tabs, "Character", 1)
  state.tabs.tabReputation = CreateTab(state.tabs, "Rep", 2)
  state.tabs.tabCurrency = CreateTab(state.tabs, "Currency", 3)

  local right = CreateFrame("Frame", nil, state.root)

  -- Left panel: transparent container (model + gear text live here)
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

  state.created = true
  state.metrics.anchorsApplied = false

  return state.root
end

function Layout:_UpdatePaneTabsVisual(pane)
  local state = EnsureState(self)
  local normalized = NormalizePane(pane) or state.activePane or "character"
  local tabs = state.tabs
  if not tabs then
    return
  end

  local function Apply(tab, active)
    if not tab then
      return
    end
    if tab.SetBackdropColor then
      tab:SetBackdropColor(0.03, 0.02, 0.05, 0.92)
      if active then
        tab:SetBackdropBorderColor(0.98, 0.64, 0.14, 0.98)
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

local PANE_SUBFRAME_TOKENS = {
  character = { "PaperDollFrame" },
  reputation = { "ReputationFrame" },
  currency = { "TokenFrame", "CharacterFrameTokenFrame", "CurrencyFrame", "TokenFrameTokenFrame" },
}

local function BuildCurrencySubFrameTokens(frames)
  local out = {}
  local seen = {}
  local function Add(token)
    if type(token) ~= "string" or token == "" then
      return
    end
    if seen[token] then
      return
    end
    seen[token] = true
    out[#out + 1] = token
  end

  local resolved = GetCurrencyPaneFrame()
  if resolved and resolved.GetName then
    Add(resolved:GetName())
  end

  if type(frames) == "table" then
    if frames.currency and frames.currency.GetName then
      Add(frames.currency:GetName())
    end
    for _, frame in ipairs(frames.currencyCandidates or {}) do
      if frame and frame.GetName then
        Add(frame:GetName())
      end
    end
  end

  Add("TokenFrame")
  Add("CharacterFrameTokenFrame")
  Add("CurrencyFrame")
  Add("TokenFrameTokenFrame")

  return out
end

local function ShowNativeSubFrame(pane)
  if GuardLayoutDuringTransfer(
    Layout,
    "ShowNativeSubFrame",
    ("pane=%s"):format(tostring(pane)),
    "ShowNativeSubFrame",
    function()
      if not IsTransferVisible() then
        ShowNativeSubFrame(pane)
      end
    end
  ) then
    return false
  end

  if type(CharacterFrame_ShowSubFrame) ~= "function" then
    return false
  end

  if pane == "currency" then
    local frames = BuildPaneFrameMap()
    local tokens = BuildCurrencySubFrameTokens(frames)
    for _, token in ipairs(tokens) do
      if _G[token] or token == "TokenFrame" then
        local ok = pcall(CharacterFrame_ShowSubFrame, token)
        if ok then
          if Layout and Layout._ApplyCurrencySizingDeferred then
            Layout:_ApplyCurrencySizingDeferred("show_native_subframe.currency")
          end
          return true
        end
      end
    end
    return false
  end

  local tokens = PANE_SUBFRAME_TOKENS[pane]
  if not tokens then return false end
  for _, token in ipairs(tokens) do
    local ok = pcall(CharacterFrame_ShowSubFrame, token)
    if ok then return true end
  end
  return false
end

function Layout:_HookCustomPaneTabs()
  if IsAccountTransferBuild() then
    return
  end
  local state = EnsureState(self)
  local tabs = state.tabs
  if not tabs then
    return
  end

  local function Hook(tab, pane, key)
    if not tab then
      return
    end
    tab:EnableMouse(true)
    HookScriptOnce(state, tab, key, "OnClick", function(_, button)
      if button and button ~= "LeftButton" then
        return
      end
      if pane == "currency" and type(tab._nativeTabName) == "string" and tab._nativeTabName ~= "" then
        return
      end
      if pane == "currency" then
        ShowNativeSubFrame("currency")
        if self and self._ScheduleCurrencyPaneGuard then
          self:_ScheduleCurrencyPaneGuard("button")
        end
        return
      end
      local shown = ShowNativeSubFrame(pane)
      if not shown then
        -- Keep a minimal fallback for non-currency panes if native subframe resolution failed.
        self:SetActivePane(pane, "custom_tab_click.fallback")
      end
    end)
  end

  Hook(tabs.tabCharacter, "character", "custom_character_click")
  Hook(tabs.tabReputation, "reputation", "custom_reputation_click")
  Hook(tabs.tabCurrency, "currency", "custom_currency_click")
end

function Layout:_HookBlizzardPaneTabs()
  if IsAccountTransferBuild() then
    return
  end
  local state = EnsureState(self)
  local indexMap = {
    [1] = "character",
    [2] = "reputation",
    [3] = "currency",
  }

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

local function NormalizeSubFrameFullFrame(state, frame)
  if not (state and frame and CharacterFrame) then
    return false
  end

  CaptureFrameLayout(state, frame)

  if frame.SetParent and frame:GetParent() ~= CharacterFrame then
    frame:SetParent(CharacterFrame)
  end

  if frame.ClearAllPoints then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -58)
    frame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -8, 44)
  end

  if frame.SetFrameStrata then
    frame:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH")
  end
  if frame.SetFrameLevel then
    frame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 30)
  end
  if frame.SetAlpha then frame:SetAlpha(1) end
  if frame.EnableMouse then frame:EnableMouse(true) end

  -- Adjust ScrollBox if present (reputation)
  if frame.ScrollBox and frame.ScrollBox.ClearAllPoints and frame.ScrollBox.SetPoint then
    frame.ScrollBox:ClearAllPoints()
    frame.ScrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -34)
    frame.ScrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 0)
  end

  return true
end

local function IsInLockdown()
  return InCombatLockdown and InCombatLockdown()
end

local function IsSecureExecution()
  if type(issecure) ~= "function" then
    return false
  end
  local ok, secure = pcall(issecure)
  return ok and secure == true
end

local function IsProtectedFrameSafe(frame)
  if not frame then
    return false
  end
  if frame.IsProtected then
    local ok, isProtected = pcall(frame.IsProtected, frame)
    if ok and isProtected then
      return true
    end
  end
  return false
end

local function CanMutateFrameLayout(frame)
  if not frame then
    return false
  end
  if IsFrameForbidden and IsFrameForbidden(frame) then
    return false
  end
  if IsProtectedFrameSafe(frame) then
    return false
  end
  return true
end

local function RunCurrencyMutation(fn)
  if type(fn) ~= "function" then
    return false
  end

  if IsInLockdown() then
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if IsInLockdown() then
          return
        end
        pcall(fn)
      end)
    end
    return false
  end

  local ok = pcall(fn)
  return ok
end

local function ForceCurrencyOverlayFrameTopmost(frame, opts)
  if IsAccountTransferBuild() then
    return false
  end
  if not frame then
    return false
  end
  if IsFrameForbidden and IsFrameForbidden(frame) then
    return false
  end
  if not CanMutateFrameLayout(frame) then
    return false
  end
  opts = type(opts) == "table" and opts or nil
  local keepParent = opts and opts.keepParent == true

  return RunCurrencyMutation(function()
    if not keepParent and frame.SetParent and UIParent and frame.GetParent and frame:GetParent() ~= UIParent then
      frame:SetParent(UIParent)
    end
    if frame.SetFrameStrata then
      frame:SetFrameStrata(CURRENCY_POPUP_STRATA)
    end
    if frame.SetFrameLevel then
      frame:SetFrameLevel(CURRENCY_POPUP_LEVEL)
    end
    if frame.SetToplevel then
      frame:SetToplevel(true)
    end
    if frame.Raise then
      frame:Raise()
    end
  end)
end

local function HookCurrencyOverlayOnShow(frame, opts)
  if IsAccountTransferBuild() then
    return false
  end
  if not frame then
    return false
  end
  if IsFrameForbidden and IsFrameForbidden(frame) then
    return false
  end
  if not CanMutateFrameLayout(frame) then
    return false
  end
  if not frame.HookScript then
    return false
  end
  opts = type(opts) == "table" and opts or nil
  local keepParent = opts and opts.keepParent == true
  local existing = _currencyOverlayHookMap[frame]
  if existing then
    if keepParent then
      if type(existing) == "table" then
        existing.keepParent = true
      else
        _currencyOverlayHookMap[frame] = { keepParent = true }
      end
    end
    return false
  end

  frame:HookScript("OnShow", function()
    local config = _currencyOverlayHookMap[frame]

    local function runDeferred()
      if not frame then
        return
      end
      if not IsFrameShownSafe(frame) then
        return
      end
      if IsInLockdown() then
        return
      end
      ForceCurrencyOverlayFrameTopmost(frame, config)
    end

    if C_Timer and C_Timer.After then
      C_Timer.After(0, runDeferred)
    else
      runDeferred()
    end
  end)
  _currencyOverlayHookMap[frame] = { keepParent = keepParent }
  return true
end

local function BuildTransferOverlayFrames(active)
  local list = {}
  local seen = setmetatable({}, { __mode = "k" })
  local function Add(frame)
    if frame and not seen[frame] and not (IsFrameForbidden and IsFrameForbidden(frame)) then
      seen[frame] = true
      list[#list + 1] = frame
    end
  end

  Add(_G and _G.AccountCurrencyTransferFrame or nil)
  Add(_G and _G.CurrencyTransferFrame or nil)
  Add(_G and _G.CurrencyTransferMenu or nil)
  Add(_G and _G.CurrencyTransferLog or nil)
  Add((_G and _G.TokenFramePopup) or (active and active.TokenFramePopup) or nil)
  return list
end

local function RaiseTransferOverlaysTopmost(active, opts)
  if IsAccountTransferBuild() then
    return false
  end
  opts = type(opts) == "table" and opts or nil
  local keepParent = false
  for _, frame in ipairs(BuildTransferOverlayFrames(active)) do
    if IsFrameShownSafe(frame) and CanMutateFrameLayout(frame) then
      HookCurrencyOverlayOnShow(frame, { keepParent = keepParent })
      ForceCurrencyOverlayFrameTopmost(frame, { keepParent = keepParent })
    end
  end
end

local function ForceUIDropDownListsTopmost()
  return false
end

local function HookCurrencyDropdownListLayering(dropdown)
  if not dropdown then
    return false
  end
  return true
end

local function RaiseCurrencyPopupLayers(active, opts)
  if IsAccountTransferBuild() then
    return false
  end
  InstallTransferVisibilityHooks()
  opts = type(opts) == "table" and opts or nil
  local optionsOnly = opts and opts.optionsOnly == true
  local keepParent = opts and opts.keepParent == true
  local seen = setmetatable({}, { __mode = "k" })
  local function Add(list, frame)
    if frame and not seen[frame] and not (IsFrameForbidden and IsFrameForbidden(frame)) then
      seen[frame] = true
      list[#list + 1] = frame
    end
  end

  local optionsFrames = {}
  Add(optionsFrames, _G and _G.TokenFramePopup or nil)
  Add(optionsFrames, _G and _G.CurrencyOptionsFrame or nil)
  Add(optionsFrames, _G and _G.CurrencyOptionsPopup or nil)
  Add(optionsFrames, _G and _G.CurrencyFrameOptionsFrame or nil)

  for _, frame in ipairs(optionsFrames) do
    HookCurrencyOverlayOnShow(frame, { keepParent = keepParent })
    ForceCurrencyOverlayFrameTopmost(frame, { keepParent = keepParent })
  end
  if not optionsOnly then
    RaiseTransferOverlaysTopmost(active, { keepParent = keepParent })
  end
end

local function SetCurrencyRightPanelLayering(active)
  local rightPanel = CS and CS.RightPanel or nil
  local rightRoot = rightPanel and rightPanel._state and rightPanel._state.root or nil
  if not rightRoot then
    return false
  end

  if active then
    if not rightRoot._huiCurrencyLayerSnapshot then
      rightRoot._huiCurrencyLayerSnapshot = {
        strata = rightRoot.GetFrameStrata and rightRoot:GetFrameStrata() or nil,
        level = rightRoot.GetFrameLevel and rightRoot:GetFrameLevel() or nil,
      }
    end
    if rightRoot.SetFrameStrata then
      rightRoot:SetFrameStrata("LOW")
    end
    if rightRoot.SetFrameLevel then
      rightRoot:SetFrameLevel(1)
    end
    return true
  end

  local snapshot = rightRoot._huiCurrencyLayerSnapshot
  if snapshot then
    if rightRoot.SetFrameStrata and snapshot.strata then
      rightRoot:SetFrameStrata(snapshot.strata)
    end
    if rightRoot.SetFrameLevel and snapshot.level then
      rightRoot:SetFrameLevel(snapshot.level)
    end
    rightRoot._huiCurrencyLayerSnapshot = nil
  end
  return true
end

local function DeferTransferOverlayTopmost(active)
  if not (C_Timer and C_Timer.After) then
    return false
  end

  C_Timer.After(0, function()
    local visible = IsTransferVisible(active)
    if not visible then
      return
    end
    RaiseTransferOverlaysTopmost(active, { keepParent = false })
  end)
  return true
end

local function EnsureCurrencyRightPanelCreateHook()
  if _rightPanelCreateHookInstalled then
    return
  end
  local rightPanel = CS and CS.RightPanel or nil
  if not (hooksecurefunc and rightPanel and type(rightPanel.Create) == "function") then
    return
  end

  hooksecurefunc(rightPanel, "Create", function()
    if Layout and Layout._ApplyCurrencyRightPanelLayering then
      Layout:_ApplyCurrencyRightPanelLayering()
    end
  end)
  _rightPanelCreateHookInstalled = true
end

local function AnchorCurrencyChild(child, anchor, leftPad, rightPad, topPad, bottomPad)
  if not (child and anchor and child.ClearAllPoints and child.SetPoint and CanMutateFrameLayout(child)) then
    return false
  end
  child:ClearAllPoints()
  child:SetPoint("TOPLEFT", anchor, "TOPLEFT", leftPad, topPad)
  child:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", rightPad, topPad)
  if type(bottomPad) == "number" then
    child:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", leftPad, bottomPad)
  end
  return true
end

local function BuildCurrencyStretchTargets(active)
  local targets = {}
  local seen = setmetatable({}, { __mode = "k" })

  local function Add(frame, label, kind)
    if not frame or seen[frame] then
      return
    end
    seen[frame] = true
    targets[#targets + 1] = {
      frame = frame,
      label = label,
      kind = kind,
    }
  end

  local scrollFrame = active and active.ScrollFrame or nil
  Add(scrollFrame, "active.ScrollFrame", "scroll")
  if scrollFrame and scrollFrame.GetScrollChild then
    local ok, scrollChild = pcall(scrollFrame.GetScrollChild, scrollFrame)
    if ok then
      Add(scrollChild, "active.ScrollFrame:GetScrollChild()", "scroll_child")
    end
  end

  local scrollBox = active and active.ScrollBox or nil
  Add(scrollBox, "active.ScrollBox", "scroll")
  if scrollBox and scrollBox.GetScrollTarget then
    local ok, scrollTarget = pcall(scrollBox.GetScrollTarget, scrollBox)
    if ok then
      Add(scrollTarget, "active.ScrollBox:GetScrollTarget()", "scroll_child")
    end
  end

  Add(active and active.Inset, "active.Inset", "inset")
  Add(active and active.InsetFrame, "active.InsetFrame", "inset")

  local containerKeys = { "CurrencyContainer", "TokenContainer", "Container", "List" }
  for _, key in ipairs(containerKeys) do
    Add(active and active[key], "active." .. key, "container")
  end

  local categoryKeys = { "CategoryList", "CategoryScrollBox" }
  for _, key in ipairs(categoryKeys) do
    Add(active and active[key], "active." .. key, "category")
  end

  return targets
end

local function ResolveScrollBarForOwner(owner)
  if not owner then
    return nil
  end

  if owner.ScrollBar then
    return owner.ScrollBar
  end
  if owner.scrollBar then
    return owner.scrollBar
  end

  if owner.GetScrollBar then
    local ok, scrollBar = pcall(owner.GetScrollBar, owner)
    if ok and scrollBar then
      return scrollBar
    end
  end

  if owner.GetName and _G then
    local ok, ownerName = pcall(owner.GetName, owner)
    if ok and type(ownerName) == "string" and ownerName ~= "" then
      local byName = _G[ownerName .. "ScrollBar"]
      if byName then
        return byName
      end
    end
  end

  return nil
end

local function BuildCurrencyScrollBarTargets(active)
  local targets = {}
  local seen = setmetatable({}, { __mode = "k" })

  local function Add(scrollBar, anchor, label, topPad, bottomPad)
    if not scrollBar or seen[scrollBar] then
      return
    end
    seen[scrollBar] = true
    targets[#targets + 1] = {
      bar = scrollBar,
      anchor = anchor or active,
      label = label,
      topPad = topPad,
      bottomPad = bottomPad,
    }
  end

  local function AddFromOwner(owner, label, topPad, bottomPad)
    Add(ResolveScrollBarForOwner(owner), owner or active, label, topPad, bottomPad)
  end

  AddFromOwner(active and active.ScrollFrame, "active.ScrollFrame.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  AddFromOwner(active and active.ScrollBox, "active.ScrollBox.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  AddFromOwner(active and active.CategoryScrollBox, "active.CategoryScrollBox.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  AddFromOwner(active and active.CategoryList, "active.CategoryList.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)

  for _, key in ipairs({ "CurrencyContainer", "TokenContainer", "Container", "List" }) do
    local owner = active and active[key] or nil
    AddFromOwner(owner, "active." .. key .. ".ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  end

  local fallbackTop = CURRENCY_INNER_TOP
  local fallbackBottom = CURRENCY_INNER_BOTTOM
  AddFromOwner(active, "active.ScrollBar", fallbackTop, fallbackBottom)
  Add(_G and _G.TokenFrameScrollBar, active, "_G.TokenFrameScrollBar", fallbackTop, fallbackBottom)
  return targets
end

local function PositionCurrencyScrollBars(active, scrollBarTargets)
  for _, entry in ipairs(scrollBarTargets or {}) do
    local scrollBar = entry.bar
    local anchor = entry.anchor or active
    if scrollBar and anchor and scrollBar.ClearAllPoints and scrollBar.SetPoint and CanMutateFrameLayout(scrollBar) then
      scrollBar:ClearAllPoints()
      scrollBar:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", CURRENCY_SCROLLBAR_EDGE_X, entry.topPad or CURRENCY_SCROLLBAR_EDGE_TOP)
      scrollBar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", CURRENCY_SCROLLBAR_EDGE_X, entry.bottomPad or CURRENCY_SCROLLBAR_EDGE_BOTTOM)

      if scrollBar.SetFrameStrata and CharacterFrame and CharacterFrame.GetFrameStrata then
        scrollBar:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH")
      end
      if scrollBar.SetFrameLevel then
        local baseLevel = anchor.GetFrameLevel and tonumber(anchor:GetFrameLevel()) or 1
        scrollBar:SetFrameLevel(math.max(1, baseLevel + 4))
      end
      if scrollBar.Show then
        scrollBar:Show()
      end
    end
  end
end

local function AnchorCurrencyFrame(frame, anchor, leftPad, topPad, rightPad, bottomPad)
  if not (frame and anchor and frame.ClearAllPoints and frame.SetPoint and CanMutateFrameLayout(frame)) then
    return false
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", leftPad, topPad)
  frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", rightPad, bottomPad)
  return true
end

local function ResolveCurrencyListContainer(active, listWidget)
  if not active then
    return nil
  end

  local parent = listWidget and listWidget.GetParent and listWidget:GetParent() or nil
  local candidates = {
    active.Inset,
    active.InsetFrame,
    active.CurrencyContainer,
    active.TokenContainer,
    active.Container,
    active.List,
    parent,
  }

  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= listWidget and IsDescendantOf(candidate, active) then
      return candidate
    end
  end

  if parent and parent ~= listWidget then
    return parent
  end
  return active
end

local function ApplyCurrencySizing(source)
  local state = EnsureState(Layout)
  local leftContainer = state and state.panels and state.panels.left or nil
  local frames = BuildPaneFrameMap()
  local active = frames and frames.currency or nil
  local transferVisible = IsTransferVisible(active)

  if IsAccountTransferBuild() then
    if transferVisible then
      DeferTransferOverlayTopmost(active)
    end

    return false
  end

  if transferVisible or IsInLockdown() or IsSecureExecution() then
    if transferVisible then
      DeferTransferOverlayTopmost(active)
    end
    return false
  end

  if not (leftContainer and active and CanMutateFrameLayout(active)) then
    return false
  end

  AnchorCurrencyFrame(active, leftContainer, 0, 0, 0, 0)

  PositionCurrencyScrollBars(active, BuildCurrencyScrollBarTargets(active))

  return true
end

local function ApplyCurrencySizingDeferred(layout, source)
  local target = layout or Layout
  local state = EnsureState(target)
  state.currencySizingToken = (state.currencySizingToken or 0) + 1
  local token = state.currencySizingToken
  local reason = type(source) == "string" and source ~= "" and source or "currency_sizing"

  local function run(suffix)
    local liveState = EnsureState(target)
    if liveState.currencySizingToken ~= token then
      return
    end
    local marker = suffix and (reason .. "." .. suffix) or reason
    ApplyCurrencySizing(marker)
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() run(nil) end)
    C_Timer.After(0.15, function() run("late") end)
  else
    run(nil)
    run("late")
  end
  return true
end

local function GetCurrencyDropdownFrame(active)
  if active and active.filterDropdown then return active.filterDropdown end
  if active and active.FilterDropdown then return active.FilterDropdown end
  if active and active.filterDropDown then return active.filterDropDown end
  if active and active.FilterDropDown then return active.FilterDropDown end
  if _G and _G.TokenFrameFilterDropdown then return _G.TokenFrameFilterDropdown end
  if _G and _G.TokenFrameFilterDropDown then return _G.TokenFrameFilterDropDown end
  return nil
end

local function HookCurrencyMethodOnce(frame, methodName)
  if not (hooksecurefunc and frame and type(methodName) == "string") then
    return false
  end
  if not CanMutateFrameLayout(frame) then
    return false
  end
  if type(frame[methodName]) ~= "function" then
    return false
  end

  local byMethod = _currencyMethodHookMap[frame]
  if type(byMethod) ~= "table" then
    byMethod = {}
    _currencyMethodHookMap[frame] = byMethod
  end
  if byMethod[methodName] then
    return false
  end

  hooksecurefunc(frame, methodName, function()
    if Layout and Layout._ScheduleCurrencyPaneGuard then
      Layout:_ScheduleCurrencyPaneGuard("currency.method." .. methodName)
    end
  end)
  byMethod[methodName] = true
  return true
end

local function HookCurrencyWidthOnce(frame)
  if not (hooksecurefunc and frame and frame.SetWidth and CanMutateFrameLayout(frame)) then
    return false
  end
  if _currencyWidthHookMap[frame] then
    return false
  end

  _currencyWidthHookMap[frame] = true
  hooksecurefunc(frame, "SetWidth", function()
    if Layout and Layout._ScheduleCurrencyPaneGuard then
      Layout:_ScheduleCurrencyPaneGuard("currency.width")
    end
  end)
  return true
end

local function HookCurrencyGlobalOnce(functionName)
  if not (hooksecurefunc and type(functionName) == "string" and _G and type(_G[functionName]) == "function") then
    return false
  end
  if _currencyGlobalHookMap[functionName] then
    return false
  end

  hooksecurefunc(functionName, function()
    if Layout and Layout._ScheduleCurrencyPaneGuard then
      Layout:_ScheduleCurrencyPaneGuard("currency.global." .. functionName)
    end
  end)
  _currencyGlobalHookMap[functionName] = true
  return true
end

local function InstallCurrencyReflowHooks(active, stretchTargets, scrollBarTargets)
  HookCurrencyGlobalOnce("TokenFrame_Update")
  HookCurrencyGlobalOnce("TokenFrame_UpdateFrame")
  HookCurrencyGlobalOnce("TokenFrame_UpdateLayout")

  for _, methodName in ipairs({ "Update", "UpdateLayout", "Refresh", "Layout" }) do
    HookCurrencyMethodOnce(active, methodName)
  end

  HookCurrencyWidthOnce(active)
  for _, entry in ipairs(stretchTargets or {}) do
    HookCurrencyWidthOnce(entry.frame)
  end
  for _, entry in ipairs(scrollBarTargets or {}) do
    HookCurrencyWidthOnce(entry.bar)
  end
end

local function StretchCurrencyChildren(active, stretchTargets)
  if IsTransferVisible(active) then
    DeferTransferOverlayTopmost(active)
    return
  end

  local inset = active and (active.Inset or active.InsetFrame) or nil
  local scrollAnchor = inset or active
  local primaryScroll = active and (active.ScrollFrame or active.ScrollBox) or nil

  for _, entry in ipairs(stretchTargets or {}) do
    local child = entry.frame
    local kind = entry.kind

    if kind == "inset" then
      AnchorCurrencyChild(child, active, 4, -4, -30, 4)
    elseif kind == "scroll" then
      AnchorCurrencyChild(child, scrollAnchor, CURRENCY_INNER_PAD_LEFT, CURRENCY_INNER_PAD_RIGHT, CURRENCY_INNER_TOP, CURRENCY_INNER_BOTTOM)
    elseif kind == "scroll_child" then
      local parent = primaryScroll or active
      AnchorCurrencyChild(child, parent, 0, 0, 0, 0)
    else
      AnchorCurrencyChild(child, active, CURRENCY_INNER_PAD_LEFT, CURRENCY_INNER_PAD_RIGHT, CURRENCY_INNER_TOP, CURRENCY_INNER_BOTTOM)
    end
  end
end

local function GetCurrencyTransferAnchorFrame(active)
  local log = _G and _G.CurrencyTransferLog or nil
  local menu = _G and _G.CurrencyTransferMenu or nil
  local popup = (_G and _G.TokenFramePopup) or (active and active.TokenFramePopup) or nil

  local function IsShownSafe(frame)
    if not (frame and frame.IsShown) then
      return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown or false
  end

  if IsShownSafe(log) then return log end
  if IsShownSafe(menu) then return menu end
  if IsShownSafe(popup) then return popup end
  return log or menu or popup
end

local function PositionCurrencyDropdown(state, active, leftContainer, transferAnchor)
  local dropdown = GetCurrencyDropdownFrame(active)
  if not dropdown then
    return nil
  end
  if IsTransferVisible(active) then
    DeferTransferOverlayTopmost(active)
    return dropdown
  end

  if IsInLockdown() then
    if C_Timer and C_Timer.After and Layout and Layout._ScheduleCurrencyPaneGuard then
      C_Timer.After(0, function()
        if IsInLockdown() then
          return
        end
        Layout:_ScheduleCurrencyPaneGuard("currency.dropdown.defer")
      end)
    end
    return dropdown
  end

  if not CanMutateFrameLayout(dropdown) then
    return dropdown
  end

  local dropdownParent = leftContainer or (state and state.root) or CharacterFrame
  if dropdownParent and dropdown.SetParent and dropdown.GetParent and dropdown:GetParent() ~= dropdownParent then
    dropdown:SetParent(dropdownParent)
  end

  if dropdown.ClearAllPoints and dropdown.SetPoint then
    dropdown:ClearAllPoints()
    if transferAnchor then
      dropdown:SetPoint("TOPRIGHT", transferAnchor, "TOPLEFT", CURRENCY_DROPDOWN_NEAR_TRANSFER_GAP_X, CURRENCY_DROPDOWN_NEAR_TRANSFER_GAP_Y)
    elseif leftContainer then
      dropdown:SetPoint("TOPRIGHT", leftContainer, "TOPRIGHT", CURRENCY_DROPDOWN_OFFSET_X, CURRENCY_DROPDOWN_OFFSET_Y)
    end
  end

  if dropdown.SetFrameStrata then
    dropdown:SetFrameStrata("DIALOG")
  end
  if dropdown.SetFrameLevel then
    local leftLevel = leftContainer and leftContainer.GetFrameLevel and tonumber(leftContainer:GetFrameLevel()) or 1
    local activeLevel = active and active.GetFrameLevel and tonumber(active:GetFrameLevel()) or leftLevel
    local transferLevel = transferAnchor and transferAnchor.GetFrameLevel and tonumber(transferAnchor:GetFrameLevel()) or 0
    dropdown:SetFrameLevel(math.max(leftLevel + CURRENCY_DROPDOWN_LEVEL_BOOST, activeLevel + CURRENCY_DROPDOWN_LEVEL_BOOST, transferLevel + 1))
  end
  if dropdown.SetToplevel then
    dropdown:SetToplevel(true)
  end
  if dropdown.Raise then
    dropdown:Raise()
  end
  if dropdown.SetAlpha then dropdown:SetAlpha(1) end
  if dropdown.EnableMouse then dropdown:EnableMouse(true) end
  if dropdown.Show then dropdown:Show() end
  HookCurrencyDropdownListLayering(dropdown)
  return dropdown
end

local function PositionCurrencyTransferFrames(active, currencyContainer, dropdown)
  if IsInLockdown() then
    if C_Timer and C_Timer.After and Layout and Layout._ScheduleCurrencyPaneGuard then
      C_Timer.After(0, function()
        if IsInLockdown() then
          return
        end
        Layout:_ScheduleCurrencyPaneGuard("currency.transfer.defer")
      end)
    end
    return
  end

  local function PositionFrame(frame, anchor, point, relPoint, x, y, levelBoost)
    if not frame then
      return false
    end
    if not (anchor and CanMutateFrameLayout(frame)) then
      return false
    end

    if currencyContainer and frame.SetParent and frame.GetParent and frame:GetParent() ~= currencyContainer then
      frame:SetParent(currencyContainer)
    end

    if frame.ClearAllPoints and frame.SetPoint then
      frame:ClearAllPoints()
      frame:SetPoint(point, anchor, relPoint, x, y)
    end

    if frame.SetFrameStrata and CharacterFrame and CharacterFrame.GetFrameStrata then
      frame:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH")
    end
    if frame.SetFrameLevel then
      local baseLevel = anchor.GetFrameLevel and tonumber(anchor:GetFrameLevel()) or 1
      frame:SetFrameLevel(math.max(1, baseLevel + (levelBoost or 8)))
    end
    return true
  end

  local popup = (_G and _G.TokenFramePopup) or (active and active.TokenFramePopup) or nil
  local menu = _G and _G.CurrencyTransferMenu or nil
  local log = _G and _G.CurrencyTransferLog or nil
  local popupAnchor = dropdown or currencyContainer

  PositionFrame(
    popup,
    popupAnchor,
    dropdown and "RIGHT" or "TOPRIGHT",
    dropdown and "LEFT" or "TOPRIGHT",
    dropdown and CURRENCY_TRANSFER_POPUP_GAP_X or CURRENCY_DROPDOWN_OFFSET_X,
    dropdown and CURRENCY_TRANSFER_POPUP_GAP_Y or (CURRENCY_DROPDOWN_OFFSET_Y - 2),
    10
  )

  local menuAnchor = dropdown or popup or currencyContainer
  if menuAnchor then
    PositionFrame(menu, menuAnchor, "TOPRIGHT", "BOTTOMRIGHT", 0, CURRENCY_TRANSFER_MENU_GAP_Y, 10)
  end

  local logAnchor = popup or dropdown or currencyContainer
  if logAnchor then
    PositionFrame(log, logAnchor, "TOPRIGHT", "BOTTOMRIGHT", 0, CURRENCY_TRANSFER_LOG_GAP_Y, 11)
  end
end

local function SetCurrencyDropdownVisible(active, visible)
  if IsTransferVisible(active) then
    return false
  end
  local dropdown = GetCurrencyDropdownFrame(active)
  if not dropdown then
    return false
  end
  if IsProtectedFrameSafe(dropdown) then
    return false
  end
  if visible then
    if dropdown.Show then dropdown:Show() end
  else
    if dropdown.Hide then dropdown:Hide() end
  end
  return true
end

local function NormalizeCurrencyFrameSafe(state, frame, source)
  if not (state and frame and CharacterFrame) then
    return false
  end

  if IsTransferVisible(frame) then
    DeferTransferOverlayTopmost(frame)
    return true
  end

  if GuardLayoutDuringTransfer(
    Layout,
    "NormalizeCurrencyFrameSafe",
    ("source=%s frame=%s"):format(tostring(source), tostring(GetFrameNameOrNil(frame) or "<unnamed>")),
    "NormalizeCurrencyFrameSafe",
    function()
      if Layout and Layout._ScheduleCurrencyPaneGuard then
        Layout:_ScheduleCurrencyPaneGuard("transfer_hidden.normalize")
      end
    end
  ) then
    return false
  end

  local panels = state.panels
  local leftContainer = panels and panels.left or nil
  local rootContainer = state.root
  local currencyContainer = leftContainer or rootContainer or CharacterFrame
  local rightContainer = panels and panels.right or nil
  if not currencyContainer then
    return false
  end

  CaptureFrameLayout(state, frame)

  if IsAccountTransferBuild() then
    RaiseCurrencyPopupLayers(frame, { optionsOnly = true, keepParent = true })

    return true
  end

  if IsInLockdown() or IsSecureExecution() then
    if Layout and Layout._ApplyCurrencySizingDeferred then
      Layout:_ApplyCurrencySizingDeferred((source or "normalize.currency") .. ".deferred")
    end
    return false
  end

  if not CanMutateFrameLayout(frame) then
    return false
  end

  local scrollBarTargets = BuildCurrencyScrollBarTargets(frame)
  if frame.ClearAllPoints and frame.SetPoint then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", currencyContainer, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", currencyContainer, "BOTTOMRIGHT", 0, 0)
  end
  if frame.SetFrameStrata then
    frame:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH")
  end
  if frame.SetFrameLevel then
    local leftLevel = currencyContainer.GetFrameLevel and tonumber(currencyContainer:GetFrameLevel()) or 1
    local rightLevel = rightContainer and rightContainer.GetFrameLevel and tonumber(rightContainer:GetFrameLevel()) or nil
    local targetLevel = leftLevel
    if rightLevel then
      targetLevel = math.min(targetLevel, rightLevel - 1)
    end
    frame:SetFrameLevel(math.max(1, targetLevel))
  end
  if frame.SetAlpha then frame:SetAlpha(1) end
  if frame.EnableMouse then frame:EnableMouse(true) end

  local transferAnchor = GetCurrencyTransferAnchorFrame(frame)
  PositionCurrencyDropdown(state, frame, currencyContainer, transferAnchor)
  PositionCurrencyScrollBars(frame, scrollBarTargets)
  RaiseCurrencyPopupLayers(frame, { optionsOnly = true })
  InstallCurrencyReflowHooks(frame, nil, scrollBarTargets)
  if Layout and Layout._ApplyCurrencySizingDeferred then
    Layout:_ApplyCurrencySizingDeferred(source or "normalize.currency")
  end

  return true
end

function Layout:_ApplyCurrencySizingDeferred(source)
  if IsAccountTransferBuild() then
    return false
  end
  return ApplyCurrencySizingDeferred(self, source)
end

local function ClearPendingPaneState(state)
  if not state then
    return
  end
  state.pendingPane = nil
  state.pendingPaneAttempts = 0
  state.pendingPaneRetryScheduled = false
  state.pendingPaneRetryToken = (tonumber(state.pendingPaneRetryToken) or 0) + 1
  state.currencyPaneGuardToken = (tonumber(state.currencyPaneGuardToken) or 0) + 1
end

function Layout:_SchedulePendingPaneRetry(pane, _reason)
  local state = EnsureState(self)
  if type(pane) ~= "string" or pane == "" then
    return false
  end
  if state.pendingPaneRetryScheduled then
    return false
  end

  state.pendingPaneRetryScheduled = true
  state.pendingPaneRetryToken = (tonumber(state.pendingPaneRetryToken) or 0) + 1
  local token = state.pendingPaneRetryToken

  local function retry()
    local liveState = EnsureState(self)
    if liveState.pendingPaneRetryToken ~= token then
      return
    end
    liveState.pendingPaneRetryScheduled = false
    if liveState.pendingPane ~= pane then
      return
    end
    if not IsRefactorEnabled() then
      return
    end
    if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then
      return
    end
    self:SetActivePane(pane, "pending_pane_retry")
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(0, retry)
  else
    retry()
  end
  return true
end

function Layout:_ScheduleCurrencyPaneGuard(_reason)
  if IsAccountTransferBuild() then
    return false
  end
  local state = EnsureState(self)
  state.currencyPaneGuardToken = (tonumber(state.currencyPaneGuardToken) or 0) + 1
  local token = state.currencyPaneGuardToken

  local function enforce(attempt)
    local liveState = EnsureState(self)
    if liveState.currencyPaneGuardToken ~= token then
      return
    end
    if not IsRefactorEnabled() then
      return
    end
    if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then
      return
    end

    local activePane = NormalizePane(liveState.activePane) or ResolveActivePaneFromFrames(BuildPaneFrameMap())
    if activePane ~= "currency" then
      return
    end

    local frames = BuildPaneFrameMap()
    local activeFrame = frames.currency
    if not activeFrame then
      if attempt < CURRENCY_GUARD_MAX_RETRIES and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          enforce(attempt + 1)
        end)
      end
      return
    end

    self:_ApplyCurrencySizingDeferred("currency_guard." .. tostring(attempt))
    if activeFrame.Show then
      activeFrame:Show()
    end
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      enforce(0)
    end)
  else
    enforce(0)
  end
  return true
end

function Layout:SetActivePane(pane, reason)
  if not IsRefactorEnabled() then
    return false
  end

  if GuardLayoutDuringTransfer(
    self,
    "SetActivePane",
    ("pane=%s reason=%s"):format(tostring(pane), tostring(reason)),
    "SetActivePane",
    function()
      self:SetActivePane(pane, reason or "transfer_hidden")
    end
  ) then
    return false
  end

  local state = EnsureState(self)
  if (state.paneSwitchDepth or 0) > 0 then
    return false
  end

  local requestedPane = NormalizePane(pane)
  local frames = BuildPaneFrameMap()
  local normalized = requestedPane
  if not normalized then
    if type(state.pendingPane) == "string" then
      normalized = state.pendingPane
    else
      normalized = ResolveActivePaneFromFrames(frames) or state.activePane or "character"
    end
  end

  if IsAccountTransferBuild() and normalized == "currency" then
    state.nativeCurrencyMode = true
    ClearPendingPaneState(state)

    local gear = CS and CS.GearDisplay or nil
    local gearRoot = gear and gear._state and gear._state.root or nil
    local specPanel = gear and gear._state and gear._state.specPanel or nil
    if gearRoot and gearRoot.Hide then
      gearRoot:Hide()
    end
    if specPanel and specPanel.Hide then
      specPanel:Hide()
    end

    local statsPanel = CS and CS.StatsPanel or nil
    local spRoot = statsPanel and statsPanel._state and statsPanel._state.root or nil
    if spRoot and spRoot.Hide then
      spRoot:Hide()
    end

    local rightPanel = CS and CS.RightPanel or nil
    local rpRoot = rightPanel and rightPanel._state and rightPanel._state.root or nil
    if rpRoot and rpRoot.Hide then
      rpRoot:Hide()
    end

    if state.root and state.root.Hide then
      state.root:Hide()
    end

    local Skin = CS and CS.Skin or nil
    if Skin and Skin.SetCustomHeaderVisible then
      Skin.SetCustomHeaderVisible(false)
    end

    state.activePane = "currency"
    if Skin and Skin.ApplyNativeBottomTabSkin then
      Skin.ApplyNativeBottomTabSkin()
    end
    return true
  end

  if state.nativeCurrencyMode and normalized ~= "currency" then
    state.nativeCurrencyMode = false
  end

  state.paneSwitchDepth = (state.paneSwitchDepth or 0) + 1
  local ok, err = pcall(function()
    local activeFrame = nil
    if normalized == "character" then
      activeFrame = frames.character
    elseif normalized == "reputation" then
      activeFrame = frames.reputation
    else
      activeFrame = frames.currency
    end

    -- If the target frame wasn't found, try to trigger Blizzard to load it
    if not activeFrame and normalized ~= "character" then
      ShowNativeSubFrame(normalized)
      -- Re-resolve after loading
      frames = BuildPaneFrameMap()
      if normalized == "reputation" then
        activeFrame = frames.reputation
      else
        activeFrame = frames.currency
      end
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
        self:_SchedulePendingPaneRetry("currency", reason)
        return
      end
    else
      if normalized ~= "currency" or activeFrame then
        ClearPendingPaneState(state)
      end
    end

    -- Non-currency pane fallback remains immediate.
    if not activeFrame and normalized ~= "character" then
      normalized = "character"
      activeFrame = frames.character
    end

    state.activePane = normalized

    local accountTransferBuild = IsAccountTransferBuild()

    -- Hide all panes first
    if frames.character and frames.character ~= activeFrame and frames.character.Hide then
      frames.character:Hide()
    end
    if frames.reputation and frames.reputation ~= activeFrame and frames.reputation.Hide then
      frames.reputation:Hide()
    end
    if not accountTransferBuild then
      for _, frame in ipairs(frames.currencyCandidates or {}) do
        if frame and frame ~= activeFrame and frame.Hide then
          frame:Hide()
        end
      end
    end

    -- Position and show the active pane
    if activeFrame then
      if normalized == "character" then
        NormalizeSubFramePlacement(state, activeFrame)
      elseif normalized == "currency" then
        if accountTransferBuild then
          if IsTransferVisible() then
            DeferTransferOverlayTopmost(activeFrame)
          end
        elseif IsTransferVisible() then
          DeferTransferOverlayTopmost(activeFrame)
        elseif IsInLockdown() or IsSecureExecution() then
          self:_ApplyCurrencySizingDeferred("set_active_pane.transfer_deferred")
        else
          NormalizeCurrencyFrameSafe(state, activeFrame, "set_active_pane." .. tostring(reason or "unknown"))
        end
      else
        -- Reputation pane remains full-frame.
        NormalizeSubFrameFullFrame(state, activeFrame)
      end
      if normalized ~= "currency" or not accountTransferBuild then
        activeFrame:Show()
      end
      if normalized == "currency" and not accountTransferBuild then
        self:_ScheduleCurrencyPaneGuard("set_active_pane")
      end
    end

    -- Currency backdrop: show behind native TokenFrame, hide for other panes
    if normalized == "currency" and activeFrame then
      ShowCurrencyBackdrop(activeFrame)
    else
      HideCurrencyBackdrop()
      if not accountTransferBuild then
        SetCurrencyDropdownVisible(frames.currency or activeFrame, false)
      end
    end

    -- Show/hide gear display, spec panel, and stats panel based on pane
    local gear = CS and CS.GearDisplay or nil
    local gearRoot = gear and gear._state and gear._state.root or nil
    local specPanel = gear and gear._state and gear._state.specPanel or nil
    if normalized == "character" then
      if gearRoot then gearRoot:Show() end
      if specPanel then specPanel:Show() end
      if gear and gear.RequestUpdate then
        pcall(gear.RequestUpdate, gear, "pane_switch.character")
      end
    else
      if gearRoot then gearRoot:Hide() end
      if specPanel then specPanel:Hide() end
    end

    -- Hide stats panel + sidebar + root overlay for non-character panes
    local statsPanel = CS and CS.StatsPanel or nil
    local spRoot = statsPanel and statsPanel._state and statsPanel._state.root or nil
    if spRoot then
      if normalized == "character" then
        spRoot:Show()
      else
        spRoot:Hide()
      end
    end

    -- Floating Mythic+ panel must only exist on Character pane.
    local rightPanel = CS and CS.RightPanel or nil
    local rpRoot = rightPanel and rightPanel._state and rightPanel._state.root or nil
    if normalized == "character" then
      if rightPanel and rightPanel.Update then
        pcall(rightPanel.Update, rightPanel, "pane_switch.character")
      end
    else
      if rpRoot and rpRoot.Hide then
        rpRoot:Hide()
      end
      if rightPanel and rightPanel._StopTicker then
        pcall(rightPanel._StopTicker, rightPanel)
      end
    end

    -- Keep root visible for character/currency panes (currency is constrained to left container).
    if state.root then
      if normalized == "character" or normalized == "currency" then
        state.root:Show()
      else
        state.root:Hide()
      end
    end

    -- Show custom header only on the character pane
    local Skin = CS and CS.Skin or nil
    if Skin and Skin.SetCustomHeaderVisible then
      Skin.SetCustomHeaderVisible(normalized == "character")
    end

    EnsureCurrencyRightPanelCreateHook()
    self:_ApplyCurrencyRightPanelLayering()
    self:_UpdatePaneTabsVisual(normalized)
    if Skin and Skin.ApplyNativeBottomTabSkin then
      Skin.ApplyNativeBottomTabSkin()
    end
    UpdateLeftPaneHeading(state, normalized)
  end)

  state.paneSwitchDepth = math.max((state.paneSwitchDepth or 1) - 1, 0)
  if not ok then
    if NS and NS.Debug then
      NS:Debug("CharacterSheet subframe manager error:", tostring(reason or "unknown"), err)
    end
    return false
  end
  return true
end

function Layout:SetActivePaneFromToken(token, reason)
  if GuardLayoutDuringTransfer(
    self,
    "SetActivePaneFromToken",
    ("token=%s reason=%s"):format(tostring(token), tostring(reason)),
    "SetActivePaneFromToken",
    function()
      self:SetActivePaneFromToken(token, reason or "transfer_hidden")
    end
  ) then
    return false
  end

  local function ResolveAndSet()
    local state = EnsureState(self)
    local pane = ResolvePaneFromToken(token)
    if not pane then
      if type(state.pendingPane) == "string" then
        pane = state.pendingPane
      else
        pane = ResolveActivePaneFromFrames(BuildPaneFrameMap())
      end
    end
    if not pane then
      pane = state.activePane or "character"
    end
    local result = self:SetActivePane(pane, reason)
    if NormalizePane(pane) == "currency" then
      self:_ScheduleCurrencyPaneGuard("set_active_pane_from_token")
    end
    return result
  end

  local guards = CS and CS.Guards or nil
  if guards and guards.WithLock then
    local didRun = false
    local result = false
    guards:WithLock("paneSwitch", function()
      didRun = true
      result = ResolveAndSet()
    end)
    if didRun then
      return result
    end
    return false
  end

  return ResolveAndSet()
end

function Layout:ShowPane(pane, reason)
  if GuardLayoutDuringTransfer(
    self,
    "ShowPane",
    ("pane=%s reason=%s"):format(tostring(pane), tostring(reason)),
    "ShowPane",
    function()
      self:ShowPane(pane, reason or "transfer_hidden")
    end
  ) then
    return false
  end

  local normalized = NormalizePane(pane) or "character"
  local frames = BuildPaneFrameMap()
  local token = ResolveSubFrameTokenForPane(normalized, frames)

  if type(CharacterFrame_ShowSubFrame) == "function" then
    CharacterFrame_ShowSubFrame(token)
  end

  return self:SetActivePane(normalized, reason or "show_pane")
end

function Layout:RestoreSubFrames()
  local state = EnsureState(self)
  state.nativeCurrencyMode = false
  RestoreCapturedSubFrameLayout(state)
  RestoreCharacterFrame(state)
  ClearPendingPaneState(state)
  local Skin = CS and CS.Skin or nil
  if Skin then
    Skin.RestoreBlizzardChrome()
    Skin.HideCustomHeader()
  end
  state.activePane = "character"
  UpdateLeftPaneHeading(state, "character")
  EnsureCurrencyRightPanelCreateHook()
  self:_ApplyCurrencyRightPanelLayering()
  self:_UpdatePaneTabsVisual("character")
  if Skin and Skin.ApplyNativeBottomTabSkin then
    Skin.ApplyNativeBottomTabSkin()
  end
end

function Layout:_ApplyCurrencyRightPanelLayering()
  local state = EnsureState(self)
  local pane = NormalizePane(state.activePane)
  SetCurrencyRightPanelLayering(pane == "currency")
end

function Layout:_EnsureSubFrameHooks()
  local state = EnsureState(self)
  self:_HookCustomPaneTabs()
  self:_HookBlizzardPaneTabs()

  if state.subFrameHookedGlobals then
    return
  end
  state.subFrameHookedGlobals = true

  if hooksecurefunc and type(CharacterFrame_ShowSubFrame) == "function" then
    hooksecurefunc("CharacterFrame_ShowSubFrame", function(subFrameToken)
      if not IsRefactorEnabled() then
        return
      end
      if GuardLayoutDuringTransfer(
        self,
        "CharacterFrame_ShowSubFrame.hook",
        ("token=%s"):format(tostring(subFrameToken)),
        "CharacterFrame_ShowSubFrame.hook",
        function()
          self:SetActivePaneFromToken(subFrameToken, "CharacterFrame_ShowSubFrame.transfer_hidden")
          if ResolvePaneFromToken(subFrameToken) == "currency" then
            self:_ScheduleCurrencyPaneGuard("CharacterFrame_ShowSubFrame.transfer_hidden")
          end
        end
      ) then
        return
      end
      if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then
        return
      end
      self:SetActivePaneFromToken(subFrameToken, "CharacterFrame_ShowSubFrame")
      if ResolvePaneFromToken(subFrameToken) == "currency" then
        self:_ApplyCurrencySizingDeferred("CharacterFrame_ShowSubFrame")
        self:_ScheduleCurrencyPaneGuard("CharacterFrame_ShowSubFrame")
      end
    end)
  end
end

local function ApplyAnchors(state)
  local parent = state.parent
  local root = state.root
  local tabs = state.tabs
  local panels = state.panels
  if not (parent and root and tabs and panels and panels.right) then
    return
  end

  -- Widen CharacterFrame to fit two-panel layout
  ExpandCharacterFrame(state, parent)

  -- Hide Blizzard default chrome and skin slot buttons
  local Skin = CS and CS.Skin or nil
  if Skin then
    Skin.HideBlizzardChrome()
    Skin.SkinAllSlotButtons()
    Skin.ApplyCustomHeader()
    Skin.ApplyCloseButtonGlyph()
    Skin.ApplyChonkySlotLayout()
    Skin.ApplyChonkyModelLayout()
    Skin.ApplyCharacterPanelGradient()
    Skin.StartSlotEnforcer()
  end

  -- Strata + frame levels: right container above left, both within CharacterFrame
  local baseLevel = (parent:GetFrameLevel() or 1)
  root:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
  root:SetFrameLevel(baseLevel + 1)
  panels.left:SetFrameLevel(baseLevel + 2)
  panels.right:SetFrameLevel(baseLevel + 12)
  panels.rightTop:SetFrameLevel(baseLevel + 12)
  panels.rightBottom:SetFrameLevel(baseLevel + 12)
  if panels.right.SetClipsChildren then
    panels.right:SetClipsChildren(true)
  end
  if panels.rightTop.SetClipsChildren then
    panels.rightTop:SetClipsChildren(true)
  end

  -- Root fills CharacterFrame content area (name+close button nest inside)
  root:ClearAllPoints()
  root:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
  root:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
  EnsureDragSupport(state, parent)
  EnsurePaneHeadingOverlay(state, parent)

  -- Tab bar (modeBar): positioned BELOW CharacterFrame
  local CFG = (CS and CS.Skin and CS.Skin.CFG) or {}
  local btnW = CFG.STATS_MODE_BUTTON_WIDTH or 86
  local btnH = CFG.STATS_MODE_BUTTON_HEIGHT or 30
  local btnGap = CFG.STATS_MODE_BUTTON_GAP or 6
  local barW = btnW * 3 + btnGap * 2
  tabs:ClearAllPoints()
  tabs:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 22, -1)
  tabs:SetSize(barW, btnH)
  RefreshTabSecureBindings(tabs)
  if IsAccountTransferBuild() then
    if tabs.Hide then
      tabs:Hide()
    end
  else
    if tabs.Show then
      tabs:Show()
    end
  end
  if Skin and Skin.ApplyNativeBottomTabSkin then
    Skin.ApplyNativeBottomTabSkin()
  end

  -- Left panel: top-left of root down to bottom (tabs are outside frame now)
  panels.left:ClearAllPoints()
  panels.left:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -40)
  panels.left:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 8, 8)

  -- Right container: anchored to left's right edge, fills to root right
  panels.right:ClearAllPoints()
  panels.right:SetPoint("TOPLEFT", panels.left, "TOPRIGHT", 4, RIGHT_PANEL_TOP_RAISE)
  panels.right:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -4, 8)

  -- Stats panel: fills entire right container (M+ panel is floating separately)
  panels.rightTop:ClearAllPoints()
  panels.rightTop:SetPoint("TOPLEFT", panels.right, "TOPLEFT", 0, 0)
  panels.rightTop:SetPoint("BOTTOMRIGHT", panels.right, "BOTTOMRIGHT", 0, 0)

  -- RightPanel (M+ dashboard) is now a floating frame outside CharacterFrame,
  -- so the rightBottom placeholder is hidden.
  panels.rightBottom:ClearAllPoints()
  panels.rightBottom:SetPoint("TOPLEFT", panels.rightTop, "BOTTOMLEFT", 0, -8)
  panels.rightBottom:SetPoint("BOTTOMRIGHT", panels.right, "BOTTOMRIGHT", 0, 0)
  panels.rightBottom:Hide()
end

function Layout:Apply(reason)
  if not IsRefactorEnabled() then
    return false
  end

  local state = EnsureState(self)
  if IsAccountTransferBuild() and state.nativeCurrencyMode then
    -- Re-expand CharacterFrame so the custom layout size persists while
    -- Blizzard's native currency UI is active.  This is safe because
    -- Apply() now runs from a single deferred C_Timer.After(0) callback,
    -- well after the panel-manager secure chain has completed.
    ExpandCharacterFrame(state, state.parent or CharacterFrame)
    -- ExpandCharacterFrame hides CharacterFrameInset (HaraUI's custom
    -- panels normally replace it).  In nativeCurrencyMode the custom
    -- panels are hidden so restore the Blizzard inset for the native
    -- currency background.
    local inset = _G and _G.CharacterFrameInset or nil
    if inset then
      if inset.SetAlpha then inset:SetAlpha(1) end
      if inset.EnableMouse then inset:EnableMouse(true) end
    end
    local Skin = CS and CS.Skin or nil
    if Skin and Skin.ApplyNativeBottomTabSkin then
      Skin.ApplyNativeBottomTabSkin()
    end
    return false
  end
  if GuardLayoutDuringTransfer(
    self,
    "Apply",
    ("reason=%s"):format(tostring(reason)),
    "Apply",
    function()
      self:_ScheduleBoundedApply("Apply.transfer_hidden")
    end
  ) then
    return false
  end
  self:_EnsureSubFrameHooks()
  local root = self:Create(state.parent or CharacterFrame)
  if not root then
    return false
  end
  self:_EnsureSubFrameHooks()

  ApplyAnchors(state)

  local w = math.floor((root:GetWidth() or 0) + 0.5)
  local h = math.floor((root:GetHeight() or 0) + 0.5)
  if w <= 0 or h <= 0 then
    return false
  end

  local metrics = state.metrics
  -- Right panel (stats) should be fixed at BASE_STATS_WIDTH (~230px) like Legacy.
  -- Left panel gets everything remaining.
  local skinCFGRef = (CS and CS.Skin and CS.Skin.CFG) or {}
  local statsW = math.max(230, (skinCFGRef.BASE_STATS_WIDTH or 230) + STATS_COLUMN_WIDTH_BONUS)
  local gap_lr = 16  -- total horizontal padding (8 left inset + 4 gap + 4 right inset)
  local leftW = math.max(240, w - gap_lr - statsW)

  -- Set left width; rightTop fills entire right column via anchors
  state.panels.left:SetWidth(leftW)

  if metrics.lastW ~= w or metrics.lastH ~= h then
    local skinCFG = (CS and CS.Skin and CS.Skin.CFG) or {}
    local tabW = skinCFG.STATS_MODE_BUTTON_WIDTH or 86
    local tabH = skinCFG.STATS_MODE_BUTTON_HEIGHT or 30
    local tabGap = skinCFG.STATS_MODE_BUTTON_GAP or 6
    local tabA = state.tabs.tabCharacter
    local tabB = state.tabs.tabReputation
    local tabC = state.tabs.tabCurrency

    tabA:ClearAllPoints()
    tabA:SetPoint("LEFT", state.tabs, "LEFT", 0, 0)
    tabA:SetSize(tabW, tabH)

    tabB:ClearAllPoints()
    tabB:SetPoint("LEFT", tabA, "RIGHT", tabGap, 0)
    tabB:SetSize(tabW, tabH)

    tabC:ClearAllPoints()
    tabC:SetPoint("LEFT", tabB, "RIGHT", tabGap, 0)
    tabC:SetSize(tabW, tabH)

    metrics.lastW = w
    metrics.lastH = h
  end

  state.root:Show()
  if state.pendingPane == "currency" then
    self:SetActivePane("currency", "layout.apply.pending")
  elseif type(state.activePane) == "string" then
    self:SetActivePane(state.activePane, "layout.apply.active")
  else
    self:SetActivePaneFromToken(nil, "layout.apply")
  end

  return true
end

function Layout:_ScheduleBoundedApply(reason)
  local state = EnsureState(self)
  state.retryToken = (state.retryToken or 0) + 1
  local myToken = state.retryToken

  local function invoke()
    if not IsRefactorEnabled() then
      return
    end
    if myToken ~= state.retryToken then
      return
    end
    if not (state.parent and state.parent.IsShown and state.parent:IsShown()) then
      return
    end
    self:Apply(reason)
  end

  if not (C_Timer and C_Timer.After) then
    invoke()
    return
  end

  -- In account transfer builds use a single deferred invoke to minimise
  -- the insecure timer-callback footprint.  Legacy.lua uses one
  -- C_Timer.After(0) and avoids taint; match that pattern here.
  if IsAccountTransferBuild() then

    C_Timer.After(0, invoke)
    return
  end

  for _, delay in ipairs(RETRY_DELAYS) do

    C_Timer.After(delay, invoke)
  end
end

function Layout:_HookParent(parent)
  local state = EnsureState(self)
  if not parent or not parent.HookScript then
    return
  end
  if state.hookedParents[parent] then
    return
  end
  parent:HookScript("OnShow", function()
    if not IsRefactorEnabled() then
      return
    end
    -- In account transfer builds, defer all work so zero insecure Lua
    -- executes synchronously during CharacterFrame:Show() inside the
    -- panel-manager secure chain.  Matches Legacy.lua's C_Timer.After(0)
    -- deferral pattern that avoids tainting the currency-transfer flow.
    if IsAccountTransferBuild() and C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if not IsRefactorEnabled() then return end
        if not (state.parent and state.parent.IsShown and state.parent:IsShown()) then return end
        self:_ScheduleBoundedApply("CharacterFrame.OnShow.deferred")
      end)
      return
    end
    self:_ScheduleBoundedApply("CharacterFrame.OnShow")
  end)
  parent:HookScript("OnHide", function()
    if state.root then
      state.root:Hide()
    end
    local rightPanel = CS and CS.RightPanel or nil
    local rpRoot = rightPanel and rightPanel._state and rightPanel._state.root or nil
    if rpRoot and rpRoot.Hide then
      rpRoot:Hide()
    end
    if rightPanel and rightPanel._StopTicker then
      pcall(rightPanel._StopTicker, rightPanel)
    end
    local Skin = CS and CS.Skin or nil
    if Skin and Skin.StopSlotEnforcer then
      Skin.StopSlotEnforcer()
    end
    if Skin and Skin.HideCharacterPanelGradient then
      Skin.HideCharacterPanelGradient()
    end
  end)
  state.hookedParents[parent] = true
end

function Layout:_EnsureBootstrapHooks()
  local state = EnsureState(self)
  self:_EnsureSubFrameHooks()
  EnsureCurrencyRightPanelCreateHook()
  EnsureCharacterEscapeCloseRegistration()
  InstallTransferVisibilityHooks()
  if state.hookBootstrapDone then
    return
  end
  state.hookBootstrapDone = true

  if hooksecurefunc and type(ToggleCharacter) == "function" then
    hooksecurefunc("ToggleCharacter", function(subFrameToken)
      if not IsRefactorEnabled() then
        return
      end
      if GuardLayoutDuringTransfer(
        self,
        "ToggleCharacter.hook",
        ("token=%s"):format(tostring(subFrameToken)),
        "ToggleCharacter.hook",
        function()
          local parent = CharacterFrame
          if not parent then
            return
          end
          self:Create(parent)
          self:_HookParent(parent)
          if parent.IsShown and parent:IsShown() then
            self:SetActivePaneFromToken(subFrameToken, "ToggleCharacter.transfer_hidden")
            if ResolvePaneFromToken(subFrameToken) == "currency" then
              self:_ScheduleCurrencyPaneGuard("ToggleCharacter.transfer_hidden")
            end
            self:_ScheduleBoundedApply("ToggleCharacter.transfer_hidden")
          end
        end
      ) then
        return
      end
      local parent = CharacterFrame
      if not parent then
        return
      end
      self:Create(parent)
      self:_HookParent(parent)
      if parent.IsShown and parent:IsShown() then
        self:SetActivePaneFromToken(subFrameToken, "ToggleCharacter")
        -- Once nativeCurrencyMode is active the Blizzard currency UI owns
        -- the currency layout.  Skip currency sizing / pane guard but still
        -- schedule Apply so ExpandCharacterFrame restores the panel size.
        if IsAccountTransferBuild() and state.nativeCurrencyMode then
          self:_ScheduleBoundedApply("ToggleCharacter.nativeCurrency")
          return
        end
        if ResolvePaneFromToken(subFrameToken) == "currency" then
          self:_ApplyCurrencySizingDeferred("ToggleCharacter")
          self:_ScheduleCurrencyPaneGuard("ToggleCharacter")
        end
        self:_ScheduleBoundedApply("ToggleCharacter")
      end
    end)
  end
end

function Layout:_HandleCoordinatorLayoutFlush(reason)
  if not IsRefactorEnabled() then
    local state = EnsureState(self)
    self:RestoreSubFrames()
    if state.root then
      state.root:Hide()
    end
    return
  end

  self:_EnsureBootstrapHooks()
  local parent = CharacterFrame
  if not parent then
    return
  end
  self:Create(parent)
  self:_HookParent(parent)
  if parent.IsShown and parent:IsShown() then
    self:_ScheduleBoundedApply(reason or "coordinator.layout")
  end
end

local coordinator = CS and CS.Coordinator or nil
if coordinator and coordinator.SetFlushHandler then
  coordinator:SetFlushHandler("layout", function(_, reason)
    Layout:_HandleCoordinatorLayoutFlush(reason)
  end)
end
