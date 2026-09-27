--[[
	ui/Components.lua
	Reusable widgets built from the palette spec. Every interactive component
	walks the idle -> hover -> pressed sequence defined in
	idea/colour-palette.md §4.
]]

local Fonts = require("core/Fonts")
local Palette = require("core/Palette")
local Util = require("core/Util")

local Components = {}

local function merge(base, overrides)
	local result = {}
	for key, value in pairs(base) do
		result[key] = value
	end
	if overrides then
		for key, value in pairs(overrides) do
			result[key] = value
		end
	end
	return result
end

-- Containers ------------------------------------------------------------------

-- Styling-only keys that must never be assigned to the Instance itself.
local PANEL_RESERVED = {
	Radius = true,
	Stroke = true,
	StrokeColor = true,
	StrokeTransparency = true,
}

--- Dark console card: card background, metallic border, rounded corners.
--- Every other prop is forwarded straight to the Instance.
function Components.panel(props, children)
	props = props or {}

	local config = {
		Name = "Panel",
		BackgroundColor3 = Palette.surfaces.card,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	}

	for key, value in pairs(props) do
		if not PANEL_RESERVED[key] then
			config[key] = value
		end
	end

	local frame = Util.create("Frame", config, children)

	Util.corner(props.Radius or 8).Parent = frame
	if props.Stroke ~= false then
		Util.stroke(props.StrokeColor or Palette.surfaces.border, 1, props.StrokeTransparency or 0).Parent = frame
	end

	return frame
end

--- Transparent layout container (no background, no stroke).
function Components.row(props, children)
	props = props or {}
	return Util.create("Frame", merge({
		Name = "Row",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 36),
	}, props), children)
end

function Components.divider(props)
	props = props or {}
	return Util.create("Frame", {
		Name = "Divider",
		BackgroundColor3 = Palette.surfaces.border,
		BorderSizePixel = 0,
		BackgroundTransparency = 0.35,
		Size = props.Size or UDim2.new(1, 0, 0, 1),
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	})
end

-- Text ------------------------------------------------------------------------

function Components.label(props)
	props = props or {}
	local config = merge({
		Name = "Label",
		BackgroundTransparency = 1,
		TextColor3 = Palette.text.primary,
		Text = "",
		Size = UDim2.new(1, 0, 0, 20),
	}, props)
	return Fonts.new("TextLabel", props.Role or "body", config)
end

-- Styling-only keys that must never be assigned to the Instance itself.
local BADGE_RESERVED = {
	Color = true,
	Text = true,
}

--[[
	Small uppercase chip used for provider/model metadata.
	Returns a controller table: { frame, label, setText(text), setColor(color) }
]]
function Components.badge(props)
	props = props or {}

	local config = {
		Name = "Badge",
		BackgroundColor3 = Palette.surfaces.card,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 22),
	}

	for key, value in pairs(props) do
		if not BADGE_RESERVED[key] then
			config[key] = value
		end
	end

	local container = Util.create("Frame", config)
	Util.corner(999).Parent = container

	local stroke = Util.stroke(props.Color or Palette.surfaces.border, 1, 0.3)
	stroke.Parent = container
	Util.padding(0, 10, 0, 10).Parent = container

	local label = Fonts.new("TextLabel", "small", {
		Name = "Text",
		BackgroundTransparency = 1,
		Text = props.Text or "",
		TextColor3 = props.Color or Palette.text.secondary,
		TextSize = 11,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = container,
	})

	local badge = {
		frame = container,
		label = label,
	}

	function badge:setText(text)
		label.Text = text
	end

	function badge:setColor(color)
		label.TextColor3 = color
		stroke.Color = color
	end

	return badge
end

-- Buttons ---------------------------------------------------------------------

--[[
	props = {
		Text, Variant ("dark"|"green"|"pink"|"cyan"), Accent (Color3 override),
		Size, Position, AnchorPoint, LayoutOrder, Parent, Radius, Role,
		OnClick, Disabled (bool), Tooltip
	}
]]
-- Behaviour keys that must never be assigned to the Instance itself.
local BUTTON_RESERVED = {
	Variant = true,
	Role = true,
	Radius = true,
	Disabled = true,
	OnClick = true,
}

function Components.button(props)
	props = props or {}

	local variant = props.Variant or "dark"
	local states = Palette.statesFor(variant)
	local textColor = (variant == "dark") and Palette.text.primary or Palette.text.inverse

	local config = {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = props.Disabled and Palette.surfaces.panel or states.idle,
		TextTransparency = props.Disabled and 0.5 or 0,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 120, 0, 34),
		TextColor3 = props.TextColor3 or textColor,
	}

	-- Forward anything else (AutomaticSize, BackgroundTransparency, AnchorPoint,
	-- Position, LayoutOrder, Visible, ZIndex, Parent, ...) straight through.
	for key, value in pairs(props) do
		if not BUTTON_RESERVED[key] then
			config[key] = value
		end
	end

	local button = Util.create("TextButton", config, {
		Util.corner(props.Radius or 8),
		Util.stroke(states.stroke, 1, 0.45),
		Util.padding(6, 12, 6, 12),
	})

	Fonts.apply(button, props.Role or "button", {
		TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
	})

	-- Buttons that were intentionally made transparent keep their transparency.
	local idleTransparency = config.BackgroundTransparency or 0

	local function tweenTo(color, transparency)
		if not button.Parent then
			return
		end
		Util.animate(button, {
			BackgroundColor3 = color,
			BackgroundTransparency = transparency == nil and idleTransparency or transparency,
		}, 0.12)
	end

	button.MouseEnter:Connect(function()
		if props.Disabled then
			return
		end
		tweenTo(states.hover)
	end)

	button.MouseLeave:Connect(function()
		tweenTo(props.Disabled and Palette.surfaces.panel or states.idle)
	end)

	button.MouseButton1Down:Connect(function()
		if props.Disabled then
			return
		end
		tweenTo(states.pressed)
	end)

	button.MouseButton1Up:Connect(function()
		if props.Disabled then
			return
		end
		tweenTo(states.hover)
	end)

	button.MouseButton1Click:Connect(function()
		if props.Disabled then
			return
		end

		if props.OnClick then
			local ok, err = pcall(props.OnClick)
			if not ok then
				warn("[RickMortyAI] button callback failed: " .. tostring(err))
			end
		end
	end)

	return button
end

function Components.accentButton(props)
	props = props or {}
	props.Variant = props.Variant or "green"
	return Components.button(props)
end

-- Inputs ----------------------------------------------------------------------

--[[
	props = { Text, Placeholder, Size, Parent, LayoutOrder, MultiLine, Role,
	          OnSubmit(text, enterPressed), OnChanged(text), ClearTextOnFocus }
]]
function Components.input(props)
	props = props or {}
	local multiLine = props.MultiLine == true

	local box = Util.create("TextBox", {
		Name = props.Name or "Input",
		Text = props.Text or "",
		PlaceholderText = props.Placeholder or "",
		PlaceholderColor3 = Palette.text.dim,
		TextColor3 = Palette.text.primary,
		BackgroundColor3 = Palette.surfaces.background,
		BackgroundTransparency = props.BackgroundTransparency or 0,
		BorderSizePixel = 0,
		ClearTextOnFocus = props.ClearTextOnFocus == true,
		MultiLine = multiLine,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = multiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		Size = props.Size or UDim2.new(1, 0, 0, 36),
		Position = props.Position,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Parent = props.Parent,
	}, {
		Util.corner(props.Radius or 8),
		Util.stroke(Palette.surfaces.border, 1, 0.2),
		Util.padding(multiLine and 10 or 4, 10, multiLine and 10 or 4, 10),
	})

	Fonts.apply(box, props.Role or (multiLine and "code" or "body"), {
		TextWrapped = props.Wrap == true,
	})

	local stroke = box:FindFirstChildOfClass("UIStroke")

	box.Focused:Connect(function()
		if stroke then
			Util.animate(stroke, { Color = Palette.neon.green }, 0.12)
		end
	end)

	box.FocusLost:Connect(function(enterPressed)
		if stroke then
			Util.animate(stroke, { Color = Palette.surfaces.border }, 0.12)
		end
		if props.OnSubmit then
			local ok, err = pcall(props.OnSubmit, box.Text, enterPressed)
			if not ok then
				warn("[RickMortyAI] input submit failed: " .. tostring(err))
			end
		end
	end)

	if props.OnChanged then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			props.OnChanged(box.Text)
		end)
	end

	return box
end

-- Scrolling -------------------------------------------------------------------

function Components.scroll(props)
	props = props or {}

	local frame = Util.create("ScrollingFrame", {
		Name = props.Name or "Scroll",
		BackgroundColor3 = props.BackgroundColor3 or Palette.surfaces.panel,
		BackgroundTransparency = props.BackgroundTransparency == nil and 1 or props.BackgroundTransparency,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = props.ScrollBarColor or Palette.surfaces.border,
		ScrollBarImageTransparency = 0.25,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = true,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Size = props.Size or UDim2.new(1, 0, 1, 0),
		Position = props.Position,
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}, {
		Util.list({
			Padding = UDim.new(0, props.Padding or 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = props.HorizontalAlignment or Enum.HorizontalAlignment.Left,
		}),
		Util.padding(props.Inset or 6),
	})

	if props.Stroke then
		Util.stroke(Palette.surfaces.border, 1, 0.3).Parent = frame
		Util.corner(props.Radius or 8).Parent = frame
	end

	return frame
end

-- Dropdown --------------------------------------------------------------------

--[[
	Provider-selector style dropdown.

	props = {
		Options  = { { id = "OpenAI", label = "OpenAI" }, ... },
		Value    = "OpenAI",
		OnSelect = function(id),
		Size, Parent, LayoutOrder, Placeholder
	}

	Returns a controller table:
		{ frame, toggleButton, list, setValue(id), getValue() }
]]
function Components.dropdown(props)
	props = props or {}

	local options = props.Options or {}
	local value = props.Value

	local function labelFor(id)
		for _, option in ipairs(options) do
			if option.id == id then
				return option.label or option.id
			end
		end
		return props.Placeholder or "Select..."
	end

	local container = Util.create("Frame", {
		Name = props.Name or "Dropdown",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 36),
		Position = props.Position,
		LayoutOrder = props.LayoutOrder,
		ClipsDescendants = false,
		ZIndex = props.ZIndex or 2,
		Parent = props.Parent,
	})

	local toggle
	toggle = Components.button({
		Name = "Toggle",
		Text = "  " .. labelFor(value),
		Variant = "dark",
		Size = UDim2.new(1, 0, 1, 0),
		Radius = 8,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = container,
	})

	local arrow = Fonts.new("TextLabel", "small", {
		Name = "Arrow",
		BackgroundTransparency = 1,
		Text = "v",
		TextColor3 = Palette.text.secondary,
		Size = UDim2.new(0, 16, 1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = toggle,
	})

	local list = Util.create("Frame", {
		Name = "List",
		BackgroundColor3 = Palette.surfaces.card,
		BorderSizePixel = 0,
		Visible = false,
		Size = UDim2.new(1, 0, 0, #options * 30 + 8),
		Position = UDim2.new(0, 0, 1, 4),
		ZIndex = 60,
		Parent = container,
	}, {
		Util.corner(8),
		Util.stroke(Palette.surfaces.border, 1, 0.1),
		Util.padding(4),
		Util.list({ Padding = UDim.new(0, 2) }),
	})

	local rows = {}

	local function close()
		list.Visible = false
		arrow.Text = "v"
	end

	local function open()
		list.Visible = true
		arrow.Text = "^"
	end

	-- `programmatic` suppresses OnSelect so callers can sync the widget from
	-- state without re-entering their own change handler.
	local function select(id, programmatic)
		value = id
		toggle.Text = "  " .. labelFor(id)
		for _, row in ipairs(rows) do
			row.TextColor3 = (row:GetAttribute("optionId") == id) and Palette.neon.green or Palette.text.primary
		end
		close()

		if props.OnSelect and not programmatic then
			props.OnSelect(id)
		end
	end

	for index, option in ipairs(options) do
		local row = Fonts.new("TextButton", "body", {
			Name = "Option" .. tostring(index),
			Text = option.label or option.id,
			TextColor3 = option.id == value and Palette.neon.green or Palette.text.primary,
			BackgroundColor3 = Palette.surfaces.card,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = index,
			ZIndex = 61,
			Parent = list,
		})

		row:SetAttribute("optionId", option.id)

		row.MouseEnter:Connect(function()
			Util.animate(row, { BackgroundTransparency = 0.4, BackgroundColor3 = Palette.surfaces.border }, 0.12)
		end)
		row.MouseLeave:Connect(function()
			Util.animate(row, { BackgroundTransparency = 1 }, 0.12)
		end)
		row.MouseButton1Click:Connect(function()
			select(option.id)
		end)

		table.insert(rows, row)
	end

	toggle.MouseButton1Click:Connect(function()
		if list.Visible then
			close()
		else
			open()
		end
	end)

	local dropdown = {
		frame = container,
		toggleButton = toggle,
		list = list,
	}

	--- Programmatic value sync; does not fire OnSelect.
	function dropdown:setValue(id)
		select(id, true)
	end

	function dropdown:getValue()
		return value
	end

	return dropdown
end

-- Tabs ------------------------------------------------------------------------

--[[
	props = { Items = { { id, label } }, Value, OnSelect, Parent, Size, LayoutOrder }

	Returns a controller table: { frame, buttons, setActive(id), getActive() }
]]
function Components.tabs(props)
	props = props or {}

	local container = Util.create("Frame", {
		Name = props.Name or "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 34),
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}, {
		Util.list({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	local buttons = {}
	local active = props.Value

	local function apply(id)
		for _, entry in ipairs(buttons) do
			local isActive = entry.id == id
			entry.button.BackgroundColor3 = isActive and Palette.states.green.idle or Palette.surfaces.card
			entry.button.TextColor3 = isActive and Palette.text.inverse or Palette.text.secondary
			entry.marker.Visible = isActive
			local stroke = entry.button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = isActive and Palette.neon.green or Palette.surfaces.border
				stroke.Transparency = isActive and 0.1 or 0.45
			end
		end
	end

	for index, item in ipairs(props.Items or {}) do
		local button = Components.button({
			Name = "Tab" .. tostring(index),
			Text = item.label or item.id,
			Variant = "dark",
			Size = UDim2.new(0, 96, 1, 0),
			LayoutOrder = index,
			Parent = container,
			OnClick = function()
				active = item.id
				apply(item.id)
				if props.OnSelect then
					props.OnSelect(item.id)
				end
			end,
		})

		local marker = Util.create("Frame", {
			Name = "Marker",
			BackgroundColor3 = Palette.neon.green,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -16, 0, 2),
			Position = UDim2.new(0, 8, 1, -2),
			Visible = false,
			ZIndex = 4,
			Parent = button,
		})

		table.insert(buttons, { id = item.id, button = button, marker = marker })
	end

	local tabs = {
		frame = container,
		buttons = buttons,
	}

	function tabs:setActive(id)
		active = id
		apply(id)
	end

	function tabs:getActive()
		return active
	end

	apply(active)

	return tabs
end

-- Small helpers ---------------------------------------------------------------

--- Coloured status dot used by the connection indicators.
function Components.dot(props)
	props = props or {}
	return Util.create("Frame", {
		Name = "Dot",
		BackgroundColor3 = props.Color or Palette.neon.green,
		BorderSizePixel = 0,
		Size = UDim2.new(0, props.Size or 8, 0, props.Size or 8),
		Position = props.Position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}, {
		Util.corner(999),
	})
end

-- Layout-only keys that must never be assigned to the Instance itself.
local CONSOLE_RESERVED = {
	Name = true,
	Size = true,
	Position = true,
	LayoutOrder = true,
	Parent = true,
}

--- Multi-line read-only output console for the Code / Cowork panes.
--- Returns a controller table: { frame, scroll, lines, append(text, kind), clear() }
function Components.console(props)
	props = props or {}

	local config = {
		Name = props.Name or "Console",
		BackgroundColor3 = Palette.surfaces.background,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 1, 0),
	}

	-- Forward anything else (AnchorPoint, ZIndex, Visible, ...). Dropping props
	-- here is how the Cowork console used to end up anchored outside its panel.
	for key, value in pairs(props) do
		if not CONSOLE_RESERVED[key] then
			config[key] = value
		end
	end

	local frame = Util.create("Frame", config, {
		Util.corner(8),
		Util.stroke(Palette.surfaces.border, 1, 0.2),
	})

	local scroll = Components.scroll({
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.new(0, 6, 0, 6),
		Padding = 2,
		Inset = 2,
		Parent = frame,
	})

	local console = {
		frame = frame,
		scroll = scroll,
		lines = {},
	}

	local paletteText = {
		ok = Palette.neon.green,
		error = Palette.neon.pink,
		warn = Palette.characters.Morty.text,
		user = Palette.neon.cyan,
		info = Palette.text.secondary,
	}

	--- Appends a line; `kind` picks the colour scheme.
	function console:append(text, kind)
		local color = paletteText[kind or "info"] or Palette.text.primary

		local line = Fonts.new("TextLabel", "log", {
			Name = "Line",
			Text = text,
			TextColor3 = color,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = #console.lines + 1,
			Parent = scroll,
		})

		table.insert(console.lines, line)
		task.defer(function()
			if scroll and scroll.Parent then
				scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y))
			end
		end)

		return line
	end

	function console:clear()
		Util.clear(scroll)
		console.lines = {}
	end

	return console
end

return Components
