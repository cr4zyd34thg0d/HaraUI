local ADDON, NS = ...

local DEV_VERSION = "2.2.0"
local VERSION_TOKEN = "v2.2.0"

local function ReadAddonVersion()
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, "Version")
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, "Version")
  end
  return nil
end

local function GetVersionString()
  local version = ReadAddonVersion()
  if type(version) ~= "string" or version == "" then
    return DEV_VERSION
  end
  if version:find(VERSION_TOKEN, 1, true) then
    return DEV_VERSION
  end
  return version
end

NS.DEV_VERSION = DEV_VERSION
NS.VERSION_TOKEN = VERSION_TOKEN
NS.GetVersionString = GetVersionString
