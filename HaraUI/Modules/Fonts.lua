local ADDON, NS = ...

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

LSM:Register("font", "Tahoma Bold", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\TahomaBold.ttf")

-- WoW built-in fonts (override LSM defaults with correct paths)
LSM:Register("font", "Arial Narrow", "Interface\\Fonts\\ARIALN.ttf")
LSM:Register("font", "Friz Quadrata TT", "Interface\\Fonts\\FRIZQT__.ttf")
LSM:Register("font", "Morpheus", "Interface\\Fonts\\MORPHEUS.ttf")
LSM:Register("font", "Skurri", "Interface\\Fonts\\skurri.ttf")
