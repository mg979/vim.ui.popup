--------------------------------------------------------------------------------
-- Description: Popup themes
-- File:        themes.lua
-- Author:      Gianmaria Bajo <mg1979.git@gmail.com>
-- License:     MIT
-- Created:     Sun Feb 12 15:04:40 2023
--------------------------------------------------------------------------------

local api = vim.api
local win_set_hl = api.nvim_win_set_hl_ns
local hi = api.nvim_set_hl
local u = require("popup.util")

local M = { winhighlight = "" }

-- Reset on colorscheme change.
api.nvim_create_autocmd("Colorscheme", {
  group = u.aug,
  callback = function(_) pcall(M[M.current]) end
})

-- Default highlight links
local links = {
  PopupNormal = "NormalFloat",
  PopupBorder = "FloatBorder",
  PopupConstant = "Constant",
  PopupComment = "Comment",
  PopupGutter = "LineNr",
}

-- Define groups globally too, so that 'winhighlight' can use them.
for k, v in pairs(links) do
  hi(0, k, { link = v })
end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

--- Create default highlight links.
function M.default()
  -- we link our groups to the default groups
  -- when blending we need to modify our groups without modifying the original
  for k, v in pairs(links) do
    hi(u.ns, k, { link = v })
  end
  -- currently we actually use winhighlight, not the namespace (it's 0)
  local wh = {}
  for k, v in pairs(links) do
    table.insert(wh, v .. ":" .. k)
  end
  M.winhighlight = table.concat(wh, ",")
  M.current = "default"
end

-- Set defaults right away
M.default()

--- Apply highlight namespace to popup window.
--- Skip if the popup has defined its own window highlights.
---@param win number: window-ID
function M.apply(p)
  if not p.winopts.winhighlight then
    local th = p.theme or "default"
    if th ~= M.current then
      pcall(M[th])
      M.current = th
    end
    -- win_set_hl(win, u.ns)
    api.nvim_win_set_option(p.win, 'winhighlight', M.winhighlight)
  end
end

function M.reset(p)
  if not p.winopts.winhighlight then
    pcall(M[p.theme or "default"])
  end
end

function M.get_hl(name)
  return api.nvim_get_hl_by_name(name, vim.o.termguicolors)
end

-- Access the table like themes.Normal to get the Normal highlight group
-- definition.
return setmetatable(M, {
  __index = function(t, k)
    return t.get_hl(k)
  end
})