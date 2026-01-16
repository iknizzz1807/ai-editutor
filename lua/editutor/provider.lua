-- editutor/provider.lua
-- LLM API client with declarative provider definitions and streaming support

local M = {}

local config = require("editutor.config")

-- =============================================================================
-- Provider Registry with Inheritance
-- =============================================================================

---Base provider template that others inherit from
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
  -- Streaming configuration
  stream_enabled = true,
  stream_parser = nil, -- Override for custom SSE parsing
}

---Built-in provider definitions (declarative)
M.PROVIDERS = {
  -- Claude (Anthropic)
  claude = {
    __inherited_from = "BASE_PROVIDER",
    name = "claude",
    url = "https://api.anthropic.com/v1/messages",
    model = "claude-sonnet-4-20250514",
    headers = {
      ["content-type"] = "application/json",
      ["x-api-key"] = "${api_key}",
      ["anthropic-version"] = "2023-06-01",
    },
    api_key = function()
      return os.getenv("ANTHROPIC_API_KEY")
    end,
    format_request = function(data)
      return {
        model = data.model,
        max_tokens = data.max_tokens or 4096,
        system = data.system,
        messages = {
          { role = "user", content = data.message },
        },
      }
    end,
    format_response = function(response)
      if response.content and response.content[1] then
        return response.content[1].text
      end
      return nil
    end,
    format_error = function(response)
      if response.error then
        return response.error.message
      end
      return "Unknown error"
    end,
  },

  -- OpenAI
  openai = {
    __inherited_from = "BASE_PROVIDER",
    name = "openai",
    url = "https://api.openai.com/v1/chat/completions",
    model = "gpt-4o",
    headers = {
      ["content-type"] = "application/json",
      ["Authorization"] = "Bearer ${api_key}",
    },
    api_key = function()
      return os.getenv("OPENAI_API_KEY")
    end,
    format_request = function(data)
      return {
        model = data.model,
        max_tokens = data.max_tokens or 4096,
        messages = {
          { role = "system", content = data.system },
          { role = "user", content = data.message },
        },
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
        return response.error.message
      end
      return "Unknown error"
    end,
  },

  -- OpenAI-compatible providers (inherit from openai)
  deepseek = {
    __inherited_from = "openai",
    name = "deepseek",
    url = "https://api.deepseek.com/chat/completions",
    model = "deepseek-chat",
    api_key = function()
      return os.getenv("DEEPSEEK_API_KEY")
    end,
  },

  groq = {
    __inherited_from = "openai",
    name = "groq",
    url = "https://api.groq.com/openai/v1/chat/completions",
    model = "llama-3.3-70b-versatile",
    api_key = function()
      return os.getenv("GROQ_API_KEY")
    end,
  },

  together = {
    __inherited_from = "openai",
    name = "together",
    url = "https://api.together.xyz/v1/chat/completions",
    model = "meta-llama/Llama-3.3-70B-Instruct-Turbo",
    api_key = function()
      return os.getenv("TOGETHER_API_KEY")
    end,
  },

  openrouter = {
    __inherited_from = "openai",
    name = "openrouter",
    url = "https://openrouter.ai/api/v1/chat/completions",
    model = "anthropic/claude-3.5-sonnet",
    api_key = function()
      return os.getenv("OPENROUTER_API_KEY")
    end,
  },

  -- Ollama (local)
  ollama = {
    __inherited_from = "BASE_PROVIDER",
    name = "ollama",
    url = "http://localhost:11434/api/chat",
    model = "llama3.2",
    headers = {
      ["content-type"] = "application/json",
    },
    api_key = function()
      return nil -- No API key needed
    end,
    format_request = function(data)
      return {
        model = data.model,
        messages = {
          { role = "system", content = data.system },
          { role = "user", content = data.message },
        },
        stream = false,
      }
    end,
    format_response = function(response)
      if response.message then
        return response.message.content
      end
      return nil
    end,
    format_error = function(response)
      return response.error or "Unknown error"
    end,
  },
}

---Resolve provider with inheritance
---@param provider_name string
---@return table|nil resolved_provider
function M.resolve_provider(provider_name)
  local provider = M.PROVIDERS[provider_name]
  if not provider then
    -- Check config for custom providers
    provider = config.options.providers and config.options.providers[provider_name]
    if not provider then
      return nil
    end
  end

  -- Resolve inheritance chain
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
    -- Apply this provider's overrides
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
---@param definition table Provider definition (can use __inherited_from)
function M.register_provider(name, definition)
  M.PROVIDERS[name] = definition
end

-- =============================================================================
-- Streaming Debounce State
-- =============================================================================

M._stream_buffer = {}
M._stream_timer = nil
M._stream_debounce_ms = 50 -- Debounce interval for UI updates

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
  local provider_name = config.options.provider or "claude"

  -- First try to resolve from our registry
  local resolved = M.resolve_provider(provider_name)
  if resolved then
    return resolved
  end

  -- Fallback to config providers
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
    timeout = 60000, -- 60 seconds
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
    -- Not in coroutine, make blocking request
    return curl.post(url, {
      headers = headers,
      body = vim.json.encode(body),
      timeout = 60000,
    })
  end

  -- In coroutine, yield until response
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
---Checks config.options.api_key first, then provider's default
---@param provider table Provider configuration
---@return string|nil api_key
local function get_api_key(provider)
  -- Check if user provided api_key in setup()
  local config_key = config.options.api_key
  if config_key then
    if type(config_key) == "function" then
      return config_key()
    end
    return config_key
  end

  -- Fall back to provider's default api_key function
  if provider.api_key then
    local ok, key = pcall(provider.api_key)
    if ok then
      return key
    end
  end

  return nil
end

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

  -- Get API key
  local api_key = get_api_key(provider)

  -- Check for required API key
  if provider.name ~= "ollama" and not api_key then
    callback(nil, string.format("API key not found for %s. Set %s_API_KEY environment variable.",
      provider.name, provider.name:upper()))
    return
  end

  -- Build request
  local headers = build_headers(provider.headers, api_key)
  local model = config.options.model or provider.model

  local request_body = provider.format_request({
    model = model,
    max_tokens = 4096,
    system = system_prompt,
    message = user_message,
  })

  -- Make request
  make_request_async(provider.url, headers, request_body, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    local text, api_err = process_response(response, provider)
    callback(text, api_err)
  end)
end

---Send a query to the LLM (sync version for use in coroutines)
---@param system_prompt string System prompt
---@param user_message string User message
---@return string|nil response_text
---@return string|nil error
function M.query(system_prompt, user_message)
  local provider = get_current_provider()
  if not provider then
    return nil, "Provider not configured"
  end

  -- Get API key
  local api_key = get_api_key(provider)

  -- Check for required API key
  if provider.name ~= "ollama" and not api_key then
    return nil, string.format("API key not found for %s", provider.name)
  end

  -- Build request
  local headers = build_headers(provider.headers, api_key)
  local model = config.options.model or provider.model

  local request_body = provider.format_request({
    model = model,
    max_tokens = 4096,
    system = system_prompt,
    message = user_message,
  })

  -- Make request
  local response = make_request_sync(provider.url, headers, request_body)
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

  if provider.name ~= "ollama" then
    local api_key = get_api_key(provider)
    if not api_key then
      return false, string.format("%s_API_KEY environment variable not set", provider.name:upper())
    end
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
---@param provider_name string Provider name
---@return string|nil text Extracted text content
---@return boolean done Whether stream is done
local function parse_sse_line(line, provider_name)
  -- Skip empty lines and non-data lines
  if not line or line == "" or line == "data: [DONE]" then
    if line == "data: [DONE]" then
      return nil, true
    end
    return nil, false
  end

  -- Remove "data: " prefix
  local data = line:match("^data: (.+)$")
  if not data then
    return nil, false
  end

  -- Parse JSON
  local ok, json = pcall(vim.json.decode, data)
  if not ok or not json then
    return nil, false
  end

  -- Extract text based on provider format
  local text = nil

  -- OpenAI-compatible providers (openai, deepseek, groq, together, openrouter)
  local openai_compatible = {
    openai = true,
    deepseek = true,
    groq = true,
    together = true,
    openrouter = true,
  }

  if provider_name == "claude" then
    -- Claude format: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}
    if json.type == "content_block_delta" and json.delta and json.delta.text then
      text = json.delta.text
    elseif json.type == "message_stop" then
      return nil, true
    end
  elseif openai_compatible[provider_name] then
    -- OpenAI format: {"choices":[{"delta":{"content":"..."}}]}
    if json.choices and json.choices[1] and json.choices[1].delta then
      text = json.choices[1].delta.content
    end
    -- Check for finish_reason (vim.NIL from JSON null is truthy, so check explicitly)
    local finish_reason = json.choices and json.choices[1] and json.choices[1].finish_reason
    if finish_reason and finish_reason ~= vim.NIL then
      return text, true
    end
  elseif provider_name == "ollama" then
    -- Ollama format: {"message":{"content":"..."},"done":false}
    if json.message and json.message.content then
      text = json.message.content
    end
    if json.done then
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

  -- Get API key
  local api_key = get_api_key(prov)

  -- Check for required API key
  if prov.name ~= "ollama" and not api_key then
    on_done(nil, string.format("API key not found for %s", prov.name))
    return
  end

  -- Build streaming request
  local headers = build_headers(prov.headers, api_key)
  local model = config.options.model or prov.model

  local request_body = prov.format_request({
    model = model,
    max_tokens = 4096,
    system = system_prompt,
    message = user_message,
  })

  -- Enable streaming
  request_body.stream = true

  -- Build curl command for streaming
  local header_args = {}
  for k, v in pairs(headers) do
    table.insert(header_args, "-H")
    table.insert(header_args, string.format("%s: %s", k, v))
  end

  local cmd = {
    "curl",
    "-sS",
    "--no-buffer",
    "-X",
    "POST",
    prov.url,
  }

  for _, h in ipairs(header_args) do
    table.insert(cmd, h)
  end

  table.insert(cmd, "-d")
  table.insert(cmd, vim.json.encode(request_body))

  -- Streaming state with debounce
  local full_response = {}
  local buffer = ""
  local pending_chunks = {}
  local debounce_timer = nil
  local stream_done = false

  -- Debounced flush of pending chunks
  local function flush_pending()
    if #pending_chunks > 0 and not stream_done then
      local batch = table.concat(pending_chunks, "")
      pending_chunks = {}

      vim.schedule(function()
        -- Call on_batch if provided (for batched UI updates)
        if opts.on_batch then
          opts.on_batch(batch, table.concat(full_response, ""))
        else
          on_chunk(batch)
        end
      end)
    end
  end

  -- Schedule debounced flush
  local function schedule_flush()
    if debounce_timer then
      vim.fn.timer_stop(debounce_timer)
    end

    debounce_timer = vim.fn.timer_start(debounce_ms, function()
      flush_pending()
    end)
  end

  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          -- Buffer incomplete lines
          buffer = buffer .. line

          -- Process complete lines
          while true do
            local newline_pos = buffer:find("\n")
            if not newline_pos then
              break
            end

            local complete_line = buffer:sub(1, newline_pos - 1)
            buffer = buffer:sub(newline_pos + 1)

            -- Parse SSE data
            local text, done = parse_sse_line(complete_line, prov.name)

            if text then
              table.insert(full_response, text)
              table.insert(pending_chunks, text)
              schedule_flush()
            end

            if done then
              stream_done = true
              -- Final flush
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
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data and data[1] ~= "" then
        local err_msg = table.concat(data, "\n")
        if err_msg ~= "" then
          stream_done = true
          vim.schedule(function()
            on_done(nil, "Stream error: " .. err_msg)
          end)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      stream_done = true
      if debounce_timer then
        vim.fn.timer_stop(debounce_timer)
      end
      flush_pending()

      vim.schedule(function()
        if exit_code ~= 0 and #full_response == 0 then
          on_done(nil, "Stream request failed with exit code: " .. exit_code)
        elseif #full_response > 0 then
          -- In case we didn't get a proper [DONE] signal
          on_done(table.concat(full_response, ""), nil)
        end
      end)
    end,
    stdout_buffered = false,
    stderr_buffered = false,
  })

  if job_id <= 0 then
    on_done(nil, "Failed to start streaming request")
  end

  -- Return job_id for potential cancellation
  return job_id
end

---Cancel a streaming request
---@param job_id number Job ID from query_stream
function M.cancel_stream(job_id)
  if job_id and job_id > 0 then
    vim.fn.jobstop(job_id)
  end
end

return M
