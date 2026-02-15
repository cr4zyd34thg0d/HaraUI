--[[
  Cast Bar Module

  Interface:
    M:Apply()        - Initialize/update with current settings
    M:Disable()      - Clean up and restore Blizzard cast bar
    M:SetLocked()    - Toggle drag mode
    M:Preview()      - Toggle preview state

  Events Registered:
    - UNIT_SPELLCAST_START
    - UNIT_SPELLCAST_STOP
    - UNIT_SPELLCAST_CHANNEL_START
    - UNIT_SPELLCAST_CHANNEL_STOP
--]]

local ADDON, NS = ...
local M = {}
NS:RegisterModule("castbar", M)
M.active = false

local f
local state = {
  active = false,
  channel = false,
  empower = false,
  empowerStages = 0,
  empowerStageDurations = {},
  empowerStageTotalMS = 0,
  empowerHoldMS = 0,
  empowerStage = 0,
  spellName = nil,
  startMS = 0,
  endMS = 0,
  preview = false,
  manualPreview = false,
  unlockPlaceholder = false,
  notInterruptible = false,
  lagCache = nil,
  lagCacheAt = 0,
  events = nil,
}
local LAG_CACHE_INTERVAL = 0.2

local FLAT_TEXTURE = "Interface/TargetingFrame/UI-StatusBar"
local GetTime = GetTime
local GetNetStats = GetNetStats
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local string_format = string.format
local math_max = math.max
local math_min = math.min
local GetUnitEmpowerStageDuration = GetUnitEmpowerStageDuration
local GetUnitEmpowerHoldAtMaxTime = GetUnitEmpowerHoldAtMaxTime

local function IsEditModeActive()
  if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
    return EditModeManagerFrame:IsEditModeActive()
  end
  return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

local function ApplyBarAppearance(bar, db)
  if not bar then return end
  
  local texture = db.castbar.barTexture or FLAT_TEXTURE
  bar:SetStatusBarTexture(texture)
  
  local color = db.castbar.barColor or { r = 0.5, g = 0.5, b = 1.0 }
  bar:SetStatusBarColor(color.r, color.g, color.b, 1.0)
end

local function ApplyTextAppearance(db)
  if not f or not db then return end
  local size = db.castbar.textSize or 11
  NS:ApplyDefaultFont(f.text, size)
  NS:ApplyDefaultFont(f.time, size)
  local c = db.castbar.textColor or { r = 1, g = 1, b = 1 }
  f.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
  f.time:SetTextColor(c.r or 1, c.g or 1, c.b or 1, 1)
end

local function HideBlizzardCastBar()
  if not PlayerCastingBarFrame then return end
  if IsEditModeActive() then return end

  PlayerCastingBarFrame:UnregisterAllEvents()
  PlayerCastingBarFrame:SetAlpha(0)
  if PlayerCastingBarFrame.SetShown then
    PlayerCastingBarFrame:SetShown(false)
  else
    PlayerCastingBarFrame:Hide()
  end
end

local function Create()
  f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(320, 18)
  f:SetFrameStrata("HIGH")

  -- Icon (LEFT)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(18, 18)
  f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Status bar
  f.bar = CreateFrame("StatusBar", nil, f)
  f.bar:SetPoint("LEFT", f.icon, "RIGHT", 2, 0)
  f.bar:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.bar:SetHeight(18)
  f.bar:SetMinMaxValues(0, 1)

  -- Background (flat, no border)
  f.bg = f.bar:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(true)
  f.bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)

  -- Spell name (centered, on top)
  f.text = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("CENTER", f.bar, "CENTER", 0, 0)
  f.text:SetDrawLayer("OVERLAY", 7)

  -- Time remaining (left inside bar)
  f.time = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.time:SetPoint("LEFT", f.bar, "LEFT", 6, 0)
  f.time:SetDrawLayer("OVERLAY", 7)

  -- Shield (right edge)
  f.shield = f:CreateTexture(nil, "OVERLAY")
  f.shield:SetSize(16, 16)
  f.shield:SetPoint("RIGHT", f.bar, "RIGHT", -2, 0)
  f.shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
  f.shield:Hide()

  -- Latency spark
  f.spark = f.bar:CreateTexture(nil, "OVERLAY")
  f.spark:SetWidth(2)
  f.spark:SetColorTexture(1, 1, 1, 0.8)
  f.spark:Hide()

  f.empowerOverlay = f.bar:CreateTexture(nil, "ARTWORK")
  f.empowerOverlay:SetColorTexture(1, 1, 1, 0.08)
  f.empowerOverlay:Hide()

  f.empowerPips = {}
  for i = 1, 4 do
    local pip = f.bar:CreateTexture(nil, "OVERLAY")
    pip:SetWidth(1)
    pip:SetColorTexture(1, 1, 1, 0.35)
    pip:Hide()
    f.empowerPips[i] = pip
  end

  f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  f:Hide()

  NS:MakeMovable(f, "castbar", "Cast Bar (drag)")
end

local function ClearEmpowerVisuals()
  if not f then return end
  if f.empowerOverlay then
    f.empowerOverlay:Hide()
  end
  if f.empowerPips then
    for i = 1, #f.empowerPips do
      f.empowerPips[i]:Hide()
    end
  end
end

local function ConfigureEmpowerStages()
  wipe(state.empowerStageDurations)
  state.empowerStageTotalMS = 0

  if not state.empower then
    state.empowerStages = 0
    return
  end

  local desiredStages = state.empowerStages
  if desiredStages <= 0 then
    desiredStages = 4
  end
  desiredStages = math_min(desiredStages, 4)

  local useZeroBased = false
  if GetUnitEmpowerStageDuration then
    local probe = GetUnitEmpowerStageDuration("player", 0)
    if probe and probe > 0 then
      useZeroBased = true
    end
  end

  local foundStages = 0
  for i = 1, desiredStages do
    local duration = nil
    if GetUnitEmpowerStageDuration then
      local index = useZeroBased and (i - 1) or i
      duration = GetUnitEmpowerStageDuration("player", index)
      if not duration or duration <= 0 then
        local altIndex = useZeroBased and i or (i - 1)
        if altIndex >= 0 then
          duration = GetUnitEmpowerStageDuration("player", altIndex)
        end
      end
    end
    if duration and duration > 0 then
      foundStages = foundStages + 1
      state.empowerStageDurations[foundStages] = duration
      state.empowerStageTotalMS = state.empowerStageTotalMS + duration
    else
      break
    end
  end

  if foundStages == 0 and desiredStages > 0 then
    local chargeDuration = math_max(0, (state.endMS - state.startMS) - (state.empowerHoldMS or 0))
    local perStage = chargeDuration / desiredStages
    for i = 1, desiredStages do
      state.empowerStageDurations[i] = perStage
    end
    state.empowerStageTotalMS = chargeDuration
    foundStages = desiredStages
  end

  if foundStages <= 0 then
    state.empowerStages = 0
  else
    state.empowerStages = foundStages
  end
end

local function GetEmpowerStageAtTime(elapsedMS)
  local stages = state.empowerStages or 0
  if stages <= 0 then return 0 end

  local cumulative = 0
  for i = 1, stages do
    cumulative = cumulative + (state.empowerStageDurations[i] or 0)
    if elapsedMS <= cumulative then
      return i
    end
  end
  return stages
end

local function UpdateEmpowerVisuals(nowMS, durationMS)
  if not f or not state.empower then
    ClearEmpowerVisuals()
    return
  end
  local stages = state.empowerStages or 0
  if stages <= 0 or durationMS <= 0 then
    ClearEmpowerVisuals()
    return
  end

  local elapsedMS = math_max(0, nowMS - state.startMS)
  local currentStage = GetEmpowerStageAtTime(elapsedMS)
  state.empowerStage = currentStage

  local total = durationMS
  local prevBoundary = 0
  local cumulative = 0
  local stageStart = 0
  local stageEnd = total
  for i = 1, stages do
    cumulative = cumulative + (state.empowerStageDurations[i] or 0)
    if i == currentStage then
      stageStart = prevBoundary
      stageEnd = cumulative
      break
    end
    prevBoundary = cumulative
  end
  if elapsedMS > state.empowerStageTotalMS then
    stageStart = state.empowerStageTotalMS
    stageEnd = total
  end

  local startPct = math_max(0, math_min(1, stageStart / total))
  local endPct = math_max(0, math_min(1, stageEnd / total))
  local width = f.bar:GetWidth()
  local left = width * startPct
  local right = width * endPct

  if f.empowerOverlay then
    f.empowerOverlay:ClearAllPoints()
    f.empowerOverlay:SetPoint("TOPLEFT", f.bar, "TOPLEFT", left, 0)
    f.empowerOverlay:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMLEFT", right, 0)
    f.empowerOverlay:Show()
  end

  if f.empowerPips then
    local boundary = 0
    for i = 1, #f.empowerPips do
      local pip = f.empowerPips[i]
      if i < stages then
        boundary = boundary + (state.empowerStageDurations[i] or 0)
        local pct = math_max(0, math_min(1, boundary / total))
        pip:ClearAllPoints()
        pip:SetPoint("TOP", f.bar, "TOPLEFT", width * pct, 0)
        pip:SetPoint("BOTTOM", f.bar, "BOTTOMLEFT", width * pct, 0)
        pip:Show()
      else
        pip:Hide()
      end
    end
  end

  if state.spellName and f.text then
    f.text:SetText(string_format("%s L%d/%d", state.spellName, currentStage, stages))
  end
end

local function IsFramesUnlocked()
  local db = NS:GetDB()
  return db and db.general and db.general.framesLocked == false
end

local function ShowUnlockPlaceholder()
  if not f then return end
  if state.active then return end

  state.unlockPlaceholder = true
  f.icon:SetTexture(134400)
  f.text:SetText("Cast Bar")
  f.time:SetText("")
  f.bar:SetMinMaxValues(0, 1)
  f.bar:SetValue(0)
  state.empower = false
  state.empowerStages = 0
  state.empowerStage = 0
  state.spellName = nil
  ClearEmpowerVisuals()
  if f.spark then f.spark:Hide() end
  if f.shield then f.shield:Hide() end
  f:Show()
end

local function HideUnlockPlaceholder()
  state.unlockPlaceholder = false
  if not state.active and f then
    f:Hide()
  end
end

local function StartCast(preview, manualPreview)
  local name, _, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo("player")
  local channel = false
  local isEmpowered = false
  local numEmpowerStages = 0

  if not name then
    name, _, texture, startMS, endMS, _, notInterruptible, _, isEmpowered, numEmpowerStages = UnitChannelInfo("player")
    channel = true
  end

  -- Preview cast when requested
  if preview then
    name = "Invincible"
    texture = 132251
    startMS = GetTime() * 1000
    endMS = startMS + 2500
    notInterruptible = false
  end

  if not name then return end

  state.active = true
  state.preview = preview and true or false
  state.manualPreview = (preview and manualPreview) and true or false
  state.unlockPlaceholder = false
  state.channel = channel
  state.empower = (not preview) and ((isEmpowered and true) or ((numEmpowerStages or 0) > 0)) or false
  state.empowerStages = state.empower and math_min(numEmpowerStages or 0, 4) or 0
  state.empowerHoldMS = 0
  state.empowerStage = 0
  state.spellName = name
  state.startMS = startMS
  state.endMS = endMS
  state.notInterruptible = notInterruptible and true or false

  if state.empower then
    state.empowerHoldMS = (GetUnitEmpowerHoldAtMaxTime and GetUnitEmpowerHoldAtMaxTime("player")) or 0
    state.endMS = state.endMS + state.empowerHoldMS
    ConfigureEmpowerStages()
  else
    state.empowerStages = 0
    wipe(state.empowerStageDurations)
    state.empowerStageTotalMS = 0
    ClearEmpowerVisuals()
  end

  f.icon:SetTexture(texture)
  f.text:SetText(name)
  f:Show()
end

local function Stop()
  state.active = false
  state.preview = false
  state.manualPreview = false
  state.empower = false
  state.empowerStages = 0
  state.empowerStage = 0
  state.empowerStageTotalMS = 0
  state.empowerHoldMS = 0
  state.spellName = nil
  wipe(state.empowerStageDurations)
  ClearEmpowerVisuals()
  state.notInterruptible = false
  if IsFramesUnlocked() then
    ShowUnlockPlaceholder()
  elseif f then
    f:Hide()
  end
end

local function OnUpdate()
  if not state.active then return end

  local db = NS:GetDB()
  if not db then return end
  local castbar = db.castbar

  local nowSeconds = GetTime()
  local now = nowSeconds * 1000
  local duration = state.endMS - state.startMS
  if duration <= 0 then return end

  local progress
  if state.empower then
    progress = (now - state.startMS) / duration
  elseif state.channel then
    progress = (state.endMS - now) / duration
  else
    progress = (now - state.startMS) / duration
  end

  progress = math_max(0, math_min(1, progress))
  f.bar:SetValue(progress)
  if state.empower then
    UpdateEmpowerVisuals(now, duration)
  else
    ClearEmpowerVisuals()
  end

  local remain = math_max(0, (state.endMS - now) / 1000)
  f.time:SetText(string_format("%.1f", remain))

  if f.spark then
    if castbar.showLatencySpark then
      if not state.lagCache or (nowSeconds - state.lagCacheAt) >= LAG_CACHE_INTERVAL then
        local _, _, _, lagHome = GetNetStats()
        state.lagCache = (lagHome or 0) / 1000
        state.lagCacheAt = nowSeconds
      end
      local lag = state.lagCache or 0
      local dur = duration / 1000
      local offset = (dur > 0) and math_min(lag / dur, 1) or 0
      local pos = math_max(0, math_min(1, progress + offset))
      local w = f.bar:GetWidth()
      f.spark:ClearAllPoints()
      f.spark:SetPoint("CENTER", f.bar, "LEFT", w * pos, 0)
      f.spark:SetHeight(f.bar:GetHeight())
      f.spark:Show()
    else
      f.spark:Hide()
    end
  end

  if f.shield then
    f.shield:SetShown(castbar.showShield and state.notInterruptible)
  end

  if now >= state.endMS then
    if state.preview and state.manualPreview then
      StartCast(true, true)
    else
      Stop()
    end
  end
end

local function ApplyLayout(db)
  local height = db.castbar.height or 16
  f:SetSize(db.castbar.width or 320, height)
  f.bar:SetHeight(height)
  f.icon:SetSize(height, height)

  f.bar:ClearAllPoints()
  if db.castbar.showIcon then
    f.icon:Show()
    f.bar:SetPoint("LEFT", f.icon, "RIGHT", 2, 0)
    f.bar:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  else
    f.icon:Hide()
    f.bar:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.bar:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  end
end

function M:SetLocked(locked)
  if not M.active or not f then return end
  if locked then
    f._huiMover:Hide()
    if state.unlockPlaceholder then
      HideUnlockPlaceholder()
    end
  else
    f._huiMover:Show()
    if not state.active then
      ShowUnlockPlaceholder()
    end
  end
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.castbar or not db.castbar.enabled then
    self:Disable()
    return
  end
  if IsEditModeActive() then
    self:Disable()
    return
  end
  M.active = true

  if not f then
    Create()
  end

  f:SetScript("OnUpdate", OnUpdate)

  if not state.events then
    state.events = CreateFrame("Frame")
    state.events:RegisterEvent("UNIT_SPELLCAST_START")
    state.events:RegisterEvent("UNIT_SPELLCAST_STOP")
    state.events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    state.events:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    state.events:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
    state.events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    state.events:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    state.events:SetScript("OnEvent", function(_, event, unit)
      if not M.active then return end
      if unit ~= "player" then return end
      if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        Stop()
      else
        StartCast(false)
      end
    end)
  end

  HideBlizzardCastBar()

  f:SetScale(db.castbar.scale)
  f:ClearAllPoints()
  f:SetPoint(db.castbar.anchor, UIParent, db.castbar.anchor, db.castbar.x, db.castbar.y)
  
  ApplyLayout(db)
  ApplyBarAppearance(f.bar, db)
  ApplyTextAppearance(db)

  M:SetLocked(db.general.framesLocked)
  if state.unlockPlaceholder and db.general.framesLocked then
    HideUnlockPlaceholder()
  end
end

function M:Preview()
  local db = NS:GetDB()
  if not db or not db.castbar or not db.castbar.enabled then return false end
  if not f then
    Create()
  end

  if state.preview and state.manualPreview then
    Stop()
    return false
  end

  StartCast(true, true)
  return true
end

function M:Disable()
  M.active = false
  state.active = false
  state.preview = false
  state.manualPreview = false
  state.unlockPlaceholder = false
  state.notInterruptible = false
  if f then f:Hide() end
  if f then
    f:SetScript("OnUpdate", nil)
  end
  if state.events then
    state.events:UnregisterAllEvents()
    state.events:SetScript("OnEvent", nil)
    state.events:Hide()
    state.events:SetParent(nil)
    state.events = nil
  end

  -- Restore Blizzard cast bar
  if PlayerCastingBarFrame then
    PlayerCastingBarFrame:SetAlpha(1)
    if PlayerCastingBarFrame.SetShown then
      PlayerCastingBarFrame:SetShown(true)
    else
      PlayerCastingBarFrame:Show()
    end
    -- Re-register default events
    PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_START")
    PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
  end
end
