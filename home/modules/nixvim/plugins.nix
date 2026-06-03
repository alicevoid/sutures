{ ... }:
{
  programs.nixvim.plugins = {

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
    which-key = {
      enable = true;
      settings.spec = [
        { __unkeyed-1 = "<leader>f"; group = "Find"; }
        { __unkeyed-1 = "<leader>l"; group = "LSP"; }
        { __unkeyed-1 = "<leader>h"; group = "Terminal (horizontal)"; }
        { __unkeyed-1 = "<leader>v"; group = "Terminal (vertical)"; }
        { __unkeyed-1 = "<leader>e"; group = "Explorer"; }
        { __unkeyed-1 = "<leader>x"; group = "Close buffer"; }
        { __unkeyed-1 = "<leader>r"; group = "Rename"; }
        { __unkeyed-1 = "<leader>c"; group = "Code action"; }
        { __unkeyed-1 = "<leader>D"; group = "Type definition"; }
        { __unkeyed-1 = "<leader>fm"; group = "Format"; }
      ];
    };

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

    # Linting
    lint = {
      enable = true;
      lintersByFt.python = [ "ruff" ];
    };

    # Terminal
    toggleterm = {
      enable = true;
      settings = {
        size = 15;
        shade_terminals = true;
        direction = "horizontal";
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
}
