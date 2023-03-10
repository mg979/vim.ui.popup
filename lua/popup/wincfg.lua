-------------------------------------------------------------------------------
-- Window configuration for nvim_open_win()
-------------------------------------------------------------------------------

local api = require("popup.util").api
local strwidth = vim.fn.strdisplaywidth
local buf_get_option = api.buf_get_option
local win_is_valid = api.win_is_valid

-- popup standard positions
local Pos = {
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

--  We keep the tabline visible.
local function tabline_row()
  return vim.o.showtabline ~= 0 and 1 or 0
end

--- Get border width for popup window (sum of both sides).
local function border_width(p)
  return (p.wincfg.border or "none") ~= "none" and 2 or 0
end

--- Get all buffer lines.
local function getlines(buf)
  return api.buf_get_lines(buf, 0, -1, true)
end

--- Get row for popup, based on popup position.
local function get_row(p, height)
  local rows = vim.o.lines
  local wh = api.win_get_height(p.prevwin)
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

--- Get column for popup, based on popup position.
local function get_column(p, width)
  local cols = vim.o.columns
  local x = api.win_get_position(p.prevwin)[2]
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
    if p.textwidth ~= false then
      w = math.min(w, math.max(buf_get_option(p.buf, "textwidth"), 79))
    end
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
    w = p._.wincfg.width or p.wincfg.width or calc_width(p, lines)
    h = p._.wincfg.height or p.wincfg.height or calc_height(p, lines, w)
    return w, h
  elseif p.pos == Pos.WIN_TOP or p.pos == Pos.WIN_BOTTOM then
    w = api.win_get_width(p.prevwin) - border_width(p)
  else
    w = p.wincfg.width or calc_width(p, lines)
  end
  return w, p.wincfg.height or calc_height(p, lines, w)
end

--- Update popup.wincfg by reading directly from window configuration, but
--- adjust some values because of different defaults, and check problematic
--- values, in case the config couldn't be read. If the window isn't valid,
--- return the last valid configuration.
---@param p table
---@return table
local function update_wincfg(p)
  local o = win_is_valid(p.win or -1) and api.win_get_config(p.win) or p._.wincfg
  o.style = o.style or "minimal"
  o.win = o.relative == "win" and o.win or nil
  return o
end

--- Generate the window configuration to pass to nvim_open_win().
---@param p table
---@return table
local function do_wincfg(p)
  if p.pos == Pos.CUSTOM then
    return update_wincfg(p)
  end
  if not api.win_is_valid(p.prevwin) then
    p.prevwin = api.get_current_win()
  end
  local o = p.wincfg
  local editor = p.pos >= Pos.EDITOR_CENTER
  local cursor = p.pos == Pos.AT_CURSOR
  local win = not editor and not cursor and p.prevwin
  local lines = getlines(p.buf)
  local width, height = calc_dimensions(p, lines)
  return {
    relative = cursor and "cursor" or editor and "editor" or "win",
    win = win or nil,
    anchor = o.anchor or "NW",
    width = width,
    height = height,
    col = get_column(p, width),
    row = get_row(p, height),
    focusable = p.enter or p.drag or (o.focusable == true and true or false),
    bufpos = o.bufpos,
    zindex = o.zindex,
    style = o.style or "minimal",
    border = o.border or "none",
    noautocmd = o.noautocmd,
  }
end

return {
  do_wincfg = do_wincfg,
  update_wincfg = update_wincfg,
  Pos = Pos,
}
