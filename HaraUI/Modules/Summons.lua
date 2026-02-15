local ADDON, NS = ...
local M = {}
NS:RegisterModule("summons", M)
M.active = false

local eventFrame = CreateFrame("Frame")
local pendingConfirm = false

local function IsEnabled()
  local db = NS:GetDB()
  return db and db.summons and db.summons.enabled
end

local function HasPendingSummon()
  if C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft then
    local secs = C_SummonInfo.GetSummonConfirmTimeLeft() or 0
    return secs > 0
  end
  if StaticPopup_FindVisible then
    return StaticPopup_FindVisible("CONFIRM_SUMMON") ~= nil
  end
  return false
end

local function TryConfirmSummon()
  if not IsEnabled() then
    pendingConfirm = false
    return
  end
  if not HasPendingSummon() then
    pendingConfirm = false
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    pendingConfirm = true
    return
  end

  if C_SummonInfo and C_SummonInfo.ConfirmSummon then
    local ok = pcall(C_SummonInfo.ConfirmSummon)
    if ok then
      pendingConfirm = false
    end
  end
end

eventFrame:SetScript("OnEvent", function(_, event)
  if event == "CONFIRM_SUMMON" then
    pendingConfirm = true
    TryConfirmSummon()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingConfirm then
      TryConfirmSummon()
    end
  end
end)

function M:Apply()
  if not IsEnabled() then
    self:Disable()
    return
  end

  M.active = true
  eventFrame:RegisterEvent("CONFIRM_SUMMON")
  eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function M:Disable()
  M.active = false
  pendingConfirm = false
  eventFrame:UnregisterEvent("CONFIRM_SUMMON")
  eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

