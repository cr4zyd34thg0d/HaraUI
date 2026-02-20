local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

function NS.OptionsPages.BuildFriendlyPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeAccentDivider, MakeColorSwatch, BuildStandardSliderRow, Small, db)
  pages.friendly = CreateFrame("Frame", nil, content); pages.friendly:SetAllPoints(true)
  do
    local function IsPlatynatorInstalled()
      if C_AddOns and C_AddOns.DoesAddOnExist then
        local ok, exists = pcall(C_AddOns.DoesAddOnExist, "Platynator")
        if ok and exists ~= nil then
          return exists == true
        end
      end
      if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, title = pcall(C_AddOns.GetAddOnMetadata, "Platynator", "Title")
        if ok and type(title) == "string" and title ~= "" then
          return true
        end
      end
      if GetAddOnInfo then
        local ok, name = pcall(GetAddOnInfo, "Platynator")
        if ok and name then
          return true
        end
      end
      return false
    end

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

    local function RefreshFriendly()
      if NS.Modules and NS.Modules.friendlyplates and NS.Modules.friendlyplates.Refresh then
        NS.Modules.friendlyplates:Refresh()
      end
    end

    local classColor = MakeCheckbox(cards.general.content, "Use Class Color", "Class colors override custom color.")
    classColor:SetPoint("TOPLEFT", 6, -4)
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
      NS.OptionsPages.CoerceInt,
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
      NS.OptionsPages.CoerceInt,
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

    local platynatorStatus = Small(cards.advanced.content, "")
    platynatorStatus:SetPoint("TOPLEFT", advancedText, "BOTTOMLEFT", 0, -10)
    local function UpdatePlatynatorStatus()
      if IsPlatynatorInstalled() then
        platynatorStatus:SetText("Platynator: detected")
        platynatorStatus:SetTextColor(0.20, 0.88, 0.32)
      else
        platynatorStatus:SetText("Platynator: not detected")
        platynatorStatus:SetTextColor(0.92, 0.24, 0.24)
      end
    end
    UpdatePlatynatorStatus()
    pages.friendly:HookScript("OnShow", UpdatePlatynatorStatus)

  end
end
