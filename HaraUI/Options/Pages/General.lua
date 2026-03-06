local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

local floor = math.floor

function NS.OptionsPages.CoerceInt(v)
  return floor(v + 0.5)
end

function NS.OptionsPages.SetModulePreviewOnClick(button, moduleKey, NS)
  button:SetScript("OnClick", function()
    if NS.Modules and NS.Modules[moduleKey] and NS.Modules[moduleKey].Preview then
      NS.Modules[moduleKey]:Preview()
    end
  end)
end

function NS.OptionsPages.CreateBuildGeneralPageCards(ctx)
  local db = ctx.db
  local ORANGE = ctx.ORANGE
  local MakeCheckbox = ctx.MakeCheckbox
  local NS = ctx.NS
  local UpdateNavIndicators = ctx.UpdateNavIndicators
  local MakeButton = ctx.MakeButton
  local MakeColorSwatch = ctx.MakeColorSwatch
  local SetThemeColor = ctx.SetThemeColor
  local Small = ctx.Small
  local BuildStandardSliderRow = ctx.BuildStandardSliderRow
  local Round2 = ctx.Round2
  local RegisterTheme = ctx.RegisterTheme
  local ApplyUIFont = ctx.ApplyUIFont
  -- Compact rune-themed skin for the top-section checkboxes.
  local ApplyRuneToggleSkin = NS.OptionsWidgets and NS.OptionsWidgets.ApplyRuneToggleSkin
    or ctx.ApplyToggleSkin  -- graceful fallback

  return function(cards)
    -- ── DB defaults ──────────────────────────────────────────────────────────
    db.charsheet      = db.charsheet      or {}
    db.gamemenu       = db.gamemenu       or {}
    db.altpanel       = db.altpanel       or {}
    db.xpbar          = db.xpbar          or {}
    db.castbar        = db.castbar        or {}
    db.loot           = db.loot           or {}
    db.friendlyplates = db.friendlyplates or {}
    db.rotationhelper = db.rotationhelper or {}
    db.minimapbar     = db.minimapbar     or {}
    db.merchant       = db.merchant       or {}
    db.questreward    = db.questreward    or {}
    db.autoequip      = db.autoequip      or {}
    db.bagupgrades    = db.bagupgrades    or {}

    if db.charsheet.enabled      == nil then db.charsheet.enabled      = true  end
    if db.gamemenu.enabled       == nil then db.gamemenu.enabled       = true  end
    if db.altpanel.enabled       == nil then db.altpanel.enabled       = true  end
    if db.xpbar.enabled          == nil then db.xpbar.enabled          = true  end
    if db.castbar.enabled        == nil then db.castbar.enabled        = true  end
    if db.loot.enabled           == nil then db.loot.enabled           = true  end
    if db.friendlyplates.enabled == nil then db.friendlyplates.enabled = true  end
    if db.rotationhelper.enabled == nil then db.rotationhelper.enabled = true  end
    if db.minimapbar.enabled     == nil then db.minimapbar.enabled     = true  end
    if db.merchant.enabled       == nil then db.merchant.enabled       = true  end
    if db.questreward.enabled    == nil then db.questreward.enabled    = true  end
    if db.autoequip.enabled      == nil then db.autoequip.enabled      = true  end
    if db.bagupgrades.enabled    == nil then db.bagupgrades.enabled    = true  end

    if db.general.showSpellIDs    == nil then db.general.showSpellIDs    = false end
    if db.general.trackedBarsSkin == nil then db.general.trackedBarsSkin = false end
    db.general.themeColor = db.general.themeColor
      or { r = ORANGE[1], g = ORANGE[2], b = ORANGE[3] }

    local leftX = 6    -- col 1
    local col2  = 226  -- col 2
    local col3  = 446  -- col 3

    -- ── Row 1: Enable HaraUI | Unlock Frames | Move Options ──────────────────
    local enable = MakeCheckbox(cards.general.content, "Enable HaraUI", "Toggle the whole UI suite on/off.")
    enable:SetPoint("TOPLEFT", leftX, -4)
    enable:SetChecked(db.general.enabled)
    enable:SetScript("OnClick", function()
      db.general.enabled = enable:GetChecked()
      NS:ApplyAll()
      UpdateNavIndicators()
    end)
    ApplyRuneToggleSkin(enable)

    local unlock = MakeCheckbox(cards.general.content, "Unlock Frames", "Show simple drag outlines for movable UI elements.")
    unlock:SetPoint("TOPLEFT", col2, -4)
    unlock:SetChecked(not db.general.framesLocked)
    unlock:SetScript("OnClick", function()
      db.general.framesLocked = not unlock:GetChecked()
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end)
    ApplyRuneToggleSkin(unlock)

    local moveOptions = MakeCheckbox(cards.general.content, "Move Options", "Drag the Blizzard Settings window.")
    moveOptions:SetPoint("TOPLEFT", col3, -4)
    moveOptions:SetChecked(db.general.moveOptions)
    moveOptions:SetScript("OnClick", function()
      db.general.moveOptions = moveOptions:GetChecked()
      NS:ApplyAll()
    end)
    ApplyRuneToggleSkin(moveOptions)

    -- ── Row 2: Minimap Button | Show Spell IDs (26 px below row 1) ───────────
    local minimapBtn = MakeCheckbox(cards.general.content, "Minimap Button", "Show or hide the HaraUI minimap button.")
    minimapBtn:SetPoint("TOPLEFT", leftX, -30)
    minimapBtn:SetChecked(not (db.general.minimapButton and db.general.minimapButton.hide))
    minimapBtn:SetScript("OnClick", function()
      db.general.minimapButton = db.general.minimapButton or {}
      db.general.minimapButton.hide = not minimapBtn:GetChecked()
      if NS.UpdateMinimapButton then NS:UpdateMinimapButton() end
    end)
    ApplyRuneToggleSkin(minimapBtn)

    local spellIdsCB = MakeCheckbox(cards.general.content, "Show Spell IDs", "Append spell IDs to spell tooltips.")
    spellIdsCB:SetPoint("TOPLEFT", col2, -30)
    spellIdsCB:SetChecked(db.general.showSpellIDs == true)
    spellIdsCB:SetScript("OnClick", function()
      db.general.showSpellIDs = spellIdsCB:GetChecked()
    end)
    ApplyRuneToggleSkin(spellIdsCB)

    local autoRepair = MakeCheckbox(cards.general.content, "Auto Repair", "Automatically repair gear when opening a repair merchant.")
    autoRepair:SetPoint("TOPLEFT", col3, -30)
    autoRepair:SetChecked(db.merchant.autoRepair ~= false)
    autoRepair:SetScript("OnClick", function()
      db.merchant.autoRepair = autoRepair:GetChecked()
    end)
    ApplyRuneToggleSkin(autoRepair)

    local autoSell = MakeCheckbox(cards.general.content, "Auto Sell Junk", "Automatically sell grey items when opening a merchant.")
    autoSell:SetPoint("TOPLEFT", leftX, -56)
    autoSell:SetChecked(db.merchant.autoSell ~= false)
    autoSell:SetScript("OnClick", function()
      db.merchant.autoSell = autoSell:GetChecked()
    end)
    ApplyRuneToggleSkin(autoSell)

    local bagUpgrades = MakeCheckbox(cards.general.content, "Bag Upgrade Arrows", "Show a small green arrow on bag items that are upgrades for your equipped gear.")
    bagUpgrades:SetPoint("TOPLEFT", col2, -56)
    bagUpgrades:SetChecked(db.bagupgrades.enabled ~= false)
    bagUpgrades:SetScript("OnClick", function()
      db.bagupgrades.enabled = bagUpgrades:GetChecked()
      NS:ApplyAll()
    end)
    ApplyRuneToggleSkin(bagUpgrades)

    -- ════════════════════════════════════════════════════════════════════════
    --  MODULE DASHBOARD — Necromancer's Codex
    -- ════════════════════════════════════════════════════════════════════════
    NS.OptionsPages.BuildCodexPanel(
      cards.general.content, db, NS, ORANGE,
      RegisterTheme, ApplyUIFont, UpdateNavIndicators)

    -- ════════════════════════════════════════════════════════════════════════
    --  VISUALS tab
    -- ════════════════════════════════════════════════════════════════════════
    -- Reset All Positions moved here from the General top section.
    local resetAll = MakeButton(cards.visuals.content, "Reset All Positions", 170, 24)
    resetAll:SetPoint("TOPLEFT", leftX, -10)
    resetAll:SetScript("OnClick", function()
      NS:ResetFramePosition("xpbar",   NS.DEFAULTS.profile.xpbar)
      NS:ResetFramePosition("castbar", NS.DEFAULTS.profile.castbar)
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end)

    local themeLabel, themeSwatch = MakeColorSwatch(
      cards.visuals.content,
      "Theme Color",
      function() return db.general.themeColor end,
      function(r, g, b)
        db.general.themeColor = { r = r, g = g, b = b }
        SetThemeColor(r, g, b)
      end
    )
    themeLabel:SetPoint("TOPLEFT", leftX, -46)
    themeLabel:SetWidth(96)
    themeLabel:SetJustifyH("LEFT")
    themeSwatch:ClearAllPoints()
    themeSwatch:SetPoint("LEFT", themeLabel, "RIGHT", 12, 0)

    local themeHint = Small(cards.visuals.content, "Adjusts the accent color used across HaraUI.")
    themeHint:SetPoint("TOPLEFT", leftX, -76)
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
    csScale:SetPoint("TOPLEFT",  leftX, -106)
    csScale:SetPoint("TOPRIGHT", -6,    -106)

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
      "Quick Commands\n\n- /hui (options)\n- /hui lock (toggle Unlock Frames)\n- /hui xp | cast | loot")
    commands:SetPoint("TOPLEFT", leftX, -10)
    commands:SetTextColor(0.92, 0.92, 0.94)
  end
end

function NS.OptionsPages.BuildGeneralPage(ctx)
  local pages = ctx.pages
  local content = ctx.content
  local BuildStandardModuleCards = ctx.BuildStandardModuleCards
  local BuildGeneralPageCards = ctx.BuildGeneralPageCards
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
