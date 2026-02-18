local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then
	return
end

CS.Skin = CS.Skin or {}
local Skin = CS.Skin

local function IsAccountTransferBuild()
	return C_CurrencyInfo and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function"
end

---------------------------------------------------------------------------
-- CFG: shared constants used by GearDisplay, StatsPanel, RightPanel
---------------------------------------------------------------------------
Skin.CFG = {
	SLOT_ICON_SIZE = 38,
	GEAR_ROW_WIDTH = 272,
	GEAR_ROW_HEIGHT = 46,
	ENCHANT_QUALITY_MARKUP_SIZE = 18,

	STAT_ROW_HEIGHT = 16,
	STAT_ROW_GAP = 2,
	STAT_SECTION_GAP = 7,
	STAT_SECTION_BOTTOM_PAD = 2,
	STAT_GRADIENT_SPLIT = 0.82,
	STAT_TOPINFO_GRADIENT_SPLIT = 0.86,
	STAT_BODY_GRADIENT_SPLIT = 0.90,
	STAT_ROW_GRADIENT_SPLIT = 0.92,
	STAT_HEADER_GRADIENT_ALPHA = 1.00,
	STAT_BODY_GRADIENT_ALPHA = 0.72,
	STAT_ROW_GRADIENT_ALPHA = 0.74,

	BASE_STATS_WIDTH = 292,
	BASE_FRAME_WIDTH = 820,
	FRAME_EXPAND_FACTOR = 1.15,

	-- Slot layout constants (from Legacy ApplyChonkySlotLayout)
	SLOT_VPAD = 24,
	SLOT_TOP_Y = -64,
	-- Unified cluster controls
	LeftGearCluster = {
		IconX = 14,
		TextGap = 10,
	},
	RightGearCluster = {
		ColumnInset = 52, -- keeps ~4px gap between right slot icons and stats/titles/equipment panel
		ColumnOffsetX = -28, -- negative moves left, positive moves right
		TextGap = 10,
	},
	WeaponGearCluster = {
		PairGapX = 68,
		BottomY = 71,
		OffsetX = 0, -- moves both weapon slots together
	},

	-- Legacy aliases (fallback only; prefer cluster tables above)
	GEAR_TEXT_GAP = 10,
	SLOT_LEFT_X = 14,
	SLOT_RIGHT_COLUMN_INSET = 52,
	RIGHT_ICON_COLUMN_SHIFT_X = 10,
	ICON_TO_GRADIENT_RIGHT_INSET = 6,
	GRADIENT_TO_STATS_GAP = 4,
	SLOT_WEAPON_PAIR_GAP = 68,
	SLOT_WEAPON_BOTTOM_Y = 71,

	-- Button layout constants (from Legacy CFG)
	STATS_MODE_BUTTON_WIDTH = 86,
	STATS_MODE_BUTTON_HEIGHT = 30,
	STATS_MODE_BUTTON_GAP = 6,
	STATS_SIDEBAR_BUTTON_COUNT = 4,
	STATS_SIDEBAR_BUTTON_SIZE = 34,
	STATS_SIDEBAR_BUTTON_GAP = 4,

	LEFT_GEAR_SLOTS = {
		"HeadSlot",
		"NeckSlot",
		"ShoulderSlot",
		"BackSlot",
		"ChestSlot",
		"ShirtSlot",
		"SecondaryHandSlot",
		"WristSlot",
	},
	RIGHT_GEAR_SLOTS = {
		"HandsSlot",
		"WaistSlot",
		"LegsSlot",
		"FeetSlot",
		"Finger0Slot",
		"Finger1Slot",
		"Trinket0Slot",
		"Trinket1Slot",
		"MainHandSlot",
	},

	SLOT_NAME_TO_INDEX = {
		HeadSlot = 1,
		NeckSlot = 2,
		ShoulderSlot = 3,
		ShirtSlot = 4,
		ChestSlot = 5,
		WaistSlot = 6,
		LegsSlot = 7,
		FeetSlot = 8,
		WristSlot = 9,
		HandsSlot = 10,
		Finger0Slot = 11,
		Finger1Slot = 12,
		Trinket0Slot = 13,
		Trinket1Slot = 14,
		BackSlot = 15,
		MainHandSlot = 16,
		SecondaryHandSlot = 17,
		TabardSlot = 19,
	},

	-- Right-column slots display text to the LEFT.
	DISPLAY_TO_LEFT = {
		[6] = true,
		[7] = true,
		[8] = true,
		[10] = true,
		[11] = true,
		[12] = true,
		[13] = true,
		[14] = true,
		[16] = true,
		[17] = true,
	},

	RARITY_GRADIENT = {
		[0] = { 0.31, 0.31, 0.31, 0.8, 0.62, 0.62, 0.62, 1 }, -- Poor
		[1] = { 0.5, 0.5, 0.5, 0.8, 1, 1, 1, 1 }, -- Common
		[2] = { 0.06, 0.5, 0, 0.8, 0.12, 1, 0, 1 }, -- Uncommon
		[3] = { 0, 0.22, 0.435, 0.8, 0, 0.44, 0.87, 1 }, -- Rare
		[4] = { 0.32, 0.105, 0.465, 0.8, 0.64, 0.21, 0.93, 1 }, -- Epic
		[5] = { 0.5, 0.25, 0, 0.8, 1, 0.5, 0, 1 }, -- Legendary
		[6] = { 0.45, 0.4, 0.25, 0.8, 0.9, 0.8, 0.5, 1 }, -- Artifact
		[7] = { 0, 0.4, 0.5, 0.8, 0, 0.8, 1, 1 }, -- Heirloom
	},

	SECTION_COLORS = {
		{ 0.64, 0.47, 0.1, 0.4 }, -- Attributes (gold)
		{ 0.16, 0.34, 0.08, 0.4 }, -- Secondary (green)
		{ 0.41, 0, 0, 0.4 }, -- Attack (red)
		{ 0, 0.13, 0.38, 0.4 }, -- Defense (blue)
		{ 0.45, 0.45, 0.45, 0.4 }, -- General (gray)
	},

	ALL_SLOT_INDICES = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19 },

	CHARACTER_SLOT_BUTTON_NAMES = {
		"CharacterHeadSlot",
		"CharacterNeckSlot",
		"CharacterShoulderSlot",
		"CharacterShirtSlot",
		"CharacterChestSlot",
		"CharacterWaistSlot",
		"CharacterLegsSlot",
		"CharacterFeetSlot",
		"CharacterWristSlot",
		"CharacterHandsSlot",
		"CharacterFinger0Slot",
		"CharacterFinger1Slot",
		"CharacterTrinket0Slot",
		"CharacterTrinket1Slot",
		"CharacterBackSlot",
		"CharacterMainHandSlot",
		"CharacterSecondaryHandSlot",
		"CharacterTabardSlot",
	},
}

local CFG = Skin.CFG

---------------------------------------------------------------------------
-- Enchant/upgrade constants
---------------------------------------------------------------------------
local TIER_CLASS_COLOR_FALLBACK = { 0.20, 1.00, 0.60 }

local ENCHANT_QUALITY_ATLAS = {
	[1] = { "Professions-Quality-Tier1-Small", "Professions-Quality-Tier1", "Professions-ChatIcon-Quality-Tier1" },
	[2] = { "Professions-Quality-Tier2-Small", "Professions-Quality-Tier2", "Professions-ChatIcon-Quality-Tier2" },
	[3] = { "Professions-Quality-Tier3-Small", "Professions-Quality-Tier3", "Professions-ChatIcon-Quality-Tier3" },
}

local UPGRADE_TRACK_COLORS = {
	["explorer"] = { 0.62, 0.62, 0.62 },
	["adventurer"] = { 0.12, 1.00, 0.12 },
	["veteran"] = { 0.00, 0.44, 0.87 },
	["champion"] = { 0.64, 0.21, 0.93 },
	["hero"] = { 1.00, 0.50, 0.00 },
	["myth"] = { 0.90, 0.12, 0.12 },
	["mythic"] = { 0.90, 0.12, 0.12 },
}

---------------------------------------------------------------------------
-- Internal state
---------------------------------------------------------------------------
local _hiddenRegions = {}
local _slotSkins = {}
local _tooltipCache = {}
local _nativeTabSkins = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Gradient helpers (WoW API compat: Classic vs Retail)
---------------------------------------------------------------------------
function Skin.SetHorizontalGradient(tex, fromR, fromG, fromB, fromA, toR, toG, toB, toA)
	if not tex then
		return
	end
	if tex.SetGradientAlpha then
		tex:SetGradientAlpha("HORIZONTAL", fromR, fromG, fromB, fromA, toR, toG, toB, toA)
	elseif tex.SetGradient and CreateColor then
		tex:SetGradient("HORIZONTAL", CreateColor(fromR, fromG, fromB, fromA), CreateColor(toR, toG, toB, toA))
	else
		tex:SetColorTexture(toR, toG, toB, toA)
	end
end

function Skin.SetVerticalGradient(tex, topR, topG, topB, topA, botR, botG, botB, botA)
	if not tex then
		return
	end
	if tex.SetGradientAlpha then
		tex:SetGradientAlpha("VERTICAL", topR, topG, topB, topA, botR, botG, botB, botA)
	elseif tex.SetGradient and CreateColor then
		tex:SetGradient("VERTICAL", CreateColor(topR, topG, topB, topA), CreateColor(botR, botG, botB, botA))
	else
		tex:SetColorTexture(botR, botG, botB, botA)
	end
end

---------------------------------------------------------------------------
-- Region save/hide/restore pattern
---------------------------------------------------------------------------
local function SaveAndHideRegion(region)
	if not region then
		return
	end
	if not _hiddenRegions[region] then
		local w = region.GetWidth and region:GetWidth() or nil
		local h = region.GetHeight and region:GetHeight() or nil
		local mouse = region.IsMouseEnabled and region:IsMouseEnabled() or nil
		_hiddenRegions[region] = {
			alpha = region.GetAlpha and region:GetAlpha() or 1,
			shown = region.IsShown and region:IsShown() or false,
			width = w,
			height = h,
			mouseEnabled = mouse,
		}
	end
	if region.SetAlpha then
		region:SetAlpha(0)
	end
	if region.Hide then
		region:Hide()
	end
end

local function ShouldHideTexture(region)
	if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then
		return false
	end
	local tex = region.GetTexture and region:GetTexture() or nil
	if type(tex) ~= "string" or tex == "" then
		return false
	end
	local t = string.lower(tex)
	if t:find("character") then
		return true
	end
	if t:find("paperdoll") then
		return true
	end
	if t:find("parchment") then
		return true
	end
	if t:find("ui%-frame") then
		return true
	end
	if t:find("ui%-panel") then
		return true
	end
	if t:find("ui%-dialogbox") then
		return true
	end
	return false
end

local function HideFrameTextureRegions(frame)
	if not frame or not frame.GetRegions then
		return
	end
	local regions = { frame:GetRegions() }
	for _, region in ipairs(regions) do
		if ShouldHideTexture(region) then
			SaveAndHideRegion(region)
		end
	end
end

local function AggressiveStripFrame(frame)
	if not frame or not frame.GetRegions then
		return
	end
	local regions = { frame:GetRegions() }
	for _, region in ipairs(regions) do
		if region and region.GetObjectType and region:GetObjectType() == "Texture" then
			SaveAndHideRegion(region)
		end
	end
end

local function SuppressDefaultStatRows()
	for i = 1, 80 do
		local row = _G["CharacterStatFrame" .. i]
		if row then
			SaveAndHideRegion(row)
			SaveAndHideRegion(row.Label or _G[row:GetName() .. "Label"])
			SaveAndHideRegion(row.Value or _G[row:GetName() .. "Value"])
			if row.EnableMouse then
				row:EnableMouse(false)
			end
			if row.SetMouseClickEnabled then
				row:SetMouseClickEnabled(false)
			end
			if row.SetMouseMotionEnabled then
				row:SetMouseMotionEnabled(false)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Blizzard chrome hiding
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Strip all children/regions of a frame (recursive to depth)
---------------------------------------------------------------------------
local function StripFrameDeep(frame, depth)
	if not frame or (depth or 0) <= 0 then
		return
	end
	depth = depth or 1
	-- Hide all texture/fontstring regions
	if frame.GetRegions then
		for i = 1, select("#", frame:GetRegions()) do
			local region = select(i, frame:GetRegions())
			if region then
				SaveAndHideRegion(region)
			end
		end
	end
	-- Recurse into child frames
	if frame.GetChildren then
		for i = 1, select("#", frame:GetChildren()) do
			local child = select(i, frame:GetChildren())
			if child then
				StripFrameDeep(child, depth - 1)
			end
		end
	end
end

local function GetSidebarTabButton(index)
	local i = tonumber(index)
	if not i or i < 1 or i > 8 then
		return nil
	end
	local names = {
		("PaperDollSidebarTab%d"):format(i),
		("PaperDollSidebarButton%d"):format(i),
		("CharacterFrameSidebarTab%d"):format(i),
		("CharacterSidebarTab%d"):format(i),
	}
	for _, name in ipairs(names) do
		local btn = _G[name]
		if btn then
			return btn
		end
	end
	return nil
end

function Skin.HideBlizzardChrome()
	local cf = _G.CharacterFrame
	if not cf then
		return
	end

	---------------------------------------------------------------------------
	-- 1. Modern retail PortraitFrameTemplate elements
	---------------------------------------------------------------------------
	-- NineSlice border (the entire frame border)
	if cf.NineSlice then
		StripFrameDeep(cf.NineSlice, 3)
		SaveAndHideRegion(cf.NineSlice)
	end
	-- Portrait container (circle portrait top-left)
	if cf.PortraitContainer then
		StripFrameDeep(cf.PortraitContainer, 2)
		SaveAndHideRegion(cf.PortraitContainer)
	end
	-- Background texture
	SaveAndHideRegion(cf.Bg)
	SaveAndHideRegion(cf.Background)
	SaveAndHideRegion(cf.TopTileStreaks)
	-- Title bar
	SaveAndHideRegion(cf.TitleContainer)
	SaveAndHideRegion(_G.CharacterFrameTitleText)
	SaveAndHideRegion(_G.CharacterLevelText)

	---------------------------------------------------------------------------
	-- 2. Legacy named globals (older WoW versions / compatibility)
	---------------------------------------------------------------------------
	local legacyHide = {
		"CharacterFrameBg",
		"CharacterFrameTitleBg",
		"CharacterFrameTopTileStreaks",
		"CharacterFrameTopBorder",
		"CharacterFrameBotLeft",
		"CharacterFrameBotRight",
		"CharacterFramePortrait",
		"PaperDollInnerBorderBottom",
		"PaperDollInnerBorderBottom2",
		"PaperDollInnerBorderBottomLeft",
		"PaperDollInnerBorderBottomRight",
		"PaperDollInnerBorderLeft",
		"PaperDollInnerBorderRight",
		"PaperDollInnerBorderTop",
		"PaperDollInnerBorderTopLeft",
		"PaperDollInnerBorderTopRight",
		"CharacterModelFrameBackgroundTopLeft",
		"CharacterModelFrameBackgroundTopRight",
		"CharacterModelFrameBackgroundBotLeft",
		"CharacterModelFrameBackgroundBotRight",
		"CharacterModelFrameBackgroundOverlay",
		"CharacterStatsPaneItemLevelCategoryTitle",
		"CharacterStatsPaneItemLevelCategoryValue",
		"CharacterStatsPaneAttributesCategoryTitle",
		"CharacterStatsPaneEnhancementsCategoryTitle",
	}
	for _, name in ipairs(legacyHide) do
		SaveAndHideRegion(_G[name])
	end

	---------------------------------------------------------------------------
	-- 3. Insets (our custom panels replace these entirely)
	---------------------------------------------------------------------------
	for _, insetName in ipairs({ "CharacterFrameInset", "CharacterFrameInsetLeft", "CharacterFrameInsetRight" }) do
		local inset = _G[insetName]
		if inset then
			if inset.SetAlpha then
				inset:SetAlpha(0)
			end
			if inset.EnableMouse then
				inset:EnableMouse(false)
			end
			if inset.NineSlice then
				SaveAndHideRegion(inset.NineSlice)
			end
			SaveAndHideRegion(inset and inset.Bg)
		end
	end

	---------------------------------------------------------------------------
	-- 4. Stats pane (replaced by our StatsPanel)
	---------------------------------------------------------------------------
	local statsPane = _G.CharacterStatsPane
	if statsPane then
		statsPane:SetAlpha(0)
		if statsPane.EnableMouse then
			statsPane:EnableMouse(false)
		end
		if statsPane.SetMouseClickEnabled then
			statsPane:SetMouseClickEnabled(false)
		end
		if statsPane.SetMouseMotionEnabled then
			statsPane:SetMouseMotionEnabled(false)
		end
		SaveAndHideRegion(statsPane.Background)
		SaveAndHideRegion(statsPane.Bg)
		SaveAndHideRegion(statsPane.ClassBackground)
		if statsPane.NineSlice then
			SaveAndHideRegion(statsPane.NineSlice)
		end
		if statsPane.ItemLevelFrame then
			SaveAndHideRegion(statsPane.ItemLevelFrame.Value)
			SaveAndHideRegion(statsPane.ItemLevelFrame.Title)
		end
	end
	SuppressDefaultStatRows()

	---------------------------------------------------------------------------
	-- 5. PaperDoll title text
	---------------------------------------------------------------------------
	if _G.PaperDollFrame and _G.PaperDollFrame.TitleText then
		SaveAndHideRegion(_G.PaperDollFrame.TitleText)
	end

	---------------------------------------------------------------------------
	-- 6. Slot frame decorations
	---------------------------------------------------------------------------
	local slotFrameNames = {
		"CharacterBackSlotFrame",
		"CharacterChestSlotFrame",
		"CharacterFeetSlotFrame",
		"CharacterFinger0SlotFrame",
		"CharacterFinger1SlotFrame",
		"CharacterHandsSlotFrame",
		"CharacterHeadSlotFrame",
		"CharacterLegsSlotFrame",
		"CharacterMainHandSlotFrame",
		"CharacterNeckSlotFrame",
		"CharacterSecondaryHandSlotFrame",
		"CharacterShirtSlotFrame",
		"CharacterShoulderSlotFrame",
		"CharacterTabardSlotFrame",
		"CharacterTrinket0SlotFrame",
		"CharacterTrinket1SlotFrame",
		"CharacterWaistSlotFrame",
		"CharacterWristSlotFrame",
	}
	for _, name in ipairs(slotFrameNames) do
		SaveAndHideRegion(_G[name])
	end

	---------------------------------------------------------------------------
	-- 7. Model scene: strip all backgrounds and borders
	---------------------------------------------------------------------------
	local scene = _G.CharacterModelScene
	if scene then
		AggressiveStripFrame(scene)
		SaveAndHideRegion(scene.Background)
		SaveAndHideRegion(scene.BG)
		if scene.ControlFrame then
			SaveAndHideRegion(scene.ControlFrame)
		end
	end

	---------------------------------------------------------------------------
	-- 8. Blizzard tabs (we use custom tabs)
	---------------------------------------------------------------------------
	if not IsAccountTransferBuild() then
		for i = 1, 4 do
			local tab = _G["CharacterFrameTab" .. i]
			if tab then
				-- Save state for RestoreBlizzardChrome without calling Hide().
				-- Tabs must remain shown so /click macros from our custom tabs work.
				if not _hiddenRegions[tab] then
					_hiddenRegions[tab] = {
						alpha = tab.GetAlpha and tab:GetAlpha() or 1,
						shown = tab.IsShown and tab:IsShown() or true,
						width = tab.GetWidth and tab:GetWidth() or nil,
						height = tab.GetHeight and tab:GetHeight() or nil,
						mouseEnabled = tab.IsMouseEnabled and tab:IsMouseEnabled() or true,
					}
				end
				if tab.SetAlpha then
					tab:SetAlpha(0)
				end
				if tab.EnableMouse then
					tab:EnableMouse(false)
				end
				if tab.SetSize then
					tab:SetSize(0.001, 0.001)
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- 8.5. PaperDoll sidebar tabs (includes Blizzard Equipment Manager button)
	---------------------------------------------------------------------------
	if not IsAccountTransferBuild() then
		for i = 1, 8 do
			local btn = GetSidebarTabButton(i)
			if btn then
				SaveAndHideRegion(btn)
				if btn.SetAlpha then
					btn:SetAlpha(0)
				end
				if btn.EnableMouse then
					btn:EnableMouse(false)
				end
				if btn.SetSize then
					btn:SetSize(0.001, 0.001)
				end
				if btn.Hide then
					btn:Hide()
				end

				local icon = btn.Icon or btn.icon or (btn.GetName and _G[btn:GetName() .. "Icon"]) or nil
				if icon then
					SaveAndHideRegion(icon)
				end
				if btn.GetNormalTexture then
					SaveAndHideRegion(btn:GetNormalTexture())
				end
				if btn.GetPushedTexture then
					SaveAndHideRegion(btn:GetPushedTexture())
				end
				if btn.GetHighlightTexture then
					SaveAndHideRegion(btn:GetHighlightTexture())
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- 9. Aggressive texture strip on main frames
	---------------------------------------------------------------------------
	HideFrameTextureRegions(cf)
	HideFrameTextureRegions(_G.PaperDollFrame)
end

function Skin.RestoreBlizzardChrome()
	for region, state in pairs(_hiddenRegions) do
		if region then
			if region.SetAlpha and state.alpha ~= nil then
				region:SetAlpha(state.alpha)
			end
			if state.width and state.height and region.SetSize then
				region:SetSize(state.width, state.height)
			end
			if state.mouseEnabled ~= nil and region.EnableMouse then
				region:EnableMouse(state.mouseEnabled)
			end
			if region.SetShown then
				region:SetShown(state.shown == true)
			elseif state.shown and region.Show then
				region:Show()
			end
		end
	end
	wipe(_hiddenRegions)

	-- Re-enable mouse on stats pane
	if _G.CharacterStatsPane then
		_G.CharacterStatsPane:EnableMouse(true)
		if _G.CharacterStatsPane.SetMouseClickEnabled then
			_G.CharacterStatsPane:SetMouseClickEnabled(true)
		end
		if _G.CharacterStatsPane.SetMouseMotionEnabled then
			_G.CharacterStatsPane:SetMouseMotionEnabled(true)
		end
	end
	for _, frame in ipairs({ _G.CharacterFrameInset, _G.CharacterFrameInsetLeft, _G.CharacterFrameInsetRight }) do
		if frame and frame.EnableMouse then
			frame:EnableMouse(true)
		end
	end

	for i = 1, 3 do
		local tab = _G and _G[("CharacterFrameTab%d"):format(i)] or nil
		local skin = tab and _nativeTabSkins[tab] or nil
		if skin then
			if skin.bg and skin.bg.Hide then
				skin.bg:Hide()
			end
			if skin.top and skin.top.Hide then
				skin.top:Hide()
			end
			if skin.bottom and skin.bottom.Hide then
				skin.bottom:Hide()
			end
			if skin.left and skin.left.Hide then
				skin.left:Hide()
			end
			if skin.right and skin.right.Hide then
				skin.right:Hide()
			end
		end
	end

	-- Re-enable stat rows
	for i = 1, 80 do
		local row = _G["CharacterStatFrame" .. i]
		if row then
			if row.EnableMouse then
				row:EnableMouse(true)
			end
			if row.SetMouseClickEnabled then
				row:SetMouseClickEnabled(true)
			end
			if row.SetMouseMotionEnabled then
				row:SetMouseMotionEnabled(true)
			end
		end
	end
end

local function GetCharacterTabTextRegion(tab)
	if not tab then
		return nil
	end
	if tab.Text then
		return tab.Text
	end
	if tab.text then
		return tab.text
	end
	if tab.GetName then
		local name = tab:GetName()
		if type(name) == "string" and name ~= "" then
			local text = _G[name .. "Text"]
			if text then
				return text
			end
		end
	end
	return nil
end

local function IsCharacterTabSelected(tab)
	if not tab then
		return false
	end
	if CharacterFrame and PanelTemplates_GetSelectedTab and tab.GetID then
		local selectedID = PanelTemplates_GetSelectedTab(CharacterFrame)
		local tabID = tab:GetID()
		if selectedID and tabID then
			return selectedID == tabID
		end
	end
	if tab.IsEnabled then
		return tab:IsEnabled() == false
	end
	return false
end

local function EnsureCharacterTabSkin(tab)
	if not tab then
		return nil
	end
	if _nativeTabSkins[tab] then
		return _nativeTabSkins[tab]
	end

	local textureKeys = {
		"Left",
		"Middle",
		"Right",
		"LeftActive",
		"MiddleActive",
		"RightActive",
		"LeftDisabled",
		"MiddleDisabled",
		"RightDisabled",
		"LeftHighlight",
		"MiddleHighlight",
		"RightHighlight",
		"HighlightTexture",
	}
	for _, key in ipairs(textureKeys) do
		local tex = tab[key]
		if tex then
			SaveAndHideRegion(tex)
		end
	end
	if tab.GetNormalTexture then
		SaveAndHideRegion(tab:GetNormalTexture())
	end
	if tab.GetPushedTexture then
		SaveAndHideRegion(tab:GetPushedTexture())
	end
	if tab.GetHighlightTexture then
		SaveAndHideRegion(tab:GetHighlightTexture())
	end
	if tab.GetDisabledTexture then
		SaveAndHideRegion(tab:GetDisabledTexture())
	end

	local bg = tab:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", tab, "TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 1)

	local top = tab:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0)
	top:SetHeight(1)

	local bottom = tab:CreateTexture(nil, "BORDER")
	bottom:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(1)

	local left = tab:CreateTexture(nil, "BORDER")
	left:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
	left:SetWidth(1)

	local right = tab:CreateTexture(nil, "BORDER")
	right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(1)

	local skin = {
		bg = bg,
		top = top,
		bottom = bottom,
		left = left,
		right = right,
	}
	_nativeTabSkins[tab] = skin
	return skin
end

local function RefreshCharacterTabSkin(tab)
	local skin = EnsureCharacterTabSkin(tab)
	if not skin then
		return
	end

	local selected = IsCharacterTabSelected(tab)
	skin.bg:SetColorTexture(0.03, 0.02, 0.05, 0.92)

	local br, bg, bb, ba = 0.24, 0.18, 0.32, 0.95
	if selected then
		br, bg, bb, ba = 0.98, 0.64, 0.14, 0.98
	end

	skin.top:SetColorTexture(br, bg, bb, ba)
	skin.bottom:SetColorTexture(br, bg, bb, ba)
	skin.left:SetColorTexture(br, bg, bb, ba)
	skin.right:SetColorTexture(br, bg, bb, ba)

	local text = GetCharacterTabTextRegion(tab)
	if text then
		if NS and NS.ApplyDefaultFont then
			NS:ApplyDefaultFont(text, 10)
		end
		if selected then
			text:SetTextColor(1.00, 0.82, 0.40, 1)
		else
			text:SetTextColor(0.95, 0.95, 0.95, 1)
		end
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(1, -1)
	end
end

function Skin.ApplyNativeBottomTabSkin()
	if not IsAccountTransferBuild() then
		return
	end
	for i = 1, 3 do
		local tab = _G and _G[("CharacterFrameTab%d"):format(i)] or nil
		if tab then
			RefreshCharacterTabSkin(tab)
		end
	end
end

---------------------------------------------------------------------------
-- Slot button skinning
---------------------------------------------------------------------------
local function EnsureSlotSkin(slotButton)
	if not slotButton then
		return nil
	end
	if _slotSkins[slotButton] then
		local existing = _slotSkins[slotButton]
		existing:ClearAllPoints()
		existing:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
		existing:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
		return existing
	end

	local holder = CreateFrame("Frame", nil, slotButton, "BackdropTemplate")
	holder:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
	holder:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
	holder:SetFrameLevel(math.max(0, (slotButton:GetFrameLevel() or 1) - 1))
	holder:SetBackdrop({
		bgFile = "Interface/Buttons/WHITE8x8",
		edgeFile = "Interface/Buttons/WHITE8x8",
		edgeSize = 1,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	holder:SetBackdropColor(0.05, 0.02, 0.08, 0.90)
	holder:SetBackdropBorderColor(0.35, 0.18, 0.55, 0.95)
	holder:Hide()

	_slotSkins[slotButton] = holder
	return holder
end

function Skin.SkinAllSlotButtons()
	for _, name in ipairs(CFG.CHARACTER_SLOT_BUTTON_NAMES) do
		local btn = _G[name]
		if btn then
			if btn.SetSize then
				btn:SetSize(CFG.SLOT_ICON_SIZE, CFG.SLOT_ICON_SIZE)
			end
			if btn.SetSnapToPixelGrid then
				btn:SetSnapToPixelGrid(true)
			end
			if btn.SetTexelSnappingBias then
				btn:SetTexelSnappingBias(0)
			end
			if btn.SetScale then
				btn:SetScale(1)
			end

			local skin = EnsureSlotSkin(btn)
			if skin then
				skin:Show()
			end

			-- Icon cropping
			local icon = _G[name .. "IconTexture"] or btn.icon or btn.Icon
			if icon and icon.SetTexCoord then
				icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				if icon.SetSnapToPixelGrid then
					icon:SetSnapToPixelGrid(true)
				end
				if icon.SetTexelSnappingBias then
					icon:SetTexelSnappingBias(0)
				end
			end
			if icon and icon.SetDrawLayer then
				icon:SetDrawLayer("ARTWORK", 7)
			end

			-- Hide default decoration textures
			SaveAndHideRegion(_G[name .. "NormalTexture"])
			SaveAndHideRegion(_G[name .. "HighlightTexture"])
			SaveAndHideRegion(_G[name .. "Background"])

			-- Weapon/offhand slots need extra stripping
			if name == "CharacterMainHandSlot" or name == "CharacterSecondaryHandSlot" then
				SaveAndHideRegion(btn.BottomLeftSlotTexture)
				SaveAndHideRegion(btn.BottomRightSlotTexture)
				SaveAndHideRegion(btn.SlotTexture)
				SaveAndHideRegion(btn.IconOverlay)
				SaveAndHideRegion(btn.PopoutButton)
				SaveAndHideRegion(btn.ShadowOverlay)
				SaveAndHideRegion(btn.Border)
				SaveAndHideRegion(_G[name .. "PopoutButton"])
				SaveAndHideRegion(_G[name .. "SlotTexture"])
				SaveAndHideRegion(_G[name .. "ShadowOverlay"])
				SaveAndHideRegion(_G[name .. "IconOverlay"])
				SaveAndHideRegion(_G[name .. "Border"])

				if btn.GetChildren then
					for i = 1, select("#", btn:GetChildren()) do
						local child = select(i, btn:GetChildren())
						if child then
							local childName = child.GetName and child:GetName()
							if childName and childName:find("Popout") then
								SaveAndHideRegion(child)
								if child.EnableMouse then
									child:EnableMouse(false)
								end
							end
						end
					end
				end
				-- Strip remaining decorative textures
				if btn.GetRegions then
					for i = 1, select("#", btn:GetRegions()) do
						local region = select(i, btn:GetRegions())
						if region and region.GetObjectType and region:GetObjectType() == "Texture" then
							if region ~= icon and region ~= btn.IconBorder and region ~= btn.icon then
								SaveAndHideRegion(region)
							end
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Slot positioning (ported from Legacy ApplyChonkySlotLayout)
---------------------------------------------------------------------------
function Skin.ApplyChonkySlotLayout()
	local anchor = CharacterFrame
	if not anchor then
		return
	end

	local head = _G.CharacterHeadSlot
	local neck = _G.CharacterNeckSlot
	local shoulder = _G.CharacterShoulderSlot
	local back = _G.CharacterBackSlot
	local chest = _G.CharacterChestSlot
	local shirt = _G.CharacterShirtSlot
	local tabard = _G.CharacterTabardSlot
	local wrist = _G.CharacterWristSlot
	local hands = _G.CharacterHandsSlot
	local waist = _G.CharacterWaistSlot
	local legs = _G.CharacterLegsSlot
	local feet = _G.CharacterFeetSlot
	local finger0 = _G.CharacterFinger0Slot
	local finger1 = _G.CharacterFinger1Slot
	local trinket0 = _G.CharacterTrinket0Slot
	local trinket1 = _G.CharacterTrinket1Slot
	local mainHand = _G.CharacterMainHandSlot
	local offHand = _G.CharacterSecondaryHandSlot

	if
		not (
			head
			and neck
			and shoulder
			and back
			and chest
			and shirt
			and tabard
			and wrist
			and hands
			and waist
			and legs
			and feet
			and finger0
			and finger1
			and trinket0
			and trinket1
			and mainHand
			and offHand
		)
	then
		return
	end

	local leftCluster = CFG.LeftGearCluster or {}
	local rightCluster = CFG.RightGearCluster or {}
	local weaponCluster = CFG.WeaponGearCluster or {}
	local slotSize = CFG.SLOT_ICON_SIZE
	local stride = slotSize + CFG.SLOT_VPAD
	local topY = CFG.SLOT_TOP_Y
	local leftX = tonumber(leftCluster.IconX) or CFG.SLOT_LEFT_X
	local frameWidth = anchor:GetWidth() or math.floor(CFG.BASE_FRAME_WIDTH * CFG.FRAME_EXPAND_FACTOR + 0.5)
	local statsWidth = CFG.BASE_STATS_WIDTH
	local rightInset = tonumber(rightCluster.ColumnInset) or CFG.SLOT_RIGHT_COLUMN_INSET
	local rightOffsetX = tonumber(rightCluster.ColumnOffsetX)
	if rightOffsetX == nil then
		rightOffsetX = -(CFG.RIGHT_ICON_COLUMN_SHIFT_X or 0)
	end
	local rightColumnBaseX = frameWidth - statsWidth - rightInset
	local rightColumnX = rightColumnBaseX + rightOffsetX

	local leftSlots = { head, neck, shoulder, back, chest, shirt, tabard, wrist }
	local rightSlots = { hands, waist, legs, feet, finger0, finger1, trinket0, trinket1 }

	for i, slot in ipairs(leftSlots) do
		slot:SetSize(slotSize, slotSize)
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", anchor, "TOPLEFT", leftX, topY - stride * (i - 1))
	end
	for i, slot in ipairs(rightSlots) do
		slot:SetSize(slotSize, slotSize)
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", anchor, "TOPLEFT", rightColumnX, topY - stride * (i - 1))
	end

	-- Weapons: centered between columns at bottom
	local pairGapX = tonumber(weaponCluster.PairGapX) or CFG.SLOT_WEAPON_PAIR_GAP
	local weaponBottomY = tonumber(weaponCluster.BottomY) or CFG.SLOT_WEAPON_BOTTOM_Y
	local weaponOffsetX = tonumber(weaponCluster.OffsetX) or 0
	local leftColumnCenter = leftX + (slotSize * 0.5)
	local rightColumnCenter = rightColumnX + (slotSize * 0.5)
	local centerX = math.floor(((leftColumnCenter + rightColumnCenter) * 0.5) + 0.5)
	local mainHandX = math.floor((centerX - (pairGapX * 0.5) - (slotSize * 0.5) + weaponOffsetX) + 0.5)

	mainHand:SetSize(slotSize, slotSize)
	mainHand:ClearAllPoints()
	mainHand:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", mainHandX, weaponBottomY)
	offHand:SetSize(slotSize, slotSize)
	offHand:ClearAllPoints()
	offHand:SetPoint("TOPLEFT", mainHand, "TOPLEFT", pairGapX, 0)
end

---------------------------------------------------------------------------
-- Model layout (ported from Legacy ApplyChonkyModelLayout)
---------------------------------------------------------------------------
local _modelFillFrame = nil

local function EnsureModelFillFrame()
	if _modelFillFrame then
		return _modelFillFrame
	end
	local cf = CharacterFrame
	if not cf then
		return nil
	end

	_modelFillFrame = CreateFrame("Frame", nil, cf)
	_modelFillFrame:SetFrameStrata(cf:GetFrameStrata() or "HIGH")
	_modelFillFrame:SetFrameLevel((cf:GetFrameLevel() or 1) + 2)

	_modelFillFrame.base = _modelFillFrame:CreateTexture(nil, "BACKGROUND")
	_modelFillFrame.base:SetAllPoints()
	_modelFillFrame.base:SetColorTexture(0, 0, 0, 0.0)

	_modelFillFrame.overlay = _modelFillFrame:CreateTexture(nil, "BORDER")
	_modelFillFrame.overlay:SetAllPoints()
	_modelFillFrame.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
	-- Purple at top -> black at bottom
	Skin.SetVerticalGradient(_modelFillFrame.overlay, 0.08, 0.02, 0.12, 0.90, 0, 0, 0, 0.90)

	_modelFillFrame:Hide()
	return _modelFillFrame
end

function Skin.ApplyCharacterPanelGradient()
	local fill = EnsureModelFillFrame()
	if not fill then
		return
	end
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 2, -2)
	fill:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -2, 2)
	fill:Show()
end

function Skin.HideCharacterPanelGradient()
	if _modelFillFrame then
		_modelFillFrame:Hide()
	end
end

function Skin.ApplyChonkyModelLayout()
	local model = _G.CharacterModelScene
	if not model then
		return
	end

	local fill = EnsureModelFillFrame()
	local slotSize = CFG.SLOT_ICON_SIZE
	local leftCluster = CFG.LeftGearCluster or {}
	local rightCluster = CFG.RightGearCluster or {}
	local leftX = tonumber(leftCluster.IconX) or CFG.SLOT_LEFT_X
	local defaultW = math.floor(CFG.BASE_FRAME_WIDTH * CFG.FRAME_EXPAND_FACTOR + 0.5)
	local frameWidth = CharacterFrame and CharacterFrame:GetWidth() or defaultW
	local statsWidth = CFG.BASE_STATS_WIDTH
	local rightInset = tonumber(rightCluster.ColumnInset) or CFG.SLOT_RIGHT_COLUMN_INSET
	local rightOffsetX = tonumber(rightCluster.ColumnOffsetX)
	if rightOffsetX == nil then
		rightOffsetX = -(CFG.RIGHT_ICON_COLUMN_SHIFT_X or 0)
	end
	local rightColumnX = frameWidth - statsWidth - rightInset + rightOffsetX

	local leftColumnCenter = leftX + (slotSize * 0.5)
	local rightColumnCenter = rightColumnX + (slotSize * 0.5)
	local slotMidX = (leftColumnCenter + rightColumnCenter) * 0.5

	local boxWidth = 356
	local boxTop, boxBottom = -84, 46
	local boxLeft = math.floor(slotMidX - (boxWidth * 0.5) + 0.5)
	local boxRight = boxLeft + boxWidth

	model:ClearAllPoints()
	model:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", boxLeft, boxTop)
	model:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", boxRight, boxBottom)

	-- Suppress borders
	Skin.SuppressModelBorders()

	if model.SetFrameLevel then
		model:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 3)
	end
	if model.EnableMouse then
		model:EnableMouse(true)
	end
	if model.EnableMouseWheel then
		model:EnableMouseWheel(false)
	end
	if model.SetScript then
		model:SetScript("OnMouseWheel", function() end)
	end
	if model.SetPropagateMouseClicks then
		model:SetPropagateMouseClicks(false)
	end
	if model.SetPropagateMouseMotion then
		model:SetPropagateMouseMotion(false)
	end

	if model.ControlFrame then
		SaveAndHideRegion(model.ControlFrame)
		if model.ControlFrame.EnableMouse then
			model.ControlFrame:EnableMouse(true)
		end
		if model.ControlFrame.EnableMouseWheel then
			model.ControlFrame:EnableMouseWheel(false)
		end
		if model.ControlFrame.GetChildren then
			for i = 1, select("#", model.ControlFrame:GetChildren()) do
				local child = select(i, model.ControlFrame:GetChildren())
				if child then
					SaveAndHideRegion(child)
					if child.EnableMouse then
						child:EnableMouse(false)
					end
				end
			end
		end
	end

	if fill then
		fill:ClearAllPoints()
		fill:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 2, -2)
		fill:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -2, 2)
		fill:Show()
	end
end

---------------------------------------------------------------------------
-- Slot position enforcer (fights Blizzard late re-anchoring)
---------------------------------------------------------------------------
local _slotEnforcer = nil
local _slotEnforceUntil = 0

function Skin.StartSlotEnforcer()
	if not _slotEnforcer then
		_slotEnforcer = CreateFrame("Frame")
		_slotEnforcer:Hide()
		_slotEnforcer:SetScript("OnUpdate", function(self)
			if GetTime() >= _slotEnforceUntil then
				self:Hide()
				return
			end
			Skin.ApplyChonkySlotLayout()
		end)
	end
	_slotEnforceUntil = GetTime() + 1.5
	_slotEnforcer:Show()
end

function Skin.StopSlotEnforcer()
	if _slotEnforcer then
		_slotEnforcer:Hide()
	end
end

function Skin.UpdateSlotBorder(btn, quality, isTier, classR, classG, classB)
	local skin = btn and _slotSkins[btn]
	if not skin then
		return
	end
	if isTier and classR then
		skin:SetBackdropBorderColor(classR, classG, classB, 1.0)
	elseif quality and quality >= 2 then
		local grad = CFG.RARITY_GRADIENT[quality]
		if grad then
			skin:SetBackdropBorderColor(grad[5], grad[6], grad[7], grad[8])
		end
	else
		skin:SetBackdropBorderColor(0.35, 0.18, 0.55, 0.95)
	end
end

---------------------------------------------------------------------------
-- Tooltip parsing: enchants, upgrade tracks, tier sets
---------------------------------------------------------------------------
local function Trim(s)
	if type(s) ~= "string" then
		return ""
	end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function StripColorAndTextureCodes(s)
	if type(s) ~= "string" then
		return ""
	end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", "")
	s = s:gsub("|A.-|a", "")
	s = s:gsub("|T.-|t", "")
	return Trim(s)
end

local function GetTooltipLines(invID)
	if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem and invID) then
		return {}
	end
	local link = GetInventoryItemLink and GetInventoryItemLink("player", invID) or nil
	local cached = _tooltipCache[invID]
	if cached and cached.link == link and type(cached.lines) == "table" then
		return cached.lines
	end
	local ok, info = pcall(C_TooltipInfo.GetInventoryItem, "player", invID)
	if not ok or type(info) ~= "table" or type(info.lines) ~= "table" then
		_tooltipCache[invID] = { link = link, lines = {} }
		return {}
	end
	_tooltipCache[invID] = { link = link, lines = info.lines }
	return info.lines
end

function Skin.InvalidateTooltipCache()
	wipe(_tooltipCache)
end

function Skin.ParseEnchantName(itemLink)
	if type(itemLink) ~= "string" then
		return ""
	end
	local enchantID = tonumber(itemLink:match("^|?c?[^|]*|?Hitem:%d+:(%-?%d+)")) or 0
	if enchantID and enchantID > 0 then
		local name
		if C_Spell and type(C_Spell.GetSpellName) == "function" then
			name = C_Spell.GetSpellName(enchantID)
		end
		if (not name or name == "") and type(GetSpellInfo) == "function" then
			name = GetSpellInfo(enchantID)
		end
		if name and name ~= "" then
			return name
		end
	end
	return ""
end

function Skin.GetEnchantFromTooltip(invID)
	local lines = GetTooltipLines(invID)
	if type(lines) ~= "table" or #lines == 0 then
		return ""
	end

	local localizedPattern = nil
	local template = _G and _G.ENCHANTED_TOOLTIP_LINE or nil
	if type(template) == "string" and template ~= "" then
		localizedPattern = "^" .. template:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
	end

	for _, line in ipairs(lines) do
		if type(line) == "table" then
			local clean = StripColorAndTextureCodes(line.leftText)
			if clean ~= "" then
				local enchantName = nil
				if localizedPattern then
					enchantName = clean:match(localizedPattern)
				end
				if not enchantName then
					enchantName = clean:match("^Enchanted:%s*(.+)$")
				end
				if enchantName and enchantName ~= "" then
					return Trim(enchantName)
				end
			end
		end
	end
	return ""
end

function Skin.GetUpgradeTrack(invID)
	local lines = GetTooltipLines(invID)
	for _, line in ipairs(lines) do
		if type(line) == "table" then
			local candidates = { line.leftText, line.rightText }
			for _, raw in ipairs(candidates) do
				if type(raw) == "string" and raw ~= "" then
					local clean = StripColorAndTextureCodes(raw)
					if clean:find("%d+/%d+") then
						local inParens = clean:match("%(([^)]*%d+/%d+[^)]*)%)")
						if inParens and inParens ~= "" then
							return Trim(inParens)
						end
						local bare = clean:match("([%a][%a%s%-']-%d+/%d+)")
						if bare and bare ~= "" then
							return Trim(bare)
						end
					end
				end
			end
		end
	end
	return ""
end

function Skin.GetUpgradeTrackColor(trackText)
	if type(trackText) ~= "string" or trackText == "" then
		return 0.98, 0.90, 0.35
	end
	local lower = trackText:lower()
	for key, color in pairs(UPGRADE_TRACK_COLORS) do
		if lower:find(key, 1, true) then
			return color[1], color[2], color[3]
		end
	end
	return 0.98, 0.90, 0.35
end

local function GetEnchantQualityTier(invID)
	local function ParseTierToken(s)
		if type(s) ~= "string" then
			return nil
		end
		local tier = tonumber(s:match("Professions[^|]-Tier(%d)"))
			or tonumber(s:match("[Qq]uality%-Tier(%d)"))
			or tonumber(s:match("Tier(%d)"))
		if tier and tier >= 1 and tier <= 3 then
			return tier
		end
		return nil
	end
	local function ScanForTier(value, depth)
		depth = depth or 0
		if depth > 5 or value == nil then
			return nil
		end
		if type(value) == "string" then
			return ParseTierToken(value)
		end
		if type(value) == "table" then
			for _, v in pairs(value) do
				local tier = ScanForTier(v, depth + 1)
				if tier then
					return tier
				end
			end
		end
		return nil
	end
	local lines = GetTooltipLines(invID)
	for _, line in ipairs(lines) do
		local tier = ScanForTier(line, 0)
		if tier then
			return tier
		end
	end
	return nil
end

local function GetEnchantQualityAtlasFromTooltip(invID)
	local function Scan(value, depth)
		depth = depth or 0
		if depth > 6 or value == nil then
			return nil
		end
		if type(value) == "string" then
			local atlas = value:match("|A:([^:|]+):")
			if atlas and (atlas:lower():find("quality", 1, true) or atlas:lower():find("tier", 1, true)) then
				return atlas
			end
			atlas = value:match("(Professions[%w%-_]*Quality[%w%-_]*)")
				or value:match("(Professions[%w%-_]*Tier[%w%-_]*)")
			if atlas then
				return atlas
			end
			return nil
		end
		if type(value) == "table" then
			for _, v in pairs(value) do
				local atlas = Scan(v, depth + 1)
				if atlas then
					return atlas
				end
			end
		end
		return nil
	end
	local lines = GetTooltipLines(invID)
	for _, line in ipairs(lines) do
		local atlas = Scan(line, 0)
		if atlas then
			return atlas
		end
	end
	return nil
end

local function ResolveEnchantQualityAtlas(tier)
	local candidates = ENCHANT_QUALITY_ATLAS[tier]
	if type(candidates) ~= "table" then
		return nil
	end
	for _, atlas in ipairs(candidates) do
		if atlas and atlas ~= "" then
			if C_Texture and C_Texture.GetAtlasInfo then
				local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
				if ok and info then
					return atlas
				end
			else
				return atlas
			end
		end
	end
	return candidates[1]
end

function Skin.GetEnchantQualityMarkup(invID, enchantText, tierHint)
	if type(enchantText) ~= "string" or enchantText == "" then
		return ""
	end
	local tier = tierHint or GetEnchantQualityTier(invID) or 1
	if tier < 1 then
		tier = 1
	end
	if tier > 3 then
		tier = 3
	end
	local atlas = GetEnchantQualityAtlasFromTooltip(invID) or ResolveEnchantQualityAtlas(tier)
	if not atlas or atlas == "" then
		atlas = ("Professions-ChatIcon-Quality-Tier%d"):format(tier)
	end
	return (" |A:%s:%d:%d:0:0|a"):format(atlas, CFG.ENCHANT_QUALITY_MARKUP_SIZE, CFG.ENCHANT_QUALITY_MARKUP_SIZE)
end

function Skin.IsTierSetItem(itemLink, invID)
	if type(itemLink) ~= "string" or type(GetItemInfoInstant) ~= "function" then
		return invID and Skin.HasSetBonusMarker(invID) or false
	end
	local _, _, _, equipLoc, _, _, _, _, _, setID = GetItemInfoInstant(itemLink)
	if not setID or setID <= 0 then
		return invID and Skin.HasSetBonusMarker(invID) or false
	end
	return equipLoc == "INVTYPE_HEAD"
		or equipLoc == "INVTYPE_SHOULDER"
		or equipLoc == "INVTYPE_CHEST"
		or equipLoc == "INVTYPE_ROBE"
		or equipLoc == "INVTYPE_HAND"
		or equipLoc == "INVTYPE_LEGS"
end

function Skin.HasSetBonusMarker(invID)
	local lines = GetTooltipLines(invID)
	for _, line in ipairs(lines) do
		if type(line) == "table" then
			local candidates = { line.leftText, line.rightText }
			for _, raw in ipairs(candidates) do
				if type(raw) == "string" and raw ~= "" then
					local clean = StripColorAndTextureCodes(raw)
					if clean:find("%(%d+/%d+%)") then
						local lower = clean:lower()
						if
							not lower:find("adventurer", 1, true)
							and not lower:find("veteran", 1, true)
							and not lower:find("champion", 1, true)
							and not lower:find("hero", 1, true)
							and not lower:find("myth", 1, true)
							and not lower:find("explorer", 1, true)
						then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

function Skin.CanSlotHaveEnchant(slotName, itemLink)
	if
		slotName == "NeckSlot"
		or slotName == "BackSlot"
		or slotName == "ChestSlot"
		or slotName == "WristSlot"
		or slotName == "FeetSlot"
		or slotName == "Finger0Slot"
		or slotName == "Finger1Slot"
	then
		return true
	end
	if slotName == "MainHandSlot" or slotName == "SecondaryHandSlot" then
		if type(itemLink) == "string" and type(GetItemInfoInstant) == "function" then
			local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
			if slotName == "MainHandSlot" then
				return equipLoc == "INVTYPE_WEAPON"
					or equipLoc == "INVTYPE_2HWEAPON"
					or equipLoc == "INVTYPE_WEAPONMAINHAND"
			else
				return equipLoc == "INVTYPE_WEAPON"
					or equipLoc == "INVTYPE_WEAPONOFFHAND"
					or equipLoc == "INVTYPE_SHIELD"
			end
		end
		return true
	end
	return false
end

function Skin.CanSlotHaveGem(slotName)
	return slotName == "NeckSlot"
		or slotName == "Finger0Slot"
		or slotName == "Finger1Slot"
		or slotName == "WristSlot"
		or slotName == "WaistSlot"
		or slotName == "HeadSlot"
end

---------------------------------------------------------------------------
-- Gem / socket info
---------------------------------------------------------------------------
local EMPTY_SOCKET_TEXTURE = 458977  -- Interface/ItemSocketingFrame/UI-EmptySocket-Prismatic

function Skin.GetGemInfo(invID, itemLink)
	if not (invID and itemLink) then return nil end

	-- Count total sockets from tooltip (includes empty ones)
	local lines = GetTooltipLines(invID)
	local totalSockets = 0
	for _, line in ipairs(lines) do
		local text = line and line.leftText
		if type(text) == "string" and text:find("Socket", 1, true) then
			-- Match socket type lines like "Prismatic Socket", "Red Socket", etc.
			-- but NOT "Socket Bonus:" or similar
			if not text:find("Bonus", 1, true) and not text:find("Effect", 1, true) then
				totalSockets = totalSockets + 1
			end
		end
	end

	if totalSockets == 0 then return nil end

	-- Gather gem data for each socket
	local sockets = {}
	for i = 1, totalSockets do
		local gemName, gemLink
		if _G.GetItemGem then
			gemName, gemLink = _G.GetItemGem(itemLink, i)
		end
		if gemLink then
			-- select(10, GetItemInfo) returns the item icon texture
			local gemIcon = select(10, GetItemInfo(gemLink))
			sockets[#sockets + 1] = {
				name = gemName,
				link = gemLink,
				icon = gemIcon or 134400,
				empty = false,
			}
		else
			sockets[#sockets + 1] = {
				name = nil,
				link = nil,
				icon = EMPTY_SOCKET_TEXTURE,
				empty = true,
			}
		end
	end

	return #sockets > 0 and sockets or nil
end

---------------------------------------------------------------------------
-- Class color / utility
---------------------------------------------------------------------------
function Skin.GetPlayerClassColor()
	local _, classTag = UnitClass("player")
	if classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag] then
		local c = RAID_CLASS_COLORS[classTag]
		return c.r or 1, c.g or 1, c.b or 1
	end
	if C_ClassColor and C_ClassColor.GetClassColor and classTag then
		local c = C_ClassColor.GetClassColor(classTag)
		if c then
			return c:GetRGB()
		end
	end
	return TIER_CLASS_COLOR_FALLBACK[1], TIER_CLASS_COLOR_FALLBACK[2], TIER_CLASS_COLOR_FALLBACK[3]
end

function Skin.RGBToHex(r, g, b)
	local function Clamp255(v)
		v = tonumber(v) or 0
		if v < 0 then
			v = 0
		end
		if v > 1 then
			v = 1
		end
		return math.floor((v * 255) + 0.5)
	end
	return ("%02x%02x%02x"):format(Clamp255(r), Clamp255(g), Clamp255(b))
end

---------------------------------------------------------------------------
-- Polish: custom header, close button glyph, model border suppression
---------------------------------------------------------------------------
local _polishState = {
	headerFrame = nil,
	customNameText = nil,
	customLevelText = nil,
	closeBg = nil,
	closeBorder = nil,
	closeGlow = nil,
	closeGlyph = nil,
	closeHooked = false,
}

-- Offset to center name/title over the model area (left of stats panel)
local HEADER_TEXT_X_OFFSET = -144

function Skin.ApplyCustomHeader(forcedTitleID)
	if not CharacterFrame then
		return
	end

	local name = UnitName and UnitName("player") or ""
	local _, classTag = UnitClass and UnitClass("player") or nil, nil
	if UnitClass then
		_, classTag = UnitClass("player")
	end
	local c = (classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag])
		or (NORMAL_FONT_COLOR or { r = 1, g = 1, b = 1 })
	local nameHex = ("|cff%02x%02x%02x"):format(
		math.floor((c.r or 1) * 255 + 0.5),
		math.floor((c.g or 1) * 255 + 0.5),
		math.floor((c.b or 1) * 255 + 0.5)
	)
	local titleHex = "|cfff5f5f5"

	-- Build contextual title + name text
	local currentTitleID = tonumber(forcedTitleID)
	if not currentTitleID then
		currentTitleID = GetCurrentTitle and GetCurrentTitle() or 0
	end
	local rawTitleText = ""
	if currentTitleID > 0 and GetTitleName then
		local raw = GetTitleName(currentTitleID)
		if type(raw) == "string" then
			rawTitleText = raw
		end
	end

	local function BuildContextualTitleText(rawTitle, playerName)
		if type(rawTitle) ~= "string" or rawTitle == "" then
			return ""
		end
		if type(playerName) ~= "string" then
			playerName = ""
		end

		local function TrimText(text)
			if type(text) ~= "string" then
				return ""
			end
			return text:gsub("^%s+", ""):gsub("%s+$", "")
		end

		local function EnsureNameComma(text)
			if type(text) ~= "string" or text == "" or playerName == "" then
				return text
			end
			local escapedName = playerName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
			local tail = text:match("^" .. escapedName .. "(.*)$")
			if not tail or tail == "" then
				return text
			end
			if tail:match("^%s*[,%.:;!%?]") then
				return text
			end
			tail = tail:gsub("^%s+", "")
			if tail == "" then
				return text
			end
			return playerName .. ", " .. tail
		end

		local replaced = rawTitle
		local replacedAny = false
		local count = 0
		replaced, count = replaced:gsub("%%(%d+)%$s", playerName)
		if count and count > 0 then
			replacedAny = true
		end
		replaced, count = replaced:gsub("%%s", playerName)
		if count and count > 0 then
			replacedAny = true
		end
		if replacedAny then
			return EnsureNameComma(TrimText(replaced))
		end

		if playerName ~= "" and rawTitle:find(playerName, 1, true) then
			return EnsureNameComma(TrimText(rawTitle))
		end

		local clean = TrimText(rawTitle)
		if clean == "" then
			return ""
		end
		if playerName == "" then
			return clean
		end
		if rawTitle:find("%s$") then
			return rawTitle:gsub("%s+$", " ") .. playerName
		end
		if clean:match("^[,%.:;!%?]") then
			return playerName .. clean
		end
		return playerName .. ", " .. clean
	end

	local displayTitle = BuildContextualTitleText(rawTitleText, name)
	local headerText
	if displayTitle ~= "" then
		if name ~= "" then
			local startPos, endPos = displayTitle:find(name, 1, true)
			if startPos and endPos then
				local before = displayTitle:sub(1, startPos - 1)
				local after = displayTitle:sub(endPos + 1)
				headerText = titleHex .. before .. "|r" .. nameHex .. name .. "|r" .. titleHex .. after .. "|r"
			else
				headerText = titleHex .. displayTitle .. "|r"
			end
		else
			headerText = titleHex .. displayTitle .. "|r"
		end
	else
		headerText = nameHex .. name .. "|r"
	end

	-- Ensure high-level header frame so text appears above the root overlay
	if not _polishState.headerFrame then
		_polishState.headerFrame = CreateFrame("Frame", nil, CharacterFrame)
		_polishState.headerFrame:SetAllPoints(CharacterFrame)
		_polishState.headerFrame:SetFrameStrata("HIGH")
		_polishState.headerFrame:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 40)
	end

	-- Create or update custom name fontstring
	if not _polishState.customNameText then
		_polishState.customNameText =
			_polishState.headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	end
	_polishState.customNameText:ClearAllPoints()
	_polishState.customNameText:SetPoint("TOP", CharacterFrame, "TOP", HEADER_TEXT_X_OFFSET, -8)
	_polishState.customNameText:SetJustifyH("CENTER")
	_polishState.customNameText:SetDrawLayer("OVERLAY", 7)
	_polishState.customNameText:SetShadowOffset(1, -1)
	_polishState.customNameText:SetShadowColor(0, 0, 0, 0.95)
	_polishState.customNameText:SetText(headerText)
	if NS and NS.ApplyDefaultFont then
		NS:ApplyDefaultFont(_polishState.customNameText, 18)
	end
	_polishState.customNameText:Show()

	-- Level / Spec / Class line (spec + class in class color)
	local level = UnitLevel and UnitLevel("player") or 0
	local className = UnitClass and UnitClass("player") or ""
	local specText = ""
	if GetSpecialization and GetSpecializationInfo then
		local specIndex = GetSpecialization()
		if specIndex then
			local _, specName = GetSpecializationInfo(specIndex)
			if type(specName) == "string" and specName ~= "" then
				specText = specName .. " "
			end
		end
	end
	local specClassPart = specText .. className
	local levelLine = ("Level %d %s%s%s|r"):format(level, nameHex, specClassPart, "")

	if not _polishState.customLevelText then
		_polishState.customLevelText = _polishState.headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	end
	_polishState.customLevelText:ClearAllPoints()
	_polishState.customLevelText:SetPoint("TOP", _polishState.customNameText, "BOTTOM", 0, -2)
	_polishState.customLevelText:SetJustifyH("CENTER")
	_polishState.customLevelText:SetDrawLayer("OVERLAY", 7)
	_polishState.customLevelText:SetShadowOffset(1, -1)
	_polishState.customLevelText:SetShadowColor(0, 0, 0, 0.95)
	_polishState.customLevelText:SetText(levelLine)
	_polishState.customLevelText:SetTextColor(1, 1, 1, 1)
	if NS and NS.ApplyDefaultFont then
		NS:ApplyDefaultFont(_polishState.customLevelText, 13)
	end
	_polishState.customLevelText:Show()

	-- Hide Blizzard title/level text
	local blizTitle = _G.CharacterFrameTitleText
	if blizTitle then
		blizTitle:SetText("")
		blizTitle:SetAlpha(0)
		if blizTitle.Hide then
			blizTitle:Hide()
		end
	end
	local blizLevel = _G.CharacterLevelText
	if blizLevel then
		blizLevel:SetAlpha(0)
		if blizLevel.Hide then
			blizLevel:Hide()
		end
	end
end

function Skin.HideCustomHeader()
	if _polishState.customNameText then
		_polishState.customNameText:Hide()
	end
	if _polishState.customLevelText then
		_polishState.customLevelText:Hide()
	end
	local blizTitle = _G.CharacterFrameTitleText
	if blizTitle then
		blizTitle:SetAlpha(1)
		if blizTitle.Show then
			blizTitle:Show()
		end
	end
	local blizLevel = _G.CharacterLevelText
	if blizLevel then
		blizLevel:SetAlpha(1)
		if blizLevel.Show then
			blizLevel:Show()
		end
	end
end

function Skin.SetCustomHeaderVisible(visible)
	if visible then
		if _polishState.customNameText then
			_polishState.customNameText:Show()
		end
		if _polishState.customLevelText then
			_polishState.customLevelText:Show()
		end
	else
		if _polishState.customNameText then
			_polishState.customNameText:Hide()
		end
		if _polishState.customLevelText then
			_polishState.customLevelText:Hide()
		end
	end
end

function Skin.ApplyCloseButtonGlyph()
	local closeBtn = _G.CharacterFrameCloseButton
	if not closeBtn then
		return
	end

	closeBtn:ClearAllPoints()
	closeBtn:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -10, -10)
	if closeBtn.SetSize then
		closeBtn:SetSize(30, 30)
	end
	if closeBtn.SetFrameStrata then
		closeBtn:SetFrameStrata("DIALOG")
	end
	if closeBtn.SetFrameLevel then
		closeBtn:SetFrameLevel(
			(CharacterFrame and CharacterFrame.GetFrameLevel and CharacterFrame:GetFrameLevel() or 1) + 120
		)
	end

	local function ClearTex(tex)
		if not tex then
			return
		end
		if tex.SetTexture then
			tex:SetTexture(nil)
		end
		if tex.Hide then
			tex:Hide()
		end
		if tex.SetAlpha then
			tex:SetAlpha(0)
		end
	end
	if closeBtn.GetNormalTexture then
		ClearTex(closeBtn:GetNormalTexture())
	end
	if closeBtn.GetPushedTexture then
		ClearTex(closeBtn:GetPushedTexture())
	end
	if closeBtn.GetHighlightTexture then
		ClearTex(closeBtn:GetHighlightTexture())
	end
	if closeBtn.GetDisabledTexture then
		ClearTex(closeBtn:GetDisabledTexture())
	end

	if not _polishState.closeBg then
		_polishState.closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
		_polishState.closeBg:SetAllPoints(true)
	end
	if not _polishState.closeBorder then
		_polishState.closeBorder = closeBtn:CreateTexture(nil, "ARTWORK")
		_polishState.closeBorder:SetAllPoints(true)
	end
	if not _polishState.closeGlow then
		_polishState.closeGlow = closeBtn:CreateTexture(nil, "OVERLAY")
		_polishState.closeGlow:SetAllPoints(true)
		_polishState.closeGlow:SetBlendMode("ADD")
	end

	_polishState.closeBg:SetColorTexture(0.08, 0.08, 0.09, 0.95)
	_polishState.closeBorder:SetTexture("Interface\\AddOns\\HaraUI\\Media\\thin_round_border.tga")
	_polishState.closeBorder:SetVertexColor(0.949, 0.431, 0.031, 0.90)
	_polishState.closeGlow:SetTexture("Interface\\AddOns\\HaraUI\\Media\\thin_round_border.tga")
	_polishState.closeGlow:SetVertexColor(0.949, 0.431, 0.031, 0.40)
	_polishState.closeGlow:Hide()

	if not _polishState.closeGlyph then
		_polishState.closeGlyph = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		_polishState.closeGlyph:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
		_polishState.closeGlyph:SetText("X")
		_polishState.closeGlyph:SetShadowOffset(0, 0)
	end

	if not _polishState.closeHooked then
		closeBtn:HookScript("OnEnter", function(_)
			if _polishState.closeGlow then
				_polishState.closeGlow:Show()
			end
			if _polishState.closeGlyph then
				_polishState.closeGlyph:SetTextColor(1.0, 0.60, 0.16, 1)
			end
		end)
		closeBtn:HookScript("OnLeave", function(_)
			if _polishState.closeGlow then
				_polishState.closeGlow:Hide()
			end
			if _polishState.closeGlyph then
				_polishState.closeGlyph:SetTextColor(0.949, 0.431, 0.031, 1)
			end
		end)
		_polishState.closeHooked = true
	end

	_polishState.closeGlyph:SetTextColor(0.949, 0.431, 0.031, 1)
	_polishState.closeGlyph:SetAlpha(1)
	_polishState.closeGlyph:Show()
end

function Skin.SuppressModelBorders()
	local scene = _G.CharacterModelScene
	if not scene then
		return
	end
	local regions = { scene.GetRegions and scene:GetRegions() }
	for _, region in ipairs(regions) do
		if region and region.GetObjectType and region:GetObjectType() == "Texture" then
			SaveAndHideRegion(region)
		end
	end
	if scene.Background then
		SaveAndHideRegion(scene.Background)
	end
	if scene.BG then
		SaveAndHideRegion(scene.BG)
	end
end
