local ADDON, NS = ...
local f = CreateFrame("Frame")
NS.frame = f

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

local DEBUG_ENABLED = false
local DB_MIGRATION_VERSION = 1

local function RunDBMigrations(dbRoot)
  if type(dbRoot) ~= "table" then return end

  local profile = dbRoot.profile
  if type(profile) ~= "table" then
    profile = {}
    dbRoot.profile = profile
  end

  local state = profile._huiMigrationState
  if type(state) ~= "table" then
    state = {}
    profile._huiMigrationState = state
  end

  local currentVersion = tonumber(state.version) or 0
  if currentVersion >= DB_MIGRATION_VERSION then
    return
  end

  -- Rule 1: ensure legacy/non-table profile containers are upgraded to tables.
  -- Additive only: existing keys are preserved as-is.
  local general = profile.general
  if type(general) ~= "table" then
    general = {}
    profile.general = general
  end

  -- Rule 2: normalize legacy minimap button shape.
  -- Older profiles may store this as a boolean; modern shape is { hide = <bool> }.
  if type(general.minimapButton) == "boolean" then
    general.minimapButton = { hide = not general.minimapButton }
  elseif type(general.minimapButton) ~= "table" then
    general.minimapButton = {}
  end
  if general.minimapButton.hide == nil then
    general.minimapButton.hide = false
  end

  -- Rule 3: normalize theme color container and channel values.
  -- Preserve existing numeric channels; only fill missing/invalid values.
  if type(general.themeColor) ~= "table" then
    general.themeColor = {}
  end
  if type(general.themeColor.r) ~= "number" then
    general.themeColor.r = NS.DEFAULTS.profile.general.themeColor.r
  end
  if type(general.themeColor.g) ~= "number" then
    general.themeColor.g = NS.DEFAULTS.profile.general.themeColor.g
  end
  if type(general.themeColor.b) ~= "number" then
    general.themeColor.b = NS.DEFAULTS.profile.general.themeColor.b
  end

  -- Rule 4: ensure summons container exists for legacy profiles.
  -- No removals; only additive keys required by runtime toggle paths.
  if type(profile.summons) ~= "table" then
    profile.summons = {}
  end
  if profile.summons.enabled == nil then
    profile.summons.enabled = NS.DEFAULTS.profile.summons.enabled
  end

  state.version = DB_MIGRATION_VERSION
end

function NS:Debug(...)
  local debugEnabled = DEBUG_ENABLED
  if not debugEnabled then
    if not NS.db then return end
    debugEnabled = NS.db.general and NS.db.general.debug
  end
  if not debugEnabled then return end

  local args = {...}
  local msg = ""
  for i = 1, #args do
    msg = msg .. tostring(args[i])
    if i < #args then msg = msg .. " " end
  end
  Print("[Debug] " .. msg)
end

function NS:GetDB()
  if NS.db then
    return NS.db
  end
  local success, result = pcall(function()
    return HarathUI_DB and HarathUI_DB.profile
  end)
  if not success then
    return NS.DEFAULTS.profile
  end
  NS.db = result
  return result
end

function NS:InitDB()
  -- Validate saved data structure
  if HarathUI_DB and type(HarathUI_DB) ~= "table" then
    Print("Saved data corrupted, resetting to defaults")
    HarathUI_DB = nil
  end

  HarathUI_DB = HarathUI_DB or {}

  -- Run additive migrations once per stored migration version.
  local migrateOK, migrateErr = pcall(RunDBMigrations, HarathUI_DB)
  if not migrateOK then
    NS:Debug("Error running settings migrations:", migrateErr)
  end

  -- Safely merge defaults with error handling
  local success, result = pcall(DeepCopyDefaults, HarathUI_DB.profile or {}, NS.DEFAULTS.profile)
  if success then
    HarathUI_DB.profile = result
  else
    Print("Error loading settings, using defaults")
    HarathUI_DB.profile = DeepCopyDefaults({}, NS.DEFAULTS.profile)
  end
  NS.db = HarathUI_DB.profile
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
    NS.EnsureMinimapButton()
    NS.HookSpellIDTooltips()
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
