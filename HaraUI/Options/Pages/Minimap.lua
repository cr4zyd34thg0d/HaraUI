local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

function NS.OptionsPages.BuildMinimapPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)
  pages.minimap = CreateFrame("Frame", nil, content); pages.minimap:SetAllPoints(true)
  do
    local minimapEnable = MakeModuleHeader(pages.minimap, "minimapbar")

    if db.minimapbar.locked == nil then
      db.minimapbar.locked = false
    end
    if not db.minimapbar.orientation then
      db.minimapbar.orientation = "VERTICAL"
    end
    if db.minimapbar.popoutAlpha == nil then
      db.minimapbar.popoutAlpha = 0.85
    end
    if db.minimapbar.popoutStay == nil then
      db.minimapbar.popoutStay = 2.0
    end

    local cards = BuildStandardModuleCards(pages.minimap)

    NS.OptionsPages.AttachModuleEnableToggle(minimapEnable, cards.general.content, ApplyToggleSkin)

    local lockCB = MakeCheckbox(cards.general.content, "Lock Bar", "Prevents dragging the minimap bar.")
    lockCB:SetPoint("TOPLEFT", 330, -4)
    lockCB:SetChecked(db.minimapbar.locked == true)
    lockCB:SetScript("OnClick", function()
      db.minimapbar.locked = lockCB:GetChecked()
      if NS.Modules and NS.Modules.minimapbar and NS.Modules.minimapbar.SetLocked then
        NS.Modules.minimapbar:SetLocked(db.minimapbar.locked, true)
      end
    end)
    ApplyToggleSkin(lockCB)

    local generalDivider = MakeAccentDivider(cards.general.content)
    generalDivider:SetPoint("TOPLEFT", 0, -40)
    generalDivider:SetPoint("TOPRIGHT", 0, -40)

    local alpha = BuildStandardSliderRow(
      cards.sizing.content,
      "Opacity",
      0.2,
      1.0,
      0.05,
      db.minimapbar.popoutAlpha or 0.85,
      "%.2f",
      Round2,
      function(v)
        db.minimapbar.popoutAlpha = v
        if NS.Modules and NS.Modules.minimapbar then
          if NS.Modules.minimapbar.ApplyPopoutAlpha then
            NS.Modules.minimapbar:ApplyPopoutAlpha()
          else
            NS:ApplyAll()
          end
        else
          NS:ApplyAll()
        end
      end
    )
    alpha:SetPoint("TOPLEFT", 6, -10)
    alpha:SetPoint("TOPRIGHT", -6, -10)

    local stay = BuildStandardSliderRow(
      cards.sizing.content,
      "Visibility",
      1,
      10,
      0.5,
      db.minimapbar.popoutStay or 2.0,
      "%.1f",
      Round2,
      function(v)
        db.minimapbar.popoutStay = v
      end
    )
    stay:SetPoint("TOPLEFT", alpha, "BOTTOMLEFT", 0, -14)
    stay:SetPoint("TOPRIGHT", alpha, "BOTTOMRIGHT", 0, -14)

    local visualsText = Small(cards.visuals.content, "Reserved for future Minimap visuals.")
    visualsText:SetPoint("TOPLEFT", 6, -10)
    visualsText:SetTextColor(0.78, 0.78, 0.80)

    local advancedText = Small(cards.advanced.content, "Reserved for future Minimap advanced options.")
    advancedText:SetPoint("TOPLEFT", 6, -10)
    advancedText:SetTextColor(0.78, 0.78, 0.80)
  end
end
