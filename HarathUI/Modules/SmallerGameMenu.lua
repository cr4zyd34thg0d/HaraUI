local ADDON, NS = ...
local M = {}
NS:RegisterModule("gamemenu", M)
M.active = false
M.MENU_SCALE = 0.85

-- NOTE: This feature may cause taint issues with Edit Mode
-- The taint occurs because modifying GameMenuFrame can interfere with
-- Blizzard's protected UI frame access during Edit Mode initialization

local function IsEnabled(db)
  return db and db.gamemenu and db.gamemenu.enabled ~= false
end

local function ApplyScale()
  local db = NS:GetDB()
  if not GameMenuFrame then return end

  if IsEnabled(db) then
    GameMenuFrame:SetScale(M.MENU_SCALE)
  else
    GameMenuFrame:SetScale(1.0)
  end
end

local function InstallHooks()
  if not M._toggleHookInstalled and type(ToggleGameMenu) == "function" then
    M._toggleHookInstalled = true
    hooksecurefunc("ToggleGameMenu", function()
      if not M.active then return end
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          ApplyScale()
          if C_Timer and C_Timer.After then
            C_Timer.After(0.05, ApplyScale)
          end
        end)
      else
        ApplyScale()
      end
    end)
  end

  if not M._updateHookInstalled and type(GameMenuFrame_UpdateVisibleButtons) == "function" then
    M._updateHookInstalled = true
    hooksecurefunc("GameMenuFrame_UpdateVisibleButtons", function()
      if not M.active then return end
      ApplyScale()
    end)
  end

  if M._hooksInstalled then return end
  if not (GameMenuFrame and GameMenuFrame.HookScript) then return end

  M._hooksInstalled = true
  GameMenuFrame:HookScript("OnShow", function()
    if not M.active then return end
    ApplyScale()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, ApplyScale)
    end
  end)
end

function M:Apply()
  local db = NS:GetDB()
  db.gamemenu = db.gamemenu or {}
  if db.gamemenu.enabled == nil then
    db.gamemenu.enabled = true
  end

  if not IsEnabled(db) then
    self:Disable()
    return
  end
  M.active = true
  InstallHooks()
  ApplyScale()
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, ApplyScale)
  end
end

function M:Disable()
  M.active = false
  ApplyScale()
end
