local ADDON, NS = ...

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

-- Custom fonts
LSM:Register("font", "BigNoodleTilting", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\BigNoodleTitling.ttf")

-- Windows system fonts (clean, professional)
LSM:Register("font", "Arial", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\Arial.ttf")
LSM:Register("font", "Arial Bold", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\ArialBold.ttf")
LSM:Register("font", "Georgia", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\Georgia.ttf")
LSM:Register("font", "Tahoma", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\Tahoma.ttf")
LSM:Register("font", "Tahoma Bold", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\TahomaBold.ttf")
LSM:Register("font", "Verdana", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\Verdana.ttf")
LSM:Register("font", "Verdana Bold", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\VerdanaBold.ttf")

-- Monospace fonts (for code/technical look)
LSM:Register("font", "Consolas", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\Consolas.ttf")
LSM:Register("font", "Courier New", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\CourierNew.ttf")
LSM:Register("font", "Courier New Bold", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\CourierNewBold.ttf")

-- WoW built-in fonts (override LSM defaults with correct paths)
LSM:Register("font", "Arial Narrow", "Interface\\Fonts\\ARIALN.ttf")
LSM:Register("font", "Friz Quadrata TT", "Interface\\Fonts\\FRIZQT__.ttf")
LSM:Register("font", "Morpheus", "Interface\\Fonts\\MORPHEUS.ttf")
LSM:Register("font", "Skurri", "Interface\\Fonts\\skurri.ttf")

-- Additional quality fonts
LSM:Register("font", "Diablo Heavy", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\DiabloHeavy.ttf")
LSM:Register("font", "Lato", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\Lato.ttf")
LSM:Register("font", "Poppins SemiBold", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\PoppinsSemiBold.ttf")
LSM:Register("font", "Roboto Condensed Bold", "Interface\\AddOns\\HaraUI\\Media\\Fonts\\RobotoCondensedBold.ttf")
