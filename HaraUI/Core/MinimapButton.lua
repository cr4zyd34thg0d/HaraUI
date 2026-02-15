local ADDON, NS = ...
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local function EnsureMinimapButton()
  if not LDB or not LDBIcon then return end
  local db = NS:GetDB()
  if not db or not db.general then return end

  if type(db.general.minimapButton) ~= "table" then
    local hide = false
    if type(db.general.minimapButton) == "boolean" then
      hide = not db.general.minimapButton
    end
    db.general.minimapButton = { hide = hide }
  end
  if db.general.minimapButton.hide == nil then
    db.general.minimapButton.hide = false
  end

  if not NS._huiLDBObject then
    NS._huiLDBObject = LDB:NewDataObject("HaraUI", {
      type = "launcher",
      text = "HaraUI",
      icon = "Interface\\AddOns\\HaraUI\\Media\\mmicon.tga",
      OnClick = function(_, button)
        if button == "LeftButton" or button == "RightButton" then
          if NS.OpenOptions then NS:OpenOptions() end
        end
      end,
      OnTooltipShow = function(tt)
        if not tt then return end
        tt:AddLine("HaraUI", 1, 0.82, 0)
        tt:AddLine("Click: Open options", 1, 1, 1)
      end,
    })
    LDBIcon:Register("HaraUI", NS._huiLDBObject, db.general.minimapButton)
  end

  if db.general.minimapButton.hide then
    LDBIcon:Hide("HaraUI")
  else
    LDBIcon:Show("HaraUI")
  end
end
NS.EnsureMinimapButton = EnsureMinimapButton

function NS:UpdateMinimapButton()
  EnsureMinimapButton()
end

