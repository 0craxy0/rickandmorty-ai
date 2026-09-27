--[[
	ui/ChatPanel.lua
	Chat mode: conversational pane for instructing the AI to write, debug or
	patch Luau blocks (idea/ui-creation.md §3).

	Replies stream in through the typewriter and any fenced code block gets an
	inline "Execute" affordance that routes into the Code runner.
]]

local Chat = require("core/Chat")
local CodeRunner = require("core/CodeRunner")
local Components = require("ui/Components")
local Fonts = require("core/Fonts")
local Palette = require("core/Palette")
local Providers = require("core/Providers")
local State = require("core/State")
local Typewriter = require("core/Typewriter")
local Util = require("core/Util")

local ChatPanel = {}

function ChatPanel.new(parent, app)
	local frame = Util.create("Frame", {
		Name = "ChatPanel",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = parent,
	})

	-- Header ------------------------------------------------------------------

	local header = Util.create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 0, 32),
		Position = UDim2.new(0, 12, 0, 10),
		Parent = frame,
	}, {
		Util.list({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	local companionBadge = Components.badge({
		Name = "CompanionBadge",
		Text = string.upper(State.companion()),
		LayoutOrder = 1,
		Parent = header,
	})

	local providerBadge = Components.badge({
		Name = "ProviderBadge",
		Text = State.provider(),
		Color = Palette.neon.cyan,
		LayoutOrder = 2,
		Parent = header,
	})

	-- Sized to its own text (capped at 180) rather than claiming a fixed 180: a
	-- reserved width that the text rarely uses was enough to push this row past
	-- the header on a small viewport. A scale width is not an option here - it
	-- would stretch inside the horizontal UIListLayout and shove the buttons out.
	local status = Fonts.new("TextLabel", "small", {
		Name = "Status",
		Text = "ready",
		TextColor3 = Palette.text.dim,
		TextSize = 11,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		LayoutOrder = 3,
		Parent = header,
	})

	Util.create("UISizeConstraint", { MaxSize = Vector2.new(180, 1000), Parent = status })

	Components.button({
		Name = "Reset",
		Text = "New chat",
		Variant = "dark",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 4,
		Parent = header,
		OnClick = function()
			State.resetHistory()
			panel:clear()
			panel:setStatus("conversation archived")
		end,
	})

	-- Transcript --------------------------------------------------------------

	local transcript = Components.scroll({
		Name = "Transcript",
		Size = UDim2.new(1, -8, 1, -166),
		Position = UDim2.new(0, 4, 0, 50),
		Padding = 14,
		Inset = 8,
		Parent = frame,
	})

	-- Composer ----------------------------------------------------------------

	local composer = Util.create("Frame", {
		Name = "Composer",
		BackgroundColor3 = Palette.surfaces.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 0, 96),
		Position = UDim2.new(0, 12, 1, -108),
		Parent = frame,
	}, {
		Util.corner(10),
		Util.stroke(Palette.surfaces.border, 1, 0.3),
		Util.padding(10),
	})

	local input = Components.input({
		Name = "Prompt",
		Placeholder = "Ask for a Luau script, a patch, or a refactor...",
		MultiLine = true,
		Wrap = true,
		Size = UDim2.new(1, -96, 1, 0),
		Parent = composer,
		OnSubmit = function(_, enterPressed)
			if enterPressed then
				panel:submit()
			end
		end,
	})

	local sendButton
	sendButton = Components.button({
		Name = "Send",
		Text = "Send",
		Variant = "green",
		Size = UDim2.new(0, 84, 1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = composer,
		OnClick = function()
			panel:submit()
		end,
	})

	local hint = Fonts.new("TextLabel", "small", {
		Name = "Hint",
		Text = "Enter sends  |  replies auto-detect ```lua blocks  |  the persona prompt stays hidden",
		TextColor3 = Palette.text.dim,
		TextSize = 10,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 14),
		Position = UDim2.new(0, 14, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	-- Turns -------------------------------------------------------------------

	local order = 0
	local thinking = false

	local function stopThinking()
		thinking = false
	end

	local function startThinking()
		thinking = true
		task.spawn(function()
			local frames = { "", ".", "..", "..." }
			local index = 1
			while thinking do
				status.Text = string.upper(State.companion()) .. " is thinking" .. frames[index]
				index = index % #frames + 1
				task.wait(0.4)
			end
		end)
	end

	local function addTurn(role, text, opts)
		opts = opts or {}
		order += 1

		local isUser = role == "user"
		local theme = Palette.character(State.companion())

		local turn = Util.create("Frame", {
			Name = role,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = transcript,
		}, {
			Util.list({ Padding = UDim.new(0, 6) }),
		})

		Fonts.new("TextLabel", "small", {
			Name = "Author",
			Text = isUser and "OPERATOR" or string.upper(State.companion()),
			TextColor3 = isUser and Palette.text.dim or theme.text,
			TextSize = 10,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = turn,
		})

		local bubble = Components.panel({
			Name = "Bubble",
			BackgroundColor3 = isUser and Palette.surfaces.card or Palette.surfaces.panel,
			StrokeColor = isUser and Palette.surfaces.border or theme.glow,
			StrokeTransparency = isUser and 0.4 or 0.55,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = turn,
		}, {
			Util.padding(12),
			Util.list({ Padding = UDim.new(0, 8) }),
		})

		local body = Fonts.new("TextLabel", "body", {
			Name = "Body",
			Text = "",
			RichText = true,
			TextColor3 = Palette.text.primary,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			LayoutOrder = 1,
			Parent = bubble,
		})

		if opts.animate then
			local handle = Typewriter.play(body, text)
			Typewriter.bindSkip(bubble, handle)
		else
			body.Text = Typewriter.toRichText(text)
		end

		-- Inline actions for assistant turns that carry code.
		if not isUser and CodeRunner.looksLikeCode(text) then
			local actions = Util.create("Frame", {
				Name = "Actions",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 2,
				Parent = bubble,
			}, {
				Util.list({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 6),
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),
			})

			Components.button({
				Name = "Execute",
				Text = "Execute",
				Variant = "green",
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 1,
				Parent = actions,
				OnClick = function()
					local ok, output = CodeRunner.execute(text)
					if app and app.notify then
						app.notify(ok and "Executed" or "Execution failed", tostring(output ~= "" and output or "script finished"))
					end
					if app and app.dashboard then
						app.dashboard:log(ok and ("[executed] " .. tostring(output)) or ("[error] " .. tostring(output)), ok and "ok" or "error")
					end
				end,
			})

			Components.button({
				Name = "SendToCode",
				Text = "Open in Code",
				Variant = "dark",
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 2,
				Parent = actions,
				OnClick = function()
					if app and app.dashboard then
						app.dashboard:setTab("Code")
						app.dashboard:loadCode(CodeRunner.stripFences(CodeRunner.extractCode(text) or text))
					end
				end,
			})
		end

		task.defer(function()
			transcript.CanvasPosition = Vector2.new(0, math.max(0, transcript.AbsoluteCanvasSize.Y))
		end)

		return turn
	end

	-- Panel API ---------------------------------------------------------------

	local panel = {
		frame = frame,
		transcript = transcript,
		input = input,
	}

	function panel:setStatus(text, kind)
		status.Text = text
		status.TextColor3 = kind == "error" and Palette.neon.pink
			or kind == "ok" and Palette.neon.green
			or Palette.text.dim
	end

	function panel:addUser(text)
		return addTurn("user", text)
	end

	function panel:addAssistant(text, animate)
		return addTurn("assistant", text, { animate = animate })
	end

	function panel:clear()
		Util.clear(transcript)
		order = 0
	end

	--- Re-renders the stored history without animation.
	function panel:render()
		panel:clear()
		for _, message in ipairs(State.history) do
			if message.role ~= "system" then
				addTurn(message.role, message.content)
			end
		end
	end

	function panel:refresh()
		companionBadge:setText(string.upper(State.companion()))
		providerBadge:setText(State.provider())
	end

	function panel:focusInput()
		input:CaptureFocus()
	end

	function panel:setPrompt(text)
		input.Text = text
		input:CaptureFocus()
	end

	function panel:submit(text)
		local prompt = Util.trim(text or input.Text)
		if prompt == "" then
			return
		end

		input.Text = ""
		panel:addUser(prompt)

		local provider = Providers.get(State.provider())
		if provider.style ~= "freebuff" and State.apiKey(State.provider()) == "" and State.provider() ~= "AgentRouter" then
			panel:setStatus("warning: no API key set for " .. State.provider(), "error")
		end

		startThinking()

		Chat.send(prompt, {
			onDone = function(reply)
				stopThinking()
				panel:addAssistant(reply, true)
				panel:setStatus("replied", "ok")
			end,
			onError = function(message)
				stopThinking()
				panel:addAssistant("**Request failed**\n\n" .. tostring(message))
				panel:setStatus("request failed", "error")
			end,
			onFinish = function()
				stopThinking()
				if app and app.sidebar then
					app.sidebar:refreshSessions()
				end
			end,
		})
	end

	return panel
end

return ChatPanel
