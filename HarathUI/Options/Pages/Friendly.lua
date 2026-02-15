local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

function NS.OptionsPages.BuildFriendlyPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeAccentDivider, MakeColorSwatch, BuildStandardSliderRow, Small, db)
  pages.friendly = CreateFrame("Frame", nil, content); pages.friendly:SetAllPoints(true)
  do
    local friendlyEnable = MakeModuleHeader(pages.friendly, "friendlyplates")

    if not db.friendlyplates.nameColor then
      db.friendlyplates.nameColor = { r = 1, g = 1, b = 1 }
    end
    if db.friendlyplates.classColor == nil then
      db.friendlyplates.classColor = false
    end
    if not db.friendlyplates.fontSize then
      db.friendlyplates.fontSize = 12
    end
    if not db.friendlyplates.yOffset then
      db.friendlyplates.yOffset = 0
    end

    local cards = BuildStandardModuleCards(pages.friendly)

    friendlyEnable:ClearAllPoints()
    friendlyEnable:SetParent(cards.general.content)
    friendlyEnable:SetPoint("TOPLEFT", 6, -4)
    ApplyToggleSkin(friendlyEnable)

    local function RefreshFriendly()
      if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
        NS.Modules.friendlyplates:Refresh()
      end
    end

    local classColor = MakeCheckbox(cards.general.content, "Use Class Color", "Class colors override custom color.")
    classColor:SetPoint("TOPLEFT", 330, -4)
    classColor:SetChecked(db.friendlyplates.classColor)
    classColor:SetScript("OnClick", function()
      db.friendlyplates.classColor = classColor:GetChecked()
      NS:ApplyAll()
      RefreshFriendly()
    end)
    ApplyToggleSkin(classColor)

    local generalDivider = MakeAccentDivider(cards.general.content)
    generalDivider:SetPoint("TOPLEFT", 0, -40)
    generalDivider:SetPoint("TOPRIGHT", 0, -40)

    local function GetNameplateColor()
      return db.friendlyplates.nameColor
    end
    local function SetNameplateColor(r, g, b)
      db.friendlyplates.nameColor = { r = r, g = g, b = b }
      NS:ApplyAll()
      RefreshFriendly()
    end
    local visualsLabelWidth = 96
    local colorLabel, colorSwatch = MakeColorSwatch(cards.visuals.content, "Name Color", GetNameplateColor, SetNameplateColor)
    colorLabel:SetPoint("TOPLEFT", 6, -10)
    colorLabel:SetWidth(visualsLabelWidth)
    colorLabel:SetJustifyH("LEFT")
    colorSwatch:ClearAllPoints()
    colorSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 12, 0)

    local size = BuildStandardSliderRow(
      cards.sizing.content,
      "Size",
      8,
      24,
      1,
      db.friendlyplates.fontSize or 12,
      "%.0f",
      function(v) return math.floor(v + 0.5) end,
      function(v)
        db.friendlyplates.fontSize = v
        NS:ApplyAll()
        RefreshFriendly()
      end
    )
    size:SetPoint("TOPLEFT", 6, -10)
    size:SetPoint("TOPRIGHT", -6, -10)

    local offset = BuildStandardSliderRow(
      cards.sizing.content,
      "Y Offset",
      -30,
      30,
      1,
      db.friendlyplates.yOffset or 0,
      "%.0f",
      function(v) return math.floor(v + 0.5) end,
      function(v)
        db.friendlyplates.yOffset = v
        NS:ApplyAll()
        RefreshFriendly()
      end
    )
    offset:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -14)
    offset:SetPoint("TOPRIGHT", size, "BOTTOMRIGHT", 0, -14)

    local advancedText = Small(cards.advanced.content, "Reserved for future Friendly Nameplates options.")
    advancedText:SetPoint("TOPLEFT", 6, -10)
    advancedText:SetTextColor(0.78, 0.78, 0.80)

  end
end
