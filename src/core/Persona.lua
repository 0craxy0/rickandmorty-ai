--[[
	core/Persona.lua
	Persona prompt injection engine from idea/backend.md §1.

	Every fresh conversation chain gets a system-level directive prepended and
	the raw text is never shown in the visible chat log (the UI only renders
	`role == "user"` / `role == "assistant"` entries).

	`Persona.PreparePayload` is the reference implementation straight from the
	spec (system message on a fresh chain only).
	`Persona.buildMessages` is the transport variant the chat pipeline uses,
	which keeps the persona attached to every stateless HTTP call.
]]

local HttpService = game:GetService("HttpService")

local Persona = {}

Persona.prompts = {
	Rick = "Act like Rick from the famous show 'Rick and Morty' when explaining, debugging, writing or editing code. Be cynical, highly intelligent, slightly erratic, use his iconic speech patterns, and dismissive yet helpful.",
	Morty = "Act like Morty from the famous show 'Rick and Morty' when explaining, debugging, writing or editing code. Be anxious, stutter slightly, hesitant, but trying your absolute best to help out.",
}

--- Short form used by the quick menu overlay (ui-creation.md §4).
Persona.short = {
	Rick = "Act like Rick from the famous show Rick and Morty when explaining, debugging, writing or editing code.",
	Morty = "Act like Morty from the famous show Rick and Morty when explaining, debugging, writing or editing code.",
}

--- House rules that stop the model from burying code in prose.
Persona.rules = table.concat({
	"Always answer in Luau (Roblox Lua).",
	"Put every executable block in a fenced ```lua code block.",
	"Keep commentary short and in character.",
}, " ")

function Persona.prompt(choice)
	return Persona.prompts[choice] or Persona.prompts.Rick
end

function Persona.shortPrompt(choice)
	return Persona.short[choice] or Persona.short.Rick
end

function Persona.systemMessage(choice)
	return Persona.prompt(choice) .. " " .. Persona.rules
end

-- Spec implementation (idea/backend.md §1) ------------------------------------

function Persona.PreparePayload(userChoice, userPrompt, providerTemplate, chatHistory)
	local systemMessage = Persona.prompts[userChoice]
	local fullMessages = {}

	-- Inject system persona rule at the start of a fresh chain
	if #chatHistory == 0 then
		table.insert(fullMessages, { role = "system", content = systemMessage })
	end

	-- Append historical logs
	for _, msg in ipairs(chatHistory) do
		table.insert(fullMessages, msg)
	end

	-- Append the immediate active prompt
	table.insert(fullMessages, { role = "user", content = userPrompt })

	-- Merge into the structural API template
	local finalPayload = HttpService:JSONDecode(providerTemplate)
	finalPayload.messages = fullMessages

	return HttpService:JSONEncode(finalPayload)
end

-- Transport variant ----------------------------------------------------------

--- Returns { system = string, messages = { { role, content }, ... } }.
--- The system directive is guaranteed present regardless of history length.
function Persona.buildMessages(userChoice, history, userPrompt)
	local messages = {}
	local hasSystem = false

	for _, message in ipairs(history or {}) do
		if message.role == "system" then
			hasSystem = true
		end
		table.insert(messages, { role = message.role, content = message.content })
	end

	if userPrompt and userPrompt ~= "" then
		table.insert(messages, { role = "user", content = userPrompt })
	end

	return {
		system = Persona.systemMessage(userChoice),
		messages = messages,
		hasSystem = hasSystem,
	}
end

--- Strips persona/system entries before writing to the visible transcript.
function Persona.visibleHistory(history)
	local visible = {}
	for _, message in ipairs(history or {}) do
		if message.role ~= "system" then
			table.insert(visible, message)
		end
	end
	return visible
end

return Persona
