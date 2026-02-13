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

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local f
local state = {
  active = false,
  channel = false,
  startMS = 0,
  endMS = 0,
  preview = false,
  manualPreview = false,
  unlockPlaceholder = false,
  notInterruptible = false,
}
local lagCache
local lagCacheAt = 0
local LAG_CACHE_INTERVAL = 0.2

local FLAT_TEXTURE = "Interface/TargetingFrame/UI-StatusBar"

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
  if not db.castbar.textFont then
    db.castbar.textFont = "BigNoodleTilting"
  end
  local size = db.castbar.textSize or 11
  local outline = db.castbar.textOutline
  if outline == "NONE" then outline = nil end
  local fontPath
  if LSM and db.castbar.textFont then
    fontPath = LSM:Fetch("font", db.castbar.textFont, true)
  end
  if not fontPath then
    fontPath = STANDARD_TEXT_FONT
  end
  if fontPath then
    f.text:SetFont(fontPath, size, outline)
    f.time:SetFont(fontPath, size, outline)
  end
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

  f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  f:Hide()

  NS:MakeMovable(f, "castbar", "Cast Bar (drag)")
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

  if not name then
    name, _, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo("player")
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
  state.startMS = startMS
  state.endMS = endMS
  state.notInterruptible = notInterruptible and true or false

  f.icon:SetTexture(texture)
  f.text:SetText(name)
  f:Show()
end

local function Stop()
  state.active = false
  state.preview = false
  state.manualPreview = false
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

  local now = GetTime() * 1000
  local duration = state.endMS - state.startMS
  if duration <= 0 then return end

  local progress
  if state.channel then
    progress = (state.endMS - now) / duration
  else
    progress = (now - state.startMS) / duration
  end

  progress = math.max(0, math.min(1, progress))
  f.bar:SetValue(progress)

  local remain = math.max(0, (state.endMS - now) / 1000)
  f.time:SetText(string.format("%.1f", remain))

  if f.spark then
    if db.castbar.showLatencySpark then
      local nowSeconds = GetTime()
      if not lagCache or (nowSeconds - lagCacheAt) >= LAG_CACHE_INTERVAL then
        local _, _, _, lagHome = GetNetStats()
        lagCache = (lagHome or 0) / 1000
        lagCacheAt = nowSeconds
      end
      local lag = lagCache or 0
      local dur = duration / 1000
      local offset = (dur > 0) and math.min(lag / dur, 1) or 0
      local pos = math.max(0, math.min(1, progress + offset))
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
    f.shield:SetShown(db.castbar.showShield and state.notInterruptible)
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

  if not M.events then
    M.events = CreateFrame("Frame")
    M.events:RegisterEvent("UNIT_SPELLCAST_START")
    M.events:RegisterEvent("UNIT_SPELLCAST_STOP")
    M.events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    M.events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    M.events:SetScript("OnEvent", function(_, event, unit)
      if not M.active then return end
      if unit ~= "player" then return end
      if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
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
  if M.events then
    M.events:UnregisterAllEvents()
    M.events:SetScript("OnEvent", nil)
    M.events:Hide()
    M.events:SetParent(nil)
    M.events = nil
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
