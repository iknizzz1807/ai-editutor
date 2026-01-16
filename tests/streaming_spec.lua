-- tests/streaming_spec.lua
-- Comprehensive tests for streaming SSE parsing

local M = {}

M.results = { passed = 0, failed = 0, tests = {} }

local function log(status, name, msg)
  local icon = status == "PASS" and "[OK]" or (status == "FAIL" and "[!!]" or "[--]")
  print(string.format("%s %s: %s", icon, name, msg or ""))

  if status == "PASS" then
    M.results.passed = M.results.passed + 1
  elseif status == "FAIL" then
    M.results.failed = M.results.failed + 1
  end

  table.insert(M.results.tests, { name = name, status = status, msg = msg })
end

local function section(name)
  print("\n" .. string.rep("=", 60))
  print("  " .. name)
  print(string.rep("=", 60))
end

-- =============================================================================
-- SSE Parser Tests
-- =============================================================================

-- Recreate the parse_sse_line function for testing
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

  if provider_name == "claude" then
    if json.type == "content_block_delta" and json.delta and json.delta.text then
      text = json.delta.text
    elseif json.type == "message_stop" then
      return nil, true
    end
  elseif provider_name == "openai" then
    if json.choices and json.choices[1] and json.choices[1].delta then
      text = json.choices[1].delta.content
    end
    -- Check for finish_reason (vim.NIL from JSON null is truthy, so check type)
    local finish_reason = json.choices and json.choices[1] and json.choices[1].finish_reason
    if finish_reason and finish_reason ~= vim.NIL then
      return text, true
    end
  elseif provider_name == "ollama" then
    if json.message and json.message.content then
      text = json.message.content
    end
    if json.done then
      return text, true
    end
  end

  return text, false
end

function M.test_claude_sse()
  section("Claude SSE Parsing")

  -- Test content block delta
  local line1 = 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}'
  local text1, done1 = parse_sse_line(line1, "claude")
  log(text1 == "Hello" and not done1 and "PASS" or "FAIL", "claude.content_block_delta",
    string.format("text='%s', done=%s", tostring(text1), tostring(done1)))

  -- Test message stop
  local line2 = 'data: {"type":"message_stop"}'
  local text2, done2 = parse_sse_line(line2, "claude")
  log(text2 == nil and done2 and "PASS" or "FAIL", "claude.message_stop",
    string.format("text='%s', done=%s", tostring(text2), tostring(done2)))

  -- Test message start (should not return text)
  local line3 = 'data: {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant"}}'
  local text3, done3 = parse_sse_line(line3, "claude")
  log(text3 == nil and not done3 and "PASS" or "FAIL", "claude.message_start",
    string.format("text='%s', done=%s", tostring(text3), tostring(done3)))

  -- Test multiple delta chunks
  local chunks = {
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"A "}}',
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"closure "}}',
    'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"is a function."}}',
  }

  local full_text = ""
  local all_done = false
  for _, chunk in ipairs(chunks) do
    local t, d = parse_sse_line(chunk, "claude")
    if t then
      full_text = full_text .. t
    end
    all_done = d
  end

  log(full_text == "A closure is a function." and not all_done and "PASS" or "FAIL",
    "claude.multiple_chunks",
    string.format("full_text='%s'", full_text))
end

function M.test_openai_sse()
  section("OpenAI SSE Parsing")

  -- Test delta content
  local line1 = 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"World"},"finish_reason":null}]}'
  local text1, done1 = parse_sse_line(line1, "openai")
  log(text1 == "World" and not done1 and "PASS" or "FAIL", "openai.delta_content",
    string.format("text='%s', done=%s", tostring(text1), tostring(done1)))

  -- Test finish reason
  local line2 = 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'
  local text2, done2 = parse_sse_line(line2, "openai")
  log(done2 and "PASS" or "FAIL", "openai.finish_reason",
    string.format("text='%s', done=%s", tostring(text2), tostring(done2)))

  -- Test [DONE] signal
  local line3 = "data: [DONE]"
  local text3, done3 = parse_sse_line(line3, "openai")
  log(text3 == nil and done3 and "PASS" or "FAIL", "openai.done_signal",
    string.format("text='%s', done=%s", tostring(text3), tostring(done3)))

  -- Test deepseek/groq format (same as OpenAI)
  local line4 = 'data: {"choices":[{"index":0,"delta":{"content":"DeepSeek"}}]}'
  local text4, done4 = parse_sse_line(line4, "openai")
  log(text4 == "DeepSeek" and not done4 and "PASS" or "FAIL", "openai_compat.delta",
    string.format("text='%s'", tostring(text4)))
end

function M.test_ollama_sse()
  section("Ollama SSE Parsing")

  -- Test message content
  local line1 = 'data: {"model":"llama3.2","message":{"role":"assistant","content":"Hello "},"done":false}'
  local text1, done1 = parse_sse_line(line1, "ollama")
  log(text1 == "Hello " and not done1 and "PASS" or "FAIL", "ollama.message_content",
    string.format("text='%s', done=%s", tostring(text1), tostring(done1)))

  -- Test done signal
  local line2 = 'data: {"model":"llama3.2","message":{"role":"assistant","content":"!"},"done":true}'
  local text2, done2 = parse_sse_line(line2, "ollama")
  log(text2 == "!" and done2 and "PASS" or "FAIL", "ollama.done_signal",
    string.format("text='%s', done=%s", tostring(text2), tostring(done2)))
end

function M.test_edge_cases()
  section("Edge Cases")

  -- Empty line
  local text1, done1 = parse_sse_line("", "claude")
  log(text1 == nil and not done1 and "PASS" or "FAIL", "edge.empty_line", "Empty line")

  -- Nil input
  local text2, done2 = parse_sse_line(nil, "claude")
  log(text2 == nil and not done2 and "PASS" or "FAIL", "edge.nil_input", "Nil input")

  -- Invalid JSON
  local text3, done3 = parse_sse_line("data: {invalid json}", "claude")
  log(text3 == nil and not done3 and "PASS" or "FAIL", "edge.invalid_json", "Invalid JSON")

  -- Non-data line
  local text4, done4 = parse_sse_line("event: message", "claude")
  log(text4 == nil and not done4 and "PASS" or "FAIL", "edge.non_data_line", "Non-data line")

  -- Data with special characters
  local line5 = 'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello\\nWorld\\t!"}}'
  local text5, done5 = parse_sse_line(line5, "claude")
  log(text5 == "Hello\nWorld\t!" and not done5 and "PASS" or "FAIL", "edge.special_chars",
    string.format("text contains newline and tab"))

  -- Unicode content
  local line6 = 'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"日本語テスト 🚀"}}'
  local text6, done6 = parse_sse_line(line6, "claude")
  log(text6 == "日本語テスト 🚀" and not done6 and "PASS" or "FAIL", "edge.unicode",
    string.format("unicode text handled"))

  -- Very long content
  local long_text = string.rep("a", 10000)
  local line7 = 'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"' .. long_text .. '"}}'
  local text7, done7 = parse_sse_line(line7, "claude")
  log(text7 and #text7 == 10000 and not done7 and "PASS" or "FAIL", "edge.long_content",
    string.format("long content: %d chars", text7 and #text7 or 0))
end

function M.test_provider_module()
  section("Provider Module Integration")

  local provider = require("editutor.provider")

  -- Test buffer state
  log(type(provider._stream_buffer) == "table" and "PASS" or "FAIL",
    "provider.buffer_init", "Buffer initialized")

  -- Test debounce setting
  provider.set_debounce(100)
  log(provider._stream_debounce_ms == 100 and "PASS" or "FAIL",
    "provider.set_debounce", string.format("Debounce set to %dms", provider._stream_debounce_ms))

  -- Test cancel with invalid job
  local ok = pcall(function()
    provider.cancel_stream(nil)
    provider.cancel_stream(-1)
    provider.cancel_stream(0)
  end)
  log(ok and "PASS" or "FAIL", "provider.cancel_invalid", "Cancel invalid jobs handled")

  -- Test provider list includes streaming-capable providers
  local providers = provider.list_providers()
  local streaming_providers = { "claude", "openai", "ollama" }
  local all_found = true
  for _, name in ipairs(streaming_providers) do
    local found = false
    for _, p in ipairs(providers) do
      if p == name then
        found = true
        break
      end
    end
    if not found then
      all_found = false
    end
  end
  log(all_found and "PASS" or "FAIL", "provider.streaming_providers",
    string.format("%d providers available", #providers))
end

function M.test_stream_simulation()
  section("Stream Simulation")

  -- Simulate a full streaming response
  local claude_stream = {
    'data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","content":[]}}',
    'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
    'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"A "}}',
    'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"closure "}}',
    'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"captures "}}',
    'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"variables."}}',
    'data: {"type":"content_block_stop","index":0}',
    'data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null}}',
    'data: {"type":"message_stop"}',
  }

  local full_text = {}
  local stream_done = false

  for _, line in ipairs(claude_stream) do
    local text, done = parse_sse_line(line, "claude")
    if text then
      table.insert(full_text, text)
    end
    if done then
      stream_done = true
    end
  end

  local result = table.concat(full_text, "")
  log(result == "A closure captures variables." and stream_done and "PASS" or "FAIL",
    "simulation.claude_full",
    string.format("result='%s', done=%s", result, tostring(stream_done)))

  -- Simulate OpenAI stream
  local openai_stream = {
    'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}',
    'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":"The "},"finish_reason":null}]}',
    'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":"answer "},"finish_reason":null}]}',
    'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":"is 42."},"finish_reason":null}]}',
    'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
    "data: [DONE]",
  }

  local oai_text = {}
  local oai_done = false

  for _, line in ipairs(openai_stream) do
    local text, done = parse_sse_line(line, "openai")
    if text then
      table.insert(oai_text, text)
    end
    if done then
      oai_done = true
    end
  end

  local oai_result = table.concat(oai_text, "")
  log(oai_result == "The answer is 42." and oai_done and "PASS" or "FAIL",
    "simulation.openai_full",
    string.format("result='%s', done=%s", oai_result, tostring(oai_done)))
end

-- =============================================================================
-- RUN ALL TESTS
-- =============================================================================

function M.run_all()
  print(string.rep("=", 60))
  print("  Streaming SSE Parser Tests")
  print(string.rep("=", 60))

  M.results = { passed = 0, failed = 0, tests = {} }

  M.test_claude_sse()
  M.test_openai_sse()
  M.test_ollama_sse()
  M.test_edge_cases()
  M.test_provider_module()
  M.test_stream_simulation()

  -- Summary
  print("\n" .. string.rep("=", 60))
  print("  STREAMING TEST SUMMARY")
  print(string.rep("=", 60))
  print(string.format("  Passed: %d", M.results.passed))
  print(string.format("  Failed: %d", M.results.failed))
  print(string.format("  Total: %d", #M.results.tests))

  if M.results.failed > 0 then
    print("\n  Failed tests:")
    for _, t in ipairs(M.results.tests) do
      if t.status == "FAIL" then
        print(string.format("    - %s: %s", t.name, t.msg or ""))
      end
    end
  end

  print(string.rep("=", 60))

  return M.results.failed == 0
end

return M
