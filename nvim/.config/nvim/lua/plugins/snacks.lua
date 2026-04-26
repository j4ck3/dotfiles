return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
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
