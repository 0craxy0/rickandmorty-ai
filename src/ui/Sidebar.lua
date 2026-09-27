--[[
	ui/Sidebar.lua
	Persistent navigation rail from idea/ui-creation.md §1:
	  * provider selector (dropdown, preset templates)
	  * companion switch (Rick / Morty)
	  * settings: API key, model override, transport status
	  * chat history (archived sessions)
	  * footer: stats + unload
]]

local Components = require("ui/Components")
local Fonts = require("core/Fonts")
local Http = require("core/Http")
local Palette = require("core/Palette")
local Providers = require("core/Providers")
local State = require("core/State")
local Util = require("core/Util")

local Sidebar = {}

Sidebar.WIDTH = 252

-- The rail narrows on small viewports. At 800x600 a 252px rail leaves the
-- workspace ~440px, which is less than one toolbar row (buttons + status) needs.
Sidebar.COMPACT_WIDTH = 200
Sidebar.COMPACT_BELOW = 1100

--- Rail width for a viewport, so the workspace can be sized around the same
--- number instead of hard-coding Sidebar.WIDTH.
function Sidebar.widthFor(viewportWidth)
	if type(viewportWidth) == "number" and viewportWidth > 0 and viewportWidth < Sidebar.COMPACT_BELOW then
		return Sidebar.COMPACT_WIDTH
	end

	return Sidebar.WIDTH
end

local function heading(parent, text, order)
	local label = Fonts.new("TextLabel", "small", {
		Name = "Heading",
		Text = string.upper(text),
		TextColor3 = Palette.text.dim,
		TextSize = 10,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	})

	label.TextSize = 10
	return label
end

function Sidebar.new(parent, app)
	local frame = Util.create("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = Palette.surfaces.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(0, Sidebar.WIDTH, 1, 0),
		ZIndex = 3,
		Parent = parent,
	})

	Util.create("Frame", {
		Name = "Edge",
		BackgroundColor3 = Palette.surfaces.border,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(1, -1, 0, 0),
		Parent = frame,
	})

	local function fitWidth()
		local gui = app and app.gui
		local viewport = gui and gui.AbsoluteSize

		if not viewport or viewport.X <= 0 then
			return
		end

		frame.Size = UDim2.new(0, Sidebar.widthFor(viewport.X), 1, 0)
	end

	fitWidth()
	if app and app.gui then
		app.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWidth)
	end

	-- Scrolls rather than overflows: the settings rail is taller than the sidebar
	-- once the window is shorter than its 700px maximum (at a 768px-tall viewport
	-- the last rows ran a couple of pixels past the rail).
	local stack = Util.create("ScrollingFrame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 1, -24),
		Position = UDim2.new(0, 12, 0, 12),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = true,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Palette.surfaces.border,
		ScrollBarImageTransparency = 0.3,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Parent = frame,
	}, {
		Util.list({ Padding = UDim.new(0, 8) }),
	})

	-- Provider -----------------------------------------------------------------

	heading(stack, "AI provider", 1)

	local providerDropdown = Components.dropdown({
		Name = "ProviderDropdown",
		Options = (function()
			local options = {}
			for _, id in ipairs(Providers.ids()) do
				table.insert(options, { id = id, label = id })
			end
			return options
		end)(),
		Value = State.provider(),
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 2,
		Parent = stack,
		OnSelect = function(id)
			State.setProvider(id)
			Sidebar.refresh(app)
		end,
	})

	local providerHint = Fonts.new("TextLabel", "small", {
		Name = "ProviderHint",
		Text = Providers.get(State.provider()).description,
		TextColor3 = Palette.text.secondary,
		TextSize = 11,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextWrapped = true,
		LayoutOrder = 3,
		Parent = stack,
	})

	-- Companion ----------------------------------------------------------------

	heading(stack, "Companion", 4)

	local companionRow = Util.create("Frame", {
		Name = "CompanionRow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 5,
		Parent = stack,
	}, {
		Util.list({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	local companionButtons = {}

	for index, name in ipairs(Palette.characterOrder) do
		local theme = Palette.character(name)

		local button = Components.button({
			Name = name .. "Button",
			Text = name,
			Variant = "dark",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = index,
			Parent = companionRow,
			TextColor3 = theme.text,
			OnClick = function()
				State.setCompanion(name)
				if app and app.OnCompanionChanged then
					app.OnCompanionChanged(name)
				end
				Sidebar.refresh(app)
			end,
		})

		companionButtons[name] = button
	end

	-- Settings -----------------------------------------------------------------

	heading(stack, "Settings", 6)

	local keyInput = Components.input({
		Name = "KeyInput",
		Text = State.apiKey(State.provider()),
		Placeholder = Providers.get(State.provider()).keyLabel,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 7,
		Parent = stack,
		OnSubmit = function(text)
			State.setApiKey(Util.trim(text))
			Sidebar.refresh(app)
		end,
	})

	local modelInput = Components.input({
		Name = "ModelInput",
		Text = State.model(Providers.get(State.provider()).model),
		Placeholder = "model id",
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 8,
		Parent = stack,
		OnSubmit = function(text)
			State.setModel(Util.trim(text))
		end,
	})

	local saveButton = Components.button({
		Name = "SaveSettings",
		Text = "Save credentials",
		Variant = "green",
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 9,
		Parent = stack,
		OnClick = function()
			State.setApiKey(Util.trim(keyInput.Text))
			State.setModel(Util.trim(modelInput.Text))
			State.save()
			if app and app.notify then
				app.notify("Credentials saved", State.provider() .. " // " .. State.model("default"))
			end
		end,
	})

	local transport = Fonts.new("TextLabel", "small", {
		Name = "Transport",
		Text = "transport: " .. Http.transportName(),
		TextColor3 = Http.available() and Palette.text.dim or Palette.neon.pink,
		TextSize = 10,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextWrapped = true,
		LayoutOrder = 10,
		Parent = stack,
	})

	-- History ------------------------------------------------------------------

	heading(stack, "Chat history", 11)

	local sessions = Components.scroll({
		Name = "Sessions",
		Size = UDim2.new(1, 0, 0, 150),
		LayoutOrder = 12,
		Padding = 4,
		Inset = 0,
		Parent = stack,
	})

	-- Footer -------------------------------------------------------------------

	-- Vertical stack: full-width children only, so nothing can overflow the rail.
	local footer = Util.create("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 46),
		LayoutOrder = 13,
		Parent = stack,
	}, {
		Util.list({ Padding = UDim.new(0, 4) }),
	})

	Fonts.new("TextLabel", "small", {
		Name = "Version",
		Text = "v" .. tostring(app and app.version or "1.0.0") .. "  //  " .. State.companion(),
		TextColor3 = Palette.text.dim,
		TextSize = 10,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		LayoutOrder = 1,
		Parent = footer,
	})

	Components.button({
		Name = "QuickMenuHint",
		Text = "quick menu: ;",
		Variant = "dark",
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 2,
		Parent = footer,
		OnClick = function()
			if app and app.ToggleQuickMenu then
				app.ToggleQuickMenu()
			end
		end,
	})

	-- API ----------------------------------------------------------------------

	local sidebar = {
		frame = frame,
		providerDropdown = providerDropdown,
		keyInput = keyInput,
		modelInput = modelInput,
		sessions = sessions,
	}

	function sidebar:refreshSessions()
		Util.clear(sessions)

		local entries = State.data.sessions or {}

		local current = Components.button({
			Name = "Current",
			Text = "[current] " .. tostring(#State.history) .. " messages",
			Variant = "dark",
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 0,
			Parent = sessions,
			TextXAlignment = Enum.TextXAlignment.Left,
			OnClick = function()
				if app and app.dashboard then
					app.dashboard:setTab("Chat")
				end
			end,
		})
		current.TextColor3 = Palette.neon.green

		if #entries == 0 then
			Fonts.new("TextLabel", "small", {
				Name = "Empty",
				Text = "No archived conversations yet.",
				TextColor3 = Palette.text.dim,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				TextWrapped = true,
				LayoutOrder = 1,
				Parent = sessions,
			})
			return
		end

		for index, session in ipairs(entries) do
			local row = Components.button({
				Name = "Session" .. tostring(index),
				Text = session.title or "Untitled",
				Variant = "dark",
				Size = UDim2.new(1, 0, 0, 28),
				LayoutOrder = index,
				Parent = sessions,
				TextXAlignment = Enum.TextXAlignment.Left,
				OnClick = function()
					State.setHistory(session.messages or {})
					if app and app.OnHistoryRestored then
						app.OnHistoryRestored()
					end
					sidebar:refreshSessions()
				end,
			})
			row.TextColor3 = Palette.text.secondary
		end
	end

	function sidebar:refresh()
		sidebar.providerDropdown:setValue(State.provider())
		providerHint.Text = Providers.get(State.provider()).description
		keyInput.Text = State.apiKey(State.provider())
		keyInput.PlaceholderText = Providers.get(State.provider()).keyLabel
		modelInput.Text = State.model(Providers.get(State.provider()).model)
		transport.Text = "transport: " .. Http.transportName()
		transport.TextColor3 = Http.available() and Palette.text.dim or Palette.neon.pink

		for name, button in pairs(companionButtons) do
			local active = name == State.companion()
			button.BackgroundColor3 = active and Palette.surfaces.border or Palette.surfaces.card
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = active and Palette.character(name).glow or Palette.surfaces.border
			end
		end

		sidebar:refreshSessions()
	end

	sidebar:refresh()

	return sidebar
end

--- Re-applies state-driven visuals (used when the dashboard opens).
function Sidebar.refresh(app)
	if app and app.sidebar and app.sidebar.refresh then
		app.sidebar:refresh()
	end
end

return Sidebar
