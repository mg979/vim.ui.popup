--------------------------------------------------------------------------------
-- Popup methods
--------------------------------------------------------------------------------

local U = require("popup.util")
local api = U.api
local defer_fn = vim.defer_fn
local themes = require("popup.themes")
local do_wincfg = require("popup.wincfg").do_wincfg
local update_wincfg = require("popup.wincfg").update_wincfg
local ms = function(s) return s * 1000 end
local H = require("popup.helpers")
local Pos = require("popup.wincfg").Pos

local function has_method(p, name)
  return p[name] and type(p[name]) == 'function'
end

local Popup = {}
local autocmd = require("popup.autocmd")(Popup)

--- Check if popup is visible.
---@return bool
function Popup:is_visible()
  return api.win_is_valid(self.win or -1)
end

--- Remove every information that the popup object holds.
function Popup:destroy()
  if has_method(self, "on_dispose") and self:on_dispose() then
    return
  end
  self:hide()
  if U.is_temp_buffer(self.buf) then
    api.buf_delete(self.buf)
  end
end

--- Destroy the popup without waiting for the queue to process.
function Popup:destroy_now()
  self.queue:clear_queue()
  if has_method(self, "on_dispose") and self:on_dispose() then
    return
  end
  --- bypasses queue, cannot use : notation.
  Popup.hide(self)
  if U.is_temp_buffer(self.buf) then
    api.buf_delete(self.buf)
  end
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
  if self.bfn then
    self.buf = H.buf_from_func(self)
  end
  if not api.buf_is_valid(self.buf or -1) then
    self:destroy()
    error("Popup doesn't have a valid buffer.")
  end
  if not H.configure_popup(self) then
    self:destroy()
    return
  end
  autocmd.on_show(self)
  if not H.open_popup_win(self) then
    self:destroy()
    return
  end
  -- reapply highlight groups
  H.call(themes.apply, self)
  -- reset blend level
  api.win_set_option(self.win, "winblend", self._.blend)
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
  if api.win_is_valid(self.win or -1) then
    if has_method(self, "on_hide") and self:on_hide() then
      return
    end
    update_wincfg(self)
    api.win_close(self.win, true)
  end
  pcall(api.del_augroup_by_id, self._.aug)
  -- TODO: self._ should be cleared, but it currently breaks too much stuff
  if self.noqueue and seconds then
    defer_fn(function() self:show() end, seconds * 1000)
  end
end

--- Redraw the popup, keeping its config unchanged. Cheaper than Popup.show.
--- It doesn't open a new window, it doesn't reset highlight or blend level.
function Popup:redraw()
  if not self.has_set_buf and self:is_visible() then
    api.win_set_config(self.win, do_wincfg(self))
    api.win_set_cursor(self.win, { 1, 0 })
  elseif self:is_visible() then
    H.configure_popup(self)
  end
end

--- Change configuration for the popup.
--- `opts.buf` can be a table with lines, or a buffer number.
---@param opts table
function Popup:configure(opts)
  if not opts then
    if self:is_visible() then
      -- reconfigure the window, just in case
      api.win_set_config(self.win, do_wincfg(self))
    end
  elseif opts.buf and opts.buf ~= self.buf then
    -- update buffer options, potentially deleting old ones
    self.bufopts = opts.bufopts
    -- set a new buffer for the popup
    if type(opts.buf) == "number" then
      self.has_set_buf = opts.buf
    else
      self.has_set_buf = H.create_buf(opts.buf, self.bufopts)
    end
    H.configure_popup(H.merge(self, opts))
  elseif not self:is_visible() then
    -- hidden, we cannot reconfigure only the window
    H.configure_popup(H.merge(self, opts))
  else
    if opts.wincfg then
      -- if there is some other key, we cannot reconfigure only the window
      for k in pairs(opts) do
        if k ~= 'wincfg' then
          H.configure_popup(H.merge(self, opts))
          return
        end
      end
    end
    api.win_set_config(self.win, do_wincfg(H.merge(self, opts)))
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
  api.win_set_option(self.win, "winblend", self._.blend)
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
  local hi = api.set_hl

  local pb, pn, n = b.get("PopupBorder"), b.get("PopupNormal"), b.get("Normal")
  local blend_border = pb.bg ~= n.bg or pb.fg ~= n.bg
  local blend_popup  = pn.bg ~= n.bg or pn.fg ~= n.bg

  local function deferred_blend(delay, blend)
    defer_fn(function()
      if self:is_visible() then
        api.win_set_option(self.win, "winblend", blend)
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

--- Make the popup positioning custom: from now on, the window will have to be
--- reconfigured manually.
---@param relative string
function Popup:custom(relative)
  self.pos = Pos.CUSTOM
  local cfg = self:is_visible() and api.win_get_config(self.win) or self.wincfg
  cfg.relative = relative or "editor"
  cfg.win = cfg.relative == "win" and cfg.win or nil
  local pos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  cfg.row = math.min(pos.row, vim.o.lines - cfg.height - vim.o.cmdheight)
  cfg.col = math.min(pos.col, vim.o.columns - cfg.width)
  if self:is_visible() then
    api.win_set_config(self.win, cfg)
  end
  update_wincfg(self)
end

--- Move a popup on the screen.
---@param dir string: "up", "down", "left" or "right"
---@param cells number|nil
function Popup:move(dir, cells)
  if not dir or not self:is_visible() then
    return
  end
  local o = type(dir) == 'table' and {
    animate = dir.animate ~= false,
    dir = dir.dir or dir[1] or "right",
    cells = dir.cells or 10,
    speed = dir.speed or 0.1,
  } or {
    dir = dir,
    cells = cells or 1,
    speed = 20,
  }

  -- convert the position to custom, relative to edtor
  if self.pos ~= Pos.CUSTOM then Popup.custom(self) end

  local lines, columns, cmdheight = vim.o.lines, vim.o.columns, vim.o.cmdheight

  local function _move(step)
    local cfg = api.win_get_config(self.win)
    local col, row = cfg.col[false], cfg.row[false]
    if o.dir == "down" and (row + cfg.height) < lines - cmdheight then
      row = row + step
    elseif o.dir == "up" and row > 0 then
      row = row - step
    elseif o.dir == "left" and col > 0 then
      col = col - step
    elseif o.dir == "right" and (col + cfg.width) < columns then
      col = col + step
    end
    cfg.col[false] = col
    cfg.row[false] = row
    api.win_set_config(self.win, cfg)
  end

  if o.animate then
    self.queue.waiting = true
    local timer = vim.loop.new_timer()
    local i = 0
    timer:start(0, o.speed, vim.schedule_wrap(function()
      i = i + 1
      if not self:is_visible() then
        self:hide_now()
        timer:stop()
      elseif i <= o.cells then
        _move(1)
      else
        self.queue.waiting = false
        self.queue:proceed(self)
        timer:stop()
      end
    end))
  else
    _move(o.cells)
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

--- Return the window configuration. If not visible, return a configuration as
--- it will be generated when the window will be created.
---@return table
function Popup:get_wincfg()
  return self:is_visible() and api.win_get_config(self.win) or do_wincfg(self)
end

-- Dummy function, in case the method is called with the 'noqueue' option.
function Popup:wait(_)
  return self
end

return Popup
