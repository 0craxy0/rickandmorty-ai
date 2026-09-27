--[[
	core/Typewriter.lua
	Letter-by-letter rendering from idea/fonts.md §3 and idea/main.md §4.

	  * 0.03s hard delay between characters
	  * clicking the active dialogue frame reveals the whole block instantly
	  * RichText stays enabled so inline styling survives the reveal loop
	  * one click sound per rendered glyph — rbxassetid://9114223164,
	    volume 0.3, playback speed 1.2
]]

local SoundService = game:GetService("SoundService")

local Fonts = require("core/Fonts")
local Util = require("core/Util")

local Typewriter = {}

Typewriter.SPEED = 0.03
Typewriter.SOUND_ID = "rbxassetid://9114223164"
Typewriter.SOUND_VOLUME = 0.3
Typewriter.SOUND_PITCH = 1.2

local clickSound

local function sound()
	if clickSound and clickSound.Parent then
		return clickSound
	end

	clickSound = Util.create("Sound", {
		Name = "RickMortyTypewriterClick",
		SoundId = Typewriter.SOUND_ID,
		Volume = Typewriter.SOUND_VOLUME,
		PlaybackSpeed = Typewriter.SOUND_PITCH,
		Parent = SoundService,
	})

	return clickSound
end

--- Minimal markdown -> RichText for the dialogue panes.
function Typewriter.toRichText(markdown)
	local text = tostring(markdown or "")

	-- Escape first so stray angle brackets cannot become tags.
	text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")

	-- Fenced blocks collapsed to a single styled line.
	text = text:gsub("```[%w_%+%-]*\r?\n(.-)```", function(code)
		return '<font face="RobotoMono">' .. code:gsub("%s+$", "") .. "</font>"
	end)

	-- Inline code.
	text = text:gsub("`([^`\n]+)`", '<font face="RobotoMono">%1</font>')

	-- Bold / italic.
	text = text:gsub("%*%*([^%*\n]+)%*%*", "<b>%1</b>")
	text = text:gsub("__([^_\n]+)__", "<b>%1</b>")
	text = text:gsub("(%s)%*([^%*\n]+)%*", "%1<i>%2</i>")

	-- Headings become bold lead-ins.
	text = text:gsub("(\n#+)%s*([^\n]+)", function(marks, heading)
		return marks .. " <b>" .. heading .. "</b>"
	end)

	return text
end

--- Pulls the next renderable token: a single glyph, or a whole RichText tag.
local function nextToken(rich, index)
	local char = rich:sub(index, index)

	if char == "<" then
		local close = rich:find(">", index, true)
		if close then
			return rich:sub(index, close), close + 1, true
		end
	end

	return char, index + 1, false
end

--[[
	Renders `text` into `label` one character at a time.

	options = {
		speed      = number   -- seconds per character (default 0.03)
		sound      = boolean  -- click FX per glyph (default true)
		rich       = boolean  -- convert markdown to RichText (default true)
		onComplete = function(handle)
	}

	Returns a handle: { finished, skipped, text, skip(), await() }
]]
function Typewriter.play(label, text, options)
	options = options or {}

	local speed = options.speed or Typewriter.SPEED
	local plain = tostring(text or "")
	local rich = options.rich == false and plain or Typewriter.toRichText(plain)

	local generation = (label:GetAttribute("TypewriterGeneration") or 0) + 1
	label:SetAttribute("TypewriterGeneration", generation)
	label.RichText = true
	label.Text = ""

	local handle = {
		finished = false,
		skipped = false,
		text = plain,
		label = label,
		generation = generation,
	}

	function handle.skip()
		if not handle.finished then
			handle.skipped = true
		end
	end

	function handle.await()
		while not handle.finished do
			task.wait()
		end
	end

	local soundEnabled = options.sound ~= false
	local soundInstance = soundEnabled and sound() or nil

	task.spawn(function()
		local buffer = {}
		local index = 1
		local length = #rich

		while index <= length do
			-- A newer render on the same label wins.
			if label:GetAttribute("TypewriterGeneration") ~= generation then
				return
			end

			if handle.skipped then
				label.Text = rich
				handle.finished = true
				if options.onComplete then
					options.onComplete(handle)
				end
				return
			end

			local token, nextIndex, isTag = nextToken(rich, index)
			table.insert(buffer, token)
			index = nextIndex
			label.Text = table.concat(buffer)

			if not isTag then
				if soundInstance and token:match("%S") and soundInstance.Volume > 0 then
					soundInstance:Play()
				end

				if speed > 0 then
					task.wait(speed)
				end
			end
		end

		handle.finished = true
		if options.onComplete then
			options.onComplete(handle)
		end
	end)

	return handle
end

--- Clicking the dialogue frame instantly reveals the full block (spec §3).
function Typewriter.bindSkip(frame, handle)
	return frame.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			handle.skip()
		end
	end)
end

--- Tears down the shared click sound (called on unload).
function Typewriter.destroy()
	if clickSound then
		pcall(function()
			clickSound:Destroy()
		end)
		clickSound = nil
	end
end

--- Convenience: render into a fresh label and return both.
function Typewriter.into(parent, text, role, options)
	local label = Fonts.autoSized(role or "body", { Parent = parent })
	local handle = Typewriter.play(label, text, options)
	return label, handle
end

return Typewriter
