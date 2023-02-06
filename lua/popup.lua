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
local create_autocmd = api.nvim_create_autocmd
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

local Pos = popup.pos

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

-- }}}


-- Custom options (options for nvim_open_win go in 'wincfg' value):
--------------------------------------------------------------------------------
--    KEY         DEFAULT              TYPE        NOTES
--------------------------------------------------------------------------------
-- pos          popup.pos.AT_CURSOR   number    expresses desired position/type of popup
-- mode         'n'                   string    mode in which the popup can show
-- win          nil                   number    window id for the popup
-- buf          nil                   number    buffer number for the popup
-- timeout      nil                   number    initial lifetime
-- lifetime     nil                   number    remaining lifetime
-- padding      nil                   nr|tbl    distance from standard anchor
-- disposable   true                  bool      popup self-destructs when hidden
-- enter        false                 bool      enter popup window after creation
-- callbacks    nil                   table     autocommands callbacks
-- close_on     nil                   table     autocommands that close the popup
-- bufopts      nil                   table     buffer options: { option = value, ... }
-- winopts      nil                   table     window options: { option = value, ... }
-- wincfg       nil                   table     options for nvim_open_win
-- on_ready     nil                   func      callback to invoke when popup is ready
-- on_dispose   nil                   func      callback to invoke when popup is disposed

-- Table for popup methods.
local Popup = {}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function default_metatable(t) -- {{{1
  return {
    __index = Popup,
    -- -- object is readonly after creation, it can be modified through methods
    -- __newindex = function(_, _, _)
    --   error("Popup object is read-only, use methods to control it.", 2)
    -- end,
  }
end

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

--- Create autocommands to close popup.
--- @param close_on table
--- @param p table
local function setup_autocommands(close_on, p)
  if p.autoresize then
    -- resize the popup on buffer change
    create_autocmd('TextChanged', {
      buffer = p.buf,
      callback = function(_) pcall(p.resize, p) end
    })
  end
  -- defer this function because it's more reliable
  -- TODO: figure out this better
  if #close_on > 0 then
    defer_fn(function()
      create_autocmd(close_on, {
        callback = function(_)
          local ok = pcall(win_close, p.win, true)
          if ok and p.on_dispose then
            p.on_dispose()
          end
          return true -- to delete the autocommand
        end,
      })
    end)
  end
end

-------------------------------------------------------------------------------
-- Window configuration for nvim_open_win()
-------------------------------------------------------------------------------

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
  if p.wincfg.width and p.wincfg.height then
    -- no need to calculate them, set in wincfg provided by user
    return p.wincfg.width, p.wincfg.height
  end
  -- calculate width first, height calculation needs it
  local w
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
  local win = not editor and not cursor and p.prevwin
  local lines = getlines(p.buf)
  local width, height = calc_dimensions(p, lines)
  p.wincfg = {
    relative = cursor and "cursor" or editor and "editor" or "win",
    win = win or nil,
    anchor = o.anchor or "NW",
    width = width,
    height = height,
    col = o.col or get_column(p, width),
    row = o.row or get_row(p, height),
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
-- Popup generation and validation
-------------------------------------------------------------------------------

--- Ensure the popup object has a valid window and buffer.
--- Set lazyredraw, but restore old value even if there were errors.
--- Also set up closing autocommands, and set buffer local variables.
--- Return success.
---@param p table
---@return bool
local function configure_and_validate(p)
  local oldlazy = vim.o.lazyredraw
  vim.o.lazyredraw = true

  local function _ev()
    -- take care of buffer first
    p.buf = buf_is_valid(p.buf or -1) and p.buf or create_buf(false, true)
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
    -- if previous window is still valid, do a simple reconfigure, otherwise
    -- open a new one
    if win_is_valid(p.win or -1) then
      if next(p.wincfg) then
        reconfigure(p.win, do_wincfg(p))
      end
    else
      p.win = open_win(p.buf, p.enter, do_wincfg(p))
    end
    -- set window options
    for opt, val in pairs(p.winopts) do
      win_set_option(p.win, opt, val)
    end
    -- setup autocommands that close the popup
    if p.close_on then
      setup_autocommands(p.close_on, p)
    elseif p.focus then
      setup_autocommands({ "WinLeave" }, p)
    else
      setup_autocommands({ "CursorMoved", "CursorMovedI", "BufLeave" }, p)
    end
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
  local p = merge(opts or {}, popup or {}, true)
  p.win = -1
  if p.wincfg then
    -- only keep values that can be valid for different positions
    p.wincfg = {
      anchor = p.wincfg.anchor,
      focusable = p.wincfg.focusable,
      style = p.wincfg.style,
      border = p.wincfg.border,
      noautocmd = p.wincfg.noautocmd,
    }
  end
  return p
end

-------------------------------------------------------------------------------
-- Module functions
-------------------------------------------------------------------------------

--- Create a new popup object.
---@param opts table
---@return table
function popup.new(opts)
  local p = opts or {}

  if p.copy then
    p = copy(p.copy, opts)
    p.copy = nil
  end

  p.pos = p.pos or Pos.AT_CURSOR
  p.mode = p.mode or "n"
  p.enter = not_nil_or(p.enter, false)
  p.focusable = p.focus or not_nil_or(p.focusable, true)
  p.focus = p.enter or (p.focusable and p.focus)
  p.prevwin = win_is_valid(p.prevwin or -1) and p.prevwin or curwin()
  -- if buffer is not created, don't wipe it when closing popup
  p.disposable = not_nil_or(p.disposable, not buf_is_valid(p.buf or -1))
  -- let the popup resize automatically by default when its content changes
  p.autoresize = not_nil_or(p.autoresize, true)

  if configure_and_validate(p) then
    p = setmetatable(p, default_metatable(p))
    if p.on_ready then
      p.on_ready()
    end
    return p
  else
    return {}
  end
end

--- Create a buffer from given lines, apply the given options.
--- If bufopts.scratch == true, |scratch-buffer| options are set, but bufhidden
--- is set to 'wipe'.
---@param lines table|string
---@param bufopts table
function popup.make_buffer(lines, bufopts)
  local buf = create_buf(false, true)
  setlines(buf, lines)
  if not bufopts then
    buf_set_option(buf, "bufhidden", "wipe")
    return buf
  end
  local scratch = bufopts.scratch
  bufopts.scratch = nil
  for opt, val in pairs(bufopts) do
    buf_set_option(buf, opt, val)
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

--- defer_validation {{{1
--- Perform validation check and reconfigure the popup, in a deferred way, so
--- that autocommands that are waiting to be triggered do their job.
---@param p table
local function defer_validation(p)
  defer_fn(function()
    configure_and_validate(p)
    -- reconfigure(p.win, do_wincfg(p))
  end)
end
-- }}}

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
  self:redraw()
  return self
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
  if self:is_valid() then
    reconfigure(self.win, do_wincfg(self))
  else
    configure_and_validate(p)
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
  if not self:is_valid() then
    configure_and_validate(merge(self, opts))
    return
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
    configure_and_validate(merge(self, opts))
  end
  return self
end

--- Show the popup at the center of the screen.
---@param opts table
function Popup:notification_center(opts, seconds)
  merge(self, opts)
  self.pos = Pos.EDITOR_CENTER
  self:show(seconds or 3)
  return self
end

--- Show the popup at the top right corner of the screen.
---@param opts table
function Popup:notification(opts, seconds)
  merge(self, opts)
  self.pos = Pos.EDITOR_TOPRIGHT
  self:show(seconds or 3)
  return self
end

--- Hide popup, optionally for n seconds before showing it again.
---@param seconds number
function Popup:hide(seconds)
  win_close(self.win, true)
  if seconds then
    defer_fn(function() self:show() end, seconds * 1000)
  end
  return self
end

--- Show popup, optionally for n seconds before hiding it.
---@param seconds number
function Popup:show(seconds)
  configure_and_validate(self)
  if seconds then
    defer_fn(function() self:hide() end, seconds * 1000)
  end
  return self
end

function Popup:is_valid()
  return win_is_valid(self.win) and buf_is_valid(self.buf)
end

return popup
-- vim: ft=lua et ts=2 sw=2 fdm=marker
