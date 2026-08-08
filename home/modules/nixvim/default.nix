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
      mouse = "nvi";
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
      # Comment toggle
      { mode = "n"; key = "<leader>/"; action.__raw = "function() require('Comment.api').toggle.linewise.current() end"; options = { silent = true; desc = "Toggle comment"; }; }
      { mode = "v"; key = "<leader>/"; action.__raw = "function() require('Comment.api').toggle.linewise(vim.fn.visualmode()) end"; options = { silent = true; desc = "Toggle comment"; }; }
      # Copy entire file to system clipboard
      { mode = "n"; key = "<C-c>"; action = "<cmd>%y+<CR>"; options = { silent = true; desc = "Copy file to clipboard"; }; }
      # Surround toggles (visual selection)
      { mode = "v"; key = "<leader>s("; action.__raw = ''function() SurroundToggle("(", ")") end''; options = { silent = true; desc = "Toggle ()"; }; }
      { mode = "v"; key = "<leader>s["; action.__raw = ''function() SurroundToggle("[", "]") end''; options = { silent = true; desc = "Toggle []"; }; }
      { mode = "v"; key = "<leader>s{"; action.__raw = ''function() SurroundToggle("{", "}") end''; options = { silent = true; desc = "Toggle {}"; }; }
      { mode = "v"; key = "<leader>s,"; action.__raw = ''function() SurroundToggle(",", ",") end''; options = { silent = true; desc = "Toggle ,,"; }; }
      # LSP diagnostics toggle
      { mode = "n"; key = "<leader>lt"; action.__raw = "function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end"; options = { silent = true; desc = "Toggle diagnostics"; }; }
      # Cheatsheet
      { mode = "n"; key = "<leader>?"; action = "<cmd>Cheatsheet<CR>"; options = { silent = true; desc = "Cheatsheet"; }; }
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
      -- ── Cheatsheet ────────────────────────────────────────────────────────────
      -- Add / remove entries here. Each section is { section = "Name", entries = { { "keys", "desc" }, ... } }
      local _cheatsheet = {
        { section = "LSP", entries = {
          { "gd",           "Go to definition" },
          { "gD",           "Go to declaration" },
          { "gr",           "References" },
          { "gi",           "Implementation" },
          { "K",            "Hover docs" },
          { "<leader>rn",   "Rename symbol" },
          { "<leader>ca",   "Code action" },
          { "<leader>D",    "Type definition" },
          { "<leader>ld",   "Diagnostic float" },
          { "[d / ]d",      "Prev / next diagnostic" },
          { "<leader>lt",   "Toggle diagnostics" },
        }},
        { section = "Navigation", entries = {
          { "<leader>ff",   "Find files" },
          { "<leader>fg",   "Live grep" },
          { "<leader>fb",   "Find buffers" },
          { "<leader>fo",   "Recent files" },
          { "<leader>fh",   "Help tags" },
          { "<Tab>",        "Next buffer" },
          { "<S-Tab>",      "Prev buffer" },
          { "<leader>x",    "Close buffer" },
        }},
        { section = "Windows", entries = {
          { "<C-w>s",       "Split horizontal" },
          { "<C-w>v",       "Split vertical" },
          { "<C-w>q",       "Close split" },
          { "<C-w>o",       "Unsplit (close other splits)" },
          { "<C-h/j/k/l>",  "Navigate windows" },
        }},
        { section = "Editing", entries = {
          { "<leader>/",    "Toggle comment" },
          { "<C-c>",        "Copy file to clipboard" },
          { "<leader>s(",   "Toggle () around selection" },
          { "<leader>s[",   "Toggle [] around selection" },
          { "<leader>s{",   "Toggle {} around selection" },
          { "<leader>s,",   "Toggle ,, around selection" },
          { "<leader>fm",   "Format file / selection" },
          { "< / >",        "Indent left / right (visual)" },
          { "<A-j/k>",      "Move selection up / down" },
        }},
        { section = "File Tree", entries = {
          { "<C-n>",        "Toggle file tree" },
          { "<leader>e",    "Focus file tree" },
        }},
        { section = "Terminal", entries = {
          { "<leader>h",    "Horizontal terminal" },
          { "<leader>v",    "Vertical terminal" },
        }},
        { section = "General", entries = {
          { ";",            "Command mode" },
          { "jk",           "Escape insert mode" },
          { "<C-s>",        "Save file" },
          { "<Esc>",        "Clear search highlight" },
          { "<leader>?",    "Open cheatsheet" },
        }},
      }

      vim.api.nvim_create_user_command("Cheatsheet", function()
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf    = require("telescope.config").values
        local display = require("telescope.pickers.entry_display")

        local displayer = display.create({
          separator = "  ",
          items = { { width = 20 }, { width = 14 }, { remaining = true } },
        })

        local rows = {}
        for _, group in ipairs(_cheatsheet) do
          for _, e in ipairs(group.entries) do
            table.insert(rows, { keys = e[1], section = group.section, desc = e[2] })
          end
        end

        pickers.new({}, {
          prompt_title = "Cheatsheet",
          finder = finders.new_table({
            results = rows,
            entry_maker = function(e)
              return {
                value   = e,
                ordinal = e.keys .. " " .. e.section .. " " .. e.desc,
                display = function(entry)
                  return displayer({
                    { entry.value.keys,    "TelescopeResultsIdentifier" },
                    { entry.value.section, "TelescopeResultsComment" },
                    entry.value.desc,
                  })
                end,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          layout_config = { width = 0.55, height = 0.65 },
          attach_mappings = function(prompt_bufnr)
            local actions = require("telescope.actions")
            -- The entries are reference rows, not files. Replace the default
            -- <CR> action (which tries to :edit the entry and errors on the
            -- function-valued `display`) with a plain close.
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
            end)
            return true
          end,
        }):find()
      end, {})

      local function _surround_toggle(open, close)
        local s = vim.api.nvim_buf_get_mark(0, "<")
        local e = vim.api.nvim_buf_get_mark(0, ">")
        local sr, sc = s[1] - 1, s[2]
        local er, ec = e[1] - 1, e[2]
        local sl = vim.api.nvim_buf_get_lines(0, sr, sr + 1, false)[1] or ""
        local el = vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or ""
        local before = sc > 0 and sl:sub(sc, sc) or ""
        local after = el:sub(ec + 2, ec + 2)
        if before == open and after == close then
          vim.api.nvim_buf_set_text(0, er, ec + 1, er, ec + 2, {})
          vim.api.nvim_buf_set_text(0, sr, sc - 1, sr, sc, {})
        else
          vim.api.nvim_buf_set_text(0, er, ec + 1, er, ec + 1, { close })
          vim.api.nvim_buf_set_text(0, sr, sc, sr, sc, { open })
        end
      end
      _G.SurroundToggle = _surround_toggle

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
