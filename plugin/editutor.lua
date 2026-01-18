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

  local subcommand = opts.args

  if subcommand == "" or subcommand == "ask" then
    editutor.ask()
  elseif subcommand == "version" then
    vim.notify("ai-editutor v" .. editutor.version(), vim.log.levels.INFO)
  else
    vim.notify("Unknown command: " .. subcommand .. ". Use :Editutor ask", vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  complete = function()
    return { "ask", "version" }
  end,
  desc = "ai-editutor commands",
})
