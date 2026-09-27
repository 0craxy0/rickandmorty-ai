--[[
	core/State.lua
	Runtime configuration + conversation state.

	Persisted to `rick_morty_ai_config.json` in the executor workspace via the
	privileged `writefile`/`readfile` pair, so the chosen companion, provider,
	API keys and onboarding flag survive between sessions.
	See idea/backend.md §1 (persona) and idea/ui-creation.md §2 (providers).
]]

local HttpService = game:GetService("HttpService")

local Util = require("core/Util")

local State = {}

State.CONFIG_PATH = "rick_morty_ai_config.json"
State.SCHEMA_VERSION = 1

State.data = {
	version = State.SCHEMA_VERSION,
	companion = nil, -- "Rick" | "Morty"
	provider = "OpenRouter",
	keys = {}, -- provider id -> bearer token
	models = {}, -- provider id -> model override
	urls = {}, -- provider id -> endpoint override
	onboarded = false,
	sessions = {}, -- archived conversations for the sidebar
	stats = { requests = 0, tokens = 0 },
}

--- Active conversation, always an array of { role, content }.
State.history = {}

State.listeners = {}

-- Persistence -----------------------------------------------------------------

function State.load()
	local readfile = Util.global("readfile")
	if type(readfile) ~= "function" then
		return State.data
	end

	local ok, raw = pcall(readfile, State.CONFIG_PATH)
	if not ok or type(raw) ~= "string" or Util.trim(raw) == "" then
		return State.data
	end

	local decodedOk, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not decodedOk or type(decoded) ~= "table" then
		return State.data
	end

	for key, value in pairs(decoded) do
		if State.data[key] ~= nil or key == "companion" then
			State.data[key] = value
		end
	end

	if type(State.data.keys) ~= "table" then
		State.data.keys = {}
	end
	if type(State.data.models) ~= "table" then
		State.data.models = {}
	end
	if type(State.data.sessions) ~= "table" then
		State.data.sessions = {}
	end

	return State.data
end

function State.save()
	local writefile = Util.global("writefile")
	if type(writefile) ~= "function" then
		return false
	end

	local encodedOk, encoded = pcall(function()
		return HttpService:JSONEncode(State.data)
	end)
	if not encodedOk then
		return false
	end

	local ok = pcall(writefile, State.CONFIG_PATH, encoded)
	return ok
end

-- Observers -------------------------------------------------------------------

function State.onChange(callback)
	table.insert(State.listeners, callback)
	return function()
		local index = table.find(State.listeners, callback)
		if index then
			table.remove(State.listeners, index)
		end
	end
end

function State.notify(key, value)
	for _, listener in ipairs(State.listeners) do
		pcall(listener, key, value, State.data)
	end
end

-- Accessors -------------------------------------------------------------------

function State.companion()
	return State.data.companion or "Rick"
end

function State.setCompanion(name)
	State.data.companion = (string.lower(tostring(name)) == "morty") and "Morty" or "Rick"
	State.save()
	State.notify("companion", State.data.companion)
	return State.data.companion
end

function State.provider()
	return State.data.provider or "OpenRouter"
end

function State.setProvider(id)
	State.data.provider = id
	State.save()
	State.notify("provider", id)
	return id
end

function State.apiKey(id)
	return State.data.keys[id or State.provider()] or ""
end

function State.setApiKey(value, id)
	State.data.keys[id or State.provider()] = value
	State.save()
	State.notify("key", value)
	return value
end

function State.model(fallback)
	local id = State.provider()
	return State.data.models[id] or fallback
end

function State.setModel(value)
	State.data.models[State.provider()] = value
	State.save()
	State.notify("model", value)
	return value
end

function State.bumpRequests()
	State.data.stats.requests = (State.data.stats.requests or 0) + 1
	State.save()
end

-- Conversation ----------------------------------------------------------------

function State.pushMessage(role, content)
	table.insert(State.history, { role = role, content = content })
	State.notify("history", #State.history)
	return #State.history
end

function State.setHistory(history)
	State.history = history or {}
	State.notify("history", #State.history)
end

function State.resetHistory()
	if #State.history > 0 then
		State.archive()
	end
	State.history = {}
	State.notify("history", 0)
end

--- Snapshot the active conversation into the sidebar's session list.
function State.archive()
	if #State.history == 0 then
		return nil
	end

	local firstUser
	for _, message in ipairs(State.history) do
		if message.role == "user" then
			firstUser = message.content
			break
		end
	end

	local session = {
		title = Util.truncate(firstUser or "Untitled conversation", 42),
		count = #State.history,
		time = Util.timestamp(),
		messages = State.history,
	}

	table.insert(State.data.sessions, 1, session)
	while #State.data.sessions > 20 do
		table.remove(State.data.sessions)
	end

	State.save()
	State.notify("sessions", State.data.sessions)
	return session
end

return State
