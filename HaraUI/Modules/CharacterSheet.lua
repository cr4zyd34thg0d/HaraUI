local ADDON, NS = ...

local M = {}
M.active = false

local function GetCoordinator()
  local cs = NS and NS.CharacterSheet or nil
  local coordinator = cs and cs.Coordinator or nil
  if type(coordinator) == "table" then
    return coordinator
  end
  return nil
end

local function Forward(method, ...)
  local coordinator = GetCoordinator()
  local fn = coordinator and coordinator[method]
  if type(fn) == "function" then
    return fn(coordinator, ...)
  end
end

function M:Apply()
  local applied = Forward("Apply")
  M.active = applied == true
  return applied
end

function M:Refresh()
  return Forward("Refresh")
end

function M:Disable()
  local disabled = Forward("Disable")
  M.active = false
  return disabled
end

NS:RegisterModule("charsheet", M)
