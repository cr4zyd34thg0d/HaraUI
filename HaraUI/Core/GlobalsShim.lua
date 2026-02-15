local ADDON, NS = ...

-- Single legacy global surface: slash command globals required by WoW.
if type(NS) == "table" and type(NS._huiHandleSlash) == "function" then
  SLASH_HARAUI1 = "/haraui"
  SLASH_HARAUI2 = "/hui"
  SlashCmdList["HARAUI"] = NS._huiHandleSlash
end

