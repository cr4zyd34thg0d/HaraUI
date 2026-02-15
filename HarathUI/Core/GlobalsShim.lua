local ADDON, NS = ...

-- Single legacy global surface: slash command globals required by WoW.
if type(NS) == "table" and type(NS._huiHandleSlash) == "function" then
  SLASH_HARATHUI1 = "/harathui"
  SLASH_HARATHUI2 = "/hui"
  SlashCmdList["HARATHUI"] = NS._huiHandleSlash
end

