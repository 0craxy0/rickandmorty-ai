--[[
	test/stub.lua
	A minimal Roblox environment so the bundle can be executed headlessly under a
	plain Lua 5.3 VM (fengari). It exists to catch the class of bug you only
	otherwise find at runtime inside Roblox, for example:

	    TextLabel is not a valid member of Frame "QuickMenu.Module.Badge"

	i.e. attaching a helper field to an Instance. Writing an unknown member on a
	real Instance throws, so this stub throws too, and records every violation.

	It also provides the Luau-only bits the project relies on (task, table.clear,
	table.find, Enum, getgenv) plus the datatype constructors.
]]

local STUB = {
	violations = {},
	taskErrors = {},
	warnings = {},
	unknownReads = {},
	boundActions = {},
	queue = {},
	created = 0,
	connections = 0,
	delayed = 0,
}
_G.STUB = STUB

-- Luau library additions ------------------------------------------------------

table.clear = function(target)
	for key in pairs(target) do
		target[key] = nil
	end
end

table.find = function(target, wanted)
	for index, entry in ipairs(target) do
		if entry == wanted then
			return index
		end
	end
	return nil
end

-- task ------------------------------------------------------------------------

local function enqueue(fn, ...)
	local args = { ... }
	table.insert(STUB.queue, function()
		return fn(table.unpack(args))
	end)
end

task = {
	spawn = enqueue,
	defer = enqueue,
	wait = function(seconds)
		return seconds or 0
	end,
	-- Recorded only: a real scheduler would run these later, and the smoke test
	-- wants to observe the state *before* timers fire.
	delay = function(_, _)
		STUB.delayed = STUB.delayed + 1
	end,
}

function tick()
	return os.clock() * 1000
end

function warn(...)
	local parts = {}
	for _, value in ipairs({ ... }) do
		table.insert(parts, tostring(value))
	end
	table.insert(STUB.warnings, table.concat(parts, " "))
end

function getgenv()
	return _G
end

-- Datatypes -------------------------------------------------------------------

Color3 = {
	fromRGB = function(r, g, b)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
	end,
	new = function(r, g, b)
		return { R = r or 0, G = g or 0, B = b or 0 }
	end,
	fromHSV = function()
		return { R = 0, G = 0, B = 0 }
	end,
}

UDim = {
	new = function(scale, offset)
		return { Scale = scale or 0, Offset = offset or 0 }
	end,
}

UDim2 = {
	new = function(xScale, xOffset, yScale, yOffset)
		return {
			X = { Scale = xScale or 0, Offset = xOffset or 0 },
			Y = { Scale = yScale or 0, Offset = yOffset or 0 },
		}
	end,
	fromScale = function(x, y)
		return UDim2.new(x or 0, 0, y or 0, 0)
	end,
	fromOffset = function(x, y)
		return UDim2.new(0, x or 0, 0, y or 0)
	end,
}

Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0 }
	end,
}

Vector3 = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}

TweenInfo = {
	new = function(...)
		return { ... }
	end,
}

NumberSequence = { new = function() return {} end }
ColorSequence = { new = function() return {} end }
Rect = { new = function() return {} end }

--- Any Enum.X.Y resolves to a stable interned string, so == still works.
Enum = setmetatable({}, {
	__index = function(_, category)
		return setmetatable({}, {
			__index = function(_, item)
				return "Enum." .. category .. "." .. item
			end,
		})
	end,
})

-- Property whitelist ----------------------------------------------------------

local function propertySet(text)
	local set = {}
	for name in text:gmatch("[%a_][%w_]*") do
		set[name] = true
	end
	return set
end

-- Real Roblox members. Anything outside this list is treated the way Roblox
-- treats it: an error. Keeping it a superset costs nothing but a weaker check.
local ALLOWED = propertySet([[
	Name Parent Archivable ClassName
	ZIndex Visible Size Position AnchorPoint Rotation BackgroundColor3
	BackgroundTransparency BorderSizePixel ClipsDescendants LayoutOrder AutomaticSize
	Active Selectable Interactable Draggable
	Text TextColor3 TextSize Font TextXAlignment TextYAlignment TextWrapped
	TextTruncate TextScaled RichText TextTransparency TextStrokeColor3
	TextStrokeTransparency LineHeight MaxVisibleGraphemes
	PlaceholderText PlaceholderColor3 ClearTextOnFocus MultiLine TextEditable
	CursorPosition SelectionStart ReturnKeyType
	AutoButtonColor Modal Style
	Image ImageColor3 ImageTransparency ScaleType ImageRectOffset ImageRectSize
	ResampleMode SliceCenter SliceScale TileSize
	CanvasSize CanvasPosition AutomaticCanvasSize ScrollingDirection ScrollingEnabled
	ScrollBarThickness ScrollBarImageColor3 ScrollBarImageTransparency ElasticBehavior
	VerticalScrollBarInset HorizontalScrollBarInset
	CornerRadius Color Thickness Transparency ApplyStrokeMode LineJoinMode Enabled
	PaddingTop PaddingRight PaddingBottom PaddingLeft Padding
	FillDirection HorizontalAlignment VerticalAlignment SortOrder Wraps ItemLineAlignment
	CellSize CellPadding FillDirectionMaxCells StartCorner
	AspectRatio AspectType DominantAxis MinSize MaxSize Scale Offset
	DisplayOrder IgnoreGuiInset ResetOnSpawn ZIndexBehavior OnTopOfCoreBlur
	SoundId Volume PlaybackSpeed Looped Playing TimePosition SoundGroup
	Source Disabled RunContext Value
]])

-- Values returned when a property has not been assigned yet.
local DEFAULTS = {
	Visible = true,
	BackgroundTransparency = 0,
	TextTransparency = 0,
	ImageTransparency = 0,
	ZIndex = 1,
	LayoutOrder = 0,
	Text = "",
	TextSize = 14,
	Rotation = 0,
	Transparency = 0,
	Scale = 1,
	Enabled = true,
	PlaybackSpeed = 1,
	Volume = 1,
	AutomaticSize = "None",
	AbsolutePosition = { X = 0, Y = 0 },
	AbsoluteSize = { X = 100, Y = 20 },
	AbsoluteCanvasSize = { X = 0, Y = 0 },
	AbsoluteContentSize = { X = 0, Y = 0 },
	AbsoluteRotation = 0,
	CanvasPosition = { X = 0, Y = 0 },
	CornerRadius = { Scale = 0, Offset = 0 },
	Size = { X = { Scale = 1, Offset = 0 }, Y = { Scale = 1, Offset = 0 } },
	Position = { X = { Scale = 0, Offset = 0 }, Y = { Scale = 0, Offset = 0 } },
	AnchorPoint = { X = 0, Y = 0 },
}

local function copyValue(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = copyValue(entry)
	end
	return copy
end

-- Instances -------------------------------------------------------------------

local SIGNAL_NAMES = propertySet([[
	MouseEnter MouseLeave MouseButton1Down MouseButton1Up MouseButton1Click
	MouseMoved InputBegan InputChanged InputEnded Focused FocusLost Changed
	Destroying AncestryChanged Activated ChildAdded ChildRemoved DescendantAdded
	DescendantRemoving TouchTap SelectionGained SelectionLost
	ReturnPressedFromOnScreenKeyboard
]])

local function newSignal(name)
	local handlers = {}
	local signal = {}

	function signal:Connect(fn)
		table.insert(handlers, fn)
		STUB.connections = STUB.connections + 1
		return { Disconnect = function() end, disconnect = function() end, Connected = true }
	end

	function signal:connect(fn)
		return self:Connect(fn)
	end

	function signal:Once(fn)
		return self:Connect(fn)
	end

	function signal:Wait()
		return nil
	end

	--- Harness-only: drive a signal the way a player would.
	function signal:Fire(...)
		for _, fn in ipairs(handlers) do
			local ok, err = pcall(fn, ...)
			if not ok then
				table.insert(STUB.taskErrors, "handler for " .. name .. ": " .. tostring(err))
			end
		end
	end

	return signal
end

local REGISTRY = setmetatable({}, { __mode = "k" })

local function newInstance(class)
	if type(class) ~= "string" then
		error("Instance.new expects a class name string", 2)
	end

	local data = {
		ClassName = class,
		Name = class,
		children = {},
		attributes = {},
		signals = {},
	}
	STUB.created = STUB.created + 1

	local methods = {}

	local proxy = {}

	function methods.Destroy()
		local parent = data.Parent
		if parent then
			local siblings = REGISTRY[parent].children
			for index, child in ipairs(siblings) do
				if child == proxy then
					table.remove(siblings, index)
					break
				end
			end
		end
		data.Parent = nil
		data.destroyed = true
		local signal = data.signals.Destroying
		if signal then
			signal:Fire()
		end
	end

	function methods.FindFirstChild(_, name, recursive)
		for _, child in ipairs(data.children) do
			if REGISTRY[child].Name == name then
				return child
			end
		end
		if recursive then
			for _, child in ipairs(data.children) do
				local found = child:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	function methods.FindFirstChildOfClass(_, className)
		for _, child in ipairs(data.children) do
			if REGISTRY[child].ClassName == className then
				return child
			end
		end
		return nil
	end

	function methods.WaitForChild(_, name)
		return methods.FindFirstChild(nil, name)
	end

	function methods.GetChildren()
		local copy = {}
		for index, child in ipairs(data.children) do
			copy[index] = child
		end
		return copy
	end

	function methods.GetDescendants()
		local out = {}
		local function walk(node)
			for _, child in ipairs(REGISTRY[node].children) do
				table.insert(out, child)
				walk(child)
			end
		end
		walk(proxy)
		return out
	end

	function methods.GetPropertyChangedSignal(_, property)
		local key = "changed:" .. tostring(property)
		if not data.signals[key] then
			data.signals[key] = newSignal(key)
		end
		return data.signals[key]
	end

	function methods.SetAttribute(_, key, value)
		data.attributes[key] = value
	end

	function methods.GetAttribute(_, key)
		return data.attributes[key]
	end

	function methods.IsA(_, className)
		return className == class or className == "Instance"
	end

	function methods.Clone()
		return newInstance(class)
	end

	function methods.ClearAllChildren()
		for _, child in ipairs(methods.GetChildren()) do
			child:Destroy()
		end
	end

	function methods.GetFullName()
		return data.Name
	end

	function methods.CaptureFocus()
		data.focused = true
		return true
	end

	function methods.ReleaseFocus()
		data.focused = false
	end

	function methods.IsFocused()
		return data.focused == true
	end

	function methods.Play()
		data.playing = true
	end

	function methods.Stop()
		data.playing = false
	end

	setmetatable(proxy, {
		__index = function(_, key)
			local method = methods[key]
			if method ~= nil then
				return method
			end

			if SIGNAL_NAMES[key] then
				if not data.signals[key] then
					data.signals[key] = newSignal(key)
				end
				return data.signals[key]
			end

			local stored = data[key]
			if stored ~= nil then
				return stored
			end

			local default = DEFAULTS[key]
			if default ~= nil then
				return copyValue(default)
			end

			local marker = class .. "." .. tostring(key)
			STUB.unknownReads[marker] = (STUB.unknownReads[marker] or 0) + 1
			return nil
		end,

		__newindex = function(_, key, value)
			if key == "Parent" then
				local previous = data.Parent
				if previous then
					local siblings = REGISTRY[previous].children
					for index, child in ipairs(siblings) do
						if child == proxy then
							table.remove(siblings, index)
							break
						end
					end
				end

				data.Parent = value
				if value then
					table.insert(REGISTRY[value].children, proxy)
				end
				return
			end

			if not ALLOWED[key] then
				-- Exactly what Roblox raises for this mistake.
				local message = string.format("%s is not a valid member of %s", tostring(key), class)
				table.insert(
					STUB.violations,
					string.format('%s "%s"  (assigned by the bundle)', message, data.Name)
				)
				error(message, 2)
			end

			data[key] = value
		end,
	})

	REGISTRY[proxy] = data
	return proxy
end

Instance = {
	new = function(class, parent)
		local instance = newInstance(class)
		if parent then
			instance.Parent = parent
		end
		return instance
	end,
}

-- DataModel and services ------------------------------------------------------

local workspaceInstance = newInstance("Workspace")

local playerGui = newInstance("PlayerGui")
local localPlayer = newInstance("Player")
playerGui.Parent = localPlayer

local players = {
	LocalPlayer = localPlayer,
	GetPlayers = function()
		return { localPlayer }
	end,
	PlayerAdded = newSignal("PlayerAdded"),
	PlayerRemoving = newSignal("PlayerRemoving"),
}

local httpService = {
	JSONEncode = function(_, value)
		return __jsonEncode(value)
	end,
	JSONDecode = function(_, text)
		return __jsonDecode(text)
	end,
	GenerateGUID = function()
		return "00000000-0000-0000-0000-000000000000"
	end,
	HttpEnabled = true,
}

local tweenService = {
	Create = function(_, instance, _, props)
		local tween = {
			Completed = newSignal("Completed"),
			Play = function()
				-- Apply instantly so assertions see the settled state.
				for key, value in pairs(props) do
					local ok, err = pcall(function()
						instance[key] = value
					end)
					if not ok then
						table.insert(
							STUB.violations,
							"tween could not set " .. tostring(key) .. ": " .. tostring(err)
						)
					end
				end
			end,
			Cancel = function() end,
			Pause = function() end,
		}
		return tween
	end,
}

local runService = {
	RenderStepped = newSignal("RenderStepped"),
	Heartbeat = newSignal("Heartbeat"),
	Stepped = newSignal("Stepped"),
	IsClient = function()
		return true
	end,
	IsServer = function()
		return false
	end,
}

local userInputService = {
	InputBegan = newSignal("InputBegan"),
	InputChanged = newSignal("InputChanged"),
	InputEnded = newSignal("InputEnded"),
	MouseIconEnabled = true,
	KeyboardEnabled = true,
	TouchEnabled = false,
	GamepadEnabled = false,
	GetFocusedTextBox = function()
		return nil
	end,
}

local contextActionService = {
	BindAction = function(_, name)
		STUB.boundActions[name] = true
	end,
	UnbindAction = function(_, name)
		STUB.boundActions[name] = nil
	end,
	BindActionAtPriority = function(_, name)
		STUB.boundActions[name] = true
	end,
}

local services = {
	Players = players,
	HttpService = httpService,
	TweenService = tweenService,
	RunService = runService,
	UserInputService = userInputService,
	ContextActionService = contextActionService,
	SoundService = newInstance("SoundService"),
	CoreGui = newInstance("CoreGui"),
	StarterGui = newInstance("StarterGui"),
	ReplicatedStorage = newInstance("ReplicatedStorage"),
	Lighting = newInstance("Lighting"),
	Workspace = workspaceInstance,
}

workspace = workspaceInstance

game = {
	GetService = function(_, name)
		if not services[name] then
			services[name] = newInstance(name)
		end
		return services[name]
	end,
	FindService = function(_, name)
		return services[name]
	end,
	Workspace = workspaceInstance,
	Players = players,
	HttpService = httpService,
	IsLoaded = function()
		return true
	end,
	Destroy = function() end,
}

-- Harness helpers -------------------------------------------------------------

--- Runs every task queued by task.spawn / task.defer.
function __drain(limit)
	local budget = limit or 2000
	local ran = 0

	while #STUB.queue > 0 and ran < budget do
		local fn = table.remove(STUB.queue, 1)
		ran = ran + 1
		local ok, err = pcall(fn)
		if not ok then
			table.insert(STUB.taskErrors, tostring(err))
		end
	end

	return ran
end
