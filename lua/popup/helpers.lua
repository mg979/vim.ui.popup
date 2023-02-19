--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

local api = vim.api
local reconfigure = api.nvim_win_set_config
local buf_is_valid = api.nvim_buf_is_valid
local win_is_valid = api.nvim_win_is_valid
local buf_set_option = api.nvim_buf_set_option
local win_get_option = api.nvim_win_get_option
local win_set_option = api.nvim_win_set_option
local do_wincfg = require("popup.wincfg").do_wincfg

--------------------------------------------------------------------------------
-- Local functions
--------------------------------------------------------------------------------

local function setlines(buf, lines)
  lines = type(lines) == "string" and vim.split(lines, "\n", { trimempty = true }) or lines
  return vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
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

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local H = {}

--- Merge two tables in place, the second into the first one.
---@param t1 table
---@param t2 table
---@param keep bool: whether existing values from t1 should be preserved.
---@return table
function H.merge(t1, t2, keep)
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

--- Do a protected call and print any error message, before returning results.
--- Return false if there was an error, true if the called function returned
--- nothing, or its return value.
---@vararg any
---@return bool|any
function H.call(...)
  local ok, res = pcall(...)
  if not ok then
    api.nvim_echo({{"popup:", "Error"}, {" " .. res, "WarningMsg"}}, true, {})
    return false
  end
  return res or true
end

--- Return true if a new scratch buffer was created for a popup.
function H.is_temp_buffer(p)
  return buf_is_valid(p.buf or -1) and api.nvim_buf_get_var(p.buf, "popup_scratch_buffer")
end

--- Create buffer and set its options from optional table.
---@param lines table
---@param opts table
---@return number
function H.create_buf(lines, opts)
  local bnr = api.nvim_create_buf(false, true)
  setlines(bnr, lines)
  -- make buffer scratch by default
  opts = opts or {}
  opts.scratch = opts.scratch ~= false
  set_bufopts(bnr, opts)
  -- mark the buffer, so that it is reused, then wiped when popup is destroyed
  api.nvim_buf_set_var(bnr, "popup_scratch_buffer", true)
  return bnr
end

-------------------------------------------------------------------------------
-- Popup generation, helpers
-------------------------------------------------------------------------------
-- These are functions that require a popup as argument, but are not popup
-- methods, so they can't be accessed like Popup:fn().

local function create_or_reuse_buf(p, lines, opts)
  if H.is_temp_buffer(p) then
    setlines(p.buf, lines)
    return p.buf
  end
  return H.create_buf(lines, opts)
end

local function prepare_buffer(p)
  if p.has_set_buf then
    -- cleared in update_win
    p.buf = p.has_set_buf
    -- must be sure that there is no function to generate buffer
    p.bfn = nil
  elseif p.bfn then
    -- will get buffer (or its lines) from result of function
  elseif p[1] then
    -- make scratch buffer with given lines
    p.buf = create_or_reuse_buf(p, p[1] or {}, p.bufopts)
    p[1] = nil
  elseif not buf_is_valid(p.buf or -1) then
    -- make scratch buffer
    p.buf = create_or_reuse_buf(p, {}, p.bufopts)
  end

  if not p.bfn and not buf_is_valid(p.buf or -1) then
    error("Popup needs a valid buffer.")
  end

  if p.drag then
    require("popup.drag")(p)
  end
end

function H.buf_from_func(p)
  local buf, opts = p.bfn(p)
  if type(buf) == "number" then
    return buf
  elseif type(buf) == "table" then
    return create_or_reuse_buf(p, buf, opts)
  end
end

--- Update window, changing buffer if necessary. Set the cursor at the top of
--- the buffer.
---@param p table
function H.update_win(p)
  if p.has_set_buf then
    vim.fn.win_execute(p.win, "noautocmd buffer " .. p.buf, true)
    p.has_set_buf = nil
  end
  if next(p.wincfg) then
    reconfigure(p.win, do_wincfg(p))
  end
  api.nvim_win_set_cursor(p.win, { 1, 0 })
end

--- To avoid flicker, set lazyredraw, but restore old value even if there were
--- errors. Also set up closing autocommands, and set buffer local variables.
--- Return success.
---@param p table
---@return bool
function H.open_popup_win(p)
  local oldlazy = vim.o.lazyredraw
  vim.o.lazyredraw = true

  local function _open()
    p.wincfg = p.wincfg or {}
    -- cursorline disabled for minimal style
    p.winopts = H.merge(
      {
        cursorline = p.wincfg.style ~= nil and p.wincfg.style ~= "minimal",
        wrap = true,
      },
      p.winopts or {}
    )
    -- if previous window is valid, just reconfigure, otherwise open a new one
    if win_is_valid(p.win or -1) then
      H.update_win(p)
    else
      p.win = api.nvim_open_win(p.buf, p.enter and not p.bfn, do_wincfg(p))
      p._.blend = p.winopts.winblend or p._.blend or win_get_option(p.win, "winblend")
      p.has_set_buf = nil -- this should be cleared anyway
    end
    -- set window options
    for opt, val in pairs(p.winopts) do
      win_set_option(p.win, opt, val)
    end
    -- turn off gutter by default
    if not p.gutter then
      win_set_option(p.win, "number", false)
      win_set_option(p.win, "signcolumn", "no")
    end
  end

  local ok = H.call(_open)

  vim.o.lazyredraw = oldlazy
  return ok
end

--- Ensure the popup object has a valid buffer. Return success.
---@param p table
---@return bool
function H.configure_popup(p)
  -- ensure popup has a valid buffer
  local ok = H.call(prepare_buffer, p)
  -- if the window is visible, we update it, why not
  if ok and win_is_valid(p.win or -1) then
    H.update_win(p)
  end
  return ok
end

return H
