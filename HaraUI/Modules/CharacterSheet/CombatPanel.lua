local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.CombatPanel = CS.CombatPanel or {}
local CombatPanel = CS.CombatPanel

---------------------------------------------------------------------------
-- Combat-mode cleanup module.
--
-- When CharacterFrame opens during combat, the full HaraUI layout is already
-- mostly functional — slot button icons and the 3D model render correctly.
-- What doesn't fit cleanly: the stats panel, sidebar buttons, gradient,
-- right-side overlay panels, and the gear text rows (which overlap each
-- other when the stats column is removed).
--
-- This module uses SetAlpha(0) on container frames to suppress entire frame
-- trees with one call each.  No element-by-element toggling.  SetAlpha is
-- NOT a protected function and works freely during combat lockdown.
--
-- The combat view shows: dark background + Blizzard slot icons + 3D model
-- + tab bar.  Gear text rows are suppressed to avoid the overlapping mess
-- caused by left/right columns colliding without the stats column separator.
-- Slot icons are repositioned: right column anchored to the right side of
-- CharacterFrame with weapons centered between the two columns.
--
-- A CharacterFrame_ShowSubFrame hook detects tab switches during combat and
-- alpha-zeros root when on reputation/currency tabs (hiding all custom
-- content so native Blizzard frames show cleanly).
--
-- On combat end (PLAYER_REGEN_ENABLED) or frame close, everything is
-- restored and the normal layout re-apply takes over.
---------------------------------------------------------------------------

CombatPanel._state = CombatPanel._state or {
  active = false,
  tabHookInstalled = false,
  currentPane = "character",
}

local function GetFactoryState()
  local factory = CS and CS.FrameFactory or nil
  return factory and factory._state or nil
end

local function NormalizePaneName(token)
  local pm = CS and CS.PaneManager or nil
  if pm and pm.NormalizePane then
    return pm.NormalizePane(token)
  end
  -- Minimal fallback if PaneManager not loaded yet
  if type(token) ~= "string" then return nil end
  local lower = string.lower(token)
  if lower == "paperdollframe" or lower == "paperdoll" then return "character" end
  if lower == "reputationframe" or lower == "reputation" then return "reputation" end
  if lower:find("token", 1, true) or lower:find("currency", 1, true) then return "currency" end
  return nil
end

-- Suppress a container frame: alpha-zero hides it and all children.
local function Suppress(frame)
  if not frame then return end
  if frame.SetAlpha then frame:SetAlpha(0) end
end

-- Restore a container frame to full visibility.
local function Restore(frame)
  if not frame then return end
  if frame.SetAlpha then frame:SetAlpha(1) end
end

---------------------------------------------------------------------------
-- Combat slot layout: right column mirrored to the right side of the frame,
-- weapons centered between columns.  Left column stays at normal position.
-- The 3D model (CharacterModelScene) is protected and cannot be repositioned
-- during combat, but it naturally appears more to the left with the wider
-- column spread.
---------------------------------------------------------------------------
local SLOT_NAMES_LEFT = {
  "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
  "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
  "CharacterTabardSlot", "CharacterWristSlot",
}
local SLOT_NAMES_RIGHT = {
  "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot",
  "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
  "CharacterTrinket0Slot", "CharacterTrinket1Slot",
}

function CombatPanel:_ApplyCombatSlotLayout()
  local anchor = CharacterFrame
  if not anchor then return end

  local Skin = CS and CS.Skin or nil
  local CFG = Skin and Skin.CFG or nil
  if not CFG then return end

  local slotSize = CFG.SLOT_ICON_SIZE or 38
  local stride = slotSize + (CFG.SLOT_VPAD or 24)
  local topY = CFG.SLOT_TOP_Y or -64
  local leftX = tonumber((CFG.LeftGearCluster or {}).IconX) or 14
  local frameWidth = math.floor((anchor:GetWidth() or 943) + 0.5)
  -- Mirror: right column inset matches left column inset
  local rightX = frameWidth - leftX - slotSize

  for i, name in ipairs(SLOT_NAMES_LEFT) do
    local slot = _G[name]
    if slot then
      slot:SetSize(slotSize, slotSize)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", anchor, "TOPLEFT", leftX, topY - stride * (i - 1))
    end
  end

  for i, name in ipairs(SLOT_NAMES_RIGHT) do
    local slot = _G[name]
    if slot then
      slot:SetSize(slotSize, slotSize)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", anchor, "TOPLEFT", rightX, topY - stride * (i - 1))
    end
  end

  -- Weapons: centered between the two columns at the bottom
  local mainHand = _G.CharacterMainHandSlot
  local offHand = _G.CharacterSecondaryHandSlot
  if mainHand and offHand then
    local pairGapX = tonumber((CFG.WeaponGearCluster or {}).PairGapX) or 68
    local weaponBottomY = tonumber((CFG.WeaponGearCluster or {}).BottomY) or 71
    local leftCenter = leftX + slotSize * 0.5
    local rightCenter = rightX + slotSize * 0.5
    local centerX = math.floor((leftCenter + rightCenter) * 0.5 + 0.5)
    local mainHandX = math.floor(centerX - pairGapX * 0.5 - slotSize * 0.5 + 0.5)

    mainHand:SetSize(slotSize, slotSize)
    mainHand:ClearAllPoints()
    mainHand:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", mainHandX, weaponBottomY)
    offHand:SetSize(slotSize, slotSize)
    offHand:ClearAllPoints()
    offHand:SetPoint("TOPLEFT", mainHand, "TOPLEFT", pairGapX, 0)
  end
end

---------------------------------------------------------------------------
-- Tab-switch hook: installed once, only acts while state.active is true.
-- Alpha-zeros root on non-character tabs so gear rows don't bleed through
-- behind native Blizzard reputation/currency content.
---------------------------------------------------------------------------
function CombatPanel:_EnsureTabHook()
  local state = self._state
  if state.tabHookInstalled then return end
  if not (hooksecurefunc and type(CharacterFrame_ShowSubFrame) == "function") then return end
  state.tabHookInstalled = true

  hooksecurefunc("CharacterFrame_ShowSubFrame", function(subFrameToken)
    if not state.active then return end
    local pane = NormalizePaneName(subFrameToken)
    if not pane then return end
    state.currentPane = pane
    self:_ApplyCombatPaneVisibility()
  end)
end

function CombatPanel:_ApplyCombatPaneVisibility()
  local state = self._state
  local fState = GetFactoryState()
  if not fState then return end

  if state.currentPane == "character" then
    -- Character tab: show root (dark bg + slot icons visible)
    Restore(fState.root)
  else
    -- Rep/Currency tabs: hide root entirely — alpha propagates to all
    -- children (panels.left, panels.right, etc.)
    Suppress(fState.root)
  end
end

---------------------------------------------------------------------------
-- Show: suppress non-essential containers for a clean combat view.
-- Deferred one tick to run outside the secure execution context.
---------------------------------------------------------------------------
function CombatPanel:Show()
  local state = self._state
  state.active = true
  state.currentPane = "character"

  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if not state.active then return end
      local fState = GetFactoryState()
      if not fState then return end
      local panels = fState.panels

      -- 1) Stats panel + sidebar buttons (panels.right → rightTop/rightBottom)
      Suppress(panels and panels.right)
      -- 2) RightPanel + PortalPanel (suppress individually, NOT characterOverlay,
      --    because the character name/title header is also parented there).
      local rp = CS and CS.RightPanel or nil
      local rpRoot = rp and rp._state and rp._state.root or nil
      Suppress(rpRoot)
      local pp = CS and CS.PortalPanel or nil
      local ppState = pp and pp._state or nil
      Suppress(ppState and ppState.root)
      Suppress(ppState and ppState.gridRoot)
      -- 3) Pane heading ("Currency" / "Reputation" text)
      Suppress(fState.leftPaneHeadingHost)
      -- 4) Reposition slot icons for combat layout (right column to right side)
      self:_ApplyCombatSlotLayout()

      -- 5) Show GearDisplay (item texts + gradients).  DispatchOnShow is deferred
      --    during combat so GearDisplay:OnShow never ran.  GearDisplay.root is
      --    parented to panels.left (custom frame, not protected) — Show() is safe.
      --    Rows anchor to slot buttons so they follow the combat slot layout.
      local gear = CS and CS.GearDisplay or nil
      if gear and gear.OnShow then gear:OnShow("combat") end

      -- 6) Center the character name/title header between frame edges.
      --    Normal layout offsets it left to account for the stats panel.
      local Skin = CS and CS.Skin or nil
      if Skin and Skin.SetHeaderCentered then Skin.SetHeaderCentered(true) end

      -- 6) Install tab-switch hook (idempotent, one-time install).
      self:_EnsureTabHook()
    end)
  end
end

---------------------------------------------------------------------------
-- Hide: restore all suppressed containers.
-- The post-combat layout re-apply (PLAYER_REGEN_ENABLED → Apply) will
-- re-anchor everything for the expanded frame, including slot positions
-- via ApplyHaraSlotLayout.
---------------------------------------------------------------------------
function CombatPanel:Hide()
  local state = self._state
  if not state.active then return end
  state.active = false

  local fState = GetFactoryState()
  if not fState then return end
  local panels = fState.panels

  Restore(panels and panels.right)
  local rp = CS and CS.RightPanel or nil
  local rpRoot = rp and rp._state and rp._state.root or nil
  Restore(rpRoot)
  local pp = CS and CS.PortalPanel or nil
  local ppState = pp and pp._state or nil
  Restore(ppState and ppState.root)
  Restore(ppState and ppState.gridRoot)
  Restore(fState.leftPaneHeadingHost)
  Restore(fState.root)

  -- Restore header to normal offset (ApplyCustomHeader will also do this,
  -- but reset explicitly in case layout re-apply is delayed).
  local Skin = CS and CS.Skin or nil
  if Skin and Skin.SetHeaderCentered then Skin.SetHeaderCentered(false) end
end
