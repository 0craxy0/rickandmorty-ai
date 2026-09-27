--[[
	ui/CodePanel.lua
	Code mode: the on-screen executor from idea/ui-creation.md §3 — monospace
	editor with a live line gutter, raw script testing and an output console.

	Note: the gutter is a plain label, so it does not scroll in lockstep with
	the TextBox. Line counts stay correct because the gutter is rebuilt from the
	editor's contents on every change.
]]

local Chat = require("core/Chat")
local CodeRunner = require("core/CodeRunner")
local Components = require("ui/Components")
local Fonts = require("core/Fonts")
local Palette = require("core/Palette")
local State = require("core/State")
local Util = require("core/Util")

local CodePanel = {}

local SAMPLE = [[-- Rick & Morty AI Executor // sample script
local portal = Instance.new("Part")
portal.Name = "PortalTest"
portal.Shape = Enum.PartType.Ball
portal.Material = Enum.Material.Neon
portal.Color = Color3.fromRGB(0, 255, 136)
portal.Size = Vector3.new(4, 4, 4)
portal.Position = Vector3.new(0, 6, 0)
portal.Anchored = true
portal.Parent = workspace

print("RickMortyAI sample executed at " .. os.date("%H:%M:%S"))
]]

function CodePanel.new(parent, app)
	local frame = Util.create("Frame", {
		Name = "CodePanel",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = parent,
	})

	-- Toolbar -----------------------------------------------------------------

	local toolbar = Util.create("Frame", {
		Name = "Toolbar",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 0, 32),
		Position = UDim2.new(0, 12, 0, 10),
		Parent = frame,
	}, {
		Util.list({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	-- Fixed offset width: a scale-width child inside a horizontal UIListLayout
	-- would stretch and shove the trailing buttons off the row.
	local status = Fonts.new("TextLabel", "small", {
		Name = "Status",
		Text = "idle",
		TextColor3 = Palette.text.dim,
		TextSize = 11,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 170, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		LayoutOrder = 90,
		Parent = toolbar,
	})

	-- Editor ------------------------------------------------------------------

	local editor = Util.create("Frame", {
		Name = "Editor",
		BackgroundColor3 = Palette.surfaces.background,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 0.55, 0),
		Position = UDim2.new(0, 12, 0, 50),
		Parent = frame,
	}, {
		Util.corner(8),
		Util.stroke(Palette.surfaces.border, 1, 0.2),
	})

	local gutter = Fonts.new("TextLabel", "code", {
		Name = "Gutter",
		Text = "1",
		TextColor3 = Palette.text.dim,
		TextSize = 12,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 40, 1, -16),
		Position = UDim2.new(0, 8, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = editor,
	})

	local box = Components.input({
		Name = "Source",
		MultiLine = true,
		Placeholder = "-- paste Luau here, or generate code from the Chat tab",
		Role = "code",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -66, 1, -12),
		Position = UDim2.new(0, 56, 0, 6),
		Parent = editor,
		Wrap = false,
	})

	local function refreshGutter()
		local count = 1
		for _ in string.gmatch(box.Text, "\n") do
			count += 1
		end

		local numbers = {}
		for index = 1, count do
			table.insert(numbers, tostring(index))
		end
		gutter.Text = table.concat(numbers, "\n")
	end

	box:GetPropertyChangedSignal("Text"):Connect(refreshGutter)

	-- Console -----------------------------------------------------------------

	local console = Components.console({
		Name = "Console",
		Size = UDim2.new(1, -24, 0.45, -76),
		Position = UDim2.new(0, 12, 0, 50),
		Parent = frame,
	})

	console.frame.Position = UDim2.new(0, 12, 1, -1)
	console.frame.AnchorPoint = Vector2.new(0, 1)
	console.frame.Size = UDim2.new(1, -24, 0.45, -60)

	-- Actions -----------------------------------------------------------------

	local panel = {
		frame = frame,
		editor = editor,
		console = console,
	}

	function panel:setStatus(text, kind)
		status.Text = text
		status.TextColor3 = kind == "error" and Palette.neon.pink
			or kind == "ok" and Palette.neon.green
			or Palette.text.dim
	end

	function panel:log(text, kind)
		console:append(text, kind)
	end

	function panel:setSource(text)
		box.Text = text or ""
		refreshGutter()
	end

	function panel:getSource()
		return box.Text
	end

	function panel:clearConsole()
		console:clear()
		panel:setStatus("console cleared")
	end

	function panel:run()
		local source = Util.trim(box.Text)
		if source == "" then
			panel:setStatus("nothing to run", "error")
			return
		end

		panel:log("> execute (" .. tostring(select(2, string.gsub(source, "\n", "")) + 1) .. " lines)", "info")

		local ok, output = CodeRunner.execute(source, { name = "code_pane_" .. tostring(os.time()) })
		if ok then
			panel:log(tostring(output ~= "" and output or "script finished"), "ok")
			panel:setStatus("executed", "ok")
		else
			panel:log(tostring(output), "error")
			panel:setStatus("execution failed", "error")
		end
	end

	function panel:extractLastReply()
		for index = #State.history, 1, -1 do
			local message = State.history[index]
			if message.role == "assistant" then
				local code = CodeRunner.extractCode(message.content)
				if code then
					panel:setSource(code)
					panel:setStatus("pulled latest reply into the editor", "ok")
				else
					panel:setStatus("latest reply has no code block", "error")
				end
				return
			end
		end

		panel:setStatus("no assistant reply yet", "error")
	end

	--- Sends the current editor contents through the AI for a review pass.
	function panel:askForReview()
		local source = Util.trim(box.Text)
		if source == "" then
			panel:setStatus("nothing to review", "error")
			return
		end

		panel:setStatus("requesting review...")
		Chat.send("Review and fix this Luau for Roblox, then return the corrected script in a ```lua block:\n\n```lua\n" .. source .. "\n```", {
			onDone = function(reply)
				panel:log("[review]\n" .. reply, "info")
				local code = CodeRunner.extractCode(reply)
				if code then
					panel:setSource(code)
					panel:setStatus("review applied to the editor", "ok")
				end
			end,
			onError = function(message)
				panel:log("[error] " .. tostring(message), "error")
				panel:setStatus("review failed", "error")
			end,
		})
	end

	-- Toolbar wiring ----------------------------------------------------------

	local actions = {
		{ label = "Run", variant = "green", onClick = function() panel:run() end },
		{ label = "From chat", variant = "dark", onClick = function() panel:extractLastReply() end },
		{ label = "Review", variant = "dark", onClick = function() panel:askForReview() end },
		{ label = "Sample", variant = "dark", onClick = function() panel:setSource(SAMPLE) end },
		{ label = "Clear", variant = "dark", onClick = function()
			panel:setSource("")
			panel:clearConsole()
		end },
	}

	for index, action in ipairs(actions) do
		Components.button({
			Name = action.label,
			Text = action.label,
			Variant = action.variant,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = index,
			Parent = toolbar,
			OnClick = action.onClick,
		})
	end

	-- Seed with the sample so the pane is never empty on first open.
	panel:setSource(SAMPLE)
	panel:log("Rick & Morty AI Executor // code pane ready", "info")

	return panel
end

return CodePanel
