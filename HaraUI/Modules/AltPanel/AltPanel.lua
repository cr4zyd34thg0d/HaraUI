local ADDON, NS = ...

local AP = NS.AltPanel
if not AP then return end

local M = {}
M.active = false
NS:RegisterModule("altpanel", M)

local Data = AP.Data
local Window = AP.Window

---------------------------------------------------------------------------
-- Event frame
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

---------------------------------------------------------------------------
-- Throttle helper (simple per-key debounce)
---------------------------------------------------------------------------
local pendingTimers = {}

local function Throttle(key, delay, fn)
  if pendingTimers[key] then return end
  pendingTimers[key] = true
  C_Timer.After(delay, function()
    pendingTimers[key] = nil
    fn()
  end)
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------
local function RefreshIfShown()
  if Window and Window:IsShown() then
    Window:Refresh()
  end
end

local function OnPlayerEnteringWorld()
  if not Data then return end
  Data:CheckWeeklyReset()
  Data:UpdateAll()
  RefreshIfShown()

  -- M+ API often isn't ready at login; request data and retry after a delay
  if C_MythicPlus and C_MythicPlus.RequestMapInfo then
    C_MythicPlus.RequestMapInfo()
  end
  if C_MythicPlus and C_MythicPlus.RequestCurrentAffixes then
    C_MythicPlus.RequestCurrentAffixes()
  end
  C_Timer.After(3, function()
    if not Data then return end
    Data:UpdateMythicPlus()
    Data:UpdateKeystone()
    Data:UpdateVault()
    Data:UpdateCurrencies()
    Data:UpdateRaidLockouts()
    Data:UpdateCharacterInfo()
    RefreshIfShown()
  end)
  -- Request instance info for raid lockouts
  if RequestRaidInfo then RequestRaidInfo() end
end

local function OnEquipmentChanged()
  Throttle("equip", 2, function()
    if not Data then return end
    Data:UpdateCharacterInfo()
    Data:UpdateEquipment()
    RefreshIfShown()
  end)
end

local function OnMythicPlusUpdate()
  Throttle("mplus", 1, function()
    if not Data then return end
    Data:UpdateMythicPlus()
    Data:UpdateKeystone()
    RefreshIfShown()
  end)
end

local function OnVaultUpdate()
  Throttle("vault", 1, function()
    if not Data then return end
    Data:UpdateVault()
    RefreshIfShown()
  end)
end

local function OnKeystoneUpdate()
  Throttle("keystone", 2, function()
    if not Data then return end
    Data:UpdateKeystone()
    RefreshIfShown()
  end)
end

local function OnCurrencyUpdate()
  Throttle("currency", 2, function()
    if not Data then return end
    Data:UpdateCurrencies()
    RefreshIfShown()
  end)
end

local function OnRaidUpdate()
  Throttle("raid", 2, function()
    if not Data then return end
    Data:UpdateRaidLockouts()
    RefreshIfShown()
  end)
end

---------------------------------------------------------------------------
-- Event dispatch
---------------------------------------------------------------------------
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    OnPlayerEnteringWorld()
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    OnEquipmentChanged()
  elseif event == "CHALLENGE_MODE_MAPS_UPDATE" or event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then
    OnMythicPlusUpdate()
  elseif event == "WEEKLY_REWARDS_UPDATE" then
    OnVaultUpdate()
  elseif event == "BAG_UPDATE_DELAYED" then
    OnKeystoneUpdate()
  elseif event == "CURRENCY_DISPLAY_UPDATE" or event == "CHAT_MSG_CURRENCY" then
    OnCurrencyUpdate()
  elseif event == "UPDATE_INSTANCE_INFO" or event == "BOSS_KILL"
      or event == "ENCOUNTER_END" or event == "RAID_INSTANCE_WELCOME" then
    OnRaidUpdate()
  end
end)

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
local function IsEnabled()
  local db = NS:GetDB()
  return db and db.altpanel and db.altpanel.enabled
end

function M:Apply()
  if not IsEnabled() then
    self:Disable()
    return
  end

  M.active = true
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
  eventFrame:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE")
  eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
  eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
  eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
  eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
  eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
  eventFrame:RegisterEvent("BOSS_KILL")
  eventFrame:RegisterEvent("ENCOUNTER_END")
  eventFrame:RegisterEvent("RAID_INSTANCE_WELCOME")
end

function M:Disable()
  M.active = false
  eventFrame:UnregisterAllEvents()

  if Window and Window:IsShown() then
    Window:Hide()
  end
end

---------------------------------------------------------------------------
-- Public API (called by slash command)
---------------------------------------------------------------------------
function M:Toggle()
  if not M.active then
    NS.Print("AltPanel is disabled.")
    return
  end
  if Window then
    Window:Toggle()
  end
end
