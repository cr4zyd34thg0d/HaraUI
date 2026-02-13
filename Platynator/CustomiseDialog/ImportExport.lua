---@class addonTablePlatynator
local addonTable = select(2, ...)

local function IsKnownDesign(import, name)
  if type(name) ~= "string" or name == "" then
    return false
  end

  if type(import.designs) == "table" and type(import.designs[name]) == "table" then
    return true
  end

  return type(addonTable.Design) == "table"
    and type(addonTable.Design.Defaults) == "table"
    and addonTable.Design.Defaults[name] ~= nil
end

local function FindFirstImportedDesign(import)
  if type(import.designs) ~= "table" then
    return nil
  end

  local fallback
  for key, design in pairs(import.designs) do
    if type(key) == "string" and type(design) == "table" then
      if not key:match("^_") then
        return key
      end
      fallback = fallback or key
    end
  end

  return fallback
end

local function SanitizeImportedProfile(import)
  if type(import) ~= "table" then
    return
  end

  if type(import.designs) ~= "table" then
    import.designs = {}
  end
  if type(import.designs_assigned) ~= "table" then
    import.designs_assigned = {}
  end

  local show = import.show_nameplates
  if type(show) ~= "table" then
    show = {}
    import.show_nameplates = show
  end
  if show.enemy == nil then
    show.enemy = true
  end
  if show.enemyMinion == nil then
    show.enemyMinion = true
  end
  if show.enemyMinor == nil then
    show.enemyMinor = true
  end
  show.friendlyNPC = false
  show.friendlyPlayer = false
  show.friendlyMinion = false
  show.player = nil
  show.npc = nil

  local stacking = import.stacking_nameplates
  if type(stacking) ~= "table" then
    stacking = {enemy = true}
    import.stacking_nameplates = stacking
  elseif stacking.enemy == nil then
    stacking.enemy = true
  end
  stacking.friend = false

  local clickable = import.clickable_nameplates
  if type(clickable) ~= "table" then
    clickable = {enemy = true}
    import.clickable_nameplates = clickable
  elseif clickable.enemy == nil then
    clickable.enemy = true
  end
  clickable.friend = false

  import.enable_friendly_nameplates = false
  import.show_friendly_in_instances_1 = "never"
  import.show_friendly_in_instances = nil

  local mapping = import.designs_assigned
  local style = import.style
  if not IsKnownDesign(import, style) then
    style = nil
  end
  if not style and IsKnownDesign(import, mapping.enemy) then
    style = mapping.enemy
  end
  if not style and IsKnownDesign(import, mapping.friend) then
    style = mapping.friend
  end
  if not style then
    style = FindFirstImportedDesign(import)
  end
  if not style then
    local current = addonTable.Config.Get(addonTable.Config.Options.STYLE)
    if IsKnownDesign(import, current) then
      style = current
    end
  end
  if style and IsKnownDesign(import, style) then
    import.style = style
  else
    import.style = nil
  end

  if not IsKnownDesign(import, mapping.enemy) then
    mapping.enemy = import.style
  end
  if not IsKnownDesign(import, mapping.friend) then
    mapping.friend = mapping.enemy or import.style
  end
  if not IsKnownDesign(import, mapping.enemySimplified) then
    mapping.enemySimplified = "_hare_simplified"
  end
end

function addonTable.CustomiseDialog.ImportData(import, name, overwrite)
  if import.addon ~= "Platynator" then
    return false
  end

  if name:match("^_") then
    return false
  end

  import.version = nil
  import.addon = nil
  if import.kind == nil or import.kind == "style" then
    local designs = addonTable.Config.Get(addonTable.Config.Options.DESIGNS)
    if designs[name] and not overwrite then
      return false
    end
    import.kind = nil
    addonTable.Core.UpgradeDesign(import)
    addonTable.Config.Get(addonTable.Config.Options.DESIGNS)[name] = import
    addonTable.Config.Set(addonTable.Config.Options.STYLE, name)
  elseif import.kind == "profile" then
    import.kind = nil
    if overwrite and PLATYNATOR_CONFIG.Profiles[name] then
      local oldDesigns = PLATYNATOR_CONFIG.Profiles[name].designs or {}
      local old = addonTable.Config.CurrentProfile
      PLATYNATOR_CONFIG.Profiles[name] = import
      local designs = PLATYNATOR_CONFIG.Profiles[name].designs
      if type(designs) ~= "table" then
        designs = {}
        PLATYNATOR_CONFIG.Profiles[name].designs = designs
      end
      for key, design in pairs(oldDesigns) do
        if designs[key] == nil then
          designs[key] = design
        end
      end
      SanitizeImportedProfile(import)
      addonTable.Config.ChangeProfile(name, old)
    else
      if PLATYNATOR_CONFIG.Profiles[name] then
        return false
      end
      addonTable.Config.MakeProfile(name, false)
      local old = addonTable.Config.CurrentProfile
      PLATYNATOR_CONFIG.Profiles[PLATYNATOR_CURRENT_PROFILE] = import
      SanitizeImportedProfile(import)
      addonTable.Config.ChangeProfile(PLATYNATOR_CURRENT_PROFILE, old)
    end
  end

  return true
end
