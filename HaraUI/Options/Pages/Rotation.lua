local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

function NS.OptionsPages.BuildRotationPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeButton, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)
  pages.rotation = CreateFrame("Frame", nil, content); pages.rotation:SetAllPoints(true)
  do
    if not db.rotationhelper then
      db.rotationhelper = {}
    end
    if db.rotationhelper.scale == nil then
      db.rotationhelper.scale = 1.0
    end
    if db.rotationhelper.width == nil then
      db.rotationhelper.width = 52
    end
    if db.rotationhelper.height == nil then
      db.rotationhelper.height = 52
    end

    local cards = BuildStandardModuleCards(pages.rotation)

    local preview = MakeButton(cards.general.content, "Preview", 170, 24)
    preview:SetPoint("TOPLEFT", 6, -4)
    NS.OptionsPages.SetModulePreviewOnClick(preview, "rotationhelper", NS)

    local generalDivider = MakeAccentDivider(cards.general.content)
    generalDivider:SetPoint("TOPLEFT", 0, -48)
    generalDivider:SetPoint("TOPRIGHT", 0, -48)

    local scale = BuildStandardSliderRow(
      cards.sizing.content,
      "Scale",
      0.6,
      2.0,
      0.05,
      db.rotationhelper.scale or 1.0,
      "%.2f",
      Round2,
      function(v)
        db.rotationhelper.scale = v
        NS:ApplyAll()
      end
    )
    scale:SetPoint("TOPLEFT", 6, -10)
    scale:SetPoint("TOPRIGHT", -6, -10)

    local width = BuildStandardSliderRow(
      cards.sizing.content,
      "Width",
      24,
      200,
      1,
      db.rotationhelper.width or 52,
      "%.0f",
      NS.OptionsPages.CoerceInt,
      function(v)
        db.rotationhelper.width = v
        NS:ApplyAll()
      end
    )
    width:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -14)
    width:SetPoint("TOPRIGHT", scale, "BOTTOMRIGHT", 0, -14)

    local height = BuildStandardSliderRow(
      cards.sizing.content,
      "Height",
      24,
      200,
      1,
      db.rotationhelper.height or 52,
      "%.0f",
      NS.OptionsPages.CoerceInt,
      function(v)
        db.rotationhelper.height = v
        NS:ApplyAll()
      end
    )
    height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, -14)
    height:SetPoint("TOPRIGHT", width, "BOTTOMRIGHT", 0, -14)

    local visualsText = Small(cards.visuals.content, "Reserved for future Rotation visuals.")
    visualsText:SetPoint("TOPLEFT", 6, -10)
    visualsText:SetTextColor(0.78, 0.78, 0.80)

    local advancedText = Small(cards.advanced.content, "Reserved for future Rotation advanced options.")
    advancedText:SetPoint("TOPLEFT", 6, -10)
    advancedText:SetTextColor(0.78, 0.78, 0.80)
  end
end
