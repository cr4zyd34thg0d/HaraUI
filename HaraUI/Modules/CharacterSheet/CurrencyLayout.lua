local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.CurrencyLayout = CS.CurrencyLayout or {}
local CL = CS.CurrencyLayout
local Utils = CS.Utils

---------------------------------------------------------------------------
-- State (persists across /reload)
---------------------------------------------------------------------------
CL._state = CL._state or {
  currencySizingToken = 0,
  transferDeferredQueue = nil,
}

local function EnsureState()
  local s = CL._state
  s.currencySizingToken = tonumber(s.currencySizingToken) or 0
  if type(s.transferDeferredQueue) ~= "table" then
    s.transferDeferredQueue = {}
  end
  return s
end

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local CURRENCY_INNER_TOP = -34
local CURRENCY_INNER_BOTTOM = 6
local CURRENCY_DROPDOWN_OFFSET_X = -14
local CURRENCY_DROPDOWN_OFFSET_Y = 21
local CURRENCY_DROPDOWN_NEAR_TRANSFER_GAP_X = -8
local CURRENCY_DROPDOWN_NEAR_TRANSFER_GAP_Y = 0
local CURRENCY_DROPDOWN_LEVEL_BOOST = 50
local CURRENCY_SCROLLBAR_EDGE_X = -6
local CURRENCY_SCROLLBAR_EDGE_TOP = -2
local CURRENCY_SCROLLBAR_EDGE_BOTTOM = 2
local CURRENCY_POPUP_STRATA = "FULLSCREEN_DIALOG"
local CURRENCY_POPUP_LEVEL = 2000

---------------------------------------------------------------------------
-- Lazy accessors (modules loaded after CurrencyLayout)
---------------------------------------------------------------------------
local function GetPM()
  return CS and CS.PaneManager or nil
end

---------------------------------------------------------------------------
-- Utility locals
---------------------------------------------------------------------------
local function IsFrameShownSafe(frame)
  if not (frame and frame.IsShown) then return false end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown == true
end

local function GetFrameNameOrNil(frame)
  if not (frame and frame.GetName) then return nil end
  local ok, name = pcall(frame.GetName, frame)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  return name
end

local function IsDescendantOf(frame, ancestor)
  if not frame or not ancestor or not frame.GetParent then return false end
  local cursor = frame
  while cursor and cursor.GetParent do
    local ok, parent = pcall(cursor.GetParent, cursor)
    if not ok then return false end
    if parent == ancestor then return true end
    cursor = parent
  end
  return false
end

local function IsProtectedFrameSafe(frame)
  if not frame then return false end
  if frame.IsProtected then
    local ok, isProtected = pcall(frame.IsProtected, frame)
    if ok and isProtected then return true end
  end
  return false
end

local function CanMutateFrameLayout(frame)
  if not frame then return false end
  if IsFrameForbidden and IsFrameForbidden(frame) then return false end
  if IsProtectedFrameSafe(frame) then return false end
  return true
end

local function CaptureFrameLayout(state, frame)
  if not (state and frame) then return end
  if state.originalSubFrameLayout and state.originalSubFrameLayout[frame] then return end
  if not state.originalSubFrameLayout then return end
  local points = {}
  if frame.GetNumPoints and frame.GetPoint then
    for i = 1, (frame:GetNumPoints() or 0) do
      local point, rel, relPoint, x, y = frame:GetPoint(i)
      points[#points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end
  end
  state.originalSubFrameLayout[frame] = {
    parent = frame.GetParent and frame:GetParent() or nil,
    strata = frame.GetFrameStrata and frame:GetFrameStrata() or nil,
    level = frame.GetFrameLevel and frame:GetFrameLevel() or nil,
    points = points,
  }
end

---------------------------------------------------------------------------
-- Transfer frame visibility helpers
---------------------------------------------------------------------------
local _transferFrameHookMap = setmetatable({}, { __mode = "k" })
local _transferVisibilityKnownVisible = false
local _transferVisibleFrameName = nil

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
      if IsFrameShownSafe(frame) then return true, frame end
    end
  end
  return false, nil
end

local function QueueDeferredAfterTransferHide(key, callback)
  if type(callback) ~= "function" then return false end
  local state = EnsureState()
  local token = type(key) == "string" and key ~= "" and key or ("callback." .. tostring(#state.transferDeferredQueue + 1))
  state.transferDeferredQueue[token] = callback
  return true
end

local function FlushDeferredAfterTransferHide()
  local state = EnsureState()
  local queue = state.transferDeferredQueue
  if type(queue) ~= "table" or next(queue) == nil then return false end
  state.transferDeferredQueue = {}
  local function run()
    for _, callback in pairs(queue) do
      if type(callback) == "function" then pcall(callback) end
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, run)
  else
    run()
  end
  return true
end

-- Forward declaration (used in InstallTransferVisibilityHooks)
local ApplyCurrencySizingDeferred

local function InstallTransferVisibilityHooks()
  if C_CurrencyInfo and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function" then
    return false
  end
  local function HookFrame(frame)
    if not (frame and frame.HookScript) then return false end
    if _transferFrameHookMap[frame] then return false end
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
        FlushDeferredAfterTransferHide()
        ApplyCurrencySizingDeferred("transfer_hide")
      end
    end)
    _transferFrameHookMap[frame] = true
    return true
  end
  for _, frame in ipairs(BuildTransferFrameCandidates()) do
    HookFrame(frame)
  end
end

local function GuardLayoutDuringTransfer(entrypoint, detail, deferredKey, deferredFn)
  if Utils.IsAccountTransferBuild() then
    return IsTransferVisible() and true or false
  end
  InstallTransferVisibilityHooks()
  if not IsTransferVisible() then return false end
  if type(deferredFn) == "function" then
    QueueDeferredAfterTransferHide(deferredKey or entrypoint, deferredFn)
  end
  return true
end

---------------------------------------------------------------------------
-- Currency frame identification
---------------------------------------------------------------------------
local NativeGetCurrencyPaneFrame = _G and type(_G.GetCurrencyPaneFrame) == "function" and _G.GetCurrencyPaneFrame or nil

local function IsCurrencyTransferAuxFrame(frame)
  if not frame then return false end
  if frame == _G.CurrencyTransferMenu or frame == _G.CurrencyTransferLog or frame == _G.TokenFramePopup then
    return true
  end
  local name = GetFrameNameOrNil(frame)
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
  local name = GetFrameNameOrNil(frame)
  if expectedName and name ~= expectedName then
    local expectedIsToken = expectedName == "TokenFrame"
    local tokenAliasMatch = expectedIsToken and name and name:find("TokenFrame", 1, true)
    if not tokenAliasMatch then return false end
  end
  if name and (name:find("Transfer", 1, true) or name:find("Popup", 1, true)) then
    return false
  end
  if CharacterFrame and IsDescendantOf(frame, CharacterFrame) then return true end
  if not name then return false end
  if name == "CharacterFrameTokenFrame" or name == "CurrencyFrame" then return true end
  return name:find("TokenFrame", 1, true) ~= nil
end

local function GetCurrencyPaneFrame()
  local token = _G.TokenFrame
  if IsLikelyCharacterCurrencyPane(token, "TokenFrame") then return token end
  local characterToken = _G.CharacterFrameTokenFrame
  if IsLikelyCharacterCurrencyPane(characterToken, "CharacterFrameTokenFrame") then return characterToken end
  local currency = _G.CurrencyFrame
  if IsLikelyCharacterCurrencyPane(currency, "CurrencyFrame") then return currency end
  if NativeGetCurrencyPaneFrame then
    local ok, nativeFrame = pcall(NativeGetCurrencyPaneFrame)
    if ok and IsLikelyCharacterCurrencyPane(nativeFrame) then return nativeFrame end
  end
  local tokenAlias = _G.TokenFrameTokenFrame
  if IsLikelyCharacterCurrencyPane(tokenAlias, "TokenFrameTokenFrame") then return tokenAlias end
  return nil
end

local function BuildCurrencyCandidateFrames(resolvedFrame)
  local unique = {}
  local seen = setmetatable({}, { __mode = "k" })
  local function Add(frame, expectedName)
    if not frame or seen[frame] then return end
    if not IsLikelyCharacterCurrencyPane(frame, expectedName) then return end
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

-- Resolve the best currency frame (visible > resolved > first candidate)
local function ResolveCurrencyFrame()
  local resolved = GetCurrencyPaneFrame()
  local candidates = BuildCurrencyCandidateFrames(resolved)
  for _, frame in ipairs(candidates) do
    if Utils.IsFrameVisible(frame) then return frame end
  end
  return resolved or candidates[1] or nil
end

local function ResolveCurrencyToken(frames)
  if _G.TokenFrame and IsLikelyCharacterCurrencyPane(_G.TokenFrame, "TokenFrame") then return "TokenFrame" end
  if _G.CharacterFrameTokenFrame and IsLikelyCharacterCurrencyPane(_G.CharacterFrameTokenFrame, "CharacterFrameTokenFrame") then return "CharacterFrameTokenFrame" end
  if _G.CurrencyFrame and IsLikelyCharacterCurrencyPane(_G.CurrencyFrame, "CurrencyFrame") then return "CurrencyFrame" end
  local resolved = GetCurrencyPaneFrame()
  local name = resolved and resolved.GetName and resolved:GetName() or nil
  if type(name) == "string" and name ~= "" then return name end
  if type(frames) == "table" then
    local cName = frames.currency and frames.currency.GetName and frames.currency:GetName() or nil
    if type(cName) == "string" and cName ~= "" then return cName end
    for _, frame in ipairs(frames.currencyCandidates or {}) do
      local dName = frame and frame.GetName and frame:GetName() or nil
      if type(dName) == "string" and dName ~= "" then return dName end
    end
  end
  return "TokenFrame"
end

---------------------------------------------------------------------------
-- Currency backdrop
---------------------------------------------------------------------------
local _currencyBackdrop = nil

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
    backdrop:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, CURRENCY_INNER_TOP)
    backdrop:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
  end
  local tokenLevel = tokenFrame and tokenFrame.GetFrameLevel and tokenFrame:GetFrameLevel()
    or ((CharacterFrame:GetFrameLevel() or 1) + 30)
  backdrop:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH")
  backdrop:SetFrameLevel(math.max(1, tokenLevel - 1))
  backdrop:Show()
end

local function HideCurrencyBackdrop()
  if _currencyBackdrop and _currencyBackdrop.Hide then _currencyBackdrop:Hide() end
end

---------------------------------------------------------------------------
-- Currency overlay / transfer popup layering
---------------------------------------------------------------------------
local _currencyOverlayHookMap = setmetatable({}, { __mode = "k" })

local function RunCurrencyMutation(fn)
  if type(fn) ~= "function" then return false end
  if Utils.IsInLockdown() then
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if not Utils.IsInLockdown() then pcall(fn) end
      end)
    end
    return false
  end
  return pcall(fn)
end

local function ForceCurrencyOverlayFrameTopmost(frame, opts)
  if Utils.IsAccountTransferBuild() or not frame then return false end
  if IsFrameForbidden and IsFrameForbidden(frame) then return false end
  if not CanMutateFrameLayout(frame) then return false end
  opts = type(opts) == "table" and opts or nil
  local keepParent = opts and opts.keepParent == true
  return RunCurrencyMutation(function()
    if not keepParent and frame.SetParent and UIParent and frame.GetParent and frame:GetParent() ~= UIParent then
      frame:SetParent(UIParent)
    end
    if frame.SetFrameStrata then frame:SetFrameStrata(CURRENCY_POPUP_STRATA) end
    if frame.SetFrameLevel then frame:SetFrameLevel(CURRENCY_POPUP_LEVEL) end
    if frame.SetToplevel then frame:SetToplevel(true) end
    if frame.Raise then frame:Raise() end
  end)
end

local function HookCurrencyOverlayOnShow(frame, opts)
  if Utils.IsAccountTransferBuild() or not frame then return false end
  if IsFrameForbidden and IsFrameForbidden(frame) then return false end
  if not CanMutateFrameLayout(frame) or not frame.HookScript then return false end
  opts = type(opts) == "table" and opts or nil
  local keepParent = opts and opts.keepParent == true
  local existing = _currencyOverlayHookMap[frame]
  if existing then
    if keepParent and type(existing) == "table" then existing.keepParent = true end
    return false
  end
  frame:HookScript("OnShow", function()
    local config = _currencyOverlayHookMap[frame]
    local function runDeferred()
      if not frame or not IsFrameShownSafe(frame) or Utils.IsInLockdown() then return end
      ForceCurrencyOverlayFrameTopmost(frame, config)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, runDeferred) else runDeferred() end
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
  if Utils.IsAccountTransferBuild() then return false end
  for _, frame in ipairs(BuildTransferOverlayFrames(active)) do
    if IsFrameShownSafe(frame) and CanMutateFrameLayout(frame) then
      HookCurrencyOverlayOnShow(frame, { keepParent = false })
      ForceCurrencyOverlayFrameTopmost(frame, { keepParent = false })
    end
  end
end

local function RaiseCurrencyPopupLayers(active, opts)
  if Utils.IsAccountTransferBuild() then return false end
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

local function DeferTransferOverlayTopmost(active)
  if not (C_Timer and C_Timer.After) then return false end
  C_Timer.After(0, function()
    if IsTransferVisible(active) then
      RaiseTransferOverlaysTopmost(active, { keepParent = false })
    end
  end)
  return true
end

---------------------------------------------------------------------------
-- Currency right-panel layering
---------------------------------------------------------------------------
local _rightPanelCreateHookInstalled = false

local function SetCurrencyMythicPanelLayering(active)
  local rightPanel = CS and CS.MythicPanel or nil
  local rightRoot = rightPanel and rightPanel._state and rightPanel._state.root or nil
  if not rightRoot then return false end
  if active then
    if not rightRoot._huiCurrencyLayerSnapshot then
      rightRoot._huiCurrencyLayerSnapshot = {
        strata = rightRoot.GetFrameStrata and rightRoot:GetFrameStrata() or nil,
        level = rightRoot.GetFrameLevel and rightRoot:GetFrameLevel() or nil,
      }
    end
    if rightRoot.SetFrameStrata then rightRoot:SetFrameStrata("LOW") end
    if rightRoot.SetFrameLevel then rightRoot:SetFrameLevel(1) end
    return true
  end
  local snapshot = rightRoot._huiCurrencyLayerSnapshot
  if snapshot then
    if rightRoot.SetFrameStrata and snapshot.strata then rightRoot:SetFrameStrata(snapshot.strata) end
    if rightRoot.SetFrameLevel and snapshot.level then rightRoot:SetFrameLevel(snapshot.level) end
    rightRoot._huiCurrencyLayerSnapshot = nil
  end
  return true
end

local function EnsureCurrencyMythicPanelCreateHook()
  if _rightPanelCreateHookInstalled then return end
  local rightPanel = CS and CS.MythicPanel or nil
  if not (hooksecurefunc and rightPanel and type(rightPanel.Create) == "function") then return end
  hooksecurefunc(rightPanel, "Create", function()
    local pm = GetPM()
    if pm and pm._ApplyCurrencyMythicPanelLayering then
      pm:_ApplyCurrencyMythicPanelLayering()
    end
  end)
  _rightPanelCreateHookInstalled = true
end

---------------------------------------------------------------------------
-- Currency sizing / positioning
---------------------------------------------------------------------------
local _currencyMethodHookMap = setmetatable({}, { __mode = "k" })
local _currencyWidthHookMap = setmetatable({}, { __mode = "k" })
local _currencyGlobalHookMap = {}

local function GetCurrencyDropdownFrame(active)
  if active and active.filterDropdown then return active.filterDropdown end
  if active and active.FilterDropdown then return active.FilterDropdown end
  if active and active.filterDropDown then return active.filterDropDown end
  if active and active.FilterDropDown then return active.FilterDropDown end
  if _G and _G.TokenFrameFilterDropdown then return _G.TokenFrameFilterDropdown end
  if _G and _G.TokenFrameFilterDropDown then return _G.TokenFrameFilterDropDown end
  return nil
end

local function PositionCurrencyDropdown(state, active, leftContainer, transferAnchor)
  local dropdown = GetCurrencyDropdownFrame(active)
  if not dropdown then return nil end
  if IsTransferVisible(active) then
    DeferTransferOverlayTopmost(active)
    return dropdown
  end
  if Utils.IsInLockdown() then
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if not Utils.IsInLockdown() then
          local pm = GetPM()
          if pm then pm:_ScheduleCurrencyPaneGuard("currency.dropdown.defer") end
        end
      end)
    end
    return dropdown
  end
  if not CanMutateFrameLayout(dropdown) then return dropdown end
  local fState = Utils.GetFactoryState()
  local root = fState and fState.root or nil
  local dropdownParent = leftContainer or root or CharacterFrame
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
  if dropdown.SetFrameStrata then dropdown:SetFrameStrata("DIALOG") end
  if dropdown.SetFrameLevel then
    local leftLevel = leftContainer and leftContainer.GetFrameLevel and tonumber(leftContainer:GetFrameLevel()) or 1
    local activeLevel = active and active.GetFrameLevel and tonumber(active:GetFrameLevel()) or leftLevel
    local transferLevel = transferAnchor and transferAnchor.GetFrameLevel and tonumber(transferAnchor:GetFrameLevel()) or 0
    dropdown:SetFrameLevel(math.max(leftLevel + CURRENCY_DROPDOWN_LEVEL_BOOST, activeLevel + CURRENCY_DROPDOWN_LEVEL_BOOST, transferLevel + 1))
  end
  if dropdown.SetToplevel then dropdown:SetToplevel(true) end
  if dropdown.Raise then dropdown:Raise() end
  if dropdown.SetAlpha then dropdown:SetAlpha(1) end
  if dropdown.EnableMouse then dropdown:EnableMouse(true) end
  if dropdown.Show then dropdown:Show() end
  return dropdown
end

local function SetCurrencyDropdownVisible(active, visible)
  if IsTransferVisible(active) then return false end
  local dropdown = GetCurrencyDropdownFrame(active)
  if not dropdown or IsProtectedFrameSafe(dropdown) then return false end
  if visible then
    if dropdown.Show then dropdown:Show() end
  else
    if dropdown.Hide then dropdown:Hide() end
  end
  return true
end

local function ResolveScrollBarForOwner(owner)
  if not owner then return nil end
  if owner.ScrollBar then return owner.ScrollBar end
  if owner.scrollBar then return owner.scrollBar end
  if owner.GetScrollBar then
    local ok, sb = pcall(owner.GetScrollBar, owner)
    if ok and sb then return sb end
  end
  if owner.GetName and _G then
    local ok, ownerName = pcall(owner.GetName, owner)
    if ok and type(ownerName) == "string" and ownerName ~= "" then
      local byName = _G[ownerName .. "ScrollBar"]
      if byName then return byName end
    end
  end
  return nil
end

local function BuildCurrencyScrollBarTargets(active)
  local targets = {}
  local seen = setmetatable({}, { __mode = "k" })
  local function Add(scrollBar, anchor, label, topPad, bottomPad)
    if not scrollBar or seen[scrollBar] then return end
    seen[scrollBar] = true
    targets[#targets + 1] = { bar = scrollBar, anchor = anchor or active, label = label, topPad = topPad, bottomPad = bottomPad }
  end
  local function AddFromOwner(owner, label, topPad, bottomPad)
    Add(ResolveScrollBarForOwner(owner), owner or active, label, topPad, bottomPad)
  end
  AddFromOwner(active and active.ScrollFrame, "active.ScrollFrame.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  AddFromOwner(active and active.ScrollBox, "active.ScrollBox.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  AddFromOwner(active and active.CategoryScrollBox, "active.CategoryScrollBox.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  AddFromOwner(active and active.CategoryList, "active.CategoryList.ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  for _, key in ipairs({ "CurrencyContainer", "TokenContainer", "Container", "List" }) do
    AddFromOwner(active and active[key], "active." .. key .. ".ScrollBar", CURRENCY_SCROLLBAR_EDGE_TOP, CURRENCY_SCROLLBAR_EDGE_BOTTOM)
  end
  AddFromOwner(active, "active.ScrollBar", CURRENCY_INNER_TOP, CURRENCY_INNER_BOTTOM)
  Add(_G and _G.TokenFrameScrollBar, active, "_G.TokenFrameScrollBar", CURRENCY_INNER_TOP, CURRENCY_INNER_BOTTOM)
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
      if scrollBar.SetFrameStrata and CharacterFrame then
        scrollBar:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH")
      end
      if scrollBar.SetFrameLevel then
        scrollBar:SetFrameLevel(math.max(1, (anchor.GetFrameLevel and tonumber(anchor:GetFrameLevel()) or 1) + 4))
      end
      if scrollBar.Show then scrollBar:Show() end
    end
  end
end

local function AnchorCurrencyFrame(frame, anchor, leftPad, topPad, rightPad, bottomPad)
  if not (frame and anchor and frame.ClearAllPoints and frame.SetPoint and CanMutateFrameLayout(frame)) then return false end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", leftPad, topPad)
  frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", rightPad, bottomPad)
  return true
end

local function GetCurrencyTransferAnchorFrame(active)
  local log = _G and _G.CurrencyTransferLog or nil
  local menu = _G and _G.CurrencyTransferMenu or nil
  local popup = (_G and _G.TokenFramePopup) or (active and active.TokenFramePopup) or nil
  if IsFrameShownSafe(log) then return log end
  if IsFrameShownSafe(menu) then return menu end
  if IsFrameShownSafe(popup) then return popup end
  return log or menu or popup
end

---------------------------------------------------------------------------
-- Currency reflow hooks
---------------------------------------------------------------------------
local function HookCurrencyMethodOnce(frame, methodName)
  if not (hooksecurefunc and frame and type(methodName) == "string") then return false end
  if not CanMutateFrameLayout(frame) or type(frame[methodName]) ~= "function" then return false end
  local byMethod = _currencyMethodHookMap[frame]
  if type(byMethod) ~= "table" then byMethod = {}; _currencyMethodHookMap[frame] = byMethod end
  if byMethod[methodName] then return false end
  hooksecurefunc(frame, methodName, function()
    local pm = GetPM()
    if pm then pm:_ScheduleCurrencyPaneGuard("currency.method." .. methodName) end
  end)
  byMethod[methodName] = true
  return true
end

local function HookCurrencyWidthOnce(frame)
  if not (hooksecurefunc and frame and frame.SetWidth and CanMutateFrameLayout(frame)) then return false end
  if _currencyWidthHookMap[frame] then return false end
  _currencyWidthHookMap[frame] = true
  hooksecurefunc(frame, "SetWidth", function()
    local pm = GetPM()
    if pm then pm:_ScheduleCurrencyPaneGuard("currency.width") end
  end)
  return true
end

local function HookCurrencyGlobalOnce(functionName)
  if not (hooksecurefunc and type(functionName) == "string" and _G and type(_G[functionName]) == "function") then return false end
  if _currencyGlobalHookMap[functionName] then return false end
  hooksecurefunc(functionName, function()
    local pm = GetPM()
    if pm then pm:_ScheduleCurrencyPaneGuard("currency.global." .. functionName) end
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
  for _, entry in ipairs(stretchTargets or {}) do HookCurrencyWidthOnce(entry.frame) end
  for _, entry in ipairs(scrollBarTargets or {}) do HookCurrencyWidthOnce(entry.bar) end
end

---------------------------------------------------------------------------
-- ApplyCurrencySizing / ApplyCurrencySizingDeferred
---------------------------------------------------------------------------
local function ApplyCurrencySizing()
  local fState = Utils.GetFactoryState()
  local leftContainer = fState and fState.panels and fState.panels.left or nil
  local active = ResolveCurrencyFrame()
  local transferVisible = IsTransferVisible(active)
  if Utils.IsAccountTransferBuild() then
    if transferVisible then DeferTransferOverlayTopmost(active) end
    return false
  end
  if transferVisible or Utils.IsInLockdown() or Utils.IsSecureExecution() then
    if transferVisible then DeferTransferOverlayTopmost(active) end
    return false
  end
  if not (leftContainer and active and CanMutateFrameLayout(active)) then return false end
  AnchorCurrencyFrame(active, leftContainer, 0, 0, 0, 0)
  PositionCurrencyScrollBars(active, BuildCurrencyScrollBarTargets(active))
  return true
end

-- Assign to the forward-declared local
ApplyCurrencySizingDeferred = function(source)
  local state = EnsureState()
  state.currencySizingToken = (state.currencySizingToken or 0) + 1
  local token = state.currencySizingToken
  local function run()
    if EnsureState().currencySizingToken ~= token then return end
    ApplyCurrencySizing()
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() run() end)
    C_Timer.After(0.15, function() run() end)
  else
    run()
  end
  return true
end

---------------------------------------------------------------------------
-- NormalizeCurrencyFrameSafe
---------------------------------------------------------------------------
local function NormalizeCurrencyFrameSafe(state, frame, source)
  if not (state and frame and CharacterFrame) then return false end
  if IsTransferVisible(frame) then
    DeferTransferOverlayTopmost(frame)
    return true
  end
  if GuardLayoutDuringTransfer("NormalizeCurrencyFrameSafe", tostring(source), "NormalizeCurrencyFrameSafe", function()
    local pm = GetPM()
    if pm then pm:_ScheduleCurrencyPaneGuard("transfer_hidden.normalize") end
  end) then
    return false
  end
  local fState = Utils.GetFactoryState()
  local panels = fState and fState.panels or nil
  local leftContainer = panels and panels.left or nil
  local rootContainer = fState and fState.root or nil
  local currencyContainer = leftContainer or rootContainer or CharacterFrame
  local rightContainer = panels and panels.right or nil
  if not currencyContainer then return false end
  CaptureFrameLayout(state, frame)
  if Utils.IsAccountTransferBuild() then
    RaiseCurrencyPopupLayers(frame, { optionsOnly = true, keepParent = true })
    return true
  end
  if Utils.IsInLockdown() or Utils.IsSecureExecution() then
    ApplyCurrencySizingDeferred((source or "normalize.currency") .. ".deferred")
    return false
  end
  if not CanMutateFrameLayout(frame) then return false end
  local scrollBarTargets = BuildCurrencyScrollBarTargets(frame)
  if frame.ClearAllPoints and frame.SetPoint then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", currencyContainer, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", currencyContainer, "BOTTOMRIGHT", 0, 0)
  end
  if frame.SetFrameStrata then frame:SetFrameStrata(CharacterFrame:GetFrameStrata() or "HIGH") end
  if frame.SetFrameLevel then
    local leftLevel = currencyContainer.GetFrameLevel and tonumber(currencyContainer:GetFrameLevel()) or 1
    local rightLevel = rightContainer and rightContainer.GetFrameLevel and tonumber(rightContainer:GetFrameLevel()) or nil
    local targetLevel = leftLevel
    if rightLevel then targetLevel = math.min(targetLevel, rightLevel - 1) end
    frame:SetFrameLevel(math.max(1, targetLevel))
  end
  if frame.SetAlpha then frame:SetAlpha(1) end
  if frame.EnableMouse then frame:EnableMouse(true) end
  local transferAnchor = GetCurrencyTransferAnchorFrame(frame)
  PositionCurrencyDropdown(state, frame, currencyContainer, transferAnchor)
  PositionCurrencyScrollBars(frame, scrollBarTargets)
  RaiseCurrencyPopupLayers(frame, { optionsOnly = true })
  InstallCurrencyReflowHooks(frame, nil, scrollBarTargets)
  ApplyCurrencySizingDeferred(source or "normalize.currency")
  return true
end

---------------------------------------------------------------------------
-- ShowNativeSubFrame + sub-frame tokens
---------------------------------------------------------------------------
local PANE_SUBFRAME_TOKENS = {
  character = { "PaperDollFrame" },
  reputation = { "ReputationFrame" },
  currency = { "TokenFrame", "CharacterFrameTokenFrame", "CurrencyFrame", "TokenFrameTokenFrame" },
}

local function BuildCurrencySubFrameTokens(frames)
  local out = {}
  local seen = {}
  local function Add(token)
    if type(token) ~= "string" or token == "" or seen[token] then return end
    seen[token] = true
    out[#out + 1] = token
  end
  local resolved = GetCurrencyPaneFrame()
  if resolved and resolved.GetName then Add(resolved:GetName()) end
  if type(frames) == "table" then
    if frames.currency and frames.currency.GetName then Add(frames.currency:GetName()) end
    for _, frame in ipairs(frames.currencyCandidates or {}) do
      if frame and frame.GetName then Add(frame:GetName()) end
    end
  end
  Add("TokenFrame"); Add("CharacterFrameTokenFrame"); Add("CurrencyFrame"); Add("TokenFrameTokenFrame")
  return out
end

local function ShowNativeSubFrame(pane)
  if GuardLayoutDuringTransfer("ShowNativeSubFrame", tostring(pane), "ShowNativeSubFrame", function()
    if not IsTransferVisible() then ShowNativeSubFrame(pane) end
  end) then
    return false
  end
  if type(CharacterFrame_ShowSubFrame) ~= "function" then return false end
  if pane == "currency" then
    local pm = GetPM()
    local frames = pm and pm.BuildPaneFrameMap and pm.BuildPaneFrameMap() or {}
    for _, token in ipairs(BuildCurrencySubFrameTokens(frames)) do
      if _G[token] or token == "TokenFrame" then
        local ok = pcall(CharacterFrame_ShowSubFrame, token)
        if ok then
          ApplyCurrencySizingDeferred("show_native_subframe.currency")
          return true
        end
      end
    end
    return false
  end
  local tokens = PANE_SUBFRAME_TOKENS[pane]
  if not tokens then return false end
  for _, token in ipairs(tokens) do
    if pcall(CharacterFrame_ShowSubFrame, token) then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
CL.GetCurrencyPaneFrame = GetCurrencyPaneFrame
CL.BuildCurrencyCandidateFrames = BuildCurrencyCandidateFrames
CL.ResolveCurrencyToken = ResolveCurrencyToken
CL.ShowCurrencyBackdrop = ShowCurrencyBackdrop
CL.HideCurrencyBackdrop = HideCurrencyBackdrop
CL.SetCurrencyDropdownVisible = SetCurrencyDropdownVisible
CL.IsTransferVisible = IsTransferVisible
CL.GuardLayoutDuringTransfer = GuardLayoutDuringTransfer
CL.InstallTransferVisibilityHooks = InstallTransferVisibilityHooks
CL.DeferTransferOverlayTopmost = DeferTransferOverlayTopmost
CL.RaiseCurrencyPopupLayers = RaiseCurrencyPopupLayers
CL.NormalizeCurrencyFrameSafe = NormalizeCurrencyFrameSafe
CL.ApplyCurrencySizingDeferred = ApplyCurrencySizingDeferred
CL.ApplyCurrencySizing = ApplyCurrencySizing
CL.SetCurrencyMythicPanelLayering = SetCurrencyMythicPanelLayering
CL.EnsureCurrencyMythicPanelCreateHook = EnsureCurrencyMythicPanelCreateHook
CL.BuildCurrencySubFrameTokens = BuildCurrencySubFrameTokens
CL.ShowNativeSubFrame = ShowNativeSubFrame
CL.CaptureFrameLayout = CaptureFrameLayout
