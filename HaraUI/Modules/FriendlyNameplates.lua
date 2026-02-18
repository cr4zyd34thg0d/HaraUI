local ADDON, NS = ...
local M = {}
NS:RegisterModule("friendlyplates", M)

local eventFrame
local friendlyCVarBackup
local onlyNameCVar
local onlyNameEnemyCVar
local friendlyBuffsCVar = "nameplateShowFriendlyBuffs"
local pendingCVarApply = false
local plates = {}
local cvarCheckTicker
local deferredUpdateTicket = 0
local systemNameplateFontBackup
local systemNameplateFontApplied = false
M.active = false

-- Platynator integration --------------------------------------------------
-- When Platynator is loaded we inject a single "Name Only (No Guild)" design
-- into its saved-variables table BEFORE it initialises.  At runtime we
-- post-modify Platynator's own text FontStrings (font / size / colour /
-- offset) using HaraUI's controls so there are no duplicate overlay frames
-- and no CVar fights.
local hasPlatynator = false
local PLAT_DESIGN_KEY = "Name Only (No Guild)"
local function SyncPlatynatorState()
  if hasPlatynator then return end
  if IsAddOnLoaded and IsAddOnLoaded("Platynator") then
    hasPlatynator = true
  end
end
local modifiedPlates = {} -- plate → { fs = FontString, origFont, origSize, origFlags, origR, origG, origB }

-- The design table matches the old built-in _name-only-no-guild that was
-- removed from Platynator 320.  Tahoma Bold, outline, no guild text.
local function MakeDesignTable()
  return {
    highlights = {
      {
        color  = { a = 1, r = 0.110, g = 0.886, b = 0.929 },
        anchor = { "BOTTOM", 0, -19 },
        kind   = "target",
        height = 1,
        scale  = 0.56,
        layer  = 0,
        asset  = "glow",
        width  = 1,
      },
    },
    specialBars = {},
    scale       = 1,
    auras       = {},
    font        = { outline = true, shadow = true, asset = "Tahoma Bold", slug = true },
    version     = 1,
    bars        = {},
    markers     = {
      { scale = 0.9,  color = { r = 1, g = 1, b = 1 }, anchor = { "BOTTOMLEFT", -82, -7 }, kind = "quest", asset = "normal/quest-boss-blizzard", layer = 3 },
      { scale = 1.45, color = { r = 1, g = 1, b = 1 }, anchor = { "BOTTOM", 0, 25 },       kind = "raid",  asset = "normal/blizzard-raid",        layer = 3 },
    },
    texts = {
      {
        showWhenWowDoes = true,
        truncate        = false,
        color           = { r = 1, g = 1, b = 1 },
        layer           = 2,
        maxWidth        = 1.04,
        autoColors      = {
          { colors = {},                                                                                                                                kind = "classColors" },
          { colors = { tapped    = { r = 0.431, g = 0.431, b = 0.431 } },                                                                             kind = "tapped" },
          { colors = { neutral   = { r = 1, g = 1, b = 0 }, unfriendly = { r = 1, g = 0.506, b = 0 }, friendly = { r = 0, g = 1, b = 0 }, hostile = { r = 1, g = 0, b = 0 } }, kind = "reaction" },
        },
        anchor = { "BOTTOM", 0, 0 },
        kind   = "creatureName",
        align  = "CENTER",
        scale  = 1.27,
      },
    },
  }
end

local function SetWrapperYOffset(wrapper, yOffset)
  if not wrapper or not wrapper.ClearAllPoints or not wrapper.SetPoint then return false end
  if wrapper.IsForbidden and wrapper:IsForbidden() then return false end
  local parent = wrapper.GetParent and wrapper:GetParent() or nil
  if not parent then return false end
  local y = tonumber(yOffset) or 0
  pcall(wrapper.ClearAllPoints, wrapper)
  return pcall(wrapper.SetPoint, wrapper, "BOTTOM", parent, "BOTTOM", 0, y) == true
end

---------------------------------------------------------------------------
-- Early injection: runs BEFORE Platynator's own ADDON_LOADED handler
-- because HaraUI's .lua files execute first (alphabetical load order).
---------------------------------------------------------------------------
local injector = CreateFrame("Frame")
injector:RegisterEvent("ADDON_LOADED")
injector:SetScript("OnEvent", function(_, _, addonName)
  if addonName ~= "Platynator" then return end
  injector:UnregisterAllEvents()

  -- PLATYNATOR_CONFIG exists at this point (saved-vars loaded before event).
  if type(PLATYNATOR_CONFIG) ~= "table" then return end

  local profiles = PLATYNATOR_CONFIG.Profiles
  if type(profiles) ~= "table" then return end

  local profileKey = PLATYNATOR_CURRENT_PROFILE or "DEFAULT"
  local profile = profiles[profileKey]
  if type(profile) ~= "table" then return end

  -- Ensure designs table exists
  if type(profile.designs) ~= "table" then
    profile.designs = {}
  end

  -- Inject / refresh our design
  profile.designs[PLAT_DESIGN_KEY] = MakeDesignTable()

  -- Clean up any stale design from older HaraUI versions
  if profile.designs["haraui_friendly_no_guild"] then
    -- If friend was pointing at the old name, redirect it
    if type(profile.designs_assigned) == "table"
      and profile.designs_assigned["friend"] == "haraui_friendly_no_guild" then
      profile.designs_assigned["friend"] = PLAT_DESIGN_KEY
    end
    profile.designs["haraui_friendly_no_guild"] = nil
  end

  -- Point friend plates at our design (only if it's currently the old
  -- removed default or unset; don't override a deliberate user choice).
  if type(profile.designs_assigned) == "table" then
    local cur = profile.designs_assigned["friend"]
    if cur == nil
      or cur == "_name-only"
      or cur == "_name-only-no-guild"
      or cur == "haraui_friendly_no_guild" then
      profile.designs_assigned["friend"] = PLAT_DESIGN_KEY
    end
  end

  hasPlatynator = true
end)

---------------------------------------------------------------------------
-- Find Platynator's creatureName FontString on a friendly plate
---------------------------------------------------------------------------
local function FindPlatynatorNameFS(plate)
  local children = { plate:GetChildren() }
  for _, child in ipairs(children) do
    if child.kind == "friend" and child.widgets then
      for _, w in ipairs(child.widgets) do
        if w.details and w.details.kind == "creatureName" and w.text then
          return w.text
        end
      end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Post-modify Platynator's text with HaraUI's settings
---------------------------------------------------------------------------
local function ApplyPlatynatorText(plate, unit, db)
  if not plate or not unit or not db then return end
  if not UnitIsPlayer(unit) then return end

  local fs = FindPlatynatorNameFS(plate)
  if not fs then return end

  -- Save originals for restore on Disable
  local info = modifiedPlates[plate]
  if not info then
    local origFont, origSize, origFlags = fs:GetFont()
    local origR, origG, origB = fs:GetTextColor()
    -- Name-only profile uses bottom anchor at y=0; avoid GetPoint on restricted frames.
    local wrapperOrigY = 0
    local widget = fs:GetParent()
    local wrapper = widget and widget.Wrapper
    info = {
      fs = fs,
      wrapper = wrapper,
      origFont = origFont,
      origSize = origSize,
      origFlags = origFlags,
      origR = origR, origG = origG, origB = origB,
      wrapperOrigY = wrapperOrigY,
    }
    modifiedPlates[plate] = info
  end

  -- Font
  local fp = db.friendlyplates
  local fontPath = NS and NS.GetDefaultFontPath and NS:GetDefaultFontPath() or "Fonts\\ARIALN.TTF"
  local fontFlags = NS and NS.GetDefaultFontFlags and NS:GetDefaultFontFlags() or "OUTLINE"
  local fontSize = fp.fontSize or 14
  fs:SetFont(fontPath, fontSize, fontFlags)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)

  -- Colour
  if fp.classColor then
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
      fs:SetTextColor(c.r, c.g, c.b, 1)
    end
    -- If no class colour found, leave Platynator's auto-colour in place
  elseif fp.nameColor then
    local c = fp.nameColor
    fs:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
  end

  -- Vertical offset: Platynator anchors text via a Wrapper frame.  Use the
  -- saved original y-offset so repeated calls don't accumulate drift.
  local yOff = fp.yOffset or 0
  local wrapper = info.wrapper
  if wrapper then
    SetWrapperYOffset(wrapper, (info.wrapperOrigY or 0) + yOff)
  end
end

local function RestorePlatynatorText(plate)
  local info = modifiedPlates[plate]
  if not info then return end
  local fs = info.fs
  if fs and info.origFont then
    pcall(fs.SetFont, fs, info.origFont, info.origSize, info.origFlags)
    fs:SetTextColor(info.origR or 1, info.origG or 1, info.origB or 1, 1)
  end
  -- Restore the Wrapper's original y-offset
  local wrapper = info.wrapper
  if wrapper then
    SetWrapperYOffset(wrapper, info.wrapperOrigY or 0)
  end
  modifiedPlates[plate] = nil
end

local REFRESH_RETRY_DELAYS = { 0, 0.12, 0.30, 0.60 }

local function GetPlateUnitToken(plate)
  if not plate then return nil end
  return plate.namePlateUnitToken or plate.unitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function UpdateAllPlatynator(db)
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    local unit = GetPlateUnitToken(plate)
    if unit and UnitIsPlayer(unit) and not UnitCanAttack("player", unit) then
      ApplyPlatynatorText(plate, unit, db)
    end
  end
end

---------------------------------------------------------------------------
-- Standalone helpers (no Platynator)
---------------------------------------------------------------------------
local NAMEPLATE_FONT_ALPHABETS = {
  "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian",
}

local function EnsureFriendlyDB(db)
  if not db then return nil end
  db.friendlyplates = db.friendlyplates or {}
  local d = db.friendlyplates
  if d.enabled == nil then d.enabled = true end
  if not d.nameColor then d.nameColor = { r = 1, g = 1, b = 1 } end
  if d.classColor == nil then d.classColor = false end
  if not d.fontSize then d.fontSize = 14 end
  if not d.yOffset then d.yOffset = 0 end
  return d
end

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
  if hasPlatynator then return end

  local preserveShowAll
  local showAllCVar = "nameplateShowAll"
  if CVarExists(showAllCVar) then
    local cur = GetCVarSafe(showAllCVar)
    if cur ~= nil then
      if not friendlyCVarBackup then friendlyCVarBackup = {} end
      if friendlyCVarBackup[showAllCVar] == nil then
        friendlyCVarBackup[showAllCVar] = cur
      end
      preserveShowAll = cur
    end
  end

  if not onlyNameCVar then
    if C_CVar and C_CVar.GetCVarInfo and C_CVar.GetCVarInfo("nameplateShowOnlyNameForFriendlyPlayerUnits") ~= nil then
      onlyNameCVar = "nameplateShowOnlyNameForFriendlyPlayerUnits"
    end
  end
  if not onlyNameEnemyCVar then
    if CVarExists("nameplateShowOnlyNameForEnemyPlayerUnits") then
      onlyNameEnemyCVar = "nameplateShowOnlyNameForEnemyPlayerUnits"
    end
  end

  if InCombatLockdown and InCombatLockdown() then
    pendingCVarApply = true
    return
  end

  if CVarExists("nameplateShowEnemies") then
    SetCVarSafe("nameplateShowEnemies", "1")
  end

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

  if preserveShowAll ~= nil and CVarExists(showAllCVar) then
    local cur = GetCVarSafe(showAllCVar)
    local want = tostring(preserveShowAll)
    if cur ~= nil and tostring(cur) ~= want then
      SetCVarSafe(showAllCVar, want)
    end
  end

  if C_NamePlate and C_NamePlate.SetNamePlateFriendlySize then
    local size = C_NamePlate.GetNamePlateFriendlySize()
    C_NamePlate.SetNamePlateFriendlySize(size, size)
  end
  if C_NamePlate and C_NamePlate.SetNamePlateEnemySize then
    local esize = C_NamePlate.GetNamePlateEnemySize()
    C_NamePlate.SetNamePlateEnemySize(esize, esize)
  end
end

local function IsCVarValue(name, expected)
  local cur = GetCVarSafe(name)
  if cur == nil then return false end
  return tostring(cur) == tostring(expected)
end

local function NeedsFriendlyCVarReapply()
  if hasPlatynator then return false end
  if pendingCVarApply then return true end
  if CVarExists("nameplateShowEnemies") and not IsCVarValue("nameplateShowEnemies", "1") then return true end
  if onlyNameCVar and CVarExists(onlyNameCVar) and not IsCVarValue(onlyNameCVar, "1") then return true end
  if onlyNameEnemyCVar and CVarExists(onlyNameEnemyCVar) and not IsCVarValue(onlyNameEnemyCVar, "1") then return true end
  if CVarExists(friendlyBuffsCVar) and not IsCVarValue(friendlyBuffsCVar, "0") then return true end
  return false
end

local function RestoreFriendlyCVars()
  if hasPlatynator then return end
  if not friendlyCVarBackup then return end
  for name, value in pairs(friendlyCVarBackup) do
    if value ~= nil then SetCVarSafe(name, value) end
  end
end

local function StartCVarMonitor()
  if hasPlatynator then return end
  if cvarCheckTicker then return end
  cvarCheckTicker = C_Timer.NewTicker(5, function()
    if not M.active then
      if cvarCheckTicker then cvarCheckTicker:Cancel(); cvarCheckTicker = nil end
      return
    end
    if NeedsFriendlyCVarReapply() then ApplyFriendlyCVars() end
  end)
end

local function StopCVarMonitor()
  if cvarCheckTicker then cvarCheckTicker:Cancel(); cvarCheckTicker = nil end
end

local function IsDungeonOrRaidInstance()
  if not IsInInstance or not GetInstanceInfo then return false end
  local inInstance, instanceType = IsInInstance()
  if not inInstance then return false end
  return instanceType == "party" or instanceType == "raid"
end

local function CaptureNameplateFontFamilyState(fontFamily)
  if not fontFamily or not fontFamily.GetFontObjectForAlphabet then return nil end
  local saved = { alphabets = {} }
  if fontFamily.GetShadowColor then
    local r, g, b, a = fontFamily:GetShadowColor()
    saved.shadowColor = { r, g, b, a }
  end
  if fontFamily.GetShadowOffset then
    local x, y = fontFamily:GetShadowOffset()
    saved.shadowOffset = { x, y }
  end
  for _, alphabet in ipairs(NAMEPLATE_FONT_ALPHABETS) do
    local obj = fontFamily:GetFontObjectForAlphabet(alphabet)
    if obj and obj.GetFont then
      local path, size, flags = obj:GetFont()
      saved.alphabets[alphabet] = { path = path, size = size, flags = flags }
    end
  end
  return saved
end

local function ApplyNameplateFontFamily(fontFamily, path, flags)
  if not fontFamily or not path or not fontFamily.GetFontObjectForAlphabet then return end
  for _, alphabet in ipairs(NAMEPLATE_FONT_ALPHABETS) do
    local obj = fontFamily:GetFontObjectForAlphabet(alphabet)
    if obj and obj.SetFont and obj.GetFont then
      local _, size = obj:GetFont()
      obj:SetFont(path, size or 9, flags or "OUTLINE")
    end
  end
  if fontFamily.SetShadowOffset then fontFamily:SetShadowOffset(1, -1) end
  if fontFamily.SetShadowColor then fontFamily:SetShadowColor(0, 0, 0, 1) end
end

local function RestoreNameplateFontFamily(fontFamily, saved)
  if not fontFamily or not saved or not saved.alphabets or not fontFamily.GetFontObjectForAlphabet then return end
  for alphabet, fontData in pairs(saved.alphabets) do
    local obj = fontFamily:GetFontObjectForAlphabet(alphabet)
    if obj and obj.SetFont and fontData and fontData.path then
      obj:SetFont(fontData.path, fontData.size or 9, fontData.flags)
    end
  end
  if saved.shadowOffset and fontFamily.SetShadowOffset then
    fontFamily:SetShadowOffset(saved.shadowOffset[1] or 0, saved.shadowOffset[2] or 0)
  end
  if saved.shadowColor and fontFamily.SetShadowColor then
    fontFamily:SetShadowColor(saved.shadowColor[1] or 0, saved.shadowColor[2] or 0, saved.shadowColor[3] or 0, saved.shadowColor[4] or 1)
  end
end

local function UpdateDungeonSystemNameplateFont(db)
  if hasPlatynator then return end
  if not db then return end
  if not SystemFont_NamePlate or not SystemFont_NamePlate_Outlined then return end
  if not SystemFont_NamePlate.GetFontObjectForAlphabet or not SystemFont_NamePlate_Outlined.GetFontObjectForAlphabet then return end

  local shouldApply = M.active and IsDungeonOrRaidInstance()
  if shouldApply then
    if not systemNameplateFontBackup then
      systemNameplateFontBackup = {
        normal = CaptureNameplateFontFamilyState(SystemFont_NamePlate),
        outlined = CaptureNameplateFontFamilyState(SystemFont_NamePlate_Outlined),
      }
    end
    local fontPath = NS and NS.GetDefaultFontPath and NS:GetDefaultFontPath() or STANDARD_TEXT_FONT
    local fontFlags = NS and NS.GetDefaultFontFlags and NS:GetDefaultFontFlags() or "OUTLINE"
    ApplyNameplateFontFamily(SystemFont_NamePlate, fontPath, fontFlags)
    ApplyNameplateFontFamily(SystemFont_NamePlate_Outlined, fontPath, fontFlags)
    systemNameplateFontApplied = true
  elseif systemNameplateFontApplied and systemNameplateFontBackup then
    RestoreNameplateFontFamily(SystemFont_NamePlate, systemNameplateFontBackup.normal)
    RestoreNameplateFontFamily(SystemFont_NamePlate_Outlined, systemNameplateFontBackup.outlined)
    systemNameplateFontApplied = false
    systemNameplateFontBackup = nil
  end
end

---------------------------------------------------------------------------
-- Standalone overlay helpers (only used when Platynator is NOT loaded)
---------------------------------------------------------------------------
local function IsPlayerUnit(unit)
  return unit and UnitIsPlayer(unit)
end

local function GetClassColor(unit)
  local _, class = UnitClass(unit)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return nil
end

local function ApplyFont(fs, db)
  if not fs or not db then return end
  local size = db.friendlyplates.fontSize or 14
  local fontPath = NS and NS.GetDefaultFontPath and NS:GetDefaultFontPath()
  local fontFlags = NS and NS.GetDefaultFontFlags and NS:GetDefaultFontFlags() or "OUTLINE"
  if fs.SetFont then fs:SetFont(fontPath or STANDARD_TEXT_FONT, size, fontFlags) end
  if fs.SetSnapToPixelGrid then fs:SetSnapToPixelGrid(false) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
end

local function ApplyColor(fs, unit, db)
  if not fs or not unit or not db then return end
  if db.friendlyplates.classColor then
    local r, g, b = GetClassColor(unit)
    if r then fs:SetTextColor(r, g, b, 1); return end
  end
  local c = db.friendlyplates.nameColor or { r = 1, g = 1, b = 1 }
  fs:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
end

local function ApplyNameText(f, unit, db)
  if not f or not f.name then return end
  f.name:SetText(UnitName(unit) or "")
  ApplyFont(f.name, db)
  ApplyColor(f.name, unit, db)
  if f.nameBold then f.nameBold:SetText(""); f.nameBold:Hide() end
end

local function ApplyOffset(f, db)
  if not f or not f.name or not db then return end
  local y = db.friendlyplates.yOffset or 0
  f.name:ClearAllPoints()
  f.name:SetPoint("CENTER", f, "CENTER", 0, y)
  if f.nameBold then
    f.nameBold:ClearAllPoints()
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
  f.name = f:CreateFontString(nil, "OVERLAY")
  f.name:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.name:SetJustifyH("CENTER")
  f.name:SetJustifyV("MIDDLE")
  f.name:SetDrawLayer("OVERLAY", 7)
  f.name:SetShadowOffset(1, -1)
  f.name:SetShadowColor(0, 0, 0, 1)
  if f.name.SetSnapToPixelGrid then f.name:SetSnapToPixelGrid(false) end
  if f.name.SetNonSpaceWrap then f.name:SetNonSpaceWrap(false) end
  f.nameBold = f:CreateFontString(nil, "OVERLAY")
  f.nameBold:SetPoint("CENTER", f.name, "CENTER", 1, 0)
  f.nameBold:SetJustifyH("CENTER")
  f.nameBold:SetJustifyV("MIDDLE")
  f.nameBold:SetDrawLayer("OVERLAY", 6)
  f.nameBold:SetShadowOffset(1, -1)
  f.nameBold:SetShadowColor(0, 0, 0, 0.5)
  f.nameBold:Hide()
  if f.nameBold.SetSnapToPixelGrid then f.nameBold:SetSnapToPixelGrid(false) end
  if f.nameBold.SetNonSpaceWrap then f.nameBold:SetNonSpaceWrap(false) end
  NS:ApplyDefaultFont(f.name, 14)
  NS:ApplyDefaultFont(f.nameBold, 14)
  return f
end

local function HideBlizzardName(plate)
  if not plate or not plate.UnitFrame then return end
  local name = plate.UnitFrame.name
  if not name then return end
  if name.IsForbidden and name:IsForbidden() then return end
  if plate._huiNameAlpha == nil then plate._huiNameAlpha = name:GetAlpha() end
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

local function UpdatePlateStandalone(plate, unit, db)
  if not plate or not unit or not db then return end
  if not UnitIsPlayer(unit) then
    RestoreBlizzardName(plate)
    if plates[plate] then plates[plate]:Hide() end
    return
  end
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

local function RemovePlateStandalone(plate)
  RestoreBlizzardName(plate)
  local f = plates[plate]
  if f then f:Hide(); plates[plate] = nil end
end

local function UpdateAllStandalone(db, force)
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    local unit = GetPlateUnitToken(plate)
    if unit and (force or IsPlayerUnit(unit)) then
      UpdatePlateStandalone(plate, unit, db)
    end
  end
end

local function UpdateAllActivePath(db)
  if hasPlatynator then
    UpdateAllPlatynator(db)
  else
    UpdateAllStandalone(db)
  end
end

local function UpdateAllDeferred(db)
  if not db then return end
  SyncPlatynatorState()
  deferredUpdateTicket = deferredUpdateTicket + 1
  local ticket = deferredUpdateTicket
  UpdateAllActivePath(db)
  if not (C_Timer and C_Timer.After) then return end
  for i = 2, #REFRESH_RETRY_DELAYS do
    local delay = REFRESH_RETRY_DELAYS[i]
    C_Timer.After(delay, function()
      if not M.active then return end
      if ticket ~= deferredUpdateTicket then return end
      local liveDB = NS:GetDB()
      local fp = EnsureFriendlyDB(liveDB)
      if not (liveDB and fp and fp.enabled) then return end
      SyncPlatynatorState()
      UpdateAllActivePath(liveDB)
    end)
  end
end

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------
local function IsWatchedCVar(name)
  if not name then return false end
  return name == "nameplateShowOnlyNames"
    or name == "nameplateShowEnemies"
    or name == "nameplateShowAll"
    or name == "nameplateShowOnlyNameForFriendlyPlayerUnits"
    or name == "nameplateShowOnlyNameForEnemyPlayerUnits"
    or name == friendlyBuffsCVar
    or (onlyNameCVar and name == onlyNameCVar)
    or (onlyNameEnemyCVar and name == onlyNameEnemyCVar)
end

local function HandlePlayerEnteringWorld(db)
  ApplyFriendlyCVars()
  UpdateDungeonSystemNameplateFont(db)
  UpdateAllDeferred(db)
  C_Timer.After(0.5, function()
    if M.active then ApplyFriendlyCVars(); UpdateAllDeferred(db) end
  end)
  C_Timer.After(1.5, function()
    if M.active then ApplyFriendlyCVars() end
  end)
end

local function HandleZoneChangedOrBattleground(db)
  ApplyFriendlyCVars()
  UpdateDungeonSystemNameplateFont(db)
  UpdateAllDeferred(db)
  C_Timer.After(0.5, function()
    if M.active then ApplyFriendlyCVars(); UpdateAllDeferred(db) end
  end)
end

local function HandlePlayerRegenEnabled(db)
  if pendingCVarApply then
    pendingCVarApply = false
    ApplyFriendlyCVars()
    UpdateAllDeferred(db)
  end
  UpdateDungeonSystemNameplateFont(db)
end

local function HandleCVarUpdate(arg1, db)
  if hasPlatynator then return end
  if not IsWatchedCVar(arg1) then return end
  ApplyFriendlyCVars()
  UpdateDungeonSystemNameplateFont(db)
  UpdateAllDeferred(db)
end

local function HandleNamePlateUnitAdded(unit, db)
  if hasPlatynator then
    -- Defer so Platynator finishes its Install first
    C_Timer.After(0, function()
      if not M.active then return end
      local plate = C_NamePlate.GetNamePlateForUnit(unit)
      if plate and UnitIsPlayer(unit) and not UnitCanAttack("player", unit) then
        ApplyPlatynatorText(plate, unit, db)
      end
    end)
  else
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then UpdatePlateStandalone(plate, unit, db) end
  end
end

local function HandleNamePlateUnitRemoved(unit)
  if hasPlatynator then
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then
      modifiedPlates[plate] = nil
    end
  else
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then RemovePlateStandalone(plate) end
  end
end

local function HandleUnitNameUpdate(unit, db)
  if not (unit and unit:match("^nameplate")) then return end
  if hasPlatynator then
    C_Timer.After(0, function()
      if not M.active then return end
      local plate = C_NamePlate.GetNamePlateForUnit(unit)
      if plate and UnitIsPlayer(unit) and not UnitCanAttack("player", unit) then
        ApplyPlatynatorText(plate, unit, db)
      end
    end)
  else
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then UpdatePlateStandalone(plate, unit, db) end
  end
end

local function HandleEvent(event, arg1)
  if not M.active then return end
  local db = NS:GetDB()
  local fp = EnsureFriendlyDB(db)
  if not db or not fp or not fp.enabled then return end

  if event == "PLAYER_ENTERING_WORLD" then
    HandlePlayerEnteringWorld(db)
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_BATTLEGROUND" then
    HandleZoneChangedOrBattleground(db)
  elseif event == "PLAYER_REGEN_ENABLED" then
    HandlePlayerRegenEnabled(db)
  elseif event == "CVAR_UPDATE" then
    HandleCVarUpdate(arg1, db)
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    HandleNamePlateUnitAdded(arg1, db)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    HandleNamePlateUnitRemoved(arg1)
  elseif event == "UNIT_NAME_UPDATE" then
    HandleUnitNameUpdate(arg1, db)
  end
end

---------------------------------------------------------------------------
-- Public module API
---------------------------------------------------------------------------
function M:Refresh()
  SyncPlatynatorState()
  local db = NS:GetDB()
  local fp = EnsureFriendlyDB(db)
  if not db or not fp or not fp.enabled then return end
  if not hasPlatynator then
    UpdateDungeonSystemNameplateFont(db)
    for plate, f in pairs(plates) do
      local unit = f and f._huiUnit
      if unit then UpdatePlateStandalone(plate, unit, db) end
    end
  end
  UpdateAllDeferred(db)
end

function M:Apply()
  SyncPlatynatorState()
  local db = NS:GetDB()
  local fp = EnsureFriendlyDB(db)
  if not db or not fp or not fp.enabled then
    self:Disable()
    return
  end
  M.active = true

  ApplyFriendlyCVars()
  UpdateDungeonSystemNameplateFont(db)

  if not eventFrame then
    eventFrame = CreateFrame("Frame")
  else
    eventFrame:UnregisterAllEvents()
  end
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  eventFrame:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND")
  eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
  if not hasPlatynator then
    eventFrame:RegisterEvent("CVAR_UPDATE")
  end
  eventFrame:SetScript("OnEvent", function(_, event, arg1)
    HandleEvent(event, arg1)
  end)

  UpdateAllDeferred(db)
  StartCVarMonitor()
end

function M:Disable()
  SyncPlatynatorState()
  M.active = false
  StopCVarMonitor()
  UpdateDungeonSystemNameplateFont(NS:GetDB())
  RestoreFriendlyCVars()
  pendingCVarApply = false
  friendlyCVarBackup = nil

  if hasPlatynator then
    -- Restore Platynator's original text on all modified plates
    for plate in pairs(modifiedPlates) do
      RestorePlatynatorText(plate)
    end
    if wipe then
      wipe(modifiedPlates)
    else
      for plate in pairs(modifiedPlates) do
        modifiedPlates[plate] = nil
      end
    end
  else
    if C_NamePlate and C_NamePlate.GetNamePlates then
      for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        RestoreBlizzardName(plate)
      end
    end
    for plate, f in pairs(plates) do
      if f then f:Hide() end
      plates[plate] = nil
    end
  end

  if eventFrame then
    eventFrame:SetScript("OnEvent", nil)
    eventFrame:UnregisterAllEvents()
  end
end
