--[[
  XP Bar Module

  Interface:
    M:Apply()        - Initialize/update with current settings
    M:Disable()      - Clean up and hide
    M:SetLocked()    - Toggle drag mode
    M:Preview()      - Show preview state

  Events Registered:
    - PLAYER_XP_UPDATE
    - UPDATE_EXHAUSTION
    - PLAYER_LEVEL_UP
    - UPDATE_FACTION
    - QUEST_LOG_UPDATE
    - QUEST_LOG_CRITERIA_UPDATE
--]]

local ADDON, NS = ...
local M = {}
NS:RegisterModule("xpbar", M)
M.active = false

local bar
local previewActive = false
local sessionStart
local sessionStartXP
local cachedQuestXP = 0
local questDirty = true
local updateTimer
local UPDATE_INTERVAL = 1
local hideBlizzardTicker
local hideBlizzardHooked = false

-- Cache color codes for performance (avoid string creation in hot paths)
local QUEST_COLOR = NS.THEME.QUEST_COLOR
local RESTED_COLOR = NS.THEME.RESTED_COLOR
local COLOR_END = NS.THEME.COLOR_END

local function ApplyBarFont(fontString, size)
  if not fontString then return end
  NS:ApplyDefaultFont(fontString, size)
end

local function HideBlizzardXPTrackingBars()
  local candidates = {
    "MainMenuExpBar",
    "MainMenuBarExpBar",
    "MainMenuXPBar",
    "MainMenuBarMaxLevelBar",
    "ReputationWatchBar",
    "HonorWatchBar",
    "ArtifactWatchBar",
    "AzeriteBar",
    "StatusTrackingBarManager",
    "MainStatusTrackingBarContainer",
    "MainStatusTrackingBarContainer.BarFrame",
  }

  for _, key in ipairs(candidates) do
    local frame = _G[key]
    if not frame and key:find("%.", 1, true) then
      local root, child = key:match("^([^.]+)%.(.+)$")
      local parent = root and _G[root]
      frame = parent and parent[child]
    end
    if frame then
      if frame.SetAlpha then frame:SetAlpha(0) end
      if frame.EnableMouse then frame:EnableMouse(false) end
      if frame.Hide then frame:Hide() end
    end
  end
end

local function Create()
  bar = CreateFrame("StatusBar", nil, UIParent, "BackdropTemplate")
  bar:SetSize(520, 12)
  bar:SetStatusBarTexture(NS.TEXTURES.STATUSBAR)
  bar:SetMinMaxValues(0, 1)

  local bgColor = NS.THEME.BG_DARK
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(true)
  bar.bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

  bar.overlay = CreateFrame("StatusBar", nil, bar)
  bar.overlay:SetAllPoints(true)
  bar.overlay:SetStatusBarTexture(NS.TEXTURES.STATUSBAR)
  bar.overlay:SetMinMaxValues(0, 1)
  bar.overlay:SetFrameLevel(bar:GetFrameLevel() - 1)

  local questColor = NS.XPBAR_COLORS.QUEST
  bar.questTex = bar:CreateTexture(nil, "ARTWORK")
  bar.questTex:SetTexture(NS.TEXTURES.STATUSBAR)
  bar.questTex:SetVertexColor(questColor.r, questColor.g, questColor.b, questColor.a)
  bar.questTex:Hide()

  local restedColor = NS.XPBAR_COLORS.RESTED
  bar.restedTex = bar:CreateTexture(nil, "ARTWORK")
  bar.restedTex:SetTexture(NS.TEXTURES.STATUSBAR)
  bar.restedTex:SetVertexColor(restedColor.r, restedColor.g, restedColor.b, restedColor.a)
  bar.restedTex:Hide()

  bar.levelText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.levelText:SetPoint("LEFT", 8, 0)
  ApplyBarFont(bar.levelText, 12)

  bar.xpText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.xpText:SetPoint("CENTER")
  ApplyBarFont(bar.xpText, 12)

  bar.pctText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.pctText:SetPoint("RIGHT", -8, 0)
  ApplyBarFont(bar.pctText, 12)

  bar.detailText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.detailText:SetPoint("TOP", bar, "BOTTOM", 0, -4)
  ApplyBarFont(bar.detailText, 10)

  bar.sessionText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.sessionText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -4)
  ApplyBarFont(bar.sessionText, 10)

  bar.rateText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.rateText:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -2, -4)
  ApplyBarFont(bar.rateText, 10)

  bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 80)

  NS:MakeMovable(bar, "xpbar", "XP/Rep Bar (drag)")
end

local function GetCompletedQuestXP()
  if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not GetQuestLogRewardXP then
    return 0
  end
  local total = 0
  local numEntries = C_QuestLog.GetNumQuestLogEntries()
  for i = 1, numEntries do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID then
      local isComplete = C_QuestLog.IsComplete(info.questID)
      local ready = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(info.questID)
      if ready or isComplete == true or (type(isComplete) == "number" and isComplete > 0) then
        local index = info.questLogIndex or i
        local xp = GetQuestLogRewardXP(index)
        if xp and xp > 0 then
          total = total + xp
        end
      end
    end
  end
  return total
end

local function UpdateSegments(cur, max, questXP, restedXP)
  local width = bar:GetWidth()
  local curPct = (max > 0) and math.min(cur / max, 1) or 0
  local questPct = (max > 0) and math.max(0, questXP / max) or 0
  local restedPct = (max > 0) and math.max(0, restedXP / max) or 0

  local curWidth = width * curPct
  local questWidth = width * questPct
  local restedWidth = width * restedPct

  bar.questTex:ClearAllPoints()
  bar.restedTex:ClearAllPoints()

  if questWidth > 0 then
    bar.questTex:SetPoint("LEFT", bar, "LEFT", curWidth, 0)
    bar.questTex:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.questTex:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.questTex:SetWidth(math.min(width - curWidth, questWidth))
    bar.questTex:Show()
  else
    bar.questTex:Hide()
  end

  if restedWidth > 0 then
    local offset = curWidth + questWidth
    bar.restedTex:SetPoint("LEFT", bar, "LEFT", offset, 0)
    bar.restedTex:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.restedTex:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.restedTex:SetWidth(math.min(width - offset, restedWidth))
    bar.restedTex:Show()
  else
    bar.restedTex:Hide()
  end
end

local function FormatTime(seconds)
  if not seconds or seconds < 0 then return "00:00" end
  local hours = math.floor(seconds / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  if hours > 0 then
    return string.format("%d:%02d", hours, mins)
  end
  return string.format("%d:%02d", mins, math.floor(seconds % 60))
end

local function WatchedReputationInfo()
  if C_Reputation and C_Reputation.GetWatchedFactionData then
    local data = C_Reputation.GetWatchedFactionData()
    if data and data.name and data.max and data.min then
      return data
    end
  end
  return nil
end

local function GetQuestXP(force)
  if force or questDirty then
    cachedQuestXP = GetCompletedQuestXP()
    questDirty = false
  end
  return cachedQuestXP
end

local function IsFramesUnlocked(db)
  return db and db.general and db.general.framesLocked == false
end

local function ShowUnlockPlaceholder()
  if not bar then return end
  bar._huiUnlockPlaceholder = true
  bar:SetValue(0)
  bar.overlay:SetValue(0)
  UpdateSegments(0, 1, 0, 0)
  bar.levelText:SetText("XP / Rep Bar")
  bar.xpText:SetText("")
  bar.pctText:SetText("")
  bar.detailText:SetText("")
  bar.sessionText:SetText("")
  bar.rateText:SetText("")
  bar:Show()
end

local function Update(forceQuest)
  if not bar then return end
  local db = NS:GetDB()
  if not db or not db.xpbar.enabled then return end

  if previewActive then
    -- Toggle preview state from the options button.
    bar._huiUnlockPlaceholder = nil
    bar:SetValue(0.658)
    bar.overlay:SetValue(0)
    UpdateSegments(0.658, 1, 0.048, 0.064)
    if db.xpbar.showText then
      bar.levelText:SetText("Level 57")
      bar.xpText:SetText("204931 / 311490")
      bar.pctText:SetText("65.8% (70.6%)")
      if db.xpbar.showQuestText ~= false then
        bar.detailText:SetText("Completed Quests: |cffffa11a4.8%|r - Rested: |cff5aa0ff6.4%|r")
      else
        bar.detailText:SetText("")
      end
      if db.xpbar.showSessionTime then
        bar.sessionText:SetText("Session: 0:22")
      else
        bar.sessionText:SetText("")
      end
      if db.xpbar.showRateText then
      bar.rateText:SetText("ETA 1h12m - 52k/hr")
      else
        bar.rateText:SetText("")
      end
    else
      bar.levelText:SetText("")
      bar.xpText:SetText("")
      bar.pctText:SetText("")
      bar.detailText:SetText("")
      bar.sessionText:SetText("")
      bar.rateText:SetText("")
    end
    bar:Show()
    return
  end

  local unlocked = IsFramesUnlocked(db)
  local level = UnitLevel("player")
  local xpMax = UnitXPMax("player") or 0
  local atMaxLevel = (xpMax == 0) or (level >= 80)

  if atMaxLevel then
    if not db.xpbar.showAtMaxLevel then
      if unlocked then
        ShowUnlockPlaceholder()
      else
        bar._huiUnlockPlaceholder = nil
        bar:Hide()
      end
      return
    end

    local rep = WatchedReputationInfo()
    if rep then
      bar._huiUnlockPlaceholder = nil
      local cur = (rep.currentStanding or 0) - (rep.min or 0)
      local max = (rep.max or 1) - (rep.min or 0)
      local pct = (max > 0) and (cur / max) or 0

      bar:SetValue(pct)
      bar.overlay:SetValue(0)
      UpdateSegments(cur, max, 0, 0)

      if db.xpbar.showText then
        bar.levelText:SetText(rep.name or "Reputation")
        bar.xpText:SetText(("%d / %d"):format(cur, max))
        bar.pctText:SetText(("%.1f%%"):format(pct * 100))
        bar.detailText:SetText("")
      else
        bar.levelText:SetText("")
        bar.xpText:SetText("")
        bar.pctText:SetText("")
        bar.detailText:SetText("")
      end
      bar:Show()
      return
    end

    if db.xpbar.hideAtMaxIfNoRep and not db.xpbar.showAtMaxLevel then
      if unlocked then
        ShowUnlockPlaceholder()
      else
        bar._huiUnlockPlaceholder = nil
        bar:Hide()
      end
      return
    end

    bar._huiUnlockPlaceholder = nil
    if db.xpbar.showAtMaxLevel then
      bar:SetValue(1)
    else
      bar:SetValue(0)
    end
    bar.overlay:SetValue(0)
    UpdateSegments(0, 1, 0, 0)
    if db.xpbar.showText then
      bar.levelText:SetText("Max Level")
      bar.xpText:SetText("")
      bar.pctText:SetText("")
      bar.detailText:SetText("")
      bar.sessionText:SetText("")
      bar.rateText:SetText("")
    else
      bar.levelText:SetText("")
      bar.xpText:SetText("")
      bar.pctText:SetText("")
      bar.detailText:SetText("")
      bar.sessionText:SetText("")
      bar.rateText:SetText("")
    end
    bar:Show()
    return
  end

  bar._huiUnlockPlaceholder = nil
  local cur = UnitXP("player")
  local max = xpMax
  local pct = (max > 0) and (cur / max) or 0
  bar:SetValue(pct)

  local rested = GetXPExhaustion()
  local restedPct = 0
  if rested and max > 0 then restedPct = math.min(1, (cur + rested) / max) end
  bar.overlay:SetValue(restedPct)

  local questXP = GetQuestXP(forceQuest)
  UpdateSegments(cur, max, questXP, rested or 0)

  if db.xpbar.showText then
    local totalPct = math.min(1, (cur + (rested or 0) + questXP) / max)
    bar.levelText:SetText(("Level %d"):format(level))
    bar.xpText:SetText(("%d / %d"):format(cur, max))
    bar.pctText:SetText(("%.1f%% (%.1f%%)"):format(pct * 100, totalPct * 100))
    local questPct = (questXP > 0 and max > 0) and (questXP / max * 100) or 0
    local restedPctNum = (rested and max > 0) and (rested / max * 100) or 0
    if db.xpbar.showQuestText ~= false then
      bar.detailText:SetText(("Completed Quests: %s%.1f%%%s - Rested: %s%.1f%%%s"):format(
        QUEST_COLOR, questPct, COLOR_END,
        RESTED_COLOR, restedPctNum, COLOR_END
      ))
    else
      bar.detailText:SetText("")
    end
    if db.xpbar.showSessionTime then
      local elapsed = GetTime() - (sessionStart or GetTime())
      bar.sessionText:SetText(("Session: %s"):format(FormatTime(elapsed)))
    else
      bar.sessionText:SetText("")
    end
    if db.xpbar.showRateText then
      local elapsed = GetTime() - (sessionStart or GetTime())
      if sessionStartXP == nil then
        sessionStartXP = cur
      end
      if cur < sessionStartXP then
        sessionStartXP = cur
        sessionStart = GetTime()
      end
      local xpGained = math.max(0, cur - sessionStartXP)
      local rate = (elapsed > 0) and (xpGained / elapsed) * 3600 or 0
      local remaining = max - cur
      local eta = (rate > 0) and (remaining / rate) or 0
      bar.rateText:SetText(("ETA %s - %s/hr"):format(FormatTime(eta), AbbreviateLargeNumbers(math.floor(rate + 0.5))))
    else
      bar.rateText:SetText("")
    end
  else
    bar.levelText:SetText("")
    bar.xpText:SetText("")
    bar.pctText:SetText("")
    bar.detailText:SetText("")
    bar.sessionText:SetText("")
    bar.rateText:SetText("")
  end

  bar:Show()
end

local function ShouldRealtimeUpdate(db)
  return db and db.xpbar.enabled and (db.xpbar.showSessionTime or db.xpbar.showRateText)
end

function M:SetLocked(locked)
  if not M.active or not bar or not bar._huiMover then return end
  if locked then
    bar:EnableMouse(false)
    bar._huiMover:Hide()
    if bar._huiUnlockPlaceholder then
      bar._huiUnlockPlaceholder = nil
      Update(false)
    end
  else
    bar:EnableMouse(true)
    bar._huiMover:Show()
    if not bar:IsShown() then
      ShowUnlockPlaceholder()
    end
  end
end

function M:Apply()
  local db = NS:GetDB()
  if not db or not db.xpbar or not db.xpbar.enabled then
    self:Disable()
    return
  end
  M.active = true
  if not bar then Create() end

  -- Refresh fonts when settings change
  if bar then
    ApplyBarFont(bar.levelText, 12)
    ApplyBarFont(bar.xpText, 12)
    ApplyBarFont(bar.pctText, 12)
    ApplyBarFont(bar.detailText, 10)
    ApplyBarFont(bar.sessionText, 10)
    ApplyBarFont(bar.rateText, 10)
  end

  if db.xpbar.hideAtMaxIfNoRep == nil then
    db.xpbar.hideAtMaxIfNoRep = true
  end
  if db.xpbar.showSessionTime == nil then
    db.xpbar.showSessionTime = false
  end
  if db.xpbar.showRateText == nil then
    db.xpbar.showRateText = false
  end
  if db.xpbar.showQuestText == nil then
    db.xpbar.showQuestText = true
  end
  if db.xpbar.showAtMaxLevel == nil then
    db.xpbar.showAtMaxLevel = false
  end
  if not sessionStart then
    sessionStart = GetTime()
    sessionStartXP = UnitXP("player") or 0
  end

  bar:SetSize(db.xpbar.width, db.xpbar.height)
  bar:SetScale(db.xpbar.scale)
  if bar.detailText then
    bar.detailText:SetPoint("TOP", bar, "BOTTOM", 0, -4)
  end
  bar:ClearAllPoints()
  bar:SetPoint(db.xpbar.anchor, UIParent, db.xpbar.anchor, db.xpbar.x, db.xpbar.y)
  local tex = bar:GetStatusBarTexture()
  if tex and tex.SetGradient then
    tex:SetGradient("HORIZONTAL", CreateColor(0.45, 0.3, 0.95), CreateColor(0.7, 0.45, 1.0))
  end

  if not M.eventFrame then
    M.eventFrame = CreateFrame("Frame")
    M.eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    M.eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
    M.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    M.eventFrame:RegisterEvent("UPDATE_FACTION")
    M.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    M.eventFrame:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE")
    M.eventFrame:SetScript("OnEvent", function(self, event)
      if not M.active then return end
      if event == "QUEST_LOG_UPDATE" or event == "QUEST_LOG_CRITERIA_UPDATE" then
        questDirty = true
        Update(true)
      else
        Update(false)
      end
    end)
  end

  M:SetLocked(db.general.framesLocked)

  HideBlizzardXPTrackingBars()
  if not hideBlizzardHooked then
    if StatusTrackingBarManager and hooksecurefunc then
      hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", HideBlizzardXPTrackingBars)
    elseif MainStatusTrackingBarContainer and hooksecurefunc then
      hooksecurefunc(MainStatusTrackingBarContainer, "UpdateBarsShown", HideBlizzardXPTrackingBars)
    end
    hideBlizzardHooked = true
  end
  if not hideBlizzardTicker and C_Timer and C_Timer.NewTicker then
    hideBlizzardTicker = C_Timer.NewTicker(3, HideBlizzardXPTrackingBars)
  end

  -- Use C_Timer instead of OnUpdate for better performance
  if ShouldRealtimeUpdate(db) then
    if not updateTimer then
      updateTimer = C_Timer.NewTicker(UPDATE_INTERVAL, function()
        Update(false)
      end)
    end
  else
    if updateTimer then
      updateTimer:Cancel()
      updateTimer = nil
    end
  end

  Update()
end

function M:Preview()
  previewActive = not previewActive
  Update()
  return previewActive
end

function M:Disable()
  M.active = false
  previewActive = false
  if bar then
    bar._huiUnlockPlaceholder = nil
  end
  if bar then bar:Hide() end
  if updateTimer then
    updateTimer:Cancel()
    updateTimer = nil
  end
  if hideBlizzardTicker then
    hideBlizzardTicker:Cancel()
    hideBlizzardTicker = nil
  end
  if M.eventFrame then
    M.eventFrame:UnregisterAllEvents()
    M.eventFrame:SetScript("OnEvent", nil)
    M.eventFrame:Hide()
    M.eventFrame:SetParent(nil)
    M.eventFrame = nil
  end
end
