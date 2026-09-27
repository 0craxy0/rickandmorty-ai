--[[
	core/Util.lua
	Shared helpers: instance construction, tweening, executor environment
	lookups and small text utilities.
	Spec: idea/main.md (layout), idea/backend.md (executor environment).
]]

local TweenService = game:GetService("TweenService")

local Util = {}

-- Environment -----------------------------------------------------------------

--- Returns the executor's global environment when available, else _G.
function Util.environment()
	local env

	if type(getgenv) == "function" then
		local ok, result = pcall(getgenv)
		if ok and type(result) == "table" then
			env = result
		end
	end

	return env or _G or {}
end

--- Safe lookup for executor-exclusive globals (writefile, request, ...).
function Util.global(name)
	local direct = _G[name]
	if direct ~= nil then
		return direct
	end

	return Util.environment()[name]
end

--- Wraps a privileged global so callers never have to pcall by hand.
function Util.call(name, ...)
	local fn = Util.global(name)
	if type(fn) ~= "function" then
		return false, nil
	end

	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		return false, results[2]
	end

	return true, table.unpack(results, 2, results.n)
end

--- True when the script is running inside an exploit/executor sandbox.
function Util.isExecutor()
	return type(Util.global("writefile")) == "function"
		or type(Util.global("request")) == "function"
		or type(Util.global("getcustomasset")) == "function"
end

-- Instances -------------------------------------------------------------------

--- Instance.new with declarative props + children. `Parent` is applied last so
--- children never briefly reparent to the DataModel.
function Util.create(className, props, children)
	local instance = Instance.new(className)

	if props then
		for key, value in pairs(props) do
			if key ~= "Parent" then
				instance[key] = value
			end
		end
	end

	if children then
		for _, child in ipairs(children) do
			if child then
				child.Parent = instance
			end
		end
	end

	if props and props.Parent then
		instance.Parent = props.Parent
	end

	return instance
end

--- textlabel/textbutton/textbox with font + colour applied in one call.
function Util.text(className, props, children)
	return Util.create(className, props, children)
end

function Util.clear(instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

function Util.find(parent, name)
	return parent and parent:FindFirstChild(name) or nil
end

--- PlayerGui for the local player, which is where every ScreenGui lives.
function Util.guiParent()
	local player = game:GetService("Players").LocalPlayer
	if not player then
		return nil
	end

	return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
end

-- Decorators ------------------------------------------------------------------

function Util.corner(radius)
	return Util.create("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function Util.stroke(color, thickness, transparency)
	return Util.create("UIStroke", {
		Color = color or Color3.fromRGB(48, 54, 61),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Util.padding(all, right, bottom, left)
	local uniform = all or 8
	return Util.create("UIPadding", {
		PaddingTop = UDim.new(0, uniform),
		PaddingRight = UDim.new(0, right or uniform),
		PaddingBottom = UDim.new(0, bottom or uniform),
		PaddingLeft = UDim.new(0, left or uniform),
	})
end

function Util.list(props)
	return Util.create("UIListLayout", props or {})
end

function Util.grid(props)
	return Util.create("UIGridLayout", props or {})
end

function Util.aspect(ratio)
	return Util.create("UIAspectRatioConstraint", {
		AspectRatio = ratio or 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
	})
end

function Util.gradient(colorSequence, rotation)
	return Util.create("UIGradient", {
		Color = colorSequence,
		Rotation = rotation or 90,
	})
end

-- Motion ----------------------------------------------------------------------

function Util.tween(instance, props, duration, style, direction)
	local info = TweenInfo.new(
		duration or 0.15,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	return TweenService:Create(instance, info, props)
end

function Util.animate(instance, props, duration, style, direction)
	local tween = Util.tween(instance, props, duration, style, direction)
	tween:Play()
	return tween
end

function Util.connect(signal, callback)
	return signal:Connect(callback)
end

--- Groups connections so a panel can tear them all down at once.
function Util.connections()
	local group = {}

	function group.add(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(group, connection)
		return connection
	end

	function group.destroy()
		for _, connection in ipairs(group) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(group)
	end

	return group
end

-- Text ------------------------------------------------------------------------

function Util.hex(value)
	local text = tostring(value):gsub("#", "")
	if #text ~= 6 then
		return Color3.fromRGB(255, 255, 255)
	end

	return Color3.fromRGB(
		tonumber(text:sub(1, 2), 16) or 0,
		tonumber(text:sub(3, 4), 16) or 0,
		tonumber(text:sub(5, 6), 16) or 0
	)
end

function Util.trim(text)
	return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.startsWith(text, prefix)
	return text:sub(1, #prefix) == prefix
end

function Util.clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

--- Wraps a function so it cannot fire more than once per `delay` seconds.
function Util.debounce(delay, callback)
	local last = 0

	return function(...)
		local now = os.clock()
		if now - last < (delay or 0.2) then
			return nil
		end

		last = now
		return callback(...)
	end
end

function Util.timestamp()
	return os.date("%H:%M:%S")
end

--- Truncates on a word boundary where possible.
function Util.truncate(text, limit)
	if #text <= limit then
		return text
	end

	local cut = text:sub(1, limit)
	local space = cut:match("^(.+)%s")
	return (space or cut) .. "..."
end

return Util
