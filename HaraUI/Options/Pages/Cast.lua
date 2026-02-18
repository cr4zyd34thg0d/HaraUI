local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

function NS.OptionsPages.BuildCastPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeButton, MakeAccentDivider, BuildStandardSliderRow, Round2, MakeColorSwatch, ApplyUIFont, ORANGE_SIZE, ORANGE, ApplyDropdownFont, RegisterTheme, Small, db)
  pages.cast = CreateFrame("Frame", nil, content); pages.cast:SetAllPoints(true)
  do
    local castEnable = MakeModuleHeader(pages.cast, "castbar")

    if not db.castbar.barTexture then db.castbar.barTexture = "Interface/TargetingFrame/UI-StatusBar" end
    if not db.castbar.barColor then db.castbar.barColor = { r = 0.5, g = 0.5, b = 1.0 } end
    if not db.castbar.textColor then db.castbar.textColor = { r = 1, g = 1, b = 1 } end

    local textures = {
      { name = "Flat",     path = "Interface/TargetingFrame/UI-StatusBar" },
      { name = "Blizzard", path = "Interface/RaidFrame/Raid-Bar-Hp-Fill" },
      { name = "White",    path = "Interface/Buttons/WHITE8x8" },
    }

    local cards = BuildStandardModuleCards(pages.cast)

    -- General card controls.
    NS.OptionsPages.AttachModuleEnableToggle(castEnable, cards.general.content, ApplyToggleSkin)

    local showIcon = MakeCheckbox(cards.general.content, "Show Spell Icon", "Show the spell icon on the left.")
    showIcon:SetPoint("TOPLEFT", 330, -4)
    showIcon:SetChecked(db.castbar.showIcon)
    showIcon:SetScript("OnClick", function()
      db.castbar.showIcon = showIcon:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(showIcon)

    local shield = MakeCheckbox(cards.general.content, "Show Interrupt Shield", "Shield icon on uninterruptible casts.")
    shield:SetPoint("TOPLEFT", 6, -40)
    shield:SetChecked(db.castbar.showShield)
    shield:SetScript("OnClick", function()
      db.castbar.showShield = shield:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(shield)

    local latency = MakeCheckbox(cards.general.content, "Show Latency Spark", "Latency spark at the bar edge (best-effort).")
    latency:SetPoint("TOPLEFT", 330, -40)
    latency:SetChecked(db.castbar.showLatencySpark)
    latency:SetScript("OnClick", function()
      db.castbar.showLatencySpark = latency:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(latency)

    local previewBtn = MakeButton(cards.general.content, "Preview Cast Bar", 170, 24)
    previewBtn:SetPoint("TOPLEFT", 6, -86)
    NS.OptionsPages.SetModulePreviewOnClick(previewBtn, "castbar", NS)

    local generalDivider = MakeAccentDivider(cards.general.content)
    generalDivider:SetPoint("TOPLEFT", 0, -124)
    generalDivider:SetPoint("TOPRIGHT", 0, -124)

    -- Sizing card controls.
    local scale = BuildStandardSliderRow(
      cards.sizing.content,
      "Scale",
      0.6,
      1.8,
      0.05,
      db.castbar.scale or 1.0,
      "%.2f",
      Round2,
      function(v)
        db.castbar.scale = v
        NS:ApplyAll()
      end
    )
    scale:SetPoint("TOPLEFT", 6, -10)
    scale:SetPoint("TOPRIGHT", -6, -10)

    local width = BuildStandardSliderRow(
      cards.sizing.content,
      "Width",
      220,
      640,
      10,
      db.castbar.width or 320,
      "%.0f",
      NS.OptionsPages.CoerceInt,
      function(v)
        db.castbar.width = v
        NS:ApplyAll()
      end
    )
    width:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -14)
    width:SetPoint("TOPRIGHT", scale, "BOTTOMRIGHT", 0, -14)

    local height = BuildStandardSliderRow(
      cards.sizing.content,
      "Height",
      12,
      32,
      1,
      db.castbar.height or 16,
      "%.0f",
      NS.OptionsPages.CoerceInt,
      function(v)
        db.castbar.height = v
        NS:ApplyAll()
      end
    )
    height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, -14)
    height:SetPoint("TOPRIGHT", width, "BOTTOMRIGHT", 0, -14)

    local textSize = BuildStandardSliderRow(
      cards.sizing.content,
      "Text Size",
      8,
      20,
      1,
      db.castbar.textSize or 11,
      "%.0f",
      NS.OptionsPages.CoerceInt,
      function(v)
        db.castbar.textSize = v
        NS:ApplyAll()
      end
    )
    textSize:SetPoint("TOPLEFT", height, "BOTTOMLEFT", 0, -14)
    textSize:SetPoint("TOPRIGHT", height, "BOTTOMRIGHT", 0, -14)

    -- Visuals card controls.
    local function GetCastBarColor()
      return db.castbar.barColor
    end
    local function SetCastBarColor(r, g, b)
      db.castbar.barColor = { r = r, g = g, b = b }
      NS:ApplyAll()
    end
    local visualsLabelWidth = 90
    local colorLabel, colorSwatch = MakeColorSwatch(cards.visuals.content, "Bar Color", GetCastBarColor, SetCastBarColor)
    colorLabel:SetPoint("TOPLEFT", 6, -10)
    colorLabel:SetWidth(visualsLabelWidth)
    colorLabel:SetJustifyH("LEFT")
    colorSwatch:ClearAllPoints()
    colorSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 12, 0)

    local function GetCastTextColor()
      return db.castbar.textColor
    end
    local function SetCastTextColor(r, g, b)
      db.castbar.textColor = { r = r, g = g, b = b }
      NS:ApplyAll()
    end
    local textColorLabel, textColorSwatch = MakeColorSwatch(cards.visuals.content, "Text Color", GetCastTextColor, SetCastTextColor)
    textColorLabel:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -20)
    textColorLabel:SetWidth(visualsLabelWidth)
    textColorLabel:SetJustifyH("LEFT")
    textColorSwatch:ClearAllPoints()
    textColorSwatch:SetPoint("LEFT", textColorLabel, "RIGHT", 12, 0)

    local visualsDivider = MakeAccentDivider(cards.visuals.content)
    visualsDivider:SetPoint("TOPLEFT", 0, -74)
    visualsDivider:SetPoint("TOPRIGHT", 0, -74)

    local texLabel = cards.visuals.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    texLabel:SetPoint("TOPLEFT", 6, -100)
    texLabel:SetText("Bar Texture")
    ApplyUIFont(texLabel, ORANGE_SIZE, "OUTLINE", ORANGE)

    local texDD = CreateFrame("Button", nil, cards.visuals.content, "BackdropTemplate")
    texDD:ClearAllPoints()
    texDD:SetPoint("TOPLEFT", texLabel, "BOTTOMLEFT", 0, -6)
    texDD:SetSize(186, 24)
    texDD:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    texDD:SetBackdropColor(0.07, 0.08, 0.11, 0.92)
    texDD:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.92)

    local texDDText = texDD:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    texDDText:SetPoint("LEFT", 10, 0)
    texDDText:SetPoint("RIGHT", -22, 0)
    texDDText:SetJustifyH("LEFT")
    ApplyUIFont(texDDText, 12, "OUTLINE", { 0.9, 0.9, 0.9 })

    local texDDArrow = texDD:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    texDDArrow:SetPoint("RIGHT", -8, 0)
    texDDArrow:SetText("v")
    ApplyUIFont(texDDArrow, 11, "OUTLINE", { ORANGE[1], ORANGE[2], ORANGE[3] })

    local texDDMenu = CreateFrame("Frame", nil, texDD, "BackdropTemplate")
    texDDMenu:SetPoint("TOPLEFT", texDD, "BOTTOMLEFT", 0, -2)
    texDDMenu:SetPoint("TOPRIGHT", texDD, "BOTTOMRIGHT", 0, -2)
    texDDMenu:SetHeight(2)
    texDDMenu:SetFrameStrata("TOOLTIP")
    texDDMenu:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    texDDMenu:SetBackdropColor(0.07, 0.08, 0.11, 0.96)
    texDDMenu:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.92)
    texDDMenu:Hide()

    local function ApplyCastTextureDropdownTheme(c)
      local accent = c or ORANGE
      texDD:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.92)
      texDDArrow:SetTextColor(accent[1], accent[2], accent[3], 1)
      texDDMenu:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.92)
    end
    ApplyCastTextureDropdownTheme(ORANGE)
    RegisterTheme(function(c)
      ApplyCastTextureDropdownTheme(c)
    end)

    local function GetTextureName(path)
      for _, t in ipairs(textures) do
        if t.path == path then return t.name end
      end
      return path
    end

    local function RefreshTexLabel()
      texDDText:SetText(GetTextureName(db.castbar.barTexture))
    end

    local rows = {}
    local ROW_HEIGHT = 20
    local MENU_PAD_TOP = -4
    local MENU_PAD_BOTTOM = 4
    for i, t in ipairs(textures) do
      local row = CreateFrame("Button", nil, texDDMenu)
      row:SetPoint("TOPLEFT", texDDMenu, "TOPLEFT", 4, MENU_PAD_TOP - ((i - 1) * ROW_HEIGHT))
      row:SetPoint("TOPRIGHT", texDDMenu, "TOPRIGHT", -4, MENU_PAD_TOP - ((i - 1) * ROW_HEIGHT))
      row:SetHeight(ROW_HEIGHT)

      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetAllPoints(true)
      row.bg:SetColorTexture(1, 1, 1, 0.0)

      row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.text:SetPoint("LEFT", 8, 0)
      row.text:SetPoint("RIGHT", -8, 0)
      row.text:SetJustifyH("LEFT")
      row.text:SetText(t.name)
      ApplyUIFont(row.text, 12, "OUTLINE", { 0.9, 0.9, 0.9 })

      row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.08)
      end)
      row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.0)
      end)
      row:SetScript("OnClick", function()
        db.castbar.barTexture = t.path
        RefreshTexLabel()
        texDDMenu:Hide()
        NS:ApplyAll()
      end)

      rows[#rows + 1] = row
    end
    texDDMenu:SetHeight((#rows * ROW_HEIGHT) + math.abs(MENU_PAD_TOP) + MENU_PAD_BOTTOM)

    texDD:SetScript("OnClick", function()
      if texDDMenu:IsShown() then
        texDDMenu:Hide()
      else
        texDDMenu:Show()
        texDDMenu:Raise()
      end
    end)
    texDD:SetScript("OnHide", function()
      texDDMenu:Hide()
    end)
    cards.visuals.content:HookScript("OnHide", function()
      texDDMenu:Hide()
    end)

    RefreshTexLabel()

    -- Advanced placeholder card.
    local advancedText = Small(cards.advanced.content, "Reserved for future Cast Bar options.")
    advancedText:SetPoint("TOPLEFT", 6, -10)
    advancedText:SetTextColor(0.78, 0.78, 0.80)

  end
end
