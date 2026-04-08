-- editutor/provider.lua
-- LLM API client for Gemini and NVIDIA (Kimi K2.5)

local M = {}

local config = require("editutor.config")

-- =============================================================================
-- Provider Registry
-- =============================================================================

M.BASE_PROVIDER = {
	name = "base",
	url = "",
	model = "",
	headers = {
		["content-type"] = "application/json",
	},
	api_key = function()
		return nil
	end,
	format_request = function(data)
		return data
	end,
	format_response = function(response)
		return nil
	end,
	format_error = function(response)
		return "Unknown error"
	end,
	stream_enabled = true,
}

M.PROVIDERS = {
	gemini = {
		__inherited_from = "BASE_PROVIDER",
		name = "gemini",
		url = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent",
		streaming_url = "https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse",
		model = "gemini-3-flash-preview",
		headers = {
			["content-type"] = "application/json",
			["x-goog-api-key"] = "${api_key}",
		},
		api_key = function()
			return os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
		end,
		build_url = function(base_url, model, _api_key)
			return base_url:gsub("%${model}", model)
		end,
		build_streaming_url = function(streaming_url, model, _api_key)
			return streaming_url:gsub("%${model}", model)
		end,
		format_request = function(data)
			return {
				contents = {
					{
						parts = { { text = data.message } },
					},
				},
				systemInstruction = {
					parts = { { text = data.system } },
				},
				generationConfig = {
					maxOutputTokens = data.max_tokens or 4096,
				},
			}
		end,
		format_response = function(response)
			if response.candidates and response.candidates[1] then
				local content = response.candidates[1].content
				if content and content.parts and content.parts[1] then
					return content.parts[1].text
				end
			end
			return nil
		end,
		format_error = function(response)
			if response.error then
				return response.error.message or response.error.status or "Unknown error"
			end
			return "Unknown error"
		end,
		stream_enabled = true,
		stream_in_body = false,
	},

	nvidia = {
		__inherited_from = "BASE_PROVIDER",
		name = "nvidia",
		url = "https://integrate.api.nvidia.com/v1/chat/completions",
		model = "moonshotai/kimi-k2.5",
		headers = {
			["content-type"] = "application/json",
			["Authorization"] = "Bearer ${api_key}",
		},
		api_key = function()
			return os.getenv("NVIDIA_API_KEY")
		end,
		format_request = function(data)
			return {
				model = data.model,
				messages = {
					{ role = "system", content = data.system },
					{ role = "user", content = data.message },
				},
				max_tokens = data.max_tokens or 16384,
				temperature = 1.0,
				top_p = 1.0,
				stream = true,
				chat_template_kwargs = { thinking = true },
			}
		end,
		format_response = function(response)
			if response.choices and response.choices[1] then
				return response.choices[1].message.content
			end
			return nil
		end,
		format_error = function(response)
			if response.error then
				return response.error.message or "Unknown error"
			end
			return "Unknown error"
		end,
		stream_enabled = true,
		stream_in_body = true,
	},
}

---Resolve provider with inheritance
---@param provider_name string
---@return table|nil resolved_provider
function M.resolve_provider(provider_name)
	local provider = M.PROVIDERS[provider_name]
	if not provider then
		provider = config.options.providers and config.options.providers[provider_name]
		if not provider then
			return nil
		end
	end

	local resolved = vim.deepcopy(M.BASE_PROVIDER)

	local function inherit_from(prov)
		if prov.__inherited_from then
			local parent_name = prov.__inherited_from
			if parent_name == "BASE_PROVIDER" then
				-- Already inherited from base
			elseif M.PROVIDERS[parent_name] then
				inherit_from(M.PROVIDERS[parent_name])
			end
		end
		for k, v in pairs(prov) do
			if k ~= "__inherited_from" then
				resolved[k] = v
			end
		end
	end

	inherit_from(provider)
	return resolved
end

---Register a custom provider
---@param name string Provider name
---@param definition table Provider definition
function M.register_provider(name, definition)
	M.PROVIDERS[name] = definition
end

-- =============================================================================
-- Streaming Debounce State
-- =============================================================================

M._stream_buffer = {}
M._stream_timer = nil
M._stream_debounce_ms = 50

---Set streaming debounce interval
---@param ms number Milliseconds
function M.set_debounce(ms)
	M._stream_debounce_ms = ms
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

---Process headers by replacing ${api_key} placeholders
---@param headers table<string, string>
---@param api_key string|nil
---@return table<string, string>
local function build_headers(headers, api_key)
	local processed = {}
	for key, value in pairs(headers) do
		if api_key then
			processed[key] = value:gsub("${api_key}", api_key)
		else
			processed[key] = value
		end
	end
	return processed
end

---Get the current provider (resolved with inheritance)
---@return table|nil provider
local function get_current_provider()
	local provider_name = config.options.provider or "gemini"

	local resolved = M.resolve_provider(provider_name)
	if resolved then
		return resolved
	end

	return config.get_provider()
end

---Process HTTP response from API
---@param response table HTTP response from curl
---@param provider table Provider configuration
---@return string|nil text Response text
---@return string|nil error Error message
local function process_response(response, provider)
	if not response then
		return nil, "No response received from API"
	end

	if response.status == 0 then
		return nil, "Failed to connect to API (network error or timeout)"
	end

	local ok, body = pcall(vim.json.decode, response.body)
	if not ok or not body then
		return nil, "Failed to parse API response"
	end

	if response.status >= 400 then
		local err = provider.format_error(body)
		return nil, string.format("API error (%d): %s", response.status, err)
	end

	local text = provider.format_response(body)
	if text then
		return text, nil
	end

	return nil, "Unexpected response format from API"
end

---Make async HTTP request
---@param url string API URL
---@param headers table Headers
---@param body table Request body
---@param callback function Callback(response, error)
local function make_request_async(url, headers, body, callback)
	local curl_ok, curl = pcall(require, "plenary.curl")
	if not curl_ok then
		vim.schedule(function()
			callback(nil, "plenary.nvim is required for HTTP requests")
		end)
		return
	end

	curl.post(url, {
		headers = headers,
		body = vim.json.encode(body),
		timeout = 60000,
		callback = function(response)
			vim.schedule(function()
				callback(response, nil)
			end)
		end,
	})
end

---Make sync HTTP request (using coroutine)
---@param url string API URL
---@param headers table Headers
---@param body table Request body
---@return table|nil response
local function make_request_sync(url, headers, body)
	local curl_ok, curl = pcall(require, "plenary.curl")
	if not curl_ok then
		return nil
	end

	local co = coroutine.running()
	if not co then
		return curl.post(url, {
			headers = headers,
			body = vim.json.encode(body),
			timeout = 60000,
		})
	end

	curl.post(url, {
		headers = headers,
		body = vim.json.encode(body),
		timeout = 60000,
		callback = function(response)
			vim.schedule(function()
				coroutine.resume(co, response)
			end)
		end,
	})

	return coroutine.yield()
end

---Get API key for current provider
---@param provider table Provider configuration
---@return string|nil api_key
local function get_api_key(provider)
	local config_key = config.options.api_key
	if config_key then
		if type(config_key) == "function" then
			return config_key()
		end
		return config_key
	end

	if provider.api_key then
		local ok, key = pcall(provider.api_key)
		if ok then
			return key
		end
	end

	return nil
end

-- =============================================================================
-- Query Functions
-- =============================================================================

---Send a query to the LLM (async version)
---@param system_prompt string System prompt
---@param user_message string User message
---@param callback function Callback(response_text, error)
function M.query_async(system_prompt, user_message, callback)
	local provider = get_current_provider()
	if not provider then
		callback(nil, "Provider not configured")
		return
	end

	local api_key = get_api_key(provider)

	if not api_key then
		callback(nil, "API key not found. Set GEMINI_API_KEY or NVIDIA_API_KEY environment variable.")
		return
	end

	local headers = build_headers(provider.headers, api_key)
	local model = config.options.model or provider.model

	local url = provider.url
	if provider.build_url then
		url = provider.build_url(provider.url, model, api_key)
	end

	local request_body = provider.format_request({
		model = model,
		max_tokens = 4096,
		system = system_prompt,
		message = user_message,
	})

	make_request_async(url, headers, request_body, function(response, err)
		if err then
			callback(nil, err)
			return
		end

		local text, api_err = process_response(response, provider)
		callback(text, api_err)
	end)
end

---Send a query to the LLM (sync version)
---@param system_prompt string System prompt
---@param user_message string User message
---@return string|nil response_text
---@return string|nil error
function M.query(system_prompt, user_message)
	local provider = get_current_provider()
	if not provider then
		return nil, "Provider not configured"
	end

	local api_key = get_api_key(provider)

	if not api_key then
		return nil, "API key not found. Set GEMINI_API_KEY or NVIDIA_API_KEY environment variable."
	end

	local headers = build_headers(provider.headers, api_key)
	local model = config.options.model or provider.model

	local url = provider.url
	if provider.build_url then
		url = provider.build_url(provider.url, model, api_key)
	end

	local request_body = provider.format_request({
		model = model,
		max_tokens = 4096,
		system = system_prompt,
		message = user_message,
	})

	local response = make_request_sync(url, headers, request_body)
	return process_response(response, provider)
end

---Check if provider is configured and ready
---@return boolean ready
---@return string|nil error
function M.check_provider()
	local provider = get_current_provider()
	if not provider then
		return false, "No provider configured"
	end

	local api_key = get_api_key(provider)
	if not api_key then
		return false, "API key not found. Set GEMINI_API_KEY or NVIDIA_API_KEY environment variable."
	end

	return true, nil
end

---Get provider info for display
---@return table info {name, model, url}
function M.get_info()
	local provider = get_current_provider()
	if not provider then
		return { name = "none", model = "none", url = "" }
	end

	return {
		name = provider.name,
		model = config.options.model or provider.model,
		url = provider.url,
	}
end

---List available providers
---@return string[] provider_names
function M.list_providers()
	local names = {}
	for name, _ in pairs(M.PROVIDERS) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- =============================================================================
-- Streaming Support
-- =============================================================================

---Parse SSE (Server-Sent Events) data line
---@param line string Data line from SSE
---@return string|nil text Extracted text content
---@return boolean done Whether stream is done
local function parse_sse_line(line, provider_name)
	if not line or line == "" or line == "data: [DONE]" then
		if line == "data: [DONE]" then
			return nil, true
		end
		return nil, false
	end

	local data = line:match("^data: (.+)$")
	if not data then
		return nil, false
	end

	local ok, json = pcall(vim.json.decode, data)
	if not ok or not json then
		return nil, false
	end

	local text = nil

	if provider_name == "gemini" then
		if json.candidates and json.candidates[1] then
			local content = json.candidates[1].content
			if content and content.parts and content.parts[1] then
				text = content.parts[1].text
			end
			local finish_reason = json.candidates[1].finishReason
			if finish_reason and finish_reason == "STOP" then
				return text, true
			end
		end
		if json.error then
			return nil, true
		end
	else
		-- OpenAI-compatible (nvidia, etc.)
		if json.choices and json.choices[1] and json.choices[1].delta then
			text = json.choices[1].delta.content
		end
		local finish_reason = json.choices and json.choices[1] and json.choices[1].finish_reason
		if finish_reason and finish_reason ~= vim.NIL then
			return text, true
		end
	end

	return text, false
end

---Send a streaming query to the LLM with debounced UI updates
---@param system_prompt string System prompt
---@param user_message string User message
---@param on_chunk function Callback(chunk_text) for each text chunk
---@param on_done function Callback(full_response, error) when complete
---@param opts? table {debounce_ms?: number, on_batch?: function}
function M.query_stream(system_prompt, user_message, on_chunk, on_done, opts)
	opts = opts or {}
	local debounce_ms = opts.debounce_ms or M._stream_debounce_ms

	local prov = get_current_provider()
	if not prov then
		on_done(nil, "Provider not configured")
		return
	end

	local api_key = get_api_key(prov)

	if not api_key then
		on_done(nil, "API key not found. Set GEMINI_API_KEY or NVIDIA_API_KEY environment variable.")
		return
	end

	local headers = build_headers(prov.headers, api_key)
	local model = config.options.model or prov.model

	local url
	if prov.build_streaming_url and prov.streaming_url then
		url = prov.build_streaming_url(prov.streaming_url, model, api_key)
	elseif prov.build_url then
		url = prov.build_url(prov.url, model, api_key)
	else
		url = prov.url
	end

	local request_body = prov.format_request({
		model = model,
		max_tokens = 4096,
		system = system_prompt,
		message = user_message,
	})

	if prov.stream_in_body ~= false then
		request_body.stream = true
	end

	local curl_ok, curl = pcall(require, "plenary.curl")
	if not curl_ok then
		on_done(nil, "plenary.nvim is required for HTTP requests")
		return nil
	end

	local full_response = {}
	local pending_chunks = {}
	local debounce_timer = nil
	local stream_done = false

	local function flush_pending()
		if #pending_chunks > 0 and not stream_done then
			local batch = table.concat(pending_chunks, "")
			pending_chunks = {}

			vim.schedule(function()
				if opts.on_batch then
					opts.on_batch(batch, table.concat(full_response, ""))
				else
					on_chunk(batch)
				end
			end)
		end
	end

	local function schedule_flush()
		if debounce_timer then
			vim.fn.timer_stop(debounce_timer)
		end
		debounce_timer = vim.fn.timer_start(debounce_ms, function()
			flush_pending()
		end)
	end

	local stream_callback = vim.schedule_wrap(function(_, data)
		if not data or data == "" then
			return
		end

		for line in data:gmatch("[^\n]+") do
			local text, done = parse_sse_line(line, prov.name)

			if text then
				table.insert(full_response, text)
				table.insert(pending_chunks, text)
				schedule_flush()
			end

			if done then
				stream_done = true
				if debounce_timer then
					vim.fn.timer_stop(debounce_timer)
				end
				flush_pending()
				vim.schedule(function()
					on_done(table.concat(full_response, ""), nil)
				end)
				return
			end
		end
	end)

	local job = curl.post(url, {
		headers = headers,
		body = vim.json.encode(request_body),
		stream = stream_callback,
		compressed = false,
		raw = { "--no-buffer", "-sS" },
		callback = function(response)
			vim.schedule(function()
				stream_done = true
				if debounce_timer then
					vim.fn.timer_stop(debounce_timer)
				end
				flush_pending()

				if response and response.status and response.status >= 400 then
					local err_msg = response.body or "Unknown error"
					on_done(nil, string.format("API error (%d): %s", response.status, err_msg))
					return
				end

				if #full_response == 0 then
					if response and response.body and response.body ~= "" then
						for line in response.body:gmatch("[^\n]+") do
							local text, _ = parse_sse_line(line, prov.name)
							if text then
								table.insert(full_response, text)
							end
						end
						if #full_response > 0 then
							local final_text = table.concat(full_response, "")
							if opts.on_batch then
								opts.on_batch(final_text, final_text)
							else
								on_chunk(final_text)
							end
							on_done(final_text, nil)
							return
						end
					end
					on_done(nil, "No response received")
				end
			end)
		end,
		on_error = function(err)
			vim.schedule(function()
				stream_done = true
				on_done(nil, "Request error: " .. vim.inspect(err))
			end)
		end,
	})

	return job
end

---Cancel a streaming request
---@param job any Job from query_stream
function M.cancel_stream(job)
	if job and job.shutdown then
		pcall(job.shutdown, job)
	end
end

return M
