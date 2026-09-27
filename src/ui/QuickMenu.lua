--[[
	ui/QuickMenu.lua
	The semicolon quick-menu from idea/main.md §1 and idea/backend.md §4.

	  * pressing ';' spawns a full-screen overlay over the game canvas
	    (BackgroundColor3 #0D1117, BackgroundTransparency 0.4)
	  * movement keys are sunk while it is open so the character does not walk
	  * submitting a prompt sends it straight to the active provider, extracts the
	    ```lua block, executes it into the live workspace, then closes
	  * Escape or a click on the dim backdrop closes it
]]

local Assets = require("core/Assets")
local Chat = require("core/Chat")
local Companion = require("ui/Companion")
local Components = require("ui/Components")
local Fonts = require("core/Fonts")
local Palette = require("core/Palette")
local State = require("core/State")
local Util = require("core/Util")

local QuickMenu = {}

QuickMenu.WIDTH = 640
QuickMenu.HEIGHT = 340

local SINK_ACTION = "RickMortyAI_QuickMenuSink"
local SINK_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Q,
	Enum.KeyCode.E,
	Enum.KeyCode.Space,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.LeftControl,
}

function QuickMenu.new(gui, app)
	local UserInputService = game:GetService("UserInputService")
	local ContextActionService = game:GetService("ContextActionService")

	local self = {
		isOpen = false,
		busy = false,
	}

	local connections = Util.connections()

	-- Backdrop -----------------------------------------------------------------

	local overlay = Util.create("Frame", {
		Name = "QuickMenu",
		BackgroundColor3 = Palette.overlay.color,
		BackgroundTransparency = Palette.overlay.transparency,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 250,
		Parent = gui,
	})

	-- Centered module ----------------------------------------------------------

	local module = Components.panel({
		Name = "Module",
		BackgroundColor3 = Palette.surfaces.background,
		Size = UDim2.new(0, QuickMenu.WIDTH, 0, QuickMenu.HEIGHT),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 251,
		Parent = overlay,
	}, {
		Util.padding(18),
	})

	-- title.png at 50% of the module width, aspect locked to the logo's trim.
	local title = Assets.imageLabel("title", {
		Name = "Title",
		Size = UDim2.new(0.5, 0, 0, 84),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 252,
		Parent = module,
	})
	Assets.aspect(title, Assets.TITLE_ASPECT, Enum.DominantAxis.Height)

	local input = Components.input({
		Name = "Prompt",
		Placeholder = "portal gun, but for luau...",
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.new(0, 0, 0, 104),
		ZIndex = 253,
		Parent = module,
		OnSubmit = function(text, enterPressed)
			if enterPressed then
				self:submit(text)
			end
		end,
	})

	local status = Fonts.new("TextLabel", "small", {
		Name = "Status",
		Text = "type a prompt, hit enter, the script runs itself",
		TextColor3 = Palette.text.secondary,
		TextSize = 11,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 158),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 253,
		Parent = module,
	})

	local companionHolder = Util.create("Frame", {
		Name = "CompanionHolder",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 64, 0, 64),
		Position = UDim2.new(0, 0, 0, 190),
		ZIndex = 253,
		Parent = module,
	})

	local providerBadge = Components.badge({
		Name = "ProviderBadge",
		Text = State.provider(),
		Color = Palette.neon.cyan,
		Position = UDim2.new(1, 0, 0, 196),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 253,
		Parent = module,
	})

	Fonts.new("TextLabel", "small", {
		Name = "Hint",
		Text = "esc closes  |  output executes into workspace and is mirrored in the Code tab",
		TextColor3 = Palette.text.dim,
		TextSize = 10,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 253,
		Parent = module,
	})

	-- Companion portrait ------------------------------------------------------

	local portrait

	local function mountPortrait()
		if portrait then
			portrait:destroy()
		end

		portrait = Companion.create(companionHolder, {
			Name = State.companion(),
			Size = 64,
			Position = UDim2.new(0, 0, 0, 0),
			AnchorPoint = Vector2.new(0, 0),
			ZIndex = 254,
			Parent = companionHolder,
		})
	end

	-- Behaviour ---------------------------------------------------------------

	local function sinkMovement(enabled)
		if enabled then
			ContextActionService:BindAction(SINK_ACTION, function()
				return Enum.ContextActionResult.Sink
			end, false, table.unpack(SINK_KEYS))
		else
			pcall(function()
				ContextActionService:UnbindAction(SINK_ACTION)
			end)
		end
	end

	function self:open()
		if self.isOpen then
			return
		end

		self.isOpen = true
		mountPortrait()
		providerBadge:setText(State.provider())
		overlay.Visible = true
		sinkMovement(true)

		task.defer(function()
			input:CaptureFocus()
		end)
	end

	function self:close()
		if not self.isOpen then
			return
		end

		self.isOpen = false
		overlay.Visible = false
		pcall(function()
			input:ReleaseFocus()
		end)
		sinkMovement(false)
	end

	function self:toggle()
		if self.isOpen then
			self:close()
		else
			self:open()
		end
	end

	function self:setStatus(text, kind)
		status.Text = text
		status.TextColor3 = kind == "error" and Palette.neon.pink
			or kind == "ok" and Palette.neon.green
			or Palette.text.secondary
	end

	--- Dispatch + execute + close (main.md §1 workflow loop).
	function self:submit(text)
		local prompt = Util.trim(text or input.Text)
		if prompt == "" or self.busy then
			return
		end

		self.busy = true
		input.Text = ""
		self:setStatus("dispatching to " .. State.provider() .. "...")

		Chat.sendAndRun(prompt, function(line, kind)
			if app and app.dashboard then
				app.dashboard:log(line, kind)
			end
		end, {
			onExecuted = function(ok, output)
				self:setStatus(
					ok and ("executed: " .. Util.truncate(tostring(output), 64)) or ("failed: " .. tostring(output)),
					ok and "ok" or "error"
				)
			end,
			onError = function(message)
				self:setStatus(tostring(message), "error")
			end,
			onFinish = function()
				self.busy = false
				if self.isOpen then
					task.delay(0.6, function()
						if not self.busy and self.isOpen then
							self:close()
						end
					end)
				end
			end,
		})
	end

	--- True when a screen-space point sits inside the module.
	local function insideModule(position)
		local topLeft = module.AbsolutePosition
		local size = module.AbsoluteSize

		return position.X >= topLeft.X
			and position.X <= topLeft.X + size.X
			and position.Y >= topLeft.Y
			and position.Y <= topLeft.Y + size.Y
	end

	-- Input -------------------------------------------------------------------

	connections.add(UserInputService.InputBegan, function(inputObject, processed)
		if inputObject.KeyCode == Enum.KeyCode.Semicolon and not processed then
			self:toggle()
		elseif inputObject.KeyCode == Enum.KeyCode.Escape and self.isOpen then
			self:close()
		end
	end)

	-- Clicking the dim backdrop (outside the module) closes.
	connections.add(overlay.InputBegan, function(inputObject)
		local isClick = inputObject.UserInputType == Enum.UserInputType.MouseButton1
			or inputObject.UserInputType == Enum.UserInputType.Touch

		if isClick and not insideModule(inputObject.Position) then
			self:close()
		end
	end)

	function self:destroy()
		self:close()
		connections.destroy()
		sinkMovement(false)
		if overlay then
			overlay:Destroy()
		end
	end

	self.overlay = overlay
	self.module = module
	self.input = input
	self.title = title

	return self
end

return QuickMenu
