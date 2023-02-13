--------------------------------------------------------------------------------
-- Description: Helpers for window blending
-- File:        blend.lua
-- Author:      Gianmaria Bajo <mg1979.git@gmail.com>
-- License:     MIT
-- Created:     Sun Feb 12 07:05:33 2023
--------------------------------------------------------------------------------

local api = vim.api
local fn = vim.fn
local floor = math.floor
local u = require("popup.util")

-- constants for rgb conversion
local P4 = 65536 -- math.pow(16, 4)
local P2 = 256   -- math.pow(16, 2)

-- Tables with cached highlights/blended colors. They are cleared on color
-- scheme change. vim.ui.popup.reset() clears them too.
--
-- CACHE is a table with highlight definitions, indexed by group name.
-- NORMAL is a shorthand for CACHE.Normal.
-- BLEND is a table with structure:
-- {
--    [src rgb (integer)] = {
--      [dst rgb (integer)] = {
--        [0] = (color in html notation at blend level == index),
--        [1] = ...,
--        ...
--      }
--    }
-- }
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
  local t = api.nvim_get_hl_by_name(group, vim.o.termguicolors)
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

--- Mutate src color towards dst color by altering the color luminosity.
---@param alpha number: transparency (0 is opaque, 100 is transparent)
---@param s table: higlight definition table for source
---@param d table: higlight definition table for destination
---@param foreground bool: whether it's for the foreground (text) color
---@return string: mutated color in html format
local function _blend_to_bg(alpha, s, d, foreground)
  -- integer rgb values
  local si, di = foreground and s.foreground or s.background, d.background
  -- no difference, no need to blend anything
  if si == di then
    BLEND[si][di][alpha] = d.background
    return BLEND[si][di][alpha]
  end
  s = foreground and s.rgb_fg or s.rgb_bg
  d = d.rgb_bg
  local r, g, b = s.r, s.g, s.b
  local R, G, B = d.r, d.g, d.b
  -- we blend src, by changing luminosity to get closer to dst
  local dst_lum = floor((R + G + B) / 3)
  local a = alpha * 0.01
  r = r - floor((r - dst_lum) * a)
  g = g - floor((g - dst_lum) * a)
  b = b - floor((b - dst_lum) * a)
  -- cache the result
  BLEND[si][di][alpha] = string.format(XFMT, r, g, b)
  return BLEND[si][di][alpha]
end



-------------------------------------------------------------------------------
-- Cached tables
-------------------------------------------------------------------------------

CACHE, BLEND = defaults(), {}

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

local function clear_caches()
  CACHE, BLEND = defaults(), {}
end

-- Reset highlight tables on colorscheme change.
api.nvim_create_autocmd("Colorscheme", {
  group = u.aug,
  callback = clear_caches,
})



-------------------------------------------------------------------------------
-- Module functions
-------------------------------------------------------------------------------

-- Get table with higlight definition for group.
local function hltbl(hlgroup)
  return CACHE[hlgroup] or cache_hl(hlgroup)
end

--- Mutate a background color towards the background of the destination group.
---@param alpha number: transparency (0 is opaque, 100 is transparent)
---@param src string: highlight group name of the color to change
---@param dst string: highlight group name of the destination
---@param foreground bool: whether it's for the foreground (text) color
---@return string: mutated color in html format
local function blend_to_bg(alpha, src, dst, foreground)
  local stlb, dtbl = hltbl(src), hltbl(dst)
  local s = foreground and stlb.foreground or stlb.background
  local d = dtbl.background
  -- is in blend cache?
  if BLEND[s] and BLEND[s][d] and BLEND[s][d][alpha] then
    return BLEND[s][d][alpha]
  end
  -- will be cached there
  BLEND[s] = BLEND[s] or {}
  BLEND[s][d] = BLEND[s][d] or {}
  return _blend_to_bg(alpha, stlb, dtbl, foreground)
end

return {
  blend_to_bg = blend_to_bg,
  get = hltbl,
  clear_caches = clear_caches,
}
