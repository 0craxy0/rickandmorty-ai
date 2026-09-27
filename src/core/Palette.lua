--[[
	core/Palette.lua
	Every colour constant from idea/colour-palette.md.

	Three layers, matching the spec:
	  1. surfaces  — Citadel space station panels (#0D1117 / #161B22 / #21262D / #30363D)
	  2. neon      — Portal Green / Dimension Pink / Plasma Link Cyan
	  3. characters — Rick and Morty theme overlays
	Plus the two interactive state sequences (portal green, dark console).
]]

local Util = require("core/Util")

local Palette = {}

Palette.hex = Util.hex

-- 1. Primary structural theme -------------------------------------------------

Palette.surfaces = {
	background = Util.hex("#0D1117"), -- main window background
	panel = Util.hex("#161B22"), -- secondary panels / sidebar
	card = Util.hex("#21262D"), -- inner card panels / frames
	border = Util.hex("#30363D"), -- borders & dividers
	black = Color3.fromRGB(0, 0, 0),
}

-- 2. Neon energy accents ------------------------------------------------------

Palette.neon = {
	green = Util.hex("#00FF88"), -- portal green (active state)
	pink = Util.hex("#FF007F"), -- dimension battery pink (warning)
	cyan = Util.hex("#00E1FF"), -- portal blue (system link)
}

-- 3. Text ---------------------------------------------------------------------

Palette.text = {
	primary = Util.hex("#E6EDF3"),
	secondary = Util.hex("#8B949E"),
	dim = Util.hex("#6E7681"),
	inverse = Util.hex("#0D1117"),
}

-- Overlay used by the semicolon quick menu (semi-transparent black).
Palette.overlay = {
	color = Util.hex("#0D1117"),
	transparency = 0.4,
}

-- Character theme profiles ----------------------------------------------------

Palette.characters = {
	Rick = {
		name = "Rick",
		label = "Rick Sanchez",
		tagline = "Dimension C-137 // Genius Sci-Fi",
		accent = Util.hex("#A2E8DD"), -- lab coat / hair blue-gray
		text = Util.hex("#00FF88"), -- portal fluid green
		glow = Util.hex("#00BCFF"), -- battery cell blue
		portrait = "rick",
	},
	Morty = {
		name = "Morty",
		label = "Morty Smith",
		tagline = "Dimension C-137 // Anxious Sidekick",
		accent = Util.hex("#FFE600"), -- t-shirt yellow
		text = Util.hex("#FFAA00"), -- alert amber
		glow = Util.hex("#FF5500"), -- panic orange
		portrait = "morty",
	},
}

Palette.characterOrder = { "Rick", "Morty" }

-- 4. Interactive state variations ---------------------------------------------

Palette.states = {
	green = {
		idle = Util.hex("#00BD65"),
		hover = Util.hex("#00FF88"),
		pressed = Util.hex("#008044"),
		stroke = Util.hex("#00BD65"),
	},
	dark = {
		idle = Util.hex("#21262D"),
		hover = Util.hex("#30363D"),
		pressed = Util.hex("#161B22"),
		stroke = Util.hex("#30363D"),
	},
	pink = {
		idle = Util.hex("#C40062"),
		hover = Util.hex("#FF007F"),
		pressed = Util.hex("#8A0045"),
		stroke = Util.hex("#FF007F"),
	},
	cyan = {
		idle = Util.hex("#00A8BF"),
		hover = Util.hex("#00E1FF"),
		pressed = Util.hex("#00768A"),
		stroke = Util.hex("#00E1FF"),
	},
}

--- Theme profile for a companion name ("Rick" or "Morty").
function Palette.character(name)
	return Palette.characters[name] or Palette.characters.Rick
end

--- State triplet for a button variant ("dark", "green", "pink", "cyan").
function Palette.statesFor(variant)
	return Palette.states[variant or "dark"] or Palette.states.dark
end

return Palette
