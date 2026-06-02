require("codecompanion").setup({
  adapters = {
    anthropic = require("codecompanion.adapters").extend("anthropic", {
      env = {
        api_key = "ANTHROPIC_API_KEY",
      },
    }),
  },
  strategies = {
    chat = { adapter = "anthropic" },
    inline = { adapter = "anthropic" },
  },
})
