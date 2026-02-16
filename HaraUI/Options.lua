--[[
  HaraUI Options Panel

  Structure:
    - Theme System & UI Helpers (lines 16-364)
    - Options Panel Initialization (lines 370+)
      - General Page
      - XP/Rep Bar Page
      - Cast Bar Page
      - Loot Toasts Page
      - Friendly Nameplates Page
      - Rotation Helper Page
      - Minimap Bar Page
      - Game Menu Page
--]]

local ADDON, NS = ...

local function GetAddonMetadataField(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, field)
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, field)
  end
  return nil
end

local DEV_VERSION = "2.0.2-dev"
local VERSION_TOKEN = "@project-version@"

local function GetVersionString()
  if NS and NS.GetVersionString then
    return NS.GetVersionString()
  end

  local version = GetAddonMetadataField("Version")
  if type(version) ~= "string" or version == "" then
    return DEV_VERSION
  end
  if version:find(VERSION_TOKEN, 1, true) then
    return DEV_VERSION
  end
  return version
end

local function GetVersionStatus(info)
  if NS and NS.GetVersionStatus then
    return NS.GetVersionStatus(info)
  end
  if type(info) ~= "table" then return "unknown" end
  local cmp = info.cmp
  if cmp ~= nil then
    if cmp < 0 then return "out-of-date" end
    if cmp > 0 then return "ahead" end
    if cmp == 0 then return "up-to-date" end
  end
  return "unknown"
end

local function GetVersionInfo()
  if NS and NS.GetVersionInfo then
    return NS.GetVersionInfo()
  end
  local installed = GetVersionString()
  local latest = installed
  local cmp = nil
  local status = GetVersionStatus({
    cmp = cmp,
  })
  return {
    installed = installed,
    latest = latest,
    cmp = cmp,
    status = status,
    source = "local-metadata",
    authoritative = false,
  }
end

local Theme = NS.OptionsTheme or {}
local Widgets = NS.OptionsWidgets or {}
local Pages = NS.OptionsPages or {}

local ORANGE = Theme.ORANGE
local ORANGE_SIZE = Theme.ORANGE_SIZE
local RegisterTheme = Theme.RegisterTheme
local ApplyThemeToRegistry = Theme.ApplyThemeToRegistry
local SetThemeColor = Theme.SetThemeColor
local GetUIFontPath = Theme.GetUIFontPath
local SetUIFont = Theme.SetUIFont
local ApplyUIFont = Theme.ApplyUIFont
local ApplyDropdownFont = Theme.ApplyDropdownFont
local ApplyDarkBackdrop = Widgets.ApplyDarkBackdrop
local MakeGlassCard = Widgets.MakeGlassCard
local MakeAccentDivider = Widgets.MakeAccentDivider
local Title = Widgets.Title
local Small = Widgets.Small
local MakeButton = Widgets.MakeButton
local MakeCheckbox = Widgets.MakeCheckbox
local ApplyToggleSkin = Widgets.ApplyToggleSkin
local MakeSlider = Widgets.MakeSlider
local Round2 = Widgets.Round2
local MakeColorSwatch = Widgets.MakeColorSwatch
local MakeValueChip = Widgets.MakeValueChip

-- =========================================================
-- =========================================================
--                   OPTIONS PANEL MAIN
-- =========================================================
-- =========================================================

function NS:InitOptions()
  local db = NS:GetDB()
  if not db then return end

  local function BuildFullUI(panel)
    -- Reset registries instead of appending to prevent memory growth
    NS._huiFontRegistry = {}
    NS._huiThemeRegistry = {}

    local UpdateNavIndicators = function() end

    if db and db.general then
      if not db.general.themeColor then
        db.general.themeColor = { r = ORANGE[1], g = ORANGE[2], b = ORANGE[3] }
      end
      SetThemeColor(db.general.themeColor.r, db.general.themeColor.g, db.general.themeColor.b)
    end
    ApplyDarkBackdrop(panel)

    -- Modern grey/orange theme
    -- Fully transparent backdrop so only the two panels are visible.
    panel.bg:SetColorTexture(0, 0, 0, 0)
    -- Remove outer border so each panel has its own rounded border.
    panel.border:SetBackdropBorderColor(0, 0, 0, 0)

    local function ApplyCharacterGradient(frame, baseTex)
      if not frame or not baseTex then return end
      baseTex:SetColorTexture(0, 0, 0, 0.90)

      local g = frame._huiCharacterGradient
      if not g then
        g = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame._huiCharacterGradient = g
      end
      g:SetAllPoints(baseTex)
      g:SetTexture("Interface/Buttons/WHITE8x8")

      -- Match Character Sheet black -> purple panel gradient.
      if g.SetGradient and CreateColor then
        g:SetGradient(
          "VERTICAL",
          CreateColor(0, 0, 0, 0.90),
          CreateColor(0.08, 0.02, 0.12, 0.90)
        )
      elseif g.SetGradientAlpha then
        g:SetGradientAlpha("VERTICAL", 0, 0, 0, 0.90, 0.08, 0.02, 0.12, 0.90)
      else
        g:SetColorTexture(0.08, 0.02, 0.12, 0.90)
      end
    end

    local nav = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", 0, 0)
    nav:SetWidth(200)
    ApplyDarkBackdrop(nav)
    ApplyCharacterGradient(nav, nav.bg)
    nav.border:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    RegisterTheme(function(c)
      if nav.border and nav.border.SetBackdropBorderColor then
        nav.border:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
      end
    end)

    local navHeader = CreateFrame("Frame", nil, nav, "BackdropTemplate")
    navHeader:SetPoint("TOPLEFT", 0, 0)
    navHeader:SetPoint("TOPRIGHT", -2, 0)
    navHeader:SetHeight(72)
    navHeader:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8x8",
      edgeFile = "Interface/Buttons/WHITE8x8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    -- Match header tone to the black/purple nav panel.
    navHeader:SetBackdropColor(0, 0, 0, 0.90)
    navHeader:SetBackdropBorderColor(0, 0, 0, 0)
    local navHeaderGradient = navHeader:CreateTexture(nil, "BACKGROUND", nil, 1)
    navHeaderGradient:SetAllPoints()
    navHeaderGradient:SetTexture("Interface/Buttons/WHITE8x8")
    if navHeaderGradient.SetGradient and CreateColor then
      navHeaderGradient:SetGradient(
        "VERTICAL",
        CreateColor(0, 0, 0, 0.90),
        CreateColor(0.08, 0.02, 0.12, 0.90)
      )
    elseif navHeaderGradient.SetGradientAlpha then
      navHeaderGradient:SetGradientAlpha("VERTICAL", 0, 0, 0, 0.90, 0.08, 0.02, 0.12, 0.90)
    else
      navHeaderGradient:SetColorTexture(0.08, 0.02, 0.12, 0.90)
    end

    -- Line under logo to match settings pages (inset, lower).
    local navLine = nav:CreateTexture(nil, "OVERLAY")
    navLine:SetPoint("TOPLEFT", 18, -80)
    navLine:SetPoint("TOPRIGHT", -18, -80)
    navLine:SetHeight(2)
    navLine:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    RegisterTheme(function(c)
      if navLine and navLine.SetColorTexture then
        navLine:SetColorTexture(c[1], c[2], c[3], 0.8)
      end
    end)

    local navVersion = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    navVersion:SetPoint("BOTTOMRIGHT", -12, 10)
    navVersion:SetJustifyH("RIGHT")
    ApplyUIFont(navVersion, 10, "OUTLINE", ORANGE)

    local navGitIndicator = nav:CreateTexture(nil, "OVERLAY")
    navGitIndicator:SetSize(10, 10)
    navGitIndicator:SetPoint("RIGHT", navVersion, "LEFT", -6, 0)
    if navGitIndicator.EnableMouse then
      navGitIndicator:EnableMouse(true)
    end
    if navGitIndicator.SetScript then
      navGitIndicator:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local info = GetVersionInfo()
        local status = (info and (info.status or GetVersionStatus(info))) or "unknown"
        local source = tostring(info and info.source or "unknown")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Version Status", ORANGE[1], ORANGE[2], ORANGE[3])
        GameTooltip:AddLine(("Installed: %s"):format(tostring(info and info.installed or "unknown")), 0.95, 0.95, 0.95)
        GameTooltip:AddLine(("Latest: %s"):format(tostring(info and info.latest or "n/a")), 0.95, 0.95, 0.95)
        if info and info.peerName then
          GameTooltip:AddLine(("Peer: %s"):format(tostring(info.peerName)), 0.85, 0.85, 0.85)
        end
        if status == "out-of-date" then
          GameTooltip:AddLine("Status: Update available", 1.0, 0.35, 0.35)
        elseif status == "ahead" then
          GameTooltip:AddLine("Status: Local build is ahead", 0.95, 0.80, 0.35)
        elseif status == "up-to-date" then
          GameTooltip:AddLine("Status: Up to date", 0.35, 1.0, 0.45)
        else
          GameTooltip:AddLine("Status: Unknown", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(("Source: %s"):format(source), 0.7, 0.7, 0.7)
        if not (info and info.authoritative) then
          GameTooltip:AddLine("Waiting for peer version data.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
      end)
      navGitIndicator:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end

    local function UpdateVersionIndicator()
      local info = GetVersionInfo()
      local installed = info and info.installed or nil
      local status = (info and (info.status or GetVersionStatus(info))) or "unknown"

      navVersion:SetText(tostring(installed or DEV_VERSION))

      navGitIndicator:Show()
      if status == "out-of-date" then
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
      elseif status == "ahead" then
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Away")
      elseif status == "up-to-date" then
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
      else
        navGitIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Away")
      end
    end

    UpdateVersionIndicator()
    if NS and NS.RegisterVersionInfoListener then
      NS:RegisterVersionInfoListener(UpdateVersionIndicator)
    end

    local content = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    -- Left pane removed: content fills the full options window.
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    ApplyDarkBackdrop(content)
    -- Match the left nav panel black/purple gradient.
    ApplyCharacterGradient(content, content.bg)
    content.border:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    RegisterTheme(function(c)
      if content.border and content.border.SetBackdropBorderColor then
        content.border:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
      end
    end)

    -- Move logo into the header lane of the right panel.
    local rightLogo = content:CreateTexture(nil, "OVERLAY")
    rightLogo:SetSize(170, 56)
    rightLogo:SetTexCoord(0, 1, 0, 1)
    rightLogo:SetTexture("Interface\\AddOns\\HaraUI\\Media\\logo.tga")
    rightLogo:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    rightLogo:SetPoint("TOPRIGHT", content, "TOPRIGHT", -46, -20)
    RegisterTheme(function(c)
      if rightLogo and rightLogo.SetVertexColor then
        rightLogo:SetVertexColor(c[1], c[2], c[3], 1)
      end
    end)

    local rightLogoCaps = content:CreateTexture(nil, "OVERLAY", nil, 1)
    rightLogoCaps:SetPoint("TOPLEFT", rightLogo, "TOPLEFT", 0, 0)
    rightLogoCaps:SetPoint("BOTTOMRIGHT", rightLogo, "BOTTOMRIGHT", 0, 0)
    rightLogoCaps:SetTexCoord(0, 1, 0, 1)
    rightLogoCaps:SetTexture("Interface\\AddOns\\HaraUI\\Media\\logoCaps.tga")

    -- Version text under logo, right-aligned.
    navVersion:SetParent(content)
    navVersion:ClearAllPoints()
    navVersion:SetPoint("TOPRIGHT", rightLogo, "BOTTOMRIGHT", -8, 4)
    navGitIndicator:SetParent(content)
    navGitIndicator:ClearAllPoints()
    navGitIndicator:SetPoint("RIGHT", navVersion, "LEFT", -6, 0)
    nav:Hide()

    local pages = {}
    local function ShowPage(key)
      for k, p in pairs(pages) do
        p:SetShown(k == key)
      end
    end

    local BuildGeneralPageCards = Pages.CreateBuildGeneralPageCards(
      db,
      ORANGE,
      MakeCheckbox,
      NS,
      function()
        UpdateNavIndicators()
      end,
      ApplyToggleSkin,
      MakeAccentDivider,
      MakeButton,
      MakeColorSwatch,
      SetThemeColor,
      Small
    )

    local function MakeModuleHeader(page, key)
      local en = MakeCheckbox(page, "Enable Module", "Enable or disable this module.")
      en:SetPoint("TOPLEFT", 18, -96)
      en:SetChecked(db[key] and db[key].enabled)
      en:SetScript("OnClick", function()
        db[key].enabled = en:GetChecked()
        NS:ApplyAll()
        UpdateNavIndicators()
      end)
      return en
    end

    local function BuildStandardSliderRow(parent, labelText, minv, maxv, step, initial, fmt, coerce, onValue)
      local row = CreateFrame("Frame", nil, parent)
      row:SetHeight(34)

      row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.label:SetPoint("LEFT", 0, 0)
      row.label:SetWidth(96)
      row.label:SetJustifyH("LEFT")
      row.label:SetText(labelText)
      ApplyUIFont(row.label, 12, "OUTLINE", { 0.93, 0.93, 0.95 })

      local slider = MakeSlider(row, labelText, minv, maxv, step)
      if slider.Label then slider.Label:Hide() end
      if slider.Text then slider.Text:Hide() end
      slider:ClearAllPoints()
      slider:SetWidth(330)
      slider:SetPoint("LEFT", row.label, "RIGHT", 10, 0)

      local initialValue = coerce and coerce(initial) or initial
      slider:SetValue(initialValue)

      local chip = MakeValueChip(row, 62, 20)
      chip:SetPoint("LEFT", slider, "RIGHT", 14, 0)
      chip:SetValue(initialValue, fmt)

      slider:SetScript("OnValueChanged", function(_, raw)
        local value = coerce and coerce(raw) or raw
        chip:SetValue(value, fmt)
        onValue(value)
      end)

      row.slider = slider
      row.chip = chip
      return row
    end

    local function BuildStandardModuleCards(page)
      local tabOrder = { "general", "sizing", "visuals", "advanced" }
      local tabLabels = {
        general = "General",
        sizing = "Sizing",
        visuals = "Visuals",
        advanced = "Advanced",
      }

      local tabRow = CreateFrame("Frame", nil, page)
      tabRow:SetPoint("TOPLEFT", 18, -96)
      tabRow:SetPoint("TOPRIGHT", -18, -96)
      tabRow:SetHeight(26)

      local tabDivider = MakeAccentDivider(page)
      tabDivider:SetPoint("TOPLEFT", tabRow, "BOTTOMLEFT", 0, -4)
      tabDivider:SetPoint("TOPRIGHT", tabRow, "BOTTOMRIGHT", 0, -4)

      local cards = {
        general = MakeGlassCard(page, "General"),
        sizing = MakeGlassCard(page, "Sizing"),
        visuals = MakeGlassCard(page, "Visuals"),
        advanced = MakeGlassCard(page, "Advanced"),
      }

      for _, card in pairs(cards) do
        card:SetPoint("TOPLEFT", 18, -136)
        card:SetPoint("TOPRIGHT", -18, -136)
        card:SetPoint("BOTTOMLEFT", 18, 18)
        card:SetPoint("BOTTOMRIGHT", -18, 18)
      end

      local tabs = {}

      local function ApplyTabStyle(btn, selected)
        if selected then
          btn:SetBackdropColor(0.16, 0.13, 0.09, 0.94)
          btn:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.92)
          btn.label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
          btn.accent:Show()
        else
          btn:SetBackdropColor(0.08, 0.09, 0.11, 0.82)
          btn:SetBackdropBorderColor(0.54, 0.56, 0.62, 0.28)
          btn.label:SetTextColor(0.86, 0.86, 0.89)
          btn.accent:Hide()
        end
      end

      local function ShowTab(key)
        if not cards[key] then key = "general" end
        for cardKey, card in pairs(cards) do
          card:SetShown(cardKey == key)
        end
        for tabKey, tab in pairs(tabs) do
          tab._selected = (tabKey == key)
          ApplyTabStyle(tab, tab._selected)
        end
      end

      local previous
      for _, key in ipairs(tabOrder) do
        local tabKey = key
        local tab = CreateFrame("Button", nil, tabRow, "BackdropTemplate")
        tab:SetSize(110, 24)
        if previous then
          tab:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
          tab:SetPoint("LEFT", tabRow, "LEFT", 0, 0)
        end
        tab:SetBackdrop({
          bgFile = "Interface/Buttons/WHITE8x8",
          edgeFile = "Interface/Buttons/WHITE8x8",
          edgeSize = 1,
          insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })

        tab.accent = tab:CreateTexture(nil, "OVERLAY")
        tab.accent:SetPoint("BOTTOMLEFT", 5, 1)
        tab.accent:SetPoint("BOTTOMRIGHT", -5, 1)
        tab.accent:SetHeight(1)
        tab.accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.95)
        RegisterTheme(function(c)
          if tab.accent and tab.accent.SetColorTexture then
            tab.accent:SetColorTexture(c[1], c[2], c[3], 0.95)
          end
          ApplyTabStyle(tab, tab._selected)
        end)

        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tab.label:SetPoint("CENTER", 0, 0)
        tab.label:SetText(tabLabels[tabKey] or tabKey)
        ApplyUIFont(tab.label, 11, "OUTLINE", { 0.86, 0.86, 0.89 })

        tab:SetScript("OnEnter", function(self)
          if self._selected then return end
          self:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.58)
          self.label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
        end)
        tab:SetScript("OnLeave", function(self)
          if self._selected then return end
          ApplyTabStyle(self, false)
        end)
        tab:SetScript("OnClick", function()
          ShowTab(tabKey)
        end)

        tabs[tabKey] = tab
        previous = tab
      end

      ShowTab("general")
      return cards, ShowTab, tabs
    end

  -- =========================================================
  -- GENERAL PAGE
  -- =========================================================
    Pages.BuildGeneralPage(pages, content, BuildStandardModuleCards, BuildGeneralPageCards)

  -- =========================================================
  -- XP / REP BAR PAGE
  -- =========================================================
    Pages.BuildXPPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, MakeButton, NS, ApplyToggleSkin, MakeCheckbox, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)

  -- =========================================================
  -- CAST BAR PAGE
  -- =========================================================
    Pages.BuildCastPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeButton, MakeAccentDivider, BuildStandardSliderRow, Round2, MakeColorSwatch, ApplyUIFont, ORANGE_SIZE, ORANGE, ApplyDropdownFont, RegisterTheme, Small, db)

  -- =========================================================
  -- LOOT TOASTS PAGE
  -- =========================================================
    Pages.BuildLootPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeButton, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)

  -- =========================================================
  -- FRIENDLY NAMEPLATES PAGE
  -- =========================================================
    Pages.BuildFriendlyPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeAccentDivider, MakeColorSwatch, BuildStandardSliderRow, Small, db)

  -- =========================================================
  -- ROTATION HELPER PAGE
  -- =========================================================
    Pages.BuildRotationPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeButton, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)

  -- =========================================================
  -- MINIMAP BAR PAGE
  -- =========================================================
    Pages.BuildMinimapPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeAccentDivider, BuildStandardSliderRow, Round2, Small, db)

  -- =========================================================
  -- NAVIGATION MENU
  -- =========================================================
    local navItems = {
      { key = "general",  label = "General",              media = "General.png" },
      { key = "xp",       label = "XP / Rep Bar",         media = "XP_Rep_Bar.png" },
      { key = "cast",     label = "Cast Bar",             media = "Cast_Bar.png" },
      { key = "friendly", label = "Friendly Nameplates",  media = "Friendly_Nameplates.png" },
      { key = "rotation", label = "Rotation Helper",      media = "Rotation_Helper.png" },
      { key = "minimap",  label = "Minimap Bar",          media = "Minimap_Bar.png" },
      { key = "loot",     label = "Loot Toasts",          media = "Loot_Toasts.png" },
      { key = nil,        label = "",                     media = nil },
      { key = nil,        label = "",                     media = nil },
    }

    local navKeyToDb = {
      general = "general",
      xp = "xpbar",
      cast = "castbar",
      friendly = "friendlyplates",
      rotation = "rotationhelper",
      minimap = "minimapbar",
      loot = "loot",
    }

    local function IsNavEnabled(key)
      local dbKey = navKeyToDb[key]
      if not dbKey then return nil end
      if dbKey == "general" then
        return db.general and db.general.enabled ~= false
      end
      return db[dbKey] and db[dbKey].enabled ~= false
    end

    -- Single-row nav lives in the right content panel, left-aligned.
    local navGrid = CreateFrame("Frame", nil, content)
    navGrid:SetPoint("TOPLEFT", content, "TOPLEFT", 18, -26)
    navGrid:SetPoint("TOPRIGHT", content, "TOPRIGHT", -18, -26)
    navGrid:SetHeight(44)

    local function ApplyNavButtonState(btn)
      if not btn or btn._isPlaceholder then return end
      if btn._huiSelected then
        btn:SetBackdropColor(0.18, 0.08, 0.24, 0.88)
        btn:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.95)
        if btn.selectedGlow then btn.selectedGlow:Show() end
      else
        btn:SetBackdropColor(0.06, 0.07, 0.10, 0.82)
        if btn._huiEnabledState == true then
          btn:SetBackdropBorderColor(0.20, 0.88, 0.32, 0.90) -- enabled: green border
        elseif btn._huiEnabledState == false then
          btn:SetBackdropBorderColor(0.92, 0.22, 0.22, 0.90) -- disabled: red border
        else
          btn:SetBackdropBorderColor(0.52, 0.54, 0.60, 0.26)
        end
        if btn.selectedGlow then btn.selectedGlow:Hide() end
      end
    end

    local function SelectNavKey(key)
      if not key then return end
      ShowPage(key)
      for _, btn in ipairs(nav._huiButtons or {}) do
        btn._huiSelected = (btn._key == key)
        ApplyNavButtonState(btn)
      end
    end

    for idx, it in ipairs(navItems) do
      local navKey = it.key
      local b = CreateFrame("Button", nil, navGrid, "BackdropTemplate")
      b:SetSize(44, 44)
      b:SetPoint("LEFT", navGrid, "LEFT", (idx - 1) * 46, 0)
      b._key = it.key
      b._isPlaceholder = (it.key == nil)
      b._label = it.label

      b:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
      })

      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetPoint("TOPLEFT", 1, -1)
      b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      if it.media then
        b.icon:SetTexture("Interface\\AddOns\\HaraUI\\Media\\" .. it.media)
      else
        b.icon:SetTexture("Interface/Buttons/WHITE8x8")
        b.icon:SetColorTexture(0, 0, 0, 0.18)
      end

      b.selectedGlow = b:CreateTexture(nil, "OVERLAY")
      b.selectedGlow:SetPoint("TOPLEFT", 1, -1)
      b.selectedGlow:SetPoint("BOTTOMRIGHT", -1, 1)
      b.selectedGlow:SetTexture("Interface/Buttons/WHITE8x8")
      b.selectedGlow:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.12)
      b.selectedGlow:Hide()

      RegisterTheme(function(c)
        if b.selectedGlow and b.selectedGlow.SetColorTexture then
          b.selectedGlow:SetColorTexture(c[1], c[2], c[3], 0.12)
        end
        ApplyNavButtonState(b)
      end)

      if b._isPlaceholder then
        b:SetBackdropColor(0.02, 0.02, 0.03, 0.48)
        b:SetBackdropBorderColor(0.28, 0.30, 0.36, 0.18)
        b:Disable()
      else
        ApplyNavButtonState(b)
        b:SetScript("OnEnter", function(self)
          if not self._huiSelected then
            self:SetBackdropColor(0.12, 0.09, 0.16, 0.88)
            self:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.68)
          end
          if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._label, ORANGE[1], ORANGE[2], ORANGE[3])
            GameTooltip:Show()
          end
        end)
        b:SetScript("OnLeave", function(self)
          ApplyNavButtonState(self)
          if GameTooltip then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
          SelectNavKey(navKey)
        end)
      end

      nav._huiButtons = nav._huiButtons or {}
      table.insert(nav._huiButtons, b)
    end

    UpdateNavIndicators = function()
      if not nav._huiButtons then return end
      for _, btn in ipairs(nav._huiButtons) do
        if not btn._isPlaceholder then
          local enabled = IsNavEnabled(btn._key)
          btn._huiEnabledState = enabled
          ApplyNavButtonState(btn)
        end
      end
      UpdateVersionIndicator()
    end

    UpdateNavIndicators()

    SelectNavKey("general")

    RegisterTheme(function(c)
      if not nav._huiButtons then return end
      for _, btn in ipairs(nav._huiButtons) do
        ApplyNavButtonState(btn)
      end
    end)

    panel.refresh = function()
      if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    end
  end

  -- =========================================================
  -- POPOUT WINDOW
  -- =========================================================
  NS:BuildOptionsWindow(BuildFullUI, db)
end

