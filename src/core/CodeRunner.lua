--[[
	core/CodeRunner.lua
	Code extraction + execution from idea/backend.md §4.

	The hot path is:
	  1. isolate the raw ```lua block out of the model's prose
	  2. publish it into a script container inside Workspace
	  3. run it against the executor's global environment
]]

local Util = require("core/Util")

local CodeRunner = {}

CodeRunner.CONTAINER_NAME = "RickMortyAI_Scripts"

--- Every fenced block in the message, as { language, code }.
function CodeRunner.extractBlocks(text)
	local blocks = {}

	for language, body in string.gmatch(tostring(text or ""), "```([%w_%+%-]*)\r?\n(.-)```") do
		table.insert(blocks, {
			language = language == "" and "lua" or language,
			code = body,
		})
	end

	return blocks
end

--- Code that should actually be executed: prefer lua/luau blocks.
function CodeRunner.extractCode(text)
	local blocks = CodeRunner.extractBlocks(text)
	local preferred = {}

	for _, block in ipairs(blocks) do
		local language = string.lower(block.language)
		if language == "lua" or language == "luau" or language == "" then
			table.insert(preferred, block.code)
		end
	end

	if #preferred > 0 then
		return table.concat(preferred, "\n\n"), #preferred
	end

	if #blocks > 0 then
		local all = {}
		for _, block in ipairs(blocks) do
			table.insert(all, block.code)
		end
		return table.concat(all, "\n\n"), #blocks
	end

	return nil, 0
end

--- Removes every fence so the Code pane shows clean Luau.
function CodeRunner.stripFences(text)
	local stripped = tostring(text or ""):gsub("```[%w_%+%-]*\r?\n", ""):gsub("```", "")
	return Util.trim(stripped)
end

--- True when the text looks executable rather than conversational.
function CodeRunner.looksLikeCode(text)
	local source = tostring(text or "")
	if source:find("```") then
		return true
	end

	local signatures = {
		"local ",
		"function ",
		"game:GetService",
		"game%.GetService",
		"Instance%.new",
		"task%.wait",
		"print%(",
		"end",
	}

	local hits = 0
	for _, pattern in ipairs(signatures) do
		if source:find(pattern) then
			hits += 1
		end
	end

	return hits >= 2
end

--- Writes the generated source into Workspace as a script container (spec §4).
function CodeRunner.publish(source, name)
	local container = Util.find(workspace, CodeRunner.CONTAINER_NAME)
	if not container then
		container = Util.create("Folder", {
			Name = CodeRunner.CONTAINER_NAME,
			Parent = workspace,
		})
	end

	local holder = Instance.new("ModuleScript")
	holder.Name = name or ("generated_" .. tostring(os.time()))

	local ok = pcall(function()
		holder.Source = source
	end)

	if not ok then
		-- Some executors lock Source outside of elevated identity.
		holder:SetAttribute("Source", source)
	end

	holder.Parent = container
	return holder
end

--- Compiles and runs source with access to the executor globals.
function CodeRunner.run(source, options)
	options = options or {}

	local loader = Util.global("loadstring") or loadstring
	if type(loader) ~= "function" then
		return false, "loadstring is unavailable in this environment."
	end

	local chunk, compileError = loader(source, options.chunkName or "RickMortyAI")
	if not chunk then
		return false, tostring(compileError)
	end

	local setfenv = Util.global("setfenv")
	if type(setfenv) == "function" then
		pcall(setfenv, chunk, Util.environment())
	end

	if options.defer then
		task.spawn(function()
			local ok, result = pcall(chunk)
			if options.onError and not ok then
				options.onError(tostring(result))
			end
		end)
		return true, nil
	end

	local ok, result = pcall(chunk)
	if not ok then
		return false, tostring(result)
	end

	return true, result
end

--- Extract -> publish -> run. Returns (ok, output).
function CodeRunner.execute(text, options)
	options = options or {}

	local source = CodeRunner.extractCode(text)
	if not source or Util.trim(source) == "" then
		return false, "No executable code block found in the response."
	end

	local published, holder = pcall(CodeRunner.publish, source, options.name)
	local ok, output = CodeRunner.run(source, options)

	if not ok then
		return false, tostring(output)
	end

	local note = published and "" or "\n(publishing to Workspace failed)"

	-- A chunk with no return value reports nil. Every call site renders an empty
	-- output as "script finished", so normalising it here is what makes that
	-- fallback reachable - `tostring(nil)` put a literal "nil" in the console.
	return true, (output == nil and "" or tostring(output)) .. note, holder
end

return CodeRunner
