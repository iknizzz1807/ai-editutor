-- editutor/parser.lua
-- Comment parsing for ai-editutor
-- Detects comments near cursor and AI responses

local M = {}

-- Comment styles by filetype
M.COMMENT_STYLES = {
  -- C-style: // and /* */
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

  -- Hash-style: #
  python = { line = "#", block = { '"""', '"""' } },
  ruby = { line = "#", block = { "=begin", "=end" } },
  sh = { line = "#", block = nil },
  bash = { line = "#", block = nil },
  zsh = { line = "#", block = nil },
  yaml = { line = "#", block = nil },
  toml = { line = "#", block = nil },
  dockerfile = { line = "#", block = nil },

  -- Dash-style: --
  lua = { line = "--", block = { "--[[", "]]" } },
  sql = { line = "--", block = { "/*", "*/" } },
  haskell = { line = "--", block = { "{-", "-}" } },

  -- HTML/XML: <!-- -->
  html = { line = nil, block = { "<!--", "-->" } },
  xml = { line = nil, block = { "<!--", "-->" } },
  vue = { line = "//", block = { "<!--", "-->" } },
  svelte = { line = "//", block = { "<!--", "-->" } },

  -- Lisp-style: ;
  lisp = { line = ";", block = { "#|", "|#" } },
  clojure = { line = ";", block = nil },

  -- Other
  vim = { line = '"', block = nil },
  tex = { line = "%", block = nil },
  latex = { line = "%", block = nil },
}

M.DEFAULT_STYLE = { line = "//", block = { "/*", "*/" } }

-- AI response marker
M.AI_RESPONSE_MARKER = "[AI]"

---Get comment style for filetype
---@param bufnr? number
---@return table style
function M.get_comment_style(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  return M.COMMENT_STYLES[ft] or M.DEFAULT_STYLE
end

---Check if line is a comment
---@param line string
---@param style table
---@return boolean is_comment
---@return string|nil content Content without comment prefix
function M.is_comment(line, style)
  local trimmed = line:match("^%s*(.-)%s*$")
  
  -- Check line comment
  if style.line then
    local prefix = style.line:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local content = trimmed:match("^" .. prefix .. "%s*(.*)$")
    if content then
      return true, content
    end
  end
  
  -- Check block comment start
  if style.block then
    local block_start = style.block[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    if trimmed:match("^" .. block_start) then
      return true, trimmed
    end
  end
  
  return false, nil
end

---Check if line starts an AI response block
---@param line string
---@param style table
---@return boolean
function M.is_ai_response_start(line, style)
  if not style.block then return false end
  
  local block_start = style.block[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  local marker = M.AI_RESPONSE_MARKER:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  
  -- Match: /* [AI] or /*[AI]
  return line:match("^%s*" .. block_start .. "%s*" .. marker) ~= nil
end

---Find the nearest comment line to cursor that looks like a question/request
---@param bufnr? number
---@return table|nil result { line_num, content, cursor_line }
function M.find_question_near_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local style = M.get_comment_style(bufnr)
  
  -- Search pattern: current line, then up/down alternating
  local search_order = { cursor_line }
  for i = 1, 15 do
    if cursor_line - i >= 1 then
      table.insert(search_order, cursor_line - i)
    end
    if cursor_line + i <= #lines then
      table.insert(search_order, cursor_line + i)
    end
  end
  
  for _, line_num in ipairs(search_order) do
    local line = lines[line_num]
    local is_comment, content = M.is_comment(line, style)
    
    if is_comment and content and content ~= "" then
      -- Skip if this is an AI response
      if M.is_ai_response_start(line, style) then
        goto continue
      end
      
      -- Skip if next non-empty line is an AI response (already answered)
      local has_response = false
      for offset = 1, 5 do
        local check_line = lines[line_num + offset]
        if check_line then
          if not check_line:match("^%s*$") then
            if M.is_ai_response_start(check_line, style) then
              has_response = true
            end
            break
          end
        end
      end
      
      if not has_response then
        return {
          line_num = line_num,
          content = content,
          cursor_line = cursor_line,
        }
      end
    end
    
    ::continue::
  end
  
  return nil
end

---Find AI response block at or near a line
---@param bufnr number
---@param start_line number 1-indexed
---@return table|nil result { start_line, end_line, content }
function M.find_ai_response_block(bufnr, start_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local style = M.get_comment_style(bufnr)
  
  if not style.block then return nil end
  
  -- Search down from start_line for AI response
  local response_start = nil
  for i = start_line, math.min(start_line + 5, #lines) do
    if M.is_ai_response_start(lines[i], style) then
      response_start = i
      break
    end
  end
  
  if not response_start then return nil end
  
  -- Find end of block comment
  local block_end = style.block[2]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  local response_end = response_start
  
  for i = response_start, #lines do
    if lines[i]:match(block_end .. "%s*$") then
      response_end = i
      break
    end
  end
  
  -- Extract content (strip comment markers)
  local content_lines = {}
  for i = response_start, response_end do
    local line = lines[i]
    -- Remove block comment markers and [AI] marker
    line = line:gsub("^%s*" .. style.block[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%s*", "")
    line = line:gsub("%s*" .. style.block[2]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%s*$", "")
    line = line:gsub("^%[AI%]%s*", "")
    table.insert(content_lines, line)
  end
  
  return {
    start_line = response_start,
    end_line = response_end,
    content = table.concat(content_lines, "\n"),
  }
end

---Get visual selection
---@return table|nil { start_line, end_line, text }
function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  local start_line = start_pos[2]
  local end_line = end_pos[2]
  
  if start_line == 0 or end_line == 0 or start_line > end_line then
    return nil
  end
  
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  
  return {
    start_line = start_line,
    end_line = end_line,
    text = table.concat(lines, "\n"),
  }
end

return M
