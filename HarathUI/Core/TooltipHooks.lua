local ADDON, NS = ...
local spellIDTooltipHooked = false
local spellIDTooltipDataHooked = false

local function HookSpellIDTooltips()
  if spellIDTooltipHooked then return end
  spellIDTooltipHooked = true

  local function ShouldShow()
    local db = NS:GetDB()
    return db and db.general and db.general.showSpellIDs
  end

  local function AddSpellIDLine(tt, spellID)
    if not tt or type(spellID) ~= "number" then return end
    tt:AddLine(("Spell ID: %d"):format(spellID), 0.7, 0.7, 0.7)
    tt:Show()
  end

  -- Retail 12.x+ spell tooltips are data-driven; use TooltipDataProcessor when available.
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    spellIDTooltipDataHooked = true
    for key, tooltipType in pairs(Enum.TooltipDataType) do
      if type(key) == "string" and type(tooltipType) == "number" and string.find(string.lower(key), "spell", 1, true) then
        TooltipDataProcessor.AddTooltipPostCall(tooltipType, function(tt, data)
          if not ShouldShow() then return end
          if not tt or type(data) ~= "table" then return end
          local spellID = data.spellID or data.id
          if type(spellID) == "number" then
            AddSpellIDLine(tt, spellID)
          end
        end)
      end
    end
  end

  -- Compatibility fallback for clients without TooltipDataProcessor spell callbacks.
  local function Attach(tooltip)
    if not tooltip or not tooltip.HookScript then return end
    tooltip:HookScript("OnTooltipSetItem", function(tt)
      if not ShouldShow() then return end
      if not tt or not tt.GetSpell then return end
      local _, spellID = tt:GetSpell()
      if type(spellID) == "number" then
        AddSpellIDLine(tt, spellID)
      end
    end)
  end

  if not spellIDTooltipDataHooked then
    Attach(GameTooltip)
    Attach(ItemRefTooltip)
    Attach(ShoppingTooltip1)
    Attach(ShoppingTooltip2)
  end
end
NS.HookSpellIDTooltips = HookSpellIDTooltips

