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
local ms = function(s) return s * 1000 end
local themes = require("popup.themes")
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
-- noqueue      false                 bool      don't use async queuing
-- enter        false                 bool      enter popup window after creation
-- namespace    "_G"                  string    namespace for popup
-- theme        "default"             string    popup appearance
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

local function true_or_false(v1, v2) -- {{{1
  return v1 == nil and v2 or v1
end

local function call(...)
  local ok, res = pcall(...)
  if not ok then
    api.nvim_echo({{"vim.ui.popup:", "Error"}, {" " .. res, "WarningMsg"}}, true, {})
    return false
  end
  return res or true
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
    focusable = p.enter or (o.focusable == true and true or false),
    bufpos = o.bufpos,
    zindex = o.zindex,
    style = o.style or "minimal",
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
--- This function should only run after the window has been created!
--- @param p table
local function on_show_autocommands(p)
  -- defer this function because it's more reliable
  -- FIXME: no clue why it's needed
  defer_fn(function()
    if not p:is_visible() then
      return
    end
    p._.aug = api.nvim_create_augroup("__VimUiPopup_" .. p.ID, { clear = true })

    -- redraw the popup on buffer change
    if p.autoresize then
      create_autocmd(p, "TextChanged", {
        buffer = p.buf,
        callback = function(_) Popup.redraw(p) end,
      })
    end

    -- update position on cursor moved
    if p.follow then
      create_autocmd(p, "CursorMoved", {
        buffer = p.bufbind,
        callback = function(_) Popup.redraw(p) end,
      })
    end

    -- if the window should be entered, make sure it actually is
    -- entering the window immediately is prevented by having p.bfn
    if p.enter and curwin ~= p.win then
      api.nvim_set_current_win(p.win)
    end

    local hide_on = p.hide_on
      or (p.enter and { "WinLeave" })
      or (p.follow and { "CursorMovedI", "BufLeave" })
      or { "CursorMoved", "CursorMovedI", "BufLeave" }

    -- close popup on user-/predefined events
    if next(hide_on) then
      create_autocmd(p, hide_on, {
        callback = function(_)
          p:hide_now()
          return true -- to delete the autocommand
        end,
      })
    end
  end)
end

-------------------------------------------------------------------------------
-- Popup generation, local popup functions
-------------------------------------------------------------------------------

local function prepare_buffer(p)
  if p.has_set_buf then
    -- set by Popup.set_buffer, cleared in open_popup_win
    p.buf = p.has_set_buf
  elseif p.bfn then
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
      {
        cursorline = p.wincfg.style ~= nil and p.wincfg.style ~= "minimal",
        wrap = true,
      },
      p.winopts or {}
    )
    -- if previous window is valid, just reconfigure, otherwise open a new one
    if win_is_valid(p.win or -1) then
      if p.has_set_buf then
        vim.fn.win_execute(p.win, "noautocmd buffer " .. p.buf, true)
      end
      if next(p.wincfg) then
        reconfigure(p.win, do_wincfg(p))
      end
    else
      p.win = open_win(p.buf, p.enter and not p.bfn, do_wincfg(p))
      p._.blend = win_get_option(p.win, "winblend")
    end
    -- set window options
    for opt, val in pairs(p.winopts) do
      win_set_option(p.win, opt, val)
    end
  end

  local ok, err = pcall(_open)

  -- clear variable set by Popup.set_buffer
  p.has_set_buf = nil
  vim.o.lazyredraw = oldlazy
  return ok, err
end

--- Ensure the popup object has a valid buffer. Return success.
---@param p table
---@return bool
local function configure_popup(p)
  local ok, err

  -- ensure popup has a valid buffer
  return call(prepare_buffer, p)
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
-- Queue handling
-------------------------------------------------------------------------------

-- The queue table is stored in popup.queue. When popup methods are called,
-- many of them are queued rather than instantly invoked. Each method can have
-- an expected delay, depending on its arguments.
--
-- Some methods cannot be queued, therefore cannot be chained (for example
-- `is_visible` and other methods that aren't supposed to return the popup
-- object): in this case the Popup method is returned directly.

-- Note: calling the queue itself inserts an item in queue.items.
-- These methods don't want to be queued:
--    Popup.is_visible    -> bool
--    Popup.hide_now      -> void, empties queue, removes autocommands
--    Popup.destroy_now   -> void, invalidates popup object

local Queue = {}

function Queue:proceed(p)
  if not self.stop and #self.items > 0 then
    local item = table.remove(self.items, 1)
    if not self.waiting and item.wait then
      self.waiting = true
      defer_fn(function()
        self.waiting = false
        self:proceed(p)
      end, item.wait)
    elseif not self.waiting and item.items then
      -- multiple items in a block that must be processed together
      -- unroll it and put it on top, in the same order as in the block
      for i = #item.items, 1, -1 do
        self(item.items[i], 1)
      end
      self:proceed(p)
    elseif not next(item) then -- empty item?
      self:proceed(p)
    elseif not self.waiting then
      if item[2] then
        Popup[item[1]](p, unpack(item[2]))
      else
        Popup[item[1]](p)
      end
      self:proceed(p)
    else
      self(item, 1) -- couldn't process item, put it back
    end
  end
end

function Queue:clear_queue()
  self.stop = true
  self.items = {}
end

function Queue:show(seconds)
  if seconds then
    self({ items = {{ "show" }, { wait = ms(seconds) }, { "hide" }} })
  else
    self({ "show" })
  end
end

function Queue:hide(seconds)
  if seconds then
    self({ items = {{ "hide" }, { wait = ms(seconds) }, { "show" }} })
  else
    self({ "hide" })
  end
end

function Queue:destroy()
  self({ "destroy" })
end

function Queue:configure(opts)
  self({ "configure", { opts } })
end

function Queue:notification(seconds, opts)
  self({ "notification", { seconds, opts } })
  self:show(seconds)
end

function Queue:notification_center(seconds, opts)
  self({ "notification_center", { seconds, opts } })
  self:show(seconds)
end

function Queue:blend(val)
  self({ "blend", { val } })
end

function Queue:fade(for_seconds, endblend)
  self({ "fade", { for_seconds, endblend } })
end

function Queue:wait(seconds)
  self({ wait = ms(seconds or 1) })
end

function Queue:redraw()
  self({ "redraw" })
end

function Queue:set_buffer(buf, opts)
  self({ "set_buffer", { buf, opts } })
end

-- Metatable for popup object:
-- 1. the looked up method must exist in either Popup or Queue
-- 2. non-queuable methods are returned right away
-- 3. queuable methods are added to the queue
-- TODO: queue also unkown method by creating a Queue method on the fly
local mt = {
  __index = function(p, method)
    if not Popup[method] and not Queue[method] then
      return nil
    end
    if p.noqueue and Queue[method] then
      -- not using queue, protected call of Popup method
      return function(p, ...)
        call(Popup[method], p, ...)
        return p
      end
    elseif Queue[method] then
      return function(p, ...)
        call(Queue[method], p.queue, ...)
        Queue.proceed(p.queue, p)
        return p
      end
    end
    return Popup[method]
  end
}

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

  -- calling the queue adds something to it
  p.queue = setmetatable(
    { items = {} },
    {
      __index = Queue,
      __call = function(t, v, pos)
        if pos then table.insert(t.items, pos, v) else table.insert(t.items, v) end
      end,
    }
  )

  p._ = {} -- private attributes, will be cleared on hide (FIXME: not really doing it)

  p.namespace = p.namespace or "_G"
  p.pos = p.pos or Pos.AT_CURSOR
  p.follow = not p.enter and p.follow and p.pos == Pos.AT_CURSOR
  p.prevwin = win_is_valid(p.prevwin or -1) and p.prevwin or curwin()
  -- let the popup redraw automatically by default when its content changes
  p.autoredraw = true_or_false(p.autoredraw, true)

  -- popup starts disabled
  if configure_popup(setmetatable(p, mt)) then
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

--- Get a popup by its ID. How useful is that?
---@param id number
function popup.get(id)
  for ns in pairs(ALL) do
    for k, v in pairs(ALL[ns]) do
      if k == id then
        return v
      end
    end
  end
end

--- Destroy all popups in a namespace.
---@param ns string: required
function popup.destroy_ns(ns)
  for _, v in pairs(ALL[ns] or {}) do
    v:destroy_now()
  end
  ALL[ns] = nil
end

--- Destroy all popups in all tabpages. Completely aspecific!
function popup.panic()
  for _, ns in pairs(ALL) do
    for _, v in pairs(ns) do
      v:destroy_now()
    end
  end
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(win).relative ~= "" then
      win_close(win, true)
    end
  end
end

function popup.reset()
  require("popup.blend").clear_caches()
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
  if not configure_popup(self) then
    return
  end
  on_show_autocommands(self)
  open_popup_win(self)
  -- reapply highlight groups
  themes.apply(self)
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
---@param opts table
function Popup:configure(opts)
  -- hidden, we cannot reconfigure only the window
  if not self:is_visible() then
    configure_popup(merge(self, opts))
    return
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
end

--- Show the popup at the center of the screen.
---@param opts table
function Popup:notification_center(seconds, opts)
  local pos = opts and opts.pos or Pos.EDITOR_CENTER
  merge(self, opts).pos = pos
  if self.noqueue then self:show(seconds) end
end

--- Show the popup at the top right corner of the screen.
---@param opts table
function Popup:notification(seconds, opts)
  local pos = opts and opts.pos or Pos.EDITOR_TOPRIGHT
  merge(self, opts).pos = pos
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

--- Set buffer for popup.
--- `buf` can be a table with lines, or a buffer number.
---@param buf number|table|nil
---@param opts table|nil
function Popup:set_buffer(buf, opts)
  if type(buf) == "number" then
    self.has_set_buf = buf
    self.bfn = nil
  elseif type(buf) == "function" then
    self.bfn = buf
  else
    self.has_set_buf = create_buf(buf or {}, opts)
  end
  self.bufopts = opts
  configure_popup(self)
end

-- Dummy function, in case the method is called with the 'noqueue' option.
function Popup:wait(seconds)
  return self
end

return popup
-- vim: ft=lua et ts=2 sw=2 fdm=marker
