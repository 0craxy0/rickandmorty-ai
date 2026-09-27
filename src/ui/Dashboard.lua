--[[
	ui/Dashboard.lua
	The full-sized main menu from idea/main.md §1 and idea/ui-creation.md §1.

	  * no screen dimming - the console floats over the live viewport
	  * header: title.png anchored top-center with a locked aspect ratio
	  * left: persistent navigation sidebar (provider, companion, history)
	  * center: Chat / Cowork / Code workspace
	  * lower-right: the active companion frame
	  * plus a floating anchor button that reopens the window once it is hidden
]]

local Assets = require("core/Assets")
local ChatPanel = require("ui/ChatPanel")
local CodePanel = require("ui/CodePanel")
local Companion = require("ui/Companion")
local Components = require("ui/Components")
local CoworkPanel = require("ui/CoworkPanel")
local Fonts = require("core/Fonts")
local Palette = require("core/Palette")
local Sidebar = require("ui/Sidebar")
local State = require("core/State")
local Util = require("core/Util")

local Dashboard = {}

Dashboard.HEADER_HEIGHT = 76
Dashboard.TABS = {
	{ id = "Chat", label = "Chat" },
	{ id = "Cowork", label = "Cowork" },
	{ id = "Code", label = "Code" },
}

function Dashboard.new(gui, app)
	-- Root (no dimming layer) --------------------------------------------------

	local root = Util.create("Frame", {
		Name = "DashboardRoot",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 100,
		Parent = gui,
	})

	local window = Util.create("Frame", {
		Name = "Window",
		BackgroundColor3 = Palette.surfaces.background,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -60, 1, -120),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ClipsDescendants = true,
		Parent = root,
	}, {
		Util.corner(12),
		Util.stroke(Palette.surfaces.border, 1, 0),
		Util.create("UISizeConstraint", {
			MinSize = Vector2.new(900, 560),
			MaxSize = Vector2.new(1180, 700),
		}),
	})

	-- Header ------------------------------------------------------------------

	local header = Util.create("Frame", {
		Name = "Header",
		BackgroundColor3 = Palette.surfaces.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, Dashboard.HEADER_HEIGHT),
		Parent = window,
	})

	Util.create("Frame", {
		Name = "Seam",
		BackgroundColor3 = Palette.surfaces.border,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		Parent = header,
	})

	local companionBadge = Components.badge({
		Name = "CompanionBadge",
		Text = string.upper(State.companion()),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = header,
	})

	local providerBadge = Components.badge({
		Name = "ProviderBadge",
		Text = State.provider(),
		Color = Palette.neon.cyan,
		Position = UDim2.new(0, 16, 0.5, 26),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = header,
	})

	-- title.png anchored top-center, aspect locked to the trimmed logo ratio.
	local title = Assets.imageLabel("title", {
		Name = "Title",
		Size = UDim2.new(0, 300, 1, -16),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = header,
	})
	Assets.aspect(title, Assets.TITLE_ASPECT, Enum.DominantAxis.Height)

	local headerActions = Util.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 260, 1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = header,
	}, {
		Util.list({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})

	-- Body --------------------------------------------------------------------

	local body = Util.create("Frame", {
		Name = "Body",
		BackgroundColor3 = Palette.surfaces.background,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -Dashboard.HEADER_HEIGHT),
		Position = UDim2.new(0, 0, 0, Dashboard.HEADER_HEIGHT),
		Parent = window,
	})

	local sidebar = Sidebar.new(body, app)
	app.sidebar = sidebar

	local main = Util.create("Frame", {
		Name = "Main",
		BackgroundColor3 = Palette.surfaces.background,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -Sidebar.WIDTH, 1, 0),
		Position = UDim2.new(0, Sidebar.WIDTH, 0, 0),
		ZIndex = 2,
		Parent = body,
	})

	local tabs = Components.tabs({
		Name = "WorkspaceTabs",
		Items = Dashboard.TABS,
		Value = "Chat",
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.new(0, 12, 0, 12),
		Parent = main,
		OnSelect = function(id)
			dashboard:setTab(id)
		end,
	})

	local content = Util.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -58),
		Position = UDim2.new(0, 0, 0, 58),
		Parent = main,
	})

	local panels = {
		Chat = ChatPanel.new(content, app),
		Cowork = CoworkPanel.new(content, app),
		Code = CodePanel.new(content, app),
	}

	for _, panel in pairs(panels) do
		panel.frame.Visible = false
	end

	-- Companion ---------------------------------------------------------------

	local companion = Companion.create(window, {
		Name = State.companion(),
		Position = UDim2.new(1, -18, 1, -18),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 5,
		Parent = window,
	})

	-- Anchor shortcut button (bottom-left) ------------------------------------

	local anchor = Util.create("Frame", {
		Name = "AnchorButton",
		BackgroundColor3 = Palette.surfaces.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 132, 0, 42),
		Position = UDim2.new(0, 18, 1, -18),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 120,
		Parent = gui,
	}, {
		Util.corner(10),
		Util.stroke(Palette.surfaces.border, 1, 0.2),
		Util.padding(6),
	})

	local anchorPortrait = Assets.imageLabel(string.lower(State.companion()), {
		Name = "Portrait",
		Image = Assets.portrait(State.companion()),
		Size = UDim2.new(0, 30, 1, 0),
		Parent = anchor,
	})

	Fonts.new("TextLabel", "small", {
		Name = "Label",
		Text = "AI CONSOLE",
		TextColor3 = Palette.text.primary,
		TextSize = 10,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -36, 1, 0),
		Position = UDim2.new(0, 36, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = anchor,
	})

	local anchorButton = Components.button({
		Name = "Hit",
		Text = "",
		Variant = "dark",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 121,
		Parent = anchor,
		OnClick = function()
			root.Visible = true
			anchor.Visible = false
		end,
	})

	local anchorStroke = anchorButton:FindFirstChildOfClass("UIStroke")
	if anchorStroke then
		anchorStroke.Transparency = 1
	end

	-- Dragging ----------------------------------------------------------------

	local dragging = false
	local dragStart
	local startPosition

	--- True when a screen-space point sits inside a GuiObject.
	local function insideGui(instance, position)
		local topLeft = instance.AbsolutePosition
		local size = instance.AbsoluteSize

		return position.X >= topLeft.X
			and position.X <= topLeft.X + size.X
			and position.Y >= topLeft.Y
			and position.Y <= topLeft.Y + size.Y
	end

	header.InputBegan:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Let header buttons take their own clicks.
			if headerActions.Visible and insideGui(headerActions, inputObject.Position) then
				return
			end

			dragging = true
			dragStart = inputObject.Position
			startPosition = window.Position

			inputObject.Changed:Connect(function()
				if inputObject.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	header.InputChanged:Connect(function(inputObject)
		if not dragging or inputObject.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local delta = inputObject.Position - dragStart
		window.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end)

	-- Header buttons ----------------------------------------------------------

	Components.button({
		Name = "QuickMenuButton",
		Text = "quick menu  ;",
		Variant = "dark",
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = headerActions,
		OnClick = function()
			if app.ToggleQuickMenu then
				app.ToggleQuickMenu()
			end
		end,
	})

	Components.button({
		Name = "NewChatButton",
		Text = "New chat",
		Variant = "dark",
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = headerActions,
		OnClick = function()
			State.resetHistory()
			panels.Chat:clear()
			sidebar:refreshSessions()
			dashboard:setTab("Chat")
		end,
	})

	Components.button({
		Name = "HideButton",
		Text = "Hide",
		Variant = "dark",
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Parent = headerActions,
		OnClick = function()
			dashboard:setVisible(false)
		end,
	})

	Components.button({
		Name = "UnloadButton",
		Text = "Unload",
		Variant = "pink",
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 4,
		Parent = headerActions,
		OnClick = function()
			if app.Unload then
				app.Unload()
			end
		end,
	})

	-- API ---------------------------------------------------------------------

	local dashboard = {
		root = root,
		window = window,
		header = header,
		body = body,
		main = main,
		tabs = tabs,
		panels = panels,
		companion = companion,
		anchor = anchor,
	}

	function dashboard:setVisible(visible)
		root.Visible = visible == true
		anchor.Visible = not root.Visible
	end

	function dashboard:isVisible()
		return root.Visible
	end

	function dashboard:toggle()
		dashboard:setVisible(not root.Visible)
	end

	function dashboard:setTab(id)
		local resolved = panels[id] and id or "Chat"

		for panelId, panel in pairs(panels) do
			panel.frame.Visible = panelId == resolved
		end

		tabs:SetActive(resolved)
		self.activeTab = resolved

		local panel = panels[resolved]
		if panel.render and resolved == "Chat" then
			panel:render()
		end
		if panel.refresh then
			panel:refresh()
		end
	end

	--- Appends a line to the Code pane's console (shared log target).
	function dashboard:log(text, kind)
		panels.Code:log(text, kind)
	end

	function dashboard:loadCode(source)
		panels.Code:setSource(source)
	end

	function dashboard:refresh()
		companionBadge.TextLabel.Text = string.upper(State.companion())
		providerBadge.TextLabel.Text = State.provider()
		companion:SetCharacter(State.companion())
		anchorPortrait.Image = Assets.portrait(State.companion())
		sidebar:refresh()
		panels.Chat:refresh()
	end

	function dashboard:destroy()
		anchor:Destroy()
		root:Destroy()
	end

	dashboard:setTab("Chat")
	dashboard:setVisible(false)

	return dashboard
end

return Dashboard
