local ADDON, NS = ...

local function HandleSlash(msg)
  msg = (msg or ""):lower()

  if msg == "" or msg == "options" or msg == "config" then
    if NS.ToggleOptionsWindow then
      NS:ToggleOptionsWindow()
    elseif NS.OpenOptions then
      NS:OpenOptions()
    end
    return
  end

  if msg == "lock" or msg == "move" then
    local db = NS:GetDB()
    db.general.framesLocked = not db.general.framesLocked
    NS.Print("Unlock Frames: " .. (db.general.framesLocked and "Off (Locked)" or "On (Unlocked)"))
    if NS.SetFramesLocked then NS:SetFramesLocked(db.general.framesLocked) end
    return
  end

  if msg == "xp" then
    local db = NS:GetDB(); db.xpbar.enabled = not db.xpbar.enabled
    NS.Print("XP/Rep Bar: " .. (db.xpbar.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end

  if msg == "cast" then
    local db = NS:GetDB(); db.castbar.enabled = not db.castbar.enabled
    NS.Print("Cast Bar: " .. (db.castbar.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end

  if msg == "loot" then
    local db = NS:GetDB(); db.loot.enabled = not db.loot.enabled
    NS.Print("Loot Toasts: " .. (db.loot.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end

  if msg == "summon" or msg == "summons" then
    local db = NS:GetDB()
    db.summons = db.summons or {}
    db.summons.enabled = not (db.summons.enabled == true)
    NS.Print("Auto Summon Accept: " .. (db.summons.enabled and "On" or "Off"))
    NS:ApplyAll()
    return
  end


  if msg == "debug" then
    local db = NS:GetDB(); db.general.debug = not db.general.debug
    NS.Print("Debug: " .. (db.general.debug and "On" or "Off"))
    return
  end
  if msg == "version" then
    local info = NS.GetVersionInfo and NS.GetVersionInfo() or nil
    if not info then
      NS.Print("Version info unavailable.")
      return
    end
    local installed = tostring(info.installed or "unknown")
    local latest = tostring(info.latest or "unknown")
    local source = tostring(info.source or "unknown")
    local peerName = tostring(info.peerName or "n/a")
    local status = (info.status or (NS.GetVersionStatus and NS.GetVersionStatus(info)) or "unknown")
    NS.Print(("Version status: %s (installed %s, latest %s; source=%s; peer=%s)"):format(
      status,
      installed,
      latest,
      source,
      peerName
    ))
    return
  end
  NS.Print("Commands: /hui (options) | lock | xp | cast | loot | summon | debug | version")
end

NS._huiHandleSlash = HandleSlash

SLASH_HARALT1 = "/haralt"
SlashCmdList["HARALT"] = function()
  local mod = NS.Modules and NS.Modules.altpanel
  if mod and mod.Toggle then
    mod:Toggle()
  else
    NS.Print("AltPanel module is not loaded.")
  end
end

