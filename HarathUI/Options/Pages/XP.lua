local ADDON, NS = ...

NS.OptionsPages = NS.OptionsPages or {}

function NS.OptionsPages.BuildXPPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, MakeButton, NS, ApplyToggleSkin, MakeCheckbox, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)
  pages.xp = CreateFrame("Frame", nil, content); pages.xp:SetAllPoints(true)
  do
    local xpEnable = MakeModuleHeader(pages.xp, "xpbar")

    local cards = BuildStandardModuleCards(pages.xp)

    -- General card controls.
    NS.OptionsPages.AttachModuleEnableToggle(xpEnable, cards.general.content, ApplyToggleSkin)

    local showAtMax = MakeCheckbox(cards.general.content, "Show Bar at Max Level", "Keep XP bar visible at max level.")
    showAtMax:SetPoint("TOPLEFT", 330, -4)
    showAtMax:SetChecked(db.xpbar.showAtMaxLevel)
    showAtMax:SetScript("OnClick", function()
      db.xpbar.showAtMaxLevel = showAtMax:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(showAtMax)

    local preview = MakeButton(cards.general.content, "Preview Bar", 170, 24)
    preview:SetPoint("TOPLEFT", 6, -40)
    preview:SetScript("OnClick", function()
      if NS.Modules and NS.Modules.xpbar and NS.Modules.xpbar.Preview then
        NS.Modules.xpbar:Preview()
      end
    end)

    local generalDivider = MakeAccentDivider(cards.general.content)
    generalDivider:SetPoint("TOPLEFT", 0, -84)
    generalDivider:SetPoint("TOPRIGHT", 0, -84)

    -- Sizing card controls.
    local scale = BuildStandardSliderRow(
      cards.sizing.content,
      "Scale",
      0.6,
      1.5,
      0.05,
      db.xpbar.scale or 1.0,
      "%.2f",
      Round2,
      function(v)
        db.xpbar.scale = v
        NS:ApplyAll()
      end
    )
    scale:SetPoint("TOPLEFT", 6, -10)
    scale:SetPoint("TOPRIGHT", -6, -10)

    local width = BuildStandardSliderRow(
      cards.sizing.content,
      "Length",
      200,
      800,
      10,
      db.xpbar.width or 520,
      "%.0f",
      NS.OptionsPages.CoerceInt,
      function(v)
        db.xpbar.width = v
        NS:ApplyAll()
      end
    )
    width:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -14)
    width:SetPoint("TOPRIGHT", scale, "BOTTOMRIGHT", 0, -14)

    local height = BuildStandardSliderRow(
      cards.sizing.content,
      "Height",
      6,
      26,
      1,
      db.xpbar.height or 12,
      "%.0f",
      NS.OptionsPages.CoerceInt,
      function(v)
        db.xpbar.height = v
        NS:ApplyAll()
      end
    )
    height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, -14)
    height:SetPoint("TOPRIGHT", width, "BOTTOMRIGHT", 0, -14)

    -- Visuals card controls.
    local showText = MakeCheckbox(cards.visuals.content, "Show Text", "Show exact progress numbers.")
    showText:SetPoint("TOPLEFT", 6, -10)
    showText:SetChecked(db.xpbar.showText)
    showText:SetScript("OnClick", function()
      db.xpbar.showText = showText:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(showText)

    local showRate = MakeCheckbox(cards.visuals.content, "TTL & Exp P/h", "Show ETA and XP per hour.")
    showRate:SetPoint("TOPLEFT", 330, -10)
    showRate:SetChecked(db.xpbar.showRateText)
    showRate:SetScript("OnClick", function()
      db.xpbar.showRateText = showRate:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(showRate)

    local showSession = MakeCheckbox(cards.visuals.content, "Session Time", "Show time played this session.")
    showSession:SetPoint("TOPLEFT", 6, -46)
    showSession:SetChecked(db.xpbar.showSessionTime)
    showSession:SetScript("OnClick", function()
      db.xpbar.showSessionTime = showSession:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(showSession)

    local showQuest = MakeCheckbox(cards.visuals.content, "Quest Exp", "Show completed quests and rested text.")
    showQuest:SetPoint("TOPLEFT", 330, -46)
    showQuest:SetChecked(db.xpbar.showQuestText)
    showQuest:SetScript("OnClick", function()
      db.xpbar.showQuestText = showQuest:GetChecked()
      NS:ApplyAll()
    end)
    ApplyToggleSkin(showQuest)

    -- Advanced placeholder card.
    local advancedText = Small(cards.advanced.content, "Reserved for future XP / Rep options.")
    advancedText:SetPoint("TOPLEFT", 6, -10)
    advancedText:SetTextColor(0.78, 0.78, 0.80)

  end
end
