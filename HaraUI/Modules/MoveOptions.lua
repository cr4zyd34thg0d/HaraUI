local ADDON, NS = ...
local M = {}
NS:RegisterModule("moveoptions", M)
M.active = false

local function MakeFrameMovable(frame)
  if not frame or frame._huiMoveOptions then return end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetClampedToScreen(true)

  frame:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  frame._huiMoveOptions = true
end

local function GetSettingsFrame()
  if SettingsPanel then return SettingsPanel end
  if SettingsFrame then return SettingsFrame end
  if InterfaceOptionsFrame then return InterfaceOptionsFrame end
  return nil
end

local function IsEnabled(db)
  if not db or not db.general then return false end
  return db.general.moveOptions
end

function M:Apply()
  local db = NS:GetDB()
  if not IsEnabled(db) then
    self:Disable()
    return
  end
  M.active = true

  local frame = GetSettingsFrame()
  if not frame then return end

  MakeFrameMovable(frame)
end

function M:Disable()
  M.active = false
  local frame = GetSettingsFrame()
  if not frame or not frame._huiMoveOptions then return end
  frame:SetScript("OnDragStart", nil)
  frame:SetScript("OnDragStop", nil)
  frame:RegisterForDrag()
  frame:SetMovable(false)
  frame._huiMoveOptions = nil
end
