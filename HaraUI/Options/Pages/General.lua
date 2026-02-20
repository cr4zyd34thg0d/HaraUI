local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

local floor = math.floor

function NS.OptionsPages.CoerceInt(v)
  return floor(v + 0.5)
end

function NS.OptionsPages.AttachModuleEnableToggle(toggle, parent, ApplyToggleSkin)
  toggle:ClearAllPoints()
  toggle:SetParent(parent)
  toggle:SetPoint("TOPLEFT", 6, -4)
  ApplyToggleSkin(toggle)
end

function NS.OptionsPages.SetModulePreviewOnClick(button, moduleKey, NS)
  button:SetScript("OnClick", function()
    if NS.Modules and NS.Modules[moduleKey] and NS.Modules[moduleKey].Preview then
      NS.Modules[moduleKey]:Preview()
    end
  end)
end

function NS.OptionsPages.CreateBuildGeneralPageCards(
  db, ORANGE, MakeCheckbox, NS, UpdateNavIndicators, ApplyToggleSkin,
  MakeButton, MakeColorSwatch, SetThemeColor, Small,
  BuildStandardSliderRow, Round2, RegisterTheme, ApplyUIFont
)
  return function(cards)
    -- ── DB defaults ──────────────────────────────────────────────────────────
    db.summons        = db.summons        or {}
    db.charsheet      = db.charsheet      or {}
    db.gamemenu       = db.gamemenu       or {}
    db.altpanel       = db.altpanel       or {}
    db.xpbar          = db.xpbar          or {}
    db.castbar        = db.castbar        or {}
    db.loot           = db.loot           or {}
    db.friendlyplates = db.friendlyplates or {}
    db.rotationhelper = db.rotationhelper or {}
    db.minimapbar     = db.minimapbar     or {}

    if db.summons.enabled        == nil then db.summons.enabled        = true  end
    if db.charsheet.enabled      == nil then db.charsheet.enabled      = true  end
    if db.gamemenu.enabled       == nil then db.gamemenu.enabled       = true  end
    if db.altpanel.enabled       == nil then db.altpanel.enabled       = true  end
    if db.xpbar.enabled          == nil then db.xpbar.enabled          = true  end
    if db.castbar.enabled        == nil then db.castbar.enabled        = true  end
    if db.loot.enabled           == nil then db.loot.enabled           = true  end
    if db.friendlyplates.enabled == nil then db.friendlyplates.enabled = true  end
    if db.rotationhelper.enabled == nil then db.rotationhelper.enabled = true  end
    if db.minimapbar.enabled     == nil then db.minimapbar.enabled     = true  end

    if db.general.showSpellIDs    == nil then db.general.showSpellIDs    = false end
    if db.general.trackedBarsSkin == nil then db.general.trackedBarsSkin = false end
    db.general.themeColor = db.general.themeColor
      or { r = ORANGE[1], g = ORANGE[2], b = ORANGE[3] }

    local leftX  = 6    -- col 1 (also used in Visuals/Advanced tabs)
    local col2   = 226  -- col 2
    local col3   = 446  -- col 3

    -- ── Row 1: Enable HaraUI | Unlock Frames | Move Options ──────────────────
    local enable = MakeCheckbox(cards.general.content, "Enable HaraUI", "Toggle the whole UI suite on/off.")
    enable:SetPoint("TOPLEFT", leftX, -4)
    enable:SetChecked(db.general.enabled)
    enable:SetScript("OnClick", function()
      db.general.enabled = enable:GetChecked()
      NS:ApplyAll()
      UpdateNavIndicators()
    end)
    ApplyToggleSkin(enable)

    local unlock = MakeCheckbox(cards.general.content, "Unlock Frames", "Show simple drag outlines for movable UI elements.")
    unlock:SetPoint("TOPLEFT", col2, -4)
    unlock:SetChecked(not db.general.framesLocked)
    unlock:SetScript("OnClick", function()
      db.general.framesLocked = not unlock:GetChecked()
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end)
    ApplyToggleSkin(unlock)

    local moveOptions = MakeCheckbox(cards.general.content, "Move Options", "Drag the Blizzard Settings window.")
    moveOptions:SetPoint("TOPLEFT", col3, -4)
    moveOptions:SetChecked(db.general.moveOptions)
    moveOptions:SetScript("OnClick", function()
      db.general.moveOptions = moveOptions:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(moveOptions)

    -- ── Row 2: Minimap Button | Show Spell IDs | Reset All Positions ──────────
    local minimapBtn = MakeCheckbox(cards.general.content, "Minimap Button", "Show or hide the HaraUI minimap button.")
    minimapBtn:SetPoint("TOPLEFT", leftX, -34)
    minimapBtn:SetChecked(not (db.general.minimapButton and db.general.minimapButton.hide))
    minimapBtn:SetScript("OnClick", function()
      db.general.minimapButton = db.general.minimapButton or {}
      db.general.minimapButton.hide = not minimapBtn:GetChecked()
      if NS.UpdateMinimapButton then NS:UpdateMinimapButton() end
    end)
    ApplyToggleSkin(minimapBtn)

    local spellIdsCB = MakeCheckbox(cards.general.content, "Show Spell IDs", "Append spell IDs to spell tooltips.")
    spellIdsCB:SetPoint("TOPLEFT", col2, -34)
    spellIdsCB:SetChecked(db.general.showSpellIDs == true)
    spellIdsCB:SetScript("OnClick", function()
      db.general.showSpellIDs = spellIdsCB:GetChecked()
    end)
    ApplyToggleSkin(spellIdsCB)

    local resetAll = MakeButton(cards.general.content, "Reset All Positions", 170, 24)
    resetAll:SetPoint("TOPLEFT", col3, -34)
    resetAll:SetScript("OnClick", function()
      NS:ResetFramePosition("xpbar",   NS.DEFAULTS.profile.xpbar)
      NS:ResetFramePosition("castbar", NS.DEFAULTS.profile.castbar)
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end)

    -- ── Row 3: Codex Theme ────────────────────────────────────────────────────
    db.general.codexTheme = db.general.codexTheme or "necromancer"
    local THEME_LABELS  = { none = "None", necromancer = "Necromancer", arcane = "Arcane", faction = "Faction" }
    local THEME_CYCLE   = { none = "necromancer", necromancer = "arcane", arcane = "faction", faction = "none" }
    local themeBtn = MakeButton(cards.general.content,
      "Theme: " .. (THEME_LABELS[db.general.codexTheme] or "Necromancer"), 170, 24)
    themeBtn:SetPoint("TOPLEFT", col3, -64)
    themeBtn:SetScript("OnClick", function()
      local cur  = db.general.codexTheme or "necromancer"
      local next = THEME_CYCLE[cur] or "necromancer"
      db.general.codexTheme = next
      themeBtn:SetText("Theme: " .. THEME_LABELS[next])
      if NS.OptionsPages.SetCodexTheme then NS.OptionsPages.SetCodexTheme(next) end
    end)

    -- ════════════════════════════════════════════════════════════════════════
    --  MODULE DASHBOARD — Necromancer's Codex
    -- ════════════════════════════════════════════════════════════════════════
    NS.OptionsPages.BuildCodexPanel(
      cards.general.content, db, NS, ORANGE,
      RegisterTheme, ApplyUIFont, UpdateNavIndicators)

    --  VISUALS / SIZING / ADVANCED tabs (unchanged)
    -- ════════════════════════════════════════════════════════════════════════
    local themeLabel, themeSwatch = MakeColorSwatch(
      cards.visuals.content,
      "Theme Color",
      function() return db.general.themeColor end,
      function(r, g, b)
        db.general.themeColor = { r = r, g = g, b = b }
        SetThemeColor(r, g, b)
      end
    )
    themeLabel:SetPoint("TOPLEFT", leftX, -10)
    themeLabel:SetWidth(96)
    themeLabel:SetJustifyH("LEFT")
    themeSwatch:ClearAllPoints()
    themeSwatch:SetPoint("LEFT", themeLabel, "RIGHT", 12, 0)

    local themeHint = Small(cards.visuals.content, "Adjusts the accent color used across HaraUI.")
    themeHint:SetPoint("TOPLEFT", leftX, -40)
    themeHint:SetTextColor(0.78, 0.78, 0.80)

    db.charsheet = db.charsheet or {}
    if db.charsheet.scale == nil then db.charsheet.scale = 1.0 end

    local csScale = BuildStandardSliderRow(
      cards.visuals.content,
      "Character Sheet Scale",
      0.50, 1.50, 0.05,
      db.charsheet.scale,
      "%.2f",
      Round2,
      function(v)
        db.charsheet.scale = v
        NS:ApplyAll()
      end
    )
    csScale:SetPoint("TOPLEFT",  leftX, -70)
    csScale:SetPoint("TOPRIGHT", -6,    -70)

    db.altpanel = db.altpanel or {}
    if db.altpanel.scale == nil then db.altpanel.scale = 1.0 end

    local apScale = BuildStandardSliderRow(
      cards.visuals.content,
      "Alt Panel Scale",
      0.50, 1.50, 0.05,
      db.altpanel.scale,
      "%.2f",
      Round2,
      function(v)
        db.altpanel.scale = v
        if NS.AltPanel and NS.AltPanel.Window and NS.AltPanel.Window.ApplyScale then
          NS.AltPanel.Window:ApplyScale()
        end
      end
    )
    apScale:SetPoint("TOPLEFT",  csScale, "BOTTOMLEFT",  0, -14)
    apScale:SetPoint("TOPRIGHT", csScale, "BOTTOMRIGHT", 0, -14)

    local noSizing = Small(cards.sizing.content, "No sizing options for General settings yet.")
    noSizing:SetPoint("TOPLEFT", leftX, -10)
    noSizing:SetTextColor(0.78, 0.78, 0.80)

    local commands = Small(cards.advanced.content,
      "Quick Commands\n\n- /hui (options)\n- /hui lock (toggle Unlock Frames)\n- /hui xp | cast | loot | summon")
    commands:SetPoint("TOPLEFT", leftX, -10)
    commands:SetTextColor(0.92, 0.92, 0.94)
  end
end

function NS.OptionsPages.BuildGeneralPage(pages, content, BuildStandardModuleCards, BuildGeneralPageCards)
  pages.general = CreateFrame("Frame", nil, content); pages.general:SetAllPoints(true)
  do
    local cards = BuildStandardModuleCards(pages.general)
    -- The "General" card label is redundant on the main settings page — hide it
    -- and shift the content frame up to reclaim the 18px header gap.
    if cards.general.title then
      cards.general.title:Hide()
      cards.general.content:ClearAllPoints()
      cards.general.content:SetPoint("TOPLEFT",     cards.general, "TOPLEFT",     12, -12)
      cards.general.content:SetPoint("BOTTOMRIGHT", cards.general, "BOTTOMRIGHT", -12,  12)
    end
    BuildGeneralPageCards(cards)
  end
end
