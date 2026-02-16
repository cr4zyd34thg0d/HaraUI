local ADDON, NS = ...

local VERSION_COMM_PREFIX = "HUIV1"
local VERSION_COMM_PROTOCOL = 1
local VERSION_QUERY_COOLDOWN = 15
local VERSION_RESPONSE_COOLDOWN = 5
local VERSION_PEER_TTL = 600

NS.VERSION_COMM_PREFIX = VERSION_COMM_PREFIX

local versionTracker = {
  prefixRegistered = false,
  prefixRegistrationWarned = false,
  peers = {},
  bestPeer = nil,
  lastQueryAt = 0,
  lastResponseAt = 0,
  warnedOutdated = false,
}

local function GetSelfShortName()
  local me = UnitName and UnitName("player") or nil
  if type(me) ~= "string" or me == "" then
    return nil
  end
  return me
end

local function IsSelfSender(sender)
  if type(sender) ~= "string" or sender == "" then return false end
  local me = GetSelfShortName()
  if not me then return false end
  if sender == me then return true end
  if Ambiguate then
    local short = Ambiguate(sender, "short")
    if short == me then return true end
  end
  local bare = sender:match("^[^-]+")
  return bare == me
end

local function NormalizeSender(sender)
  if type(sender) ~= "string" or sender == "" then return nil end
  if Ambiguate then
    return Ambiguate(sender, "none")
  end
  return sender
end

local function GetVersionBroadcastChannels()
  local channels = {}
  local seen = {}
  local function AddChannel(name)
    if not name or seen[name] then return end
    seen[name] = true
    channels[#channels + 1] = name
  end

  local inInstanceGroup = false
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE ~= nil then
    inInstanceGroup = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) == true
  end
  if inInstanceGroup then
    AddChannel("INSTANCE_CHAT")
  end

  if IsInRaid and IsInRaid() then
    AddChannel("RAID")
  elseif IsInGroup and IsInGroup() then
    AddChannel("PARTY")
  end

  if IsInGuild and IsInGuild() then
    AddChannel("GUILD")
  end

  return channels
end

local function GetLocalBuildInfo()
  local installed = nil
  if NS.GetVersionString then
    installed = NS.GetVersionString()
  elseif NS.GetAddonMetadataField then
    installed = NS.GetAddonMetadataField("Version")
  end
  if type(installed) ~= "string" or installed == "" then
    installed = NS.DEV_VERSION or "2.0.2-dev"
  end
  return {
    installed = installed,
  }
end

local function ComparePeerInfo(left, right)
  if not left and not right then return 0 end
  if not left then return -1 end
  if not right then return 1 end

  local cmp = NS.CompareVersions(left.version, right.version)
  if cmp and cmp ~= 0 then
    return cmp
  end

  local leftSeen = left.seenAt or 0
  local rightSeen = right.seenAt or 0
  if leftSeen < rightSeen then return -1 end
  if leftSeen > rightSeen then return 1 end

  return 0
end

local function RecomputeBestPeer()
  local now = time()
  for key, peer in pairs(versionTracker.peers) do
    local seenAt = peer and peer.seenAt
    if type(seenAt) ~= "number" or (now - seenAt) > VERSION_PEER_TTL then
      versionTracker.peers[key] = nil
    end
  end

  local best = nil
  for _, peer in pairs(versionTracker.peers) do
    if ComparePeerInfo(peer, best) > 0 then
      best = peer
    end
  end
  versionTracker.bestPeer = best
end

local function NotifyVersionInfoUpdated()
  if not NS._huiVersionInfoListeners then return end
  for _, fn in ipairs(NS._huiVersionInfoListeners) do
    if type(fn) == "function" then
      pcall(fn)
    end
  end
end

function NS:RegisterVersionInfoListener(fn)
  if type(fn) ~= "function" then return end
  NS._huiVersionInfoListeners = NS._huiVersionInfoListeners or {}
  for _, existing in ipairs(NS._huiVersionInfoListeners) do
    if existing == fn then return end
  end
  NS._huiVersionInfoListeners[#NS._huiVersionInfoListeners + 1] = fn
end

function NS:UnregisterVersionInfoListener(fn)
  if type(fn) ~= "function" or not NS._huiVersionInfoListeners then return end
  for i = #NS._huiVersionInfoListeners, 1, -1 do
    if NS._huiVersionInfoListeners[i] == fn then
      table.remove(NS._huiVersionInfoListeners, i)
    end
  end
end

function NS.NormalizeVersion(version)
  if type(version) ~= "string" then return nil end
  local parts = {}
  for n in version:gmatch("%d+") do
    parts[#parts + 1] = tonumber(n)
  end
  if #parts == 0 then return nil end
  return parts
end

function NS.CompareVersions(left, right)
  local a = NS.NormalizeVersion(left)
  local b = NS.NormalizeVersion(right)
  if not a or not b then return nil end
  local count = math.max(#a, #b)
  for i = 1, count do
    local av = a[i] or 0
    local bv = b[i] or 0
    if av < bv then return -1 end
    if av > bv then return 1 end
  end
  return 0
end

function NS.GetVersionStatus(info)
  if type(info) ~= "table" then return "unknown" end
  if type(info.status) == "string" and info.status ~= "" then
    return info.status
  end

  local cmp = info.cmp
  if cmp ~= nil then
    if cmp < 0 then return "out-of-date" end
    if cmp > 0 then return "ahead" end
    if cmp == 0 then return "up-to-date" end
  end

  return "unknown"
end

function NS.GetVersionInfo()
  local localInfo = GetLocalBuildInfo()
  local installed = localInfo.installed
  RecomputeBestPeer()

  local latest
  local source = "local-metadata"
  local authoritative = false
  local peerName

  if versionTracker.bestPeer and type(versionTracker.bestPeer.version) == "string" and versionTracker.bestPeer.version ~= "" then
    authoritative = true
    source = "addon-comms"
    latest = versionTracker.bestPeer.version
    peerName = versionTracker.bestPeer.sender
  else
    latest = installed
  end

  local cmp = authoritative and NS.CompareVersions(installed, latest) or nil
  local status = authoritative and NS.GetVersionStatus({ cmp = cmp }) or "unknown"

  return {
    installed = installed,
    latest = latest,
    cmp = cmp,
    status = status,
    source = source,
    authoritative = authoritative,
    peerName = peerName,
  }
end

local function PrintOutOfDateNotice()
  local info = NS.GetVersionInfo and NS.GetVersionInfo() or nil
  local installed = info and info.installed or nil
  local latest = info and info.latest or nil
  local status = info and (info.status or (NS.GetVersionStatus and NS.GetVersionStatus(info))) or "unknown"
  if status ~= "out-of-date" then
    versionTracker.warnedOutdated = false
    return
  end
  if versionTracker.warnedOutdated then
    return
  end
  if status == "out-of-date" then
    local source = tostring(info and info.source or "unknown")
    local detail = ""
    if source == "addon-comms" and info and info.peerName then
      detail = (" (seen from %s)"):format(tostring(info.peerName))
    end
    NS.Print(("Update available: installed %s, latest %s%s."):format(tostring(installed), tostring(latest), detail))
    versionTracker.warnedOutdated = true
  end
end
NS.PrintOutOfDateNotice = PrintOutOfDateNotice

local function BuildVersionResponseMessage()
  local localInfo = GetLocalBuildInfo()
  local installed = tostring(localInfo.installed or "0.0.0")
  return ("V|%d|%s"):format(VERSION_COMM_PROTOCOL, installed)
end

local function SendVersionCommMessage(payload)
  if type(payload) ~= "string" or payload == "" then return end
  if not versionTracker.prefixRegistered then return end
  if NS.IsChatMessagingLocked() then return end
  local channels = GetVersionBroadcastChannels()
  for _, channel in ipairs(channels) do
    pcall(NS.SendAddonMessageCompat, VERSION_COMM_PREFIX, payload, channel)
  end
end

local function SendVersionQuery(force)
  local now = GetTime and GetTime() or 0
  if not force and ((now - (versionTracker.lastQueryAt or 0)) < VERSION_QUERY_COOLDOWN) then
    return
  end
  versionTracker.lastQueryAt = now
  SendVersionCommMessage(("Q|%d"):format(VERSION_COMM_PROTOCOL))
end
NS.SendVersionQuery = SendVersionQuery

local function SendVersionResponse(force)
  local now = GetTime and GetTime() or 0
  if not force and ((now - (versionTracker.lastResponseAt or 0)) < VERSION_RESPONSE_COOLDOWN) then
    return
  end
  versionTracker.lastResponseAt = now
  SendVersionCommMessage(BuildVersionResponseMessage())
end
NS.SendVersionResponse = SendVersionResponse

local function ProcessPeerVersion(sender, version)
  if type(version) ~= "string" or version == "" then return end
  if IsSelfSender(sender) then return end
  local key = NormalizeSender(sender) or sender
  if type(key) ~= "string" or key == "" then return end

  local current = versionTracker.peers[key]
  local changed = (not current)
    or current.version ~= version

  versionTracker.peers[key] = {
    sender = key,
    rawSender = sender,
    version = version,
    seenAt = time(),
  }

  local oldBest = versionTracker.bestPeer
  RecomputeBestPeer()
  if changed or oldBest ~= versionTracker.bestPeer then
    NotifyVersionInfoUpdated()
    PrintOutOfDateNotice()
  end
end

local function HandleVersionCommMessage(message, sender)
  if type(message) ~= "string" or message == "" then return end
  if IsSelfSender(sender) then return end

  local msgType, protocol, p1 = strsplit("|", message)
  if tonumber(protocol) ~= VERSION_COMM_PROTOCOL then
    return
  end

  if msgType == "Q" then
    SendVersionResponse(false)
    return
  end

  if msgType ~= "V" then
    return
  end

  local version = tostring(p1 or "")
  ProcessPeerVersion(sender, version)
end
NS.HandleVersionCommMessage = HandleVersionCommMessage

local function InitializeVersionTracker()
  if versionTracker.prefixRegistered then return end
  versionTracker.prefixRegistered = NS.RegisterAddonMessagePrefixCompat(VERSION_COMM_PREFIX)
  if not versionTracker.prefixRegistered then
    if not versionTracker.prefixRegistrationWarned then
      NS:Debug("Version comm prefix registration failed:", VERSION_COMM_PREFIX)
      versionTracker.prefixRegistrationWarned = true
    end
  elseif versionTracker.prefixRegistrationWarned then
    NS:Debug("Version comm prefix registration recovered:", VERSION_COMM_PREFIX)
    versionTracker.prefixRegistrationWarned = false
  end
end
NS.InitializeVersionTracker = InitializeVersionTracker

function NS.IsVersionTrackerInitialized()
  return versionTracker.prefixRegistered
end
