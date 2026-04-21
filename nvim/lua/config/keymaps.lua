-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set({ "i", "c" }, "<C-v>", "<C-r>+", { desc = "Paste from system clipboard" })
vim.keymap.set("v", "<C-c>", '"+y', { desc = "Copy selection to system clipboard" })
