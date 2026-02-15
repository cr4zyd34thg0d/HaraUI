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

function NS.OptionsPages.CreateBuildGeneralPageCards(db, ORANGE, MakeCheckbox, NS, UpdateNavIndicators, ApplyToggleSkin, MakeAccentDivider, MakeButton, MakeColorSwatch, SetThemeColor, Small)
  return function(cards)
    db.summons = db.summons or {}
    if db.summons.enabled == nil then
      db.summons.enabled = true
    end
    db.charsheet = db.charsheet or {}
    if db.charsheet.enabled == nil then
      db.charsheet.enabled = true
    end
    if db.general.showSpellIDs == nil then
      db.general.showSpellIDs = false
    end
    db.general.themeColor = db.general.themeColor or { r = ORANGE[1], g = ORANGE[2], b = ORANGE[3] }

    local leftX = 6
    local rightX = 330

    local enable = MakeCheckbox(cards.general.content, "Enable HarathUI", "Toggle the whole UI suite on/off.")
    enable:SetPoint("TOPLEFT", leftX, -4)
    enable:SetChecked(db.general.enabled)
    enable:SetScript("OnClick", function()
      db.general.enabled = enable:GetChecked()
      NS:ApplyAll()
      UpdateNavIndicators()
    end)
    ApplyToggleSkin(enable)

    local unlock = MakeCheckbox(cards.general.content, "Unlock Frames", "Show simple drag outlines for movable UI elements.")
    unlock:SetPoint("TOPLEFT", rightX, -4)
    unlock:SetChecked(not db.general.framesLocked)
    unlock:SetScript("OnClick", function()
      db.general.framesLocked = not unlock:GetChecked()
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end)
    ApplyToggleSkin(unlock)

    local moveOptions = MakeCheckbox(cards.general.content, "Move Options", "Drag the Blizzard Settings window.")
    moveOptions:SetPoint("TOPLEFT", leftX, -40)
    moveOptions:SetChecked(db.general.moveOptions)
    moveOptions:SetScript("OnClick", function()
      db.general.moveOptions = moveOptions:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(moveOptions)

    local minimapBtn = MakeCheckbox(cards.general.content, "Minimap Button", "Show or hide the HarathUI minimap button.")
    minimapBtn:SetPoint("TOPLEFT", rightX, -40)
    minimapBtn:SetChecked(not (db.general.minimapButton and db.general.minimapButton.hide))
    minimapBtn:SetScript("OnClick", function()
      db.general.minimapButton = db.general.minimapButton or {}
      db.general.minimapButton.hide = not minimapBtn:GetChecked()
      if NS.UpdateMinimapButton then NS:UpdateMinimapButton() end
    end)
    ApplyToggleSkin(minimapBtn)

    local spellIdsCB = MakeCheckbox(cards.general.content, "Show Spell IDs", "Append spell IDs to spell tooltips.")
    spellIdsCB:SetPoint("TOPLEFT", leftX, -76)
    spellIdsCB:SetChecked(db.general.showSpellIDs == true)
    spellIdsCB:SetScript("OnClick", function()
      db.general.showSpellIDs = spellIdsCB:GetChecked()
    end)
    ApplyToggleSkin(spellIdsCB)

    local smallMenu = MakeCheckbox(cards.general.content, "Smaller Game Menu", "Use the compact game menu.")
    smallMenu:SetPoint("TOPLEFT", rightX, -76)
    smallMenu:SetChecked(db.gamemenu and db.gamemenu.enabled)
    smallMenu:SetScript("OnClick", function()
      db.gamemenu = db.gamemenu or {}
      db.gamemenu.enabled = smallMenu:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(smallMenu)

    local summonCB = MakeCheckbox(cards.general.content, "Auto Accept Summons", "Automatically accept incoming party/raid summons.")
    summonCB:SetPoint("TOPLEFT", leftX, -112)
    summonCB:SetChecked(db.summons.enabled == true)
    summonCB:SetScript("OnClick", function()
      db.summons.enabled = summonCB:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(summonCB)

    local charsheetToggle = MakeCheckbox(cards.general.content, "Character Sheet", "Enable or disable Character Sheet module.")
    charsheetToggle:SetPoint("TOPLEFT", rightX, -112)
    charsheetToggle:SetChecked(db.charsheet.enabled == true)
    charsheetToggle:SetScript("OnClick", function()
      db.charsheet.enabled = charsheetToggle:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(charsheetToggle)

    local trackedBars = MakeCheckbox(cards.general.content, "Skin Tracked Bars", "Apply cast-bar style to Blizzard Cooldown Viewer tracked bars.")
    trackedBars:SetPoint("TOPLEFT", leftX, -148)
    trackedBars:SetChecked(db.general.trackedBarsSkin == true)
    trackedBars:SetScript("OnClick", function()
      db.general.trackedBarsSkin = trackedBars:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(trackedBars)

    local controlsDivider = MakeAccentDivider(cards.general.content)
    controlsDivider:SetPoint("TOPLEFT", 0, -184)
    controlsDivider:SetPoint("TOPRIGHT", 0, -184)

    local resetAll = MakeButton(cards.general.content, "Reset All Positions", 170, 24)
    resetAll:SetPoint("TOPLEFT", leftX, -202)
    resetAll:SetScript("OnClick", function()
      NS:ResetFramePosition("xpbar", NS.DEFAULTS.profile.xpbar)
      NS:ResetFramePosition("castbar", NS.DEFAULTS.profile.castbar)
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end)

    local themeLabel, themeSwatch = MakeColorSwatch(
      cards.visuals.content,
      "Theme Color",
      function()
        return db.general.themeColor
      end,
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

    local noSizing = Small(cards.sizing.content, "No sizing options for General settings yet.")
    noSizing:SetPoint("TOPLEFT", leftX, -10)
    noSizing:SetTextColor(0.78, 0.78, 0.80)

    local commands = Small(cards.advanced.content, "Quick Commands\n\n- /hui (options)\n- /hui lock (toggle Unlock Frames)\n- /hui xp | cast | loot | summon")
    commands:SetPoint("TOPLEFT", leftX, -10)
    commands:SetTextColor(0.92, 0.92, 0.94)
  end
end

function NS.OptionsPages.BuildGeneralPage(pages, content, BuildStandardModuleCards, BuildGeneralPageCards)
  pages.general = CreateFrame("Frame", nil, content); pages.general:SetAllPoints(true)
  do
    local cards = BuildStandardModuleCards(pages.general)
    BuildGeneralPageCards(cards)
  end
end
