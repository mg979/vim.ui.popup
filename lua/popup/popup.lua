--------------------------------------------------------------------------------
-- Popup methods
--------------------------------------------------------------------------------

local api = vim.api
local win_close = api.nvim_win_close
local reconfigure = api.nvim_win_set_config
local win_is_valid = api.nvim_win_is_valid
local buf_is_valid = api.nvim_buf_is_valid
local win_set_option = api.nvim_win_set_option
local defer_fn = vim.defer_fn
local themes = require("popup.themes")
local helpers = require("popup.helpers")
local do_wincfg = require("popup.wincfg")
local ms = function(s) return s * 1000 end
local H = require("popup.helpers")
local Pos = vim.ui.popup.pos

local function has_method(p, name)
  return p[name] and type(p[name]) == 'function'
end

local Popup = {}
local autocmd = require("popup.autocmd")(Popup)

--- Check if popup is visible.
---@return bool
function Popup:is_visible()
  return win_is_valid(self.win or -1)
end

--- Remove every information that the popup object holds.
function Popup:destroy()
  if has_method(self, "on_dispose") and self:on_dispose() then
    return self
  end
  self:hide()
  self = nil
end

--- Destroy the popup without waiting for the queue to process.
function Popup:destroy_now()
  self.queue:clear_queue()
  if has_method(self, "on_dispose") and self:on_dispose() then
    return self
  end
  --- bypasses queue, cannot use : notation.
  Popup.hide(self)
  self = nil
end

--- Hide the popup without waiting for the queue to process.
function Popup:hide_now()
  self.queue:clear_queue()
  --- bypasses queue, cannot use : notation.
  Popup.hide(self)
end

--- Show popup. This is the safe function to run to ensure a popup is correctly
--- displayed. It will reset blend level and theme (highlight groups).
function Popup:show(seconds)
  if not buf_is_valid(self.buf or -1) then
    self:destroy()
    error("Popup doesn't have a valid buffer.")
  end
  if not helpers.configure_popup(self) then
    return
  end
  autocmd.on_show(self)
  helpers.open_popup_win(self)
  -- reapply highlight groups
  H.call(themes.apply, self)
  -- reset blend level
  win_set_option(self.win, "winblend", self._.blend)
  if has_method(self, "on_show") then
    self:on_show()
  end
  if self.noqueue and seconds then
    defer_fn(function() self:hide() end, seconds * 1000)
  end
end

--- Hide popup. This is always called when the window is closed with a popup
--- method or autocommand, and also with popup.destroy_ns or popup.panic.
function Popup:hide(seconds)
  if win_is_valid(self.win or -1) then
    if has_method(self, "on_hide") and self:on_hide() then
      return
    end
    win_close(self.win, true)
  end
  pcall(api.nvim_del_augroup_by_id, self._.aug)
  -- TODO: self._ should be cleared, but it currently breaks too much stuff
  if self.noqueue and seconds then
    defer_fn(function() self:show() end, seconds * 1000)
  end
end

--- Redraw the popup, keeping its config unchanged. Cheaper than Popup.show.
--- It doesn't open a new window, it doesn't reset highlight or blend level.
function Popup:redraw()
  if not self.has_set_buf and self:is_visible() then
    reconfigure(self.win, do_wincfg(self))
  elseif self:is_visible() then
    self:show()
  end
end

--- Change configuration for the popup.
--- `opts.buf` can be a table with lines, or a buffer number.
---@param opts table
function Popup:configure(opts)
  if not opts then
    -- reconfigure the window, just in case
    reconfigure(self.win, do_wincfg(self))
  elseif opts.buf and opts.buf ~= self.buf then
    -- update buffer options, potentially deleting old ones
    self.bufopts = opts.bufopts
    -- set a new buffer for the popup
    if type(opts.buf) == "number" then
      self.has_set_buf = opts.buf
    else
      self.has_set_buf = helpers.create_buf(opts.buf, self.bufopts)
    end
    helpers.configure_popup(helpers.merge(self, opts))
  elseif not self:is_visible() then
    -- hidden, we cannot reconfigure only the window
    helpers.configure_popup(helpers.merge(self, opts))
    return
  else
    if opts.wincfg then
      -- if there is some other key, we cannot reconfigure only the window
      for k in pairs(opts) do
        if k ~= 'wincfg' then
          helpers.configure_popup(helpers.merge(self, opts))
          return
        end
      end
    end
    reconfigure(self.win, do_wincfg(helpers.merge(self, opts)))
  end
end

--- Show the popup at the top right corner of the screen.
---@param opts table
function Popup:notification(seconds)
  self.pos = Pos.EDITOR_TOPRIGHT
  if self.noqueue then self:show(seconds) end
end

--- Set winblend for popup window.
---@param val number
---@return table
function Popup:blend(val)
  if not val or not vim.o.termguicolors or not self:is_visible() then
    return
  end
  self._.blend = val < 0 and 0 or val > 100 and 100 or val
  win_set_option(self.win, "winblend", self._.blend)
end

--- Make the popup window fade out.
---@param for_seconds number: fading lasts n seconds
---@param endblend number: final winblend value (0-100)
---@return table
function Popup:fade(for_seconds, endblend)
  if not vim.o.termguicolors or not self:is_visible() then
    return
  end
  -- stop at full transparency by default
  endblend = endblend or 100

  self.queue.waiting = true
  local startblend = self._.blend
  if endblend <= startblend then
    return
  end
  -- step length is for_seconds / 100, 10ms for 1 second
  local steplen = (for_seconds or 1) * 0.01
  local steps = ms(for_seconds or 1) / steplen
  local stepblend = (endblend - startblend) / steps

  local b = require("popup.blend")
  local hi = api.nvim_set_hl

  local pb, pn, n = b.get("PopupBorder"), b.get("PopupNormal"), b.get("Normal")
  local blend_border = pb.bg ~= n.bg or pb.fg ~= n.bg
  local blend_popup  = pn.bg ~= n.bg or pn.fg ~= n.bg

  local function deferred_blend(delay, blend)
    defer_fn(function()
      if self:is_visible() then
        win_set_option(self.win, "winblend", blend)
        if blend_popup then
          hi(0, "PopupNormal", {
            bg = themes.PopupNormal.background, -- handled by winblend
            fg = b.blend_to_bg(blend, "PopupNormal", "Normal", true),
          })
        end
        if blend_border then
          hi(0, "PopupBorder", {
            bg = b.blend_to_bg(blend, "PopupBorder", "Normal", false),
            fg = b.blend_to_bg(blend, "PopupBorder", "Normal", true),
          })
        end
      end
      if delay >= steps * steplen then
        self.queue.waiting = false
        self.queue:proceed(self)
      end
    end, delay)
  end

  local curblend, f = startblend - 1, startblend
  for i = 1, steps do
    f = f + stepblend
    if math.floor(f) > curblend then
      curblend = math.floor(f)
      deferred_blend(steplen * i, curblend)
    end
  end
end

--- Print debug information about a popup value.
---@param key string|nil
function Popup:debug(key)
  if key then
    print(vim.inspect(self[key]))
  else
    print(vim.inspect(self))
  end
end

-- Dummy function, in case the method is called with the 'noqueue' option.
function Popup:wait(_)
  return self
end

return Popup
