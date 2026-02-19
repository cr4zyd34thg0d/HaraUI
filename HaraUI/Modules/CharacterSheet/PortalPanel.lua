local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.PortalPanel = CS.PortalPanel or {}
local PortalPanel = CS.PortalPanel

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local PANEL_WIDTH = 360
local PANEL_HEIGHT = 620
local ROW_HEIGHT = 28
local ROW_SPACING = 30
local CARD_PADDING = 12
local CARD_TITLE_HEIGHT = 24
local CARD_GAP = 10

-- Quick-access grid constants
local GRID_COLS = 4
local GRID_ROWS = 2
local GRID_CELL_SIZE = 40   -- 2x the 20px spell icons in the portal list
local GRID_CELL_GAP = 4
local GRID_WIDTH  = (GRID_CELL_SIZE * GRID_COLS) + (GRID_CELL_GAP * (GRID_COLS - 1))
local GRID_HEIGHT = (GRID_CELL_SIZE * GRID_ROWS) + (GRID_CELL_GAP * (GRID_ROWS - 1))

---------------------------------------------------------------------------
-- Module state
---------------------------------------------------------------------------
local function EnsureState(self)
  self._state = self._state or {}
  local s = self._state
  if s.created == nil then s.created = false end
  s.portalCache = s.portalCache or {}
  if s.pendingSecureUpdate == nil then s.pendingSecureUpdate = false end
  if s.dirty == nil then s.dirty = false end
  -- Quick-access grid state
  if s.gridCreated == nil then s.gridCreated = false end
  s.gridCells = s.gridCells or {}
  s.selectedSpell = s.selectedSpell or nil  -- { spellID, icon, dest, known }
  if s.pendingGridSecure == nil then s.pendingGridSecure = false end
  return s
end

local function ApplyFont(fs, size)
  if not fs then return end
  if NS and NS.ApplyDefaultFont then
    NS:ApplyDefaultFont(fs, size or 12)
  end
end

local function EnsureSkin()
  return CS and CS.Skin or nil
end

---------------------------------------------------------------------------
-- Portal spell scanner — Hero's Path dungeon teleports by expansion
---------------------------------------------------------------------------
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

local function LooksLikeTravelSpell(spellName, spellDesc)
  local name = NormalizeName(spellName)
  local desc = NormalizeName(spellDesc)
  -- Exclude non-dungeon spells
  if name:find("pathfinder") then return false end
  if name:find("warband bank") or name:find("distance inhibitor") then return false end
  local isTravel = name:find("teleport") or name:find("portal") or name:find("hero s path") or name:find("path of the")
  if name ~= "" and isTravel then
    return true
  end
  if desc ~= "" and (desc:find("teleport") or desc:find("portal") or desc:find("entrance")) then
    return true
  end
  return false
end

local function GetSpellDisplayName(spellID)
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(spellID)
  end
  if GetSpellInfo then
    return GetSpellInfo(spellID)
  end
  return nil
end

local function GetSpellDisplayIcon(spellID)
  if C_Spell and C_Spell.GetSpellTexture then
    return C_Spell.GetSpellTexture(spellID)
  end
  if GetSpellTexture then
    return GetSpellTexture(spellID)
  end
  return 134400
end

local function GetSpellDesc(spellID)
  if C_Spell and C_Spell.GetSpellDescription then
    return C_Spell.GetSpellDescription(spellID) or ""
  end
  return ""
end

--- Extract dungeon name from spell description.
--- Matches patterns like "Teleport to the entrance to The Dawnbreaker."
local function ExtractDestFromDesc(desc)
  if type(desc) ~= "string" or desc == "" then return nil end
  -- "Teleport(s) (you) to the entrance to/of DUNGEON_NAME."
  local dest = desc:match("[Tt]eleport[s]?[%s%a]*the entrance[%s]+[to]+[%s]+(.+)")
  if not dest then
    dest = desc:match("[Tt]eleport[s]?[%s%a]*the entrance[%s]+of[%s]+(.+)")
  end
  if not dest then
    dest = desc:match("[Tt]eleport[s]?[%s]+to[%s]+(.+)")
  end
  if dest then
    dest = dest:gsub("[%.!]$", "")
    dest = dest:gsub("^%s+", ""):gsub("%s+$", "")
    if dest ~= "" then return dest end
  end
  return nil
end

---------------------------------------------------------------------------
-- Dungeon lookup: normalized keyword → { display, expansion }
-- Matched against the cleaned spell destination text.
---------------------------------------------------------------------------
local DUNGEON_LOOKUP = {
  -- The War Within
  ["ara kara"]            = { "Ara-Kara, City of Echoes", "The War Within" },
  ["city of threads"]     = { "City of Threads", "The War Within" },
  ["stonevault"]          = { "The Stonevault", "The War Within" },
  ["dawnbreaker"]         = { "The Dawnbreaker", "The War Within" },
  ["cinderbrew"]          = { "Cinderbrew Meadery", "The War Within" },
  ["darkflame"]           = { "Darkflame Cleft", "The War Within" },
  ["priory"]              = { "Priory of the Sacred Flame", "The War Within" },
  ["rookery"]             = { "The Rookery", "The War Within" },
  ["floodgate"]           = { "Operation: Floodgate", "The War Within" },
  ["eco dome"]            = { "Operation: Floodgate", "The War Within" },
  -- Dragonflight
  ["brackenhide"]         = { "Brackenhide Hollow", "Dragonflight" },
  ["algeth ar"]           = { "Algeth'ar Academy", "Dragonflight" },
  ["nokhud"]              = { "The Nokhud Offensive", "Dragonflight" },
  ["azure vault"]         = { "The Azure Vault", "Dragonflight" },
  ["ruby life"]           = { "Ruby Life Pools", "Dragonflight" },
  ["halls of infusion"]   = { "Halls of Infusion", "Dragonflight" },
  ["neltharus"]           = { "Neltharus", "Dragonflight" },
  ["uldaman"]             = { "Uldaman: Legacy of Tyr", "Dragonflight" },
  ["dawn of the infinite"] = { "Dawn of the Infinite", "Dragonflight" },
  ["galakrond"]           = { "Galakrond's Fall", "Dragonflight" },
  ["murozond"]            = { "Murozond's Rise", "Dragonflight" },
  -- Shadowlands
  ["necrotic wake"]       = { "The Necrotic Wake", "Shadowlands" },
  ["tirna scithe"]        = { "Mists of Tirna Scithe", "Shadowlands" },
  ["plaguefall"]          = { "Plaguefall", "Shadowlands" },
  ["halls of atonement"]  = { "Halls of Atonement", "Shadowlands" },
  ["theater of pain"]     = { "Theater of Pain", "Shadowlands" },
  ["de other side"]       = { "De Other Side", "Shadowlands" },
  ["spires of ascension"] = { "Spires of Ascension", "Shadowlands" },
  ["sanguine depths"]     = { "Sanguine Depths", "Shadowlands" },
  ["tazavesh"]            = { "Tazavesh, the Veiled Market", "Shadowlands" },
  -- Battle for Azeroth
  ["siege of boralus"]    = { "Siege of Boralus", "Battle for Azeroth" },
  ["freehold"]            = { "Freehold", "Battle for Azeroth" },
  ["atal dazar"]          = { "Atal'Dazar", "Battle for Azeroth" },
  ["waycrest"]            = { "Waycrest Manor", "Battle for Azeroth" },
  ["heartsbane"]          = { "Waycrest Manor", "Battle for Azeroth" },
  ["motherlode"]          = { "The MOTHERLODE!!", "Battle for Azeroth" },
  ["underrot"]            = { "The Underrot", "Battle for Azeroth" },
  ["temple of sethraliss"] = { "Temple of Sethraliss", "Battle for Azeroth" },
  ["shrine of the storm"] = { "Shrine of the Storm", "Battle for Azeroth" },
  ["kings rest"]          = { "Kings' Rest", "Battle for Azeroth" },
  ["mechagon"]            = { "Operation: Mechagon", "Battle for Azeroth" },
  ["junkyard"]            = { "Mechagon: Junkyard", "Battle for Azeroth" },
  ["workshop"]            = { "Mechagon: Workshop", "Battle for Azeroth" },
  ["ancient horrors"]     = { "Atal'Dazar", "Battle for Azeroth" },
  -- Legion
  ["court of stars"]      = { "Court of Stars", "Legion" },
  ["darkheart thicket"]   = { "Darkheart Thicket", "Legion" },
  ["eye of azshara"]      = { "Eye of Azshara", "Legion" },
  ["halls of valor"]      = { "Halls of Valor", "Legion" },
  ["neltharion"]          = { "Neltharion's Lair", "Legion" },
  ["black rook"]          = { "Black Rook Hold", "Legion" },
  ["karazhan"]            = { "Return to Karazhan", "Legion" },
  ["cathedral"]           = { "Cathedral of Eternal Night", "Legion" },
  ["seat of the triumvirate"] = { "Seat of the Triumvirate", "Legion" },
  -- Warlords of Draenor
  ["iron docks"]          = { "Iron Docks", "Warlords of Draenor" },
  ["grimrail"]            = { "Grimrail Depot", "Warlords of Draenor" },
  ["everbloom"]           = { "The Everbloom", "Warlords of Draenor" },
  ["shadowmoon"]          = { "Shadowmoon Burial Grounds", "Warlords of Draenor" },
  ["auchindoun"]          = { "Auchindoun", "Warlords of Draenor" },
  ["skyreach"]            = { "Skyreach", "Warlords of Draenor" },
  -- Mists of Pandaria
  ["jade serpent"]        = { "Temple of the Jade Serpent", "Mists of Pandaria" },
  ["stormstout"]          = { "Stormstout Brewery", "Mists of Pandaria" },
  ["shado pan"]           = { "Shado-Pan Monastery", "Mists of Pandaria" },
  ["mogu shan"]           = { "Mogu'shan Palace", "Mists of Pandaria" },
  -- Cataclysm
  ["grim batol"]          = { "Grim Batol", "Cataclysm" },
  ["vortex pinnacle"]     = { "The Vortex Pinnacle", "Cataclysm" },
  ["throne of the tides"] = { "Throne of the Tides", "Cataclysm" },
  -- Wrath of the Lich King
  ["utgarde"]             = { "Utgarde Pinnacle", "Wrath of the Lich King" },
  -- Vanilla / Classic
  ["deadmines"]           = { "The Deadmines", "Vanilla" },
}

-- Expansion display order (newest first)
local EXPANSION_ORDER = {
  "The War Within", "Dragonflight", "Shadowlands",
  "Battle for Azeroth", "Legion", "Warlords of Draenor",
  "Mists of Pandaria", "Cataclysm", "Wrath of the Lich King",
  "The Burning Crusade", "Vanilla",
}
local EXPANSION_SORT = {}
for i, name in ipairs(EXPANSION_ORDER) do
  EXPANSION_SORT[name] = i
end

local function StripSpellPrefix(rawName)
  if type(rawName) ~= "string" or rawName == "" then return "" end
  local s = rawName
  s = s:gsub("^[Hh]ero'?s? [Pp]ath%s*:?%s*", "")
  s = s:gsub("^[Pp]ath of the%s+", "")
  s = s:gsub("^[Pp]ath of%s+", "")
  s = s:gsub("^[Tt]eleport%s*:?%s*", "")
  s = s:gsub("^[Pp]ortal%s*:?%s*", "")
  s = s:gsub("^[Tt]o%s+", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

--- Look up a spell's dungeon display name and expansion from DUNGEON_LOOKUP.
--- Returns displayName, expansionName or nil, nil if no match.
local function ResolveDungeonInfo(rawName)
  local stripped = StripSpellPrefix(rawName)
  local normalized = NormalizeName(stripped)
  if normalized == "" then return nil, nil end

  -- Try longest-match first: check if any key is found within the normalized text
  local bestKey, bestLen = nil, 0
  for key, _ in pairs(DUNGEON_LOOKUP) do
    if normalized:find(key, 1, true) and #key > bestLen then
      bestKey = key
      bestLen = #key
    end
  end
  if bestKey then
    local entry = DUNGEON_LOOKUP[bestKey]
    return entry[1], entry[2]
  end
  return nil, nil
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

--- Scan the entire spellbook and return Hero's Path dungeon teleport spells grouped by expansion.
--- Returns: { { name = "The War Within", spells = { {spellID, rawName, dest, icon, known}, ... } }, ... }
local function ScanAllPortalSpells()
  local groups = {}
  local groupByName = {}
  local seen = {}

  local spellBookType = BOOKTYPE_SPELL or "spell"
  local spellBookBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or spellBookType

  local GetItemInfo = GetSpellBookItemInfo or (C_SpellBook and C_SpellBook.GetSpellBookItemInfo)
  if not GetItemInfo then return groups end

  local function ProcessSpell(spellID, tabName)
    if not spellID or seen[spellID] then return end
    seen[spellID] = true

    local rawName = GetSpellDisplayName(spellID)
    if not rawName or rawName == "" then return end

    local desc = GetSpellDesc(spellID)
    if not LooksLikeTravelSpell(rawName, desc) then return end

    -- Try description first ("Teleport to the entrance to X"), then lookup, then prefix strip
    local descDest = ExtractDestFromDesc(desc)
    local displayName, lookupExpansion = ResolveDungeonInfo(descDest or rawName)
    local dest = descDest or displayName or StripSpellPrefix(rawName)
    local expansion = lookupExpansion or tabName or "Other"
    local icon = GetSpellDisplayIcon(spellID)
    local known = IsSpellKnownCompat(spellID)

    if not groupByName[expansion] then
      local group = { name = expansion, spells = {} }
      groupByName[expansion] = group
      groups[#groups + 1] = group
    end
    local spells = groupByName[expansion].spells
    spells[#spells + 1] = {
      spellID = spellID,
      rawName = rawName,
      dest = dest,
      icon = icon or 134400,
      known = known,
    }
  end

  local function ScanRange(offset, numSlots, expansionName)
    offset = tonumber(offset) or 0
    numSlots = tonumber(numSlots) or 0
    for i = offset + 1, offset + numSlots do
      local rawA, rawB = GetItemInfo(i, spellBookBank)
      if rawA == nil and spellBookBank ~= spellBookType then
        rawA, rawB = GetItemInfo(i, spellBookType)
      end
      local spellType, spellID = UnpackSpellBookItemInfo(rawA, rawB)
      if IsItemType(spellType, "SPELL") and spellID then
        ProcessSpell(spellID, expansionName)
      elseif IsItemType(spellType, "FLYOUT") and spellID then
        local numFlyoutSlots = GetFlyoutSlots(spellID)
        for s = 1, numFlyoutSlots do
          local flyID, overID, isKnown = GetFlyoutSpellAt(spellID, s)
          if isKnown == nil or isKnown then
            if flyID then ProcessSpell(flyID, expansionName) end
            if overID and overID ~= flyID then ProcessSpell(overID, expansionName) end
          end
        end
      end
    end
  end

  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    for line = 1, numLines do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      local tabName = info and info.name or ("Tab " .. line)
      local offset, numSlots = GetSkillLineRange(info)
      if offset == nil or numSlots == nil then
        local _, _, tupleOffset, tupleCount = C_SpellBook.GetSpellBookSkillLineInfo(line)
        offset = tupleOffset
        numSlots = tupleCount
      end
      if offset and numSlots then
        ScanRange(offset, numSlots, tabName)
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo then
    for tab = 1, (GetNumSpellTabs() or 0) do
      local tabName, _, offset, numSlots = GetSpellTabInfo(tab)
      tabName = tabName or ("Tab " .. tab)
      ScanRange(offset, numSlots, tabName)
    end
  end

  -- Sort expansions newest-first using known order
  table.sort(groups, function(a, b)
    local ai = EXPANSION_SORT[a.name] or 999
    local bi = EXPANSION_SORT[b.name] or 999
    return ai < bi
  end)

  -- Sort spells within each group alphabetically by destination
  for _, group in ipairs(groups) do
    table.sort(group.spells, function(a, b)
      return (a.dest or "") < (b.dest or "")
    end)
  end

  return groups
end

---------------------------------------------------------------------------
-- Glass card factory (matches Options/Widgets pattern)
---------------------------------------------------------------------------
local function MakeGlassCard(parent, title)
  local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  card:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  card:SetBackdropColor(0, 0, 0, 0.08)
  card:SetBackdropBorderColor(0.58, 0.60, 0.70, 0.22)

  if title and title ~= "" then
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOP", 0, -8)
    card.title:SetText(title)
    card.title:SetTextColor(0.98, 0.64, 0.14, 1)
    ApplyFont(card.title, 13)
  end

  return card
end

---------------------------------------------------------------------------
-- Spell row factory
---------------------------------------------------------------------------
local function CreateSpellRow(parent, index)
  local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  row:SetHeight(ROW_HEIGHT)
  row:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  local a = ((index % 2) == 0) and 0.30 or 0.18
  row:SetBackdropColor(0.02, 0.03, 0.05, a)
  row:SetBackdropBorderColor(0.12, 0.16, 0.22, 0.5)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 8, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.icon:SetTexture(134400)

  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetMaxLines(1)
  if row.label.SetWordWrap then row.label:SetWordWrap(false) end
  ApplyFont(row.label, 13)

  -- Selection glow for drag-to-grid
  row.selectGlow = row:CreateTexture(nil, "OVERLAY")
  row.selectGlow:SetPoint("TOPLEFT", -1, 1)
  row.selectGlow:SetPoint("BOTTOMRIGHT", 1, -1)
  row.selectGlow:SetTexture("Interface/Buttons/WHITE8x8")
  row.selectGlow:SetBlendMode("ADD")
  row.selectGlow:SetVertexColor(0.9, 0.6, 0.1, 0.35)
  row.selectGlow:Hide()

  -- SecureActionButton overlay for spell casting (matches M+ panel pattern)
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

  row:EnableMouse(false)  -- let castBtn handle all mouse events

  return row
end

---------------------------------------------------------------------------
-- Secure cast attribute update (combat-safe)
---------------------------------------------------------------------------
local function ClearAllAttrs(btn)
  btn:SetAttribute("type", nil)
  btn:SetAttribute("type1", nil)
  btn:SetAttribute("spell", nil)
  btn:SetAttribute("spell1", nil)
  btn:SetAttribute("macrotext", nil)
  btn:SetAttribute("macrotext1", nil)
end

local function UpdateSpellRowSecureCast(row, state)
  if not row or not row.castBtn then return end
  local spellID = row.spellID
  local known = row.known

  if InCombatLockdown and InCombatLockdown() then
    if state then state.pendingSecureUpdate = true end
    return
  end

  if known and spellID then
    ClearAllAttrs(row.castBtn)
    row.castBtn:SetAttribute("type", "spell")
    row.castBtn:SetAttribute("type1", "spell")
    row.castBtn:SetAttribute("spell", spellID)
    row.castBtn:SetAttribute("spell1", spellID)
  else
    ClearAllAttrs(row.castBtn)
  end
end

---------------------------------------------------------------------------
-- Preference / persistence helpers (must be above grid code)
---------------------------------------------------------------------------
local function GetCharSheetDB()
  local db = NS and NS.db or nil
  if type(db) ~= "table" then return nil end
  if type(db.charsheet) ~= "table" then
    db.charsheet = {}
  end
  return db.charsheet
end

local function GetPortalGrid()
  local csdb = GetCharSheetDB()
  if type(csdb) ~= "table" then return {} end
  if type(csdb.portalGrid) ~= "table" then
    csdb.portalGrid = {}
  end
  return csdb.portalGrid
end

local function SavePortalGridSlot(index, spellID)
  local grid = GetPortalGrid()
  grid[index] = spellID
end

local function ClearPortalGridSlot(index)
  local grid = GetPortalGrid()
  grid[index] = nil
end

local function IsCharacterPaneActive()
  local pm = CS and CS.PaneManager or nil
  if not pm then return true end
  return pm:IsCharacterPaneActive()
end

---------------------------------------------------------------------------
-- Quick-access grid: 4×4 spell grid on CharacterFrame
---------------------------------------------------------------------------
local function CreateGridCell(parent, index)
  -- Visual container (BackdropTemplate only — no SecureActionButton)
  local cell = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  cell:SetSize(GRID_CELL_SIZE, GRID_CELL_SIZE)
  cell:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  cell:SetBackdropColor(0.02, 0.02, 0.04, 0.75)
  cell:SetBackdropBorderColor(0.22, 0.22, 0.28, 0.70)

  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetPoint("TOPLEFT", 3, -3)
  cell.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  cell.icon:SetTexture(nil)

  cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
  cell.highlight:SetAllPoints()
  cell.highlight:SetTexture("Interface/Buttons/WHITE8x8")
  cell.highlight:SetBlendMode("ADD")
  cell.highlight:SetVertexColor(0.6, 0.5, 0.9, 0.15)

  cell.selectGlow = cell:CreateTexture(nil, "OVERLAY")
  cell.selectGlow:SetPoint("TOPLEFT", -1, 1)
  cell.selectGlow:SetPoint("BOTTOMRIGHT", 1, -1)
  cell.selectGlow:SetTexture("Interface/Buttons/WHITE8x8")
  cell.selectGlow:SetBlendMode("ADD")
  cell.selectGlow:SetVertexColor(0.9, 0.6, 0.1, 0.40)
  cell.selectGlow:Hide()

  cell.gridIndex = index
  cell.assignedSpellID = nil

  -- Secure casting overlay (matches M+ panel / spell row pattern)
  cell.castBtn = CreateFrame("Button", nil, cell, "SecureActionButtonTemplate")
  cell.castBtn:SetAllPoints(true)
  cell.castBtn:SetFrameStrata(cell:GetFrameStrata())
  cell.castBtn:SetFrameLevel(cell:GetFrameLevel() + 40)
  cell.castBtn:EnableMouse(true)
  cell.castBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  cell.castBtn:SetAttribute("useOnKeyDown", false)
  cell.castBtn:SetAttribute("type", nil)
  cell.castBtn:SetAttribute("type1", nil)
  cell.castBtn:SetAttribute("spell", nil)
  cell.castBtn:SetAttribute("spell1", nil)

  -- cell stays mouse-enabled for right-click (slot clear/assign)
  -- castBtn sits on top for left-click secure casting
  cell:EnableMouse(true)

  return cell
end

local function UpdateGridCellSecure(cell, state)
  if not cell or not cell.castBtn then return end
  if InCombatLockdown and InCombatLockdown() then
    if state then state.pendingGridSecure = true end
    return
  end

  local btn = cell.castBtn
  local spellID = cell.assignedSpellID
  if spellID and IsSpellKnownCompat(spellID) then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("spell", spellID)
    btn:SetAttribute("spell1", spellID)
  else
    btn:SetAttribute("type", nil)
    btn:SetAttribute("type1", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("spell1", nil)
  end
end

local function ApplyGridCellVisual(cell)
  local spellID = cell.assignedSpellID
  if spellID then
    local icon = GetSpellDisplayIcon(spellID)
    cell.icon:SetTexture(icon or 134400)
    local known = IsSpellKnownCompat(spellID)
    cell.icon:SetDesaturated(not known)
    if known then
      cell:SetBackdropBorderColor(0.40, 0.30, 0.65, 0.85)
    else
      cell:SetBackdropBorderColor(0.35, 0.20, 0.20, 0.70)
    end
  else
    cell.icon:SetTexture(nil)
    cell:SetBackdropBorderColor(0.22, 0.22, 0.28, 0.70)
  end
end

local function ClearSelectedSpell(state)
  state.selectedSpell = nil
  -- Remove selection glow from all portal list rows
  if state.spellRows then
    for _, row in ipairs(state.spellRows) do
      if row.selectGlow then row.selectGlow:Hide() end
    end
  end
end

local function SetSelectedSpell(state, spellData)
  ClearSelectedSpell(state)
  if spellData then
    state.selectedSpell = {
      spellID = spellData.spellID,
      icon = spellData.icon,
      dest = spellData.dest,
      known = spellData.known,
    }
  end
end

function PortalPanel:CreateQuickAccessGrid()
  local state = EnsureState(self)
  if state.gridCreated and state.gridRoot then return state.gridRoot end
  if not CharacterFrame then return nil end

  local gridFrame = CreateFrame("Frame", nil, CS._characterOverlay or CharacterFrame, "BackdropTemplate")
  gridFrame:SetSize(GRID_WIDTH + 16, GRID_HEIGHT + 32)
  gridFrame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  gridFrame:SetBackdropColor(0, 0, 0, 0)
  gridFrame:SetBackdropBorderColor(0, 0, 0, 0)
  gridFrame:SetFrameStrata("HIGH")
  gridFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 44)
  gridFrame:EnableMouse(true)

  -- No background — panel is invisible, only cells are visible

  -- Title
  gridFrame.title = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gridFrame.title:SetPoint("TOP", gridFrame, "TOP", 0, -5)
  gridFrame.title:SetText("Quick Portals")
  gridFrame.title:SetTextColor(1, 1, 1, 1)
  ApplyFont(gridFrame.title, 10)

  -- Create 4×4 grid cells
  state.gridCells = {}
  for row = 0, GRID_ROWS - 1 do
    for col = 0, GRID_COLS - 1 do
      local idx = row * GRID_COLS + col + 1
      local cell = CreateGridCell(gridFrame, idx)
      local x = 8 + col * (GRID_CELL_SIZE + GRID_CELL_GAP)
      local y = -(20 + row * (GRID_CELL_SIZE + GRID_CELL_GAP))
      cell:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x, y)

      -- PreClick: suppress casting on right-click by clearing attrs
      local cellRef = cell
      cell.castBtn:SetScript("PreClick", function(btnFrame, button)
        if button == "RightButton" then
          if not (InCombatLockdown and InCombatLockdown()) then
            btnFrame:SetAttribute("type", nil)
            btnFrame:SetAttribute("type1", nil)
            btnFrame:SetAttribute("spell", nil)
            btnFrame:SetAttribute("spell1", nil)
          end
        end
        -- Left-click: attrs already set by UpdateGridCellSecure
      end)

      -- PostClick: right-click clears slot, left-click assigns selected spell
      cell.castBtn:SetScript("PostClick", function(btnFrame, button)
        if button == "RightButton" then
          cellRef.assignedSpellID = nil
          ClearPortalGridSlot(idx)
          ApplyGridCellVisual(cellRef)
          UpdateGridCellSecure(cellRef, state)
          ClearSelectedSpell(state)
          return
        end
        -- Left-click: assign selected spell if one is picked
        local sel = state.selectedSpell
        if sel and sel.spellID then
          cellRef.assignedSpellID = sel.spellID
          SavePortalGridSlot(idx, sel.spellID)
          ApplyGridCellVisual(cellRef)
          UpdateGridCellSecure(cellRef, state)
          ClearSelectedSpell(state)
        end
      end)

      -- Tooltip
      cell.castBtn:SetScript("OnEnter", function(btnFrame)
        if not GameTooltip then return end
        GameTooltip:SetOwner(btnFrame, "ANCHOR_RIGHT")
        local sid = cellRef.assignedSpellID
        if sid then
          GameTooltip:SetSpellByID(sid)
          if IsSpellKnownCompat(sid) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click to cast", 0.4, 0.9, 0.4)
          else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Not yet learned", 0.9, 0.3, 0.3)
          end
          GameTooltip:AddLine("Right-click to clear", 0.6, 0.6, 0.6)
        else
          GameTooltip:AddLine("Empty Slot", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("Select a portal from the list,\nthen click here to assign it.", 0.5, 0.5, 0.5, true)
        end
        GameTooltip:Show()
      end)
      cell.castBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)

      state.gridCells[idx] = cell
    end
  end

  state.gridRoot = gridFrame
  state.gridCreated = true

  -- Position: to the right of loot spec buttons, above the tab bar
  gridFrame:ClearAllPoints()
  gridFrame:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 420, 4)

  return gridFrame
end

function PortalPanel:UpdateQuickAccessGrid()
  local state = EnsureState(self)
  if not state.gridCreated or not state.gridRoot then return end

  local grid = GetPortalGrid()
  for i = 1, GRID_ROWS * GRID_COLS do
    local cell = state.gridCells[i]
    if cell then
      local savedID = grid[i]
      cell.assignedSpellID = savedID or nil
      ApplyGridCellVisual(cell)
      UpdateGridCellSecure(cell, state)
    end
  end
end

function PortalPanel:ShowQuickAccessGrid()
  local state = EnsureState(self)
  if not IsCharacterPaneActive() then return end
  if not state.gridCreated then
    self:CreateQuickAccessGrid()
  end
  if state.gridRoot then
    state.gridRoot:Show()
    self:UpdateQuickAccessGrid()
  end
end

function PortalPanel:HideQuickAccessGrid()
  local state = EnsureState(self)
  if state.gridRoot then
    state.gridRoot:Hide()
  end
end

---------------------------------------------------------------------------
-- Panel creation
---------------------------------------------------------------------------
function PortalPanel:Create()
  local state = EnsureState(self)
  if not CharacterFrame then return nil end
  if state.created and state.root then return state.root end

  local Skin = EnsureSkin()

  local f = CreateFrame("Frame", nil, CS._characterOverlay or CharacterFrame, "BackdropTemplate")
  f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  f:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  f:SetBackdropColor(0, 0, 0, 0)
  f:SetBackdropBorderColor(0, 0, 0, 0)
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 82)
  f:EnableMouse(true)

  -- Black-to-purple vertical gradient background (same as RightPanel)
  f.bgGradient = f:CreateTexture(nil, "BACKGROUND")
  f.bgGradient:SetAllPoints()
  f.bgGradient:SetTexture("Interface/Buttons/WHITE8x8")
  if Skin and Skin.SetVerticalGradient then
    Skin.SetVerticalGradient(f.bgGradient, 0, 0, 0, 0.90, 0.08, 0.02, 0.12, 0.90)
  else
    f.bgGradient:SetColorTexture(0.04, 0.01, 0.06, 0.90)
  end

  state.root = f

  -- Header
  f.headerTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.headerTitle:SetPoint("TOP", 0, -5)
  f.headerTitle:SetText("Dungeon Portals")
  ApplyFont(f.headerTitle, 15)
  f.headerTitle:SetTextColor(0.98, 0.64, 0.14, 1)

  f.headerSubtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.headerSubtitle:SetPoint("TOP", f.headerTitle, "BOTTOM", 0, -6)
  f.headerSubtitle:SetText("Right-click to assign to quick panel")
  f.headerSubtitle:SetTextColor(0.75, 0.70, 0.85, 0.95)
  ApplyFont(f.headerSubtitle, 10)

  -- Scroll frame for expansion cards
  f.scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  f.scrollFrame:SetPoint("TOPLEFT", 8, -46)
  f.scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

  f.scrollChild = CreateFrame("Frame", nil, f.scrollFrame)
  f.scrollChild:SetWidth(PANEL_WIDTH - 44)
  f.scrollFrame:SetScrollChild(f.scrollChild)

  -- Style the scrollbar to be less obtrusive
  local scrollBar = f.scrollFrame.ScrollBar or _G[f.scrollFrame:GetName() and (f.scrollFrame:GetName() .. "ScrollBar") or ""]
  if scrollBar and scrollBar.SetAlpha then
    scrollBar:SetAlpha(0.5)
  end

  state.cards = {}
  state.spellRows = {}

  f:Hide()
  state.created = true
  return f
end

---------------------------------------------------------------------------
-- Build / rebuild content from scanned spells
---------------------------------------------------------------------------
local function RebuildContent(state)
  if not state or not state.root then return end
  local f = state.root
  local scrollChild = f.scrollChild
  if not scrollChild then return end

  -- Clear existing content
  if state.cards then
    for _, card in ipairs(state.cards) do
      if card.Hide then card:Hide() end
    end
  end
  if state.spellRows then
    for _, row in ipairs(state.spellRows) do
      if row.Hide then row:Hide() end
    end
  end
  state.cards = {}
  state.spellRows = {}

  local groups = ScanAllPortalSpells()
  if #groups == 0 then
    if not state.emptyLabel then
      state.emptyLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      state.emptyLabel:SetPoint("TOP", 0, -20)
      state.emptyLabel:SetText("No dungeon portals found.\nComplete Mythic+ dungeons to\nunlock Hero's Path teleports.")
      state.emptyLabel:SetTextColor(0.6, 0.6, 0.6, 1)
      ApplyFont(state.emptyLabel, 13)
    end
    state.emptyLabel:Show()
    scrollChild:SetHeight(80)
    return
  end

  if state.emptyLabel then state.emptyLabel:Hide() end

  local yOffset = 0
  local rowIndex = 0

  for _, group in ipairs(groups) do
    local numSpells = #group.spells
    if numSpells > 0 then
      local cardHeight = CARD_TITLE_HEIGHT + (numSpells * ROW_SPACING) + CARD_PADDING
      local card = MakeGlassCard(scrollChild, group.name)
      card:SetPoint("TOPLEFT", 0, -yOffset)
      card:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
      card:SetHeight(cardHeight)
      card:Show()
      state.cards[#state.cards + 1] = card

      for i, spell in ipairs(group.spells) do
        rowIndex = rowIndex + 1
        local row = CreateSpellRow(card, rowIndex)
        row:SetPoint("TOPLEFT", CARD_PADDING, -(CARD_TITLE_HEIGHT + (i - 1) * ROW_SPACING))
        row:SetPoint("RIGHT", card, "RIGHT", -CARD_PADDING, 0)

        row.spellID = spell.spellID
        row.known = spell.known
        row.icon:SetTexture(spell.icon)
        row.label:SetText(spell.dest or spell.rawName or "")

        if spell.known then
          row.icon:SetDesaturated(false)
          row.label:SetTextColor(0.95, 0.95, 0.95, 1)
        else
          row.icon:SetDesaturated(true)
          row.label:SetTextColor(0.45, 0.45, 0.45, 1)
        end

        UpdateSpellRowSecureCast(row, state)

        -- No PreClick/PostClick on castBtn (matches working M+ panel pattern)
        -- castBtn only handles left-click casting via pre-set secure attributes
        do
          local rowRef = row
          local spellData = spell
          -- Tooltip on castBtn (left-click target)
          row.castBtn:SetScript("OnEnter", function(btnFrame)
            if not GameTooltip then return end
            GameTooltip:SetOwner(btnFrame, "ANCHOR_RIGHT")
            if rowRef.spellID then
              GameTooltip:SetSpellByID(rowRef.spellID)
              if rowRef.known then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Left-click to cast", 0.4, 0.9, 0.4)
              else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Not yet learned", 0.9, 0.3, 0.3)
              end
              GameTooltip:AddLine("Right-click to select for grid", 0.6, 0.6, 0.6)
              GameTooltip:Show()
            end
          end)
          row.castBtn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
          end)

          -- Right-click for grid assignment: use castBtn OnMouseUp
          -- (OnMouseUp is NOT a secure handler, so it won't interfere with casting)
          row.castBtn:HookScript("OnMouseUp", function(btnFrame, button)
            if button == "RightButton" then
              SetSelectedSpell(state, spellData)
              if rowRef.selectGlow then rowRef.selectGlow:Show() end
            end
          end)
        end

        row:Show()
        state.spellRows[#state.spellRows + 1] = row
      end

      yOffset = yOffset + cardHeight + CARD_GAP
    end
  end

  scrollChild:SetHeight(math.max(yOffset, 1))
end

---------------------------------------------------------------------------
-- Anchoring: attach to M+ panel if visible, else to CharacterFrame
---------------------------------------------------------------------------
function PortalPanel:UpdateAnchoring()
  local state = EnsureState(self)
  if not state.root then return end

  state.root:ClearAllPoints()

  local rp = CS and CS.RightPanel or nil
  local rpRoot = rp and rp._state and rp._state.root or nil
  local rpVisible = rpRoot and rpRoot.IsShown and rpRoot:IsShown()

  if rpVisible then
    state.root:SetPoint("LEFT", rpRoot, "RIGHT", 0, 0)
  else
    state.root:SetPoint("LEFT", CharacterFrame, "RIGHT", 0, -12)
  end
end

local function IsPortalPanelPreferenceEnabled()
  local csdb = GetCharSheetDB()
  if type(csdb) ~= "table" then return false end
  return csdb.showPortalPanel == true
end

local function ApplyPreferredVisibility(state)
  local root = state and state.root or nil
  local charShown = CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()
  local shouldShow = IsPortalPanelPreferenceEnabled() and IsCharacterPaneActive() and charShown == true
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
-- Update: rescan spells and rebuild content
---------------------------------------------------------------------------
function PortalPanel:UpdatePortalPanel()
  local state = EnsureState(self)
  if not state.created or not state.root then return false end

  RebuildContent(state)
  self:UpdateAnchoring()
  return true
end

function PortalPanel:RequestUpdate(reason)
  local state = EnsureState(self)
  if not state.created then self:Create() end

  local visible = state.root and state.root:IsShown()
  if not visible then
    state.dirty = true
    return true
  end

  self:UpdatePortalPanel()
  return true
end

function PortalPanel:MarkDirty(reason)
  local state = EnsureState(self)
  state.dirty = true
end

---------------------------------------------------------------------------
-- CharacterFrame integration (called by Coordinator)
---------------------------------------------------------------------------
function PortalPanel:OnShow(reason)
  local state = EnsureState(self)
  self:Create()
  self:ShowQuickAccessGrid()
  if ApplyPreferredVisibility(state) then
    self:RequestUpdate(reason or "CharacterFrame.OnShow")
  else
    state.dirty = true
  end
end

function PortalPanel:OnHide()
  local state = EnsureState(self)
  if state.root then state.root:Hide() end
  self:HideQuickAccessGrid()
  ClearSelectedSpell(state)
end

---------------------------------------------------------------------------
-- Event frame: re-scan on spell changes, flush secure attrs after combat
---------------------------------------------------------------------------
function PortalPanel:_EnsureEventFrame()
  local state = EnsureState(self)
  if state.eventFrame then return end

  state.eventFrame = CreateFrame("Frame")
  state.eventFrame:RegisterEvent("SPELLS_CHANGED")
  state.eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
  state.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  state.eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
      if not (InCombatLockdown and InCombatLockdown()) then
        if state.pendingSecureUpdate and state.spellRows then
          state.pendingSecureUpdate = false
          for _, row in ipairs(state.spellRows) do
            UpdateSpellRowSecureCast(row, state)
          end
        end
        if state.pendingGridSecure and state.gridCells then
          state.pendingGridSecure = false
          for _, cell in ipairs(state.gridCells) do
            UpdateGridCellSecure(cell, state)
          end
        end
      end
    end

    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
      state.dirty = true
      if state.root and state.root:IsShown() then
        self:RequestUpdate("event:" .. tostring(event))
      end
      -- Refresh grid visuals (spell known status may have changed)
      self:UpdateQuickAccessGrid()
    end
  end)
end

---------------------------------------------------------------------------
-- Coordinator integration
---------------------------------------------------------------------------
function PortalPanel:Update(reason)
  local state = EnsureState(self)

  self:_EnsureEventFrame()
  self:Create()

  if CharacterFrame and CharacterFrame:IsShown() then
    self:ShowQuickAccessGrid()
    if ApplyPreferredVisibility(state) then
      self:RequestUpdate(reason or "coordinator.portalpanel")
    else
      state.dirty = true
    end
  else
    state.dirty = true
    if state.root then state.root:Hide() end
    self:HideQuickAccessGrid()
  end
  return true
end
