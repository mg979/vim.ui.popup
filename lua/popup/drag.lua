--------------------------------------------------------------------------------
-- Mappings to drag/resize the popup
--------------------------------------------------------------------------------
-- Credits: github.com/tamton-aquib/flirt.nvim for inspiration

local api = require("popup.util").api
local winid = vim.fn.win_getid
local setmap = vim.keymap.set
local CUSTOM = require("popup.wincfg").Pos.CUSTOM
local min, max = math.min, math.max

--- Mapping for mouse drag release.
---@param p table: popup object
---@param m table: mouse position
---@return table: mouse position when dragging starts
local function map_release(p, m)
  -- release mappings
  for _, map in ipairs({ "<LeftRelease>", "<C-LeftRelease>" }) do
    setmap("n", map, function()
      if winid() ~= p.win then
        return
      end
      vim.cmd("nunmap <buffer> <LeftRelease>")
      vim.cmd("nunmap <buffer> <C-LeftRelease>")
      p.dragging = nil
    end, { silent = true, buffer = p.buf })
  end

  -- mouse position when dragging starts
  return m
end

-- Close popup.
local function Close(p)
  if winid() ~= p.win then
    return
  end
  p.dragging = nil
  p:hide()
end

--- Drag window.
---@param p table: popup object
local function Drag(p)
  if winid() ~= p.win then
    return
  elseif p.pos ~= CUSTOM then
    p:custom()
  end

  local m = vim.fn.getmousepos()
  local w = api.win_get_config(p.win)

  p.dragging = p.dragging or map_release(p, m)

  w.row = m.screenrow - p.dragging.winrow
  w.col = m.screencol - p.dragging.wincol

  api.win_set_config(p.win, w)
end

--- Move window.
---@param p table: popup object
local function Move(p, dir, n)
  if winid() ~= p.win then
    return
  elseif p.pos ~= CUSTOM then
    p:custom()
  end

  local w = api.win_get_config(p.win)
  local r, c = w.row[false], w.col[false]

  if dir == "left" then
    c = c - n
  elseif dir == "right" then
    c = c + n
  elseif dir == "up" then
    r = r - n
  else
    r = r + n
  end

  w.row = min(max(r, 1), vim.o.lines - w.height)
  w.col = min(max(c, 1), vim.o.columns - w.width)
  api.win_set_config(p.win, w)
end

--- Resize window by dragging the borders with <C-LeftDrag>.
---@param p table: popup object
local function Resize(p)
  if winid() ~= p.win then
    return
  elseif p.pos ~= CUSTOM then
    p:custom()
  end

  local m = vim.fn.getmousepos()
  local cfg = api.win_get_config(p.win)
  local r, c, w, h = cfg.row[false], cfg.col[false], cfg.width, cfg.height

  p.dragging = p.dragging or map_release(p, m)

  local up = m.screenrow < p.dragging.screenrow
  local down = m.screenrow > p.dragging.screenrow
  local left = m.screencol < p.dragging.screencol
  local right = m.screencol > p.dragging.screencol

  -- leave a dead zone in the central third
  local lside = m.screencol < c + w / 3
  local rside = m.screencol > c + w / 3 * 2
  local top = m.screenrow < r + h / 3
  local bot = m.screenrow > r + h / 3 * 2

  -- record the last position
  p.dragging = m

  if left then
    if lside then -- increase width
      c = c - 1
      w = w + 1
    elseif rside then
      w = w - 1
    end
  elseif right then
    if lside then -- reduce width
      c = c + 1
      w = w - 1
    elseif rside then
      w = w + 1
    end
  end

  if up then
    if top then -- increase height
      r = r - 1
      h = h + 1
    elseif bot then
      h = h - 1
    end
  elseif down then
    if top then -- reduce height
      r = r + 1
      h = h - 1
    elseif bot then
      h = h + 1
    end
  end

  cfg.row = max(r, 1)
  cfg.col = max(c, 1)
  cfg.width = max(w, 1)
  cfg.height = max(h, 1)
  api.win_set_config(p.win, cfg)
end

--- Set up drag mappings for popup buffer.
--- On left drag, popup is moved. On left release, but only after drag, focus
--- returns to previous window. If popup has focus, right mouse closes it.
---@param p table: popup object
return function(p)
  -- drag
  setmap("n", "<LeftDrag>", function() Drag(p) end, { silent = true, buffer = p.buf })

  -- resize with keys
  setmap("n", "<S-Up>", "<cmd>wincmd -<cr>", { silent = true, buffer = p.buf })
  setmap("n", "<S-Down>", "<cmd>wincmd +<cr>", { silent = true, buffer = p.buf })
  setmap("n", "<S-Left>", "<cmd>wincmd <lt><cr>", { silent = true, buffer = p.buf })
  setmap("n", "<S-Right>", "<cmd>wincmd ><cr>", { silent = true, buffer = p.buf })

  -- resize with mouse
  local resize = function() Resize(p, vim.v.count1) end
  setmap("n", "<C-LeftDrag>", resize, { silent = true, buffer = p.buf })

  -- disable <C-LeftMouse> or it will trigger
  setmap("n", "<C-LeftMouse>", "<nop>", { silent = true, buffer = p.buf })

  -- move with keys
  local move = function(dir)
    return function() Move(p, dir, vim.v.count1) end
  end
  setmap("n", "<Up>", move("up"), { silent = true, buffer = p.buf })
  setmap("n", "<Down>", move("down"), { silent = true, buffer = p.buf })
  setmap("n", "<Left>", move("left"), { silent = true, buffer = p.buf })
  setmap("n", "<right>", move("right"), { silent = true, buffer = p.buf })

  -- close
  local extend = vim.o.mousemodel == "extend" or vim.o.mousemodel == ""
  local rmouse = extend and "<RightMouse>" or "g<LeftMouse>"
  for _, m in ipairs({ "<Esc>", rmouse }) do
    setmap("n", m, function() Close(p) end, { silent = true, buffer = p.buf })
  end
end
