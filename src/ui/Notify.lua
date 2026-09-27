--[[
	ui/Notify.lua
	Toasts for errors, execution results and the Cowork "double-click the bridge
	file" instructions (idea/backend.md §2 step 4).

	Layout note: the accent rail is parented to the wrap, not the card, because
	the card runs a UIListLayout and every visible GuiObject inside it would
	otherwise be given a slot.
]]

local Assets = require("core/Assets")
local Components = require("ui/Components")
local Cowork = require("core/Cowork")
local Fonts = require("core/Fonts")
local Palette = require("core/Palette")
local State = require("core/State")
local Util = require("core/Util")

local Notify = {}

Notify.container = nil
Notify.history = {}

-- Live toasts, oldest first. The container grows downward with its list layout,
-- so a burst of toasts would stack past the bottom of the screen.
Notify.active = {}
Notify.MAX_VISIBLE = 4

-- Gap between stacked toasts, mirroring the container's UIListLayout.
Notify.GAP = 10

--[[
	Retires old toasts until the rail fits the screen. The count cap alone is not
	enough: a single Cowork-instructions toast is taller than 200px, so four of them
	still run off a 768px-tall display. Sizes come from the layout pass that just
	placed the toast, so this settles in one go; the newest toast is always kept,
	even if it alone is taller than the screen.
]]
function Notify.trimToScreen()
	local container = Notify.container
	local screen = container and container.Parent
	if not container or not screen then
		return
	end

	local limit = screen.AbsoluteSize.Y - 36

	while #Notify.active > 1 do
		local children = container:GetChildren()
		local total = 0

		for index, child in ipairs(children) do
			total = total + child.AbsoluteSize.Y
			if index > 1 then
				total = total + Notify.GAP
			end
		end

		if total <= limit then
			return
		end

		local oldest = table.remove(Notify.active, 1)
		if not oldest then
			return
		end
		oldest.dismiss()
	end
end

local VARIANT_COLORS = {
	info = Palette.neon.cyan,
	ok = Palette.neon.green,
	warn = Palette.characters.Morty.text,
	error = Palette.neon.pink,
}

function Notify.setup(gui)
	if Notify.container and Notify.container.Parent then
		return Notify.container
	end

	Notify.container = Util.create("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 360, 0, 0),
		Position = UDim2.new(1, -18, 0, 18),
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 200,
		Parent = gui,
	}, {
		Util.list({
			Padding = UDim.new(0, Notify.GAP),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	})

	-- Trim on both triggers: the rail grows when a toast arrives, and the screen
	-- can shrink under a stack that already fits (the rail itself keeps its size
	-- through a resize, since it is sized by its content).
	Notify.container:GetPropertyChangedSignal("AbsoluteSize"):Connect(Notify.trimToScreen)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Notify.trimToScreen)

	return Notify.container
end

--[[
	options = {
		Title, Body, Variant ("info"|"ok"|"warn"|"error"),
		Duration (seconds, 0 = sticky), Portrait (companion name or false),
		Actions = { { label = string, Variant = string, OnClick = function } }
	}

	Returns (wrap, dismiss).
]]
function Notify.toast(options)
	options = options or {}

	local container = options.Parent or Notify.container
	if not container or not container.Parent then
		warn("[RickMortyAI] " .. tostring(options.Title or "") .. ": " .. tostring(options.Body or ""))
		return nil
	end

	local accent = VARIANT_COLORS[options.Variant or "info"] or Palette.neon.cyan

	local wrap = Components.panel({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Palette.surfaces.panel,
		Parent = container,
	})

	local stroke = wrap:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = accent
		stroke.Transparency = 0.55
	end

	local rail = Util.create("Frame", {
		Name = "Rail",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		-- Offset height only: a scale-height child under an AutomaticSize parent
		-- makes the layout circular, so it is driven from the card instead.
		Size = UDim2.new(0, 3, 0, 0),
		Position = UDim2.new(0, 0, 0, 6),
		ZIndex = 2,
		Parent = wrap,
	}, { Util.corner(2) })

	local card = Util.create("Frame", {
		Name = "Card",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -10, 0, 0),
		Position = UDim2.new(0, 10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = wrap,
	}, {
		Util.padding(12, 12, 12, 10),
		Util.list({ Padding = UDim.new(0, 8) }),
	})

	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		rail.Size = UDim2.new(0, 3, 0, math.max(0, card.AbsoluteSize.Y - 12))
	end)

	local scale = Util.create("UIScale", { Scale = 0.94, Parent = wrap })

	local header = Util.create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = card,
	})

	Fonts.new("TextLabel", "subtitle", {
		Name = "Title",
		Text = options.Title or "Notice",
		TextColor3 = accent,
		TextSize = 14,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -30, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = header,
	})

	local close = Components.button({
		Name = "Close",
		Text = "x",
		Variant = "dark",
		Size = UDim2.new(0, 24, 0, 18),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Radius = 6,
		Parent = header,
	})

	local content = Util.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = card,
	})

	local textInset = 0

	if options.Portrait ~= false then
		local portraitName = options.Portrait or State.companion()
		textInset = 46

		Util.create("ImageLabel", {
			Name = "Portrait",
			BackgroundTransparency = 1,
			Image = Assets.portrait(portraitName),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(0, 40, 0, 40),
			Position = UDim2.new(0, 0, 0, 0),
			ZIndex = 3,
			Parent = content,
		})
	end

	Fonts.new("TextLabel", "body", {
		Name = "Body",
		Text = options.Body or "",
		TextColor3 = Palette.text.primary,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -textInset, 0, 0),
		Position = UDim2.new(0, textInset, 0, 0),
		TextWrapped = true,
		Parent = content,
	})

	if options.Actions and #options.Actions > 0 then
		local actions = Util.create("Frame", {
			Name = "Actions",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 3,
			Parent = card,
		}, {
			Util.list({
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		})

		for index, action in ipairs(options.Actions) do
			Components.button({
				Name = "Action" .. tostring(index),
				Text = action.label,
				Variant = action.Variant or "dark",
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = index,
				Parent = actions,
				OnClick = function()
					if action.OnClick then
						action.OnClick()
					end
				end,
			})
		end
	end

	-- Fade + pop in (position is owned by the container's list layout).
	wrap.BackgroundTransparency = 1
	Util.animate(wrap, { BackgroundTransparency = 0 }, 0.2)
	Util.animate(scale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local dismissed = false
	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true

		for index, entry in ipairs(Notify.active) do
			if entry.toast == wrap then
				table.remove(Notify.active, index)
				break
			end
		end

		Util.animate(scale, { Scale = 0.94 }, 0.15)
		local tween = Util.animate(wrap, { BackgroundTransparency = 1 }, 0.16)
		tween.Completed:Connect(function()
			wrap:Destroy()
		end)
	end

	close.MouseButton1Click:Connect(dismiss)

	table.insert(Notify.active, { toast = wrap, dismiss = dismiss })
	while #Notify.active > Notify.MAX_VISIBLE do
		local oldest = table.remove(Notify.active, 1)
		oldest.dismiss()
	end

	local duration = options.Duration == nil and 6 or options.Duration
	if duration > 0 then
		task.delay(duration, dismiss)
	end

	table.insert(Notify.history, { title = options.Title, body = options.Body })

	return wrap, dismiss
end

--- Cowork instruction toast with the portrait pointing at the launcher.
function Notify.coworkInstructions(files)
	local list = files and table.concat(files, "\n") or ""

	return Notify.toast({
		Title = "Cowork bridge generated",
		Variant = "ok",
		Duration = 0,
		Body = Cowork.instructions() .. (list ~= "" and ("\n\nWritten:\n" .. list) or ""),
		Actions = {
			{ label = "Got it", Variant = "dark" },
		},
	})
end

function Notify.info(title, body)
	return Notify.toast({ Title = title, Body = body, Variant = "info" })
end

function Notify.error(title, body)
	return Notify.toast({ Title = title, Body = body, Variant = "error", Duration = 9 })
end

return Notify
