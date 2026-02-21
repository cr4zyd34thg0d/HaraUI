local ADDON, NS = ...
local CS = NS.CharacterSheet
if not CS then return end

CS.Data = CS.Data or {}
local Data = CS.Data

local function ResolveWeeklyRewardType(name, fallback)
  local enumTable = Enum and Enum.WeeklyRewardChestThresholdType
  local value = enumTable and enumTable[name]
  if type(value) == "number" then
    return value
  end
  return fallback
end

Data.VAULT_THRESHOLDS = {
  raid = { 1, 4, 6 },
  dungeon = { 2, 4, 8 },
  world = { 2, 4, 8 },
  pvp = { 2, 4, 8 },
}

Data.WEEKLY_REWARD_TYPE = {
  Raid = ResolveWeeklyRewardType("Raid", 1),
  Activities = ResolveWeeklyRewardType("Activities", 2),
  World = ResolveWeeklyRewardType("World", 3),
  RankedPvP = ResolveWeeklyRewardType("RankedPvP", 4),
}
