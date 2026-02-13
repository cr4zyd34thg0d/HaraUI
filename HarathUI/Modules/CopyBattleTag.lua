local ADDON, NS = ...
local M = {}
NS:RegisterModule("copybtag", M)
M.active = false

local hookFrame
local popupRegistered = false
local dropdownHooked = false

local function RegisterPopup()
  if popupRegistered then return end
  if not StaticPopupDialogs then return end
  if StaticPopupDialogs.HaraUI_CopyBattleTag then
    popupRegistered = true
    return
  end

  StaticPopupDialogs.HaraUI_CopyBattleTag = {
    text = "Copy BattleTag",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    hasEditBox = true,
    maxLetters = 64,
    OnShow = function(self, data)
      local editBox = self.editBox
      if not editBox then return end
      local value = type(data) == "string" and data or ""
      editBox:SetText(value)
      editBox:HighlightText()
      editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
      local parent = self and self:GetParent()
      if parent then
        parent:Hide()
      end
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self and self:GetParent()
      if parent then
        parent:Hide()
      end
    end,
    EditBoxOnTextChanged = function() end,
  }

  popupRegistered = true
end

local function NormalizeBattleTag(text)
  if type(text) ~= "string" then return nil end
  local t = text:gsub("%s+", "")
  if t == "" then return nil end
  if t:find("#", 1, true) then
    return t
  end
  return nil
end

local function GetBattleTagFromFriendIndex(idx)
  if type(idx) ~= "number" then return nil end

  if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
    local info = C_BattleNet.GetFriendAccountInfo(idx)
    if type(info) == "table" then
      local btag = NormalizeBattleTag(info.battleTag)
      if btag then return btag end
      if type(info.accountName) == "string" then
        btag = NormalizeBattleTag(info.accountName)
        if btag then return btag end
      end
    end
  end

  if BNGetFriendInfoByID then
    local a, b, c, d, e, f, g, h, i, j = BNGetFriendInfoByID(idx)
    local candidates = { a, b, c, d, e, f, g, h, i, j }
    for _, v in ipairs(candidates) do
      local btag = NormalizeBattleTag(v)
      if btag then return btag end
    end
  end

  return nil
end

local function GetSelectedBattleTag()
  local bnetIndex = tonumber(_G.FRIENDS_DROPDOWN_BNETID) or tonumber(_G.FRIENDS_DROPDOWN_BNET_ACCOUNT_ID)
  if bnetIndex then
    local btag = GetBattleTagFromFriendIndex(bnetIndex)
    if btag then return btag end
  end

  local name = NormalizeBattleTag(_G.FRIENDS_DROPDOWN_NAME)
  if name then return name end

  if UIDROPDOWNMENU_INIT_MENU then
    local initMenu = UIDROPDOWNMENU_INIT_MENU
    local btag = NormalizeBattleTag(initMenu.battleTag)
    if btag then return btag end
    btag = NormalizeBattleTag(initMenu.accountName)
    if btag then return btag end
    btag = NormalizeBattleTag(initMenu.name)
    if btag then return btag end
  end

  return nil
end

local function AddCopyMenuButton(level)
  if not M.active then return end
  if level ~= 1 then return end
  if not (UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton) then return end

  local battleTag = GetSelectedBattleTag()
  if not battleTag then return end

  local info = UIDropDownMenu_CreateInfo()
  info.text = "Copy BattleTag"
  info.notCheckable = true
  info.func = function()
    RegisterPopup()
    if StaticPopup_Show then
      StaticPopup_Show("HaraUI_CopyBattleTag", nil, nil, battleTag)
    end
  end
  UIDropDownMenu_AddButton(info, level)
end

local function TryHookDropdown()
  if dropdownHooked then return true end
  if not hooksecurefunc then return false end
  if not FriendsFrameDropDown_Initialize then return false end

  hooksecurefunc("FriendsFrameDropDown_Initialize", function(a, b)
    local lv = 1
    if type(a) == "number" then
      lv = a
    elseif type(b) == "number" then
      lv = b
    end
    AddCopyMenuButton(lv)
  end)
  dropdownHooked = true
  return true
end

function M:Apply()
  M.active = true
  RegisterPopup()
  if TryHookDropdown() then
    return
  end

  if not hookFrame then
    hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:SetScript("OnEvent", function(_, _, addonName)
      if not M.active then return end
      if addonName == "Blizzard_FriendsFrame" or addonName == "Blizzard_Communities" then
        if TryHookDropdown() and hookFrame then
          hookFrame:UnregisterAllEvents()
        end
      end
    end)
  end
end

function M:Disable()
  M.active = false
end
