local ADDON, NS = ...

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

-- Custom fonts
LSM:Register("font", "BigNoodleTilting", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\BigNoodleTitling.ttf")

-- Windows system fonts (clean, professional)
LSM:Register("font", "Arial", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\Arial.ttf")
LSM:Register("font", "Arial Bold", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\ArialBold.ttf")
LSM:Register("font", "Georgia", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\Georgia.ttf")
LSM:Register("font", "Tahoma", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\Tahoma.ttf")
LSM:Register("font", "Tahoma Bold", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\TahomaBold.ttf")
LSM:Register("font", "Verdana", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\Verdana.ttf")
LSM:Register("font", "Verdana Bold", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\VerdanaBold.ttf")

-- Monospace fonts (for code/technical look)
LSM:Register("font", "Consolas", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\Consolas.ttf")
LSM:Register("font", "Courier New", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\CourierNew.ttf")
LSM:Register("font", "Courier New Bold", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\CourierNewBold.ttf")

-- WoW built-in fonts (override LSM defaults with correct paths)
LSM:Register("font", "Arial Narrow", "Interface\\Fonts\\ARIALN.ttf")
LSM:Register("font", "Friz Quadrata TT", "Interface\\Fonts\\FRIZQT__.ttf")
LSM:Register("font", "Morpheus", "Interface\\Fonts\\MORPHEUS.ttf")
LSM:Register("font", "Skurri", "Interface\\Fonts\\skurri.ttf")

-- Additional quality fonts
LSM:Register("font", "Diablo Heavy", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\DiabloHeavy.ttf")
LSM:Register("font", "Lato", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\Lato.ttf")
LSM:Register("font", "Poppins SemiBold", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\PoppinsSemiBold.ttf")
LSM:Register("font", "Roboto Condensed Bold", "Interface\\AddOns\\HarathUI\\Media\\Fonts\\RobotoCondensedBold.ttf")
