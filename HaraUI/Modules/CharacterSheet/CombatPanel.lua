local _, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.CombatPanel = CS.CombatPanel or {}
local CombatPanel = CS.CombatPanel
local Utils = CS.Utils

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
-- trees with one call each.  SetAlpha is NOT a protected function and works
-- freely during combat lockdown.
--
-- The combat view shows: dark background + Blizzard slot icons + 3D model
-- + tab bar.  Gear text rows are suppressed to avoid the overlapping mess
-- caused by left/right columns colliding without the stats column separator.
-- Slot icons are repositioned: right column anchored to the right side of
-- CharacterFrame with weapons centered between the two columns.
--
-- A CharacterFrame_ShowSubFrame hook detects tab switches during combat and
-- alpha-zeros root on rep/currency tabs so native Blizzard frames show cleanly.
--
-- On combat end (PLAYER_REGEN_ENABLED) or frame close, everything is
-- restored and the normal layout re-apply takes over.
---------------------------------------------------------------------------

CombatPanel._state = CombatPanel._state or {
  active = false,
  tabHookInstalled = false,
  currentPane = "character",
}

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
-- Detect which native Blizzard sub-frame is currently visible.
-- Called at Show() time (before the deferred tick) so we get the real
-- active tab even if the user had rep/currency open before entering combat.
---------------------------------------------------------------------------
local function DetectActiveCombatPane()
  local repFrame = _G.ReputationFrame or nil
  if repFrame and repFrame.IsShown and repFrame:IsShown() then return "reputation" end
  local tokenFrame = CharacterFrameTokenFrame or nil
  if tokenFrame and tokenFrame.IsShown and tokenFrame:IsShown() then return "currency" end
  return "character"
end

---------------------------------------------------------------------------
-- Grouped overlay helpers.
-- SuppressOverlays suppresses everything except fState.root, which is
-- managed separately by _ApplyCombatPaneVisibility based on active tab.
-- RestoreOverlays restores all overlays including fState.root.
---------------------------------------------------------------------------
local function GetStaticOverlays(fState)
  local panels = fState.panels
  local rp = CS and CS.MythicPanel or nil
  local pp = CS and CS.PortalPanel or nil
  local ppState = pp and pp._state or nil
  return {
    panels and panels.right,
    rp and rp._state and rp._state.root,
    ppState and ppState.root,
    ppState and ppState.gridRoot,
    fState.leftPaneHeadingHost,
  }
end

local function SuppressOverlays(fState)
  for _, f in ipairs(GetStaticOverlays(fState)) do
    Suppress(f)
  end
  -- Center name/title header since the stats panel is no longer beside it.
  local Skin = CS and CS.Skin or nil
  if Skin and Skin.SetHeaderCentered then Skin.SetHeaderCentered(true) end
end

local function RestoreOverlays(fState)
  for _, f in ipairs(GetStaticOverlays(fState)) do
    Restore(f)
  end
  Restore(fState.root)
  -- Restore header to normal offset (ApplyCustomHeader will also do this).
  local Skin = CS and CS.Skin or nil
  if Skin and Skin.SetHeaderCentered then Skin.SetHeaderCentered(false) end
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
-- Hooks both CharacterFrame_ShowSubFrame (if it exists) and the native
-- Blizzard tab buttons as a fallback for WoW 12.0.
---------------------------------------------------------------------------
function CombatPanel:_EnsureTabHook()
  local state = self._state
  if state.tabHookInstalled then return end
  state.tabHookInstalled = true

  local function OnTabSwitch(pane)
    if not state.active then return end
    state.currentPane = pane
    self:_ApplyCombatPaneVisibility()
  end

  -- Hook CharacterFrame_ShowSubFrame if available.
  if hooksecurefunc and type(CharacterFrame_ShowSubFrame) == "function" then
    hooksecurefunc("CharacterFrame_ShowSubFrame", function(subFrameToken)
      local pane = NormalizePaneName(subFrameToken)
      if pane then OnTabSwitch(pane) end
    end)
  end

  -- Hook our own custom HaraUI tab buttons (safe — these are our frames,
  -- not protected Blizzard frames, so no taint risk near currency transfer).
  local fState = Utils.GetFactoryState()
  local tabs = fState and fState.tabs or nil
  if tabs then
    local tabMap = {
      { tab = tabs.tabCharacter,  pane = "character"  },
      { tab = tabs.tabReputation, pane = "reputation" },
      { tab = tabs.tabCurrency,   pane = "currency"   },
    }
    for _, entry in ipairs(tabMap) do
      if entry.tab and entry.tab.HookScript then
        entry.tab:HookScript("OnClick", function(_, button)
          if button and button ~= "LeftButton" then return end
          OnTabSwitch(entry.pane)
        end)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Root visibility based on active tab.
-- Character tab: show root (gear rows visible).
-- Rep/Currency tabs: suppress root so gear rows don't bleed over native content.
---------------------------------------------------------------------------
function CombatPanel:_ApplyCombatPaneVisibility()
  local state = self._state
  local fState = Utils.GetFactoryState()
  if not fState then return end

  if state.currentPane == "character" then
    Restore(fState.root)
  else
    Suppress(fState.root)
  end
end

---------------------------------------------------------------------------
-- Show: detect actual active tab, suppress all overlays, apply pane
-- visibility.  Deferred one tick to run outside the secure execution context.
---------------------------------------------------------------------------
function CombatPanel:Show()
  local state = self._state
  state.active = true
  state.currentPane = "character"

  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if not state.active then return end
      local fState = Utils.GetFactoryState()
      if not fState then return end

      -- Re-detect inside the deferred tick so WoW has had time to call
      -- CharacterFrame_ShowSubFrame and make the active sub-frame visible.
      state.currentPane = DetectActiveCombatPane()
      -- Suppress all static overlays (stats panel, mythic, portal, heading).
      SuppressOverlays(fState)
      -- Apply root visibility based on detected pane (fixes bleed when
      -- entering combat with rep/currency tab open).
      self:_ApplyCombatPaneVisibility()
      -- Reposition slot icons for combat layout.
      self:_ApplyCombatSlotLayout()
      -- Show GearDisplay (deferred during combat so OnShow never ran).
      local gear = CS and CS.GearDisplay or nil
      if gear and gear.OnShow then gear:OnShow("combat") end
      -- Install tab-switch hook (idempotent, one-time install).
      self:_EnsureTabHook()
    end)
  end
end

---------------------------------------------------------------------------
-- Hide: restore all suppressed overlays in one call.
-- The post-combat layout re-apply (PLAYER_REGEN_ENABLED → Apply) will
-- re-anchor everything for the expanded frame, including slot positions
-- via ApplyHaraSlotLayout.
---------------------------------------------------------------------------
function CombatPanel:Hide()
  local state = self._state
  if not state.active then return end
  state.active = false

  local fState = Utils.GetFactoryState()
  if not fState then return end
  -- Restore everything (static overlays + root + header) in one grouped call.
  RestoreOverlays(fState)
end
