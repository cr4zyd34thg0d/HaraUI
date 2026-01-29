local ADDON, NS = ...

-- UI Theme Constants
NS.THEME = {
  -- Mover overlay alpha
  MOVER_ALPHA = 0.06,

  -- Background colors
  BG_DARK = { r = 0.05, g = 0.05, b = 0.06, a = 0.85 },
  BG_MEDIUM = { r = 0.15, g = 0.15, b = 0.15, a = 0.6 },
  BG_LOOT = { r = 0.06, g = 0.06, b = 0.07, a = 0.92 },

  -- Accent/theme color (orange)
  ACCENT = { r = 0.949, g = 0.431, b = 0.031, a = 0.98 },

  -- Text colors with markup
  QUEST_COLOR = "|cffffa11a",
  RESTED_COLOR = "|cff5aa0ff",
  COLOR_END = "|r",
}

-- XP Bar color segments
NS.XPBAR_COLORS = {
  QUEST = { r = 1.0, g = 0.62, b = 0.05, a = 1.0 },
  RESTED = { r = 0.35, g = 0.62, b = 1.0, a = 1.0 },
}

-- Default textures
NS.TEXTURES = {
  STATUSBAR = "Interface/TargetingFrame/UI-StatusBar",
  CAST_SHIELD = "Interface\\CastingBar\\UI-CastingBar-Small-Shield",
}

-- Default font
NS.DEFAULT_FONT = "BigNoodleTilting"
