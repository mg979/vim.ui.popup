local popup = { Pos = require("popup.wincfg").Pos }

-- api {{{1
local api = require("popup.util").api
local curwin = api.get_current_win
local win_is_valid = api.win_is_valid
local win_close = api.win_close
local H = require("popup.helpers")
-- }}}

-- Table for positions
local Pos = popup.Pos

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
-- gutter       false                 bool      disabled by default, whatever the style
-- textwidth    true                  bool      limit width to textwidth (or 79)
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

-- }}}

-------------------------------------------------------------------------------
-- Popup metatables
-------------------------------------------------------------------------------

local Queue = require("popup.queue")
local Popup = require("popup.popup")

-- Metatable for popup object:
-- 1. the looked up method must exist in either Popup or Queue
-- 2. non-queuable methods are returned right away
-- 3. queuable methods are added to the queue
-- Note: calling the popup will configure it.
local mt = {
  __index = function(p, method)
    if not Popup[method] and not Queue[method] then
      return nil
    end
    if p.noqueue and Queue[method] then
      -- not using queue, protected call of Popup method
      return function(pp, ...)
        H.call(Popup[method], pp, ...)
        return pp
      end
    elseif Queue[method] then
      return function(pp, ...)
        H.call(Queue[method], pp.queue, ...)
        Queue.proceed(pp.queue, pp)
        return pp
      end
    end
    return Popup[method]
  end,
  __call = function(t, ...) return t:configure(...) end,
}

-- Metatable for popup.queue.
-- Note: calling the queue itself inserts an item in queue.items.
local qmt = {
  __index = Queue,
  __call = function(t, v, pos)
    if pos then table.insert(t.items, pos, v) else table.insert(t.items, v) end
  end,
}

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
-- Module functions
-------------------------------------------------------------------------------

--- Create a copy of a previous popup, optionally with some different options
--- provided in the second argument.
---@param src table
---@param dst table
---@return table
local function copy(src, dst)
  dst = H.merge(dst or {}, src, true)
  -- clear private values
  dst._ = {}
  -- must have its own window and queue
  dst.win, dst.queue = -1, setmetatable({ items = {} }, qmt)
  -- make a copy of both winopts and bufopts
  dst.winopts = dst.winopts or {}
  for k, v in pairs(src.winopts or {}) do
    dst.winopts[k] = v
  end
  dst.bufopts = dst.bufopts or {}
  for k, v in pairs(src.bufopts or {}) do
    dst.bufopts[k] = v
  end
  if src.wincfg then
    if dst.pos == Pos.CUSTOM then
      -- keep current window config
      dst._.wincfg = src._.wincfg
      -- full copy, but keep new values
      for k, v in pairs(src.wincfg) do
        if not dst.wincfg[k] then
          dst.wincfg[k] = v
        end
      end
    else
      -- only keep values that can be valid for different positions
      local prev = dst.wincfg
      dst.wincfg = {
        anchor = prev.anchor,
        focusable = prev.focusable,
        style = prev.style,
        border = prev.border,
        noautocmd = prev.noautocmd,
        width = prev.width,
        height = prev.height,
      }
    end
  end
  return dst
end

--- Create a new popup object.
---@param opts table
---@return table|nil
function popup.new(opts)
  local p = opts or {}

  if p.copy then
    p = copy(p.copy, p)
    p.copy = nil
  end

  -- calling the queue adds something to it
  p.queue = setmetatable({ items = {} }, qmt)

  p._ = { wincfg = {} } -- private attributes
  p.bufopts = p.bufopts or {}
  p.winopts = p.winopts or {}
  p.wincfg = p.wincfg or {}

  p.namespace = p.namespace or "_G"
  p.pos = p.pos or Pos.AT_CURSOR
  p.follow = not p.enter and p.follow and p.pos == Pos.AT_CURSOR
  p.prevwin = win_is_valid(p.prevwin or -1) and p.prevwin or curwin()
  -- let the popup redraw automatically by default when its content changes
  p.autoredraw = true_or_false(p.autoredraw, true)

  -- popup starts disabled
  if H.configure_popup(setmetatable(p, mt)) then
    return register_popup(p)
  else
    return {}
  end
end

--- Create a buffer from given lines, apply the given options.
--- If bufopts.scratch == true, |scratch-buffer| options are set.
--- It is scratch by default.
---@param lines table|string
---@param bufopts table|nil
function popup.make_buffer(lines, bufopts)
  return H.create_buf(lines, bufopts)
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
  for _, win in ipairs(api.list_wins()) do
    if api.win_get_config(win).relative ~= "" then
      win_close(win, true)
    end
  end
end

function popup.reset()
  require("popup.blend").clear_caches()
end

--------------------------------------------------------------------------------
-- End of module
--------------------------------------------------------------------------------

return popup
-- vim: ft=lua et ts=2 sw=2 fdm=marker
