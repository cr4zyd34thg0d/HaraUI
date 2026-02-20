local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.MythicPanel = CS.MythicPanel or {}
local MythicPanel = CS.MythicPanel
local SpellScanner = CS.SpellScanner

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
MythicPanel._state = MythicPanel._state or {
  root = nil,
  created = false,
  eventFrame = nil,
  ticker = nil,
  dirtyReason = nil,
  pendingSecureUpdate = false,
  affixSlots = nil,
  dungeonRows = nil,
  vaultCards = nil,
  lastSnapshot = { ownerKey = nil, affixIDs = nil, runs = nil },
  portalCache = {},
}

local function IsNativeCurrencyMode()
  local pm = CS and CS.PaneManager or nil
  return pm ~= nil and pm:IsNativeCurrencyMode()
end

local function IsCharacterPaneActive()
  local pm = CS and CS.PaneManager or nil
  if not pm then return true end
  return pm:IsCharacterPaneActive()
end

local function EnsureState(self)
  local s = self._state
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

local function IsMythicPanelPreferenceEnabled()
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
  local shouldShow = IsMythicPanelPreferenceEnabled() and IsCharacterPaneActive() and charShown == true
  if not root then
    return shouldShow
  else
    if shouldShow then
      if root.Show then root:Show() end
    else
      if root.Hide then root:Hide() end
    end
  end
  -- Notify PortalPanel to re-anchor when M+ panel visibility changes
  local pp = CS and CS.PortalPanel or nil
  if pp and pp.UpdateAnchoring then
    pcall(pp.UpdateAnchoring, pp)
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

local STAR_ATLAS = {
  [1] = "Professions-Icon-Quality-Tier1-Small",
  [2] = "Professions-Icon-Quality-Tier2-Small",
  [3] = "Professions-Icon-Quality-Tier3-Small",
}

local function StarText(stars)
  stars = tonumber(stars) or 0
  stars = math.max(0, math.min(3, math.floor(stars + 0.5)))
  if stars <= 0 then return "" end
  local atlas = STAR_ATLAS[stars]
  if not atlas then return "" end
  return ("|A:%s:17:17|a"):format(atlas)
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

local function TrySetAtlas(tex, atlas)
  if tex and tex.SetAtlas then
    local ok = pcall(tex.SetAtlas, tex, atlas)
    if ok then return true end
  end
  return false
end

local function GetPortalAliases(mapName, mapID)
  local aliases = {}
  local seen = {}
  local function AddAlias(v)
    v = SpellScanner.NormalizeName(v)
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
  local dest = SpellScanner.NormalizeName(spellName)
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
    local spellName = SpellScanner.NormalizeName(rawName)
    local rawDesc = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)) or ""
    local spellDesc = SpellScanner.NormalizeName(rawDesc)

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

  local GetItemInfo = GetSpellBookItemInfo or (C_SpellBook and C_SpellBook.GetSpellBookItemInfo)
  local function ScanRange(offset, numSlots)
    offset = tonumber(offset) or 0
    numSlots = tonumber(numSlots) or 0
    for i = offset + 1, offset + numSlots do
      local rawA, rawB = GetItemInfo(i, spellBookBank)
      if rawA == nil and spellBookBank ~= spellBookType then
        rawA, rawB = GetItemInfo(i, spellBookType)
      end
      local spellType, spellID = SpellScanner.UnpackSpellBookItemInfo(rawA, rawB)
      if SpellScanner.IsItemType(spellType, "SPELL") and spellID then
        if type(rawA) == "table" and type(rawA.actionID) == "number" then
          spellActionByID[spellID] = rawA.actionID
        elseif type(i) == "number" then
          spellActionByID[spellID] = i
        end
        ScoreCandidateSpell(spellID)
      elseif SpellScanner.IsItemType(spellType, "FLYOUT") and spellID then
        local numFlyoutSlots = SpellScanner.GetFlyoutSlots(spellID)
        for s = 1, numFlyoutSlots do
          local flyID, overID, isKnown = SpellScanner.GetFlyoutSpellAt(spellID, s)
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
      local offset, numSlots = SpellScanner.GetSkillLineRange(info)
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
  local state = MythicPanel._state
  local mapName, mapID = row.mapName, row.mapID
  local spellID, actionID
  if mapName and mapName ~= "" then
    spellID, actionID = FindPortalSpellForMap(mapName, mapID, cache)
  end
  local unlocked = spellID and SpellScanner.IsSpellKnownCompat(spellID)
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
  local unlocked = spellID and SpellScanner.IsSpellKnownCompat(spellID)

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

local function GetVaultSlotDescription(trackType, threshold)
  threshold = threshold or 0
  if trackType == 1 then
    return threshold == 1 and "Defeat 1 Raid Boss"
      or ("Defeat %d Raid Bosses"):format(threshold)
  elseif trackType == 2 then
    return threshold == 1
      and "Complete 1 Heroic, Mythic, or Timewalking Dungeon"
      or ("Complete %d Heroic, Mythic, or Timewalking Dungeons"):format(threshold)
  elseif trackType == 3 then
    return threshold == 1
      and "Complete 1 Delve or World Activity"
      or ("Complete %d Delves or World Activities"):format(threshold)
  end
  return ""
end

---------------------------------------------------------------------------
-- Frame creation
---------------------------------------------------------------------------
function MythicPanel:MarkDirty(reason)
  local state = EnsureState(self)
  state.dirtyReason = tostring(reason or "dirty")
end

function MythicPanel:_StopTicker()
  local state = EnsureState(self)
  if state.ticker and type(state.ticker) == "table" and state.ticker.Cancel then state.ticker:Cancel() end
  state.ticker = nil
end

function MythicPanel:_StartTicker()
  local state = EnsureState(self)
  if not (state.root and state.root:IsShown()) then self:_StopTicker(); return end
  if state.ticker then return end
  if C_Timer and C_Timer.NewTicker then
    state.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
      local live = EnsureState(self)
      if not (live.root and live.root:IsShown()) then self:_StopTicker(); return end
      self:RequestUpdate("ticker")
    end)
  end
end

function MythicPanel:Create()
  local state = EnsureState(self)
  if not CharacterFrame then return nil end

  if state.created and state.root then return state.root end

  local Skin = EnsureSkin()

  -- Floating frame parented to CharacterFrame, anchored to its right
  local f = CreateFrame("Frame", nil, CS._characterOverlay or CharacterFrame, "BackdropTemplate")
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
  f.mplusTitle:SetPoint("TOP", f, "TOP", 0, -12)
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
  f.tableHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -66)
  f.tableHeader:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -66)
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
  HeaderCol(f.tableHeader, "Level", "RIGHT", -245, 64, "CENTER")
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

  -- Great Vault: 3x3 grid, Blizzard-style vault slots
  f.vault = CreateFrame("Frame", nil, f)
  f.vault:SetSize(612, 228)
  f.vault:SetPoint("TOP", f.rowContainer, "BOTTOM", 0, -9)
  state.vaultCards = {}

  local VAULT_CARD_W = 200
  local VAULT_CARD_H = 72
  local VAULT_COL_SPACING = 206
  local VAULT_ROW_SPACING = 78

  for i = 1, 9 do
    local card = CreateFrame("Frame", nil, f.vault, "BackdropTemplate")
    card:SetSize(VAULT_CARD_W, VAULT_CARD_H)
    local col = (i - 1) % 3
    local vRow = math.floor((i - 1) / 3)
    card:SetPoint("TOPLEFT", col * VAULT_COL_SPACING, -(vRow * VAULT_ROW_SPACING))
    card:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    card:SetBackdropColor(0.12, 0.12, 0.14, 0.88)
    card:SetBackdropBorderColor(0.40, 0.40, 0.42, 0.85)

    -- Description text (top, multi-line wrapping like Blizzard vault)
    card.desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.desc:SetPoint("TOPLEFT", 6, -5)
    card.desc:SetPoint("TOPRIGHT", -6, -5)
    card.desc:SetJustifyH("LEFT")
    card.desc:SetJustifyV("TOP")
    if card.desc.SetWordWrap then card.desc:SetWordWrap(true) end
    card.desc:SetMaxLines(3)
    card.desc:SetText("")
    card.desc:SetTextColor(0.80, 0.80, 0.80, 1)
    ApplyFont(card.desc, 9)

    -- Green checkmark (top-left, shown when completed)
    card.check = card:CreateTexture(nil, "OVERLAY")
    card.check:SetSize(14, 14)
    card.check:SetPoint("TOPLEFT", 4, -4)
    if not TrySetAtlas(card.check, "common-icon-checkmark") then
      card.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    end
    card.check:SetVertexColor(0.2, 0.9, 0.3, 1)
    card.check:Hide()

    -- Blizzard vault background (locked / unlocked atlas)
    card.vaultBg = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.vaultBg:SetAllPoints()
    card.vaultBg:SetAlpha(0.45)
    TrySetAtlas(card.vaultBg, "evergreen-weeklyrewards-reward-unlocked")
    card.vaultBg:Hide()

    -- Lock icon (bottom-left, Blizzard Great Vault ornate shield)
    card.lock = card:CreateTexture(nil, "ARTWORK")
    card.lock:SetSize(42, 42)
    card.lock:SetPoint("BOTTOMLEFT", 2, 2)
    if not TrySetAtlas(card.lock, "greatVault-centerPlate-dis") then
      TrySetAtlas(card.lock, "evergreen-weeklyrewards-reward-locked")
    end
    card.lock:SetVertexColor(0.75, 0.75, 0.78, 0.9)

    -- Blizzard-style back-glow (shown when completed, breathing pulse)
    card.glow = card:CreateTexture(nil, "ARTWORK", nil, 2)
    card.glow:SetAllPoints()
    if not TrySetAtlas(card.glow, "evergreen-weeklyrewards-reward-fx-backglow") then
      card.glow:SetTexture("Interface\\Cooldown\\star4")
    end
    card.glow:SetVertexColor(0.95, 0.75, 0.15, 0.5)
    card.glow:SetBlendMode("ADD")
    card.glow:Hide()

    card.glowAG = card.glow:CreateAnimationGroup()
    card.glowAG:SetLooping("REPEAT")
    local fadeOut = card.glowAG:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.55)
    fadeOut:SetDuration(1.2)
    fadeOut:SetOrder(1)
    fadeOut:SetSmoothing("IN_OUT")
    local fadeIn = card.glowAG:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.55)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(1.2)
    fadeIn:SetOrder(2)
    fadeIn:SetSmoothing("IN_OUT")

    -- Rotating swirl effect inside the glow
    card.swirl = card:CreateTexture(nil, "ARTWORK", nil, 3)
    card.swirl:SetSize(VAULT_CARD_H * 0.9, VAULT_CARD_H * 0.9)
    card.swirl:SetPoint("CENTER", 0, 0)
    TrySetAtlas(card.swirl, "evergreen-weeklyrewards-reward-unlocked-fx-swirl")
    card.swirl:SetVertexColor(0.95, 0.75, 0.15, 0.35)
    card.swirl:SetBlendMode("ADD")
    card.swirl:Hide()

    card.swirlAG = card.swirl:CreateAnimationGroup()
    card.swirlAG:SetLooping("REPEAT")
    local spin = card.swirlAG:CreateAnimation("Rotation")
    spin:SetDegrees(-360)
    spin:SetDuration(8)
    spin:SetOrder(1)
    spin:SetOrigin("CENTER", 0, 0)

    -- Sparkle overlay (pulsing star on top of swirl)
    card.sparkle = card:CreateTexture(nil, "ARTWORK", nil, 4)
    card.sparkle:SetSize(VAULT_CARD_H * 0.55, VAULT_CARD_H * 0.55)
    card.sparkle:SetPoint("CENTER", 0, 0)
    TrySetAtlas(card.sparkle, "evergreen-weeklyrewards-reward-unlocked-fx-sparkle01")
    card.sparkle:SetBlendMode("ADD")
    card.sparkle:SetVertexColor(1, 0.85, 0.3, 0.6)
    card.sparkle:Hide()

    card.sparkleAG = card.sparkle:CreateAnimationGroup()
    card.sparkleAG:SetLooping("REPEAT")
    local spkOut = card.sparkleAG:CreateAnimation("Alpha")
    spkOut:SetFromAlpha(1)
    spkOut:SetToAlpha(0.3)
    spkOut:SetDuration(0.8)
    spkOut:SetOrder(1)
    spkOut:SetSmoothing("IN_OUT")
    local spkIn = card.sparkleAG:CreateAnimation("Alpha")
    spkIn:SetFromAlpha(0.3)
    spkIn:SetToAlpha(1)
    spkIn:SetDuration(0.8)
    spkIn:SetOrder(2)
    spkIn:SetSmoothing("IN_OUT")

    -- Enable mouse for reward tooltip on completed cards
    card:EnableMouse(true)
    card.actInfo = nil  -- populated on update
    card:SetScript("OnEnter", function(self)
      if not self.actInfo or not self.actComplete then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -7, -11)
      GameTooltip:ClearLines()
      GameTooltip:AddLine("Current Reward", 1, 1, 1)
      local actID = self.actInfo.id
      local itemLink, upgradeItemLink
      if actID and C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
        local ok, link, upLink = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, actID)
        if ok then itemLink, upgradeItemLink = link, upLink end
      end
      local itemLevel
      if itemLink and C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok2, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok2 then itemLevel = ilvl end
      end
      if itemLevel then
        local diffLabel = self.actDiffLabel or ""
        if diffLabel ~= "" then
          GameTooltip:AddLine(("Item Level %d - %s"):format(itemLevel, diffLabel), 1, 0.82, 0, true)
        else
          GameTooltip:AddLine(("Item Level %d"):format(itemLevel), 1, 0.82, 0, true)
        end
        local upgradeLevel
        if upgradeItemLink and C_Item and C_Item.GetDetailedItemLevelInfo then
          local ok3, uIlvl = pcall(C_Item.GetDetailedItemLevelInfo, upgradeItemLink)
          if ok3 then upgradeLevel = uIlvl end
        end
        if upgradeLevel then
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(("Improve to Item Level %d"):format(upgradeLevel), 0.2, 0.9, 0.2)
        else
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine("Reward at Highest Item Level", 0.2, 0.9, 0.2)
        end
      else
        GameTooltip:AddLine("Retrieving item information...", 0.7, 0.7, 0.7)
      end
      GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Info text (bottom-right: progress when locked, difficulty when complete)
    card.info = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.info:SetPoint("BOTTOMRIGHT", -6, 5)
    card.info:SetJustifyH("RIGHT")
    card.info:SetText("")
    ApplyFont(card.info, 11)

    state.vaultCards[i] = card
  end

  -- Show/hide hooks on root
  f:HookScript("OnShow", function()
    self:_StartTicker()
    if state.dirtyReason then self:RequestUpdate(state.dirtyReason) end
  end)
  f:HookScript("OnHide", function()
    self:_StopTicker()
  end)

  f:Hide()
  state.created = true
  return f
end

---------------------------------------------------------------------------
-- Update: refresh header, affixes, dungeon rows, vault cards
---------------------------------------------------------------------------
function MythicPanel:UpdateMythicPanel()
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

    local target = GetVaultThreshold(trackType, col, act)
    local progress = GetVaultProgress(act)
    local rewards = GetVaultRewards(act)
    local complete = #rewards > 0 or (target > 0 and progress >= target)
    local desc = GetVaultSlotDescription(trackType, target)

    -- Store activity info for tooltip
    card.actInfo = act
    card.actComplete = complete
    local diffLabel = GetVaultDifficultyLabel(trackType, act)
    card.actDiffLabel = diffLabel ~= "" and diffLabel or nil

    if complete then
      -- Completed: golden border, green description, orb effects, difficulty info
      card:SetBackdropBorderColor(0.78, 0.60, 0.12, 1)
      card:SetBackdropColor(0.16, 0.13, 0.08, 0.90)
      card.vaultBg:Show()
      TrySetAtlas(card.vaultBg, "evergreen-weeklyrewards-reward-unlocked")
      card.vaultBg:SetAlpha(0.45)
      card.desc:SetText(desc)
      card.desc:SetTextColor(0.25, 0.85, 0.25, 1)
      card.desc:ClearAllPoints()
      card.desc:SetPoint("TOPLEFT", 22, -5)
      card.desc:SetPoint("TOPRIGHT", -6, -5)
      card.check:Show()
      card.lock:Hide()
      card.glow:Show()
      card.swirl:Show()
      card.sparkle:Show()
      if not card.glowAG:IsPlaying() then card.glowAG:Play() end
      if not card.swirlAG:IsPlaying() then card.swirlAG:Play() end
      if not card.sparkleAG:IsPlaying() then card.sparkleAG:Play() end
      card.info:SetText(diffLabel)
      card.info:SetTextColor(0.95, 0.75, 0.15, 1)
    else
      -- Incomplete: gray metallic border, Blizzard vault lock, progress counter
      card:SetBackdropBorderColor(0.40, 0.40, 0.42, 0.85)
      card:SetBackdropColor(0.12, 0.12, 0.14, 0.88)
      card.vaultBg:Hide()
      card.desc:SetText(desc)
      card.desc:SetTextColor(0.80, 0.80, 0.80, 1)
      card.desc:ClearAllPoints()
      card.desc:SetPoint("TOPLEFT", 6, -5)
      card.desc:SetPoint("TOPRIGHT", -6, -5)
      card.check:Hide()
      card.lock:Show()
      card.glow:Hide()
      card.swirl:Hide()
      card.sparkle:Hide()
      if card.glowAG:IsPlaying() then card.glowAG:Stop() end
      if card.swirlAG:IsPlaying() then card.swirlAG:Stop() end
      if card.sparkleAG:IsPlaying() then card.sparkleAG:Stop() end
      local progressDisplay = target > 0 and math.min(math.max(progress, 0), target) or progress
      card.info:SetText(target > 0 and ("%d/%d"):format(progressDisplay, target) or "-")
      card.info:SetTextColor(0.70, 0.70, 0.70, 1)
    end
  end

  state.dirtyReason = nil
  return true
end

---------------------------------------------------------------------------
-- Request update with throttle
---------------------------------------------------------------------------
function MythicPanel:RequestUpdate(reason)
  local state = EnsureState(self)
  if not state.created then self:Create() end

  local visible = state.root and state.root:IsShown()
  if not visible then self:MarkDirty(reason); return true end


  local function doUpdate()
    self:UpdateMythicPanel()
  end

  local guards = CS and CS.Guards or nil
  if guards and guards.Throttle then
    guards:Throttle("right_panel_update", THROTTLE_INTERVAL, doUpdate)
  elseif C_Timer and C_Timer.After then
    C_Timer.After(0, doUpdate)
  else
    doUpdate()
  end
  return true
end

---------------------------------------------------------------------------
-- CharacterFrame integration
---------------------------------------------------------------------------
function MythicPanel:OnShow(reason)
  local state = EnsureState(self)
  self:Create()
  if ApplyPreferredVisibility(state) then
    self:RequestUpdate(reason or "CharacterFrame.OnShow")
    self:_StartTicker()
  else
    self:MarkDirty((reason or "CharacterFrame.OnShow") .. ".hidden")
    self:_StopTicker()
  end
end

function MythicPanel:OnHide()
  local state = EnsureState(self)
  if state.root then state.root:Hide() end
  self:_StopTicker()
end


function MythicPanel:_EnsureEventFrame()
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
function MythicPanel:Update(reason)
  if InCombatLockdown and InCombatLockdown() then return false end
  local state = EnsureState(self)
  if IsNativeCurrencyMode() then
    if state.root then state.root:Hide() end
    self:_StopTicker()
    return false
  end

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

function MythicPanel:Refresh()
  return self:UpdateMythicPanel()
end


---------------------------------------------------------------------------
-- Register coordinator flush handler
---------------------------------------------------------------------------
