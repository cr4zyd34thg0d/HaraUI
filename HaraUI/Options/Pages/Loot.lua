local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

function NS.OptionsPages.BuildLootPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeButton, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)
  pages.loot = CreateFrame("Frame", nil, content); pages.loot:SetAllPoints(true)
  do
    local cards = BuildStandardModuleCards(pages.loot)

    local preview = MakeButton(cards.general.content, "Preview Toasts", 170, 24)
    preview:SetPoint("TOPLEFT", 6, -4)
    NS.OptionsPages.SetModulePreviewOnClick(preview, "loot", NS)

    local generalDivider = MakeAccentDivider(cards.general.content)
    generalDivider:SetPoint("TOPLEFT", 0, -48)
    generalDivider:SetPoint("TOPRIGHT", 0, -48)

    local scale = BuildStandardSliderRow(
      cards.sizing.content,
      "Scale",
      0.6,
      1.5,
      0.05,
      db.loot.scale or 1.0,
      "%.2f",
      Round2,
      function(v)
        db.loot.scale = v
        NS:ApplyAll()
      end
    )
    scale:SetPoint("TOPLEFT", 6, -10)
    scale:SetPoint("TOPRIGHT", -6, -10)

    local duration = BuildStandardSliderRow(
      cards.sizing.content,
      "Duration",
      1.0,
      8.0,
      0.5,
      db.loot.duration or 3.5,
      "%.1f",
      Round2,
      function(v)
        db.loot.duration = v
        NS:ApplyAll()
      end
    )
    duration:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -14)
    duration:SetPoint("TOPRIGHT", scale, "BOTTOMRIGHT", 0, -14)

    local visualsText = Small(cards.visuals.content, "Reserved for future Loot visuals.")
    visualsText:SetPoint("TOPLEFT", 6, -10)
    visualsText:SetTextColor(0.78, 0.78, 0.80)

    local advancedText = Small(cards.advanced.content, "Reserved for future Loot advanced options.")
    advancedText:SetPoint("TOPLEFT", 6, -10)
    advancedText:SetTextColor(0.78, 0.78, 0.80)
  end
end
