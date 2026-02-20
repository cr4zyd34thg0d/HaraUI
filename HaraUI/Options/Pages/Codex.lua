local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

local TX = "Interface\\AddOns\\HaraUI\\Media\\HaraUI_Codex\\"

-- Fixed color constants (not theme-dependent)
local COL_PURPLE  = { 0.42, 0.29, 0.55 }
local COL_LAVLIVE = { 0.72, 0.60, 0.92 }
local COL_DIMTEXT = { 0.38, 0.30, 0.52 }

-- Glyph watermark themes for the Codex pages
local GLYPH_THEMES = {
  none = {},
  necromancer = {
    left  = { expand = 0,  base = "glyph_skull", crackle = { "glyph_skull_crackle1",  "glyph_skull_crackle2",  "glyph_skull_crackle3"  } },
    right = { expand = 30,  base = "glyph_demon",  crackle = { "glyph_demon_crackle1",  "glyph_demon_crackle2",  "glyph_demon_crackle3"  } },
  },
  arcane = {
    left  = { expand = 80, base = "glyph_arcane", crackle = { "glyph_arcane_crackle1", "glyph_arcane_crackle2", "glyph_arcane_crackle3" } },
    right = { expand = 80, base = "glyph_fire",   crackle = { "glyph_fire_crackle1",   "glyph_fire_crackle2",   "glyph_fire_crackle3"   } },
  },
  faction = {
    left  = { expand = 0, base = "glyph_horde",    crackle = { "glyph_horde_crackle1",    "glyph_horde_crackle2",    "glyph_horde_crackle3"    } },
    right = { expand = 0, base = "glyph_alliance", crackle = { "glyph_alliance_crackle1", "glyph_alliance_crackle2", "glyph_alliance_crackle3" } },
  },
}

-- Module definitions — ordered left-page (6) then right-page (5).
-- dbKey/special must match the existing SavedVariables structure exactly.
local CODEX_MODS = {
  -- Left page (slots 1–6) — DARK BINDINGS
  { name = "XP / Rep Bar",    dbKey = "xpbar",         rune = "rune_xp",       settingsKey = "xp"       },
  { name = "Cast Bar",        dbKey = "castbar",        rune = "rune_cast",     settingsKey = "cast"     },
  { name = "Loot Toasts",     dbKey = "loot",           rune = "rune_loot",     settingsKey = "loot"     },
  { name = "Minimap Bar",     dbKey = "minimapbar",     rune = "rune_minimap",  settingsKey = "minimap"  },
  { name = "Alt Panel",       dbKey = "altpanel",       rune = "rune_altpanel"  },
  { name = "Char Sheet",      dbKey = "charsheet",      rune = "rune_charsheet" },
  -- Right page (slots 7–11) — FORBIDDEN RITES
  { name = "Game Menu",       dbKey = "gamemenu",       rune = "rune_menu"      },
  { name = "Skin Bars",       special = "tbs",          rune = "rune_skinbars"  },
  { name = "Auto Summons",    dbKey = "summons",        rune = "rune_summons"   },
  { name = "Rotation Helper", dbKey = "rotationhelper", rune = "rune_rotation", settingsKey = "rotation" },
  { name = "Friendly Plates", dbKey = "friendlyplates", rune = "rune_plates",   settingsKey = "friendly" },
}

-- ============================================================
-- BuildCodexPanel
--   parent  = cards.general.content (660 × 424 px content frame)
--   db      = HaraUI SavedVariables profile table
--   NS      = addon namespace (for ApplyAll)
--   ORANGE  = live theme color table { r, g, b }
--   RegisterTheme  = Theme.RegisterTheme
--   ApplyUIFont    = Theme.ApplyUIFont
--   UpdateNavIndicators = function to refresh nav button state
-- ============================================================
function NS.OptionsPages.BuildCodexPanel(parent, db, NS, ORANGE, RegisterTheme, ApplyUIFont, UpdateNavIndicators)

  -- ── Layout constants ──────────────────────────────────────────────────────
  local LEFT_COUNT = 6           -- entries on the left page
  local CODEX_W    = 660         -- content frame width (window 720 - 36 card margin - 24 inset)
  local SPINE_W    = 24
  local PAGE_W     = math.floor((CODEX_W - SPINE_W) / 2)  -- 323
  local ROW_H      = 38          -- entry row height
  local CHAIN_PAD  = 14          -- vertical space taken by the chain at the top
  local HDR_H      = 20          -- combined page-header text + divider height
  local RUNE_SZ    = 36          -- rendered rune icon size (px)
  local RUNE_PAD   = 5           -- px from page left edge to rune frame left
  local ACCENT_W   = 3
  local BAR_W      = 38
  local BAR_H      = 4
  local FOOTER_H   = 22
  local ENTRY_Y0   = -(CHAIN_PAD + HDR_H + 2)  -- Y of first entry row, relative to page top


  -- ── Codex container ───────────────────────────────────────────────────────
  local codex = CreateFrame("Frame", nil, parent)
  codex:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, -94)
  codex:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0,   0)

  -- ── Book backdrop + ambient glow ──────────────────────────────────────────
  local bookBg = codex:CreateTexture(nil, "BACKGROUND")
  bookBg:SetAllPoints(true)
  bookBg:SetTexture(TX .. "book_backdrop.tga")
  bookBg:SetVertexColor(0.10, 0.05, 0.16, 0.82)

  local aura = codex:CreateTexture(nil, "BACKGROUND", nil, -1)
  aura:SetAllPoints(true)
  aura:SetTexture(TX .. "aura_glow.tga")
  aura:SetVertexColor(0.16, 0.05, 0.28, 0.20)

  -- ── Burned edges ──────────────────────────────────────────────────────────
  local burnTop = codex:CreateTexture(nil, "OVERLAY", nil, 1)
  burnTop:SetPoint("TOPLEFT",  codex, "TOPLEFT",  0, 0)
  burnTop:SetPoint("TOPRIGHT", codex, "TOPRIGHT", 0, 0)
  burnTop:SetHeight(10)
  burnTop:SetTexture(TX .. "burned_edge_top.tga")

  local burnBot = codex:CreateTexture(nil, "OVERLAY", nil, 1)
  burnBot:SetPoint("BOTTOMLEFT",  codex, "BOTTOMLEFT",  0, 0)
  burnBot:SetPoint("BOTTOMRIGHT", codex, "BOTTOMRIGHT", 0, 0)
  burnBot:SetHeight(10)
  burnBot:SetTexture(TX .. "burned_edge_bottom.tga")

  -- ── Chain across the top ──────────────────────────────────────────────────
  local chain = codex:CreateTexture(nil, "ARTWORK")
  chain:SetPoint("TOPLEFT",  codex, "TOPLEFT",  0, -2)
  chain:SetPoint("TOPRIGHT", codex, "TOPRIGHT", 0, -2)
  chain:SetHeight(8)
  chain:SetTexture(TX .. "chain_tile.tga")
  chain:SetHorizTile(true)

  local capL = codex:CreateTexture(nil, "ARTWORK", nil, 1)
  capL:SetSize(14, 14)
  capL:SetPoint("LEFT", codex, "LEFT", -1, -2)
  capL:SetTexture(TX .. "chain_cap.tga")

  local capR = codex:CreateTexture(nil, "ARTWORK", nil, 1)
  capR:SetSize(14, 14)
  capR:SetPoint("RIGHT", codex, "RIGHT", 1, -2)
  capR:SetTexture(TX .. "chain_cap.tga")

  -- ── Spine ─────────────────────────────────────────────────────────────────
  local spineFrame = CreateFrame("Frame", nil, codex)
  spineFrame:SetWidth(SPINE_W)
  spineFrame:SetPoint("TOP",    codex, "TOP",    0, -CHAIN_PAD + 7)
  spineFrame:SetPoint("BOTTOM", codex, "BOTTOM", 0,  FOOTER_H + 11)
  spineFrame:EnableMouse(false)

  local spineBG = spineFrame:CreateTexture(nil, "BACKGROUND")
  spineBG:SetAllPoints(spineFrame)
  spineBG:SetTexture(TX .. "spine_bg.tga")

  local ornamentTop = spineFrame:CreateTexture(nil, "ARTWORK")
  ornamentTop:SetSize(32, 32)
  ornamentTop:SetPoint("TOP", spineFrame, "TOP", 0, -12)
  ornamentTop:SetTexture(TX .. "spine_ornament_top.tga")

  local ornamentMid = spineFrame:CreateTexture(nil, "ARTWORK")
  ornamentMid:SetSize(32, 48)
  ornamentMid:SetPoint("CENTER", spineFrame, "CENTER", 0, 0)
  ornamentMid:SetTexture(TX .. "spine_ornament_mid.tga")

  local ornamentBot = spineFrame:CreateTexture(nil, "ARTWORK")
  ornamentBot:SetSize(32, 32)
  ornamentBot:SetPoint("BOTTOM", spineFrame, "BOTTOM", 0, 12)
  ornamentBot:SetTexture(TX .. "spine_ornament_bot.tga")

  -- Decorative dots: 3 between top ornament and mid, 3 between mid and bottom
  for _, yOff in ipairs({ 20, 44, 68 }) do
    local d = spineFrame:CreateTexture(nil, "ARTWORK")
    d:SetSize(8, 8)
    d:SetPoint("TOP", ornamentTop, "BOTTOM", 0, -yOff)
    d:SetTexture(TX .. "spine_dot.tga")
  end
  for _, yOff in ipairs({ 20, 44, 68 }) do
    local d = spineFrame:CreateTexture(nil, "ARTWORK")
    d:SetSize(8, 8)
    d:SetPoint("TOP", ornamentMid, "BOTTOM", 0, -yOff)
    d:SetTexture(TX .. "spine_dot.tga")
  end

  -- ── Left and right page frames ────────────────────────────────────────────
  local leftPage = CreateFrame("Frame", nil, codex)
  leftPage:SetPoint("TOPLEFT",    codex, "TOPLEFT",    0, 0)
  leftPage:SetPoint("BOTTOMLEFT", codex, "BOTTOMLEFT", 0, FOOTER_H + 6)
  leftPage:SetWidth(PAGE_W)
  leftPage:SetClipsChildren(true)

  local rightPage = CreateFrame("Frame", nil, codex)
  rightPage:SetPoint("TOPRIGHT",    codex, "TOPRIGHT",    0, 0)
  rightPage:SetPoint("BOTTOMRIGHT", codex, "BOTTOMRIGHT", 0, FOOTER_H + 6)
  rightPage:SetWidth(PAGE_W)
  rightPage:SetClipsChildren(true)

  -- ── Spine shadows on page inner edges ────────────────────────────────────
  local shadowL = leftPage:CreateTexture(nil, "OVERLAY")
  shadowL:SetWidth(16)
  shadowL:SetPoint("TOPRIGHT",    leftPage, "TOPRIGHT",    0, 0)
  shadowL:SetPoint("BOTTOMRIGHT", leftPage, "BOTTOMRIGHT", 0, 0)
  shadowL:SetTexture(TX .. "spine_shadow_left.tga")

  local shadowR = rightPage:CreateTexture(nil, "OVERLAY")
  shadowR:SetWidth(16)
  shadowR:SetPoint("TOPLEFT",    rightPage, "TOPLEFT",    0, 0)
  shadowR:SetPoint("BOTTOMLEFT", rightPage, "BOTTOMLEFT", 0, 0)
  shadowR:SetTexture(TX .. "spine_shadow_right.tga")

  -- ── Page backgrounds (aged parchment) ────────────────────────────────────
  local pageBgL = leftPage:CreateTexture(nil, "BACKGROUND", nil, -8)
  pageBgL:SetAllPoints(leftPage)
  pageBgL:SetTexture(TX .. "page_left.tga")

  local pageBgR = rightPage:CreateTexture(nil, "BACKGROUND", nil, -8)
  pageBgR:SetAllPoints(rightPage)
  pageBgR:SetTexture(TX .. "page_right.tga")

  -- ── Page headers ──────────────────────────────────────────────────────────
  local function MakePageHeader(page, label)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT",  page, "TOPLEFT",  2, -4)
    fs:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, -4)
    fs:SetJustifyH("CENTER")
    ApplyUIFont(fs, 9, "OUTLINE", COL_PURPLE)
    fs:SetTextColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.55)
    fs:SetText(label)

    local div = page:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT",  page, "TOPLEFT",  2, -16)
    div:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, -16)
    div:SetHeight(1)
    div:SetTexture(TX .. "page_header_divider.tga")
    div:SetVertexColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.30)
    div:SetHorizTile(true)
  end

  MakePageHeader(leftPage,  "DARK BINDINGS")
  MakePageHeader(rightPage, "FORBIDDEN RITES")

  -- ── Glyph watermark animation helpers ────────────────────────────────────
  local function SetupPulse(texture, minAlpha, maxAlpha, duration)
    texture:SetAlpha(minAlpha)
    local ag = texture:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(minAlpha)
    anim:SetToAlpha(maxAlpha)
    anim:SetDuration(duration)
    anim:SetSmoothing("IN_OUT")
    anim:SetOrder(1)
    ag:Play()
  end

  local function SetupCrackle(texture, cycleDur, startDelay, flashDur, peakAlpha)
    peakAlpha = peakAlpha or 0.5
    texture:SetAlpha(0)
    local ag = texture:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local wait = ag:CreateAnimation("Alpha")
    wait:SetFromAlpha(0)
    wait:SetToAlpha(0)
    wait:SetDuration(cycleDur - flashDur)
    wait:SetStartDelay(startDelay)
    wait:SetOrder(1)
    local flashIn = ag:CreateAnimation("Alpha")
    flashIn:SetFromAlpha(0)
    flashIn:SetToAlpha(peakAlpha)
    flashIn:SetDuration(flashDur * 0.3)
    flashIn:SetSmoothing("OUT")
    flashIn:SetOrder(2)
    local flashOut = ag:CreateAnimation("Alpha")
    flashOut:SetFromAlpha(peakAlpha)
    flashOut:SetToAlpha(0)
    flashOut:SetDuration(flashDur * 0.7)
    flashOut:SetSmoothing("IN")
    flashOut:SetOrder(3)
    ag:Play()
  end

  local function MakePageGlyphs(page)
    local container = CreateFrame("Frame", nil, page)
    container:SetPoint("TOPLEFT",     page, "TOPLEFT",     0, 0)
    container:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    container:EnableMouse(false)
    local base = container:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetAllPoints(container)
    local crackle = {}
    for i = 1, 3 do
      crackle[i] = container:CreateTexture(nil, "BACKGROUND", nil, -7)
      crackle[i]:SetAllPoints(container)
    end
    return base, crackle, container
  end

  -- ── Create glyph textures (upvalued for SetCodexTheme) ───────────────────
  local leftBase,  leftCrackle,  leftGlyphContainer  = MakePageGlyphs(leftPage)
  local rightBase, rightCrackle, rightGlyphContainer = MakePageGlyphs(rightPage)

  -- Left page: slow eerie pulse + 3 prime-duration crackles
  SetupPulse(leftBase, 0.55, 1.0, 2.5)
  SetupCrackle(leftCrackle[1], 6.0, 0.0, 0.40, 0.90)
  SetupCrackle(leftCrackle[2], 8.3, 2.1, 0.35, 0.85)
  SetupCrackle(leftCrackle[3], 7.0, 4.5, 0.45, 0.92)

  -- Right page: faster aggressive pulse + 3 prime-duration crackles
  SetupPulse(rightBase, 0.45, 0.95, 1.9)
  SetupCrackle(rightCrackle[1], 5.2, 0.0, 0.35, 0.85)
  SetupCrackle(rightCrackle[2], 7.0, 1.8, 0.40, 0.90)
  SetupCrackle(rightCrackle[3], 6.2, 3.3, 0.30, 0.80)

  -- ── Entry state tracking ──────────────────────────────────────────────────
  local allGetEn      = {}
  local allRefreshFns = {}
  local countLabel    = nil   -- assigned below when footer is built
  local disableLabel  = nil   -- assigned below when footer is built
  local totalMods     = 0

  local function UpdateCount()
    if not countLabel then return end
    local active = 0
    for _, getEn in ipairs(allGetEn) do
      if getEn() then active = active + 1 end
    end
    countLabel:SetText(active .. "  /  " .. totalMods .. "  MODULES ACTIVE")
    if disableLabel then
      disableLabel:SetText(active == totalMods and "DISABLE ALL" or "ENABLE ALL")
    end
  end

  -- ── Entry row builder ─────────────────────────────────────────────────────
  local function MakeEntry(page, m, slotIdx)
    local entryY = ENTRY_Y0 - (slotIdx - 1) * ROW_H

    -- Empty placeholder: just a dim rune silhouette, no interaction
    if m.empty then
      local emptyTex = page:CreateTexture(nil, "ARTWORK")
      emptyTex:SetSize(RUNE_SZ - 4, RUNE_SZ - 4)
      emptyTex:SetPoint(
        "TOPLEFT", page, "TOPLEFT",
        RUNE_PAD + ACCENT_W + 3,
        entryY - (ROW_H - (RUNE_SZ - 4)) / 2)
      emptyTex:SetTexture(TX .. "rune_empty.tga")
      emptyTex:SetVertexColor(0.10, 0.07, 0.18, 0.06)
      return
    end

    -- Enable/disable accessors
    local function getEn()
      if m.special then return db.general.trackedBarsSkin == true end
      db[m.dbKey] = db[m.dbKey] or {}
      return db[m.dbKey].enabled ~= false
    end

    local function setEn(v)
      if m.special then
        db.general.trackedBarsSkin = v
      else
        db[m.dbKey] = db[m.dbKey] or {}
        db[m.dbKey].enabled = v
      end
    end

    -- Full-width clickable button
    local btn = CreateFrame("Button", nil, page)
    btn:SetPoint("TOPLEFT",  page, "TOPLEFT",  0, entryY)
    btn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, entryY)
    btn:SetHeight(ROW_H)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- ON highlight (orange fade)
    local hlOn = btn:CreateTexture(nil, "BACKGROUND")
    hlOn:SetAllPoints(true)
    hlOn:SetTexture(TX .. "entry_highlight_on.tga")

    -- Hover highlight (purple fade)
    local hlHov = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    hlHov:SetAllPoints(true)
    hlHov:SetTexture(TX .. "entry_highlight_hover.tga")
    hlHov:Hide()

    -- Row on/off gradient (green = on, red = off)
    local hlGrad = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
    hlGrad:SetAllPoints(true)
    hlGrad:SetTexture("Interface/Buttons/WHITE8x8")

    -- Left accent strip (ON only)
    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetSize(ACCENT_W, ROW_H - 2)
    accent:SetPoint("LEFT", btn, "LEFT", 0, 0)
    accent:SetTexture(TX .. "entry_accent.tga")
    accent:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)

    -- Rune frame (border ring)
    local runeFrame = btn:CreateTexture(nil, "ARTWORK")
    runeFrame:SetSize(RUNE_SZ, RUNE_SZ)
    runeFrame:SetPoint("LEFT", btn, "LEFT", RUNE_PAD + ACCENT_W + 2, 0)

    -- Rune sigil (inside frame)
    local runeIcon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    runeIcon:SetSize(RUNE_SZ - 8, RUNE_SZ - 8)
    runeIcon:SetPoint("CENTER", runeFrame, "CENTER", 0, 0)

    -- Rune glow (additive, ON only)
    local runeGlow = btn:CreateTexture(nil, "OVERLAY")
    runeGlow:SetSize(RUNE_SZ + 12, RUNE_SZ + 12)
    runeGlow:SetPoint("CENTER", runeFrame, "CENTER", 0, 0)
    runeGlow:SetTexture(TX .. "rune_glow.tga")
    runeGlow:SetBlendMode("ADD")
    runeGlow:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.55)

    -- Module name
    local nameFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT",  runeFrame, "RIGHT", 5, 0)
    nameFS:SetPoint("RIGHT", btn,       "RIGHT", -(BAR_W + 10), 0)
    nameFS:SetJustifyH("LEFT")
    ApplyUIFont(nameFS, 11, "OUTLINE", COL_LAVLIVE)
    nameFS:SetText(m.name)

    -- Power bar background
    local barBg = btn:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(BAR_W, BAR_H)
    barBg:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    barBg:SetTexture(TX .. "bar_bg.tga")
    barBg:SetVertexColor(0.16, 0.10, 0.26, 0.75)

    -- Power bar fill
    local bar = CreateFrame("StatusBar", nil, btn)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("CENTER", barBg, "CENTER", 0, 0)
    bar:SetStatusBarTexture(TX .. "bar_fill.tga")
    bar:SetMinMaxValues(0, 1)

    -- Row divider at bottom
    local rowDiv = btn:CreateTexture(nil, "ARTWORK")
    rowDiv:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  2, 0)
    rowDiv:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 0)
    rowDiv:SetHeight(1)
    rowDiv:SetTexture(TX .. "row_divider.tga")
    rowDiv:SetVertexColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.18)
    rowDiv:SetHorizTile(true)

    -- Apply all visuals from current state
    local function Refresh()
      local en = getEn()
      if en then
        hlOn:Show()
        accent:Show()
        runeFrame:SetTexture(TX .. "rune_frame_active.tga")
        runeIcon:SetTexture(TX .. m.rune .. ".tga")
        runeIcon:SetVertexColor(1, 1, 1, 1)
        runeGlow:Show()
        nameFS:SetTextColor(COL_LAVLIVE[1], COL_LAVLIVE[2], COL_LAVLIVE[3])
        bar:SetValue(1)
        bar:SetStatusBarColor(0.15, 0.80, 0.25, 0.90)
        if hlGrad.SetGradient and CreateColor then
          hlGrad:SetGradient("HORIZONTAL", CreateColor(0.15, 0.75, 0.25, 0.12), CreateColor(0.15, 0.75, 0.25, 0))
        elseif hlGrad.SetGradientAlpha then
          hlGrad:SetGradientAlpha("HORIZONTAL", 0.15, 0.75, 0.25, 0.12, 0.15, 0.75, 0.25, 0)
        else
          hlGrad:SetColorTexture(0.15, 0.75, 0.25, 0.06)
        end
      else
        hlOn:Hide()
        accent:Hide()
        runeFrame:SetTexture(TX .. "rune_frame_normal.tga")
        runeIcon:SetTexture(TX .. m.rune .. "_off.tga")
        runeIcon:SetVertexColor(0.60, 0.54, 0.74, 0.60)
        runeGlow:Hide()
        nameFS:SetTextColor(COL_DIMTEXT[1], COL_DIMTEXT[2], COL_DIMTEXT[3])
        bar:SetValue(1)
        bar:SetStatusBarColor(0.75, 0.15, 0.15, 0.55)
        if hlGrad.SetGradient and CreateColor then
          hlGrad:SetGradient("HORIZONTAL", CreateColor(0.80, 0.12, 0.12, 0.12), CreateColor(0.80, 0.12, 0.12, 0))
        elseif hlGrad.SetGradientAlpha then
          hlGrad:SetGradientAlpha("HORIZONTAL", 0.80, 0.12, 0.12, 0.12, 0.80, 0.12, 0.12, 0)
        else
          hlGrad:SetColorTexture(0.80, 0.12, 0.12, 0.06)
        end
      end
    end

    RegisterTheme(function(c)
      accent:SetVertexColor(c[1], c[2], c[3], 1)
      runeGlow:SetVertexColor(c[1], c[2], c[3], 0.55)
      Refresh()
    end)

    btn:SetScript("OnEnter", function()
      local en = getEn()
      runeFrame:SetTexture(TX .. "rune_frame_hover.tga")
      if not en then
        hlHov:Show()
        bar:SetValue(0.25)
        bar:SetStatusBarColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.50)
      end
      if GameTooltip then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(m.name, ORANGE[1], ORANGE[2], ORANGE[3])
        GameTooltip:AddLine(
          en and "Right-click to disable." or "Right-click to enable.",
          0.80, 0.80, 0.86, true)
        if m.settingsKey then
          GameTooltip:AddLine("Left-click for settings.", 0.65, 0.65, 0.72, true)
        end
        GameTooltip:Show()
      end
    end)

    btn:SetScript("OnLeave", function()
      hlHov:Hide()
      Refresh()
      if GameTooltip then GameTooltip:Hide() end
    end)

    btn:SetScript("OnClick", function(_, mouseButton)
      if mouseButton == "RightButton" then
        setEn(not getEn())
        Refresh()
        UpdateCount()
        NS:ApplyAll()
        if UpdateNavIndicators then UpdateNavIndicators() end
      else
        if m.settingsKey and NS.OptionsPages and NS.OptionsPages.NavigateTo then
          NS.OptionsPages.NavigateTo(m.settingsKey)
        else
          setEn(not getEn())
          Refresh()
          UpdateCount()
          NS:ApplyAll()
          if UpdateNavIndicators then UpdateNavIndicators() end
        end
      end
    end)

    Refresh()
    table.insert(allGetEn, getEn)
    table.insert(allRefreshFns, Refresh)
    totalMods = totalMods + 1
  end

  -- ── Build entries ─────────────────────────────────────────────────────────
  for i = 1, LEFT_COUNT do
    MakeEntry(leftPage, CODEX_MODS[i], i)
  end

  for i = LEFT_COUNT + 1, #CODEX_MODS do
    MakeEntry(rightPage, CODEX_MODS[i], i - LEFT_COUNT)
  end

  -- ── Footer: count + disable/enable button ─────────────────────────────────
  local footer = CreateFrame("Frame", nil, codex)
  footer:SetPoint("BOTTOMLEFT",  codex, "BOTTOMLEFT",  4, 3)
  footer:SetPoint("BOTTOMRIGHT", codex, "BOTTOMRIGHT", -4, 3)
  footer:SetHeight(FOOTER_H)

  local footerDiv = footer:CreateTexture(nil, "ARTWORK")
  footerDiv:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
  footerDiv:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
  footerDiv:SetHeight(1)
  footerDiv:SetTexture(TX .. "footer_divider.tga")
  footerDiv:SetVertexColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.28)
  footerDiv:SetHorizTile(true)

  countLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  countLabel:SetPoint("LEFT", footer, "LEFT", 8, -2)
  ApplyUIFont(countLabel, 10, "OUTLINE", ORANGE)
  countLabel:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.85)

  local disableBtn = CreateFrame("Button", nil, footer, "BackdropTemplate")
  disableBtn:SetSize(110, 18)
  disableBtn:SetPoint("RIGHT", footer, "RIGHT", -4, -2)
  disableBtn:SetBackdrop({
    bgFile   = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  disableBtn:SetBackdropColor(0.08, 0.04, 0.14, 0.90)
  disableBtn:SetBackdropBorderColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.50)

  local disableTex = disableBtn:CreateTexture(nil, "BACKGROUND")
  disableTex:SetAllPoints(true)
  disableTex:SetTexture(TX .. "btn_disable_normal.tga")

  disableLabel = disableBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  disableLabel:SetPoint("CENTER", 0, 0)
  ApplyUIFont(disableLabel, 10, "OUTLINE", COL_PURPLE)
  disableLabel:SetTextColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.90)
  disableLabel:SetText("DISABLE ALL")

  disableBtn:SetScript("OnEnter", function()
    disableTex:SetTexture(TX .. "btn_disable_hover.tga")
    disableLabel:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
  end)
  disableBtn:SetScript("OnLeave", function()
    disableTex:SetTexture(TX .. "btn_disable_normal.tga")
    disableLabel:SetTextColor(COL_PURPLE[1], COL_PURPLE[2], COL_PURPLE[3], 0.90)
  end)
  disableBtn:SetScript("OnMouseDown", function()
    disableTex:SetTexture(TX .. "btn_disable_pressed.tga")
  end)
  disableBtn:SetScript("OnMouseUp", function()
    disableTex:SetTexture(TX .. "btn_disable_hover.tga")
  end)

  disableBtn:SetScript("OnClick", function()
    -- Toggle: all ON → disable all; any OFF → enable all
    local allEnabled = true
    for _, getEn in ipairs(allGetEn) do
      if not getEn() then allEnabled = false; break end
    end
    local newState = not allEnabled
    for _, m in ipairs(CODEX_MODS) do
      if not m.empty then
        if m.special then
          db.general.trackedBarsSkin = newState
        else
          db[m.dbKey] = db[m.dbKey] or {}
          db[m.dbKey].enabled = newState
        end
      end
    end
    for _, fn in ipairs(allRefreshFns) do fn() end
    UpdateCount()
    NS:ApplyAll()
    if UpdateNavIndicators then UpdateNavIndicators() end
  end)

  -- ── Glyph theme switcher ──────────────────────────────────────────────────
  local function SetCodexTheme(themeName)
    local theme = GLYPH_THEMES[themeName]
    if not theme or not theme.left then
      -- "none" theme: reset containers to page size and clear all glyph textures
      leftGlyphContainer:ClearAllPoints()
      leftGlyphContainer:SetPoint("TOPLEFT",     leftPage,  "TOPLEFT",     0, 0)
      leftGlyphContainer:SetPoint("BOTTOMRIGHT", leftPage,  "BOTTOMRIGHT", 0, 0)
      rightGlyphContainer:ClearAllPoints()
      rightGlyphContainer:SetPoint("TOPLEFT",     rightPage, "TOPLEFT",     0, 0)
      rightGlyphContainer:SetPoint("BOTTOMRIGHT", rightPage, "BOTTOMRIGHT", 0, 0)
      leftBase:SetTexture(nil)
      for i = 1, 3 do leftCrackle[i]:SetTexture(nil) end
      rightBase:SetTexture(nil)
      for i = 1, 3 do rightCrackle[i]:SetTexture(nil) end
      return
    end
    local expL = theme.left.expand  or 0
    local expR = theme.right.expand or 0
    leftGlyphContainer:ClearAllPoints()
    leftGlyphContainer:SetPoint("TOPLEFT",     leftPage,  "TOPLEFT",     -expL,  expL)
    leftGlyphContainer:SetPoint("BOTTOMRIGHT", leftPage,  "BOTTOMRIGHT",  expL, -expL)
    rightGlyphContainer:ClearAllPoints()
    rightGlyphContainer:SetPoint("TOPLEFT",     rightPage, "TOPLEFT",     -expR,  expR)
    rightGlyphContainer:SetPoint("BOTTOMRIGHT", rightPage, "BOTTOMRIGHT",  expR, -expR)
    leftBase:SetTexture(TX .. theme.left.base .. ".tga")
    for i = 1, 3 do leftCrackle[i]:SetTexture(TX .. theme.left.crackle[i] .. ".tga") end
    rightBase:SetTexture(TX .. theme.right.base .. ".tga")
    for i = 1, 3 do rightCrackle[i]:SetTexture(TX .. theme.right.crackle[i] .. ".tga") end
  end
  NS.OptionsPages.SetCodexTheme = SetCodexTheme

  -- ── Initialise count and apply saved theme ────────────────────────────────
  UpdateCount()
  SetCodexTheme(db.general.codexTheme or "necromancer")
end
