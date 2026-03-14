--[[
  Merchant Module

  Auto-repairs all gear and auto-sells grey (quality 0) items whenever a
  merchant window opens.  Both behaviours can be toggled independently in
  the Merchant options page.

  Events:
    MERCHANT_SHOW
--]]

local ADDON, NS = ...
local M = {}
NS:RegisterModule("merchant", M)
M.active = false

local state = { eventFrame = nil }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function HaraMsg(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffF36D08HaraUI|r " .. tostring(msg))
  end
end

local function AutoRepair()
  if not CanMerchantRepair or not CanMerchantRepair() then return end
  local cost, canRepair = GetRepairAllCost()
  if not canRepair or not cost or cost == 0 then return end
  if GetMoney() < cost then
    HaraMsg("Not enough gold to repair. (need " .. GetCoinTextureString(cost) .. ")")
    return
  end
  RepairAllItems()
  HaraMsg("Repaired all items for " .. GetCoinTextureString(cost) .. ".")
end

local function AutoSellJunk()
  local sold = 0
  local goldCopper = 0
  for bag = 0, 4 do
    local numSlots = C_Container and C_Container.GetContainerNumSlots
      and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, numSlots do
      local info = C_Container and C_Container.GetContainerItemInfo
        and C_Container.GetContainerItemInfo(bag, slot) or nil
      if info and info.quality == 0 and not info.isLocked then
        if info.itemLink then
          local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(info.itemLink)
          if sellPrice and sellPrice > 0 then
            goldCopper = goldCopper + sellPrice * (info.stackCount or 1)
          end
        end
        if C_Container and C_Container.UseContainerItem then
          C_Container.UseContainerItem(bag, slot)
        else
          UseContainerItem(bag, slot)
        end
        sold = sold + 1
      end
    end
  end
  if sold > 0 then
    HaraMsg("Sold " .. sold .. " junk item" .. (sold == 1 and "" or "s")
      .. " for " .. GetCoinTextureString(goldCopper) .. ".")
  end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function M:Apply()
  local db = NS:GetDB()
  if not db or not db.merchant or db.merchant.enabled == false then
    return self:Disable()
  end
  M.active = true

  if not state.eventFrame then
    state.eventFrame = CreateFrame("Frame")
    state.eventFrame:RegisterEvent("MERCHANT_SHOW")
    state.eventFrame:SetScript("OnEvent", function(_, event)
      if not M.active then return end
      if event ~= "MERCHANT_SHOW" then return end
      local mdb = NS:GetDB().merchant
      if mdb and mdb.autoRepair then
        AutoRepair()
      end
      if mdb and mdb.autoSell then
        -- Small defer so the merchant window is fully ready.
        C_Timer.After(0.15, function()
          if M.active then AutoSellJunk() end
        end)
      end
    end)
  end
end

function M:Disable()
  M.active = false
  if state.eventFrame then
    state.eventFrame:UnregisterAllEvents()
    state.eventFrame:SetScript("OnEvent", nil)
    state.eventFrame = nil
  end
end
