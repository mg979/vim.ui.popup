vim.ui.popup = {}
local popup = vim.ui.popup

-- api {{{1
local api = vim.api
local fn = vim.fn
local strwidth = fn.strdisplaywidth
local curwin = api.nvim_get_current_win
local reconfigure = api.nvim_win_set_config
local open_win = vim.api.nvim_open_win
local buf_set_option = api.nvim_buf_set_option
local buf_get_option = api.nvim_buf_get_option
local buf_is_valid = api.nvim_buf_is_valid
local win_is_valid = api.nvim_win_is_valid
local win_set_option = api.nvim_win_set_option
local win_get_config = api.nvim_win_get_config
local win_get_option = api.nvim_win_get_option
local win_set_option = api.nvim_win_set_option
local win_close = api.nvim_win_close
-- }}}

-- popup standard positions
popup.pos = { -- {{{1
  CUSTOM = -1,
  AT_CURSOR = 0,
  WIN_TOP = 1,
  WIN_BOTTOM = 2,
  EDITOR_CENTER = 3,
  EDITOR_CENTER_LEFT = 4,
  EDITOR_CENTER_RIGHT = 5,
  EDITOR_CENTER_TOP = 6,
  EDITOR_CENTER_BOTTOM = 7,
  EDITOR_LEFT_WIDE = 8,
  EDITOR_RIGHT_WIDE = 9,
  EDITOR_TOP_WIDE = 10,
  EDITOR_BOTTOM_WIDE = 11,
  EDITOR_TOPLEFT = 12,
  EDITOR_TOPRIGHT = 13,
  EDITOR_BOTLEFT = 14,
  EDITOR_BOTRIGHT = 15,
}

-- }}}

-- Table for popup methods.
local Popup = {}

-- Table for positions
local Pos = popup.pos

-- Custom options (options for nvim_open_win go in 'wincfg' value):
--------------------------------------------------------------------------------
--    KEY         DEFAULT              TYPE        NOTES
--------------------------------------------------------------------------------
-- pos          popup.pos.AT_CURSOR   number    expresses desired position/type of popup
-- win          nil                   number    window id for the popup
-- bfn          nil                   func      function returning (lines{}, opts{}) or number
-- buf          nil                   number    buffer number for the popup
-- bufbind      nil                   number    bind the popup to a single buffer
-- enter        false                 bool      enter popup window after creation
-- namespace    "_G"                  string    namespace for popup
-- bufopts      {}                    table     buffer options: { option = value, ... }
-- winopts      {}                    table     window options: { option = value, ... }
-- wincfg       {}                    table     options for nvim_open_win
-- hide_on      nil                   table     LIST of strings: events that hide the popup
-- on_show      nil                   func      called after popup is shown
-- on_hide      nil                   func      called just before hiding the popup
-- on_dispose   nil                   func      called just before destroying the popup

-- The last three methods are invoked with the popup passed as argument. The
-- popup window is always visible when this happens.

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function not_nil_or(v1, v2) -- {{{1
  return v1 ~= nil and v1 or v2
end

local function merge(t1, t2, keep) -- {{{1
  if t2 then
    t1 = t1 or {}
    if keep then
      for k, v in pairs(t2) do
        if t1[k] == nil then
          t1[k] = v
        end
      end
    else
      for k, v in pairs(t2) do
        t1[k] = v
      end
    end
  end
  return t1
end

local function setlines(buf, lines) -- {{{1
  lines = type(lines) == "string" and vim.split(lines, "\n", { trimempty = true }) or lines
  return vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
end

local function getlines(buf) -- {{{1
  return vim.api.nvim_buf_get_lines(buf, 0, -1, true)
end

local function defer_fn(fn, timeout) -- {{{1
  vim.defer_fn(fn, timeout or 0)
end

local function set_bufopts(bnr, bo) -- {{{1
  bo = bo or {}
  if bo.scratch or not next(bo) then
    bo.buftype = "nofile"
    bo.bufhidden = "hide"
    bo.swapfile = false
    bo.scratch = nil
  end
  for opt, val in pairs(bo) do
    buf_set_option(bnr, opt, val)
  end
end

local function create_buf(lines, opts) -- {{{1
  local bnr = api.nvim_create_buf(false, true)
  setlines(bnr, lines)
  set_bufopts(bnr, opts)
  return bnr
end

-- }}}

-------------------------------------------------------------------------------
-- Autocommands clearing/generation
-------------------------------------------------------------------------------

--- Create an autocommand for the popup and register it in the popup augroup.
---@param p table
---@param ev string
---@param au table
local function create_autocmd(p, ev, au)
  au.group = p._.aug
  api.nvim_create_autocmd(ev, au)
end

--- Initialize augroup for this popup, also clearing autocommands previously
--- created by it. Create autocommands for popup callbacks.
--- @param p table
local function on_show_autocommands(p)
  p._.aug = api.nvim_create_augroup("__VimUiPopup_" .. p.ID, { clear = true })

  -- defer this function because it's more reliable
  -- FIXME: figure this better out
  defer_fn(function()
    -- resize the popup on buffer change
    if p.autoresize then
      create_autocmd(p, "TextChanged", {
        buffer = p.buf,
        callback = function(_) p:resize() end,
      })
    end

    -- update position on cursor moved
    if p.follow then
      create_autocmd(p, "CursorMoved", {
        buffer = p.bufbind,
        callback = function(_) p:redraw() end,
      })
    end

    local hide_on = p.hide_on
      or (p.focus and { "WinLeave" })
      or (p.follow and { "CursorMovedI", "BufLeave" })
      or { "CursorMoved", "CursorMovedI", "BufLeave" }

    -- close popup on user-/predefined events
    if next(hide_on) then
      create_autocmd(p, hide_on, {
        callback = function(_)
          p:hide()
          return true -- to delete the autocommand
        end,
      })
    end
  end)
end

-------------------------------------------------------------------------------
-- Window configuration for nvim_open_win()
-------------------------------------------------------------------------------

--  We keep the tabline visible.
local function tabline_row()
  return vim.o.showtabline ~= 0 and 1 or 0
end

--- Get border width for popup window (sum of both sides).
local function border_width(p)
  return ((p.wincfg or {}).border or "none") ~= "none" and 2 or 0
end

--- Get row for popup, based on popup position.
local function get_row(p, height)
  local rows = vim.o.lines
  local wh = api.nvim_win_get_height(p.prevwin)
  local min = tabline_row()
  return ({
                [Pos.AT_CURSOR] = 1,
                  [Pos.WIN_TOP] = 0,
               [Pos.WIN_BOTTOM] = wh - height - border_width(p),
            [Pos.EDITOR_CENTER] = (rows - height) / 2,
       [Pos.EDITOR_CENTER_LEFT] = (rows - height) / 2,
      [Pos.EDITOR_CENTER_RIGHT] = (rows - height) / 2,
        [Pos.EDITOR_CENTER_TOP] = min,
     [Pos.EDITOR_CENTER_BOTTOM] = rows - height,
         [Pos.EDITOR_LEFT_WIDE] = min,
        [Pos.EDITOR_RIGHT_WIDE] = min,
          [Pos.EDITOR_TOP_WIDE] = min,
       [Pos.EDITOR_BOTTOM_WIDE] = rows - height,
           [Pos.EDITOR_TOPLEFT] = min,
          [Pos.EDITOR_TOPRIGHT] = min,
           [Pos.EDITOR_BOTLEFT] = rows - height,
          [Pos.EDITOR_BOTRIGHT] = rows - height,
  })[p.pos]
end

local function get_column(p, width)
  local cols = vim.o.columns
  local x = api.nvim_win_get_position(p.prevwin)[2]
  return ({
                [Pos.AT_CURSOR] = 1,
                  [Pos.WIN_TOP] = x,
               [Pos.WIN_BOTTOM] = x,
            [Pos.EDITOR_CENTER] = (cols - width) / 2,
       [Pos.EDITOR_CENTER_LEFT] = 0,
      [Pos.EDITOR_CENTER_RIGHT] = cols - width,
        [Pos.EDITOR_CENTER_TOP] = (cols - width) / 2,
     [Pos.EDITOR_CENTER_BOTTOM] = (cols - width) / 2,
         [Pos.EDITOR_LEFT_WIDE] = 0,
        [Pos.EDITOR_RIGHT_WIDE] = cols - width,
          [Pos.EDITOR_TOP_WIDE] = 0,
       [Pos.EDITOR_BOTTOM_WIDE] = 0,
           [Pos.EDITOR_TOPLEFT] = 0,
          [Pos.EDITOR_TOPRIGHT] = cols - width,
           [Pos.EDITOR_BOTLEFT] = 0,
          [Pos.EDITOR_BOTRIGHT] = cols - width,
  })[p.pos]
end

--- Calculate the width of the popup.
---@param p table
---@param lines table
---@return number
local function calc_width(p, lines)
  local w = 1
  -- width is the whole window width
  if p.pos == Pos.EDITOR_TOP_WIDE or p.pos == Pos.EDITOR_BOTTOM_WIDE then
    w = vim.o.columns - border_width(p)
  else
    for _, line in ipairs(lines) do
      local sw = strwidth(line)
      if sw > w then
        w = sw
      end
    end
    -- limit width to textwidth
    w = math.min(w, math.max(buf_get_option(p.buf, "textwidth"), 79))
  end
  return w
end

--- Calculate the height of the popup.
---@param p table
---@param lines table
---@param w number: popup width
---@return number
local function calc_height(p, lines, w)
  -- height is the whole window height
  if p.pos == Pos.EDITOR_LEFT_WIDE or p.pos == Pos.EDITOR_RIGHT_WIDE then
    return vim.o.lines - tabline_row() * 2 - border_width(p)
  end
  -- base height is the number of lines, but we must also consider wrapped
  -- lines: for each line that is wrapped, increase it by the times it wraps
  local h = #lines
  if p.winopts.wrap then
    local sb = #vim.o.showbreak
    for _, line in ipairs(lines) do
      local sw = strwidth(line)
      while sw > w and w > sb do
        sw = sw - w + sb
        h = h + 1
      end
    end
  end
  return h
end

--- Calculate the dimensions (width and height) of the popup.
---@param p table
---@param lines table
---@return number, number
local function calc_dimensions(p, lines)
  -- calculate width first, height calculation needs it
  local w, h
  if p.pos == Pos.CUSTOM then
    w = p.wincfg.width or calc_width(p, lines)
    h = p.wincfg.height or calc_height(p, lines, w)
    return w, h
  end
  if p.pos == Pos.WIN_TOP or p.pos == Pos.WIN_BOTTOM then
    w = api.nvim_win_get_width(p.prevwin) - border_width(p)
  else
    w = calc_width(p, lines)
  end
  return w, calc_height(p, lines, w)
end

--- Generate the window configuration to pass to nvim_open_win().
---@param p table
---@return table
local function do_wincfg(p)
  local o = p.wincfg
  local editor = p.pos >= Pos.EDITOR_CENTER
  local cursor = p.pos == Pos.AT_CURSOR
  local custom = p.pos == Pos.CUSTOM
  local win = not editor and not cursor and p.prevwin
  local lines = getlines(p.buf)
  local width, height = calc_dimensions(p, lines)
  p.wincfg = {
    relative = custom and o.relative
            or cursor and "cursor"
            or editor and "editor" or "win",
    win = win or nil,
    anchor = o.anchor or "NW",
    width = width,
    height = height,
    col = custom and o.col or get_column(p, width),
    row = custom and o.row or get_row(p, height),
    focusable = o.focusable ~= nil and o.focusable or true,
    bufpos = o.bufpos,
    zindex = o.zindex,
    style = o.style == nil and "minimal" or nil,
    border = o.border or "none",
    noautocmd = o.noautocmd,
  }
  return p.wincfg
end

-------------------------------------------------------------------------------
-- Popup registration
-------------------------------------------------------------------------------

-- incremental id for popups, popups table
local ID, ALL = 0, {}

-- Unique popup id.
local function get_id()
  ID = ID + 1
  return ID
end

-- Register popup in global table (by namespace and ID) and return it.
local function register_popup(p)
  p.ID = get_id()
  local ns = p.namespace or "_G"
  ALL[ns] = ALL[ns] or {}
  ALL[ns][ID] = p
  return p
end

-------------------------------------------------------------------------------
-- Popup generation, local popup functions
-------------------------------------------------------------------------------

local function prepare_buffer(p)
  -- remember previous buffer used by popup
  -- FIXME: is this really necessary?
  p._.oldbuf = p.buf

  if p.bfn then
    -- get buffer (or its lines) from result of function
    local buf, opts = p.bfn(p)
    if type(buf) == "number" then
      p.buf = buf
    elseif type(buf) == "table" then
      p.buf = create_buf(buf, merge(opts, { scratch = true }))
    end
  elseif p[1] then
    -- make scratch buffer with given lines
    p.buf = create_buf(p[1] or {}, merge(p.bufopts, { scratch = true }))
    p[1] = nil
  elseif not buf_is_valid(p.buf or -1) then
    -- make scratch buffer
    p.buf = create_buf({}, merge(p.bufopts, { scratch = true }))
  end

  if not buf_is_valid(p.buf or -1) then
    error("Popup needs a valid buffer.")
  end
end

--- To avoid flicker, set lazyredraw, but restore old value even if there were
--- errors. Also set up closing autocommands, and set buffer local variables.
--- Return success.
---@param p table
---@return bool
local function open_popup_win(p)
  local oldlazy = vim.o.lazyredraw
  vim.o.lazyredraw = true

  local function _open()
    p.wincfg = p.wincfg or {}
    -- cursorline disabled for minimal style
    p.winopts = merge(
      { cursorline = p.wincfg.style ~= nil and p.wincfg.style ~= "minimal", wrap = true },
      p.winopts or {}
    )
    -- if previous window is valid, just reconfigure, otherwise open a new one
    if win_is_valid(p.win or -1) then
      if next(p.wincfg) then
        -- this can happen if a popup is reconfigured with a different buffer
        if p._.oldbuf ~= p.buf then
          api.nvim_win_set_buf(p.win, p.buf)
          p._.oldbuf = p.buf
        end
        reconfigure(p.win, do_wincfg(p))
      end
    else
      p.win = open_win(p.buf, p.enter, do_wincfg(p))
    end
    -- set window options
    for opt, val in pairs(p.winopts) do
      win_set_option(p.win, opt, val)
    end
  end

  local ok, err = pcall(_open)
  vim.o.lazyredraw = oldlazy
  return ok, err
end

--- Ensure the popup object has a valid buffer. Return success.
---@param p table
---@return bool
local function configure_popup(p)
  local ok, err

  -- ensure popup has a valid buffer
  ok, err = pcall(prepare_buffer, p)
  if not ok then
    print(err)
  end

  return ok
end

--- Create a copy of a previous popup, optionally with some different options
--- provided in the extra argument.
---@param p table
---@param opts table
---@return table
function copy(p, opts)
  p = merge(opts or {}, p, true)
  p.win = -1
  if p.wincfg then
    -- only keep values that can be valid for different positions
    local keep = p.pos == Pos.CUSTOM
    local prev = p.wincfg
    p.wincfg = {
      anchor = prev.anchor,
      focusable = prev.focusable,
      style = prev.style,
      border = prev.border,
      noautocmd = prev.noautocmd,
      width = keep and prev.width,
      height = keep and prev.height,
      col = keep and prev.col,
      row = keep and prev.row,
    }
  end
  return p
end

function has_method(p, name)
  return p[name] and type(p[name]) == 'function'
end

-------------------------------------------------------------------------------
-- Module functions
-------------------------------------------------------------------------------

--- Create a new popup object.
---@param opts table
---@return table|nil
function popup.new(opts)
  local p = opts or {}

  if p.copy then
    p = copy(p.copy, opts)
    p.copy = nil
  end

  p._ = {} -- private attributes, will be cleared on hide
  p.namespace = p.namespace or "_G"
  p.pos = p.pos or Pos.AT_CURSOR
  p.enter = not_nil_or(p.enter, false)
  p.follow = p.follow and p.pos == Pos.AT_CURSOR
  p.focusable = p.focus or not_nil_or(p.focusable, true)
  p.focus = p.enter or (p.focusable and p.focus)
  p.prevwin = win_is_valid(p.prevwin or -1) and p.prevwin or curwin()
  -- let the popup resize automatically by default when its content changes
  p.autoresize = not_nil_or(p.autoresize, true)

  -- popup starts disabled
  if configure_popup(setmetatable(p, { __index = Popup })) then
    return register_popup(p)
  else
    return {}
  end
end

--- Create a buffer from given lines, apply the given options.
--- If bufopts.scratch == true, |scratch-buffer| options are set.
---@param lines table|string
---@param bufopts table|nil
function popup.make_buffer(lines, bufopts)
  return create_buf(lines, bufopts)
end

function popup.get(id)
  for ns in pairs(ALL) do
    for k, v in pairs(ALL[ns]) do
      if k == id then
        return v
      end
    end
  end
end

function popup.destroy_ns(ns)
  for _, v in pairs(ALL[ns] or {}) do
    v:destroy()
  end
  ALL[ns] = nil
end

--------------------------------------------------------------------------------
-- Popup methods
--------------------------------------------------------------------------------

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

--- Show popup, optionally for n seconds before hiding it.
---@param seconds number
function Popup:show(seconds)
  if not buf_is_valid(self.buf or -1) then
    self:destroy()
    error("Popup doesn't have a valid buffer.")
  end
  if not configure_popup(self) then
    return self
  end
  on_show_autocommands(self)
  open_popup_win(self)
  if seconds then
    defer_fn(function() self:hide() end, seconds * 1000)
  end
  if has_method(self, "on_show") then
    self:on_show()
  end
  return self
end

--- Hide popup, optionally for n seconds before showing it again.
---@param seconds number
function Popup:hide(seconds)
  if win_is_valid(self.win or -1) then
    if has_method(self, "on_hide") and self:on_hide() then
      return self
    end
    win_close(self.win, true)
  end
  pcall(api.nvim_del_augroup_by_id, self._.aug)
  if seconds then
    defer_fn(function() self:show() end, seconds * 1000)
  end
  return self
end

--- Redraw the popup, keeping its config unchanged. If the cursor position
--- changed, defer should be true, so that previous window is invalidated in
--- time.
---@param defer bool
function Popup:redraw(defer)
  if defer then
    defer_fn(function() self:redraw() end)
    return
  end
  if self:is_visible() then
    reconfigure(self.win, do_wincfg(self))
  else
    self:show()
  end
  return self
end

--- Redraw the popup, so that its size and position is adjusted, based on the
--- contents of its buffer. If the cursor position changed, defer should be
--- true, so that previous window is invalidated in time.
---@param defer bool
function Popup:resize(defer)
  if defer then
    defer_fn(function() self:resize() end)
    return
  end
  self.wincfg.width = nil
  self.wincfg.height = nil
  return self:redraw()
end

--- Change configuration for the popup.
---@param opts table
---@param defer bool
function Popup:configure(opts, defer)
  if defer then
    defer_fn(function() self:configure(opts) end)
    return
  end
  -- hidden, we cannot reconfigure only the window
  if not self:is_visible() then
    configure_popup(merge(self, opts))
    return self
  end
  -- check if we only want to reconfigure the window, or the whole object
  local full = false
  if opts.wincfg then
    for _, v in pairs(opts) do
      if v ~= opts.wincfg then
        full = true
        break
      end
    end
  end
  if not full then
    reconfigure(self.win, do_wincfg(merge(self, opts)))
  else
    configure_popup(merge(self, opts))
  end
  return self
end

--- Show the popup at the center of the screen.
---@param opts table
function Popup:notification_center(opts, seconds)
  merge(self, opts).pos = Pos.EDITOR_CENTER
  return self:show(seconds or 3)
end

--- Show the popup at the top right corner of the screen.
---@param opts table
function Popup:notification(opts, seconds)
  merge(self, opts).pos = Pos.EDITOR_TOPRIGHT
  return self:show(seconds or 3)
end

--- Set winblend for popup window.
---@param val number
---@return table
function Popup:blend(val)
  if not val or not vim.o.termguicolors or not self:is_visible() then
    return self
  end
  self._.blend = val < 0 and 0 or val > 100 and 100 or val
  win_set_option(self.win, "winblend", self._.blend)
  return self
end

--- Make the popup window fade out.
---@param wait_seconds number: fading starts after n seconds
---@param for_seconds number: fading lasts n seconds
---@param endblend number: final winblend value (0-100)
---@param hide_when_over bool
---@return table
function Popup:fade(wait_seconds, for_seconds, endblend, hide_when_over)
  if not vim.o.termguicolors or not self:is_visible() then
    return self
  end
  if wait_seconds and wait_seconds > 0 then
    defer_fn(function() self:fade(0, for_seconds, endblend) end, wait_seconds * 1000)
    return self
  end

  -- stop at full transparency by default
  endblend = endblend or 100

  local startblend = self._.blend or win_get_option(self.win, "winblend")
  if endblend <= startblend then
    return self
  end
  -- step length is 10ms
  local steplen = 10
  local steps = (for_seconds or 1) * (1000 / steplen)
  local stepblend = (endblend - startblend) / steps

  local finished = false

  local function deferred_blend(delay, blend)
    if finished then
      return
    end
    local stop = steps * steplen
    defer_fn(function()
      if self:is_visible() then
        win_set_option(self.win, "winblend", blend)
      end
      if delay >= stop then
        finished = true
        -- hide the window completely when fading is over
        if hide_when_over or win_get_option(self.win, "winblend") == 100 then
          self:hide()
        end
      end
    end, delay)
  end

  local curblend, f = startblend, startblend
  for i = 1, steps do
    f = f + stepblend
    if f >= 100 then
      deferred_blend(steplen * i, 100)
      break
    elseif math.floor(f) > curblend then
      curblend = math.floor(f)
      deferred_blend(steplen * i, curblend)
    end
  end
  return self
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

--- Set buffer for popup.
--- `buf` can be a table with lines, or a buffer number.
---@param buf number|table|nil
---@param opts table|nil
function Popup:set_buffer(buf, opts)
  if type(buf) == "number" then
    self.buf = buf
  else
    self.buf = create_buf(buf or {}, opts)
  end
  self.bufopts = opts
  configure_popup(self)
  return self
end

return popup
-- vim: ft=lua et ts=2 sw=2 fdm=marker
