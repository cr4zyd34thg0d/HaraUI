local ADDON, NS = ...
local M = {}
NS:RegisterModule("gamemenu", M)
M.active = false

-- NOTE: This feature may cause taint issues with Edit Mode
-- The taint occurs because modifying GameMenuFrame can interfere with
-- Blizzard's protected UI frame access during Edit Mode initialization

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.gamemenu.enabled then
    self:Disable()
    return
  end
  M.active = true

  if GameMenuFrame then
    GameMenuFrame:SetScale(db.gamemenu.scale or 0.85)
  end
end

function M:Disable()
  M.active = false
  if GameMenuFrame then GameMenuFrame:SetScale(1.0) end
end
