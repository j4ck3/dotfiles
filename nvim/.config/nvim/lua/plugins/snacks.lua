return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        -- Substring matching only: "actions" matches "actions.ts", not "someACtinTIONSglse"
        matcher = {
          fuzzy = false,
        },
        sources = {
          explorer = {
            exclude = { "node_modules" },
            hidden = true,
            ignored = true,
          },
          files = {
            exclude = { "node_modules" },
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },
}
