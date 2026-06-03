{ pkgs, ... }:
{
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
      # Command mode shortcut
      { mode = "n"; key = ";"; action = ":"; options.desc = "Command mode"; }
      # Quick escape from insert
      { mode = "i"; key = "jk"; action = "<ESC>"; options.desc = "Escape insert mode"; }
      # Save
      { mode = [ "n" "i" "v" ]; key = "<C-s>"; action = "<cmd>w<CR>"; options.desc = "Save file"; }
      # Window navigation
      { mode = "n"; key = "<C-h>"; action = "<C-w>h"; options.desc = "Window left"; }
      { mode = "n"; key = "<C-j>"; action = "<C-w>j"; options.desc = "Window down"; }
      { mode = "n"; key = "<C-k>"; action = "<C-w>k"; options.desc = "Window up"; }
      { mode = "n"; key = "<C-l>"; action = "<C-w>l"; options.desc = "Window right"; }
      # Buffer management
      { mode = "n"; key = "<Tab>"; action = ":bnext<CR>"; options = { silent = true; desc = "Next buffer"; }; }
      { mode = "n"; key = "<S-Tab>"; action = ":bprev<CR>"; options = { silent = true; desc = "Prev buffer"; }; }
      { mode = "n"; key = "<leader>x"; action = ":bdelete<CR>"; options = { silent = true; desc = "Close buffer"; }; }
      # File tree
      { mode = "n"; key = "<leader>e"; action = ":NvimTreeToggle<CR>"; options = { silent = true; desc = "Toggle file tree"; }; }
      # Telescope
      { mode = "n"; key = "<leader>ff"; action = "<cmd>Telescope find_files<CR>"; options.desc = "Find files"; }
      { mode = "n"; key = "<leader>fg"; action = "<cmd>Telescope live_grep<CR>"; options.desc = "Live grep"; }
      { mode = "n"; key = "<leader>fb"; action = "<cmd>Telescope buffers<CR>"; options.desc = "Find buffers"; }
      { mode = "n"; key = "<leader>fh"; action = "<cmd>Telescope help_tags<CR>"; options.desc = "Help tags"; }
      { mode = "n"; key = "<leader>fo"; action = "<cmd>Telescope oldfiles<CR>"; options.desc = "Recent files"; }
      # Format
      { mode = [ "n" "v" ]; key = "<leader>fm"; action.__raw = "function() require('conform').format({ async = true }) end"; options.desc = "Format file"; }
      # Clear search highlight
      { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<CR>"; options.desc = "Clear search"; }
      # Better indent in visual mode (stay in visual after indent)
      { mode = "v"; key = "<"; action = "<gv"; options.desc = "Indent left"; }
      { mode = "v"; key = ">"; action = ">gv"; options.desc = "Indent right"; }
      # Move selected lines up/down
      { mode = "v"; key = "<A-j>"; action = ":m '>+1<CR>gv=gv"; options = { silent = true; desc = "Move selection down"; }; }
      { mode = "v"; key = "<A-k>"; action = ":m '<-2<CR>gv=gv"; options = { silent = true; desc = "Move selection up"; }; }
    ];

    # ── Plugins ───────────────────────────────────────────────────────────────
    plugins = {

      # Icons (required by many plugins)
      web-devicons.enable = true;

      # Statusline
      lualine = {
        enable = true;
        settings.options = {
          theme = "catppuccin";
          globalstatus = true;
          component_separators = { left = ""; right = ""; };
          section_separators = { left = ""; right = ""; };
        };
      };

      # Buffer / tab line
      bufferline = {
        enable = true;
        settings.options = {
          always_show_bufferline = false;
          separator_style = "slant";
          offsets = [
            {
              filetype = "NvimTree";
              text = "File Explorer";
              highlight = "Directory";
              separator = true;
            }
          ];
        };
      };

      # Dashboard
      alpha = {
        enable = true;
        theme = "dashboard";
      };

      # File explorer
      nvim-tree = {
        enable = true;
        settings = {
          view.width = 30;
          renderer.group_empty = true;
          filters.dotfiles = false;
          update_focused_file = {
            enable = true;
            update_cwd = true;
          };
        };
      };

      # Indent guides
      indent-blankline = {
        enable = true;
        settings = {
          indent.char = "│";
          scope.enabled = true;
        };
      };

      # Git decorations in the sign column
      gitsigns = {
        enable = true;
        settings.signs = {
          add.text = "│";
          change.text = "│";
          delete.text = "_";
          topdelete.text = "‾";
          changedelete.text = "~";
          untracked.text = "┆";
        };
      };

      # Keybinding hints popup
      which-key.enable = true;

      # Auto-close brackets/quotes
      nvim-autopairs = {
        enable = true;
        settings.check_ts = true;
      };

      # gcc / gc comment toggling
      comment.enable = true;

      # Fuzzy finder
      telescope = {
        enable = true;
        extensions.fzf-native.enable = true;
      };

      # Syntax highlighting & more
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
          auto_install = false;
        };
      };

      # Snippets
      friendly-snippets.enable = true;
      luasnip = {
        enable = true;
        fromVscode = [ { } ];
      };

      # Completion sources
      cmp-nvim-lsp.enable = true;
      cmp-buffer.enable = true;
      cmp-path.enable = true;
      cmp_luasnip.enable = true;

      # Completion engine
      cmp = {
        enable = true;
        settings = {
          snippet.expand.__raw = "function(args) require('luasnip').lsp_expand(args.body) end";
          mapping = {
            "<C-b>".__raw = "cmp.mapping.scroll_docs(-4)";
            "<C-f>".__raw = "cmp.mapping.scroll_docs(4)";
            "<C-Space>".__raw = "cmp.mapping.complete()";
            "<C-e>".__raw = "cmp.mapping.abort()";
            "<CR>".__raw = "cmp.mapping.confirm({ select = true })";
            "<Tab>".__raw = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
            "<S-Tab>".__raw = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
          };
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "buffer"; }
            { name = "path"; }
          ];
        };
      };

      # LSP — nixvim automatically provides each server's binary
      lsp = {
        enable = true;
        keymaps = {
          diagnostic = {
            "[d" = "goto_prev";
            "]d" = "goto_next";
            "<leader>ld" = "open_float";
          };
          lspBuf = {
            "gd" = "definition";
            "gD" = "declaration";
            "gr" = "references";
            "gi" = "implementation";
            "K" = "hover";
            "<leader>rn" = "rename";
            "<leader>ca" = "code_action";
            "<leader>D" = "type_definition";
          };
        };
        servers = {
          nil_ls.enable = true;
          html.enable = true;
          cssls.enable = true;
          svelte.enable = true;
          ts_ls.enable = true;
          basedpyright.enable = true;
        };
      };

      # Formatting
      conform-nvim = {
        enable = true;
        settings.formatters_by_ft = {
          lua = [ "stylua" ];
          nix = [ "nixfmt" ];
          python = [ "black" "ruff" ];
          css = [ "prettier" ];
          html = [ "prettier" ];
          javascript = [ "prettier" ];
          javascriptreact = [ "prettier" ];
          typescript = [ "prettier" ];
          typescriptreact = [ "prettier" ];
          svelte = [ "prettier" ];
          json = [ "prettier" ];
          yaml = [ "prettier" ];
          markdown = [ "prettier" ];
        };
      };
    };

    # ── Extra tools (formatters/linters not tied to an LSP server) ────────────
    # LSP server binaries (nil, html-lsp, etc.) are handled automatically
    # by plugins.lsp.servers above.
    extraPackages = with pkgs; [
      nixfmt
      statix
      stylua
      prettier
      black
      ruff
    ];

    # ── codecompanion (not yet a nixvim module) ───────────────────────────────
    extraPlugins = with pkgs.vimPlugins; [
      codecompanion-nvim
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
