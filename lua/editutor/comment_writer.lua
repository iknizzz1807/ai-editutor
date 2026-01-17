-- editutor/comment_writer.lua
-- Insert AI responses as block comments with [AI] marker
-- Simplified: always use block comment format /* [AI] ... */

local M = {}

-- Comment syntax definitions by filetype
M.comment_styles = {
  -- C-style languages
  c = { line = "//", block = { "/*", "*/" } },
  cpp = { line = "//", block = { "/*", "*/" } },
  java = { line = "//", block = { "/*", "*/" } },
  javascript = { line = "//", block = { "/*", "*/" } },
  javascriptreact = { line = "//", block = { "/*", "*/" } },
  typescript = { line = "//", block = { "/*", "*/" } },
  typescriptreact = { line = "//", block = { "/*", "*/" } },
  go = { line = "//", block = { "/*", "*/" } },
  rust = { line = "//", block = { "/*", "*/" } },
  swift = { line = "//", block = { "/*", "*/" } },
  kotlin = { line = "//", block = { "/*", "*/" } },
  scala = { line = "//", block = { "/*", "*/" } },
  dart = { line = "//", block = { "/*", "*/" } },
  php = { line = "//", block = { "/*", "*/" } },
  css = { line = nil, block = { "/*", "*/" } },
  scss = { line = "//", block = { "/*", "*/" } },
  less = { line = "//", block = { "/*", "*/" } },

  -- Hash-style languages
  python = { line = "#", block = { '"""', '"""' } },
  ruby = { line = "#", block = { "=begin", "=end" } },
  perl = { line = "#", block = { "=pod", "=cut" } },
  sh = { line = "#", block = nil },
  bash = { line = "#", block = nil },
  zsh = { line = "#", block = nil },
  fish = { line = "#", block = nil },
  yaml = { line = "#", block = nil },
  toml = { line = "#", block = nil },
  dockerfile = { line = "#", block = nil },
  make = { line = "#", block = nil },
  cmake = { line = "#", block = { "#[[", "]]" } },
  r = { line = "#", block = nil },

  -- Dash-style languages
  lua = { line = "--", block = { "--[[", "]]" } },
  sql = { line = "--", block = { "/*", "*/" } },
  haskell = { line = "--", block = { "{-", "-}" } },
  elm = { line = "--", block = { "{-", "-}" } },

  -- HTML/XML style
  html = { line = nil, block = { "<!--", "-->" } },
  xml = { line = nil, block = { "<!--", "-->" } },
  svg = { line = nil, block = { "<!--", "-->" } },
  vue = { line = "//", block = { "<!--", "-->" } },
  svelte = { line = "//", block = { "<!--", "-->" } },

  -- Lisp-style
  lisp = { line = ";", block = { "#|", "|#" } },
  clojure = { line = ";", block = nil },
  scheme = { line = ";", block = { "#|", "|#" } },

  -- Other
  vim = { line = '"', block = nil },
  tex = { line = "%", block = nil },
  latex = { line = "%", block = nil },
  erlang = { line = "%", block = nil },
  elixir = { line = "#", block = { '"""', '"""' } },
  julia = { line = "#", block = { "#=", "=#" } },
  nim = { line = "#", block = { "#[", "]#" } },
  zig = { line = "//", block = nil },
  ocaml = { line = nil, block = { "(*", "*)" } },
  fsharp = { line = "//", block = { "(*", "*)" } },

  -- Config files
  ini = { line = ";", block = nil },
  conf = { line = "#", block = nil },
  gitignore = { line = "#", block = nil },
  editorconfig = { line = "#", block = nil },
}

-- Fallback for unknown filetypes
M.default_style = { line = "//", block = { "/*", "*/" } }

-- AI response marker
M.AI_MARKER = "[AI]"

---Get comment style for current buffer
---@param bufnr? number Buffer number
---@return table style Comment style { line, block }
function M.get_style(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  return M.comment_styles[ft] or M.default_style
end

---Get indentation from a line
---@param line string
---@return string indent
local function get_indent(line)
  return line:match("^(%s*)") or ""
end

-- Default max line width for wrapping
local MAX_LINE_WIDTH = 100

---Normalize text: collapse multiple spaces, join lines within same paragraph
---@param text string Raw text from LLM
---@return string[] paragraphs List of paragraphs (separated by blank lines)
local function normalize_paragraphs(text)
  local paragraphs = {}
  local current_para = {}

  for line in text:gmatch("[^\n]*") do
    -- Trim whitespace
    local trimmed = line:match("^%s*(.-)%s*$") or ""

    if trimmed == "" then
      -- Blank line = paragraph break
      if #current_para > 0 then
        table.insert(paragraphs, table.concat(current_para, " "))
        current_para = {}
      end
      -- Keep blank line as separator
      table.insert(paragraphs, "")
    else
      -- Continue building paragraph
      table.insert(current_para, trimmed)
    end
  end

  -- Don't forget last paragraph
  if #current_para > 0 then
    table.insert(paragraphs, table.concat(current_para, " "))
  end

  return paragraphs
end

---Wrap text to max width
---@param text string Text to wrap
---@param max_width number Max characters per line
---@param prefix string Prefix for all lines
---@return string[] lines Wrapped lines
local function wrap_text(text, max_width, prefix)
  local full_text = prefix .. text

  if #full_text <= max_width then
    return { full_text }
  end

  local lines = {}
  local words = {}
  for word in text:gmatch("%S+") do
    table.insert(words, word)
  end

  local current_line = prefix

  for _, word in ipairs(words) do
    local test_line = current_line == prefix and (current_line .. word) or (current_line .. " " .. word)

    if #test_line <= max_width then
      current_line = test_line
    else
      -- Line is full, save it
      if current_line ~= prefix then
        table.insert(lines, current_line)
      end

      if #(prefix .. word) > max_width then
        -- Word itself is too long, just add it
        table.insert(lines, prefix .. word)
        current_line = prefix
      else
        current_line = prefix .. word
      end
    end
  end

  -- Add remaining content
  if current_line ~= prefix then
    table.insert(lines, current_line)
  end

  return lines
end

---Format response as block comment with [AI] marker
---@param response string Response text
---@param style table Comment style
---@param indent string Indentation to use
---@return string[] lines Formatted comment lines
local function format_block_comment(response, style, indent)
  local lines = {}
  local block_start, block_end = style.block[1], style.block[2]

  -- Opening with [AI] marker
  table.insert(lines, indent .. block_start .. " " .. M.AI_MARKER)

  -- Normalize paragraphs (join lines within same paragraph)
  local paragraphs = normalize_paragraphs(response)

  -- Add paragraphs with wrapping
  for _, para in ipairs(paragraphs) do
    if para == "" then
      table.insert(lines, "")
    else
      local wrapped = wrap_text(para, MAX_LINE_WIDTH, indent)
      for _, wrapped_line in ipairs(wrapped) do
        table.insert(lines, wrapped_line)
      end
    end
  end

  -- Closing
  table.insert(lines, indent .. block_end)

  return lines
end

---Format response as line comments with [AI] marker (fallback for langs without block comments)
---@param response string Response text
---@param style table Comment style
---@param indent string Indentation to use
---@return string[] lines Formatted comment lines
local function format_line_comment(response, style, indent)
  local lines = {}
  local prefix = style.line .. " "
  local full_prefix = indent .. prefix

  -- First line with [AI] marker
  table.insert(lines, full_prefix .. M.AI_MARKER)

  -- Normalize paragraphs
  local paragraphs = normalize_paragraphs(response)

  for _, para in ipairs(paragraphs) do
    if para == "" then
      table.insert(lines, full_prefix)
    else
      local wrapped = wrap_text(para, MAX_LINE_WIDTH, full_prefix)
      for _, wrapped_line in ipairs(wrapped) do
        table.insert(lines, wrapped_line)
      end
    end
  end

  return lines
end

---Format response as comments with [AI] marker
---@param response string Response text
---@param bufnr? number Buffer number
---@param reference_line? number Line to get indentation from
---@return string[] lines Formatted comment lines
function M.format_response(response, bufnr, reference_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local style = M.get_style(bufnr)

  -- Get indentation from reference line
  local indent = ""
  if reference_line then
    local line_content = vim.api.nvim_buf_get_lines(bufnr, reference_line - 1, reference_line, false)[1]
    if line_content then
      indent = get_indent(line_content)
    end
  end

  -- Use block comment if available, otherwise line comment
  if style.block then
    return format_block_comment(response, style, indent)
  elseif style.line then
    return format_line_comment(response, style, indent)
  else
    -- Fallback: just return as-is with indent and marker
    local lines = { indent .. M.AI_MARKER }
    for line in response:gmatch("[^\n]*") do
      table.insert(lines, indent .. line)
    end
    return lines
  end
end

---Insert response as comment after a specific line
---@param response string Response text
---@param after_line number Line number to insert after (1-indexed)
---@param bufnr? number Buffer number
---@return boolean success
function M.insert_response(response, after_line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Format response as comments
  local comment_lines = M.format_response(response, bufnr, after_line)

  -- Insert blank line before response for readability
  table.insert(comment_lines, 1, "")

  -- Insert into buffer
  vim.api.nvim_buf_set_lines(bufnr, after_line, after_line, false, comment_lines)

  return true
end

---Check if a line starts an AI response block
---@param line string
---@param style table Comment style
---@return boolean
function M.is_ai_response_start(line, style)
  local marker = M.AI_MARKER:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")

  -- Check block comment with [AI] marker
  if style.block then
    local block_start = style.block[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    if line:match("^%s*" .. block_start .. "%s*" .. marker) then
      return true
    end
  end

  -- Check line comment with [AI] marker
  if style.line then
    local line_prefix = style.line:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    if line:match("^%s*" .. line_prefix .. "%s*" .. marker) then
      return true
    end
  end

  return false
end

---Find AI response block starting at or near a line
---@param bufnr number
---@param start_search_line number 1-indexed line to start searching from
---@return table|nil result { start_line, end_line, content }
function M.find_ai_response_block(bufnr, start_search_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local style = M.get_style(bufnr)

  -- Search down from start_search_line for AI response (within 5 lines)
  local response_start = nil
  for i = start_search_line, math.min(start_search_line + 5, #lines) do
    if M.is_ai_response_start(lines[i], style) then
      response_start = i
      break
    end
  end

  if not response_start then
    return nil
  end

  -- Find end of comment block
  local response_end = response_start

  if style.block then
    local block_end = style.block[2]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    for i = response_start, #lines do
      response_end = i
      if lines[i]:match(block_end .. "%s*$") then
        break
      end
    end
  elseif style.line then
    -- For line comments, find consecutive comment lines
    local line_prefix = style.line:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    for i = response_start + 1, #lines do
      if lines[i]:match("^%s*" .. line_prefix) then
        response_end = i
      else
        break
      end
    end
  end

  -- Extract content (strip comment markers and [AI] marker)
  local content_lines = {}
  for i = response_start, response_end do
    local line = lines[i]
    -- Remove block comment markers
    if style.block then
      line = line:gsub("^%s*" .. style.block[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%s*", "")
      line = line:gsub("%s*" .. style.block[2]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%s*$", "")
    end
    -- Remove line comment prefix
    if style.line then
      local line_prefix = style.line:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      line = line:gsub("^%s*" .. line_prefix .. "%s*", "")
    end
    -- Remove [AI] marker
    line = line:gsub("^%[AI%]%s*", "")
    table.insert(content_lines, line)
  end

  return {
    start_line = response_start,
    end_line = response_end,
    content = table.concat(content_lines, "\n"),
  }
end

---Remove existing AI response after a comment line
---@param comment_line number Line number of the user's comment (1-indexed)
---@param bufnr? number Buffer number
---@return number lines_removed Number of lines removed
function M.remove_existing_response(comment_line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Find AI response block
  local response = M.find_ai_response_block(bufnr, comment_line + 1)

  if not response then
    return 0
  end

  -- Also remove blank line before response if present
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_remove = response.start_line
  if start_remove > 1 and lines[start_remove - 1]:match("^%s*$") then
    start_remove = start_remove - 1
  end

  -- Remove the lines (0-indexed)
  vim.api.nvim_buf_set_lines(bufnr, start_remove - 1, response.end_line, false, {})

  return response.end_line - start_remove + 1
end

---Insert or replace response for a comment
---@param response string Response text
---@param comment_line number Line number of the user's comment (1-indexed)
---@param bufnr? number Buffer number
---@return boolean success
function M.insert_or_replace(response, comment_line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Remove existing response first
  M.remove_existing_response(comment_line, bufnr)

  -- Insert new response
  return M.insert_response(response, comment_line, bufnr)
end

-- =============================================================================
-- Streaming Support
-- =============================================================================

---@class StreamingState
---@field bufnr number Buffer number
---@field comment_line number User's comment line number
---@field start_line number Start line of inserted comment
---@field end_line number Current end line of comment
---@field style table Comment style
---@field indent string Indentation

---Start streaming response - inserts placeholder
---@param comment_line number Line number of the user's comment (1-indexed)
---@param bufnr? number Buffer number
---@return StreamingState state State object for updates
function M.start_streaming(comment_line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local style = M.get_style(bufnr)

  -- Remove existing response first
  M.remove_existing_response(comment_line, bufnr)

  -- Get indentation from comment line
  local line_content = vim.api.nvim_buf_get_lines(bufnr, comment_line - 1, comment_line, false)[1]
  local indent = line_content and line_content:match("^(%s*)") or ""

  -- Insert placeholder
  local placeholder_lines = { "" } -- blank line

  if style.block then
    table.insert(placeholder_lines, indent .. style.block[1] .. " " .. M.AI_MARKER)
    table.insert(placeholder_lines, indent .. "...")
    table.insert(placeholder_lines, indent .. style.block[2])
  elseif style.line then
    table.insert(placeholder_lines, indent .. style.line .. " " .. M.AI_MARKER)
    table.insert(placeholder_lines, indent .. style.line .. " ...")
  end

  vim.api.nvim_buf_set_lines(bufnr, comment_line, comment_line, false, placeholder_lines)

  return {
    bufnr = bufnr,
    comment_line = comment_line,
    start_line = comment_line + 1, -- after blank line
    end_line = comment_line + #placeholder_lines,
    style = style,
    indent = indent,
  }
end

---Update streaming response with new content
---@param state StreamingState State from start_streaming
---@param content string Full content so far (not just new chunk)
function M.update_streaming(state, content)
  if not state or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local lines = {}

  -- Normalize paragraphs
  local paragraphs = normalize_paragraphs(content)

  if state.style.block then
    -- Block comment format with [AI] marker
    table.insert(lines, state.indent .. state.style.block[1] .. " " .. M.AI_MARKER)

    for _, para in ipairs(paragraphs) do
      if para == "" then
        table.insert(lines, "")
      else
        local wrapped = wrap_text(para, MAX_LINE_WIDTH, state.indent)
        for _, wrapped_line in ipairs(wrapped) do
          table.insert(lines, wrapped_line)
        end
      end
    end

    table.insert(lines, state.indent .. state.style.block[2])
  elseif state.style.line then
    -- Line comment format with [AI] marker
    local prefix = state.style.line .. " "
    local full_prefix = state.indent .. prefix

    table.insert(lines, full_prefix .. M.AI_MARKER)

    for _, para in ipairs(paragraphs) do
      if para == "" then
        table.insert(lines, full_prefix)
      else
        local wrapped = wrap_text(para, MAX_LINE_WIDTH, full_prefix)
        for _, wrapped_line in ipairs(wrapped) do
          table.insert(lines, wrapped_line)
        end
      end
    end
  end

  -- Replace the comment block
  vim.api.nvim_buf_set_lines(state.bufnr, state.start_line, state.end_line, false, lines)

  -- Update end_line for next update
  state.end_line = state.start_line + #lines
end

---Finish streaming (cleanup if needed)
---@param state StreamingState State from start_streaming
function M.finish_streaming(state)
  -- Currently no cleanup needed
end

return M
