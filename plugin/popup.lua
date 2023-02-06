-------------------------------------------------------------------------------
-- Description: generic popup helper for neovim
-- File:        popup.lua
-- Author:      Gianmaria Bajo <mg1979.git@gmail.com>
-- License:     MIT
-- Created:     Sun Feb  5 06:09:11 2023
-------------------------------------------------------------------------------

-- vim.ui.popup will be replaced with the full implementation in popup module
-- this is for lazy loading, also don't load if already defined
if not vim.ui.popup then
  vim.ui.popup = setmetatable({}, {
    __index = function(t, key)
      return require("popup")[key]
    end,
  })
end
