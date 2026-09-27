--[[
	ui/CoworkPanel.lua
	Cowork mode: drops the local bridge into the executor's workspace folder and
	tells the user how to launch the external interface
	(idea/backend.md §2, idea/ui-creation.md §3).
]]

local Components = require("ui/Components")
local Cowork = require("core/Cowork")
local Fonts = require("core/Fonts")
local Notify = require("ui/Notify")
local Palette = require("core/Palette")
local Providers = require("core/Providers")
local State = require("core/State")
local Util = require("core/Util")

local CoworkPanel = {}

function CoworkPanel.new(parent, app)
	local frame = Util.create("Frame", {
		Name = "CoworkPanel",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = parent,
	})

	local title = Fonts.new("TextLabel", "subtitle", {
		Name = "Title",
		Text = "Cowork bridge",
		TextColor3 = Palette.text.primary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.new(0, 12, 0, 10),
		Parent = frame,
	})

	local blurb = Fonts.new("TextLabel", "small", {
		Name = "Blurb",
		Text = "Generates a local Node bridge in your executor workspace. Launching it opens the "
			.. "full-sized interface at "
			.. Cowork.URL
			.. ", where requests go straight to the provider without Roblox's HTTP whitelist.",
		TextColor3 = Palette.text.secondary,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -24, 0, 0),
		Position = UDim2.new(0, 12, 0, 34),
		TextWrapped = true,
		Parent = frame,
	})

	-- Info card ---------------------------------------------------------------

	local info = Components.panel({
		Name = "Info",
		Size = UDim2.new(1, -24, 0, 74),
		Position = UDim2.new(0, 12, 0, 92),
		Parent = frame,
	}, {
		Util.padding(10, 12, 10, 12),
		Util.list({ Padding = UDim.new(0, 4) }),
	})

	local function infoLine(order, text)
		return Fonts.new("TextLabel", "log", {
			Name = "Info" .. tostring(order),
			Text = text,
			TextColor3 = Palette.text.secondary,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 14),
			LayoutOrder = order,
			Parent = info,
		})
	end

	local dirLine = infoLine(1, "")
	local urlLine = infoLine(2, "")
	local providerLine = infoLine(3, "")
	local statusLine = infoLine(4, "")

	-- Actions -----------------------------------------------------------------

	local actionRow = Util.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.new(0, 12, 0, 178),
		Parent = frame,
	}, {
		Util.list({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	local console = Components.console({
		Name = "Console",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(1, -24, 1, -228),
		Parent = frame,
	})

	local panel = {
		frame = frame,
		console = console,
	}

	function panel:refresh()
		local provider = Providers.get(State.provider())

		dirLine.Text = "folder   : " .. Cowork.DIR .. "/"
		urlLine.Text = "interface: " .. Cowork.URL .. "   (node 18+ required)"
		providerLine.Text = "provider : " .. State.provider() .. " // " .. tostring(State.model(provider.model))
		statusLine.Text = "status   : " .. Cowork.status() .. "   transport: " .. (Cowork.available() and "writefile ok" or "unavailable")
		statusLine.TextColor3 = Cowork.available() and Palette.neon.green or Palette.neon.pink
	end

	function panel:log(text, kind)
		console:append(text, kind)
	end

	function panel:generate()
		panel:log("> writing " .. Cowork.DIR .. "/ ...", "info")

		local ok, result = Cowork.build()
		if not ok then
			panel:log("[error] " .. tostring(result), "error")
			if app and app.notify then
				app.notify("Cowork bridge failed", tostring(result))
			end
			panel:refresh()
			return
		end

		for _, path in ipairs(result) do
			panel:log("  wrote " .. tostring(path), "ok")
		end

		panel:log("done. double-click " .. Cowork.launchers.windows .. " (or run " .. Cowork.launchers.posix .. ") inside that folder.", "ok")
		panel:refresh()

		Notify.coworkInstructions(result)
	end

	Components.button({
		Name = "Generate",
		Text = "Generate bridge",
		Variant = "green",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = actionRow,
		OnClick = function()
			panel:generate()
		end,
	})

	Components.button({
		Name = "Status",
		Text = "Re-check status",
		Variant = "dark",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = actionRow,
		OnClick = function()
			panel:refresh()
			panel:log("[status] " .. Cowork.status(), "info")
		end,
	})

	Components.button({
		Name = "CopyUrl",
		Text = "Copy URL",
		Variant = "dark",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Parent = actionRow,
		OnClick = function()
			local setclipboard = Util.global("setclipboard")
			if type(setclipboard) == "function" then
				pcall(setclipboard, Cowork.URL)
				panel:log("[clipboard] " .. Cowork.URL, "ok")
			else
				panel:log("[clipboard] unavailable - open " .. Cowork.URL .. " manually", "warn")
			end
		end,
	})

	panel:refresh()
	panel:log("cowork ready. press 'Generate bridge' to write the local files.", "info")

	return panel
end

return CoworkPanel
