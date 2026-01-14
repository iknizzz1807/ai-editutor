-- codementor/provider.lua
-- LLM API client using plenary.curl

local M = {}

local config = require("codementor.config")

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

return M
