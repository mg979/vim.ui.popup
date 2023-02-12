--------------------------------------------------------------------------------
-- Description: Utilities for vim.ui.popup
-- File:        util.lua
-- Author:      Gianmaria Bajo <mg1979.git@gmail.com>
-- License:     MIT
-- Created:     Sun Feb 12 15:58:05 2023
--------------------------------------------------------------------------------

local api = vim.api
local M = {}

M.aug = api.nvim_create_augroup("PopupHlts", { clear = true })
M.ns = api.nvim_create_namespace("VimPopupUi")


return M
