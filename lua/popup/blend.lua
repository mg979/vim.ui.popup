--------------------------------------------------------------------------------
-- Description: Helpers for window blending
-- File:        blend.lua
-- Author:      Gianmaria Bajo <mg1979.git@gmail.com>
-- License:     MIT
-- Created:     Sun Feb 12 07:05:33 2023
--------------------------------------------------------------------------------

local api = vim.api
local fn = vim.fn
local get_hl = api.nvim_get_hl_by_name
local gui = vim.o.termguicolors
local floor = math.floor
local u = require("popup.util")

-- constants for rgb conversion
local P4 = 65536 -- math.pow(16, 4)
local P2 = 256   -- math.pow(16, 2)

-- Tables with default/blended colors.
local CACHE, BLEND, NORMAL
-- Format string for html notation
local XFMT = "#%02x%02x%02x"

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local okbit, bit = pcall(require, "bit")
local rs, ls, band
if okbit then
  rs, ls, band = bit.rshift, bit.lshift, bit.band
end

--- Translate an rgb integer to the (r, g, b) notation.
---@param rgb number
---@return table
local function b_rgb2tbl(rgb)
  local r = rs(rgb, 16)
  local g = rs(ls(rgb, 16), 24)
  local b = band(rgb, 255)
  return { r = r, g = g, b = b }
end

--- Translate an rgb integer to the (r, g, b) notation.
---@param rgb number
---@return table
local function nb_rgb2tbl(rgb)
  local r = floor((rgb / P4))
  local g = floor((rgb - r * P4) / P2)
  local b = rgb - r * P4 - g * P2
  return { r = r, g = g, b = b }
end

-- Use bitwise operation if possible
local rgb2tbl = okbit and b_rgb2tbl or nb_rgb2tbl

--- Fill the highlight definition with additional information:
--- t.rgb_bg = background in (r, g, b) notation
--- t.rgb_fg = foreground in (r, g, b) notation
--- t.bg = background in #xxxxxx notation
--- t.fg = foreground in #xxxxxx notation
---@param group string
---@return table
local function hl_full(group)
  local t = get_hl(group, gui)
  if not t.foreground and not t.background then
    return NORMAL or t
  end
  t.rgb_fg = t.foreground and rgb2tbl(t.foreground) or NORMAL.rgb_fg
  t.rgb_bg = t.background and rgb2tbl(t.background) or NORMAL.rgb_bg
  local f, b = t.rgb_fg, t.rgb_bg
  t.fg = f and string.format(XFMT, f.r, f.g, f.b) or NORMAL.fg
  t.bg = b and string.format(XFMT, b.r, b.g, b.b) or NORMAL.bg
  return t
end

local function defaults()
  NORMAL = hl_full("Normal")
  return {
    Normal = NORMAL,
    NormalFloat = hl_full("NormalFloat"),
    FloatBorder = hl_full("FloatBorder"),
  }
end



-------------------------------------------------------------------------------
-- Cached tables
-------------------------------------------------------------------------------

CACHE, BLEND = defaults(), {}

-- Reset highlight tables on colorscheme change.
api.nvim_create_autocmd("Colorscheme", {
  group = u.aug,
  callback = function(_) CACHE, BLEND, gui = defaults(), {}, vim.o.termguicolors end
})

-- Cache default highlight for group.
local function cache_hl(gr)
  local hl = hl_full(gr)
  if not hl.foreground then
    hl.foreground = NORMAL.foreground
    hl.fg = NORMAL.fg
    hl.rgb_fg = NORMAL.rgb_fg
  end
  if not hl.background then
    hl.background = NORMAL.background
    hl.bg = NORMAL.bg
    hl.rgb_bg = NORMAL.rgb_bg
  end
  CACHE[gr] = hl
  return hl
end



-------------------------------------------------------------------------------
-- Module functions
-------------------------------------------------------------------------------

--- Get background highlight color for group (hex notation).
local function bg(hlgroup)
  return CACHE[hlgroup] and CACHE[hlgroup].bg or cache_hl(hlgroup).bg
end

--- Get foreground highlight color for group (hex notation).
local function fg(hlgroup)
  return CACHE[hlgroup] and CACHE[hlgroup].fg or cache_hl(hlgroup).fg
end

-- Get table with higlight definition for group.
local function hltbl(hlgroup)
  return CACHE[hlgroup] or cache_hl(hlgroup)
end

--- Mutate src color towards dst color by altering the color luminosity.
---@param alpha number: transparency (0 is opaque, 100 is transparent)
---@param src number: rgb integer for color to change
---@param dst number: rgb integer for destination color
---@param s table: higlight definition table for source
---@param d table: higlight definition table for destination
---@param foreground bool: whether it's for the foreground (text) color
---@return string: mutated color in html format
local function _blend(alpha, src, dst, s, d, foreground)
  BLEND[src] = BLEND[src] or {}
  BLEND[src][dst] = BLEND[src][dst] or {}
  s = foreground and s.rgb_fg or s.rgb_bg
  d = d.rgb_bg
  local r, g, b = s.r, s.g, s.b
  local R, G, B = d.r, d.g, d.b
  -- we blend src, by changing luminosity to get closer to dst
  local dst_lum = floor((R + G + B) / 3)
  r = r - floor((r - dst_lum) * alpha * 0.01)
  g = g - floor((g - dst_lum) * alpha * 0.01)
  b = b - floor((b - dst_lum) * alpha * 0.01)
  -- cache the result
  BLEND[src][dst][alpha] = string.format(XFMT, r, g, b)
  return BLEND[src][dst][alpha]
end

--- Mutate a foreground color towards the background of the destination group.
---@param alpha number: transparency (0 is opaque, 100 is transparent)
---@param src string: highlight group name of the color to change
---@param dst string: highlight group name of the destination
local function blend_fg(alpha, src, dst)
  local s, d = hltbl(src), hltbl(dst)
  src = s.foreground
  dst = d.background
  if BLEND[src] and BLEND[src][dst] and BLEND[src][dst][alpha] then
    return BLEND[src][dst][alpha]
  end
  return _blend(alpha, src, dst, s, d, true)
end

--- Mutate a background color towards the background of the destination group.
---@param alpha number: transparency (0 is opaque, 100 is transparent)
---@param src string: highlight group name of the color to change
---@param dst string: highlight group name of the destination
local function blend_bg(alpha, src, dst)
  local s, d = hltbl(src), hltbl(dst)
  src = s.background
  dst = d.background
  if BLEND[src] and BLEND[src][dst] and BLEND[src][dst][alpha] then
    return BLEND[src][dst][alpha]
  end
  return _blend(alpha, src, dst, s, d, false)
end

return {
  blend_fg = blend_fg,
  blend_bg = blend_bg,
}
