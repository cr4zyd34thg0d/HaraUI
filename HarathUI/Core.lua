local ADDON, NS = ...
local f = CreateFrame("Frame")
NS.frame = f
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local spellIDTooltipHooked = false
local spellIDTooltipDataHooked = false
local VERSION_COMM_PREFIX = "HUIV1"
local VERSION_COMM_PROTOCOL = 1
local VERSION_QUERY_COOLDOWN = 15
local VERSION_RESPONSE_COOLDOWN = 5
local VERSION_PEER_TTL = 600

local versionTracker = {
  prefixRegistered = false,
  prefixRegistrationWarned = false,
  peers = {},
  bestPeer = nil,
  lastQueryAt = 0,
  lastResponseAt = 0,
  warnedOutdated = false,
}

local function DeepCopyDefaults(dst, src)
  if type(dst) ~= "table" then dst = {} end
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = DeepCopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff6ddcffHaraUI|r: " .. tostring(msg))
end
NS.Print = Print

local function GetAddonMetadataField(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, field)
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, field)
  end
  return nil
end

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

local function SendAddonMessageCompat(prefix, message, channel, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    return C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
  end
  if SendAddonMessage then
    return SendAddonMessage(prefix, message, channel, target)
  end
  return false
end

local function IsChatMessagingLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    return C_ChatInfo.InChatMessagingLockdown()
  end
  return false
end

local function CompareBuildDates(left, right)
  if type(left) ~= "string" or type(right) ~= "string" then return nil end
  if not left:match("^%d%d%d%d%-%d%d%-%d%d$") then return nil end
  if not right:match("^%d%d%d%d%-%d%d%-%d%d$") then return nil end
  if left < right then return -1 end
  if left > right then return 1 end
  return 0
end

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
    return Ambiguate(sender, "short")
  end
  return sender:match("^[^-]+") or sender
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
  local installed = GetAddonMetadataField("Version")
  local packagedVersion = GetAddonMetadataField("X-GitVersion") or GetAddonMetadataField("X-Git-Version")
  local buildCommit = GetAddonMetadataField("X-Build-Commit")
  local packagedCommit = GetAddonMetadataField("X-Git-Commit")
  local buildDate = GetAddonMetadataField("X-Build-Date")
  local commit = buildCommit or packagedCommit
  return {
    installed = installed,
    packagedVersion = packagedVersion,
    buildCommit = buildCommit,
    packagedCommit = packagedCommit,
    commit = commit,
    buildDate = buildDate,
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

  local dateCmp = CompareBuildDates(left.buildDate, right.buildDate)
  if dateCmp and dateCmp ~= 0 then
    return dateCmp
  end

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

function NS.NormalizeCommitHash(hash)
  if type(hash) ~= "string" then return nil end
  local clean = hash:lower():match("(%x+)")
  if not clean or clean == "" then return nil end
  return clean
end

function NS.CompareCommitHashes(installed, latest)
  local a = NS.NormalizeCommitHash(installed)
  local b = NS.NormalizeCommitHash(latest)
  if not a or not b then return nil end
  if a == b then return 0 end
  -- Treat short/long forms of the same SHA as equal.
  if #a < #b and b:sub(1, #a) == a then return 0 end
  if #b < #a and a:sub(1, #b) == b then return 0 end
  -- Git hashes alone cannot tell ahead/behind without graph context.
  return -1
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

  if info.strictCommit then
    local hashCmp = info.hashCmp
    if hashCmp == nil and (info.buildCommit or info.commit) and info.latestCommit then
      hashCmp = NS.CompareCommitHashes(info.buildCommit or info.commit, info.latestCommit)
    end
    if hashCmp ~= nil then
      if hashCmp == 0 then return "up-to-date" end
      if hashCmp < 0 then return "out-of-date" end
    end
  end

  return "unknown"
end

function NS.GetVersionInfo()
  local localInfo = GetLocalBuildInfo()
  local installed = localInfo.installed
  local buildCommit = localInfo.buildCommit or localInfo.commit
  local buildDate = localInfo.buildDate
  RecomputeBestPeer()

  local latest, latestCommit, latestBuildDate
  local source = "local-toc"
  local sourceLabel = "Local metadata only"
  local authoritative = false
  local peerName

  local external = NS._huiHostedVersionInfo
  if type(external) == "table" and type(external.version) == "string" and external.version ~= "" then
    authoritative = true
    source = "external-feed"
    sourceLabel = external.sourceLabel or "External feed"
    latest = external.version
    latestCommit = external.commit
    latestBuildDate = external.buildDate
  elseif versionTracker.bestPeer and type(versionTracker.bestPeer.version) == "string" and versionTracker.bestPeer.version ~= "" then
    authoritative = true
    source = "addon-comms"
    sourceLabel = "Addon comms"
    latest = versionTracker.bestPeer.version
    latestCommit = versionTracker.bestPeer.commit
    latestBuildDate = versionTracker.bestPeer.buildDate
    peerName = versionTracker.bestPeer.sender
  end

  local cmp = authoritative and NS.CompareVersions(installed, latest) or nil
  local hashCmp = (latestCommit and buildCommit) and NS.CompareCommitHashes(buildCommit, latestCommit) or nil
  local status = authoritative and NS.GetVersionStatus({ cmp = cmp }) or "unknown"

  return {
    installed = installed,
    latest = latest,
    commit = buildCommit or localInfo.commit,
    buildCommit = buildCommit or localInfo.commit,
    latestCommit = latestCommit,
    buildDate = buildDate,
    latestBuildDate = latestBuildDate,
    cmp = cmp,
    hashCmp = hashCmp,
    status = status,
    source = source,
    sourceLabel = sourceLabel,
    authoritative = authoritative,
    peerName = peerName,
    packagedVersion = localInfo.packagedVersion,
    packagedCommit = localInfo.packagedCommit,
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
    elseif source == "external-feed" and info and info.sourceLabel then
      detail = (" (%s)"):format(tostring(info.sourceLabel))
    end
    Print(("Update available: installed v%s, latest v%s%s."):format(tostring(installed), tostring(latest), detail))
    versionTracker.warnedOutdated = true
  end
end

local function BuildVersionResponseMessage()
  local localInfo = GetLocalBuildInfo()
  local installed = tostring(localInfo.installed or "0.0.0")
  local commit = tostring(localInfo.buildCommit or localInfo.commit or "")
  local buildDate = tostring(localInfo.buildDate or "")
  return ("V|%d|%s|%s|%s"):format(VERSION_COMM_PROTOCOL, installed, commit, buildDate)
end

local function SendVersionCommMessage(payload)
  if type(payload) ~= "string" or payload == "" then return end
  if not versionTracker.prefixRegistered then return end
  if IsChatMessagingLocked() then return end
  local channels = GetVersionBroadcastChannels()
  for _, channel in ipairs(channels) do
    pcall(SendAddonMessageCompat, VERSION_COMM_PREFIX, payload, channel)
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

local function SendVersionResponse(force)
  local now = GetTime and GetTime() or 0
  if not force and ((now - (versionTracker.lastResponseAt or 0)) < VERSION_RESPONSE_COOLDOWN) then
    return
  end
  versionTracker.lastResponseAt = now
  SendVersionCommMessage(BuildVersionResponseMessage())
end

local function ProcessPeerVersion(sender, version, commit, peerBuildDate)
  if type(version) ~= "string" or version == "" then return end
  if IsSelfSender(sender) then return end
  local key = NormalizeSender(sender) or sender
  if type(key) ~= "string" or key == "" then return end

  local current = versionTracker.peers[key]
  local changed = (not current)
    or current.version ~= version
    or current.commit ~= commit
    or current.buildDate ~= peerBuildDate

  versionTracker.peers[key] = {
    sender = key,
    rawSender = sender,
    version = version,
    commit = commit,
    buildDate = peerBuildDate,
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

  local msgType, protocol, p1, p2, p3 = strsplit("|", message)
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
  local commit = (type(p2) == "string" and p2 ~= "") and p2 or nil
  local peerBuildDate = (type(p3) == "string" and p3 ~= "") and p3 or nil
  ProcessPeerVersion(sender, version, commit, peerBuildDate)
end

local function InitializeVersionTracker()
  if versionTracker.prefixRegistered then return end
  versionTracker.prefixRegistered = RegisterAddonMessagePrefixCompat(VERSION_COMM_PREFIX)
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

function NS:SetHostedVersionInfo(info)
  local old = NS._huiHostedVersionInfo
  if type(info) ~= "table" then
    NS._huiHostedVersionInfo = nil
  else
    local version = type(info.version) == "string" and info.version or nil
    local commit = type(info.commit) == "string" and info.commit or nil
    local buildDate = type(info.buildDate) == "string" and info.buildDate or nil
    local sourceLabel = type(info.sourceLabel) == "string" and info.sourceLabel or "External feed"
    if version and version ~= "" then
      NS._huiHostedVersionInfo = {
        version = version,
        commit = commit,
        buildDate = buildDate,
        sourceLabel = sourceLabel,
      }
    else
      NS._huiHostedVersionInfo = nil
    end
  end

  local new = NS._huiHostedVersionInfo
  local changed = (old == nil and new ~= nil)
    or (old ~= nil and new == nil)
    or (old and new and (
      old.version ~= new.version
      or old.commit ~= new.commit
      or old.buildDate ~= new.buildDate
      or old.sourceLabel ~= new.sourceLabel
    ))
  if changed then
    NotifyVersionInfoUpdated()
    PrintOutOfDateNotice()
  end
end

function NS:Debug(...)
  local db = NS:GetDB()
  if db and db.general.debug then
    local args = {...}
    local msg = ""
    for i = 1, #args do
      msg = msg .. tostring(args[i])
      if i < #args then msg = msg .. " " end
    end
    Print("[Debug] " .. msg)
  end
end

function NS:GetDB()
  local success, result = pcall(function()
    return HarathUI_DB and HarathUI_DB.profile
  end)
  if not success then
    NS:Debug("Error accessing database:", result)
    return NS.DEFAULTS.profile
  end
  return result
end

function NS:InitDB()
  -- Validate saved data structure
  if HarathUI_DB and type(HarathUI_DB) ~= "table" then
    Print("Saved data corrupted, resetting to defaults")
    HarathUI_DB = nil
  end

  HarathUI_DB = HarathUI_DB or {}

  -- Safely merge defaults with error handling
  local success, result = pcall(DeepCopyDefaults, HarathUI_DB.profile or {}, NS.DEFAULTS.profile)
  if success then
    HarathUI_DB.profile = result
  else
    Print("Error loading settings, using defaults")
    HarathUI_DB.profile = DeepCopyDefaults({}, NS.DEFAULTS.profile)
  end
end

NS.Modules = {}

function NS:RegisterModule(name, mod)
  NS.Modules[name] = mod
end

function NS:ForEachModule(fn)
  for _, mod in pairs(NS.Modules) do
    if type(fn) == "function" then fn(mod) end
  end
end

function NS:ApplyAll()
  local db = NS:GetDB()
  if not db or not db.general.enabled then
    NS:ForEachModule(function(m)
      if m.Disable then
        local success, err = pcall(m.Disable, m)
        if not success then
          NS:Debug("Error disabling module:", err)
        end
      end
    end)
    return
  end
  NS:ForEachModule(function(m)
    if m.Apply then
      local success, err = pcall(m.Apply, m)
      if not success then
        NS:Debug("Error applying module:", err)
      end
    end
  end)
end

local function EnsureMinimapButton()
  if not LDB or not LDBIcon then return end
  local db = NS:GetDB()
  if not db or not db.general then return end

  if type(db.general.minimapButton) ~= "table" then
    local hide = false
    if type(db.general.minimapButton) == "boolean" then
      hide = not db.general.minimapButton
    end
    db.general.minimapButton = { hide = hide }
  end
  if db.general.minimapButton.hide == nil then
    db.general.minimapButton.hide = false
  end

  if not NS._huiLDBObject then
    NS._huiLDBObject = LDB:NewDataObject("HaraUI", {
      type = "launcher",
      text = "HaraUI",
      icon = "Interface\\AddOns\\HarathUI\\Media\\mmicon.tga",
      OnClick = function(_, button)
        if button == "LeftButton" or button == "RightButton" then
          if NS.OpenOptions then NS:OpenOptions() end
        end
      end,
      OnTooltipShow = function(tt)
        if not tt then return end
        tt:AddLine("HaraUI", 1, 0.82, 0)
        tt:AddLine("Click: Open options", 1, 1, 1)
      end,
    })
    LDBIcon:Register("HaraUI", NS._huiLDBObject, db.general.minimapButton)
  end

  if db.general.minimapButton.hide then
    LDBIcon:Hide("HaraUI")
  else
    LDBIcon:Show("HaraUI")
  end
end

local function HookSpellIDTooltips()
  if spellIDTooltipHooked then return end
  spellIDTooltipHooked = true

  local function ShouldShow()
    local db = NS:GetDB()
    return db and db.general and db.general.showSpellIDs
  end

  local function AddSpellIDLine(tt, spellID)
    if not tt or type(spellID) ~= "number" then return end
    tt:AddLine(("Spell ID: %d"):format(spellID), 0.7, 0.7, 0.7)
    tt:Show()
  end

  -- Retail 12.x+ spell tooltips are data-driven; use TooltipDataProcessor when available.
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    spellIDTooltipDataHooked = true
    for key, tooltipType in pairs(Enum.TooltipDataType) do
      if type(key) == "string" and type(tooltipType) == "number" and string.find(string.lower(key), "spell", 1, true) then
        TooltipDataProcessor.AddTooltipPostCall(tooltipType, function(tt, data)
          if not ShouldShow() then return end
          if not tt or type(data) ~= "table" then return end
          local spellID = data.spellID or data.id
          if type(spellID) == "number" then
            AddSpellIDLine(tt, spellID)
          end
        end)
      end
    end
  end

  -- Compatibility fallback for clients without TooltipDataProcessor spell callbacks.
  local function Attach(tooltip)
    if not tooltip or not tooltip.HookScript then return end
    tooltip:HookScript("OnTooltipSetItem", function(tt)
      if not ShouldShow() then return end
      if not tt or not tt.GetSpell then return end
      local _, spellID = tt:GetSpell()
      if type(spellID) == "number" then
        AddSpellIDLine(tt, spellID)
      end
    end)
  end

  if not spellIDTooltipDataHooked then
    Attach(GameTooltip)
    Attach(ItemRefTooltip)
    Attach(ShoppingTooltip1)
    Attach(ShoppingTooltip2)
  end
end

function NS:UpdateMinimapButton()
  EnsureMinimapButton()
end

function NS:MakeMovable(frame, moduleKey, label)
  frame:SetMovable(true)
  frame:EnableMouse(false)
  frame:RegisterForDrag("LeftButton")

  local handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  handle:SetAllPoints(true)
  handle:SetFrameLevel(frame:GetFrameLevel() + 50)
  handle:Hide()

  local accent = (NS.THEME and NS.THEME.ACCENT) or { r = 1, g = 0.45, b = 0.1 }
  local ar = accent.r or 1
  local ag = accent.g or 0.45
  local ab = accent.b or 0.1
  local moverAlpha = (NS.THEME and NS.THEME.MOVER_ALPHA) or 0.06

  -- Keep unlock visuals lightweight: thin outline with subtle fill.
  handle.tex = handle:CreateTexture(nil, "BACKGROUND")
  handle.tex:SetAllPoints(true)
  handle.tex:SetColorTexture(ar, ag, ab, math.min(0.03, moverAlpha * 0.5))

  handle.borderTop = handle:CreateTexture(nil, "OVERLAY")
  handle.borderTop:SetPoint("TOPLEFT", 0, 0)
  handle.borderTop:SetPoint("TOPRIGHT", 0, 0)
  handle.borderTop:SetHeight(1)
  handle.borderTop:SetColorTexture(ar, ag, ab, 0.95)

  handle.borderBottom = handle:CreateTexture(nil, "OVERLAY")
  handle.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
  handle.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
  handle.borderBottom:SetHeight(1)
  handle.borderBottom:SetColorTexture(ar, ag, ab, 0.95)

  handle.borderLeft = handle:CreateTexture(nil, "OVERLAY")
  handle.borderLeft:SetPoint("TOPLEFT", 0, 0)
  handle.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
  handle.borderLeft:SetWidth(1)
  handle.borderLeft:SetColorTexture(ar, ag, ab, 0.95)

  handle.borderRight = handle:CreateTexture(nil, "OVERLAY")
  handle.borderRight:SetPoint("TOPRIGHT", 0, 0)
  handle.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
  handle.borderRight:SetWidth(1)
  handle.borderRight:SetColorTexture(ar, ag, ab, 0.95)

  handle.label = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  handle.label:SetPoint("CENTER")
  handle.label:SetText(label or "Drag to move")
  handle.label:SetTextColor(ar, ag, ab, 1)
  handle.label:SetShadowColor(0, 0, 0, 1)
  handle.label:SetShadowOffset(1, -1)

  handle:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" then frame:StartMoving() end
  end)
  handle:SetScript("OnMouseUp", function(_, btn)
    if btn == "LeftButton" then
      frame:StopMovingOrSizing()

      local db = NS:GetDB()
      local m = db and db[moduleKey]
      if not m then return end

      local point, _, _, x, y = frame:GetPoint(1)
      m.anchor = point or m.anchor
      m.x = math.floor((x or 0) + 0.5)
      m.y = math.floor((y or 0) + 0.5)

      if db.general.debug then
        NS.Print(("Saved %s position: %s %d %d"):format(moduleKey, m.anchor, m.x, m.y))
      end
    end
  end)

  frame._huiMover = handle
end

function NS:SetFramesLocked(locked)
  local db = NS:GetDB()
  if not db then return end
  db.general.framesLocked = locked

  NS:ForEachModule(function(m)
    if m.SetLocked then m:SetLocked(locked) end
  end)
end

function NS:ResetFramePosition(moduleKey, defaults)
  local db = NS:GetDB()
  if not db or not db[moduleKey] then return end
  db[moduleKey].anchor = defaults.anchor
  db[moduleKey].x = defaults.x
  db[moduleKey].y = defaults.y
  self:ApplyAll()
end

local function HandleSlash(msg)
  msg = (msg or ""):lower()

  if msg == "" or msg == "options" or msg == "config" then
    if NS.OpenOptions then NS:OpenOptions() end
    return
  end

  if msg == "lock" or msg == "move" then
    local db = NS:GetDB()
    db.general.framesLocked = not db.general.framesLocked
    Print("Unlock Frames: " .. (db.general.framesLocked and "Off (Locked)" or "On (Unlocked)"))
    if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    return
  end

  if msg == "xp" then
    local db = NS:GetDB(); db.xpbar.enabled = not db.xpbar.enabled
    Print("XP/Rep Bar: " .. (db.xpbar.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end

  if msg == "cast" then
    local db = NS:GetDB(); db.castbar.enabled = not db.castbar.enabled
    Print("Cast Bar: " .. (db.castbar.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end

  if msg == "loot" then
    local db = NS:GetDB(); db.loot.enabled = not db.loot.enabled
    Print("Loot Toasts: " .. (db.loot.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end

  if msg == "summon" or msg == "summons" then
    local db = NS:GetDB()
    db.summons = db.summons or {}
    db.summons.enabled = not (db.summons.enabled == true)
    Print("Auto Summon Accept: " .. (db.summons.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end

  if msg == "debug" then
    local db = NS:GetDB(); db.general.debug = not db.general.debug
    Print("Debug: " .. (db.general.debug and "On" or "Off"))
    return
  end
  if msg == "version" then
    local info = NS.GetVersionInfo and NS.GetVersionInfo() or nil
    if not info then
      Print("Version info unavailable.")
      return
    end
    local installed = tostring(info.installed or "unknown")
    local latest = tostring(info.latest or "unknown")
    local buildCommit = tostring(info.buildCommit or info.commit or "unknown")
    local latestCommit = tostring(info.latestCommit or "unknown")
    local buildDate = tostring(info.buildDate or "unknown")
    local source = tostring(info.source or "unknown")
    local sourceLabel = tostring(info.sourceLabel or source)
    local peerName = tostring(info.peerName or "n/a")
    local packagedVersion = tostring(info.packagedVersion or "n/a")
    local packagedCommit = tostring(info.packagedCommit or "n/a")
    local status = (info.status or (NS.GetVersionStatus and NS.GetVersionStatus(info)) or "unknown")
    Print(("Version status: %s (installed v%s, latest v%s; buildCommit=%s; latestCommit=%s; build=%s; source=%s; peer=%s; tocVersion=%s; tocCommit=%s; sourceLabel=%s)"):format(
      status,
      installed,
      latest,
      buildCommit,
      latestCommit,
      buildDate,
      source,
      peerName,
      packagedVersion,
      packagedCommit,
      sourceLabel
    ))
    return
  end
  Print("Commands: /hui (options) | lock | xp | cast | loot | summon | debug | version")
end

SLASH_HARATHUI1 = "/harathui"
SLASH_HARATHUI2 = "/hui"
SlashCmdList["HARATHUI"] = HandleSlash

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, ...)
  local arg1 = ...
  if event == "ADDON_LOADED" and arg1 == ADDON then
    NS:InitDB()
  elseif event == "PLAYER_LOGIN" then
    InitializeVersionTracker()
    if NS.InitOptions then NS:InitOptions() end
    NS:ApplyAll()
    EnsureMinimapButton()
    HookSpellIDTooltips()
    SendVersionResponse(true)
    SendVersionQuery(true)
    if C_Timer and C_Timer.After then
      C_Timer.After(2.0, function()
        SendVersionQuery(true)
      end)
    end
    PrintOutOfDateNotice()
    local db = NS:GetDB()
    if db and NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    Print("Loaded. Type /hui for options.")
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    if prefix == VERSION_COMM_PREFIX then
      HandleVersionCommMessage(message, sender)
    end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    if not versionTracker.prefixRegistered then
      InitializeVersionTracker()
    end
    SendVersionQuery(false)
    if event == "GROUP_ROSTER_UPDATE" then
      SendVersionResponse(false)
    end
  end
end)
