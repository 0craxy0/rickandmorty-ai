--[[
	core/Fonts.lua
	Typography hierarchy from idea/fonts.md.

	| Role              | Enum.Font              | Size |
	| ----------------- | ---------------------- | ---- |
	| Headers / titles  | LuckiestGuy            | 32   |
	| Subheadings       | GothamBold             | 18   |
	| Buttons           | GothamBold             | 16   |
	| Body / dialogue   | Gotham                 | 14   |
	| Code / terminal   | RobotoMono             | 12   |
]]

local Util = require("core/Util")

local Fonts = {}

Fonts.family = {
	title = Enum.Font.LuckiestGuy,
	button = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
	code = Enum.Font.RobotoMono,
}

-- name -> { Font, TextSize, align, wrapped }
Fonts.roles = {
	title = {
		Font = Enum.Font.LuckiestGuy,
		TextSize = 32,
		align = Enum.TextXAlignment.Center,
		yAlign = Enum.TextYAlignment.Center,
	},
	subtitle = {
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		align = Enum.TextXAlignment.Left,
	},
	button = {
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		align = Enum.TextXAlignment.Center,
		yAlign = Enum.TextYAlignment.Center,
	},
	body = {
		Font = Enum.Font.Gotham,
		TextSize = 14,
		align = Enum.TextXAlignment.Left,
		wrapped = true,
	},
	small = {
		Font = Enum.Font.Gotham,
		TextSize = 12,
		align = Enum.TextXAlignment.Left,
		wrapped = true,
	},
	code = {
		Font = Enum.Font.RobotoMono,
		TextSize = 12,
		align = Enum.TextXAlignment.Left,
		wrapped = false,
	},
	log = {
		Font = Enum.Font.RobotoMono,
		TextSize = 11,
		align = Enum.TextXAlignment.Left,
		wrapped = true,
	},
}

--- Applies a role (plus optional overrides) to any text-bearing instance.
function Fonts.apply(instance, role, overrides)
	local spec = Fonts.roles[role or "body"] or Fonts.roles.body

	instance.Font = spec.Font
	instance.TextSize = spec.TextSize
	instance.TextXAlignment = spec.align or Enum.TextXAlignment.Left
	instance.TextYAlignment = spec.yAlign or Enum.TextYAlignment.Top
	instance.TextWrapped = spec.wrapped or false

	if overrides then
		for key, value in pairs(overrides) do
			instance[key] = value
		end
	end

	return instance
end

--- TextLabel/TextButton/TextBox factory with typography applied.
--- Explicit props win over the role defaults; Parent is applied last.
function Fonts.new(className, role, props)
	local config = {}
	local parent

	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				config[key] = value
			end
		end
	end

	local instance = Util.create(className or "TextLabel", config)
	Fonts.apply(instance, role)

	for key, value in pairs(config) do
		instance[key] = value
	end

	if parent then
		instance.Parent = parent
	end

	return instance
end

--- Auto-sizing label used by the chat transcript and log panes.
function Fonts.autoSized(role, overrides)
	local config = {}

	if overrides then
		for key, value in pairs(overrides) do
			config[key] = value
		end
	end

	config.AutomaticSize = config.AutomaticSize or Enum.AutomaticSize.Y
	config.TextWrapped = true
	config.Size = config.Size or UDim2.new(1, 0, 0, 0)
	if config.BackgroundTransparency == nil then
		config.BackgroundTransparency = 1
	end

	return Fonts.new("TextLabel", role or "body", config)
end

return Fonts
