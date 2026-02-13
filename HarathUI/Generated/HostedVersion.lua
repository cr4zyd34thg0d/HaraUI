local ADDON, NS = ...
if not NS or type(NS.SetHostedVersionInfo) ~= "function" then return end

NS:SetHostedVersionInfo({
  version = "1.5.1",
  commit = "56a5bb9",
  buildDate = "2026-02-13",
  sourceLabel = "GitHub branch main",
})
