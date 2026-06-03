{ pkgs, ... }:
{
  imports = [ ./plugins.nix ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    # ── Theme ────────────────────────────────────────────────────────────────
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "mocha";
        integrations = {
          bufferline = true;
          cmp = true;
          gitsigns = true;
          indent_blankline.enabled = true;
          nvimtree = true;
          telescope.enabled = true;
          treesitter = true;
          which_key = true;
          native_lsp = {
            enabled = true;
            virtual_text = {
              errors = [ "italic" ];
              hints = [ "italic" ];
              warnings = [ "italic" ];
              information = [ "italic" ];
            };
          };
        };
      };
    };

    # ── Options ───────────────────────────────────────────────────────────────
    opts = {
      number = true;
      relativenumber = true;
      cursorline = true;
      signcolumn = "yes";
      tabstop = 2;
      shiftwidth = 2;
      expandtab = true;
      smartindent = true;
      wrap = false;
      scrolloff = 8;
      sidescrolloff = 8;
      termguicolors = true;
      clipboard = "unnamedplus";
      mouse = "a";
      undofile = true;
      splitbelow = true;
      splitright = true;
      updatetime = 250;
      timeoutlen = 300;
      completeopt = [ "menu" "menuone" "noselect" ];
      viewoptions = "folds,cursor,curdir";
    };

    globals = {
      mapleader = " ";
      maplocalleader = " ";
    };

    # ── Autocommands ─────────────────────────────────────────────────────────
    autoCmd = [
      # Treesitter-based folding, preserved across sessions
      {
        event = [ "FileType" ];
        callback.__raw = ''
          function()
            vim.wo.foldmethod = "expr"
            vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
            vim.wo.foldlevel = 99
            vim.cmd("silent! loadview")
          end
        '';
      }
      {
        event = [ "BufWinLeave" ];
        pattern = [ "*" ];
        callback.__raw = ''
          function()
            vim.cmd("silent! mkview")
          end
        '';
      }
    ];

    # ── Keymaps ───────────────────────────────────────────────────────────────
    keymaps = [
      { mode = "n"; key = ";"; action = ":"; options.desc = "Command mode"; }
      { mode = "i"; key = "jk"; action = "<ESC>"; options.desc = "Escape insert mode"; }
      { mode = [ "n" "i" "v" ]; key = "<C-s>"; action = "<cmd>w<CR>"; options.desc = "Save file"; }
      { mode = "n"; key = "<C-h>"; action = "<C-w>h"; options.desc = "Window left"; }
      { mode = "n"; key = "<C-j>"; action = "<C-w>j"; options.desc = "Window down"; }
      { mode = "n"; key = "<C-k>"; action = "<C-w>k"; options.desc = "Window up"; }
      { mode = "n"; key = "<C-l>"; action = "<C-w>l"; options.desc = "Window right"; }
      { mode = "n"; key = "<Tab>"; action = ":bnext<CR>"; options = { silent = true; desc = "Next buffer"; }; }
      { mode = "n"; key = "<S-Tab>"; action = ":bprev<CR>"; options = { silent = true; desc = "Prev buffer"; }; }
      {
        mode = "n";
        key = "<leader>x";
        options = { silent = true; desc = "Close buffer"; };
        action.__raw = ''
          function()
            if vim.bo.buftype == "terminal" then
              vim.cmd("bdelete!")
              return
            end
            local cur = vim.api.nvim_get_current_buf()
            local others = vim.tbl_filter(function(b)
              return b.listed == 1
                and b.bufnr ~= cur
                and vim.bo[b.bufnr].filetype ~= "NvimTree"
            end, vim.fn.getbufinfo({ buflisted = 1 }))
            if #others > 0 then
              vim.api.nvim_set_current_buf(others[1].bufnr)
            end
            vim.cmd("bdelete " .. cur)
          end
        '';
      }
      { mode = "n"; key = "<leader>e"; action = ":NvimTreeFocus<CR>"; options = { silent = true; desc = "Toggle file tree"; }; }
      { mode = "n"; key = "<C-n>"; action = ":NvimTreeToggle<CR>"; options = { silent = true; desc = "Toggle file tree"; }; }
      # Terminal
      { mode = "n"; key = "<leader>h"; action = "<cmd>ToggleTerm direction=horizontal<CR>"; options = { silent = true; desc = "Horizontal terminal"; }; }
      { mode = "n"; key = "<leader>v"; action = "<cmd>ToggleTerm direction=vertical<CR>"; options = { silent = true; desc = "Vertical terminal"; }; }
      { mode = "n"; key = "<leader>ff"; action = "<cmd>Telescope find_files<CR>"; options.desc = "Find files"; }
      { mode = "n"; key = "<leader>fg"; action = "<cmd>Telescope live_grep<CR>"; options.desc = "Live grep"; }
      { mode = "n"; key = "<leader>fb"; action = "<cmd>Telescope buffers<CR>"; options.desc = "Find buffers"; }
      { mode = "n"; key = "<leader>fh"; action = "<cmd>Telescope help_tags<CR>"; options.desc = "Help tags"; }
      { mode = "n"; key = "<leader>fo"; action = "<cmd>Telescope oldfiles<CR>"; options.desc = "Recent files"; }
      { mode = [ "n" "v" ]; key = "<leader>fm"; action.__raw = "function() require('conform').format({ async = true }) end"; options.desc = "Format file"; }
      { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<CR>"; options.desc = "Clear search"; }
      { mode = "v"; key = "<"; action = "<gv"; options.desc = "Indent left"; }
      { mode = "v"; key = ">"; action = ">gv"; options.desc = "Indent right"; }
      { mode = "v"; key = "<A-j>"; action = ":m '>+1<CR>gv=gv"; options = { silent = true; desc = "Move selection down"; }; }
      { mode = "v"; key = "<A-k>"; action = ":m '<-2<CR>gv=gv"; options = { silent = true; desc = "Move selection up"; }; }
    ];

    # ── Extra tools (formatters/linters not tied to an LSP server) ────────────
    extraPackages = with pkgs; [
      nixfmt
      statix
      stylua
      prettier
      black
      ruff
    ];

    # ── Extra plugins (not yet wrapped as nixvim modules) ─────────────────────
    extraPlugins = with pkgs.vimPlugins; [
      codecompanion-nvim
      markdown-preview-nvim
    ];

    extraConfigLua = ''
      require("codecompanion").setup({
        adapters = {
          anthropic = require("codecompanion.adapters").extend("anthropic", {
            env = { api_key = "ANTHROPIC_API_KEY" },
          }),
        },
        strategies = {
          chat = { adapter = "anthropic" },
          inline = { adapter = "anthropic" },
        },
      })
    '';
  };
}
