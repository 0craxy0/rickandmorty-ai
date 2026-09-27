--[[
	ui/Companion.lua
	The "little buddy" overlay from idea/png-usage.md §2.

	  * 64x64 frame, ScaleType = Fit
	  * ZIndex 5 so it floats above message bubbles without clipping text
	  * hover applies a neon scaling bump to 70x70 through TweenService
	  * the tutorial reuses this at 128x128 as the guide anchor
]]

local Assets = require("core/Assets")
local Palette = require("core/Palette")
local State = require("core/State")
local Util = require("core/Util")

local Companion = {}

Companion.SIZE = 64
Companion.HOVER_SIZE = 70
Companion.GUIDE_SIZE = 128

--[[
	Creates the portrait overlay.

	props = { Name = "Rick"|"Morty", Size, Position, AnchorPoint, Parent,
	          Hover = boolean, ZIndex, ShowPlate = boolean }
]]
function Companion.create(parent, props)
	props = props or {}

	local companionName = props.Name or State.companion()
	local size = props.Size or Companion.SIZE
	local theme = Palette.character(companionName)

	local frame = Util.create("Frame", {
		Name = "Companion",
		BackgroundColor3 = Palette.surfaces.card,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.new(0, size, 0, size),
		Position = props.Position or UDim2.new(1, -16, 1, -16),
		AnchorPoint = props.AnchorPoint or Vector2.new(1, 1),
		ZIndex = props.ZIndex or 5,
		LayoutOrder = props.LayoutOrder,
		Parent = parent,
	})

	Util.corner(math.max(6, size * 0.12)).Parent = frame

	local stroke = Util.stroke(theme.glow, 1, 0.25)
	stroke.Parent = frame

	local portrait = Assets.imageLabel(string.lower(companionName), {
		Name = "Portrait",
		Image = Assets.portrait(companionName),
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.new(0, 3, 0, 3),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = (props.ZIndex or 5) + 1,
		Parent = frame,
	})

	local plate
	if props.ShowPlate then
		plate = Util.create("TextLabel", {
			Name = "Plate",
			BackgroundColor3 = Palette.surfaces.background,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Text = string.upper(companionName),
			TextColor3 = theme.text,
			TextSize = 10,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(1, 8, 0, 14),
			Position = UDim2.new(0.5, 0, 1, 3),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = (props.ZIndex or 5) + 2,
			Parent = frame,
		})
		Util.corner(4).Parent = plate
	end

	-- Hover: neon scaling bump (idea/png-usage.md §2).
	local hoverEnabled = props.Hover ~= false
	if hoverEnabled then
		local baseSize = size
		local hoverSize = math.max(size + 6, math.floor(baseSize * (Companion.HOVER_SIZE / Companion.SIZE)))

		frame.MouseEnter:Connect(function()
			Util.animate(frame, {
				Size = UDim2.new(0, hoverSize, 0, hoverSize),
				BackgroundTransparency = 0.15,
			}, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

			Util.animate(stroke, { Transparency = 0 }, 0.18)
		end)

		frame.MouseLeave:Connect(function()
			Util.animate(frame, {
				Size = UDim2.new(0, baseSize, 0, baseSize),
				BackgroundTransparency = 0.35,
			}, 0.18)

			Util.animate(stroke, { Transparency = 0.25 }, 0.18)
		end)
	end

	frame.Portrait = portrait
	frame.Stroke = stroke
	frame.Plate = plate

	--- Morphs this overlay onto another companion profile.
	function frame:SetCharacter(companionName2)
		local nextTheme = Palette.character(companionName2)
		portrait.Image = Assets.portrait(companionName2)
		stroke.Color = nextTheme.glow
		if plate then
			plate.Text = string.upper(nextTheme.name)
			plate.TextColor3 = nextTheme.text
		end
	end

	return frame
end

--- Bigger framed portrait used by the onboarding guide.
function Companion.guide(parent, companionName, props)
	props = props or {}
	props.Name = companionName
	props.Size = props.Size or Companion.GUIDE_SIZE
	props.Hover = false
	props.ShowPlate = true
	props.ZIndex = props.ZIndex or 6

	local frame = Companion.create(parent, props)

	-- A soft glow ring keeps the guide visually anchored to the dialogue box.
	local glow = Util.create("Frame", {
		Name = "Glow",
		BackgroundColor3 = Palette.character(companionName).glow,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 12, 1, 12),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = (props.ZIndex or 6) - 1,
		Parent = frame,
	})
	Util.corner(999).Parent = glow

	return frame
end

return Companion
