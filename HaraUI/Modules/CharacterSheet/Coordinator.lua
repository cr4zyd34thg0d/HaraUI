local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.Coordinator = CS.Coordinator or {}
local Coordinator = CS.Coordinator

Coordinator._handlers = Coordinator._handlers or {}

local DIRTY_KEYS = { "layout", "data", "stats", "gear", "rightpanel" }

local function NewDirtyMap()
  return {
    layout = false,
    data = false,
    stats = false,
    gear = false,
    rightpanel = false,
  }
end

local function EnsureState(self)
  self._state = self._state or {}
  local s = self._state
  if s.active == nil then s.active = false end
  s.dirty = s.dirty or NewDirtyMap()
  s.lastReason = s.lastReason
  if s.flushQueued == nil then s.flushQueued = false end
  if s.flushInProgress == nil then s.flushInProgress = false end
  if s.flushPendingAfterCurrent == nil then s.flushPendingAfterCurrent = false end
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

function Coordinator:SetFlushHandler(flag, fn)
  if type(flag) ~= "string" then
    return false
  end
  local isKnown = false
  for _, key in ipairs(DIRTY_KEYS) do
    if key == flag then
      isKnown = true
      break
    end
  end
  if not isKnown then
    return false
  end
  if fn ~= nil and type(fn) ~= "function" then
    return false
  end
  self._handlers[flag] = fn
  return true
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

  if C_Timer and C_Timer.After then
    C_Timer.After(0, run)
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
    local handledByCoordinator = NewDirtyMap()

    local function MarkAndCall(key, fn, ...)
      if type(fn) ~= "function" then
        return false
      end
      local ok, err = pcall(fn, ...)
      if not ok and NS and NS.Debug then
        NS:Debug("CharacterSheet coordinator update error:", key, err)
      end
      handledByCoordinator[key] = true
      return true
    end

    local dataProvider = CS and CS.Data or nil
    local fullSnapshotLoaded = false
    local fullSnapshot = nil
    local function GetFullSnapshot()
      if fullSnapshotLoaded then
        return fullSnapshot
      end
      fullSnapshotLoaded = true
      if dataProvider and dataProvider.GetFullSnapshot then
        local ok, snapshot = pcall(dataProvider.GetFullSnapshot, dataProvider, {
          currencyLimit = 3,
          runLimit = 1,
        })
        if ok and type(snapshot) == "table" then
          fullSnapshot = snapshot
        end
      end
      return fullSnapshot
    end
    local function BuildRightPanelSnapshot(full)
      if type(full) ~= "table" then
        return nil
      end
      return {
        mythicPlus = full.mythicPlus,
        vault = full.vault,
        currency = full.currency,
      }
    end

    -- Deterministic coordinator update order for the refactor runtime:
    -- layout first, then data-driven panels.
    if dirtySnapshot.layout then
      local layout = CS and CS.Layout or nil
      if layout and layout._EnsureBootstrapHooks then
        pcall(layout._EnsureBootstrapHooks, layout)
      end
      if layout and layout._HookParent and CharacterFrame then
        pcall(layout._HookParent, layout, CharacterFrame)
      end
      MarkAndCall("layout", layout and layout.Apply, layout, reason, dirtySnapshot)
    end

    if dirtySnapshot.gear then
      local snapshot = nil
      local full = GetFullSnapshot()
      if type(full) == "table" then
        snapshot = full.gear
      end
      local gearDisplay = CS and CS.GearDisplay or nil
      MarkAndCall("gear", gearDisplay and gearDisplay.Update, gearDisplay, reason, snapshot, dirtySnapshot)
    end

    if dirtySnapshot.stats then
      local snapshot = nil
      local full = GetFullSnapshot()
      if type(full) == "table" then
        snapshot = full.stats
      end
      local statsPanel = CS and CS.StatsPanel or nil
      MarkAndCall("stats", statsPanel and statsPanel.Update, statsPanel, reason, snapshot, dirtySnapshot)
    end

    if dirtySnapshot.rightpanel then
      local full = GetFullSnapshot()
      local snapshot = BuildRightPanelSnapshot(full)
      local rightPanel = CS and CS.RightPanel or nil
      MarkAndCall("rightpanel", rightPanel and rightPanel.Update, rightPanel, reason, snapshot, dirtySnapshot)
    end

    -- Core event routing emits data-only updates for currency/reputation changes.
    -- Fan those into the right panel so data refreshes are not dropped.
    if dirtySnapshot.data and not dirtySnapshot.rightpanel then
      local full = GetFullSnapshot()
      local snapshot = BuildRightPanelSnapshot(full)
      local rightPanel = CS and CS.RightPanel or nil
      MarkAndCall("data", rightPanel and rightPanel.Update, rightPanel, reason, snapshot, dirtySnapshot)
    end

    -- Backward-compatible fallback for keys without direct coordinator calls.
    for _, key in ipairs(DIRTY_KEYS) do
      if dirtySnapshot[key] and not handledByCoordinator[key] then
        local fn = self._handlers[key]
        if type(fn) == "function" then
          local ok, err = pcall(fn, self, reason, dirtySnapshot)
          if not ok and NS and NS.Debug then
            NS:Debug("CharacterSheet coordinator handler error:", key, err)
          end
        end
      end
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

function Coordinator:GetDirtyFlags()
  local state = EnsureState(self)
  local copy = NewDirtyMap()
  for _, key in ipairs(DIRTY_KEYS) do
    copy[key] = state.dirty[key] == true
  end
  return copy
end

function Coordinator:Apply()
  local state = EnsureState(self)
  if CS.State then
    CS.State.activeBackend = "refactor"
  end
  state.active = true
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
  })
  return true
end

function Coordinator:Disable()
  local state = EnsureState(self)
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

  local layout = CS and CS.Layout or nil
  if layout and layout.RestoreSubFrames then
    pcall(layout.RestoreSubFrames, layout)
  end
  if layout and layout._state and layout._state.root and layout._state.root.Hide then
    layout._state.root:Hide()
  end

  local gear = CS and CS.GearDisplay or nil
  if gear and gear._state and gear._state.root and gear._state.root.Hide then
    gear._state.root:Hide()
  end

  local stats = CS and CS.StatsPanel or nil
  if stats and stats._state and stats._state.root and stats._state.root.Hide then
    stats._state.root:Hide()
  end

  local right = CS and CS.RightPanel or nil
  if right and right._StopTicker then
    pcall(right._StopTicker, right)
  end
  if right and right._state and right._state.root and right._state.root.Hide then
    right._state.root:Hide()
  end

  return true
end

function Coordinator:SetLocked(locked)
  return true
end

function Coordinator:DebugLayoutSnapshot(_reason)
  return true
end
