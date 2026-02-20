local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.Guards = CS.Guards or {}
local Guards = CS.Guards

Guards._debounce = Guards._debounce or {}
Guards._throttle = Guards._throttle or {}

local function NowSeconds()
  if GetTimePreciseSec then
    return GetTimePreciseSec()
  end
  if GetTime then
    return GetTime()
  end
  return 0
end

local function CallOrError(fn)
  local ok, r1, r2, r3, r4 = pcall(fn)
  if not ok then
    error(r1, 0)
  end
  return r1, r2, r3, r4
end

function Guards:Debounce(key, delay, fn)
  if key == nil or type(fn) ~= "function" then
    return
  end

  local wait = tonumber(delay) or 0
  if wait < 0 then wait = 0 end

  local state = self._debounce[key]
  if not state then
    state = { token = 0 }
    self._debounce[key] = state
  end

  state.token = (state.token or 0) + 1
  local myToken = state.token

  if not (C_Timer and C_Timer.After) then
    if state.token ~= myToken then return end
    return CallOrError(fn)
  end

  C_Timer.After(wait, function()
    if not CS or not CS.Guards then return end
    local live = CS.Guards._debounce[key]
    if not live or live.token ~= myToken then
      return
    end
    CallOrError(fn)
  end)
end

function Guards:Throttle(key, interval, fn)
  if key == nil or type(fn) ~= "function" then
    return
  end

  local span = tonumber(interval) or 0
  if span < 0 then span = 0 end

  local state = self._throttle[key]
  if not state then
    state = {
      nextAllowedAt = 0,
      trailingQueued = false,
      trailingFn = nil,
    }
    self._throttle[key] = state
  end

  local now = NowSeconds()
  if now >= (state.nextAllowedAt or 0) then
    state.nextAllowedAt = now + span
    state.trailingFn = nil
    state.trailingQueued = false
    return CallOrError(fn)
  end

  state.trailingFn = fn
  if state.trailingQueued then
    return
  end
  state.trailingQueued = true

  local wait = (state.nextAllowedAt or now) - now
  if wait < 0 then wait = 0 end

  if not (C_Timer and C_Timer.After) then
    state.trailingQueued = false
    local trailing = state.trailingFn
    state.trailingFn = nil
    if trailing then
      state.nextAllowedAt = NowSeconds() + span
      return CallOrError(trailing)
    end
    return
  end

  C_Timer.After(wait, function()
    if not CS or not CS.Guards then return end
    local live = CS.Guards._throttle[key]
    if not live then return end
    live.trailingQueued = false
    local trailing = live.trailingFn
    live.trailingFn = nil
    if not trailing then
      return
    end
    live.nextAllowedAt = NowSeconds() + span
    CallOrError(trailing)
  end)
end

