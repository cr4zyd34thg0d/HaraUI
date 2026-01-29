local ADDON, NS = ...
local M = {}
NS:RegisterModule("minimapbar", M)
M.active = false

local bar
local tab
local holder
local grabbed = {}
local ACCENT = { 1, 0.45, 0.05, 0.98 }
local LDBI = (LibStub and LibStub("LibDBIcon-1.0", true)) or nil
local ApplyPosition
local lastAnchor
local lastOrientation
local hoverTicker
local warmupTicker
local CreateFrames
local ApplyPopoutAlpha
local HasClickScript
local ignoreNamePatterns = {
  "^MiniMapTracking",
  "^MiniMapTrackingButton",
  "^QueueStatusMinimapButton",
  "^GarrisonLandingPageMinimapButton",
  "^ExpansionLandingPageMinimapButton",
  "^TimeManagerClockButton",
  "^GameTimeFrame",
  "^MiniMapWorldMapButton",
  "^MiniMapMailFrame",
  "^MinimapCluster%.",
  "^MinimapCluster%.BorderTop",
  "MinimapZone",
  "MinimapBorder",
  "MinimapToggle",
}
local ignoreByName = {
  Minimap = true,
  MinimapBackdrop = true,
  MinimapCluster = true,
  MinimapZoomIn = true,
  MinimapZoomOut = true,
  MiniMapTracking = true,
  MiniMapTrackingButton = true,
  MiniMapMailFrame = true,
  MiniMapWorldMapButton = true,
  GameTimeFrame = true,
  TimeManagerClockButton = true,
  QueueStatusMinimapButton = true,
  GarrisonLandingPageMinimapButton = true,
  AddonCompartmentFrame = true,
  MinimapZoneText = true,
  MinimapZoneTextButton = true,
  MinimapBorder = true,
  MinimapBorderTop = true,
}
local buttonCache
local buttonCacheTime = 0
local buttonCacheTTL = 2

local function GetDB()
  local db = NS:GetDB()
  return db and db.minimapbar
end


local function Clamp(v, minv, maxv)
  if v < minv then return minv end
  if v > maxv then return maxv end
  return v
end

local function IsMinimapOrAncestor(frame)
  if not frame or not Minimap then return false end
  if frame == Minimap then return true end
  local parent = Minimap.GetParent and Minimap:GetParent()
  local depth = 0
  while parent and depth < 10 do
    if parent == frame then return true end
    parent = parent.GetParent and parent:GetParent() or nil
    depth = depth + 1
  end
  return false
end

local function EnsureMinimapParent()
  if not Minimap then return end
  local wantParent = MinimapCluster or UIParent
  if Minimap.GetParent and Minimap:GetParent() ~= wantParent then
    Minimap:SetParent(wantParent)
  end
end


local function IsDescendantOf(frame, ancestor)
  if not frame or not ancestor then return false end
  local depth = 0
  while frame and depth < 10 do
    if frame == ancestor then return true end
    frame = frame.GetParent and frame:GetParent() or nil
    depth = depth + 1
  end
  return false
end

local function EnsureZoomButtonsVisible()
  if not Minimap then return end
  if MinimapZoomIn then
    if MinimapZoomIn.GetParent and MinimapZoomIn:GetParent() ~= Minimap then
      MinimapZoomIn:SetParent(Minimap)
    end
    MinimapZoomIn:SetAlpha(1)
    MinimapZoomIn:Show()
  end
  if MinimapZoomOut then
    if MinimapZoomOut.GetParent and MinimapZoomOut:GetParent() ~= Minimap then
      MinimapZoomOut:SetParent(Minimap)
    end
    MinimapZoomOut:SetAlpha(1)
    MinimapZoomOut:Show()
  end
  if not Minimap._huiZoomHooked then
    Minimap._huiZoomHooked = true
    Minimap:HookScript("OnEnter", EnsureZoomButtonsVisible)
    Minimap:HookScript("OnLeave", EnsureZoomButtonsVisible)
  end
end


local function UpdateOrientationFromAnchor(db)
  if not db then return end
  local anchor = db.anchor or "RIGHT"
  if anchor == "LEFT" or anchor == "RIGHT" then
    db.orientation = "HORIZONTAL"
  else
    db.orientation = "VERTICAL"
  end
end

local function NormalizeAnchor(db)
  if not db or not db.anchor then return end
  local a = db.anchor
  if type(a) ~= "string" then return end
  a = a:upper()
  if a:find("LEFT", 1, true) then
    db.anchor = "LEFT"
  elseif a:find("RIGHT", 1, true) then
    db.anchor = "RIGHT"
  elseif a:find("TOP", 1, true) then
    db.anchor = "TOP"
  elseif a:find("BOTTOM", 1, true) then
    db.anchor = "BOTTOM"
  end
end

local function NormalizeEdgePosition(db)
  if not db or not holder then return end
  NormalizeAnchor(db)
  local uiw = UIParent:GetWidth()
  local uih = UIParent:GetHeight()
  local hw = holder:GetWidth() / 2
  local hh = holder:GetHeight() / 2
  local xMax = math.max(0, (uiw / 2) - hw)
  local yMax = math.max(0, (uih / 2) - hh)
  if db.anchor == "LEFT" or db.anchor == "RIGHT" then
    db.x = 0
    db.y = Clamp(db.y or 0, -yMax, yMax)
  else
    db.y = 0
    db.x = Clamp(db.x or 0, -xMax, xMax)
  end
end

local function IsEligibleButton(btn)
  if not btn then return false end

  -- Must be a Button or Frame object type
  if not btn.IsObjectType then return false end
  local objType = btn:IsObjectType("Button") or btn:IsObjectType("Frame")
  if not objType then return false end

  -- Explicitly reject FontStrings and other text regions
  if btn:IsObjectType("FontString") then return false end

  if btn == Minimap or btn == MinimapBackdrop then return false end
  if btn.IsProtected and btn:IsProtected() then return false end

  local name = btn.GetName and btn:GetName()

  -- Check explicit ignore lists
  if name and ignoreByName[name] then return false end
  if IsZoomButton and IsZoomButton(btn) then return false end

  -- Check ignore patterns
  if name then
    for i = 1, #ignoreNamePatterns do
      if name:match(ignoreNamePatterns[i]) then
        return false
      end
    end
    -- Additional name checks
    if name:find("Zoom", 1, true) then return false end
    if name:find("Text", 1, true) then return false end
    if name:find("Label", 1, true) then return false end
  end

  -- Check parent
  local parent = btn.GetParent and btn:GetParent()
  if parent then
    local pname = parent.GetName and parent:GetName()
    if pname and (pname:find("MinimapZoom", 1, true) or pname:find("MiniMapZoom", 1, true)) then
      return false
    end
  end

  -- LibDBIcon buttons are always eligible
  if name and name:find("^LibDBIcon10_") then return true end

  -- Must have visual indicators (texture/icon) or be a Button type
  if btn.GetNormalTexture and btn:GetNormalTexture() then return true end
  if btn.icon or btn.Icon then return true end
  if btn.IsObjectType and btn:IsObjectType("Button") then
    if btn.GetScript and btn:GetScript("OnClick") then return true end
  end

  return false
end

local function IsUnderMinimap(frame)
  local depth = 0
  local widgetBelow = _G and _G.UIWidgetBelowMinimapContainerFrame
  while frame and depth < 8 do
    if frame == Minimap or frame == MinimapBackdrop or frame == MinimapCluster or frame == widgetBelow then
      return true
    end
    local name = frame.GetName and frame:GetName()
    if type(name) == "string" then
      if name:find("MinimapContainer", 1, true) or name:find("MinimapCluster", 1, true) then
        return true
      end
    end
    frame = frame.GetParent and frame:GetParent() or nil
    depth = depth + 1
  end
  return false
end

local function TextureLooksLikeZoom(tex)
  if not tex or type(tex) ~= "string" then return false end
  local t = tex:lower()
  return t:find("minimap-zoom", 1, true)
    or t:find("minimapzoom", 1, true)
    or t:find("ui-minimap-zoom", 1, true)
    or t:find("ui-hud-minimap-zoom", 1, true)
    or t:find("zoom_in", 1, true)
    or t:find("zoom_out", 1, true)
end

local function AtlasLooksLikeZoom(atlas)
  if not atlas or type(atlas) ~= "string" then return false end
  local a = atlas:lower()
  return a:find("minimap-zoom", 1, true)
    or a:find("ui-hud-minimap-zoom", 1, true)
end

local function IsZoomButton(btn)
  if not btn or not btn.IsObjectType then return false end
  local name = btn.GetName and btn:GetName()
  if name and name:find("Zoom", 1, true) then return true end
  if btn.IsObjectType and btn:IsObjectType("Button") then
    local norm = btn.GetNormalTexture and btn:GetNormalTexture()
    if norm then
      if norm.GetTexture and TextureLooksLikeZoom(norm:GetTexture()) then return true end
      if norm.GetAtlas and AtlasLooksLikeZoom(norm:GetAtlas()) then return true end
    end
    local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
    if pushed then
      if pushed.GetTexture and TextureLooksLikeZoom(pushed:GetTexture()) then return true end
      if pushed.GetAtlas and AtlasLooksLikeZoom(pushed:GetAtlas()) then return true end
    end
    local highlight = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if highlight then
      if highlight.GetTexture and TextureLooksLikeZoom(highlight:GetTexture()) then return true end
      if highlight.GetAtlas and AtlasLooksLikeZoom(highlight:GetAtlas()) then return true end
    end
  end
  if btn.GetRegions then
    for _, region in ipairs({ btn:GetRegions() }) do
      if region and region.IsObjectType and region:IsObjectType("Texture") then
        if (region.GetTexture and TextureLooksLikeZoom(region:GetTexture()))
          or (region.GetAtlas and AtlasLooksLikeZoom(region:GetAtlas())) then
          return true
        end
      end
    end
  end
  return false
end

local function IsButtonLike(frame)
  if not frame then return false end
  if frame.IsProtected and frame:IsProtected() then return false end

  local width = frame.GetWidth and frame:GetWidth() or 0
  local height = frame.GetHeight and frame:GetHeight() or 0

  if not width or not height or width <= 0 or height <= 0 then return false end

  -- Must be at least 16px and roughly square (within 5px difference)
  if math.max(width, height) <= 16 then return false end
  if math.abs(width - height) >= 5 then return false end

  return true
end

HasClickScript = function(frame, depth)
  if not frame or depth and depth > 3 then return false end
  depth = (depth or 0) + 1
  if frame.HasScript then
    if frame:HasScript("OnClick") and frame:GetScript("OnClick") then return true end
    if frame:HasScript("OnMouseUp") and frame:GetScript("OnMouseUp") then return true end
    if frame:HasScript("OnMouseDown") and frame:GetScript("OnMouseDown") then return true end
  end
  if frame.GetChildren then
    for _, child in ipairs({ frame:GetChildren() }) do
      if HasClickScript(child, depth) then return true end
    end
  end
  return false
end

local function SaveOriginal(btn)
  if grabbed[btn] then return end
  local points = {}
  if btn.GetNumPoints then
    for i = 1, btn:GetNumPoints() do
      points[i] = { btn:GetPoint(i) }
    end
  end
  local onDragStart = btn.GetScript and btn:GetScript("OnDragStart")
  local onDragStop = btn.GetScript and btn:GetScript("OnDragStop")
  if btn.RegisterForDrag then
    btn:RegisterForDrag()
  end
  if btn.SetScript then
    btn:SetScript("OnDragStart", nil)
    btn:SetScript("OnDragStop", nil)
  end
  grabbed[btn] = {
    parent = btn:GetParent(),
    points = points,
    strata = btn:GetFrameStrata(),
    level = btn:GetFrameLevel(),
    scale = btn:GetScale(),
    w = btn:GetWidth(),
    h = btn:GetHeight(),
    onDragStart = onDragStart,
    onDragStop = onDragStop,
  }
  btn._huiMinimapBar = true
end

local function RestoreButton(btn)
  local info = grabbed[btn]
  if not info then return end
  btn._huiMinimapBar = nil
  if info.parent and btn.SetParent then btn:SetParent(info.parent) end
  if btn.ClearAllPoints then
    btn:ClearAllPoints()
    if info.points then
      for _, pt in ipairs(info.points) do
        btn:SetPoint(unpack(pt))
      end
    end
  end
  if info.strata then btn:SetFrameStrata(info.strata) end
  if info.level then btn:SetFrameLevel(info.level) end
  if info.scale then btn:SetScale(info.scale) end
  if info.w and info.h then btn:SetSize(info.w, info.h) end
  if btn.RegisterForDrag then
    btn:RegisterForDrag("LeftButton", "RightButton")
  end
  if btn.SetScript then
    if info.onDragStart then btn:SetScript("OnDragStart", info.onDragStart) end
    if info.onDragStop then btn:SetScript("OnDragStop", info.onDragStop) end
  end
  grabbed[btn] = nil
end

local function CollectButtons()
  if buttonCache and (GetTime() - buttonCacheTime) < buttonCacheTTL then
    return buttonCache
  end
  local list = {}
  local seen = {}

  local function Add(btn)
    if not btn or seen[btn] then return end
    if btn._huiMinimapBar then
      seen[btn] = true
      list[#list + 1] = btn
      return
    end
    if btn == Minimap or btn == MinimapBackdrop or btn == MinimapCluster then return end
    if IsMinimapOrAncestor(btn) then return end
    if MinimapCluster and MinimapCluster.BorderTop and IsDescendantOf(btn, MinimapCluster.BorderTop) then return end
    if not IsEligibleButton(btn) or IsZoomButton(btn) then return end

    local name = btn.GetName and btn:GetName()
    local isLDB = type(name) == "string" and name ~= "" and name:find("^LibDBIcon10_") ~= nil

    if isLDB then
      seen[btn] = true
      list[#list + 1] = btn
      return
    end

    -- Additional checks for non-LDB buttons
    if not IsUnderMinimap(btn) then return end
    if not IsButtonLike(btn) then return end
    if not HasClickScript(btn) then return end

    seen[btn] = true
    list[#list + 1] = btn
  end

  -- First, grab LibDBIcon buttons (most reliable)
  if LDBI and LDBI.GetButtonList then
    local names = LDBI:GetButtonList()
    for i = 1, #names do
      local btn = LDBI:GetMinimapButton(names[i])
      Add(btn)
    end
  end

  -- Include already grabbed buttons so sizing keeps up dynamically
  for btn in pairs(grabbed) do
    Add(btn)
  end

  -- Scan direct children of Minimap and MinimapBackdrop (like HidingBar does)
  if Minimap and Minimap.GetChildren then
    for _, child in ipairs({ Minimap:GetChildren() }) do
      Add(child)
    end
  end

  if MinimapBackdrop and MinimapBackdrop.GetChildren then
    for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
      Add(child)
    end
  end

  if MinimapCluster and MinimapCluster.GetChildren then
    for _, child in ipairs({ MinimapCluster:GetChildren() }) do
      if child ~= MinimapCluster.BorderTop then
        Add(child)
      end
    end
  end

  -- Fallback: enumerate all frames looking for LDB buttons (only if we found nothing)
  if #list == 0 and EnumerateFrames then
    local f = EnumerateFrames()
    local iter = 0
    while f do
      iter = iter + 1
      local name = f.GetName and f:GetName()
      if type(name) == "string" and name:find("^LibDBIcon10_") then
        Add(f)
      end
      f = EnumerateFrames(f)
      if iter > 10000 then break end
    end
  end

  -- Sort by name for consistency
  table.sort(list, function(a, b)
    local an = a.GetName and a:GetName() or ""
    local bn = b.GetName and b:GetName() or ""
    return an < bn
  end)

  buttonCache = list
  buttonCacheTime = GetTime()
  return buttonCache
end

local function ApplyOrientation()
  if not bar or not tab or not holder then return end
  local db = GetDB()
  if not db then return end
  local gap = 4
  local bw, bh = bar:GetWidth(), bar:GetHeight()
  local anchor = db.anchor or "RIGHT"
  local tabScale = 1.04

  tab:ClearAllPoints()
  bar:ClearAllPoints()

  -- Tab orientation follows screen edge; popout direction follows edge rules.
  if anchor == "LEFT" or anchor == "RIGHT" then
    tab:SetSize(8, math.floor(bh * tabScale + 0.5))
    if anchor == "LEFT" then
      tab:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
      bar:SetPoint("TOPLEFT", tab, "TOPRIGHT", gap, 0)
    else
      tab:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
      bar:SetPoint("TOPRIGHT", tab, "TOPLEFT", -gap, 0)
    end
    holder:SetSize(bw + gap + tab:GetWidth(), bh)
  else
    tab:SetSize(math.floor(bw * tabScale + 0.5), 8)
    if anchor == "TOP" then
      tab:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
      bar:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, -gap)
    else
      tab:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
      bar:SetPoint("BOTTOMLEFT", tab, "TOPLEFT", 0, gap)
    end
    holder:SetSize(bw, bh + gap + tab:GetHeight())
  end
end

local function LayoutButtons()
  if not bar then return end
  local db = GetDB()
  if not db then return end

  local function IsBorderTexture(tex, atlas, name)
    local t = (type(tex) == "string" and tex or ""):lower()
    local a = (type(atlas) == "string" and atlas or ""):lower()
    local n = (type(name) == "string" and name or ""):lower()
    if n:find("border", 1, true) then return true end
    if t:find("border", 1, true) and (t:find("minimap", 1, true) or t:find("tracking", 1, true)) then return true end
    if a:find("border", 1, true) and (a:find("minimap", 1, true) or a:find("tracking", 1, true)) then return true end
    if t:find("minimap%-trackingborder", 1, true) then return true end
    if t:find("ui%-minimap%-border", 1, true) then return true end
    return false
  end

  local function StripButtonBorder(btn)
    if not btn or not btn.GetRegions then return end
    local iconTex = btn.icon or btn.Icon
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    local mainTex = iconTex or normal
    local textures = {}
    for _, region in ipairs({ btn:GetRegions() }) do
      if region and region.IsObjectType and region:IsObjectType("Texture") then
        textures[#textures + 1] = region
      end
    end

    if not mainTex then
      local bestScore
      for i = 1, #textures do
        local region = textures[i]
        local w = region.GetWidth and region:GetWidth() or 0
        local h = region.GetHeight and region:GetHeight() or 0
        local tex = region.GetTexture and region:GetTexture()
        local atlas = region.GetAtlas and region:GetAtlas()
        local name = region.GetName and region:GetName()
        if (tex or atlas) and w > 0 and h > 0 then
          local area = w * h
          local score = area
          if IsBorderTexture(tex, atlas, name) then
            score = score - 100000
          else
            score = score + 1000
          end
          if not bestScore or score > bestScore then
            bestScore = score
            mainTex = region
          end
        end
      end
    end

    if not mainTex then return end

    for i = 1, #textures do
      local region = textures[i]
      if region ~= mainTex then
        region:Hide()
      end
    end
    if btn.Border and btn.Border.Hide then btn.Border:Hide() end
    if btn.border and btn.border.Hide then btn.border:Hide() end

    -- If the button has its own icon texture, hide common ring/border layers.
    if mainTex then
      local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
      if pushed and pushed.Hide then pushed:Hide() end
      local highlight = btn.GetHighlightTexture and btn:GetHighlightTexture()
      if highlight and highlight.Hide then highlight:Hide() end
      local disabled = btn.GetDisabledTexture and btn:GetDisabledTexture()
      if disabled and disabled.Hide then disabled:Hide() end
    end
  end

  local buttons = CollectButtons()
  local btnSize = db.buttonSize or 30
  local gap = db.gap or 4
  local pad = 12
  local outer = 8

  local count = #buttons
  UpdateOrientationFromAnchor(db)
  NormalizeAnchor(db)
  local orientation = db.orientation or "VERTICAL"
  local anchor = db.anchor or "RIGHT"
  local rows
  local cols
  if orientation == "HORIZONTAL" then
    rows = 1
    cols = math.max(1, count)
  else
    cols = 1
    rows = math.max(1, count)
  end
  local buttonSpan = btnSize + gap
  -- Add extra padding to ensure buttons fit properly
  local minWidth = cols * buttonSpan + (pad * 2) + outer * 2
  local height = rows * buttonSpan + (pad * 2) + outer * 2
  local width = minWidth

  if orientation == "HORIZONTAL" then
    local uiw = UIParent:GetWidth() or 0
    local tabWidth = 8
    local edgeIndent = gap
    local avail = uiw - (tabWidth + gap) - edgeIndent
    if avail > width then
      width = avail
    end
  end

  bar:SetSize(width, height)
  ApplyOrientation()

  local basePoint = "TOPLEFT"
  local xSign = 1
  local ySign = -1
  if orientation == "HORIZONTAL" then
    if anchor == "RIGHT" then
      basePoint = "TOPRIGHT"
      xSign = -1
      ySign = -1
    else
      basePoint = "TOPLEFT"
      xSign = 1
      ySign = -1
    end
  else
    if anchor == "BOTTOM" then
      basePoint = "BOTTOMLEFT"
      xSign = 1
      ySign = 1
    else
      basePoint = "TOPLEFT"
      xSign = 1
      ySign = -1
    end
  end

  local leftPad
  if orientation == "HORIZONTAL" then
    local totalButtons = (count * btnSize) + (math.max(0, count - 1) * gap)
    leftPad = (width - totalButtons) / 2
  end

  for i, btn in ipairs(buttons) do
    if IsMinimapOrAncestor(btn) then
      -- Safety: never reparent minimap or its parents.
    else
      SaveOriginal(btn)
      btn:SetParent(bar)
    end
    btn:ClearAllPoints()
    local row
    local col
    if orientation == "HORIZONTAL" then
      row = 0
      col = (i - 1)
    else
      row = (i - 1)
      col = 0
    end
    local offset
    if orientation == "HORIZONTAL" then
      offset = (leftPad or (pad + outer)) + (btnSize / 2)
    else
      offset = (btnSize / 2) + pad + outer
    end
    local x = (offset + col * buttonSpan) * xSign
    local y = (offset + row * buttonSpan) * ySign

    -- Reset scale to 1.0 to get accurate size, then resize to fit
    btn:SetScale(1.0)
    local bw, bh = btn:GetSize()
    if bw > 0 and bh > 0 then
      -- Scale the button to fit within btnSize while maintaining aspect ratio
      local maxSize = math.max(bw, bh)
      local scale = btnSize / maxSize
      if scale > 1 then scale = 1 end
      btn:SetScale(scale)
    else
      -- Fallback: set explicit size if button has no dimensions
      btn:SetSize(btnSize, btnSize)
    end

    btn:SetPoint("CENTER", bar, basePoint, x, y)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(bar:GetFrameLevel() + 2)
    StripButtonBorder(btn)
    if btn.SetAlpha then btn:SetAlpha(1) end
    if btn.Show then btn:Show() end
  end
end

local function StartHoverRefresh()
  if hoverTicker then return end
  local ticks = 0
  hoverTicker = C_Timer.NewTicker(0.1, function()
    if not bar or not bar:IsShown() then
      if hoverTicker then hoverTicker:Cancel() end
      hoverTicker = nil
      return
    end
    LayoutButtons()
    ticks = ticks + 1
    if ticks >= 20 then
      if hoverTicker then hoverTicker:Cancel() end
      hoverTicker = nil
    end
  end)
end

local function StartWarmupRefresh()
  if not M.active then return end
  if warmupTicker then return end
  local ticks = 0
  warmupTicker = C_Timer.NewTicker(0.1, function()
    if not M.active then return end
    if InCombatLockdown and InCombatLockdown() then return end
    CreateFrames()
    LayoutButtons()
    ApplyOrientation()
    ApplyPopoutAlpha()
    ticks = ticks + 1
    if ticks >= 20 then
      if warmupTicker then warmupTicker:Cancel() end
      warmupTicker = nil
    end
  end)
end

local function ShowBar(fromTab)
  if not bar then return end
  if fromTab ~= true and tab and not tab:IsMouseOver() then
    return
  end
  bar:Show()
  bar:SetAlpha(1)
  bar:EnableMouse(true)
  C_Timer.After(0, function()
    if not bar or not bar:IsShown() then return end
    if ApplyPosition then
      ApplyPosition()
    end
    LayoutButtons()
    StartHoverRefresh()
  end)
end

local function HideBar()
  if not bar then return end
  bar:Hide()
  bar:EnableMouse(false)
end

local function ScheduleHide()
  local db = GetDB()
  local delay = (db and db.popoutStay) or 1.5
  C_Timer.After(delay, function()
    if not bar or not tab then return end
    if bar:IsMouseOver() or tab:IsMouseOver() then return end
    HideBar()
  end)
end

CreateFrames = function()
  if holder then return end
  holder = CreateFrame("Frame", "HaraUI_MinimapBarHolder", UIParent, "BackdropTemplate")
  holder:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)
  holder:SetSize(220, 40)
  holder:SetClampedToScreen(true)
  holder:SetMovable(false)
  holder:EnableMouse(false)
  if holder._huiMover then
    holder._huiMover:Hide()
    holder._huiMover = nil
  end

  bar = CreateFrame("Frame", "HaraUI_MinimapBar", holder, "BackdropTemplate")
  bar:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  bar:SetBackdropColor(0.05, 0.05, 0.06, 0.85)
  bar:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
  bar:Hide()

  tab = CreateFrame("Button", "HaraUI_MinimapBarTab", holder, "BackdropTemplate")
  tab:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  tab:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
  tab:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
  tab.accent = tab:CreateTexture(nil, "ARTWORK")
  tab.accent:SetAllPoints(true)
  tab.accent:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], ACCENT[4])
  tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tab.text:SetPoint("CENTER", 0, 0)
  tab.text:SetText("")
  tab.text:SetTextColor(0, 0, 0, 0)
  tab.text:SetJustifyH("CENTER")
  tab.text:SetJustifyV("MIDDLE")
  tab.text:SetShadowColor(0, 0, 0, 0)
  tab.text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
  tab.text:SetAllPoints(tab.accent)
  tab:RegisterForDrag("LeftButton")
  tab:SetScript("OnDragStart", function()
    local db = GetDB()
    if db and db.locked then return end
    holder:SetScript("OnUpdate", function()
      if not db then return end
      local uiw = UIParent:GetWidth()
      local uih = UIParent:GetHeight()
      local scale = UIParent:GetEffectiveScale()
      local x, y = GetCursorPosition()
      x = x / scale
      y = y / scale
      local left = x
      local right = uiw - x
      local top = uih - y
      local bottom = y
      local anchor
      local snap = 60
      if left <= snap then
        anchor = "LEFT"
      elseif right <= snap then
        anchor = "RIGHT"
      elseif top <= snap then
        anchor = "TOP"
      elseif bottom <= snap then
        anchor = "BOTTOM"
      else
        local min = math.min(left, right, top, bottom)
        if min == left then
          anchor = "LEFT"
        elseif min == right then
          anchor = "RIGHT"
        elseif min == top then
          anchor = "TOP"
        else
          anchor = "BOTTOM"
        end
      end
      local ox, oy = 0, 0
      local hw = holder:GetWidth() / 2
      local hh = holder:GetHeight() / 2
      local xMax = math.max(0, (uiw / 2) - hw)
      local yMax = math.max(0, (uih / 2) - hh)
      if anchor == "LEFT" or anchor == "RIGHT" then
        oy = Clamp(math.floor((y - uih / 2) + 0.5), -yMax, yMax)
      else
        ox = Clamp(math.floor((x - uiw / 2) + 0.5), -xMax, xMax)
      end
      db.anchor = anchor
      db.x = ox
      db.y = oy
      UpdateOrientationFromAnchor(db)
      NormalizeEdgePosition(db)
      ApplyPosition()
    end)
  end)
  tab:SetScript("OnDragStop", function()
    holder:SetScript("OnUpdate", nil)
    if NS.Modules and NS.Modules.minimapbar and NS.Modules.minimapbar.SnapToEdge then
      NS.Modules.minimapbar:SnapToEdge()
    end
    LayoutButtons()
    ApplyOrientation()
  end)
  tab:SetScript("OnEnter", function() ShowBar(true) end)
  tab:SetScript("OnLeave", ScheduleHide)
  bar:SetScript("OnEnter", ShowBar)
  bar:SetScript("OnLeave", ScheduleHide)

end

ApplyPopoutAlpha = function()
  if not bar then return end
  local db = GetDB()
  local alpha = db and db.popoutAlpha or 0.85
  bar:SetBackdropColor(0.05, 0.05, 0.06, alpha)
end

function M:ApplyPopoutAlpha()
  ApplyPopoutAlpha()
end

function M:RefreshLayout()
  if InCombatLockdown and InCombatLockdown() then return end
  LayoutButtons()
  ApplyOrientation()
  ApplyPopoutAlpha()
end

ApplyPosition = function()
  local db = GetDB()
  if not db or not holder then return end
  NormalizeAnchor(db)
  UpdateOrientationFromAnchor(db)
  NormalizeEdgePosition(db)
  local changed = (db.anchor ~= lastAnchor) or (db.orientation ~= lastOrientation)
  holder:ClearAllPoints()
  holder:SetPoint(db.anchor or "RIGHT", UIParent, db.anchor or "RIGHT", db.x or 0, db.y or 0)
  holder:SetScale(db.scale or 1.0)
  LayoutButtons()
  ApplyOrientation()
  ApplyPopoutAlpha()
  if changed and bar and bar:IsShown() then
    bar:Hide()
    bar:Show()
  end
  lastAnchor = db.anchor
  lastOrientation = db.orientation
end

local function Refresh()
  if not M.active then return end
  if InCombatLockdown and InCombatLockdown() then return end
  EnsureMinimapParent()
  EnsureZoomButtonsVisible()
  CreateFrames()
  ApplyPosition()
  LayoutButtons()
  ApplyOrientation()
  ApplyPopoutAlpha()
end

function M:SetLocked(locked, fromOptions)
  if not fromOptions then return end
  local db = GetDB()
  if db then
    db.locked = locked and true or false
  end
end

function M:SnapToEdge()
  if not holder then return end
  local db = GetDB()
  if not db then return end
  local uiw = UIParent:GetWidth()
  local uih = UIParent:GetHeight()
  local cx, cy = holder:GetCenter()
  if not cx or not cy then return end
  local left = cx
  local right = uiw - cx
  local top = uih - cy
  local bottom = cy
  local anchor
  local x = 0
  local y = 0
  local hw = holder:GetWidth() / 2
  local hh = holder:GetHeight() / 2
  local xMax = math.max(0, (uiw / 2) - hw)
  local yMax = math.max(0, (uih / 2) - hh)

  local min = math.min(left, right, top, bottom)
  if min == left then
    anchor = "LEFT"
    x = 0
    y = Clamp(math.floor((cy - uih / 2) + 0.5), -yMax, yMax)
  elseif min == right then
    anchor = "RIGHT"
    x = 0
    y = Clamp(math.floor((cy - uih / 2) + 0.5), -yMax, yMax)
  elseif min == top then
    anchor = "TOP"
    x = Clamp(math.floor((cx - uiw / 2) + 0.5), -xMax, xMax)
    y = 0
  else
    anchor = "BOTTOM"
    x = Clamp(math.floor((cx - uiw / 2) + 0.5), -xMax, xMax)
    y = 0
  end

  db.anchor = anchor
  db.x = x
  db.y = y
  UpdateOrientationFromAnchor(db)
  NormalizeEdgePosition(db)
  ApplyPosition()
  ApplyOrientation()
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.minimapbar or not db.minimapbar.enabled then
    self:Disable()
    return
  end
  M.active = true
  EnsureMinimapParent()
  EnsureZoomButtonsVisible()
  db.minimapbar.orientation = "VERTICAL"
  if db.minimapbar.locked == nil then
    db.minimapbar.locked = false
  end
  db.minimapbar.locked = (db.minimapbar.locked == true)
  if db.minimapbar.popoutAlpha == nil then
    db.minimapbar.popoutAlpha = 0.85
  end
  if db.minimapbar.popoutStay == nil then
    db.minimapbar.popoutStay = 2.0
  end
  CreateFrames()
  ApplyPosition()
  LayoutButtons()
  ApplyPopoutAlpha()
  HideBar()
  if tab then tab:Show() end
  self:SetLocked(db.minimapbar.locked)
  self:SnapToEdge()

  if not self.eventFrame then
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:SetScript("OnEvent", function(_, event)
      if not M.active then return end
      -- Invalidate button cache when new addons load
      if event == "ADDON_LOADED" then
        buttonCache = nil
      end
      Refresh()
      StartWarmupRefresh()
    end)
  end
  C_Timer.After(1, Refresh)
  C_Timer.After(4, Refresh)
  StartWarmupRefresh()
end

function M:Disable()
  M.active = false
  if self.eventFrame then
    self.eventFrame:UnregisterAllEvents()
  end
  if hoverTicker then
    hoverTicker:Cancel()
    hoverTicker = nil
  end
  if warmupTicker then
    warmupTicker:Cancel()
    warmupTicker = nil
  end
  for btn in pairs(grabbed) do
    RestoreButton(btn)
  end
  if bar then bar:Hide() end
  if tab then tab:Hide() end
end
