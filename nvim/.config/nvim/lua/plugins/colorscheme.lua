return {
  {
    "Mofiqul/vscode.nvim",
    lazy = true,
    opts = {
      transparent = false,
      italic_comments = false,
      disable_nvimtree_bg = true,
      group_overrides = {
        Normal = { bg = "#000000" },
        NormalFloat = { bg = "#000000" },
        FloatBorder = { bg = "#000000" },
        SignColumn = { bg = "#000000" },
        LineNr = { bg = "#000000" },
        CursorLineNr = { bg = "#000000" },
        EndOfBuffer = { bg = "#000000" },
        StatusLine = { bg = "#000000" },
        StatusLineNC = { bg = "#000000" },
        VertSplit = { bg = "#000000" },
        WinSeparator = { bg = "#000000" },
        NormalNC = { bg = "#000000" },
        FoldColumn = { bg = "#000000" },
        NeoTreeNormal = { bg = "#000000" },
        NeoTreeNormalNC = { bg = "#000000" },
        SnacksNormal = { bg = "#000000" },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "vscode",
    },
  },
}
