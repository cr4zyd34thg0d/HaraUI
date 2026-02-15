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

local state = {
  bar = nil,
  previewActive = false,
  sessionStart = nil,
  sessionStartXP = nil,
  cachedQuestXP = 0,
  questDirty = true,
  updateTimer = nil,
  hideBlizzardTicker = nil,
  hideBlizzardHooked = false,
  eventFrame = nil,
}
local UPDATE_INTERVAL = 1

-- Cache color codes for performance (avoid string creation in hot paths)
local QUEST_COLOR = NS.THEME.QUEST_COLOR
local RESTED_COLOR = NS.THEME.RESTED_COLOR
local COLOR_END = NS.THEME.COLOR_END
local GetTime = GetTime
local UnitLevel = UnitLevel
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local GetXPExhaustion = GetXPExhaustion
local math_min = math.min
local math_max = math.max
local math_floor = math.floor

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
  state.bar = CreateFrame("StatusBar", nil, UIParent, "BackdropTemplate")
  local bar = state.bar
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
  local bar = state.bar
  if not bar then return end
  local width = bar:GetWidth()
  local curPct = (max > 0) and math_min(cur / max, 1) or 0
  local questPct = (max > 0) and math_max(0, questXP / max) or 0
  local restedPct = (max > 0) and math_max(0, restedXP / max) or 0

  local curWidth = width * curPct
  local questWidth = width * questPct
  local restedWidth = width * restedPct

  bar.questTex:ClearAllPoints()
  bar.restedTex:ClearAllPoints()

  if questWidth > 0 then
    bar.questTex:SetPoint("LEFT", bar, "LEFT", curWidth, 0)
    bar.questTex:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.questTex:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.questTex:SetWidth(math_min(width - curWidth, questWidth))
    bar.questTex:Show()
  else
    bar.questTex:Hide()
  end

  if restedWidth > 0 then
    local offset = curWidth + questWidth
    bar.restedTex:SetPoint("LEFT", bar, "LEFT", offset, 0)
    bar.restedTex:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.restedTex:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.restedTex:SetWidth(math_min(width - offset, restedWidth))
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
  if force or state.questDirty then
    state.cachedQuestXP = GetCompletedQuestXP()
    state.questDirty = false
  end
  return state.cachedQuestXP
end

local function IsFramesUnlocked(db)
  return db and db.general and db.general.framesLocked == false
end

local function ShowUnlockPlaceholder()
  local bar = state.bar
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
  local bar = state.bar
  if not bar then return end
  local db = NS:GetDB()
  local xpbar = db and db.xpbar
  if not db or not xpbar or not xpbar.enabled then return end

  if state.previewActive then
    -- Toggle preview state from the options button.
    bar._huiUnlockPlaceholder = nil
    bar:SetValue(0.658)
    bar.overlay:SetValue(0)
    UpdateSegments(0.658, 1, 0.048, 0.064)
    if xpbar.showText then
      bar.levelText:SetText("Level 57")
      bar.xpText:SetText("204931 / 311490")
      bar.pctText:SetText("65.8% (70.6%)")
      if xpbar.showQuestText ~= false then
        bar.detailText:SetText("Completed Quests: |cffffa11a4.8%|r - Rested: |cff5aa0ff6.4%|r")
      else
        bar.detailText:SetText("")
      end
      if xpbar.showSessionTime then
        bar.sessionText:SetText("Session: 0:22")
      else
        bar.sessionText:SetText("")
      end
      if xpbar.showRateText then
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
    if not xpbar.showAtMaxLevel then
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

      if xpbar.showText then
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

    if xpbar.hideAtMaxIfNoRep and not xpbar.showAtMaxLevel then
      if unlocked then
        ShowUnlockPlaceholder()
      else
        bar._huiUnlockPlaceholder = nil
        bar:Hide()
      end
      return
    end

    bar._huiUnlockPlaceholder = nil
    if xpbar.showAtMaxLevel then
      bar:SetValue(1)
    else
      bar:SetValue(0)
    end
    bar.overlay:SetValue(0)
    UpdateSegments(0, 1, 0, 0)
    if xpbar.showText then
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
  if rested and max > 0 then restedPct = math_min(1, (cur + rested) / max) end
  bar.overlay:SetValue(restedPct)

  local questXP = GetQuestXP(forceQuest)
  UpdateSegments(cur, max, questXP, rested or 0)

  if xpbar.showText then
    local totalPct = math_min(1, (cur + (rested or 0) + questXP) / max)
    bar.levelText:SetText(("Level %d"):format(level))
    bar.xpText:SetText(("%d / %d"):format(cur, max))
    bar.pctText:SetText(("%.1f%% (%.1f%%)"):format(pct * 100, totalPct * 100))
    local questPct = (questXP > 0 and max > 0) and (questXP / max * 100) or 0
    local restedPctNum = (rested and max > 0) and (rested / max * 100) or 0
    if xpbar.showQuestText ~= false then
      bar.detailText:SetText(("Completed Quests: %s%.1f%%%s - Rested: %s%.1f%%%s"):format(
        QUEST_COLOR, questPct, COLOR_END,
        RESTED_COLOR, restedPctNum, COLOR_END
      ))
    else
      bar.detailText:SetText("")
    end
    if xpbar.showSessionTime then
      local elapsed = GetTime() - (state.sessionStart or GetTime())
      bar.sessionText:SetText(("Session: %s"):format(FormatTime(elapsed)))
    else
      bar.sessionText:SetText("")
    end
    if xpbar.showRateText then
      local elapsed = GetTime() - (state.sessionStart or GetTime())
      if state.sessionStartXP == nil then
        state.sessionStartXP = cur
      end
      if cur < state.sessionStartXP then
        state.sessionStartXP = cur
        state.sessionStart = GetTime()
      end
      local xpGained = math_max(0, cur - state.sessionStartXP)
      local rate = (elapsed > 0) and (xpGained / elapsed) * 3600 or 0
      local remaining = max - cur
      local eta = (rate > 0) and (remaining / rate) or 0
      bar.rateText:SetText(("ETA %s - %s/hr"):format(FormatTime(eta), AbbreviateLargeNumbers(math_floor(rate + 0.5))))
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
  local bar = state.bar
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
  local xpbar = db.xpbar
  M.active = true
  if not state.bar then Create() end
  local bar = state.bar

  -- Refresh fonts when settings change
  if bar then
    ApplyBarFont(bar.levelText, 12)
    ApplyBarFont(bar.xpText, 12)
    ApplyBarFont(bar.pctText, 12)
    ApplyBarFont(bar.detailText, 10)
    ApplyBarFont(bar.sessionText, 10)
    ApplyBarFont(bar.rateText, 10)
  end

  if xpbar.hideAtMaxIfNoRep == nil then
    xpbar.hideAtMaxIfNoRep = true
  end
  if xpbar.showSessionTime == nil then
    xpbar.showSessionTime = false
  end
  if xpbar.showRateText == nil then
    xpbar.showRateText = false
  end
  if xpbar.showQuestText == nil then
    xpbar.showQuestText = true
  end
  if xpbar.showAtMaxLevel == nil then
    xpbar.showAtMaxLevel = false
  end
  if not state.sessionStart then
    state.sessionStart = GetTime()
    state.sessionStartXP = UnitXP("player") or 0
  end

  bar:SetSize(xpbar.width, xpbar.height)
  bar:SetScale(xpbar.scale)
  if bar.detailText then
    bar.detailText:SetPoint("TOP", bar, "BOTTOM", 0, -4)
  end
  bar:ClearAllPoints()
  bar:SetPoint(xpbar.anchor, UIParent, xpbar.anchor, xpbar.x, xpbar.y)
  local tex = bar:GetStatusBarTexture()
  if tex and tex.SetGradient then
    tex:SetGradient("HORIZONTAL", CreateColor(0.45, 0.3, 0.95), CreateColor(0.7, 0.45, 1.0))
  end

  if not state.eventFrame then
    state.eventFrame = CreateFrame("Frame")
    state.eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    state.eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
    state.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    state.eventFrame:RegisterEvent("UPDATE_FACTION")
    state.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    state.eventFrame:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE")
    state.eventFrame:SetScript("OnEvent", function(self, event)
      if not M.active then return end
      if event == "QUEST_LOG_UPDATE" or event == "QUEST_LOG_CRITERIA_UPDATE" then
        state.questDirty = true
        Update(true)
      else
        Update(false)
      end
    end)
  end

  M:SetLocked(db.general.framesLocked)

  HideBlizzardXPTrackingBars()
  if not state.hideBlizzardHooked then
    if StatusTrackingBarManager and hooksecurefunc then
      hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", HideBlizzardXPTrackingBars)
    elseif MainStatusTrackingBarContainer and hooksecurefunc then
      hooksecurefunc(MainStatusTrackingBarContainer, "UpdateBarsShown", HideBlizzardXPTrackingBars)
    end
    state.hideBlizzardHooked = true
  end
  if not state.hideBlizzardTicker and C_Timer and C_Timer.NewTicker then
    state.hideBlizzardTicker = C_Timer.NewTicker(3, HideBlizzardXPTrackingBars)
  end

  -- Use C_Timer instead of OnUpdate for better performance
  if ShouldRealtimeUpdate(db) then
    if not state.updateTimer then
      state.updateTimer = C_Timer.NewTicker(UPDATE_INTERVAL, function()
        Update(false)
      end)
    end
  else
    if state.updateTimer then
      state.updateTimer:Cancel()
      state.updateTimer = nil
    end
  end

  Update()
end

function M:Preview()
  state.previewActive = not state.previewActive
  Update()
  return state.previewActive
end

function M:Disable()
  local bar = state.bar
  M.active = false
  state.previewActive = false
  if bar then
    bar._huiUnlockPlaceholder = nil
  end
  if bar then bar:Hide() end
  if state.updateTimer then
    state.updateTimer:Cancel()
    state.updateTimer = nil
  end
  if state.hideBlizzardTicker then
    state.hideBlizzardTicker:Cancel()
    state.hideBlizzardTicker = nil
  end
  if state.eventFrame then
    state.eventFrame:UnregisterAllEvents()
    state.eventFrame:SetScript("OnEvent", nil)
    state.eventFrame:Hide()
    state.eventFrame:SetParent(nil)
    state.eventFrame = nil
  end
end
