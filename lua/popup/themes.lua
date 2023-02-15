--------------------------------------------------------------------------------
-- Popup themes
--------------------------------------------------------------------------------

local api = vim.api
local hi = api.nvim_set_hl

local M = { winhighlight = "" }

M.aug = api.nvim_create_augroup("PopupHlts", { clear = true })

-- Reset on colorscheme change.
api.nvim_create_autocmd("Colorscheme", {
  group = M.aug,
  callback = function(_) M.default() end,
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
    hi(0, k, { link = v })
  end
  -- currently we actually use winhighlight, not the namespace (it's 0)
  local wh = {}
  for k, v in pairs(links) do
    table.insert(wh, v .. ":" .. k)
  end
  M.winhighlight = table.concat(wh, ",")
end

-- Set defaults right away
M.default()

--- Apply highlight namespace to popup window.
--- Skip if the popup has defined its own window highlights.
---@param win number: window-ID
function M.apply(p)
  if p.winopts and not p.winopts.winhighlight then
    pcall(M[p.theme or "default"])
    api.nvim_win_set_option(p.win, 'winhighlight', M.winhighlight)
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
