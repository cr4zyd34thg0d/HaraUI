local ADDON, NS = ...

local function GetAddonMetadataField(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, field)
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, field)
  end
  return nil
end
NS.GetAddonMetadataField = GetAddonMetadataField

local function RegisterAddonMessagePrefixCompat(prefix)
  local function IsRegistered()
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
      local ok = C_ChatInfo.IsAddonMessagePrefixRegistered(prefix)
      if ok == true or ok == 1 then
        return true
      end
    end
    if IsAddonMessagePrefixRegistered then
      local ok = IsAddonMessagePrefixRegistered(prefix)
      if ok == true or ok == 1 then
        return true
      end
    end
    return false
  end

  if type(prefix) ~= "string" or prefix == "" then
    return false
  end

  if IsRegistered() then
    return true
  end

  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    local ok = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if ok == true or ok == 1 or IsRegistered() then
      return true
    end
  end
  if RegisterAddonMessagePrefix then
    local ok = RegisterAddonMessagePrefix(prefix)
    if ok == true or ok == 1 or IsRegistered() then
      return true
    end
  end
  return IsRegistered()
end
NS.RegisterAddonMessagePrefixCompat = RegisterAddonMessagePrefixCompat

local function SendAddonMessageCompat(prefix, message, channel, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    return C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
  end
  if SendAddonMessage then
    return SendAddonMessage(prefix, message, channel, target)
  end
  return false
end
NS.SendAddonMessageCompat = SendAddonMessageCompat

local function IsChatMessagingLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    return C_ChatInfo.InChatMessagingLockdown()
  end
  return false
end
NS.IsChatMessagingLocked = IsChatMessagingLocked

