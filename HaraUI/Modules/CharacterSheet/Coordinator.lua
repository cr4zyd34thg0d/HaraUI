local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.Coordinator = CS.Coordinator or {}
local Coordinator = CS.Coordinator
local Utils = CS.Utils

local DIRTY_KEYS = { "layout", "data", "stats", "gear", "rightpanel", "portalpanel" }

local LIFECYCLE_UNINITIALIZED = "UNINITIALIZED"
local LIFECYCLE_CREATED       = "CREATED"
local LIFECYCLE_SHOWN         = "SHOWN"
local LIFECYCLE_HIDDEN        = "HIDDEN"
local LIFECYCLE_DESTROYED     = "DESTROYED"

local function NewDirtyMap()
  return {
    layout = false,
    data = false,
    stats = false,
    gear = false,
    rightpanel = false,
    portalpanel = false,
  }
end

local function EnsureState(self)
  self._state = self._state or {}
  local s = self._state
  if s.active == nil then s.active = false end
  s.dirty = s.dirty or NewDirtyMap()
  if s.flushQueued == nil then s.flushQueued = false end
  if s.flushInProgress == nil then s.flushInProgress = false end
  if s.flushPendingAfterCurrent == nil then s.flushPendingAfterCurrent = false end
  if s.lifecycleState == nil then s.lifecycleState = LIFECYCLE_UNINITIALIZED end
  for _, key in ipairs(DIRTY_KEYS) do
    if s.dirty[key] == nil then
      s.dirty[key] = false
    end
  end
  return s
end

local function AnyDirty(dirty)
  for _, key in ipairs(DIRTY_KEYS) do
    if dirty[key] then
      return true
    end
  end
  return false
end

local function NormalizeFlags(flags)
  local out = NewDirtyMap()
  if flags == nil then
    for _, key in ipairs(DIRTY_KEYS) do
      out[key] = true
    end
    return out
  end

  if type(flags) == "string" then
    if out[flags] ~= nil then
      out[flags] = true
    end
    return out
  end

  if type(flags) ~= "table" then
    return out
  end

  for k, v in pairs(flags) do
    if type(k) == "string" then
      if v and out[k] ~= nil then
        out[k] = true
      end
    elseif type(v) == "string" and out[v] ~= nil then
      out[v] = true
    end
  end

  return out
end

function Coordinator:_QueueFlush()
  local state = EnsureState(self)
  if state.flushQueued then
    return
  end
  state.flushQueued = true

  local function run()
    state.flushQueued = false
    self:FlushUpdates()
  end

  local guards = CS and CS.Guards or nil
  if guards and guards.Debounce then
    guards:Debounce("coordinator_flush", 0, run)
    return
  end

  run()
end

function Coordinator:RequestUpdate(reason, flags)
  local state = EnsureState(self)
  if not state.active then
    return false
  end
  local normalized = NormalizeFlags(flags)
  if not AnyDirty(normalized) then
    return false
  end

  state.lastReason = reason or state.lastReason or "unspecified"

  for _, key in ipairs(DIRTY_KEYS) do
    if normalized[key] then
      state.dirty[key] = true
    end
  end

  self:_QueueFlush()
  return true
end

function Coordinator:FlushUpdates()
  local state = EnsureState(self)
  if state.flushInProgress then
    state.flushPendingAfterCurrent = true
    return false
  end
  state.flushInProgress = true

  local dirty = state.dirty
  local dirtySnapshot = NewDirtyMap()
  local hadDirty = false
  for _, key in ipairs(DIRTY_KEYS) do
    local isDirty = dirty[key] == true
    dirtySnapshot[key] = isDirty
    if isDirty then
      hadDirty = true
      dirty[key] = false
    end
  end
  local reason = state.lastReason
  state.lastReason = nil

  if hadDirty then
    local function MarkAndCall(key, fn, ...)
      if type(fn) ~= "function" then
        return false
      end
      local ok, err = pcall(fn, ...)
      if not ok and NS and NS.Debug then
        NS:Debug("CharacterSheet coordinator update error:", key, err)
      end
      return true
    end

    -- Deterministic coordinator update order for the refactor runtime:
    -- layout first, then data-driven panels.
    if dirtySnapshot.layout then
      local pm      = CS and CS.PaneManager  or nil
      local factory = CS and CS.FrameFactory or nil
      if pm and pm._EnsureBootstrapHooks then
        pcall(pm._EnsureBootstrapHooks, pm)
      end
      if factory and factory._HookParent and CharacterFrame then
        pcall(factory._HookParent, factory, CharacterFrame)
      end
      MarkAndCall("layout", factory and factory.Apply, factory, reason, dirtySnapshot)
      -- If _OnShow fired during combat, pm:OnShow and DispatchOnShow were skipped
      -- to avoid blocked frame Show/Hide calls (CharacterFrame child frames are
      -- restricted during combat).  Complete the dispatch now, after layout has
      -- been applied, once we're no longer in combat.
      -- NOTE: calls self:_DispatchSubModulesIfPending() (a method) so Lua resolves
      -- it at runtime — DispatchOnShow is a local defined later in this file and
      -- cannot be referenced directly from FlushUpdates.
      self:_DispatchSubModulesIfPending()
    end

    if dirtySnapshot.gear then
      local gearDisplay = CS and CS.GearDisplay or nil
      MarkAndCall("gear", gearDisplay and gearDisplay.Update, gearDisplay, reason)
    end

    if dirtySnapshot.stats then
      local statsPanel = CS and CS.StatsPanel or nil
      MarkAndCall("stats", statsPanel and statsPanel.Update, statsPanel, reason)
    end

    if dirtySnapshot.rightpanel then
      local rightPanel = CS and CS.MythicPanel or nil
      MarkAndCall("rightpanel", rightPanel and rightPanel.Update, rightPanel, reason)
    end

    if dirtySnapshot.portalpanel then
      local portalPanel = CS and CS.PortalPanel or nil
      MarkAndCall("portalpanel", portalPanel and portalPanel.Update, portalPanel, reason)
    end

    -- Core event routing emits data-only updates for currency/reputation changes.
    -- Fan those into the right panel so data refreshes are not dropped.
    if dirtySnapshot.data and not dirtySnapshot.rightpanel then
      local rightPanel = CS and CS.MythicPanel or nil
      MarkAndCall("data", rightPanel and rightPanel.Update, rightPanel, reason)
    end

  end

  state.flushInProgress = false
  if state.flushPendingAfterCurrent then
    state.flushPendingAfterCurrent = false
    if AnyDirty(state.dirty) then
      self:_QueueFlush()
    end
  end

  return hadDirty
end


---------------------------------------------------------------------------
-- Consolidated CharacterFrame OnShow / OnHide hook
---------------------------------------------------------------------------
local function IsCharacterPaneActive()
  local pm = CS and CS.PaneManager or nil
  if not pm then return true end
  return pm:IsCharacterPaneActive()
end

local function DispatchOnShow(reason)
  -- Only show character-pane modules when on the character pane;
  -- non-character panes (currency, reputation) handle their own visibility.
  if not IsCharacterPaneActive() then return end
  local gear = CS and CS.GearDisplay or nil
  if gear and gear.OnShow then pcall(gear.OnShow, gear, reason) end
  local stats = CS and CS.StatsPanel or nil
  if stats and stats.OnShow then pcall(stats.OnShow, stats, reason) end
  local right = CS and CS.MythicPanel or nil
  if right and right.OnShow then pcall(right.OnShow, right, reason) end
  local portal = CS and CS.PortalPanel or nil
  if portal and portal.OnShow then pcall(portal.OnShow, portal, reason) end
end

local function DispatchOnHide()
  local gear = CS and CS.GearDisplay or nil
  if gear and gear.OnHide then pcall(gear.OnHide, gear) end
  local stats = CS and CS.StatsPanel or nil
  if stats and stats.OnHide then pcall(stats.OnHide, stats) end
  local right = CS and CS.MythicPanel or nil
  if right and right.OnHide then pcall(right.OnHide, right) end
  local portal = CS and CS.PortalPanel or nil
  if portal and portal.OnHide then pcall(portal.OnHide, portal) end
end

-- Called from FlushUpdates after Apply completes.  Defined here (after the
-- DispatchOnShow local) so it can reference it; FlushUpdates itself is defined
-- earlier in the file where the local is not yet in scope.
function Coordinator:_DispatchSubModulesIfPending()
  local state = EnsureState(self)
  if not state.pendingSubModuleDispatch then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local reason = state.pendingSubModuleDispatch
  state.pendingSubModuleDispatch = nil
  local pm = CS and CS.PaneManager or nil
  if pm and pm.OnShow then pcall(pm.OnShow, pm, reason) end
  DispatchOnShow(reason)
end

function Coordinator:_OnShow(reason)
  local state = EnsureState(self)
  if not state.active then return end
  if state.lifecycleState == LIFECYCLE_DESTROYED then return end
  if state.lifecycleState == LIFECYCLE_SHOWN then return end
  state.lifecycleState = LIFECYCLE_SHOWN
  -- During combat, Show/Hide on frames parented to CharacterFrame is blocked.
  -- Record a pending dispatch flag; FlushUpdates will run pm:OnShow +
  -- DispatchOnShow after Apply completes once combat ends and
  -- PLAYER_REGEN_ENABLED triggers a layout update.
  -- Ordering: CombatPanel:Show runs here (UIParent-parented, safe in combat);
  -- PaneManager:OnShow + DispatchOnShow are deferred to _DispatchSubModulesIfPending
  -- in FlushUpdates, which only fires after InCombatLockdown() is false.
  if InCombatLockdown and InCombatLockdown() then
    state.pendingSubModuleDispatch = reason or "CharacterFrame.OnShow"
    -- Show compact combat overlay (UIParent-parented, deferred one tick).
    local cp = CS and CS.CombatPanel or nil
    if cp and cp.Show then cp:Show() end
    return
  end
  state.pendingSubModuleDispatch = nil
  -- PaneManager resolves active pane from current Blizzard frame visibility.
  local pm = CS and CS.PaneManager or nil
  if pm and pm.OnShow then
    pcall(pm.OnShow, pm, reason)
  end
  DispatchOnShow(reason)
end

function Coordinator:_OnHide()
  local state = EnsureState(self)
  if state.lifecycleState ~= LIFECYCLE_SHOWN then return end
  state.lifecycleState = LIFECYCLE_HIDDEN
  -- Cancel any pending sub-module show dispatch (opened + closed during combat).
  state.pendingSubModuleDispatch = nil
  -- Always hide the combat overlay (UIParent-parented, not restricted by lockdown).
  local cp = CS and CS.CombatPanel or nil
  if cp and cp.Hide then cp:Hide() end
  -- During combat, Show/Hide on frames parented to CharacterFrame is blocked.
  -- Our sub-frames are children of CharacterFrame and auto-hide with it, so
  -- skipping the explicit Hide calls here is safe.
  if InCombatLockdown and InCombatLockdown() then return end
  -- PaneManager resets activePane=nil, clears pending, hides chrome.
  local pm = CS and CS.PaneManager or nil
  if pm and pm.OnHide then
    pcall(pm.OnHide, pm)
  end
  DispatchOnHide()
end

function Coordinator:_EnsureCharacterFrameHooks()
  local state = EnsureState(self)
  if state.characterFrameHooked then return end
  if not (CharacterFrame and CharacterFrame.HookScript) then return end
  state.characterFrameHooked = true

  CharacterFrame:HookScript("OnShow", function()
    local factory = CS and CS.FrameFactory or nil
    if factory and factory.SyncExpandSize then
      factory.SyncExpandSize()
    end
    if Utils.IsAccountTransferBuild() then
      -- Transfer builds: defer by one frame so sub-frame layouts settle.
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then return end
          self:_OnShow("CharacterFrame.OnShow.deferred")
        end)
      else
        self:_OnShow("CharacterFrame.OnShow")
      end
    else
      self:_OnShow("CharacterFrame.OnShow")
    end
  end)

  CharacterFrame:HookScript("OnHide", function()
    self:_OnHide()
  end)

  -- Hook UpdateSize to directly maintain our expanded width.
  -- RefreshDisplay calls UpdateSize after every pane switch/show; it sets
  -- CharacterFrame width from Blizzard's characterFrameDisplayInfo table
  -- (Default = PANEL_DEFAULT_WIDTH, Rep/Currency = 400).  Our post-hook
  -- corrects it back to our expanded width.  This fires after the full
  -- UpdateSize body (including any UpdateUIPanelPositions call inside it),
  -- so it is the last word on frame width for that call.
  if CharacterFrame.UpdateSize then
    hooksecurefunc(CharacterFrame, "UpdateSize", function()
      if not state.active then return end
      local factory = CS and CS.FrameFactory or nil
      local w = factory and factory.EXPANDED_WIDTH or nil
      if not w then return end
      -- Defer out of any secure execution chain (ShowUIPanel attribute handler).
      -- Calling SetWidth from a tainted hook context poisons CharacterFrame
      -- and causes "Interface action failed because of an AddOn".
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          if not state.active then return end
          if InCombatLockdown and InCombatLockdown() then return end
          CharacterFrame:SetWidth(w)
        end)
      end
    end)
  end
end

function Coordinator:Apply()
  local state = EnsureState(self)
  if state.lifecycleState == LIFECYCLE_DESTROYED then return false end
  state.active = true
  if state.lifecycleState == LIFECYCLE_UNINITIALIZED
  or state.lifecycleState == LIFECYCLE_HIDDEN then
    state.lifecycleState = LIFECYCLE_CREATED
  end
  self:_EnsureCharacterFrameHooks()
  local core = CS and CS.Core or nil
  if core and core.OnEnable then
    pcall(core.OnEnable, core)
  end
  self:RequestUpdate("coordinator.apply", {
    layout = true,
    data = true,
    stats = true,
    gear = true,
    rightpanel = true,
    portalpanel = true,
  })
  return true
end

function Coordinator:Refresh()
  local state = EnsureState(self)
  if not state.active then
    return false
  end
  self:RequestUpdate("coordinator.refresh", {
    layout = true,
    data = true,
    stats = true,
    gear = true,
    rightpanel = true,
    portalpanel = true,
  })
  return true
end

function Coordinator:Disable()
  local state = EnsureState(self)
  state.lifecycleState = LIFECYCLE_HIDDEN
  state.active = false
  state.lastReason = nil
  state.flushQueued = false
  state.flushInProgress = false
  state.flushPendingAfterCurrent = false
  for _, key in ipairs(DIRTY_KEYS) do
    state.dirty[key] = false
  end

  local core = CS and CS.Core or nil
  if core and core.OnDisable then
    pcall(core.OnDisable, core)
  end

  local pm = CS and CS.PaneManager or nil
  if pm and pm.RestoreSubFrames then
    pcall(pm.RestoreSubFrames, pm)
  end
  local factory = CS and CS.FrameFactory or nil
  local fState  = factory and factory._state or nil
  if fState and fState.root and fState.root.Hide then
    fState.root:Hide()
  end
  if fState and fState.characterOverlay and fState.characterOverlay.Hide then
    fState.characterOverlay:Hide()
  end

  local gear = CS and CS.GearDisplay or nil
  if gear and gear._state and gear._state.root and gear._state.root.Hide then
    gear._state.root:Hide()
  end

  local stats = CS and CS.StatsPanel or nil
  if stats and stats._state and stats._state.root and stats._state.root.Hide then
    stats._state.root:Hide()
  end

  local right = CS and CS.MythicPanel or nil
  if right and right._StopTicker then
    pcall(right._StopTicker, right)
  end
  if right and right._state and right._state.root and right._state.root.Hide then
    right._state.root:Hide()
  end

  local portal = CS and CS.PortalPanel or nil
  if portal and portal._state and portal._state.root and portal._state.root.Hide then
    portal._state.root:Hide()
  end
  if portal and portal._state and portal._state.gridRoot and portal._state.gridRoot.Hide then
    portal._state.gridRoot:Hide()
  end

  return true
end

