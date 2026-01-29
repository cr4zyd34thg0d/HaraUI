local ADDON, NS = ...
local M = {}
NS:RegisterModule("friendlyplates", M)

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local eventFrame
local friendlyCVarBackup
local onlyNameCVar
local onlyNameEnemyCVar
local friendlyBuffsCVar = "nameplateShowFriendlyBuffs"
local pendingCVarApply = false
local plates = {}
local lastCVarCheck = 0
local cvarCheckTicker
M.active = false

local function GetCVarSafe(name)
  if GetCVar then return GetCVar(name) end
  return nil
end

local function CVarExists(name)
  if C_CVar and C_CVar.GetCVarInfo then
    return C_CVar.GetCVarInfo(name) ~= nil
  end
  local v = GetCVarSafe(name)
  return v ~= nil and v ~= ""
end

local function SetCVarSafe(name, value)
  if C_CVar and C_CVar.SetCVar then
    C_CVar.SetCVar(name, value)
  elseif SetCVar then
    SetCVar(name, value)
  end
end

local function ApplyFriendlyCVars()
  -- Detect friendly nameplate CVar
  if not onlyNameCVar then
    if C_CVar and C_CVar.GetCVarInfo and C_CVar.GetCVarInfo("nameplateShowOnlyNameForFriendlyPlayerUnits") ~= nil then
      onlyNameCVar = "nameplateShowOnlyNameForFriendlyPlayerUnits"
    elseif C_CVar and C_CVar.GetCVarInfo and C_CVar.GetCVarInfo("nameplateShowOnlyNames") ~= nil then
      onlyNameCVar = "nameplateShowOnlyNames"
    elseif CVarExists("nameplateShowOnlyNames") then
      onlyNameCVar = "nameplateShowOnlyNames"
    end
  end

  -- Detect enemy nameplate CVar
  if not onlyNameEnemyCVar then
    if CVarExists("nameplateShowOnlyNameForEnemyPlayerUnits") then
      onlyNameEnemyCVar = "nameplateShowOnlyNameForEnemyPlayerUnits"
    end
  end

  if InCombatLockdown and InCombatLockdown() then
    pendingCVarApply = true
    return
  end

  -- Ensure enemy nameplates are enabled (don't back up - this is essential)
  if CVarExists("nameplateShowEnemies") then
    SetCVarSafe("nameplateShowEnemies", "1")
  end

  -- Apply friendly nameplate CVar
  if onlyNameCVar then
    local cur = GetCVarSafe(onlyNameCVar)
    if cur ~= nil then
      if not friendlyCVarBackup then friendlyCVarBackup = {} end
      if friendlyCVarBackup[onlyNameCVar] == nil then
        friendlyCVarBackup[onlyNameCVar] = cur
      end
      SetCVarSafe(onlyNameCVar, "1")
    end
  end

  -- Apply enemy nameplate CVar
  if onlyNameEnemyCVar then
    local cur = GetCVarSafe(onlyNameEnemyCVar)
    if cur ~= nil then
      if not friendlyCVarBackup then friendlyCVarBackup = {} end
      if friendlyCVarBackup[onlyNameEnemyCVar] == nil then
        friendlyCVarBackup[onlyNameEnemyCVar] = cur
      end
      SetCVarSafe(onlyNameEnemyCVar, "1")
    end
  end

  -- Hide friendly buffs (only for player nameplates we're styling)
  if CVarExists(friendlyBuffsCVar) then
    local cur = GetCVarSafe(friendlyBuffsCVar)
    if cur ~= nil then
      if not friendlyCVarBackup then friendlyCVarBackup = {} end
      if friendlyCVarBackup[friendlyBuffsCVar] == nil then
        friendlyCVarBackup[friendlyBuffsCVar] = cur
      end
      SetCVarSafe(friendlyBuffsCVar, "0")
    end
  end

  -- NOTE: We do NOT modify enemy buff settings to avoid interfering with other enemy nameplate addons

  lastCVarCheck = GetTime()

  -- Force nameplate refresh after CVar changes
  if C_NamePlate and C_NamePlate.SetNamePlateFriendlySize then
    local size = C_NamePlate.GetNamePlateFriendlySize()
    C_NamePlate.SetNamePlateFriendlySize(size, size)
  end
  if C_NamePlate and C_NamePlate.SetNamePlateEnemySize then
    local esize = C_NamePlate.GetNamePlateEnemySize()
    C_NamePlate.SetNamePlateEnemySize(esize, esize)
  end
end

local function RestoreFriendlyCVars()
  if not friendlyCVarBackup then return end
  for name, value in pairs(friendlyCVarBackup) do
    if value ~= nil then
      SetCVarSafe(name, value)
    end
  end
end

local function StartCVarMonitor()
  if cvarCheckTicker then return end
  -- Check CVars every 3 seconds to ensure they persist (especially in instances)
  cvarCheckTicker = C_Timer.NewTicker(3, function()
    if not M.active then
      if cvarCheckTicker then
        cvarCheckTicker:Cancel()
        cvarCheckTicker = nil
      end
      return
    end
    -- Only reapply if enough time has passed since last check
    local now = GetTime()
    if now - lastCVarCheck >= 2.5 then
      ApplyFriendlyCVars()
    end
  end)
end

local function StopCVarMonitor()
  if cvarCheckTicker then
    cvarCheckTicker:Cancel()
    cvarCheckTicker = nil
  end
end

local function IsPlayerUnit(unit)
  -- Check if it's any player (friendly or enemy), not an NPC
  return unit and UnitIsPlayer(unit)
end

local function GetClassColor(unit)
  local _, class = UnitClass(unit)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then
    return c.r, c.g, c.b
  end
  return nil
end

local function FetchFontPath(name)
  if not LSM or not name then return nil end
  local path = LSM:Fetch("font", name, true)
  if path then return path end
  local lower = string.lower(name)
  for _, n in ipairs(LSM:List("font")) do
    if string.lower(n) == lower then
      return LSM:Fetch("font", n, true)
    end
  end
  return nil
end

local function ApplyFont(fs, db)
  if not fs or not db then return end
  local size = db.friendlyplates.fontSize or 12
  local outline = db.friendlyplates.fontOutline
  if outline == "NONE" then outline = nil end

  local path = FetchFontPath(db.friendlyplates.font)
  if path then
    fs:SetFont(path, size, outline)
  elseif STANDARD_TEXT_FONT then
    fs:SetFont(STANDARD_TEXT_FONT, size, outline)
  end

  -- Ensure pixel-perfect rendering after font change
  if fs.SetSnapToPixelGrid then
    fs:SetSnapToPixelGrid(false)
  end
  if fs.SetNonSpaceWrap then
    fs:SetNonSpaceWrap(false)
  end
end

local function ApplyColor(fs, unit, db)
  if not fs or not unit or not db then return end
  if db.friendlyplates.classColor then
    local r, g, b = GetClassColor(unit)
    if r then
      fs:SetTextColor(r, g, b, 1)
      return
    end
  end
  local c = db.friendlyplates.nameColor or { r = 1, g = 1, b = 1 }
  fs:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
end

local function ApplyNameText(f, unit, db)
  if not f or not f.name then return end
  local name = UnitName(unit) or ""
  f.name:SetText(name)
  ApplyFont(f.name, db)
  ApplyColor(f.name, unit, db)

  if f.nameBold then
    f.nameBold:SetText("")
    f.nameBold:Hide()
  end
end

local function ApplyOffset(f, db)
  if not f or not f.name or not db then return end
  local y = db.friendlyplates.yOffset or 0
  f.name:ClearAllPoints()
  f.name:SetPoint("CENTER", f, "CENTER", 0, y)
  if f.nameBold then
    f.nameBold:ClearAllPoints()
    -- Bold text anchored to main text with exactly 1px horizontal offset
    f.nameBold:SetPoint("CENTER", f.name, "CENTER", 1, 0)
  end
end

local function CreatePlateOverlay(plate)
  local f = CreateFrame("Frame", nil, plate)
  f:SetAllPoints(true)
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel(plate:GetFrameLevel() + 20)
  f:SetIgnoreParentAlpha(true)
  f:SetAlpha(1)

  -- Main name text (pixel perfect)
  f.name = f:CreateFontString(nil, "OVERLAY")
  f.name:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.name:SetJustifyH("CENTER")
  f.name:SetJustifyV("MIDDLE")
  f.name:SetDrawLayer("OVERLAY", 7)
  f.name:SetShadowOffset(1, -1)
  f.name:SetShadowColor(0, 0, 0, 1)

  -- Pixel-perfect text rendering
  if f.name.SetSnapToPixelGrid then
    f.name:SetSnapToPixelGrid(false)
  end
  if f.name.SetNonSpaceWrap then
    f.name:SetNonSpaceWrap(false)
  end

  -- Bold overlay (exactly 1px offset for crisp effect)
  f.nameBold = f:CreateFontString(nil, "OVERLAY")
  f.nameBold:SetPoint("CENTER", f.name, "CENTER", 1, 0)
  f.nameBold:SetJustifyH("CENTER")
  f.nameBold:SetJustifyV("MIDDLE")
  f.nameBold:SetDrawLayer("OVERLAY", 6)
  f.nameBold:SetShadowOffset(1, -1)
  f.nameBold:SetShadowColor(0, 0, 0, 0.5)
  f.nameBold:Hide()

  if f.nameBold.SetSnapToPixelGrid then
    f.nameBold:SetSnapToPixelGrid(false)
  end
  if f.nameBold.SetNonSpaceWrap then
    f.nameBold:SetNonSpaceWrap(false)
  end

  -- Set initial font
  if GameFontNormalSmall and GameFontNormalSmall.GetFont then
    local font, _, flags = GameFontNormalSmall:GetFont()
    if font then
      f.name:SetFont(font, 12, flags)
      f.nameBold:SetFont(font, 12, flags)
    end
  elseif STANDARD_TEXT_FONT then
    f.name:SetFont(STANDARD_TEXT_FONT, 12, "")
    f.nameBold:SetFont(STANDARD_TEXT_FONT, 12, "")
  end

  return f
end


local function HideBlizzardName(plate)
  if not plate or not plate.UnitFrame then return end
  local name = plate.UnitFrame.name
  if not name then return end
  if name.IsForbidden and name:IsForbidden() then return end
  if plate._huiNameAlpha == nil then
    plate._huiNameAlpha = name:GetAlpha()
  end
  name:SetAlpha(0)
end

local function RestoreBlizzardName(plate)
  if not plate or not plate.UnitFrame then return end
  local name = plate.UnitFrame.name
  if not name then return end
  if name.IsForbidden and name:IsForbidden() then return end
  if plate._huiNameAlpha ~= nil then
    name:SetAlpha(plate._huiNameAlpha)
    plate._huiNameAlpha = nil
  else
    name:SetAlpha(1)
  end
end

local function UpdatePlate(plate, unit, db)
  if not plate or not unit or not db then return end

  -- ONLY apply to player units (friendly or enemy), NEVER to NPCs
  local isPlayer = UnitIsPlayer(unit)

  if not isPlayer then
    -- This is an NPC (friendly or enemy) - don't touch it at all
    RestoreBlizzardName(plate)
    if plates[plate] then
      plates[plate]:Hide()
    end
    return
  end

  -- At this point, unit is definitely a player (not NPC)
  HideBlizzardName(plate)
  local f = plates[plate]
  if not f then
    f = CreatePlateOverlay(plate)
    plates[plate] = f
  end

  f._huiUnit = unit
  f._huiIsEnemy = UnitIsEnemy("player", unit)
  ApplyNameText(f, unit, db)
  ApplyOffset(f, db)
  f:Show()
end

local function RemovePlate(plate)
  local f = plates[plate]
  if f then
    f:Hide()
    plates[plate] = nil
  end
end

local function UpdateAll(db, force)
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    local unit = plate.namePlateUnitToken
    if unit then
      -- Force update to catch enemy players that might have been skipped
      if force or IsPlayerUnit(unit) then
        UpdatePlate(plate, unit, db)
      end
    end
  end
end

local function UpdateAllDeferred(db)
  if not db then return end
  UpdateAll(db)
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() UpdateAll(db) end)
    C_Timer.After(0.1, function() UpdateAll(db) end)
    C_Timer.After(0.3, function() UpdateAll(db) end)
  end
end

function M:Refresh()
  local db = NS:GetDB()
  if not db or not db.friendlyplates.enabled then return end
  for plate, f in pairs(plates) do
    local unit = f and f._huiUnit
    if unit then
      UpdatePlate(plate, unit, db)
    end
  end
  UpdateAllDeferred(db)
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.friendlyplates.enabled then
    self:Disable()
    return
  end
  M.active = true

  if not db.friendlyplates.font then
    db.friendlyplates.font = "BigNoodleTilting"
  end
  ApplyFriendlyCVars()

  if not eventFrame then
    eventFrame = CreateFrame("Frame")
  else
    eventFrame:UnregisterAllEvents()
  end
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  eventFrame:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND")
  eventFrame:RegisterEvent("CVAR_UPDATE")
  eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
  eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if not M.active then return end
    local db = NS:GetDB()
    if not db or not db.friendlyplates.enabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
      ApplyFriendlyCVars()
      UpdateAllDeferred(db)
      -- Reapply CVars after a short delay to override Blizzard's instance settings
      C_Timer.After(0.5, function()
        if M.active then
          ApplyFriendlyCVars()
        end
      end)
      C_Timer.After(1.5, function()
        if M.active then
          ApplyFriendlyCVars()
        end
      end)
      return
    end
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_BATTLEGROUND" then
      -- Reapply CVars when entering instances (dungeons, raids, battlegrounds)
      -- Blizzard may reset CVars to instance-specific defaults
      ApplyFriendlyCVars()
      UpdateAllDeferred(db)
      C_Timer.After(0.5, function()
        if M.active then
          ApplyFriendlyCVars()
          UpdateAllDeferred(db)
        end
      end)
      return
    end
    if event == "PLAYER_REGEN_ENABLED" then
      if pendingCVarApply then
        pendingCVarApply = false
        ApplyFriendlyCVars()
        UpdateAllDeferred(db)
      end
      return
    end
    if event == "CVAR_UPDATE" and arg1 == "nameplateShowOnlyNames" then
      ApplyFriendlyCVars()
      UpdateAllDeferred(db)
      return
    end
    if event == "CVAR_UPDATE" and arg1 == "nameplateShowOnlyNameForFriendlyPlayerUnits" then
      ApplyFriendlyCVars()
      UpdateAllDeferred(db)
      return
    end
    if event == "CVAR_UPDATE" and arg1 == "nameplateShowOnlyNameForEnemyPlayerUnits" then
      ApplyFriendlyCVars()
      UpdateAllDeferred(db)
      return
    end
    if event == "CVAR_UPDATE" and arg1 == friendlyBuffsCVar then
      ApplyFriendlyCVars()
      UpdateAllDeferred(db)
      return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      if plate then
        UpdatePlate(plate, arg1, db)
      end
      return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      if plate then
        RemovePlate(plate)
      end
      return
    end
    if event == "UNIT_NAME_UPDATE" and arg1 and arg1:match("^nameplate") then
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      if plate then
        UpdatePlate(plate, arg1, db)
      end
    end
  end)

  UpdateAllDeferred(db)
  StartCVarMonitor()
end

function M:Disable()
  M.active = false
  StopCVarMonitor()
  RestoreFriendlyCVars()
  pendingCVarApply = false
  friendlyCVarBackup = nil
  if C_NamePlate and C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
      RestoreBlizzardName(plate)
    end
  end
  for plate, f in pairs(plates) do
    if f then f:Hide() end
    plates[plate] = nil
  end
  if eventFrame then
    eventFrame:SetScript("OnEvent", nil)
    eventFrame:UnregisterAllEvents()
  end
end
