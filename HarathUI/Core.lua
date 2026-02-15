local ADDON, NS = ...
local f = CreateFrame("Frame")
NS.frame = f
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local spellIDTooltipHooked = false
local spellIDTooltipDataHooked = false

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
  NS:ApplyDefaultFont(handle.label, 11)
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
    local source = tostring(info.source or "unknown")
    local peerName = tostring(info.peerName or "n/a")
    local status = (info.status or (NS.GetVersionStatus and NS.GetVersionStatus(info)) or "unknown")
    Print(("Version status: %s (installed v%s, latest v%s; source=%s; peer=%s)"):format(
      status,
      installed,
      latest,
      source,
      peerName
    ))
    return
  end
  Print("Commands: /hui (options) | lock | xp | cast | loot | summon | debug | version")
end

NS._huiHandleSlash = HandleSlash

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
    NS.InitializeVersionTracker()
    if NS.InitOptions then NS:InitOptions() end
    NS:ApplyAll()
    EnsureMinimapButton()
    HookSpellIDTooltips()
    NS.SendVersionResponse(true)
    NS.SendVersionQuery(true)
    if C_Timer and C_Timer.After then
      C_Timer.After(2.0, function()
        NS.SendVersionQuery(true)
      end)
    end
    NS.PrintOutOfDateNotice()
    local db = NS:GetDB()
    if db and NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    Print("Loaded. Type /hui for options.")
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    if prefix == NS.VERSION_COMM_PREFIX then
      NS.HandleVersionCommMessage(message, sender)
    end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    if not NS.IsVersionTrackerInitialized() then
      NS.InitializeVersionTracker()
    end
    NS.SendVersionQuery(false)
    if event == "GROUP_ROSTER_UPDATE" then
      NS.SendVersionResponse(false)
    end
  end
end)
