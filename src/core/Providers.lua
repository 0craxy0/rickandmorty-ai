--[[
	core/Providers.lua
	The API matrix from idea/ui-creation.md §2 and idea/main.md §5.

	Each provider ships with the preset request template from the spec, a
	payload "style" describing how to merge messages into that template, and a
	response style describing how to pull the assistant text back out.

	  OpenRouter  — multi-model balancing          (openai style)
	  AgentRouter — automated multi-step loops     (agent style)
	  Anthropic   — architectural Luau projects    (anthropic style)
	  OpenAI      — rapid syntax responses         (openai style)
	  DeepSeek    — high-speed algorithmic parsing (openai style)
	  FreeBuff    — localised open-access route    (freebuff style)
]]

local Http = require("core/Http")
local Util = require("core/Util")

local Providers = {}

Providers.order = { "OpenRouter", "AgentRouter", "Anthropic", "OpenAI", "DeepSeek", "FreeBuff" }

Providers.list = {
	OpenRouter = {
		id = "OpenRouter",
		url = "https://openrouter.ai/api/v1/chat/completions",
		style = "openai",
		model = "anthropic/claude-3.5-sonnet",
		template = '{"model": "anthropic/claude-3.5-sonnet", "messages": []}',
		description = "Flexible multi-model balancing across hundreds of endpoints.",
		keyLabel = "OpenRouter API key",
		headers = { ["Content-Type"] = "application/json" },
	},

	AgentRouter = {
		id = "AgentRouter",
		url = "http://localhost:7896/api/agent",
		style = "agent",
		model = "default",
		template = '{"agent": "default", "prompt": ""}',
		description = "Structural automated multi-step development loops.",
		keyLabel = "Gateway token (optional)",
		headers = { ["Content-Type"] = "application/json" },
	},

	Anthropic = {
		id = "Anthropic",
		url = "https://api.anthropic.com/v1/messages",
		style = "anthropic",
		model = "claude-3-5-sonnet-20241022",
		template = '{"model": "claude-3-5-sonnet-20241022", "max_tokens": 1024}',
		description = "Seeded for complex architectural Luau projects.",
		keyLabel = "Anthropic API key",
		maxTokens = 4096,
		headers = {
			["Content-Type"] = "application/json",
			["anthropic-version"] = "2023-06-01",
		},
	},

	OpenAI = {
		id = "OpenAI",
		url = "https://api.openai.com/v1/chat/completions",
		style = "openai",
		model = "gpt-4o",
		template = '{"model": "gpt-4o", "messages": []}',
		description = "Rapid syntax responses and variable corrections.",
		keyLabel = "OpenAI API key",
		headers = { ["Content-Type"] = "application/json" },
	},

	DeepSeek = {
		id = "DeepSeek",
		url = "https://api.deepseek.com/chat/completions",
		style = "openai",
		model = "deepseek-chat",
		template = '{"model": "deepseek-chat", "messages": []}',
		description = "High-speed algorithmic parsing routines.",
		keyLabel = "DeepSeek API key",
		headers = { ["Content-Type"] = "application/json" },
	},

	FreeBuff = {
		id = "FreeBuff",
		url = "http://localhost:7896/api/freebuff",
		style = "freebuff",
		model = "freebuff",
		template = '{"provider": "freebuff", "input": ""}',
		description = "Immediate localised open-access development path.",
		keyLabel = "Not required",
		headers = { ["Content-Type"] = "application/json" },
	},
}

-- Keys searched (in order) when a response shape is unknown.
local PRIORITY_KEYS = {
	"content",
	"text",
	"output",
	"response",
	"completion",
	"result",
	"answer",
	"message",
}

function Providers.get(id)
	return Providers.list[id] or Providers.list.OpenRouter
end

function Providers.ids()
	return Providers.order
end

function Providers.template(id)
	return Providers.get(id).template
end

--- Decoded preset template, safe to mutate.
function Providers.baseBody(id)
	local decoded = Http.decode(Providers.template(id))
	if type(decoded) ~= "table" then
		return { messages = {} }
	end

	return decoded
end

--- Merges the conversation into the provider's preset template.
--- `request` = { messages = {...}, system = string, prompt = string, model = string }
function Providers.buildBody(id, request)
	local provider = Providers.get(id)
	local body = Providers.baseBody(id)
	local model = request.model or provider.model
	local messages = request.messages or {}

	if provider.style == "openai" then
		body.model = model
		body.messages = messages
	elseif provider.style == "anthropic" then
		body.model = model
		body.max_tokens = body.max_tokens or provider.maxTokens or 4096
		body.system = request.system

		local filtered = {}
		for _, message in ipairs(messages) do
			if message.role ~= "system" then
				table.insert(filtered, { role = message.role, content = message.content })
			end
		end
		if #filtered == 0 and request.prompt then
			table.insert(filtered, { role = "user", content = request.prompt })
		end
		body.messages = filtered
	elseif provider.style == "agent" then
		body.agent = body.agent or "default"
		body.prompt = request.prompt or ""
		body.messages = messages
		body.system = request.system
	else
		body.provider = body.provider or "freebuff"
		body.input = request.prompt or ""
		body.messages = messages
		body.system = request.system
	end

	return body
end

--- Auth headers per backend.md §3 (bearer token + content type).
function Providers.buildHeaders(id, key)
	local provider = Providers.get(id)
	local headers = {}

	for name, value in pairs(provider.headers or {}) do
		headers[name] = value
	end

	headers["Content-Type"] = "application/json"

	if type(key) == "string" and key ~= "" then
		headers["Authorization"] = "Bearer " .. key
		if id == "Anthropic" then
			headers["x-api-key"] = key
		end
	end

	if id == "OpenRouter" then
		headers["HTTP-Referer"] = "https://local.rick-morty-ai-executor"
		headers["X-Title"] = "Rick & Morty AI Executor"
	end

	return headers
end

function Providers.endpoint(id)
	local provider = Providers.get(id)
	return provider.url
end

function Providers.label(id)
	local provider = Providers.get(id)
	return string.format("%s - %s", provider.id, provider.description)
end

local function deepFindString(value, depth)
	if depth > 6 or value == nil then
		return nil
	end

	if type(value) == "string" then
		return value
	end

	if type(value) ~= "table" then
		return nil
	end

	for _, key in ipairs(PRIORITY_KEYS) do
		local candidate = value[key]
		if type(candidate) == "string" and Util.trim(candidate) ~= "" then
			return candidate
		end
		if type(candidate) == "table" then
			local nested = deepFindString(candidate, depth + 1)
			if nested then
				return nested
			end
		end
	end

	if #value > 0 then
		return deepFindString(value[1], depth + 1)
	end

	return nil
end

function Providers.describeError(err)
	if type(err) == "string" then
		return err
	end

	if type(err) == "table" then
		if type(err.message) == "string" then
			return err.message
		end

		local encoded = Http.encode(err)
		if encoded then
			return encoded
		end
	end

	return tostring(err)
end

--- Extracts the assistant text from a raw response body.
function Providers.parse(id, body)
	local provider = Providers.get(id)

	if type(body) ~= "string" or Util.trim(body) == "" then
		return nil, "The provider returned an empty response."
	end

	local decoded = Http.decode(body)
	if type(decoded) ~= "table" then
		-- Some gateways answer with plain text.
		return Util.trim(body), nil
	end

	if decoded.error then
		return nil, Providers.describeError(decoded.error)
	end

	local text

	if provider.style == "openai" then
		local choice = decoded.choices and decoded.choices[1]
		if choice then
			text = (choice.message and choice.message.content) or choice.text
		end
	elseif provider.style == "anthropic" then
		if type(decoded.content) == "table" then
			for _, part in ipairs(decoded.content) do
				if part.type == "text" and type(part.text) == "string" then
					text = text and (text .. part.text) or part.text
				end
			end
		end
		text = text or decoded.completion
	else
		text = decoded.output or decoded.text or decoded.response or decoded.result
	end

	text = text or deepFindString(decoded, 0)

	if type(text) ~= "string" or Util.trim(text) == "" then
		return nil, "Could not locate assistant text in the provider response."
	end

	return text, nil
end

return Providers
