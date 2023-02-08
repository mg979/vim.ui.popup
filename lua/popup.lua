vim.ui.popup = {}
local popup = vim.ui.popup

-- api {{{1
local api = vim.api
local fn = vim.fn
local strwidth = fn.strdisplaywidth
local curwin = api.nvim_get_current_win
local reconfigure = api.nvim_win_set_config
local create_buf = api.nvim_create_buf
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
-- buf          nil                   number    buffer number for the popup
-- bufbind      nil                   number    bind the popup to a single buffer
-- padding      nil                   nr|tbl    distance from standard anchor
-- disposable   true                  bool      popup self-destructs when hidden
-- enter        false                 bool      enter popup window after creation
-- callbacks    nil                   table     LIST of tables: autocommands callbacks
-- close_on     nil                   table     LIST of strings: events that close the popup
-- bufopts      nil                   table     buffer options: { option = value, ... }
-- winopts      nil                   table     window options: { option = value, ... }
-- wincfg       nil                   table     options for nvim_open_win
-- on_ready     nil                   func      callback to invoke when popup is ready
-- on_dispose   nil                   func      callback to invoke when popup is disposed

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function not_nil_or(v1, v2) -- {{{1
  return v1 ~= nil and v1 or v2
end

local function merge(t1, t2, keep) -- {{{1
  if t2 then
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

-- }}}

-------------------------------------------------------------------------------
-- Autocommands clearing/generation
-------------------------------------------------------------------------------

--- Create an autocommand for the popup and register it in p.au, that will
--- hold k/v pairs { id = autocmd_info, ... }
---@param p table
---@param ev string
---@param au table
local function create_autocmd(p, ev, au)
  local id = api.nvim_create_autocmd(ev, au)
  p.au[id] = au
end

--- Clear autocommands previously created by this popup.
---@param p table
---@return bool
local function clear_autocommands(p)
  p.au = p.au or {}
  for id in pairs(p.au) do
    pcall(api.nvim_del_autocmd, id)
    p.au[id] = nil
  end
  return true
end

--- Create autocommands to close popup and for other callbacks.
--- @param p table
local function setup_autocommands(p)
  -- defer this function because it's more reliable
  -- TODO: figure this better out
  defer_fn(function()
    -- resize the popup on buffer change
    if p.autoresize then
      create_autocmd(p, 'TextChanged', {
        buffer = p.buf,
        callback = function(_) return not pcall(p.resize, p) end
      })
    end

    -- update position on cursor moved
    if p.follow then
      create_autocmd(p, 'CursorMoved', {
        buffer = p.bufbind,
        callback = function(_)
          if p:is_visible() then
            p:redraw()
          else
            return true
          end
        end
      })
    end
    if p.callbacks then
      for _, cb in ipairs(callbacks) do
        create_autocmd(p, cb[1], {
          buffer = cb.buffer or p.bufbind,
          group = cb.group,
          pattern = cb.pattern,
          command = cb.command,
          desc = cb.desc,
          callback = cb.callback,
          once = cb.once,
          nested = cb.nested,
        })
      end
    end

    local close_on = p.close_on
      or (p.focus and {"WinLeave"})
      or (p.follow and { "CursorMovedI", "BufLeave" })
      or { "CursorMoved", "CursorMovedI", "BufLeave" }

    -- close popup on user-/predefined events
    if next(close_on) then
      create_autocmd(p, close_on, {
        callback = function(_)
          local ok = pcall(win_close, p.win, true)
          if ok and p.on_dispose then
            p.on_dispose()
          end
          return true -- to delete the autocommand
        end,
      })
    end

    --- clear autocommands when the popup closes
    create_autocmd(p, 'WinClosed', {
      pattern = '^' .. p.win,
      callback = function(_) return clear_autocommands(p) end
    })
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
  return p.wincfg and p.wincfg.border ~= "none" and 2 or 0
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
    border = o.border or "single",
    noautocmd = o.noautocmd,
  }
  return p.wincfg
end

-------------------------------------------------------------------------------
-- Popup generation
-------------------------------------------------------------------------------

--- Ensure the popup object has a valid window and buffer. When this function
--- returns false, the popup object is not deleted nor invalidated, it's only
--- disabled (popup:is_visible() returns false), because it doesn't have
--- a valid window.
---
--- To avoid flicker, set lazyredraw, but restore old value even if there were
--- errors. Also set up closing autocommands, and set buffer local variables.
--- Return success.
---@param p table
---@return bool
local function configure_popup(p)
  -- clear previous autocommands
  clear_autocommands(p)

  local oldlazy = vim.o.lazyredraw
  vim.o.lazyredraw = true

  local function _ev()
    -- take care of buffer first
    local oldbuf = p.buf
    if p[1] then
      -- make scratch buffer with given lines
      p.buf = create_buf(false, true)
      setlines(p.buf, p[1])
      p.disposable = true
    elseif not buf_is_valid(p.buf or -1) then
      p.buf = create_buf(false, true)
      p.disposable = true
    end

    -- set buffer options
    buf_set_option(p.buf, "bufhidden", p.disposable and "wipe" or "hide")
    if p.bufopts then
      for opt, val in pairs(p.bufopts) do
        buf_set_option(p.buf, opt, val)
      end
    end
    -- now the window
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
        if oldbuf ~= p.buf then
          api.nvim_win_set_buf(p.win, p.buf)
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
    -- setup autocommands and other callbacks
    setup_autocommands(p)
  end

  local ok, err = pcall(_ev)
  vim.o.lazyredraw = oldlazy
  if not ok then
    print(err)
  end
  return ok
end

--- Create a copy of a previous popup, optionally with some different options
--- provided in the extra argument.
---@param popup table
---@param opts table
---@return table
function copy(popup, opts)
  -- we must invalidate the window and clear the previous window configuration,
  -- so that it is reevaluated.
  local p = merge(opts, popup, true)
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

  p.pos = p.pos or Pos.AT_CURSOR
  p.follow = p.follow and p.pos == Pos.AT_CURSOR
  p.enter = not_nil_or(p.enter, false)
  p.focusable = p.focus or not_nil_or(p.focusable, true)
  p.focus = p.enter or (p.focusable and p.focus)
  p.prevwin = win_is_valid(p.prevwin or -1) and p.prevwin or curwin()
  -- if buffer is not created, don't wipe it when closing popup
  p.disposable = not_nil_or(p.disposable, not buf_is_valid(p.buf or -1))
  -- let the popup resize automatically by default when its content changes
  p.autoresize = not_nil_or(p.autoresize, true)

  p = setmetatable(p, { __index = Popup })
  if configure_popup(p) and p.on_ready then
    p.on_ready()
  end
  return p
end

--- Create a buffer from given lines, apply the given options.
--- If bufopts.scratch == true, |scratch-buffer| options are set, but bufhidden
--- is set to 'wipe'. Same if bufopts is nil.
---@param lines table|string
---@param bufopts table|nil
function popup.make_buffer(lines, bufopts)
  local buf = create_buf(false, true)
  setlines(buf, lines)
  local scratch = not bufopts or bufopts.scratch
  if bufopts then
    bufopts.scratch = nil
    for opt, val in pairs(bufopts) do
      buf_set_option(buf, opt, val)
    end
  end
  if scratch then
    buf_set_option(buf, "buftype", "nofile")
    buf_set_option(buf, "bufhidden", "wipe")
    buf_set_option(buf, "swapfile", false)
  end
  return buf
end

--------------------------------------------------------------------------------
-- Popup methods
--------------------------------------------------------------------------------

--- Redraw the popup, so that its size and position is adjusted, based on the
--- contents of its buffer. If the cursor position changed, defer should be
--- true, so that previous window is invalidated in time.
--- TODO: this should be done automatically when buffer content changes.
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

--- Redraw the popup, keeping its config unchanged. If the cursor position
--- changed, defer should be true, so that previous window is invalidated in
--- time.
--- TODO: this should be done automatically when buffer content changes.
---@param defer bool
function Popup:redraw(defer)
  if defer then
    defer_fn(function() self:redraw() end)
    return
  end
  if self:is_visible() then
    reconfigure(self.win, do_wincfg(self))
  else
    configure_popup(p)
  end
  return self
end

--- Change configuration for the popup.
---@param opts table
---@param defer bool
function Popup:configure(opts, defer)
  if defer then
    defer_fn(function() self:configure(opts) end)
    return
  end
  if not self:is_visible() then
    configure_popup(merge(self, opts))
    return self:hide()
  end
  -- check if we only want to reconfigure the window, or the whole object
  local full = false
  if opts.wincfg then
    for k, v in pairs(opts) do
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

--- Hide popup, optionally for n seconds before showing it again.
---@param seconds number
function Popup:hide(seconds)
  pcall(win_close, self.win, true)
  if seconds then
    defer_fn(function() self:show() end, seconds * 1000)
  end
  return self
end

--- Show popup, optionally for n seconds before hiding it.
---@param seconds number
function Popup:show(seconds)
  configure_popup(self)
  if seconds then
    defer_fn(function() self:hide() end, seconds * 1000)
  end
  return self
end

--- Check if popup is visible.
---@return bool
function Popup:is_visible()
  return win_is_valid(self.win)
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

return popup
-- vim: ft=lua et ts=2 sw=2 fdm=marker
