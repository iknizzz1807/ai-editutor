-- editutor/comment_writer.lua
-- Insert AI responses as inline comments

local M = {}

-- Comment syntax definitions by filetype
-- { line = "//", block = { "/*", "*/" } }
M.comment_styles = {
  -- C-style languages (prefer block comments)
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

---Format response as block comment
---@param response string Response text
---@param style table Comment style
---@param indent string Indentation to use
---@return string[] lines Formatted comment lines
local function format_block_comment(response, style, indent)
  local lines = {}
  local block_start, block_end = style.block[1], style.block[2]

  -- Opening
  table.insert(lines, indent .. block_start)

  -- Content - prefix with A:
  table.insert(lines, indent .. "A:")

  -- Add response lines
  for line in response:gmatch("[^\n]*") do
    if line == "" then
      table.insert(lines, "")
    else
      table.insert(lines, indent .. line)
    end
  end

  -- Closing
  table.insert(lines, indent .. block_end)

  return lines
end

---Format response as line comments
---@param response string Response text
---@param style table Comment style
---@param indent string Indentation to use
---@return string[] lines Formatted comment lines
local function format_line_comment(response, style, indent)
  local lines = {}
  local prefix = style.line .. " "

  -- First line with A: prefix
  local first = true

  for line in response:gmatch("[^\n]*") do
    if first then
      table.insert(lines, indent .. prefix .. "A: " .. line)
      first = false
    elseif line == "" then
      table.insert(lines, indent .. prefix)
    else
      table.insert(lines, indent .. prefix .. line)
    end
  end

  return lines
end

---Format response as comments
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
    -- Fallback: just return as-is with indent
    local lines = {}
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

---Remove existing response after a question line
---@param question_line number Line number of the question (1-indexed)
---@param bufnr? number Buffer number
---@return number lines_removed Number of lines removed
function M.remove_existing_response(question_line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local style = M.get_style(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total_lines = #lines

  -- Start checking from the line after the question
  local start_remove = question_line + 1
  local end_remove = question_line

  -- Skip blank line if present
  if start_remove <= total_lines and lines[start_remove]:match("^%s*$") then
    start_remove = start_remove + 1
    end_remove = question_line + 1
  end

  if start_remove > total_lines then
    return 0
  end

  local next_line = lines[start_remove]

  -- Check if it's a block comment response
  if style.block then
    local block_start = style.block[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    if next_line:match("^%s*" .. block_start) then
      -- Find the end of block comment
      local block_end = style.block[2]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      for i = start_remove, total_lines do
        end_remove = i
        if lines[i]:match(block_end .. "%s*$") then
          break
        end
      end
    end
  end

  -- Check if it's a line comment response starting with A:
  if style.line and end_remove == question_line then
    local line_prefix = style.line:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local pattern = "^%s*" .. line_prefix .. "%s*A:"
    if next_line:match(pattern) then
      end_remove = start_remove
      -- Find all consecutive comment lines
      for i = start_remove + 1, total_lines do
        local check_line = lines[i]
        if check_line:match("^%s*" .. line_prefix) then
          end_remove = i
        else
          break
        end
      end
    end
  end

  -- Remove the lines
  if end_remove > question_line then
    -- Also remove the blank line before if we added one
    local actual_start = question_line
    if lines[question_line + 1] and lines[question_line + 1]:match("^%s*$") then
      actual_start = question_line
    else
      actual_start = question_line
    end

    vim.api.nvim_buf_set_lines(bufnr, question_line, end_remove, false, {})
    return end_remove - question_line
  end

  return 0
end

---Insert or replace response for a question
---@param response string Response text
---@param question_line number Line number of the question (1-indexed)
---@param bufnr? number Buffer number
---@return boolean success
function M.insert_or_replace(response, question_line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Remove existing response first
  M.remove_existing_response(question_line, bufnr)

  -- Insert new response
  return M.insert_response(response, question_line, bufnr)
end

return M
