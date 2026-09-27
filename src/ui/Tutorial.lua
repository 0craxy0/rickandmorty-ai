--[[
	ui/Tutorial.lua
	First-run onboarding from idea/main.md §4 and idea/ui-creation.md §5.

	  * choose rick.png or morty.png as the guide
	  * dialogue types out character-by-character at 0.03s with a click per glyph
	  * a custom vector arrow is drawn natively (rotated square head + shaft) and
	    bounced with math.sin(tick() * 5) * 10 beside the control being explained
	  * clicking the dialogue frame reveals the rest instantly

	Layout: the card splits into a portrait column (left) and a body column
	(right) that swaps between the dialogue label and the companion picker.
]]

local Assets = require("core/Assets")
local Companion = require("ui/Companion")
local Components = require("ui/Components")
local Fonts = require("core/Fonts")
local Palette = require("core/Palette")
local State = require("core/State")
local Typewriter = require("core/Typewriter")
local Util = require("core/Util")

local Tutorial = {}

Tutorial.DIM = 0.55

--- In-character script, one per guide.
Tutorial.dialogue = {
	Rick = {
		welcome = "Alright, listen up. This is the dashboard. Everything you'd normally do by hand, the AI does in about nine seconds. Try to keep up.",
		provider = "Pick your brain donor here. Every one of them already has its own payload template wired up. FreeBuff skips the whole API key song and dance if you're broke.",
		tabs = "Three modes. Chat to write and patch, Cowork to spawn the real interface outside this game, Code to run whatever you paste in. Try not to break the game.",
		quickmenu = "And whenever you're mid-game, hit the semicolon key. Type a prompt, it writes the script and runs it before you can even ask a follow-up question.",
		done = "That's it. Don't embarrass me.",
	},
	Morty = {
		welcome = "Oh jeez, okay, uh, this is the dashboard. It's, it's not that scary once you get used to it, I promise.",
		provider = "This dropdown picks which AI we, um, talk to. You can switch whenever, and each one already has its own request setup saved. You'll probably want FreeBuff if you don't have a key.",
		tabs = "Th-there's three tabs here. Chat is for talking, Cowork opens the big interface in your browser, and Code lets you run scripts right here.",
		quickmenu = "Oh! And, um, if you press the semicolon key you get a mini prompt box. You type what you want and it, it writes and runs the script for you.",
		done = "That's, that's everything! You're gonna do great, I mean, probably.",
	},
}

-- Pointer ---------------------------------------------------------------------

--- Native vector arrow: shaft plus a rotated square head (no external asset).
local function buildPointer(parent, companion)
	local theme = Palette.character(companion)

	local pointer = Util.create("Frame", {
		Name = "Pointer",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 34, 0, 18),
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		ZIndex = 320,
		Parent = parent,
	})

	Util.create("Frame", {
		Name = "Shaft",
		BackgroundColor3 = theme.glow,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 22, 0, 3),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 320,
		Parent = pointer,
	}, { Util.corner(2) })

	local head = Util.create("Frame", {
		Name = "Head",
		BackgroundColor3 = theme.glow,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 11, 0, 11),
		Position = UDim2.new(1, -7, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		ZIndex = 321,
		Parent = pointer,
	})
	Util.corner(2).Parent = head

	return pointer
end

--- Parks the pointer beside `getTarget()` and bounces it on a sine curve.
local function trackPointer(pointer, getTarget)
	local offset = 0

	local function update()
		local target = getTarget()
		if not target or not target.Parent then
			pointer.Visible = false
			return
		end

		local absolute = target.AbsolutePosition
		local size = target.AbsoluteSize

		pointer.Visible = target.Visible
		pointer.Position = UDim2.new(0, absolute.X - 12 + offset, 0, absolute.Y + size.Y / 2)
	end

	local connection = game:GetService("RunService").RenderStepped:Connect(function()
		offset = math.sin(tick() * 5) * 10 -- the bounce curve from the spec
		update()
	end)

	update()

	return function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		pointer.Visible = false
	end
end

-- Tutorial --------------------------------------------------------------------

--- `onFinish` runs once the user completes (or skips) onboarding.
function Tutorial.start(gui, app, onFinish)
	local overlay = Util.create("Frame", {
		Name = "Tutorial",
		BackgroundColor3 = Palette.overlay.color,
		BackgroundTransparency = Tutorial.DIM,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 300,
		Parent = gui,
	})

	local card = Components.panel({
		Name = "Guide",
		BackgroundColor3 = Palette.surfaces.background,
		Size = UDim2.new(0, 740, 0, 214),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 305,
		Parent = overlay,
	}, {
		Util.padding(16),
	})

	local portraitHolder = Util.create("Frame", {
		Name = "PortraitHolder",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 136, 1, 0),
		ZIndex = 306,
		Parent = card,
	})

	local textHolder = Util.create("Frame", {
		Name = "TextHolder",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -152, 1, -42),
		Position = UDim2.new(0, 152, 0, 0),
		ZIndex = 306,
		Parent = card,
	})

	local dialogue = Fonts.new("TextLabel", "body", {
		Name = "Dialogue",
		Text = "",
		RichText = true,
		TextColor3 = Palette.text.primary,
		TextSize = 14,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 307,
		Parent = textHolder,
	})

	local choiceHolder = Util.create("Frame", {
		Name = "Choices",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 307,
		Parent = textHolder,
	})

	local buttonRow = Util.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -152, 0, 30),
		Position = UDim2.new(0, 152, 1, -30),
		ZIndex = 307,
		Parent = card,
	}, {
		Util.list({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	-- Fixed offset width: a scale-width child inside this horizontal
	-- UIListLayout would stretch and push the buttons off the card.
	local progress = Fonts.new("TextLabel", "small", {
		Name = "Progress",
		Text = "",
		TextColor3 = Palette.text.dim,
		TextSize = 10,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 220, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		LayoutOrder = 1,
		Parent = buttonRow,
	})

	local guidePortrait
	local pointer
	local stopTracking

	local function mountPortrait(companion)
		if guidePortrait then
			guidePortrait:Destroy()
		end

		guidePortrait = Companion.guide(portraitHolder, companion, {
			Size = Companion.GUIDE_SIZE,
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = portraitHolder,
		})

		if pointer then
			pointer:Destroy()
		end

		pointer = buildPointer(overlay, companion)
	end

	local function setTarget(getTarget)
		if stopTracking then
			stopTracking()
			stopTracking = nil
		end

		if getTarget then
			stopTracking = trackPointer(pointer, getTarget)
		elseif pointer then
			pointer.Visible = false
		end
	end

	-- Stop the RenderStepped loop if the overlay disappears mid-tour.
	overlay.Destroying:Connect(function()
		if stopTracking then
			stopTracking()
			stopTracking = nil
		end
	end)

	-- Steps -------------------------------------------------------------------

	local steps = {}
	local index = 1
	local handle
	local showStep
	local nextButton

	local function advance()
		if handle then
			handle.skip()
			handle = nil
		end

		local previous = steps[index]
		if previous and previous.onLeave then
			previous.onLeave()
		end

		index += 1
		showStep()
	end

	local function buildChoices()
		Util.clear(choiceHolder)

		Fonts.new("TextLabel", "body", {
			Name = "Prompt",
			Text = "Who's tagging along for the ride?",
			TextColor3 = Palette.text.primary,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 308,
			Parent = choiceHolder,
		})

		for index2, name in ipairs(Palette.characterOrder) do
			local theme = Palette.character(name)
			local offset = (index2 - 1) * 174

			local choice = Components.button({
				Name = name .. "Choice",
				Text = theme.label,
				Variant = "dark",
				Size = UDim2.new(0, 164, 0, 126),
				Position = UDim2.new(0, offset, 0, 32),
				ZIndex = 308,
				Parent = choiceHolder,
				TextColor3 = theme.text,
				OnClick = function()
					State.setCompanion(name)
					State.save()
					if app.OnCompanionChanged then
						app.OnCompanionChanged(name)
					end
					mountPortrait(name)
					advance()
				end,
			})

			choice.TextYAlignment = Enum.TextYAlignment.Bottom
			choice.TextSize = 13

			Util.create("ImageLabel", {
				Name = "Portrait",
				BackgroundTransparency = 1,
				Image = Assets.portrait(name),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.new(1, -16, 0, 84),
				Position = UDim2.new(0.5, 0, 0, 4),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = 309,
				Parent = choice,
			})
		end
	end

	local function speak(text)
		if handle then
			handle.skip()
		end

		handle = Typewriter.play(dialogue, text, {
			onComplete = function()
				nextButton.Text = index >= #steps and "Finish" or "Next"
			end,
		})
		Typewriter.bindSkip(card, handle)
	end

	showStep = function()
		local step = steps[index]
		if not step then
			Tutorial.finish(app, overlay, onFinish)
			return
		end

		if step.onEnter then
			step.onEnter()
		end

		if step.kind == "choose" then
			progress.Text = "choose your companion"
			dialogue.Visible = false
			choiceHolder.Visible = true
			nextButton.Visible = false
			setTarget(nil)
			buildChoices()
			return
		end

		progress.Text = string.format("step %d of %d", index, #steps)
		choiceHolder.Visible = false
		dialogue.Visible = true
		nextButton.Visible = true

		local lines = Tutorial.dialogue[State.companion()] or Tutorial.dialogue.Rick
		speak(lines[step.key] or "...")
		setTarget(step.target)
	end

	Components.button({
		Name = "Skip",
		Text = "Skip tour",
		Variant = "dark",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = buttonRow,
		OnClick = function()
			Tutorial.finish(app, overlay, onFinish)
		end,
	})

	nextButton = Components.button({
		Name = "Next",
		Text = "Next",
		Variant = "green",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Parent = buttonRow,
		OnClick = advance,
	})

	-- Step list ---------------------------------------------------------------

	if not State.data.companion then
		table.insert(steps, { kind = "choose" })
	end

	table.insert(steps, {
		key = "welcome",
		onEnter = function()
			if app.dashboard then
				app.dashboard:setVisible(true)
				app.dashboard:setTab("Chat")
			end
		end,
	})

	table.insert(steps, {
		key = "provider",
		target = function()
			return app.sidebar and app.sidebar.providerDropdown.Toggle
		end,
	})

	table.insert(steps, {
		key = "tabs",
		onEnter = function()
			if app.dashboard then
				app.dashboard:setTab("Cowork")
			end
		end,
		target = function()
			return app.dashboard and app.dashboard.tabs
		end,
	})

	table.insert(steps, {
		key = "quickmenu",
		onEnter = function()
			if app.quickMenu then
				app.quickMenu:open()
			end
		end,
		onLeave = function()
			if app.quickMenu then
				app.quickMenu:close()
			end
		end,
		target = function()
			return app.quickMenu and app.quickMenu.module
		end,
	})

	table.insert(steps, { key = "done" })

	mountPortrait(State.companion())
	showStep()

	return overlay
end

--- Commits onboarding and tears the overlay down.
function Tutorial.finish(app, overlay, onFinish)
	State.data.onboarded = true
	State.data.companion = State.companion()
	State.save()

	if app.quickMenu and app.quickMenu.close then
		app.quickMenu:close()
	end

	if overlay then
		overlay:Destroy()
	end

	if onFinish then
		onFinish()
	end
end

return Tutorial
