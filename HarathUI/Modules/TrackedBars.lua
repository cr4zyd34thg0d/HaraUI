local ADDON, NS = ...
local M = {}
NS:RegisterModule("trackedbars", M)

M.active = false

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local FLAT_TEXTURE = "Interface/TargetingFrame/UI-StatusBar"
local UPDATE_INTERVAL = 0.4

local scanFrame
local elapsedSinceScan = 0
local skinnedBars = {}
local hiddenRegions = {}

local function SaveAndHideRegion(region)
  if not region or hiddenRegions[region] then return end
  hiddenRegions[region] = {
    alpha = region.GetAlpha and region:GetAlpha() or 1,
    shown = region.IsShown and region:IsShown() or false,
  }
  if region.SetAlpha then region:SetAlpha(0) end
  if region.Hide then region:Hide() end
end

local function RestoreHiddenRegions()
  for region, state in pairs(hiddenRegions) do
    if region then
      if region.SetAlpha and state.alpha ~= nil then
        region:SetAlpha(state.alpha)
      end
      if region.SetShown then
        region:SetShown(state.shown == true)
      elseif state.shown and region.Show then
        region:Show()
      end
    end
  end
  wipe(hiddenRegions)
end

local function ApplyTextFont(fs, db)
  if not fs or not fs.SetFont then return end
  local size = db.castbar and db.castbar.textSize or 11
  local outline = db.castbar and db.castbar.textOutline
  if outline == "NONE" then outline = nil end
  local fontPath
  if LSM and db.castbar and db.castbar.textFont then
    fontPath = LSM:Fetch("font", db.castbar.textFont, true)
  end
  fs:SetFont(fontPath or STANDARD_TEXT_FONT, size or 11, outline)
end

local function ApplyTextColor(fs, db)
  if not fs or not fs.SetTextColor then return end
  local color = db.castbar and db.castbar.textColor or { r = 1, g = 1, b = 1 }
  fs:SetTextColor(color.r or 1, color.g or 1, color.b or 1, 1)
end

local function ApplyBarStyle(bar, db)
  if not bar then return end
  if not bar.SetStatusBarTexture then return end

  if not skinnedBars[bar] then
    local textureObj = bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
    skinnedBars[bar] = {
      texture = textureObj and textureObj.GetTexture and textureObj:GetTexture() or nil,
      colorR = select(1, bar:GetStatusBarColor()),
      colorG = select(2, bar:GetStatusBarColor()),
      colorB = select(3, bar:GetStatusBarColor()),
      colorA = select(4, bar:GetStatusBarColor()),
      bgTexture = bar.bg and bar.bg.GetTexture and bar.bg:GetTexture() or nil,
      bgR = bar.bg and bar.bg.GetVertexColor and select(1, bar.bg:GetVertexColor()) or nil,
      bgG = bar.bg and bar.bg.GetVertexColor and select(2, bar.bg:GetVertexColor()) or nil,
      bgB = bar.bg and bar.bg.GetVertexColor and select(3, bar.bg:GetVertexColor()) or nil,
      bgA = bar.bg and bar.bg.GetVertexColor and select(4, bar.bg:GetVertexColor()) or nil,
    }
  end

  local texture = (db.castbar and db.castbar.barTexture) or FLAT_TEXTURE
  local color = (db.castbar and db.castbar.barColor) or { r = 0.5, g = 0.5, b = 1.0 }
  bar:SetStatusBarTexture(texture)
  bar:SetStatusBarColor(color.r or 0.5, color.g or 0.5, color.b or 1.0, 1.0)

  bar.bg = bar.bg or bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(true)
  bar.bg:SetTexture(texture)
  bar.bg:SetVertexColor(0.15, 0.15, 0.15, 0.6)
  if bar.bg.Show then
    bar.bg:Show()
  end

  local nameFS = bar.Name or bar.Text or bar.Label or bar.name
  local countFS = bar.Count or bar.StackCount or bar.RightText or bar.count
  ApplyTextFont(nameFS, db)
  ApplyTextFont(countFS, db)
  ApplyTextColor(nameFS, db)
  ApplyTextColor(countFS, db)

  -- Blizzard tracked bars use BarBG atlas textures on some builds.
  SaveAndHideRegion(bar.BarBG)
  SaveAndHideRegion(bar.Border)
  SaveAndHideRegion(bar.Frame)
  SaveAndHideRegion(bar.Background)
  SaveAndHideRegion(bar.BG)
  SaveAndHideRegion(bar.LeftCap)
  SaveAndHideRegion(bar.RightCap)
  SaveAndHideRegion(bar.Shine)
  SaveAndHideRegion(bar.Spark)
  SaveAndHideRegion(bar.Glow)
end

local function IsStatusBarFrame(frame)
  return frame and frame.GetObjectType and frame:GetObjectType() == "StatusBar"
end

local function ScanChildren(frame, db, depth)
  if not frame or not frame.GetChildren then return end
  if depth <= 0 then return end

  local children = { frame:GetChildren() }
  for _, child in ipairs(children) do
    if IsStatusBarFrame(child) then
      ApplyBarStyle(child, db)
    end
    ScanChildren(child, db, depth - 1)
  end
end

local function GetCooldownViewerRoot()
  return BuffBarCooldownViewer or CooldownViewer
end

local function ScanCooldownViewerBars()
  local db = NS:GetDB()
  if not db then return end
  local root = GetCooldownViewerRoot()
  if not root or not root.GetChildren then return end

  ScanChildren(root, db, 5)
end

local function RestoreBars()
  for bar, state in pairs(skinnedBars) do
    if bar and state then
      if bar.SetStatusBarTexture then
        bar:SetStatusBarTexture(state.texture or FLAT_TEXTURE)
      end
      if bar.SetStatusBarColor then
        bar:SetStatusBarColor(state.colorR or 1, state.colorG or 1, state.colorB or 1, state.colorA or 1)
      end
      if bar.bg and state.bgTexture then
        bar.bg:SetTexture(state.bgTexture)
        if state.bgR then
          bar.bg:SetVertexColor(state.bgR, state.bgG or 1, state.bgB or 1, state.bgA or 1)
        end
      elseif bar.bg and bar.bg.Hide then
        bar.bg:Hide()
      end
    end
  end
  wipe(skinnedBars)
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.general or not db.general.trackedBarsSkin then
    self:Disable()
    return
  end

  M.active = true
  if not scanFrame then
    scanFrame = CreateFrame("Frame")
  end

  elapsedSinceScan = 0
  scanFrame:SetScript("OnUpdate", function(_, elapsed)
    if not M.active then return end
    elapsedSinceScan = elapsedSinceScan + (elapsed or 0)
    if elapsedSinceScan < UPDATE_INTERVAL then return end
    elapsedSinceScan = 0
    ScanCooldownViewerBars()
  end)

  ScanCooldownViewerBars()
end

function M:Disable()
  M.active = false
  if scanFrame then
    scanFrame:SetScript("OnUpdate", nil)
  end
  RestoreBars()
  RestoreHiddenRegions()
end
