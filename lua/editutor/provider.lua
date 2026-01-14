-- editutor/provider.lua
-- LLM API client using plenary.curl

local M = {}

local config = require("editutor.config")

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

---Send a query to the LLM (async version)
---@param system_prompt string System prompt
---@param user_message string User message
---@param callback function Callback(response_text, error)
function M.query_async(system_prompt, user_message, callback)
  local provider = config.get_provider()
  if not provider then
    callback(nil, "Provider not configured")
    return
  end

  -- Get API key
  local api_key = nil
  if provider.api_key then
    local ok, key = pcall(provider.api_key)
    if ok then
      api_key = key
    end
  end

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
  local provider = config.get_provider()
  if not provider then
    return nil, "Provider not configured"
  end

  -- Get API key
  local api_key = nil
  if provider.api_key then
    local ok, key = pcall(provider.api_key)
    if ok then
      api_key = key
    end
  end

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
  local provider = config.get_provider()
  if not provider then
    return false, "No provider configured"
  end

  if provider.name ~= "ollama" then
    local api_key = nil
    if provider.api_key then
      local ok, key = pcall(provider.api_key)
      if ok then
        api_key = key
      end
    end

    if not api_key then
      return false, string.format("%s_API_KEY environment variable not set", provider.name:upper())
    end
  end

  return true, nil
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

  if provider_name == "claude" then
    -- Claude format: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}
    if json.type == "content_block_delta" and json.delta and json.delta.text then
      text = json.delta.text
    elseif json.type == "message_stop" then
      return nil, true
    end
  elseif provider_name == "openai" then
    -- OpenAI format: {"choices":[{"delta":{"content":"..."}}]}
    if json.choices and json.choices[1] and json.choices[1].delta then
      text = json.choices[1].delta.content
    end
    if json.choices and json.choices[1] and json.choices[1].finish_reason then
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

---Send a streaming query to the LLM
---@param system_prompt string System prompt
---@param user_message string User message
---@param on_chunk function Callback(chunk_text) for each text chunk
---@param on_done function Callback(full_response, error) when complete
function M.query_stream(system_prompt, user_message, on_chunk, on_done)
  local prov = config.get_provider()
  if not prov then
    on_done(nil, "Provider not configured")
    return
  end

  -- Get API key
  local api_key = nil
  if prov.api_key then
    local ok, key = pcall(prov.api_key)
    if ok then
      api_key = key
    end
  end

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
    "-X", "POST",
    prov.url,
  }

  for _, h in ipairs(header_args) do
    table.insert(cmd, h)
  end

  table.insert(cmd, "-d")
  table.insert(cmd, vim.json.encode(request_body))

  -- Use vim.fn.jobstart for streaming
  local full_response = {}
  local buffer = ""

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
              vim.schedule(function()
                on_chunk(text)
              end)
            end

            if done then
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
          vim.schedule(function()
            on_done(nil, "Stream error: " .. err_msg)
          end)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
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
