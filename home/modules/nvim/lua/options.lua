require "nvchad.options"

-- add yours here!

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

-- New Folding Solution
vim.api.nvim_create_autocmd("FileType", {
    callback = function()
        vim.wo.foldmethod = "expr"
        vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.wo.foldlevel = 99
        vim.cmd("silent! loadview")
    end,
})

-- Saves to viewdir when we close 
vim.api.nvim_create_autocmd("BufWinLeave", {
    pattern = "*",
    callback = function()
        vim.cmd("silent! mkview")
    end,
})

-- enables folding in viewdir
vim.opt.viewoptions:append("folds")
