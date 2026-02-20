local ADDON, NS = ...

NS.CharacterSheet = NS.CharacterSheet or {}
local CS = NS.CharacterSheet
local Utils = CS.Utils

CS.State = CS.State or {
  activeBackend = "refactor",
}

CS.Core = CS.Core or {}
local Core = CS.Core

Core._state = Core._state or {
  loaded = false,
  enabled = false,
  eventFrame = nil,
  hookMap = nil,
}

local CURRENCY_REP_DEBOUNCE_DELAY = 0.05

local EVENT_FLAGS = {
  ADDON_LOADED = {
    layout = true,
    data = true,
    stats = true,
    gear = true,
    rightpanel = true,
    portalpanel = true,
  },
  PLAYER_LOGIN = {
    layout = true,
    data = true,
    stats = true,
    gear = true,
    rightpanel = true,
    portalpanel = true,
  },
}

local function HasAccountCurrencyTransferSupport()
  return C_CurrencyInfo
    and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function"
    and type(C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters) == "function"
end

local function IsFrameShownSafe(frame)
  if not (frame and frame.IsShown) then
    return false
  end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown == true
end

local function IsCurrencyTransferVisible()
  local candidates = {
    _G and _G.AccountCurrencyTransferFrame or nil,
    _G and _G.CurrencyTransferFrame or nil,
    _G and _G.CurrencyTransferMenu or nil,
    _G and _G.CurrencyTransferLog or nil,
    _G and _G.TokenFramePopup or nil,
  }
  for _, frame in ipairs(candidates) do
    if IsFrameShownSafe(frame) then
      return true
    end
  end
  return false
end

local function GetCoordinator()
  return CS and CS.Coordinator or nil
end

local function RegisterEventIfExists(frame, eventName)
  if not (frame and frame.RegisterEvent and type(eventName) == "string") then
    return false
  end
  local ok = pcall(frame.RegisterEvent, frame, eventName)
  return ok == true
end

local function RegisterCoreEvents(frame)
  if not frame then return end
  RegisterEventIfExists(frame, "ADDON_LOADED")
  RegisterEventIfExists(frame, "PLAYER_LOGIN")
  -- Currency/Reputation events are handled with visibility filtering + debounce.
  RegisterEventIfExists(frame, "CURRENCY_DISPLAY_UPDATE")
  RegisterEventIfExists(frame, "PLAYER_MONEY")
  RegisterEventIfExists(frame, "UPDATE_FACTION")
  -- Combat end: re-apply layout if CharacterFrame was opened during combat.
  RegisterEventIfExists(frame, "PLAYER_REGEN_ENABLED")
  -- Equipment changes: route to stats + gear panels for ilvl / slot updates.
  RegisterEventIfExists(frame, "PLAYER_EQUIPMENT_CHANGED")
  RegisterEventIfExists(frame, "PLAYER_AVG_ITEM_LEVEL_UPDATE")
end

local function IsCharacterVisible()
  return Utils.IsFrameVisible(CharacterFrame)
end

local function IsReputationPaneVisible()
  if not IsCharacterVisible() then
    return false
  end
  return Utils.IsFrameVisible(_G and _G.ReputationFrame)
end

local function IsCurrencyPaneVisible()
  if not IsCharacterVisible() then
    return false
  end

  local candidates = {
    _G and _G.CurrencyFrame,
    _G and _G.TokenFrame,
    _G and _G.CharacterFrameTokenFrame,
    _G and _G.TokenFrameTokenFrame,
  }
  for _, frame in ipairs(candidates) do
    if Utils.IsFrameVisible(frame) then
      return true
    end
  end
  return false
end

local function IsRelevantPaneVisibleForEvent(event)
  if event == "UPDATE_FACTION" then
    return IsReputationPaneVisible()
  end
  if event == "CURRENCY_DISPLAY_UPDATE" or event == "PLAYER_MONEY" then
    return IsCurrencyPaneVisible()
  end
  return false
end

local function IsCurrencySubFrameName(name)
  if type(name) ~= "string" then
    return false
  end
  return name == "TokenFrame"
    or name == "CurrencyFrame"
    or name == "CharacterFrameTokenFrame"
    or name == "TokenFrameTokenFrame"
end

function Core:RequestUpdateForEvent(event, reason)
  local flags = EVENT_FLAGS[event]
  if not flags then
    return false
  end
  local coordinator = GetCoordinator()
  if not (coordinator and coordinator.RequestUpdate) then
    return false
  end
  coordinator:RequestUpdate(reason or ("core:" .. tostring(event)), flags)
  return true
end

function Core:QueueCurrencyRepUpdate(event)
  if not self._state.enabled then
    return false
  end
  if not IsRelevantPaneVisibleForEvent(event) then
    return false
  end
  if HasAccountCurrencyTransferSupport() and IsCurrencyTransferVisible() then
    return false
  end

  local coordinator = GetCoordinator()
  if not (coordinator and coordinator.RequestUpdate) then
    return false
  end

  local flags = { data = true }
  local reason = "core:" .. string.lower(tostring(event))
  local debounceKey = (event == "UPDATE_FACTION") and "core_rep_update" or "core_currency_update"

  local function request()
    if not self._state.enabled then
      return
    end
    -- Re-check on execution because debounced calls run later.
    if not IsRelevantPaneVisibleForEvent(event) then
      return
    end
    coordinator:RequestUpdate(reason, flags)
  end

  local guards = CS and CS.Guards or nil
  if guards and guards.Debounce then
    guards:Debounce(debounceKey, CURRENCY_REP_DEBOUNCE_DELAY, request)
  elseif C_Timer and C_Timer.After then
    C_Timer.After(CURRENCY_REP_DEBOUNCE_DELAY, request)
  else
    request()
  end
  return true
end

function Core:EnsurePaneVisibilityHooks()
  local state = self._state
  if not state.hookMap then
    state.hookMap = {}
  end
  local hookMap = state.hookMap

  local function HookOnShow(frame, key, eventName)
    if hookMap[key] then
      return
    end
    if not (frame and frame.HookScript) then
      return
    end
    frame:HookScript("OnShow", function()
      self:QueueCurrencyRepUpdate(eventName)
    end)
    hookMap[key] = true
  end

  HookOnShow(CharacterFrame, "character_onshow", "CURRENCY_DISPLAY_UPDATE")
  HookOnShow(_G and _G.ReputationFrame, "reputation_onshow", "UPDATE_FACTION")
  if not HasAccountCurrencyTransferSupport() then
    HookOnShow(_G and _G.TokenFrame, "token_onshow", "CURRENCY_DISPLAY_UPDATE")
    HookOnShow(_G and _G.CurrencyFrame, "currency_onshow", "CURRENCY_DISPLAY_UPDATE")
    HookOnShow(_G and _G.CharacterFrameTokenFrame, "character_token_onshow", "CURRENCY_DISPLAY_UPDATE")
    HookOnShow(_G and _G.TokenFrameTokenFrame, "token_alias_onshow", "CURRENCY_DISPLAY_UPDATE")
  end

end

-- Called by Layout's consolidated CharacterFrame_ShowSubFrame hook.
function Core:_OnShowSubFrame(frameName)
  if HasAccountCurrencyTransferSupport() and IsCurrencyTransferVisible() then
    return
  end
  frameName = tostring(frameName or "")
  if frameName == "ReputationFrame" then
    self:QueueCurrencyRepUpdate("UPDATE_FACTION")
    return
  end
  if IsCurrencySubFrameName(frameName) then
    self:QueueCurrencyRepUpdate("CURRENCY_DISPLAY_UPDATE")
  end
end

function Core:DispatchEvent(event, ...)
  if event == "ADDON_LOADED" then
    local addonName = ...
    if addonName == "Blizzard_UIPanels_Game" then
      -- CharacterFrame now exists (demand-loaded). Install lifecycle hooks and
      -- preset attributes so the first combat open uses the expanded size.
      local factory = CS and CS.FrameFactory or nil
      if factory and factory.PresetFrameAttributes then
        factory.PresetFrameAttributes()
      end
      -- Install the CharacterFrame OnShow/OnHide lifecycle hooks now that the
      -- frame exists. Without this, a demand-load during combat means the hooks
      -- are never installed and Coordinator:_OnShow never fires.
      local coordinator = GetCoordinator()
      if coordinator and coordinator._EnsureCharacterFrameHooks then
        pcall(coordinator._EnsureCharacterFrameHooks, coordinator)
      end
      self:EnsurePaneVisibilityHooks()
      self:RequestUpdateForEvent(event, "core:blizzard_uipanels_game_loaded")
      return
    end
    if addonName == "Blizzard_TokenUI" then
      self:EnsurePaneVisibilityHooks()
      self:RequestUpdateForEvent(event, "core:blizzard_tokenui_loaded")
      return
    end
    if addonName ~= ADDON then
      return
    end
    self:OnEnable()
    self:EnsurePaneVisibilityHooks()
    self:RequestUpdateForEvent(event, "core:addon_loaded")
    return
  end

  if not self._state.enabled then
    return
  end

  if event == "PLAYER_LOGIN" then
    self:EnsurePaneVisibilityHooks()
    -- Force-load Blizzard_UIPanels_Game now so CharacterFrame exists before any
    -- combat can start. Without this, a first-ever open during combat means
    -- the addon demand-loads while InCombatLockdown() is true, SetAttribute is
    -- blocked, and the frame opens at Blizzard's small default size.
    -- LoadAddOn is not combat-restricted and runs synchronously.
    local loadFn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if loadFn then
      pcall(loadFn, "Blizzard_UIPanels_Game")
    end
    local factory = CS and CS.FrameFactory or nil
    if factory and factory.PresetFrameAttributes then
      factory.PresetFrameAttributes()
    end
    self:RequestUpdateForEvent(event, "core:player_login")
    return
  end

  if event == "CURRENCY_DISPLAY_UPDATE" or event == "PLAYER_MONEY" or event == "UPDATE_FACTION" then
    self:QueueCurrencyRepUpdate(event)
    return
  end

  -- Equipment changes: route to stats + gear panels so ilvl and slot displays refresh.
  if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
    if IsCharacterVisible() then
      local coordinator = GetCoordinator()
      if coordinator and coordinator.RequestUpdate then
        coordinator:RequestUpdate("core:" .. tostring(event), { stats = true, gear = true })
      end
    end
    return
  end

  -- Re-apply layout when combat ends as a safety net (ensures UpdateUIPanelPositions
  -- runs with the correct expanded attributes after any combat-blocked open).
  if event == "PLAYER_REGEN_ENABLED" then
    -- Dismiss the compact combat overlay now that full HaraUI can take over.
    local cp = CS and CS.CombatPanel or nil
    if cp and cp.Hide then cp:Hide() end
    if IsCharacterVisible() then
      local coordinator = GetCoordinator()
      if coordinator and coordinator.RequestUpdate then
        coordinator:RequestUpdate("core:player_regen_enabled", { layout = true })
      end
    end
    return
  end
end

function Core:OnLoad()
  local state = self._state
  if state.loaded then
    return
  end
  state.loaded = true

  if not state.eventFrame then
    state.eventFrame = CreateFrame("Frame")
    state.eventFrame:SetScript("OnEvent", function(_, event, ...)
      self:DispatchEvent(event, ...)
    end)
  end

  RegisterCoreEvents(state.eventFrame)
end

function Core:OnEnable()
  local state = self._state
  if state.enabled then
    return
  end
  state.enabled = true
  RegisterCoreEvents(state.eventFrame)
  self:EnsurePaneVisibilityHooks()
end

function Core:OnDisable()
  local state = self._state
  if not state.enabled then
    return
  end
  state.enabled = false
  if state.eventFrame then
    state.eventFrame:UnregisterAllEvents()
  end
end

Core:OnLoad()
