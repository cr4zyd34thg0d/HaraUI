local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.RightPanel = CS.RightPanel or {}
local RightPanel = CS.RightPanel

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local PANEL_WIDTH = 640
local PANEL_HEIGHT = 620
local TICK_INTERVAL = 1.5
local THROTTLE_INTERVAL = 0.10
local NUM_DUNGEON_ROWS = 8
local ROW_HEIGHT = 32
local ROW_SPACING = 35

local AFFIX_BORDER_COLORS = {
  { 0.20, 0.80, 0.25, 1.0 }, -- +4
  { 0.95, 0.82, 0.22, 1.0 }, -- +7
  { 0.98, 0.56, 0.18, 1.0 }, -- +10
  { 0.92, 0.26, 0.22, 1.0 }, -- +12
}
local AFFIX_LEVEL_LABELS = { "4", "7", "10", "12" }

local VAULT_TRACK_TYPE_BY_ROW = { 2, 1, 3 } -- Mythic+, Raid, World
local VAULT_TRACK_NAMES = { [1] = "Raid", [2] = "Mythic+", [3] = "World" }

local PORTAL_ALIASES = {
  ["the motherlode"] = { common = { "the m o t h e r l o d e", "motherlode" } },
  ["the dawnbreaker"] = {
    common = { "dawnbreaker", "arathi flagship", "hero s path of the arathi flagship" },
  },
  ["siege of boralus"] = {
    alliance = { "siege of boralus" },
    horde = { "siege of boralus" },
  },
  ["mechagon junkyard"] = { common = { "junkyard", "mechagon junkyard", "operation mechagon", "mechagon" } },
  ["mechagon workshop"] = { common = { "workshop", "mechagon workshop", "operation mechagon", "mechagon" } },
  ["operation mechagon junkyard"] = { common = { "junkyard", "mechagon junkyard", "operation mechagon", "mechagon" } },
  ["operation mechagon workshop"] = { common = { "workshop", "mechagon workshop", "operation mechagon", "mechagon" } },
  ["tazavesh streets of wonder"] = {
    common = { "tazavesh", "veiled market", "streetwise merchant", "path of the streetwise merchant" },
  },
  ["tazavesh so leah s gambit"] = {
    common = { "tazavesh", "veiled market", "streetwise merchant", "path of the streetwise merchant" },
  },
  ["galakrond s fall"] = { common = { "dawn of the infinite" } },
  ["murozond s rise"] = { common = { "dawn of the infinite" } },
  ["dawn of the infinite galakrond s fall"] = { common = { "dawn of the infinite", "galakrond s fall" } },
  ["dawn of the infinite murozond s rise"] = { common = { "dawn of the infinite", "murozond s rise" } },
  ["lower karazhan"] = { common = { "return to karazhan", "karazhan" } },
  ["upper karazhan"] = { common = { "return to karazhan", "karazhan" } },
  ["return to karazhan lower"] = { common = { "return to karazhan", "karazhan" } },
  ["return to karazhan upper"] = { common = { "return to karazhan", "karazhan" } },
}
local VAULT_THRESHOLDS = { [1] = { 1, 4, 6 }, [2] = { 2, 4, 8 }, [3] = { 2, 4, 8 } }
local VAULT_TRACK_COLORS = {
  [1] = { 0.05, 0.08, 0.16, 0.74,  0.20, 0.30, 0.55, 0.88 }, -- Raids (blue)
  [2] = { 0.12, 0.04, 0.18, 0.74,  0.38, 0.22, 0.56, 0.90 }, -- Dungeons (purple)
  [3] = { 0.06, 0.11, 0.08, 0.74,  0.20, 0.40, 0.26, 0.88 }, -- World (green)
}
local VAULT_UNLOCKED_ILVL_COLOR = { 1.00, 0.84, 0.22, 1.0 }

local WEEKLY_REWARD_TYPE = {}
do
  local t = Enum and Enum.WeeklyRewardChestThresholdType
  WEEKLY_REWARD_TYPE.Raid = (t and t.Raid) or 1
  WEEKLY_REWARD_TYPE.Activities = (t and t.Activities) or 2
  WEEKLY_REWARD_TYPE.World = (t and t.World) or 3
  WEEKLY_REWARD_TYPE.RankedPvP = (t and t.RankedPvP) or 4
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
RightPanel._state = RightPanel._state or {
  root = nil,
  created = false,
  hooksInstalled = false,
  characterHookInstalled = false,
  eventFrame = nil,
  ticker = nil,
  tickerToken = 0,
  dirtyReason = nil,
  pendingSecureUpdate = false,
  affixSlots = nil,
  dungeonRows = nil,
  vaultCards = nil,
  lastSnapshot = { ownerKey = nil, affixIDs = nil, runs = nil },
  portalCache = {},
  counters = { creates = 0, updateRequests = 0, updatesApplied = 0, tickerStarts = 0, tickerTicks = 0 },
}

local function IsRefactorEnabled()
  return CS and CS.IsRefactorEnabled and CS:IsRefactorEnabled()
end

local function IsAccountTransferBuild()
  return C_CurrencyInfo and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function"
end

local function IsNativeCurrencyMode()
  local layoutState = CS and CS.Layout and CS.Layout._state or nil
  if not layoutState then
    return false
  end
  return layoutState.nativeCurrencyMode == true and layoutState.activePane == "currency"
end

local function IsCharacterPaneActive()
  local layoutState = CS and CS.Layout and CS.Layout._state or nil
  if not layoutState then
    return true
  end
  if layoutState.nativeCurrencyMode == true then
    return false
  end
  local pane = layoutState.activePane
  if type(pane) ~= "string" then
    return true
  end
  return pane == "character"
end

local function EnsureState(self)
  local s = self._state
  s.counters = s.counters or { creates = 0, updateRequests = 0, updatesApplied = 0, tickerStarts = 0, tickerTicks = 0 }
  s.lastSnapshot = s.lastSnapshot or { ownerKey = nil, affixIDs = nil, runs = nil }
  s.portalCache = s.portalCache or {}
  return s
end

local function EnsureSkin()
  return CS and CS.Skin or nil
end

local function ApplyFont(fs, size)
  if not fs then return end
  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(fs, size or 12)
  end
end

local function IsRightPanelPreferenceEnabled()
  local db = nil
  if NS and NS.GetDB then
    db = NS:GetDB()
  elseif NS then
    db = NS.db
  end
  if type(db) ~= "table" then
    return true
  end
  local csdb = db.charsheet
  if type(csdb) ~= "table" then
    return true
  end
  return csdb.showRightPanel ~= false
end

local function ApplyPreferredVisibility(state)
  local root = state and state.root or nil
  local charShown = CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()
  local shouldShow = IsRightPanelPreferenceEnabled() and IsCharacterPaneActive() and charShown == true
  if not root then
    return shouldShow
  else
    if shouldShow then
      if root.Show then root:Show() end
    else
      if root.Hide then root:Hide() end
    end
  end
  return shouldShow
end

---------------------------------------------------------------------------
-- Utility: format milliseconds as mm:ss or h:mm:ss
---------------------------------------------------------------------------
local function FormatMS(ms)
  if not ms or ms <= 0 then return "-" end
  local total = math.floor((ms / 1000) + 0.5)
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%02d:%02d"):format(m, s)
end

local function StarText(stars)
  stars = tonumber(stars) or 0
  stars = math.max(0, math.min(3, math.floor(stars + 0.5)))
  if stars <= 0 then return "" end
  local out = ""
  for i = 1, stars do
    if i > 1 then out = out .. " " end
    out = out .. "|cffffd100*|r"
  end
  return out
end

local function NormalizeDurationMS(value, keyName)
  if type(value) ~= "number" then return nil end
  local key = type(keyName) == "string" and string.lower(keyName) or ""
  if key:find("sec") and value < 100000 then
    return math.floor((value * 1000) + 0.5)
  end
  if value > 0 and value < 100000 then
    return math.floor((value * 1000) + 0.5)
  end
  return math.floor(value + 0.5)
end

local function ToNumber(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end
  return nil
end

---------------------------------------------------------------------------
-- Dungeon map helpers
---------------------------------------------------------------------------
local function GetDungeonMapIcon(mapID)
  if not mapID or mapID <= 0 then return 134400 end
  if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return 134400 end
  local ok, a, b, c, d, e = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
  if not ok then return 134400 end
  if type(d) == "number" then return d end
  if type(e) == "number" then return e end
  if type(c) == "number" and c > 1000 then return c end
  if type(b) == "number" and b > 1000 then return b end
  if type(a) == "number" and a > 1000 then return a end
  return 134400
end

local function GetDungeonTimeLimitMS(mapID)
  if not mapID or mapID <= 0 then return nil end
  if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
  local ok, a, b, c, d, e, f = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
  if not ok then return nil end
  for _, v in ipairs({ a, b, c, d, e, f }) do
    if type(v) == "number" then
      if v >= 600 and v <= 7200 then return math.floor((v * 1000) + 0.5) end
      if v >= 600000 and v <= 7200000 then return math.floor(v + 0.5) end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Portal spell lookup (simplified from Legacy)
---------------------------------------------------------------------------
local PORTAL_CACHE_VERSION = 2

local function NormalizeName(s)
  if type(s) ~= "string" then return "" end
  s = string.lower(s)
  s = s:gsub("[%p]", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function IsSpellKnownCompat(spellID)
  if not spellID then return false end
  if IsSpellKnownOrOverridesKnown then return IsSpellKnownOrOverridesKnown(spellID) end
  if IsSpellKnown then return IsSpellKnown(spellID) end
  if IsPlayerSpell then return IsPlayerSpell(spellID) end
  return false
end

local function GetPortalAliases(mapName, mapID)
  local aliases = {}
  local seen = {}
  local function AddAlias(v)
    v = NormalizeName(v)
    if v ~= "" and not seen[v] then
      seen[v] = true
      aliases[#aliases + 1] = v
    end
  end

  if type(mapName) == "string" and mapName ~= "" then
    AddAlias(mapName)
  end
  if type(mapID) == "number" and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
    local uiName = C_ChallengeMode.GetMapUIInfo(mapID)
    if type(uiName) == "string" and uiName ~= "" then
      AddAlias(uiName)
    end
  end

  -- Common text mismatch: spell descriptions often omit a leading "The".
  for i = 1, #aliases do
    local alias = aliases[i]
    if alias:find("^the%s+") then
      AddAlias(alias:gsub("^the%s+", ""))
    end
  end

  -- Expand aliases from all matching keys so variant map names can chain to the same portal hints.
  local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
  faction = faction and string.lower(faction) or ""
  local expanded = {}
  local idx = 1
  while idx <= #aliases do
    local key = aliases[idx]
    if key and key ~= "" and not expanded[key] then
      expanded[key] = true
      local entry = PORTAL_ALIASES[key]
      if entry then
        if entry.common then
          for _, v in ipairs(entry.common) do
            AddAlias(v)
          end
        end
        if faction ~= "" and entry[faction] then
          for _, v in ipairs(entry[faction]) do
            AddAlias(v)
          end
        end
      end
    end
    idx = idx + 1
  end
  return aliases
end

local function PortalDestinationName(spellName)
  local dest = NormalizeName(spellName)
  if dest == "" then return "" end
  dest = dest:gsub("^teleport%s*:?%s*", "")
  dest = dest:gsub("^portal%s*:?%s*", "")
  dest = dest:gsub("^to%s+", "")
  dest = dest:gsub("%s+", " ")
  dest = dest:gsub("^%s+", "")
  dest = dest:gsub("%s+$", "")
  return dest
end

local function FindPortalSpellForMap(mapName, mapID, cache)
  if not mapName or mapName == "" then return nil, nil end
  if type(cache) ~= "table" then return nil, nil end
  local cacheKey = ("%d|%s|%s"):format(PORTAL_CACHE_VERSION, tostring(mapName), tostring(mapID or 0))
  if cache[cacheKey] ~= nil then
    local c = cache[cacheKey]
    if type(c) == "table" then
      return c.spellID or nil, c.actionID or nil
    end
    return nil, nil
  end

  local aliases = GetPortalAliases(mapName, mapID)
  local bestID
  local bestActionID
  local bestScore = 0
  local bestCastable = false
  local seen = {}
  local spellActionByID = {}
  local spellBookType = BOOKTYPE_SPELL or "spell"
  local spellBookBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or spellBookType

  local function ScoreCandidateSpell(spellID)
    if not spellID or seen[spellID] then return end
    seen[spellID] = true

    local rawName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or GetSpellInfo(spellID)
    local spellName = NormalizeName(rawName)
    local rawDesc = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)) or ""
    local spellDesc = NormalizeName(rawDesc)

    local tokenCastable = false
    if IsUsableSpell then
      local usableByID, noManaByID = IsUsableSpell(spellID)
      if usableByID ~= nil or noManaByID ~= nil then
        tokenCastable = true
      elseif rawName and rawName ~= "" then
        local usableByName, noManaByName = IsUsableSpell(rawName)
        if usableByName ~= nil or noManaByName ~= nil then
          tokenCastable = true
        end
      end
    end

    local looksLikeTravelSpell = (spellName ~= "" and (spellName:find("teleport") or spellName:find("portal") or spellName:find("path")))
      or (spellDesc ~= "" and (spellDesc:find("teleport") or spellDesc:find("portal") or spellDesc:find("entrance")))
    if not looksLikeTravelSpell then
      return
    end

    local dest = PortalDestinationName(spellName)
    for _, alias in ipairs(aliases) do
      if alias ~= "" then
        local score = 0
        if dest == alias then
          score = 1000 + #alias
        elseif #alias >= 5 and dest:find(alias, 1, true) then
          score = 500 + #alias
        elseif #dest >= 5 and alias:find(dest, 1, true) then
          score = 300 + #dest
        end
        if #alias >= 5 and spellDesc ~= "" and spellDesc:find(alias, 1, true) then
          score = math.max(score, 900 + #alias)
        end
        if score > 0 and (score > bestScore or (score == bestScore and tokenCastable and not bestCastable)) then
          bestScore = score
          bestID = spellID
          bestActionID = spellActionByID[spellID]
          bestCastable = tokenCastable
        end
      end
    end
  end

  local function IsItemType(itemType, want)
    if itemType == want then return true end
    if type(itemType) == "number" and Enum and Enum.SpellBookItemType then
      if want == "SPELL" and itemType == Enum.SpellBookItemType.Spell then return true end
      if want == "FLYOUT" and itemType == Enum.SpellBookItemType.Flyout then return true end
    end
    return false
  end

  local function UnpackSpellBookItemInfo(a, b)
    if type(a) == "table" then
      local itemType = a.itemType or a.spellType
      local id
      if IsItemType(itemType, "SPELL") then
        id = a.spellID or a.actionID
      elseif IsItemType(itemType, "FLYOUT") then
        id = a.flyoutID or a.actionID
      else
        id = a.spellID or a.flyoutID or a.actionID
      end
      return itemType, id
    end
    return a, b
  end

  local function GetSkillLineRange(tab)
    if type(tab) == "table" then
      local offset = tab.itemIndexOffset or tab.offset or tab.offSet
      local count = tab.numSpellBookItems or tab.numSlots or tab.numSpells
      if type(offset) == "number" and type(count) == "number" then
        return offset, count
      end
    end
    return nil, nil
  end

  local function GetFlyoutSlots(flyoutID)
    if not flyoutID then return 0 end
    if C_SpellBook and C_SpellBook.GetFlyoutInfo then
      local info = C_SpellBook.GetFlyoutInfo(flyoutID)
      if type(info) == "table" then
        return tonumber(info.numSlots) or tonumber(info.numKnownSlots) or 0
      end
      local _, _, numSlots = C_SpellBook.GetFlyoutInfo(flyoutID)
      return tonumber(numSlots) or 0
    end
    if GetFlyoutInfo then
      local _, _, numSlots = GetFlyoutInfo(flyoutID)
      return tonumber(numSlots) or 0
    end
    return 0
  end

  local function GetFlyoutSpellAt(flyoutID, slotIndex)
    if C_SpellBook and C_SpellBook.GetFlyoutSlotInfo then
      local a, b, c = C_SpellBook.GetFlyoutSlotInfo(flyoutID, slotIndex)
      if type(a) == "table" then
        return a.spellID, a.overrideSpellID, a.isKnown
      end
      return a, b, c
    end
    if GetFlyoutSlotInfo then
      return GetFlyoutSlotInfo(flyoutID, slotIndex)
    end
    return nil, nil, nil
  end

  local GetItemInfo = GetSpellBookItemInfo or (C_SpellBook and C_SpellBook.GetSpellBookItemInfo)
  local function ScanRange(offset, numSlots)
    offset = tonumber(offset) or 0
    numSlots = tonumber(numSlots) or 0
    for i = offset + 1, offset + numSlots do
      local rawA, rawB = GetItemInfo(i, spellBookBank)
      if rawA == nil and spellBookBank ~= spellBookType then
        rawA, rawB = GetItemInfo(i, spellBookType)
      end
      local spellType, spellID = UnpackSpellBookItemInfo(rawA, rawB)
      if IsItemType(spellType, "SPELL") and spellID then
        if type(rawA) == "table" and type(rawA.actionID) == "number" then
          spellActionByID[spellID] = rawA.actionID
        elseif type(i) == "number" then
          spellActionByID[spellID] = i
        end
        ScoreCandidateSpell(spellID)
      elseif IsItemType(spellType, "FLYOUT") and spellID then
        local numFlyoutSlots = GetFlyoutSlots(spellID)
        for s = 1, numFlyoutSlots do
          local flyID, overID, isKnown = GetFlyoutSpellAt(spellID, s)
          if isKnown == nil or isKnown then
            if flyID then
              ScoreCandidateSpell(flyID)
            end
            if overID and overID ~= flyID then
              ScoreCandidateSpell(overID)
            end
          end
        end
      end
    end
  end

  if GetItemInfo and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    for line = 1, numLines do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      local offset, numSlots = GetSkillLineRange(info)
      if offset == nil or numSlots == nil then
        local _, _, tupleOffset, tupleCount = C_SpellBook.GetSpellBookSkillLineInfo(line)
        offset = tupleOffset
        numSlots = tupleCount
      end
      ScanRange(offset, numSlots)
    end
  elseif GetItemInfo and GetNumSpellTabs and GetSpellTabInfo then
    for tab = 1, (GetNumSpellTabs() or 0) do
      local _, _, offset, numSlots = GetSpellTabInfo(tab)
      ScanRange(offset, numSlots)
    end
  end

  if bestID then
    cache[cacheKey] = { spellID = bestID, actionID = bestActionID }
    return bestID, bestActionID
  end
  cache[cacheKey] = false
  return nil, nil
end

---------------------------------------------------------------------------
-- Secure cast update for dungeon row teleport
---------------------------------------------------------------------------
local function UpdateRowSecureCast(row, cache)
  if not row or not row.castBtn then return end
  local state = RightPanel._state
  local mapName, mapID = row.mapName, row.mapID
  local spellID, actionID
  if mapName and mapName ~= "" then
    spellID, actionID = FindPortalSpellForMap(mapName, mapID, cache)
  end
  local unlocked = spellID and IsSpellKnownCompat(spellID)
  local spellName = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or GetSpellInfo(spellID)) or nil

  row.portalSpellID = spellID
  row.portalActionID = actionID
  row.portalSpellName = spellName
  row.portalUnlocked = unlocked and true or false

  if InCombatLockdown and InCombatLockdown() then
    if state then state.pendingSecureUpdate = true end
    return
  end

  local function ClearAllAttrs(btn)
    btn:SetAttribute("type", nil)
    btn:SetAttribute("type1", nil)
    btn:SetAttribute("action", nil)
    btn:SetAttribute("action1", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("spell1", nil)
    btn:SetAttribute("macrotext", nil)
    btn:SetAttribute("macrotext1", nil)
  end

  if unlocked and spellID then
    ClearAllAttrs(row.castBtn)
    row.castBtn:SetAttribute("type", "spell")
    row.castBtn:SetAttribute("type1", "spell")
    row.castBtn:SetAttribute("spell", spellID)
    row.castBtn:SetAttribute("spell1", spellID)
  elseif unlocked and actionID then
    ClearAllAttrs(row.castBtn)
    row.castBtn:SetAttribute("type", "action")
    row.castBtn:SetAttribute("type1", "action")
    row.castBtn:SetAttribute("action", actionID)
    row.castBtn:SetAttribute("action1", actionID)
  elseif unlocked and spellName and spellName ~= "" then
    ClearAllAttrs(row.castBtn)
    local macro = "/dismount [mounted]\n/cast " .. spellName .. "\n/cast " .. tostring(spellID)
    row.castBtn:SetAttribute("type", "macro")
    row.castBtn:SetAttribute("type1", "macro")
    row.castBtn:SetAttribute("macrotext", macro)
    row.castBtn:SetAttribute("macrotext1", macro)
  else
    ClearAllAttrs(row.castBtn)
  end
end

---------------------------------------------------------------------------
-- Tooltip helpers
---------------------------------------------------------------------------
local function ShowAffixTooltip(owner, affixID, levelLabel)
  if not owner or not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if affixID and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
    local name, desc, icon = C_ChallengeMode.GetAffixInfo(affixID)
    if icon and name then
      GameTooltip:AddLine(("|T%d:16:16:0:0|t %s"):format(icon, name), 1, 1, 1)
    else
      GameTooltip:AddLine(name or "Affix", 1, 1, 1)
    end
    if levelLabel then GameTooltip:AddLine(("Activates at +%s"):format(levelLabel), 0.4, 0.9, 0.4) end
    if desc and desc ~= "" then GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true) end
  else
    GameTooltip:AddLine("Affix", 1, 1, 1)
    if levelLabel then GameTooltip:AddLine(("Activates at +%s"):format(levelLabel), 0.4, 0.9, 0.4) end
  end
  GameTooltip:Show()
end

local function ShowDungeonTooltip(owner, mapName, mapID, cache)
  if not owner or not GameTooltip then return end
  local spellID, actionID
  if mapName then
    spellID, actionID = FindPortalSpellForMap(mapName, mapID, cache)
  end
  local spellName = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or GetSpellInfo(spellID)) or nil
  local unlocked = spellID and IsSpellKnownCompat(spellID)

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(mapName or "Dungeon", 1, 1, 1)
  if mapID then GameTooltip:AddLine(("Map ID: %d"):format(mapID), 0.7, 0.7, 0.7) end
  if spellID and unlocked then
    GameTooltip:AddLine(("Portal Ready: %s"):format(spellName or ("Spell " .. spellID)), 0.35, 1.0, 0.45)
    if actionID then
      GameTooltip:AddLine(("Action Slot: %d"):format(actionID), 0.7, 0.85, 1.0)
    end
    GameTooltip:AddLine("Left-click to cast", 0.9, 0.9, 0.9)
  elseif spellID then
    GameTooltip:AddLine(("Portal Found: %s"):format(spellName or ("Spell " .. spellID)), 1.0, 0.82, 0.3)
    GameTooltip:AddLine("Not learned on this character", 1.0, 0.45, 0.45)
  else
    GameTooltip:AddLine("Portal not found in spellbook", 1.0, 0.45, 0.45)
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- M+ Data gathering
---------------------------------------------------------------------------
local function GetPlayerSnapshotKey()
  local guid = UnitGUID and UnitGUID("player") or nil
  if type(guid) == "string" and guid ~= "" then return guid end
  local name = UnitName and UnitName("player") or nil
  local realm = GetRealmName and GetRealmName() or nil
  if type(name) == "string" and name ~= "" then return (name or "") .. "-" .. (realm or "") end
  return nil
end

local function GetCurrentMythicRating()
  local rating = 0
  if C_MythicPlus and C_MythicPlus.GetSeasonBestMythicRatingInfo then
    local info = C_MythicPlus.GetSeasonBestMythicRatingInfo()
    if type(info) == "table" then rating = info.currentSeasonScore or info.rating or 0
    elseif type(info) == "number" then rating = info end
  end
  if (not rating or rating <= 0) and C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local info = C_ChallengeMode.GetOverallDungeonScore()
    if type(info) == "table" then rating = info.currentSeasonScore or info.overallScore or info.dungeonScore or 0
    elseif type(info) == "number" then rating = info end
  end
  return rating or 0
end

local function CoerceRun(tbl, mapID)
  if type(tbl) ~= "table" then return nil end
  local level = tbl.level or tbl.bestLevel or tbl.keystoneLevel or tbl.challengeLevel or tbl.bestRunLevel
  local score = tbl.score or tbl.rating or tbl.overallScore or tbl.currentSeasonScore or tbl.mapScore
  local duration = tbl.bestRunDurationMS or tbl.durationMS or tbl.runDurationMS or tbl.bestDurationMS
  local over = tbl.overTimeMS or tbl.overtimeMS or tbl.overTime or tbl.timeOverMS
  local stars = tbl.numKeystoneUpgrades or tbl.keystoneUpgradeLevels or tbl.numUpgrades or tbl.upgrades

  if not duration and type(tbl.bestRunDurationSec) == "number" then duration = tbl.bestRunDurationSec * 1000 end
  if not duration and type(tbl.durationSec) == "number" then duration = tbl.durationSec * 1000 end
  if not over and type(tbl.overTimeSec) == "number" then over = tbl.overTimeSec * 1000 end

  if type(level) ~= "number" and type(score) ~= "number" and type(duration) ~= "number" then return nil end
  return {
    mapChallengeModeID = mapID or tbl.mapChallengeModeID or tbl.mapID,
    level = type(level) == "number" and math.floor(level + 0.5) or 0,
    score = type(score) == "number" and score or 0,
    bestRunDurationMS = NormalizeDurationMS(duration, "duration"),
    overTimeMS = type(over) == "number" and over or nil,
    stars = type(stars) == "number" and math.max(0, math.min(3, math.floor(stars + 0.5))) or 0,
  }
end

local function ExtractRunsDeep(value, mapID, out, depth)
  if depth <= 0 or type(value) ~= "table" then return end
  local run = CoerceRun(value, mapID)
  if run then out[#out + 1] = run end
  for _, v in pairs(value) do
    if type(v) == "table" then
      local childMapID = v.mapChallengeModeID or v.mapID or mapID
      ExtractRunsDeep(v, childMapID, out, depth - 1)
    end
  end
end

local function MergeBestByMap(runs)
  local byMap = {}
  for _, run in ipairs(runs or {}) do
    if type(run) == "table" then
      local mapID = run.mapChallengeModeID or run.mapID
      local key = mapID or ("idx_" .. tostring(_))
      local cur = byMap[key]
      if not cur or (run.score or 0) > (cur.score or 0) or ((run.score or 0) == (cur.score or 0) and (run.level or 0) > (cur.level or 0)) then
        byMap[key] = run
      end
    end
  end
  local merged = {}
  for _, run in pairs(byMap) do merged[#merged + 1] = run end
  return merged
end

local function CopyRuns(runs)
  if type(runs) ~= "table" then return {} end
  local out = {}
  for i = 1, #runs do
    local r = runs[i]
    if type(r) == "table" then
      local c = {}
      for k, v in pairs(r) do c[k] = v end
      out[#out + 1] = c
    end
  end
  return out
end

local function GatherMythicRuns()
  local runs = {}
  if C_MythicPlus and C_MythicPlus.GetRunHistory then
    local calls = {
      function() return C_MythicPlus.GetRunHistory(false, true) end,
      function() return C_MythicPlus.GetRunHistory(true, true) end,
      function() return C_MythicPlus.GetRunHistory(false, false) end,
      function() return C_MythicPlus.GetRunHistory() end,
    }
    for _, fn in ipairs(calls) do
      local ok, history = pcall(fn)
      if ok and type(history) == "table" and #history > 0 then runs = history; break end
    end
  end

  -- Enrich runs from GetRunHistory with per-map score data (history entries often lack score)
  if #runs > 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable then
    local scoreByMap = {}
    if C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
      local mapTable = C_ChallengeMode.GetMapTable()
      if type(mapTable) == "table" then
        for _, mapID in ipairs(mapTable) do
          local ok, info = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
          if ok and type(info) == "table" then
            local extracted = {}
            ExtractRunsDeep(info, mapID, extracted, 6)
            extracted = MergeBestByMap(extracted)
            if #extracted > 0 and (extracted[1].score or 0) > 0 then
              scoreByMap[mapID] = extracted[1]
            end
          end
        end
      end
    end
    if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
      local mapTable = C_ChallengeMode.GetMapTable()
      if type(mapTable) == "table" then
        for _, mapID in ipairs(mapTable) do
          if not scoreByMap[mapID] then
            local ok, a = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
            if ok and type(a) == "table" then
              local extracted = {}
              ExtractRunsDeep(a, mapID, extracted, 6)
              extracted = MergeBestByMap(extracted)
              if #extracted > 0 and (extracted[1].score or 0) > 0 then
                scoreByMap[mapID] = extracted[1]
              end
            end
          end
        end
      end
    end
    for _, run in ipairs(runs) do
      if type(run) == "table" then
        local mapID = run.mapChallengeModeID or run.mapID
        local enrichment = mapID and scoreByMap[mapID]
        if enrichment and (not run.score or run.score == 0) then
          run.score = enrichment.score
        end
        if enrichment and (not run.level or run.level == 0) and (enrichment.level or 0) > 0 then
          run.level = enrichment.level
        end
        if enrichment and not run.bestRunDurationMS and enrichment.bestRunDurationMS then
          run.bestRunDurationMS = enrichment.bestRunDurationMS
        end
        if enrichment and not run.overTimeMS and enrichment.overTimeMS then
          run.overTimeMS = enrichment.overTimeMS
        end
      end
    end
  end

  if #runs == 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable then
    local mapTable = C_ChallengeMode.GetMapTable()
    if type(mapTable) == "table" then
      for _, mapID in ipairs(mapTable) do
        local row = { mapChallengeModeID = mapID }
        if C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
          local ok, info = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
          if ok and type(info) == "table" then
            local extracted = {}
            ExtractRunsDeep(info, mapID, extracted, 6)
            extracted = MergeBestByMap(extracted)
            if #extracted > 0 then
              row.score = extracted[1].score or 0
              row.level = extracted[1].level or 0
              row.bestRunDurationMS = extracted[1].bestRunDurationMS
              row.overTimeMS = extracted[1].overTimeMS
            end
          end
        end
        if (row.score and row.score > 0) or (row.level and row.level > 0) then
          runs[#runs + 1] = row
        end
      end
    end
  end
  return runs
end

local function GetSeasonMapIDs()
  if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return {} end
  local ok, mapTable = pcall(C_ChallengeMode.GetMapTable)
  if not ok or type(mapTable) ~= "table" then return {} end
  local ids, seen = {}, {}
  for _, mapID in ipairs(mapTable) do
    if type(mapID) == "number" and mapID > 0 and not seen[mapID] then
      seen[mapID] = true
      ids[#ids + 1] = mapID
    end
  end
  return ids
end

local function BuildDisplayRuns(runs)
  local copied = CopyRuns(runs)
  local seasonMapIDs = GetSeasonMapIDs()
  if #seasonMapIDs == 0 then return copied end

  local byMap = {}
  for _, run in ipairs(copied) do
    if type(run) == "table" then
      local mapID = run.mapChallengeModeID or run.mapID
      if type(mapID) == "number" and mapID > 0 and not byMap[mapID] then
        byMap[mapID] = run
      end
    end
  end

  local out = {}
  for idx, mapID in ipairs(seasonMapIDs) do
    local run = byMap[mapID]
    if run then run._seasonIndex = idx; out[#out + 1] = run
    else out[#out + 1] = { mapChallengeModeID = mapID, _seasonIndex = idx } end
  end
  return out
end

local function GetRunDeltaMS(run)
  if not run then return nil end
  if type(run.overTimeMS) == "number" then return run.overTimeMS end
  if type(run.overTime) == "number" then
    return math.abs(run.overTime) > 10000 and run.overTime or (run.overTime * 1000)
  end
  if type(run.bestRunDurationMS) == "number" and type(run.parTimeMS) == "number" then
    return run.bestRunDurationMS - run.parTimeMS
  end
  return nil
end

---------------------------------------------------------------------------
-- Vault helpers
---------------------------------------------------------------------------
local function NormalizeVaultTrackType(actType)
  local t = ToNumber(actType)
  if not t then return nil end
  if t == WEEKLY_REWARD_TYPE.Activities then return 2 end
  if t == WEEKLY_REWARD_TYPE.Raid then return 1 end
  if t == WEEKLY_REWARD_TYPE.World then return 3 end
  if t == WEEKLY_REWARD_TYPE.RankedPvP then return 3 end
  if t == 2 then return 2 end
  if t == 1 then return 1 end
  if t == 3 or t == 4 then return 3 end
  return nil
end

local function IsVaultPvP(act)
  if type(act) ~= "table" then return false end
  local t = ToNumber(act.type)
  if not t then return false end
  return t == WEEKLY_REWARD_TYPE.RankedPvP or (WEEKLY_REWARD_TYPE.RankedPvP == 4 and t == 4)
end

local function GetVaultTrackLabel(trackType, act)
  if trackType == 3 and IsVaultPvP(act) then return "PvP" end
  return VAULT_TRACK_NAMES[trackType] or "Vault"
end

local function GetVaultThreshold(trackType, col, act)
  if type(act) == "table" then
    local threshold = ToNumber(act.threshold) or ToNumber(act.requiredProgress)
    if threshold and threshold > 0 then return math.floor(threshold + 0.5) end
  end
  local fb = VAULT_THRESHOLDS[trackType]
  return (fb and fb[col]) or 0
end

local function GetVaultProgress(act)
  if type(act) ~= "table" then return 0 end
  return ToNumber(act.progress) or ToNumber(act.completedActivities) or ToNumber(act.currentProgress) or 0
end

local function GetVaultRewards(act)
  if type(act) ~= "table" or type(act.rewards) ~= "table" then return {} end
  return act.rewards
end

local function GetVaultItemLevel(act)
  if type(act) ~= "table" then return nil end
  local direct = ToNumber(act.itemLevel) or ToNumber(act.rewardItemLevel) or ToNumber(act.rewardLevel) or ToNumber(act.ilvl)
  if direct and direct > 100 then return math.floor(direct + 0.5) end

  local function IlvlFromHyperlink(hyperlink)
    if type(hyperlink) ~= "string" or hyperlink == "" then return nil end
    local ilvl
    if C_Item and C_Item.GetDetailedItemLevelInfo then
      local ok2, n = pcall(C_Item.GetDetailedItemLevelInfo, hyperlink)
      if ok2 then ilvl = ToNumber(n) end
    end
    if (not ilvl or ilvl <= 0) and GetDetailedItemLevelInfo then
      local ok2, n = pcall(GetDetailedItemLevelInfo, hyperlink)
      if ok2 then ilvl = ToNumber(n) end
    end
    if (not ilvl or ilvl <= 0) and GetItemInfo then
      local ok2, _, _, _, itemLevel = pcall(GetItemInfo, hyperlink)
      if ok2 then ilvl = ToNumber(itemLevel) end
    end
    if ilvl and ilvl > 100 then return math.floor(ilvl + 0.5) end
    return nil
  end

  if C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink then
    for _, reward in ipairs(GetVaultRewards(act)) do
      local itemDBID = reward and reward.itemDBID
      if itemDBID then
        local ok, hyperlink = pcall(C_WeeklyRewards.GetItemHyperlink, itemDBID)
        if ok then
          local ilvl = IlvlFromHyperlink(hyperlink)
          if ilvl then return ilvl end
        end
      end
    end
  end

  if C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks and act.id then
    local ok, hyperlink = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, act.id)
    if ok then
      local ilvl = IlvlFromHyperlink(hyperlink)
      if ilvl then return ilvl end
    end
  end

  return nil
end

local function GetVaultDifficultyLabel(trackType, act)
  if type(act) ~= "table" then return "" end
  if trackType == 1 then
    local diff = ToNumber(act.difficultyID) or ToNumber(act.difficulty) or ToNumber(act.level)
    if diff and DifficultyUtil and DifficultyUtil.GetDifficultyName then
      local name = DifficultyUtil.GetDifficultyName(diff)
      if type(name) == "string" and name ~= "" then return name end
    end
    local map = { [17] = "LFR", [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }
    if diff and map[diff] then return map[diff] end
    return ""
  elseif trackType == 2 then
    if C_WeeklyRewards and C_WeeklyRewards.GetDifficultyIDForActivityTier and act.activityTierID and DifficultyUtil and DifficultyUtil.ID then
      local ok, difficultyID = pcall(C_WeeklyRewards.GetDifficultyIDForActivityTier, act.activityTierID)
      if ok and difficultyID == DifficultyUtil.ID.DungeonHeroic then
        return "Heroic"
      end
    end
    local lvl = ToNumber(act.level) or ToNumber(act.keystoneLevel) or ToNumber(act.bestLevel) or ToNumber(act.bestRunLevel) or ToNumber(act.challengeLevel)
    if lvl and lvl > 0 then return ("+%d"):format(math.floor(lvl + 0.5)) end
    return ""
  elseif trackType == 3 then
    if IsVaultPvP(act) and PVPUtil and PVPUtil.GetTierName then
      local pvpTier = ToNumber(act.level)
      if pvpTier and pvpTier > 0 then
        local tierName = PVPUtil.GetTierName(pvpTier)
        if type(tierName) == "string" and tierName ~= "" then return tierName end
      end
    end
    local tier = ToNumber(act.level) or ToNumber(act.tier) or ToNumber(act.tierID) or ToNumber(act.difficulty) or ToNumber(act.difficultyID)
    if tier and tier > 0 then return ("Tier %d"):format(math.floor(tier + 0.5)) end
    return ""
  end
  return ""
end

local function GetWeeklyVaultActivities()
  local acts = {}
  if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return acts end
  local ok, t = pcall(C_WeeklyRewards.GetActivities)
  if ok and type(t) == "table" and #t > 0 then return t end
  local seenByID = {}
  for _, rewardType in ipairs({ WEEKLY_REWARD_TYPE.Activities, WEEKLY_REWARD_TYPE.Raid, WEEKLY_REWARD_TYPE.World, WEEKLY_REWARD_TYPE.RankedPvP }) do
    local okType, entries = pcall(C_WeeklyRewards.GetActivities, rewardType)
    if okType and type(entries) == "table" then
      for _, act in ipairs(entries) do
        local id = act and act.id
        if id then
          if not seenByID[id] then seenByID[id] = true; acts[#acts + 1] = act end
        else
          acts[#acts + 1] = act
        end
      end
    end
  end
  return acts
end

---------------------------------------------------------------------------
-- Frame creation
---------------------------------------------------------------------------
function RightPanel:MarkDirty(reason)
  local state = EnsureState(self)
  state.dirtyReason = tostring(reason or "dirty")
end

function RightPanel:_StopTicker()
  local state = EnsureState(self)
  if state.ticker and type(state.ticker) == "table" and state.ticker.Cancel then state.ticker:Cancel() end
  state.ticker = nil
  state.tickerToken = (state.tickerToken or 0) + 1
end

function RightPanel:_StartTicker()
  local state = EnsureState(self)
  if not IsRefactorEnabled() then self:_StopTicker(); return end
  if not (state.root and state.root:IsShown()) then self:_StopTicker(); return end
  if state.ticker then return end
  state.counters.tickerStarts = (state.counters.tickerStarts or 0) + 1

  if C_Timer and C_Timer.NewTicker then
    state.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
      local live = EnsureState(self)
      if not IsRefactorEnabled() or not (live.root and live.root:IsShown()) then self:_StopTicker(); return end
      live.counters.tickerTicks = (live.counters.tickerTicks or 0) + 1
      self:RequestUpdate("ticker")
    end)
  end
end

function RightPanel:Create()
  if not IsRefactorEnabled() then return nil end
  local state = EnsureState(self)
  if not CharacterFrame then return nil end

  if state.created and state.root then return state.root end

  local Skin = EnsureSkin()

  -- Floating frame parented to CharacterFrame, anchored to its right
  local f = CreateFrame("Frame", nil, CharacterFrame, "BackdropTemplate")
  f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  f:SetPoint("LEFT", CharacterFrame, "RIGHT", 0, -12)
  f:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  f:SetBackdropColor(0, 0, 0, 0)
  f:SetBackdropBorderColor(0, 0, 0, 0)
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 80)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function()
    if InCombatLockdown and InCombatLockdown() then return end
    f:StartMoving()
  end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local db = NS and NS.GetDB and NS:GetDB() or nil
    local cs = db and db.charsheet or nil
    if cs then
      local point, _, _, x, y = f:GetPoint(1)
      if point then
        cs.rightPanelAnchor = point
        cs.rightPanelX = math.floor((x or 0) + 0.5)
        cs.rightPanelY = math.floor((y or 0) + 0.5)
      end
    end
  end)

  -- Restore saved position
  local db = NS and NS.GetDB and NS:GetDB() or nil
  local cs = db and db.charsheet or nil
  if cs and cs.rightPanelAnchor and cs.rightPanelX and cs.rightPanelY
     and (cs.rightPanelX ~= 0 or cs.rightPanelY ~= 0) then
    f:ClearAllPoints()
    f:SetPoint(cs.rightPanelAnchor, UIParent, cs.rightPanelAnchor,
               cs.rightPanelX, cs.rightPanelY)
  end

  -- Black-to-purple vertical gradient background
  f.bgGradient = f:CreateTexture(nil, "BACKGROUND")
  f.bgGradient:SetAllPoints()
  f.bgGradient:SetTexture("Interface/Buttons/WHITE8x8")
  if Skin and Skin.SetVerticalGradient then
    Skin.SetVerticalGradient(f.bgGradient, 0, 0, 0, 0.90, 0.08, 0.02, 0.12, 0.90)
  else
    f.bgGradient:SetColorTexture(0.04, 0.01, 0.06, 0.90)
  end

  state.root = f

  -- Header: keystone name (top-left)
  f.headerTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.headerTitle:SetPoint("TOPLEFT", 12, -8)
  f.headerTitle:SetText("No active key")
  ApplyFont(f.headerTitle, 13)

  -- M+ Rating: title + large value (centered)
  f.mplusTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.mplusTitle:SetPoint("TOP", f, "TOP", 0, -58)
  f.mplusTitle:SetText("Mythic+ Rating")
  ApplyFont(f.mplusTitle, 14)

  f.mplusValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.mplusValue:SetPoint("TOP", f.mplusTitle, "BOTTOM", 0, -2)
  f.mplusValue:SetTextColor(1, 0.5, 0.1, 1)
  f.mplusValue:SetText("0")
  ApplyFont(f.mplusValue, 20)

  -- Affix bar: 4 slots (top-right)
  f.affixBar = CreateFrame("Frame", nil, f)
  f.affixBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
  f.affixBar:SetSize(220, 40)
  state.affixSlots = {}

  for i = 1, 4 do
    local slot = CreateFrame("Frame", nil, f.affixBar, "BackdropTemplate")
    slot:SetSize(38, 38)
    slot:SetPoint("TOPRIGHT", f.affixBar, "TOPRIGHT", -((4 - i) * 54), 0)
    slot:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    slot:SetBackdropColor(0.02, 0.02, 0.03, 0.95)
    local bc = AFFIX_BORDER_COLORS[i]
    slot:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.icon:SetTexture(134400)

    slot.level = f.affixBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slot.level:SetPoint("TOP", slot, "BOTTOM", 0, -1)
    slot.level:SetText(AFFIX_LEVEL_LABELS[i])
    slot.levelLabel = AFFIX_LEVEL_LABELS[i]
    ApplyFont(slot.level, 11)

    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(slotFrame)
      ShowAffixTooltip(slotFrame, slotFrame.affixID, slotFrame.levelLabel)
    end)
    slot:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)

    state.affixSlots[i] = slot
  end

  -- Dungeon table header
  f.tableHeader = CreateFrame("Frame", nil, f)
  f.tableHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -106)
  f.tableHeader:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -106)
  f.tableHeader:SetHeight(26)

  local function HeaderCol(parent, text, anchor, xOff, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint(anchor, xOff, 0)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    fs:SetText(text)
    ApplyFont(fs, 12)
    return fs
  end
  HeaderCol(f.tableHeader, "Dungeon", "LEFT", 10, 340, "CENTER")
  HeaderCol(f.tableHeader, "Level", "RIGHT", -245, 64, "RIGHT")
  HeaderCol(f.tableHeader, "Rating", "RIGHT", -170, 64, "CENTER")
  local bestHeader = HeaderCol(f.tableHeader, "Best", "RIGHT", -10, 180, "RIGHT")
  bestHeader:SetMaxLines(1)
  if bestHeader.SetWordWrap then bestHeader:SetWordWrap(false) end

  -- Dungeon rows
  f.rowContainer = CreateFrame("Frame", nil, f)
  f.rowContainer:SetPoint("TOPLEFT", f.tableHeader, "BOTTOMLEFT", 0, -2)
  f.rowContainer:SetPoint("TOPRIGHT", f.tableHeader, "BOTTOMRIGHT", 0, -2)
  f.rowContainer:SetHeight(NUM_DUNGEON_ROWS * ROW_SPACING)
  state.dungeonRows = {}

  for i = 1, NUM_DUNGEON_ROWS do
    local row = CreateFrame("Frame", nil, f.rowContainer, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_SPACING))
    row:SetPoint("TOPRIGHT", 0, -((i - 1) * ROW_SPACING))
    row:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local a = ((i % 2) == 0) and 0.30 or 0.18
    row:SetBackdropColor(0.02, 0.03, 0.05, a)
    row:SetBackdropBorderColor(0.12, 0.16, 0.22, 0.5)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetTexture(134400)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetText(("Dungeon %d"):format(i))
    ApplyFont(row.name, 13)

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.level:SetPoint("RIGHT", -245, 0)
    row.level:SetWidth(64)
    row.level:SetJustifyH("RIGHT")
    row.level:SetText("-")
    ApplyFont(row.level, 13)

    row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.rating:SetPoint("RIGHT", -170, 0)
    row.rating:SetWidth(64)
    row.rating:SetJustifyH("CENTER")
    row.rating:SetText("-")
    ApplyFont(row.rating, 13)

    row.best = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.best:SetPoint("RIGHT", -10, 0)
    row.best:SetWidth(180)
    row.best:SetJustifyH("RIGHT")
    row.best:SetMaxLines(1)
    if row.best.SetWordWrap then row.best:SetWordWrap(false) end
    row.best:SetText("-")
    ApplyFont(row.best, 13)

    -- SecureActionButton overlay for dungeon teleport
    row.castBtn = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    row.castBtn:SetAllPoints(true)
    row.castBtn:SetFrameStrata(row:GetFrameStrata())
    row.castBtn:SetFrameLevel(row:GetFrameLevel() + 40)
    row.castBtn:EnableMouse(true)
    row.castBtn:RegisterForClicks("LeftButtonUp")
    row.castBtn:SetAttribute("useOnKeyDown", false)
    row.castBtn:SetAttribute("type", nil)
    row.castBtn:SetAttribute("type1", nil)
    row.castBtn:SetAttribute("spell", nil)
    row.castBtn:SetAttribute("spell1", nil)

    do
      local rowRef = row
      local portalCache = state.portalCache
      row.castBtn:SetScript("OnEnter", function(btnFrame)
        ShowDungeonTooltip(btnFrame, rowRef.mapName, rowRef.mapID, portalCache)
      end)
      row.castBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end

    row:EnableMouse(false)
    state.dungeonRows[i] = row
  end

  -- Great Vault title
  f.vaultTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.vaultTitle:SetPoint("BOTTOM", f, "BOTTOM", 0, 172)
  f.vaultTitle:SetText("Great Vault")
  ApplyFont(f.vaultTitle, 14)

  -- Vault container: 9 cards in 3x3 grid
  f.vault = CreateFrame("Frame", nil, f)
  f.vault:SetSize(606, 144)
  f.vault:SetPoint("BOTTOM", f, "BOTTOM", 0, 20)
  state.vaultCards = {}

  for i = 1, 9 do
    local card = CreateFrame("Frame", nil, f.vault, "BackdropTemplate")
    card:SetSize(198, 44)
    local col = (i - 1) % 3
    local vRow = math.floor((i - 1) / 3)
    card:SetPoint("TOPLEFT", col * 204, -(vRow * 50))
    card:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    card:SetBackdropColor(0.08, 0.03, 0.14, 0.72)
    card:SetBackdropBorderColor(0.22, 0.16, 0.28, 0.85)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.title:SetPoint("TOPLEFT", 7, -6)
    card.title:SetJustifyH("LEFT")
    card.title:SetText("Vault")
    ApplyFont(card.title, 12)

    card.ilvl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.ilvl:SetPoint("TOPRIGHT", -7, -6)
    card.ilvl:SetJustifyH("RIGHT")
    card.ilvl:SetText("")
    ApplyFont(card.ilvl, 12)

    card.difficulty = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.difficulty:SetPoint("BOTTOMLEFT", 7, 6)
    card.difficulty:SetJustifyH("LEFT")
    card.difficulty:SetText("")
    ApplyFont(card.difficulty, 11)

    card.progress = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.progress:SetPoint("BOTTOMRIGHT", -7, 6)
    card.progress:SetJustifyH("RIGHT")
    card.progress:SetText("0 / 0")
    ApplyFont(card.progress, 11)

    -- Lock overlay for incomplete slots
    card.overlay = CreateFrame("Frame", nil, card)
    card.overlay:SetAllPoints(true)
    card.overlay:SetFrameLevel(card:GetFrameLevel() + 20)
    card.overlay:EnableMouse(false)

    card.dim = card.overlay:CreateTexture(nil, "BACKGROUND")
    card.dim:SetAllPoints(true)
    card.dim:SetColorTexture(0, 0, 0, 0.65)

    card.lock = card.overlay:CreateTexture(nil, "ARTWORK")
    card.lock:SetSize(24, 24)
    card.lock:SetPoint("CENTER", 0, 0)
    card.lock:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
    if not card.lock:GetTexture() then
      card.lock:SetTexture("Interface\\Common\\LockIcon")
    end
    card.lock:SetDesaturated(true)
    card.lock:SetVertexColor(0.95, 0.95, 0.95, 1)
    card.overlay:Show()

    state.vaultCards[i] = card
  end

  -- Show/hide hooks on root
  f:HookScript("OnShow", function()
    if not IsRefactorEnabled() then return end
    self:_StartTicker()
    if state.dirtyReason then self:RequestUpdate(state.dirtyReason) end
  end)
  f:HookScript("OnHide", function()
    self:_StopTicker()
  end)

  f:Hide()
  state.created = true
  state.counters.creates = (state.counters.creates or 0) + 1
  return f
end

---------------------------------------------------------------------------
-- Update: refresh header, affixes, dungeon rows, vault cards
---------------------------------------------------------------------------
function RightPanel:UpdateRightPanel()
  if not IsRefactorEnabled() then return false end
  local state = EnsureState(self)
  if not state.created or not state.root then return false end

  local f = state.root
  local snapshotKey = GetPlayerSnapshotKey()
  local snap = state.lastSnapshot
  local sameOwner = (snapshotKey ~= nil and snap.ownerKey == snapshotKey)
  if snapshotKey and not sameOwner then
    snap.ownerKey = snapshotKey
    snap.affixIDs = nil
    snap.runs = nil
  end

  if C_MythicPlus and C_MythicPlus.RequestMapInfo then
    pcall(C_MythicPlus.RequestMapInfo)
  end

  -- Header: current keystone
  local currentRunText = "No active key"
  if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or nil
    if mapID and mapID > 0 then
      local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
      currentRunText = ("%s (%s)"):format(name or ("Map " .. mapID), level and ("+" .. level) or "?")
    end
  end
  f.headerTitle:SetText(currentRunText)

  -- M+ Rating
  local rating = GetCurrentMythicRating()
  f.mplusValue:SetText(("%d"):format(math.floor((rating or 0) + 0.5)))

  -- Affix slots
  local affixIDs = {}
  if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
    local affixes = C_MythicPlus.GetCurrentAffixes()
    if type(affixes) == "table" then
      for _, entry in ipairs(affixes) do
        local affixID = type(entry) == "table" and (entry.id or entry.affixID or entry.keystoneAffixID) or entry
        if type(affixID) == "number" then affixIDs[#affixIDs + 1] = affixID end
      end
    end
  end
  if #affixIDs == 0 and sameOwner and type(snap.affixIDs) == "table" and #snap.affixIDs > 0 then
    affixIDs = snap.affixIDs
  elseif #affixIDs > 0 then
    snap.affixIDs = affixIDs
  end

  for i, slot in ipairs(state.affixSlots) do
    local affixID = affixIDs[i]
    slot.affixID = affixID
    if affixID and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
      local _, _, icon = C_ChallengeMode.GetAffixInfo(affixID)
      slot.icon:SetTexture(icon or 134400)
    else
      slot.icon:SetTexture(134400)
    end
    slot:Show()
    slot.level:Show()
  end

  -- Dungeon rows
  local runs = GatherMythicRuns()
  -- Normalize: extract and merge
  if #runs > 0 then
    local extracted = {}
    for _, r in ipairs(runs) do
      if type(r) == "table" then
        ExtractRunsDeep(r, r.mapChallengeModeID or r.mapID, extracted, 4)
      end
    end
    runs = #extracted > 0 and MergeBestByMap(extracted) or MergeBestByMap(runs)
  end
  -- Snapshot cache
  if #runs == 0 and sameOwner and type(snap.runs) == "table" and #snap.runs > 0 then
    runs = CopyRuns(snap.runs)
  elseif #runs > 0 then
    snap.runs = CopyRuns(runs)
  end

  local displayRuns = BuildDisplayRuns(runs)
  table.sort(displayRuns, function(a, b)
    local as = a and (a.score or 0) or 0
    local bs = b and (b.score or 0) or 0
    local al = a and (a.level or 0) or 0
    local bl = b and (b.level or 0) or 0
    local aComplete = (as > 0) or (al > 0)
    local bComplete = (bs > 0) or (bl > 0)

    if aComplete ~= bComplete then
      return aComplete
    end
    if aComplete and bComplete then
      if as ~= bs then
        return as > bs
      end
      if al ~= bl then
        return al > bl
      end
    end

    local ai = a and a._seasonIndex or math.huge
    local bi = b and b._seasonIndex or math.huge
    if ai ~= bi then
      return ai < bi
    end
    return (a and (a.mapChallengeModeID or a.mapID) or math.huge) < (b and (b.mapChallengeModeID or b.mapID) or math.huge)
  end)

  for i, row in ipairs(state.dungeonRows) do
    local run = displayRuns[i]
    if run then
      local mapID = run.mapChallengeModeID or run.mapID
      local name = (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and mapID) and C_ChallengeMode.GetMapUIInfo(mapID) or ("Dungeon " .. i)
      row.name:SetText(name)
      row.mapID = mapID
      row.mapName = name
      row.icon:SetTexture(GetDungeonMapIcon(mapID))
      UpdateRowSecureCast(row, state.portalCache)

      local level = run.level or 0
      local score = run.score or 0
      local stars = run.stars or run.numKeystoneUpgrades or 0
      local bestMS = run.bestRunDurationMS or run.durationMS
      local parMS = run.parTimeMS or GetDungeonTimeLimitMS(mapID)

      -- Compute stars from timing if not provided
      if (not stars or stars <= 0) and type(bestMS) == "number" and type(parMS) == "number" and parMS > 0 then
        if bestMS > parMS then stars = 0
        else
          local pct = (parMS - bestMS) / parMS
          stars = pct >= 0.40 and 3 or pct >= 0.20 and 2 or 1
        end
      end

      if level > 0 then
        local st = StarText(stars)
        row.level:SetText(st ~= "" and ("%s +%d"):format(st, level) or ("+%d"):format(level))
      else
        row.level:SetText("-")
      end

      row.rating:SetText(score > 0 and tostring(math.floor(score + 0.5)) or "-")
      row.rating:SetTextColor(score > 0 and 1 or 0.85, score > 0 and 0.55 or 0.85, score > 0 and 0.2 or 0.85, 1)

      local best = FormatMS(bestMS)
      local deltaMS = GetRunDeltaMS(run)
      if not deltaMS and type(bestMS) == "number" and type(parMS) == "number" and parMS > 0 then
        deltaMS = bestMS - parMS
      end
      if deltaMS and best ~= "-" then
        local absText = FormatMS(math.abs(deltaMS))
        if deltaMS <= 0 then
          row.best:SetText(best .. " |cff33ff99(-" .. absText .. ")|r")
        else
          row.best:SetText(best .. " |cffff6666(+" .. absText .. ")|r")
        end
      else
        row.best:SetText(best)
      end
      row.best:SetTextColor(0.95, 0.95, 0.95, 1)
    else
      row.name:SetText(("Dungeon %d"):format(i))
      row.mapID = nil
      row.mapName = nil
      row.icon:SetTexture(134400)
      UpdateRowSecureCast(row, state.portalCache)
      row.level:SetText("-")
      row.rating:SetText("-")
      row.rating:SetTextColor(0.9, 0.9, 0.9, 1)
      row.best:SetText("-")
      row.best:SetTextColor(0.9, 0.9, 0.9, 1)
    end
  end

  -- Vault cards
  local acts = GetWeeklyVaultActivities()
  local byType = { [1] = {}, [2] = {}, [3] = {} }
  for _, act in ipairs(acts) do
    local trackType = NormalizeVaultTrackType(act and act.type)
    if trackType and byType[trackType] then
      byType[trackType][#byType[trackType] + 1] = act
    end
  end
  for _, list in pairs(byType) do
    table.sort(list, function(a, b)
      local ai = ToNumber(a and a.index) or math.huge
      local bi = ToNumber(b and b.index) or math.huge
      if ai ~= bi then return ai < bi end
      return (ToNumber(a and a.threshold) or math.huge) < (ToNumber(b and b.threshold) or math.huge)
    end)
  end

  for i, card in ipairs(state.vaultCards) do
    local col = ((i - 1) % 3) + 1
    local vRow = math.floor((i - 1) / 3) + 1
    local trackType = VAULT_TRACK_TYPE_BY_ROW[vRow] or 2
    local actList = byType[trackType] or {}
    local act = actList[col]

    local c = VAULT_TRACK_COLORS[trackType] or VAULT_TRACK_COLORS[2]
    card:SetBackdropColor(c[1], c[2], c[3], c[4])
    card:SetBackdropBorderColor(c[5], c[6], c[7], c[8])

    local label = GetVaultTrackLabel(trackType, act)
    local target = GetVaultThreshold(trackType, col, act)
    local progress = GetVaultProgress(act)
    local progressDisplay = target > 0 and math.min(math.max(progress, 0), target) or progress
    local rewards = GetVaultRewards(act)
    local complete = #rewards > 0 or (target > 0 and progress >= target)

    card.title:SetText(label)
    if target > 0 then
      card.progress:SetText(("%d / %d"):format(progressDisplay, target))
    elseif progress > 0 then
      card.progress:SetText(("%d"):format(progress))
    else
      card.progress:SetText("-")
    end

    local ilvl = GetVaultItemLevel(act)
    card.ilvl:SetText(ilvl and tostring(ilvl) or "")
    card.difficulty:SetText(GetVaultDifficultyLabel(trackType, act))

    -- Item level styling for completed slots
    card.ilvl:ClearAllPoints()
    if complete and ilvl and ilvl > 0 then
      card.ilvl:SetPoint("CENTER", card, "CENTER", 0, 0)
      card.ilvl:SetJustifyH("CENTER")
      card.ilvl:SetTextColor(VAULT_UNLOCKED_ILVL_COLOR[1], VAULT_UNLOCKED_ILVL_COLOR[2], VAULT_UNLOCKED_ILVL_COLOR[3], VAULT_UNLOCKED_ILVL_COLOR[4])
      ApplyFont(card.ilvl, 18)
    else
      card.ilvl:SetPoint("TOPRIGHT", card, "TOPRIGHT", -7, -6)
      card.ilvl:SetJustifyH("RIGHT")
      card.ilvl:SetTextColor(0.95, 0.95, 0.95, 1)
      ApplyFont(card.ilvl, 12)
    end

    if complete then
      card.title:SetTextColor(0.35, 1, 0.5, 1)
      card.difficulty:SetTextColor(0.35, 1, 0.5, 1)
      card.progress:SetTextColor(0.35, 1, 0.5, 1)
      if card.overlay then card.overlay:Hide() end
    else
      card.title:SetTextColor(0.95, 0.95, 0.95, 1)
      card.ilvl:SetTextColor(0.95, 0.95, 0.95, 1)
      card.difficulty:SetTextColor(0.95, 0.95, 0.95, 1)
      card.progress:SetTextColor(0.95, 0.95, 0.95, 1)
      if card.overlay then card.overlay:Show() end
    end
  end

  state.dirtyReason = nil
  state.counters.updatesApplied = (state.counters.updatesApplied or 0) + 1
  return true
end

---------------------------------------------------------------------------
-- Request update with throttle
---------------------------------------------------------------------------
function RightPanel:RequestUpdate(reason)
  if not IsRefactorEnabled() then return false end
  local state = EnsureState(self)
  if not state.created then self:Create() end

  local visible = state.root and state.root:IsShown()
  if not visible then self:MarkDirty(reason); return true end

  state.counters.updateRequests = (state.counters.updateRequests or 0) + 1

  local function doUpdate()
    self:UpdateRightPanel()
  end
  local function runLocked()
    local guards = CS and CS.Guards or nil
    if guards and guards.WithLock then
      guards:WithLock("right_panel_update_lock", doUpdate)
    else
      doUpdate()
    end
  end

  local guards = CS and CS.Guards or nil
  if guards and guards.Throttle then
    guards:Throttle("right_panel_update", THROTTLE_INTERVAL, runLocked)
  elseif C_Timer and C_Timer.After then
    C_Timer.After(0, runLocked)
  else
    runLocked()
  end
  return true
end

---------------------------------------------------------------------------
-- CharacterFrame integration
---------------------------------------------------------------------------
function RightPanel:_TryHookCharacterFrame()
  local state = EnsureState(self)
  if state.characterHookInstalled then return end
  if not (CharacterFrame and CharacterFrame.HookScript) then return end

  CharacterFrame:HookScript("OnShow", function()
    if not IsRefactorEnabled() then return end
    -- In account transfer builds, defer to avoid synchronous insecure work
    -- during CharacterFrame:Show() inside the panel-manager secure chain.
    if IsAccountTransferBuild() and C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if not IsRefactorEnabled() then return end
        if not (CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()) then return end
        if IsNativeCurrencyMode() then return end
        self:Create()
        if ApplyPreferredVisibility(state) then
          self:RequestUpdate("CharacterFrame.OnShow.deferred")
          self:_StartTicker()
        else
          self:MarkDirty("CharacterFrame.OnShow.deferred.hidden")
          self:_StopTicker()
        end
      end)
      return
    end
    self:Create()
    if ApplyPreferredVisibility(state) then
      self:RequestUpdate("CharacterFrame.OnShow")
      self:_StartTicker()
    else
      self:MarkDirty("CharacterFrame.OnShow.hidden")
      self:_StopTicker()
    end
  end)

  CharacterFrame:HookScript("OnHide", function()
    if state.root then state.root:Hide() end
    self:_StopTicker()
  end)

  state.characterHookInstalled = true
end

function RightPanel:_EnsureHooks()
  local state = EnsureState(self)
  if state.hooksInstalled then self:_TryHookCharacterFrame(); return end
  state.hooksInstalled = true
  self:_TryHookCharacterFrame()

end

-- Called by Layout's consolidated ToggleCharacter hook.
function RightPanel:_OnToggleCharacter()
  if not IsRefactorEnabled() then return end
  self:_TryHookCharacterFrame()
  if IsAccountTransferBuild() and IsNativeCurrencyMode() then return end
  self:Create()
  if CharacterFrame and CharacterFrame:IsShown() then
    local state = EnsureState(self)
    if ApplyPreferredVisibility(state) then
      self:RequestUpdate("ToggleCharacter")
      self:_StartTicker()
    else
      self:MarkDirty("ToggleCharacter.hidden")
      self:_StopTicker()
    end
  end
end

function RightPanel:_EnsureEventFrame()
  local state = EnsureState(self)
  if state.eventFrame then return end

  state.eventFrame = CreateFrame("Frame")
  state.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  state.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  state.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  state.eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
  state.eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
  state.eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
  state.eventFrame:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED")
  state.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  state.eventFrame:SetScript("OnEvent", function(_, event)
    if not IsRefactorEnabled() then return end
    if event == "CHALLENGE_MODE_COMPLETED" and C_MythicPlus and C_MythicPlus.RequestMapInfo then
      pcall(C_MythicPlus.RequestMapInfo)
    end
    -- Flush pending secure attribute updates after leaving combat
    if event == "PLAYER_REGEN_ENABLED" and state.pendingSecureUpdate and state.dungeonRows then
      if not (InCombatLockdown and InCombatLockdown()) then
        state.pendingSecureUpdate = false
        for _, row in ipairs(state.dungeonRows) do
          UpdateRowSecureCast(row, state.portalCache)
        end
      end
    end
    self:MarkDirty("event:" .. tostring(event))
    if state.root and state.root:IsShown() then
      self:RequestUpdate("event:" .. tostring(event))
    end
  end)
end

---------------------------------------------------------------------------
-- Coordinator integration
---------------------------------------------------------------------------
function RightPanel:_HandleCoordinatorRightPanelFlush(reason)
  local state = EnsureState(self)
  if not IsRefactorEnabled() then
    if state.root then state.root:Hide() end
    self:_StopTicker()
    return
  end
  if IsNativeCurrencyMode() then
    if state.root then state.root:Hide() end
    self:_StopTicker()
    return
  end

  self:_EnsureHooks()
  self:_EnsureEventFrame()
  self:Create()

  if CharacterFrame and CharacterFrame:IsShown() then
    if ApplyPreferredVisibility(state) then
      self:RequestUpdate(reason or "coordinator.rightpanel")
      self:_StartTicker()
    else
      self:MarkDirty(reason or "coordinator.rightpanel.hidden")
      self:_StopTicker()
    end
  else
    self:MarkDirty(reason or "coordinator.rightpanel.hidden")
    if state.root then state.root:Hide() end
    self:_StopTicker()
  end
end

function RightPanel:Update(reason)
  local state = EnsureState(self)
  if not IsRefactorEnabled() then
    if state.root then state.root:Hide() end
    self:_StopTicker()
    return false
  end
  if IsNativeCurrencyMode() then
    if state.root then state.root:Hide() end
    self:_StopTicker()
    return false
  end

  self:_EnsureHooks()
  self:_EnsureEventFrame()
  self:Create()

  if CharacterFrame and CharacterFrame:IsShown() then
    if ApplyPreferredVisibility(state) then
      self:_StartTicker()
      return self:RequestUpdate(reason or "coordinator.rightpanel")
    end
    self:MarkDirty(reason or "coordinator.rightpanel.hidden")
    self:_StopTicker()
    return false
  end

  self:MarkDirty(reason or "coordinator.rightpanel.hidden")
  if state.root then state.root:Hide() end
  self:_StopTicker()
  return false
end

function RightPanel:Refresh()
  return self:UpdateRightPanel()
end

function RightPanel:GetDebugCounters()
  local state = EnsureState(self)
  return {
    creates = state.counters.creates or 0,
    updateRequests = state.counters.updateRequests or 0,
    updatesApplied = state.counters.updatesApplied or 0,
    tickerStarts = state.counters.tickerStarts or 0,
    tickerTicks = state.counters.tickerTicks or 0,
    tickerRunning = state.ticker and true or false,
  }
end

---------------------------------------------------------------------------
-- Register coordinator flush handler
---------------------------------------------------------------------------
local coordinator = CS and CS.Coordinator or nil
if coordinator and coordinator.SetFlushHandler then
  coordinator:SetFlushHandler("rightpanel", function(_, reason)
    RightPanel:_HandleCoordinatorRightPanelFlush(reason)
  end)
end
