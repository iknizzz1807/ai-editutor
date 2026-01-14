-- plugin/editutor.lua
-- AI EduTutor - Plugin entry point for lazy loading

if vim.g.loaded_editutor then
  return
end
vim.g.loaded_editutor = true

-- Defer loading until setup() is called
-- This allows users to configure the plugin in their lazy.nvim spec

-- Create the EduTutor command that triggers lazy loading
vim.api.nvim_create_user_command("EduTutor", function(opts)
  local editutor = require("editutor")

  -- If setup hasn't been called, call with defaults
  if not editutor._setup_called then
    editutor.setup()
    editutor._setup_called = true
  end

  local subcommand = opts.args

  if subcommand == "" or subcommand == "ask" then
    editutor.ask()
  elseif subcommand == "question" then
    editutor.ask_mode("question")
  elseif subcommand == "socratic" then
    editutor.ask_mode("socratic")
  elseif subcommand == "review" then
    editutor.ask_mode("review")
  elseif subcommand == "debug" then
    editutor.ask_mode("debug")
  elseif subcommand == "explain" then
    editutor.ask_mode("explain")
  elseif subcommand == "modes" then
    editutor.show_modes()
  elseif subcommand == "close" then
    require("editutor.ui").close()
  elseif subcommand == "version" then
    vim.notify("EduTutor v" .. editutor.version(), vim.log.levels.INFO)
  else
    vim.notify("Unknown EduTutor command: " .. subcommand, vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  complete = function()
    return { "ask", "question", "socratic", "review", "debug", "explain", "modes", "close", "version" }
  end,
  desc = "AI EduTutor commands",
})
