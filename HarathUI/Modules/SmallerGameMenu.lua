local ADDON, NS = ...
local M = {}
NS:RegisterModule("gamemenu", M)
M.active = false
M.BASELINE_WIDTH = 5120
M.BASELINE_HEIGHT = 1440
M.BASELINE_SCALE = 0.70
M.MIN_SCALE = 0.45
M.MAX_SCALE = 1.20

-- NOTE: This feature may cause taint issues with Edit Mode
-- The taint occurs because modifying GameMenuFrame can interfere with
-- Blizzard's protected UI frame access during Edit Mode initialization

local function IsEnabled(db)
  return db and db.gamemenu and db.gamemenu.enabled ~= false
end

local function Clamp(v, minv, maxv)
  if v < minv then return minv end
  if v > maxv then return maxv end
  return v
end

local function GetCurrentResolution()
  if type(GetPhysicalScreenSize) == "function" then
    local w, h = GetPhysicalScreenSize()
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      return w, h
    end
  end
  if UIParent and UIParent.GetWidth and UIParent.GetHeight then
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      return w, h
    end
  end
  return M.BASELINE_WIDTH, M.BASELINE_HEIGHT
end

local function GetResolutionScale()
  local _, h = GetCurrentResolution()
  local ratio = h / M.BASELINE_HEIGHT
  return Clamp(M.BASELINE_SCALE * ratio, M.MIN_SCALE, M.MAX_SCALE)
end

local function ApplyScale()
  local db = NS:GetDB()
  if not GameMenuFrame then return end

  if IsEnabled(db) then
    GameMenuFrame:SetScale(GetResolutionScale())
  else
    GameMenuFrame:SetScale(1.0)
  end
end

local function InstallResolutionHooks()
  if M._resolutionHooksInstalled then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("DISPLAY_SIZE_CHANGED")
  f:RegisterEvent("UI_SCALE_CHANGED")
  f:SetScript("OnEvent", function()
    if not M.active then return end
    ApplyScale()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, ApplyScale)
    end
  end)
  M._resolutionHooksInstalled = true
  M._resolutionWatcher = f
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
  InstallResolutionHooks()
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
