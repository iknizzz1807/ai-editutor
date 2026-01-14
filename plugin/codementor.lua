-- plugin/codementor.lua
-- AI Code Mentor - Plugin entry point for lazy loading

if vim.g.loaded_codementor then
  return
end
vim.g.loaded_codementor = true

-- Defer loading until setup() is called
-- This allows users to configure the plugin in their lazy.nvim spec

-- Create the CodeMentor command that triggers lazy loading
vim.api.nvim_create_user_command("CodeMentor", function(opts)
  local codementor = require("codementor")

  -- If setup hasn't been called, call with defaults
  if not codementor._setup_called then
    codementor.setup()
    codementor._setup_called = true
  end

  local subcommand = opts.args

  if subcommand == "" or subcommand == "ask" then
    codementor.ask()
  elseif subcommand == "question" then
    codementor.ask_mode("question")
  elseif subcommand == "socratic" then
    codementor.ask_mode("socratic")
  elseif subcommand == "review" then
    codementor.ask_mode("review")
  elseif subcommand == "debug" then
    codementor.ask_mode("debug")
  elseif subcommand == "explain" then
    codementor.ask_mode("explain")
  elseif subcommand == "modes" then
    codementor.show_modes()
  elseif subcommand == "close" then
    require("codementor.ui").close()
  elseif subcommand == "version" then
    vim.notify("CodeMentor v" .. codementor.version(), vim.log.levels.INFO)
  else
    vim.notify("Unknown CodeMentor command: " .. subcommand, vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  complete = function()
    return { "ask", "question", "socratic", "review", "debug", "explain", "modes", "close", "version" }
  end,
  desc = "AI Code Mentor commands",
})
