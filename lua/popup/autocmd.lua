--------------------------------------------------------------------------------
-- Autocommands creation for popups.
--------------------------------------------------------------------------------

local api = vim.api
local curwin = api.nvim_get_current_win
local Popup

--- Create an autocommand for the popup and register it in the popup augroup.
---@param p table
---@param ev string
---@param au table
local function create(p, ev, au)
  au.group = p._.aug
  api.nvim_create_autocmd(ev, au)
end

--- Initialize augroup for this popup, also clearing autocommands previously
--- created by it. Create autocommands for popup callbacks.
--- This function should only run after the window has been created!
--- @param p table
local function on_show(p)
  -- defer this function because it's more reliable
  -- FIXME: no clue why it's needed
  vim.defer_fn(function()
    if not p:is_visible() then
      return
    end
    p._.aug = api.nvim_create_augroup("__VimUiPopup_" .. p.ID, { clear = true })

    -- redraw the popup on buffer change
    if p.autoresize then
      create(p, "TextChanged", {
        buffer = p.buf,
        callback = function(_) Popup.redraw(p) end,
      })
    end

    -- update position on cursor moved
    if p.follow then
      create(p, "CursorMoved", {
        buffer = p.bufbind,
        callback = function(_) Popup.redraw(p) end,
      })
    end

    -- if the window should be entered, make sure it actually is
    -- entering the window immediately is prevented by having p.bfn
    if p.enter and curwin() ~= p.win then
      api.nvim_set_current_win(p.win)
    end

    local hide_on = p.hide_on
      or (p.enter and { "WinLeave" })
      or (p.follow and { "CursorMovedI", "BufLeave" })
      or { "CursorMoved", "CursorMovedI", "BufLeave" }

    -- close popup on user-/predefined events
    if next(hide_on) then
      create(p, hide_on, {
        callback = function(_)
          p:hide_now()
          return true -- to delete the autocommand
        end,
      })
    end
  end, 0)
end

return function(p)
  Popup = p
  return {
    create = create,
    on_show = on_show,
  }
end
