-- plugin/editutor.lua
-- ai-editutor v1.2.0 - Plugin entry point for lazy loading

if vim.g.loaded_editutor then
  return
end
vim.g.loaded_editutor = true

-- Defer loading until setup() is called
-- This allows users to configure the plugin in their lazy.nvim spec

-- Create the main command that triggers lazy loading
vim.api.nvim_create_user_command("Editutor", function(opts)
  local editutor = require("editutor")

  -- If setup hasn't been called, call with defaults
  if not editutor._setup_called then
    editutor.setup()
    editutor._setup_called = true
  end

  local raw_args = vim.trim(opts.args or "")
  local parts = vim.split(raw_args, "%s+")
  local subcommand = parts[1] or ""
  local rest_args = #parts > 1 and table.concat(vim.list_slice(parts, 2), " ") or nil

  if subcommand == "" or subcommand == "ask" then
    editutor.ask()
  elseif subcommand == "question" then
    editutor.spawn_question()
  elseif subcommand == "code" then
    editutor.spawn_code()
  elseif subcommand == "execute" then
    editutor.execute()
  elseif subcommand == "search" then
    if rest_args and #rest_args > 0 then
      editutor.search(rest_args)
    else
      editutor.search_blank()
    end
  elseif subcommand == "smartfix" or subcommand == "fix" then
    editutor.smart_fix(rest_args)
  elseif subcommand == "version" then
    vim.notify("ai-editutor v" .. editutor.version(), vim.log.levels.INFO)
  else
    vim.notify("Unknown command: " .. subcommand .. ". Available: ask, question, code, execute, search, fix, version", vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function()
    return { "ask", "question", "code", "execute", "search", "smartfix", "fix", "version" }
  end,
  desc = "ai-editutor commands",
})
