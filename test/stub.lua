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
	prints = {},
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

--[[
	The executor's loader. Roblox exposes `loadstring` only with elevated identity,
	so the app treats it as optional - but without it every run path in the test
	returned "loadstring is unavailable in this environment" and the one feature
	the app exists for was never executed. Fengari's `load` has the same shape:
	source in, function (or nil + message) out.
]]
function loadstring(source, chunkName)
	local name = chunkName and ("=" .. tostring(chunkName)) or "=(loadstring)"
	return load(tostring(source), name, "t")
end

--[[
	Captured rather than printed: a script that actually runs prints, and that
	output belongs in the assertions instead of in the middle of the test log.
]]
function print(...)
	local parts = {}
	for _, value in ipairs({ ... }) do
		table.insert(parts, tostring(value))
	end
	table.insert(STUB.prints, table.concat(parts, " "))
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
	Shape Material Anchored CanCollide CastShadow Massless Reflectance Orientation
	CFrame Velocity BrickColor TopSurface BottomSurface
]])

--[[
	Roblox members are per-class, and this stub used to answer every read from the
	flat superset above: `child.AbsoluteSize` on a UIListLayout returned a
	plausible 100x20 instead of the error a real client raises. Measurement code
	that walked the wrong object therefore passed here and crashed in game
	("AbsoluteSize is not a valid member of UIListLayout"). The decoration and
	layout objects a panel can contain are enumerated instead, so a read outside
	the class fails the way Roblox fails. Classes that are not listed keep the
	permissive behaviour, which is what the dynamic parts of the API need.
]]
local CLASS_MEMBERS = {
	UIListLayout = propertySet("AbsoluteContentSize FillDirection HorizontalAlignment Padding SortOrder VerticalAlignment Wraps ItemLineAlignment"),
	UIPadding = propertySet("PaddingTop PaddingRight PaddingBottom PaddingLeft"),
	UICorner = propertySet("CornerRadius"),
	UIStroke = propertySet("ApplyStrokeMode Color Enabled LineJoinMode Thickness Transparency"),
	UISizeConstraint = propertySet("MaxSize MinSize"),
	UIAspectRatioConstraint = propertySet("AspectRatio AspectType DominantAxis"),
	UIScale = propertySet("Scale"),
	UIGridLayout = propertySet("AbsoluteCellCount AbsoluteCellSize AbsoluteContentSize CellPadding CellSize FillDirection FillDirectionMaxCells HorizontalAlignment SortOrder StartCorner VerticalAlignment"),
	UIGradient = propertySet("Color Offset Rotation Transparency"),

	-- The rest of the classes the bundle constructs or reads. The lists are the
	-- bundle's real members plus the well-known public properties of the class, so
	-- a typo (`sound.Volum`) reads an error instead of nil. Classes that are not
	-- listed stay permissive on purpose: the executor runs scripts that create
	-- whatever they like, and this stub only knows the app's own furniture.
	Sound = propertySet("SoundId Volume PlaybackSpeed Looped Playing TimePosition SoundGroup RollOffMode RespectFilteringEnabled"),
	ModuleScript = propertySet("Source"),
	Folder = propertySet(""),
	ScreenGui = propertySet("AbsolutePosition AbsoluteRotation AbsoluteSize Enabled DisplayOrder IgnoreGuiInset IgnoresTitleBarReservation ResetOnSpawn ZIndexBehavior OnTopOfCoreBlur ClipToDeviceSafeArea SafeAreaCompatibility ScreenInsets"),
	Player = propertySet("DisplayName UserId PlayerGui Character"),
	PlayerGui = propertySet("CurrentScreenOrientation ScreenOrientation"),
	Workspace = propertySet("CurrentCamera DistributedGameTime FallenPartsDestroyHeight Gravity StreamingEnabled Terrain"),
	-- What a script the executor runs is most likely to build. Other BasePart
	-- subclasses stay permissive. Part-only members (Shape) sit alongside the
	-- BasePart ones (Material, Anchored, ...) because the class name is the exact
	-- class here, not the hierarchy.
	Part = propertySet("Anchored CanCollide CastShadow Color Material Orientation Position Rotation Shape Size Transparency"),
	SoundService = propertySet("AmbientReverb DistanceFactor DopplerScale ListenerType RespectFilteringEnabled"),
}

--- Members every Instance answers to.
local INSTANCE_MEMBERS = propertySet("Name Parent Archivable ClassName")

--- Classes the bundle builds and expects to behave like GuiObjects. Declared
--- here, above the instance proxy, because both the proxy and the layout pass
--- consult it and a `local` below its first use would read nil.
local GUI_CLASSES = propertySet([[
	Frame TextLabel TextButton TextBox ImageLabel ImageButton ScrollingFrame
	ViewportFrame CanvasGroup
]])

local TEXT_CLASSES = propertySet("TextLabel TextButton TextBox")

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
	-- Read by the layout pass, so their real Roblox defaults belong here too.
	CanvasSize = { X = { Scale = 0, Offset = 0 }, Y = { Scale = 0, Offset = 0 } },
	ClipsDescendants = false,
	RichText = false,
	Font = "Enum.Font.SourceSans",
	TextWrapped = false,
	TextXAlignment = "Enum.TextXAlignment.Center",
	TextYAlignment = "Enum.TextYAlignment.Center",
	Padding = { Scale = 0, Offset = 0 },
	-- UISizeConstraint defaults: no minimum, unbounded maximum.
	MinSize = { X = 0, Y = 0 },
	MaxSize = { X = math.huge, Y = math.huge },
	PaddingTop = { Scale = 0, Offset = 0 },
	PaddingRight = { Scale = 0, Offset = 0 },
	PaddingBottom = { Scale = 0, Offset = 0 },
	PaddingLeft = { Scale = 0, Offset = 0 },
	-- Roblox's UIListLayout stacks children top to bottom unless told otherwise.
	FillDirection = "Enum.FillDirection.Vertical",
	HorizontalAlignment = "Enum.HorizontalAlignment.Left",
	VerticalAlignment = "Enum.VerticalAlignment.Top",
	SortOrder = "Enum.SortOrder.Name",
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

-- Absolute geometry resolved by STUB.layout (see the layout section below).
local ABSOLUTE = setmetatable({}, { __mode = "k" })

-- Roblox computes these; a script may only read them. The stub computes them
-- too, so assigning one is exactly as invalid here as it is in the engine.
local READONLY = propertySet("AbsolutePosition AbsoluteSize AbsoluteContentSize")

local ABSOLUTE_KEYS = {
	AbsolutePosition = "position",
	AbsoluteSize = "size",
	AbsoluteContentSize = "content",
	AbsoluteCanvasSize = "canvas",
}

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
		if className == class or className == "Instance" then
			return true
		end

		-- Only the hierarchy the bundle actually asks about is modelled.
		if className == "GuiObject" then
			return GUI_CLASSES[class] == true
		end
		if className == "UIComponent" or className == "UIBase" then
			return CLASS_MEMBERS[class] ~= nil
		end

		return false
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

			local members = CLASS_MEMBERS[class]
			if members and not members[key] and not INSTANCE_MEMBERS[key] then
				-- Exactly what Roblox raises for this mistake.
				local message = string.format("%s is not a valid member of %s", tostring(key), class)
				table.insert(
					STUB.violations,
					string.format('%s "%s"  (read by the bundle)', message, data.Name)
				)
				error(message, 2)
			end

			local absoluteField = ABSOLUTE_KEYS[key]
			if absoluteField then
				local absolute = ABSOLUTE[proxy]
				local resolved = absolute and absolute[absoluteField]
				if resolved then
					return resolved
				end
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

			if READONLY[key] then
				-- Exactly what Roblox raises for this mistake.
				local message = string.format("Unable to assign property %s. Property is read-only", tostring(key))
				table.insert(
					STUB.violations,
					string.format('%s "%s"  (assigned by the bundle)', message, data.Name)
				)
				error(message, 2)
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

	-- A ScreenGui knows the viewport as soon as it exists, before any layout has
	-- run, so the bundle can size itself against gui.AbsoluteSize at construction.
	if class == "ScreenGui" then
		local viewport = STUB.VIEWPORT or { X = 1920, Y = 1080 }
		ABSOLUTE[proxy] = {
			position = { X = 0, Y = 0 },
			size = {
				X = type(viewport.X) == "number" and viewport.X or 1920,
				Y = type(viewport.Y) == "number" and viewport.Y or 1080,
			},
		}
	end

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

--[[
	Services are plain tables in this stub, which means a misspelled member used to
	read nil and quietly take the "this environment cannot do that" branch instead
	of failing. Wrapping them makes a typo as loud as it is on an Instance.
]]
local function service(name, members)
	local function reject(key, verb)
		local message = string.format("%s is not a valid member of %s", tostring(key), name)
		table.insert(STUB.violations, string.format("%s  (%s by the bundle)", message, verb))
		error(message, 2)
	end

	setmetatable(members, {
		__index = function(_, key)
			reject(key, "read")
		end,
		__newindex = function(_, key)
			reject(key, "assigned")
		end,
	})

	return members
end

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

local tweenService = {}

--- Tweens apply immediately so assertions see the settled state, then complete on
--- the next drain. Completion is queued rather than fired inside Play() because
--- real code connects to Completed *after* calling Play() - a dismiss that
--- destroys its toast once the fade finishes has to be reachable here too.
function tweenService:Create(instance, _, props)
	local tween = { Completed = newSignal("Completed") }

	function tween:Play()
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

		enqueue(function()
			tween.Completed:Fire()
		end)
	end

	function tween:Cancel() end
	function tween:Pause() end

	return tween
end

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

-- Wrapped only now that every member exists: `function tweenService:Create()`
-- assigns a new key, which the guard would reject. setmetatable mutates the table
-- in place, so every reference - including `game.TweenService` - sees the guard.
service("Players", players)
service("HttpService", httpService)
service("TweenService", tweenService)
service("RunService", runService)
service("UserInputService", userInputService)
service("ContextActionService", contextActionService)

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
			-- Roblox refuses a service that does not exist. Auto-creating one turned a
			-- typo'd name (`game:GetService("HttpServce")`) into a permissive object
			-- whose every read was nil, which is exactly the silence to avoid.
			local message = string.format("%s is not a valid service name", tostring(name))
			table.insert(STUB.violations, message .. "  (read by the bundle)")
			error(message, 2)
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

--[[ Layout simulation ---------------------------------------------------------

	Roblox resolves UDim2 sizes, UIListLayout ordering and AutomaticSize content
	itself. This stub runs a simplified pass over the mounted GuiObjects so the
	smoke test can assert real geometry: nothing collapsed to zero, nothing
	spilling out of an unclipped parent, and text that should be on screen
	actually being on screen.

	It is an approximation, not a renderer:
	  * text is measured from an average glyph width per font family
	  * UIPadding scale (as opposed to offset) is ignored
	  * UIGridLayout is not simulated - a grid container falls back to a bounding
	    box around its children
	  * the viewport is fixed at STUB.VIEWPORT (no resize, no scrolling)
	  * TextScaled, TextTruncate and text stroke are not modelled

	Usage: __relayout(instance) from test/assert.lua, then read AbsolutePosition /
	AbsoluteSize / AbsoluteCanvasSize as usual.
]]

--- Average glyph width as a fraction of TextSize, per Roblox font family.
local FONT_WIDTH = {
	Gotham = 0.55,
	GothamMedium = 0.56,
	GothamBold = 0.58,
	GothamBlack = 0.63,
	RobotoMono = 0.6,
	Code = 0.6,
	LuckiestGuy = 0.52,
	Bangers = 0.5,
	Creepster = 0.55,
	SourceSans = 0.54,
	SourceSansBold = 0.58,
	SourceSansSemibold = 0.56,
	SourceSansLight = 0.52,
	Arial = 0.55,
	ArialBold = 0.58,
	Merriweather = 0.56,
	Nunito = 0.55,
	Oswald = 0.5,
	Sarpanch = 0.55,
	Jura = 0.55,
	JosefinSans = 0.5,
	Kalam = 0.5,
	PatrickHand = 0.5,
	IndieFlower = 0.5,
	FredokaOne = 0.55,
	Fantasy = 0.55,
	Antique = 0.6,
	SciFi = 0.55,
	Cartoon = 0.55,
	Highway = 0.55,
	Legacy = 0.55,
	Bodoni = 0.55,
	Garamond = 0.5,
}

-- Glyphs that are narrower/wider than the family average, so that a "Hide"
-- button and a "MMMM" one do not measure the same width.
local NARROW = ".,'\"!|[](){}:;iltjfr"
local WIDE = "mwMW@?"

STUB.VIEWPORT = { X = 1920, Y = 1080 }
STUB.layoutPasses = 0
STUB.laidOut = 0

local CACHE = {}

local measure
local contentExtent
local arrange

local function classNameOf(instance)
	local data = REGISTRY[instance]
	return data and data.ClassName or nil
end

function STUB.classOf(instance)
	return classNameOf(instance)
end

local function isGuiObject(instance)
	local class = classNameOf(instance)
	return class ~= nil and GUI_CLASSES[class] == true
end

function STUB.isGuiObject(instance)
	return isGuiObject(instance)
end

local function childOfClass(instance, className)
	for _, child in ipairs(REGISTRY[instance].children) do
		if REGISTRY[child].ClassName == className then
			return child
		end
	end
	return nil
end

local function guiChildren(instance)
	local out = {}
	for _, child in ipairs(REGISTRY[instance].children) do
		if isGuiObject(child) then
			table.insert(out, child)
		end
	end
	return out
end

function STUB.guiChildren(instance)
	return guiChildren(instance)
end

--- Full dotted path, for failure messages: "RickMortyAI.Window.Header.Actions".
function STUB.path(instance)
	local parts = {}
	local current = instance

	while current and REGISTRY[current] do
		table.insert(parts, 1, tostring(REGISTRY[current].Name))
		current = REGISTRY[current].Parent
	end

	return table.concat(parts, ".")
end

--- Visible through the whole ancestor chain, the way Roblox draws it.
function STUB.isVisible(instance)
	local current = instance

	while current do
		local data = REGISTRY[current]
		-- Only GuiObjects have Visible; a layout or decoration object cannot hide
		-- anything, so it is skipped rather than read.
		if data and GUI_CLASSES[data.ClassName] and current.Visible ~= true then
			return false
		end
		current = data and data.Parent or nil
	end

	return true
end

--- Resolved rectangle from the last STUB.layout pass, or nil before one.
function STUB.absSize(instance)
	local absolute = ABSOLUTE[instance]
	return absolute and absolute.size or nil
end

function STUB.absPos(instance)
	local absolute = ABSOLUTE[instance]
	return absolute and absolute.position or nil
end

-- Geometry maths ---------------------------------------------------------------

local function number(value, fallback)
	if type(value) == "number" then
		return value
	end
	return fallback or 0
end

local function udimValue(udim, reference)
	if type(udim) ~= "table" then
		return 0
	end
	return number(udim.Scale, 0) * number(reference, 0) + number(udim.Offset, 0)
end

local function resolveSize(udim2, reference)
	if type(udim2) ~= "table" then
		return { X = 0, Y = 0 }
	end
	return {
		X = udimValue(udim2.X, reference.X),
		Y = udimValue(udim2.Y, reference.Y),
	}
end

local function paddingOf(instance, size)
	local pad = childOfClass(instance, "UIPadding")
	if not pad then
		return { top = 0, right = 0, bottom = 0, left = 0 }
	end

	return {
		top = udimValue(pad.PaddingTop, size.Y),
		right = udimValue(pad.PaddingRight, size.X),
		bottom = udimValue(pad.PaddingBottom, size.Y),
		left = udimValue(pad.PaddingLeft, size.X),
	}
end

-- Text metrics -----------------------------------------------------------------

local function fontFactor(font)
	local name = tostring(font or ""):match("([%w]+)$") or ""
	return FONT_WIDTH[name] or 0.55
end

local function lineWidth(text, fontSize, factor)
	local units = 0

	for index = 1, #text do
		local char = text:sub(index, index)
		if char == " " then
			units = units + 0.35
		elseif string.find(NARROW, char, 1, true) then
			units = units + 0.45
		elseif string.find(WIDE, char, 1, true) then
			units = units + 1.25
		elseif char:match("%u") or char:match("%d") then
			units = units + 1.08
		else
			units = units + 1
		end
	end

	return units * fontSize * factor
end

--- Returns (width, height) of the text, wrapped into `wrapWidth` when set.
local function textExtent(instance, wrapWidth)
	local text = instance.Text
	if type(text) ~= "string" then
		text = ""
	end
	if instance.RichText then
		text = text:gsub("<[^>]*>", "")
	end

	local fontSize = number(instance.TextSize, 14)
	local factor = fontFactor(instance.Font)
	local available = number(wrapWidth, 0)
	local wrapped = instance.TextWrapped == true and available > 1

	local width, lines = 0, 0

	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local measured = lineWidth(line, fontSize, factor)
		if wrapped and measured > available then
			lines = lines + math.ceil(measured / available)
			width = math.max(width, available)
		else
			lines = lines + 1
			width = math.max(width, measured)
		end
	end

	if lines == 0 then
		lines = 1
	end

	return width, lines * math.ceil(fontSize * 1.2)
end

-- Content sizing ---------------------------------------------------------------

--- Children in the order a UIListLayout stacks them.
local function orderedChildren(instance, layout)
	local entries = {}

	for index, child in ipairs(guiChildren(instance)) do
		table.insert(entries, { order = index, child = child })
	end

	if layout.SortOrder == "Enum.SortOrder.LayoutOrder" then
		table.sort(entries, function(a, b)
			local left = number(REGISTRY[a.child].LayoutOrder, 0)
			local right = number(REGISTRY[b.child].LayoutOrder, 0)
			if left == right then
				return a.order < b.order
			end
			return left < right
		end)
	else
		table.sort(entries, function(a, b)
			local left = tostring(REGISTRY[a.child].Name)
			local right = tostring(REGISTRY[b.child].Name)
			if left == right then
				return a.order < b.order
			end
			return left < right
		end)
	end

	local out = {}
	for _, entry in ipairs(entries) do
		table.insert(out, entry.child)
	end
	return out
end

--[[
	Slots every child of a UIListLayout along the fill direction and returns
	`{ horizontal, extent, slots }`. `extent` excludes the container's padding;
	each slot carries its offset from the container's top-left corner.
]]
arrange = function(instance, layout, size, pad)
	local horizontal = layout.FillDirection ~= "Enum.FillDirection.Vertical"
	local gap = udimValue(layout.Padding, horizontal and size.X or size.Y)
	local children = orderedChildren(instance, layout)

	-- Children resolve their scale sizes against the padded content box.
	local inner = {
		X = math.max(0, size.X - pad.left - pad.right),
		Y = math.max(0, size.Y - pad.top - pad.bottom),
	}

	local slots = {}
	local run = 0
	local crossMax = 0

	for index, child in ipairs(children) do
		local childSize = measure(child, inner)
		local mainSize = horizontal and childSize.X or childSize.Y
		local crossSize = horizontal and childSize.Y or childSize.X

		slots[child] = { main = run, cross = 0, size = childSize, crossSize = crossSize }
		run = run + mainSize
		if index < #children then
			run = run + gap
		end
		crossMax = math.max(crossMax, crossSize)
	end

	local innerMain
	local innerCross
	local mainStart
	local crossStart

	if horizontal then
		innerMain, innerCross = inner.X, inner.Y
		mainStart, crossStart = pad.left, pad.top
	else
		innerMain, innerCross = inner.Y, inner.X
		mainStart, crossStart = pad.top, pad.left
	end

	local mainAlign = horizontal and layout.HorizontalAlignment or layout.VerticalAlignment
	if mainAlign == "Enum.HorizontalAlignment.Center" or mainAlign == "Enum.VerticalAlignment.Center" then
		mainStart = mainStart + math.max(0, (innerMain - run) / 2)
	elseif mainAlign == "Enum.HorizontalAlignment.Right" or mainAlign == "Enum.VerticalAlignment.Bottom" then
		mainStart = mainStart + math.max(0, innerMain - run)
	end

	local crossAlign = horizontal and layout.VerticalAlignment or layout.HorizontalAlignment

	for _, slot in pairs(slots) do
		slot.main = slot.main + mainStart

		if crossAlign == "Enum.VerticalAlignment.Center" or crossAlign == "Enum.HorizontalAlignment.Center" then
			slot.cross = crossStart + math.max(0, (innerCross - slot.crossSize) / 2)
		elseif crossAlign == "Enum.VerticalAlignment.Bottom" or crossAlign == "Enum.HorizontalAlignment.Right" then
			slot.cross = crossStart + math.max(0, innerCross - slot.crossSize)
		else
			slot.cross = crossStart
		end
	end

	return {
		horizontal = horizontal,
		extent = horizontal and { X = run, Y = crossMax } or { X = crossMax, Y = run },
		slots = slots,
	}
end

--- Bounding box of children laid out by their own Position (no list layout).
--- `reference` is the padded content box children resolve against.
local function boundsExtent(children, reference)
	local width, height = 0, 0

	for _, child in ipairs(children) do
		local childSize = measure(child, reference)
		local declared = child.Position
		local anchor = child.AnchorPoint
		local position = {
			X = udimValue(declared.X, reference.X) - number(anchor.X, 0) * childSize.X,
			Y = udimValue(declared.Y, reference.Y) - number(anchor.Y, 0) * childSize.Y,
		}

		width = math.max(width, math.max(0, position.X + childSize.X))
		height = math.max(height, math.max(0, position.Y + childSize.Y))
	end

	return { X = width, Y = height }
end

contentExtent = function(instance, size)
	local pad = paddingOf(instance, size)
	local inner = {
		X = math.max(0, size.X - pad.left - pad.right),
		Y = math.max(0, size.Y - pad.top - pad.bottom),
	}
	local children = guiChildren(instance)
	local layout = childOfClass(instance, "UIListLayout")
	local width, height = 0, 0

	if #children > 0 then
		if layout then
			local arranged = arrange(instance, layout, size, pad)
			width, height = arranged.extent.X, arranged.extent.Y
		else
			local bounds = boundsExtent(children, inner)
			width, height = bounds.X, bounds.Y
		end
	end

	if TEXT_CLASSES[classNameOf(instance)] then
		local textWidth, textHeight = textExtent(instance, inner.X)
		width = math.max(width, textWidth)
		height = math.max(height, textHeight)
	end

	return {
		X = width + pad.left + pad.right,
		Y = height + pad.top + pad.bottom,
	}
end

-- Sizing -----------------------------------------------------------------------

local function applyAspect(size, aspect)
	local ratio = number(aspect.AspectRatio, 1)
	if ratio <= 0 then
		return size
	end

	local resolved
	if aspect.DominantAxis == "Enum.DominantAxis.Height" then
		resolved = { X = size.Y * ratio, Y = size.Y }
	else
		resolved = { X = size.X, Y = size.X / ratio }
	end

	-- AspectType.FitWithinMaxSize never exceeds the declared box.
	if size.X > 0 and resolved.X > size.X then
		local scale = size.X / resolved.X
		resolved.X = size.X
		resolved.Y = resolved.Y * scale
	end
	if size.Y > 0 and resolved.Y > size.Y then
		local scale = size.Y / resolved.Y
		resolved.Y = size.Y
		resolved.X = resolved.X * scale
	end

	return resolved
end

measure = function(instance, reference)
	local key = string.format("%.3f:%.3f", reference.X, reference.Y)
	local cache = CACHE[instance]
	if cache and cache[key] then
		return cache[key]
	end

	local size = resolveSize(instance.Size, reference)
	local automatic = instance.AutomaticSize

	if automatic == "Enum.AutomaticSize.X" or automatic == "Enum.AutomaticSize.XY"
		or automatic == "Enum.AutomaticSize.Y" then
		local content = contentExtent(instance, size)
		if automatic ~= "Enum.AutomaticSize.Y" then
			size.X = content.X
		end
		if automatic ~= "Enum.AutomaticSize.X" then
			size.Y = content.Y
		end
	end

	local constraint = childOfClass(instance, "UISizeConstraint")
	if constraint then
		local minimum = constraint.MinSize
		local maximum = constraint.MaxSize
		if type(minimum) == "table" then
			size.X = math.max(minimum.X, size.X)
			size.Y = math.max(minimum.Y, size.Y)
		end
		if type(maximum) == "table" then
			size.X = math.min(maximum.X, size.X)
			size.Y = math.min(maximum.Y, size.Y)
		end
	end

	local aspect = childOfClass(instance, "UIAspectRatioConstraint")
	if aspect then
		size = applyAspect(size, aspect)
	end

	cache = cache or {}
	cache[key] = size
	CACHE[instance] = cache

	return size
end

-- Placement --------------------------------------------------------------------

local function place(instance, origin, reference, forced)
	local size = forced and forced.size or measure(instance, reference)
	local position

	if forced then
		position = forced.position
	else
		local declared = instance.Position
		local anchor = instance.AnchorPoint
		position = {
			X = origin.X + udimValue(declared.X, reference.X) - number(anchor.X, 0) * size.X,
			Y = origin.Y + udimValue(declared.Y, reference.Y) - number(anchor.Y, 0) * size.Y,
		}
	end

	ABSOLUTE[instance] = { position = position, size = size }
	STUB.laidOut = STUB.laidOut + 1

	if classNameOf(instance) == "ScrollingFrame" then
		local declared = instance.CanvasSize
		local content = contentExtent(instance, size)
		ABSOLUTE[instance].canvas = {
			X = math.max(content.X, udimValue(declared.X, size.X)),
			Y = math.max(content.Y, udimValue(declared.Y, size.Y)),
		}
	end

	local children = guiChildren(instance)
	if #children == 0 then
		return
	end

	-- Children live in the padded content box: their Position and scale Size are
	-- resolved against it, offset from the parent's corner by the padding.
	local pad = paddingOf(instance, size)
	local inner = {
		X = math.max(0, size.X - pad.left - pad.right),
		Y = math.max(0, size.Y - pad.top - pad.bottom),
	}
	local innerOrigin = { X = position.X + pad.left, Y = position.Y + pad.top }

	local layout = childOfClass(instance, "UIListLayout")
	if not layout then
		for _, child in ipairs(children) do
			place(child, innerOrigin, inner)
		end
		return
	end

	local arranged = arrange(instance, layout, size, paddingOf(instance, size))
	for _, child in ipairs(children) do
		local slot = arranged.slots[child]
		if slot then
			place(child, nil, size, {
				size = slot.size,
				position = {
					X = position.X + (arranged.horizontal and slot.main or slot.cross),
					Y = position.Y + (arranged.horizontal and slot.cross or slot.main),
				},
			})
		end
	end
end

--- Sizes from the previous pass, so a resize can be distinguished from a
--- plain relayout (the engine only fires changed:AbsoluteSize on a real change).
local function snapshotSizes()
	local sizes = {}

	for instance, absolute in pairs(ABSOLUTE) do
		sizes[instance] = { X = absolute.size.X, Y = absolute.size.Y }
	end

	return sizes
end

--- Fires changed:AbsoluteSize for the instances whose size actually moved.
--- Anything sizing itself off AbsoluteSize (the toast accent rail, the window's
--- shrink floor) settles on the pass that follows.
local function signalResized(root, sizes)
	local function walk(instance)
		local absolute = ABSOLUTE[instance]
		local previous = sizes[instance]

		if absolute and (not previous or previous.X ~= absolute.size.X or previous.Y ~= absolute.size.Y) then
			local signal = REGISTRY[instance].signals["changed:AbsoluteSize"]
			if signal then
				signal:Fire()
			end
		end

		for _, child in ipairs(REGISTRY[instance].children) do
			walk(child)
		end
	end

	walk(root)
end

--- Resolves geometry for `root` (a ScreenGui) and everything under it.
--- Returns the number of rects computed.
function STUB.layout(root)
	local viewport = {
		X = number(STUB.VIEWPORT.X, 1920),
		Y = number(STUB.VIEWPORT.Y, 1080),
	}
	local entry = { size = viewport, position = { X = 0, Y = 0 } }

	local sizes = snapshotSizes()

	CACHE = {}
	STUB.laidOut = 0
	place(root, entry.position, viewport, entry)

	signalResized(root, sizes)

	CACHE = {}
	STUB.laidOut = 0
	place(root, entry.position, viewport, entry)

	STUB.layoutPasses = STUB.layoutPasses + 1
	return STUB.laidOut
end

-- Harness helpers -------------------------------------------------------------

--- Resolves AbsolutePosition / AbsoluteSize for a mounted ScreenGui.
function __relayout(root)
	return STUB.layout(root)
end

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
