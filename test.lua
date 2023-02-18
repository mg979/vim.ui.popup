-------------------------------------------------------------------------------
-- Notes for when sourcing this file:
-- 1. assuming that gc toggles comments (from commenting plugin)
-- 2. @q is set to execute the current line
-- 3. @w is set to execute the current paragraph
-- 4. <space><space> is set to proceed to the next section
-- 5. <space><esc> is set to go back to the previous section
--
-- AND: if you uncomment some parts with actual code, comment them back after
-- testing them, or stuff can misbehave.
-------------------------------------------------------------------------------

vim.cmd([[
nnoremap c_ :lua require("popup").panic()<cr>
if exists(":LuaReloadAll")
  nnoremap \l :silent update \| LuaReloadAll<cr>
end
nnoremap \s :silent update \| source %<cr>
let @q = 'gcc\su'
let @w = 'gcip\su'
nnoremap <buffer> <space><space> :<c-u>call search('\n\n\zs---\+')<cr>zt
nnoremap <buffer> <space><esc>   :<c-u>call search('\n\n\zs---\+', 'b')<cr>zt
]])

local popup = require("popup")
local Pos = popup.Pos

--------------------------------------------------------------------------------
-- Options for popups configuration:
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
-- namespace    "_G"                  string    namespace for popup
-- theme        "default"             string    popup appearance
-- bufopts      {}                    table     buffer options: { option = value, ... }
-- winopts      {}                    table     window options: { option = value, ... }
-- wincfg       {}                    table     options for nvim_open_win
-- hide_on      can vary              table     LIST of strings: events that hide the popup
-- on_show      nil                   func      called after popup is shown
-- on_hide      nil                   func      called just before hiding the popup
-- on_dispose   nil                   func      called just before destroying the popup

-- The last three methods are invoked with the popup passed as argument. The
-- popup window is always visible when this happens.
--------------------------------------------------------------------------------

-- Different popups
local p, r, q

-- Create a scratch buffer with the given lines
local lorem = popup.make_buffer {
  "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
  "",
  "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
}

--------------------------------------------------------------------------------
-- Show this popup: it will follow the cursor, and will close on BufLeave,
-- CursorMovedI.
--------------------------------------------------------------------------------

-- You can't use `follow` and `enter` at the same time.
p = popup.new {
  buf = lorem,
  follow = true,
  -- enter = true,
}

-- @q here to show it:
-- p:show()

-------------------------------------------------------------------------------
-- A different popup
-------------------------------------------------------------------------------
-- This popup has no buffer.
r = popup.new()

-- Now it will create its buffer from the 'git status' output.
-- You could also omit 'configure' and call the object directly, that is:
-- r:configure{...} is the same as r{...}.
local function git_status(_) return vim.fn.systemlist("git status") end

r:configure {
  bfn = git_status,
  wincfg = { border = "rounded" },
}

-- same as before (but it doesn't work in the middle of chains):
-- r {
--   bfn = git_status,
--   wincfg = { border = "rounded" },
-- }


--------------------------------------------------------------------------------
-- If you press @q on one of the following lines, it will execute it.
-- When there is a number as argument, it's usually the duration of the effect.
-- Note that you may need to change window to make popup disappear, unless
-- there is hide() at the end of the event chain.
--
-- These methods use an internal async queue to be chained.
-- If you don't want async queueing, use the 'noqueue' popup option.
-- Simple chains will still work.
--------------------------------------------------------------------------------

-- p:show()                                             -- ok
-- r:show()                                             -- ok
-- r:show():fade()                                      -- ok
-- r:show():fade(5)                                     -- ok
-- r:notification():fade()                              -- ok
-- r:notification():wait():fade()                       -- ok
-- r:notification():wait():fade():hide()                -- ok
-- r:notification():wait():fade():destroy()             -- ok
-- r{ pos = Pos.EDITOR_BOTRIGHT }:show(2)               -- ok
-- r:show()                                             -- ok
-- r:notification():wait(1):hide()                      -- ok
-- r:notification(2)                                    -- ok
-- r:notification(2):fade()                             -- no, but OK (fade needs window)
-- r:show():hide():wait(2):redraw()                     -- no, but OK (redraw needs window)
-- r:show():hide():wait(2):show()                       -- ok (hides immediately after shown)
-- r:show(1):wait(2):show()                             -- ok
-- r:show():wait():hide():wait():show()                 -- ok
-- r:show():wait():hide():show()                        -- ok

-- r:show():wait():configure({ buf = vim.fn.bufnr() }) -- ok

-------------------------------------------------------------------------------
-- Moving popups
-------------------------------------------------------------------------------
-- Popups can be moved and even animated. For a simple movement, you can do:

-- r:show():wait():move("right", 10):wait():hide()

-- To animate it you can do (type zt@w on the paragraph below to test):

-- r:show():wait()
-- :move{ "right", speed = 5, cells = vim.o.columns / 3 }:wait()
-- :move{ "down", speed = 10, cells = 10 }:wait()
-- :move{ "left", speed = 5, cells = vim.o.columns / 3 }:wait()
-- :move{ "up", speed = 10, cells = 10 }:wait():hide()

-------------------------------------------------------------------------------
-- Extending the popup object
-------------------------------------------------------------------------------
-- You can create new methods and 'plug' them in a chain (type @w below):

-- r.say_ciao = function(p)
--   return p:move{ "right", speed = 5, cells = vim.o.columns / 3 }:wait()
--   :configure{ buf = { "ciao!" }, pos = Pos.EDITOR_CENTER }:wait()
--   :hide():wait():show()
-- end
-- r:show():wait():say_ciao():wait():hide()

-------------------------------------------------------------------------------
-- Drag & resize
-------------------------------------------------------------------------------
-- Popups can be made draggable/resizable with mouse/keys
-- When drag == true, the popup is focusable, and there are no autocommands to
-- close the popup by default. It can be closed with <Esc> or <RightMouse>

-- local draggable = popup.new {
--   bfn = git_status,
--   drag = true,
-- }:show()

-------------------------------------------------------------------------------
-- Different positions
-------------------------------------------------------------------------------
-- Note that isn't necessary to specify in the options what has been specified
-- already: a popup objects remembers all its options. Here I'm repeating some
-- of them because the file is sourced every time.
--
-- These popups don't follow the cursor: they will close on CursorMoved.
-- So don't move the cursor if you want to see the animations.
--
-- popup.pos is an enum with different predefined positions.
--
-- Assuming that gcip uncomments a paragraph, here below you can press @w to
-- execute a paragraph.
-------------------------------------------------------------------------------
q = popup.new { buf = lorem, wincfg = { border = "single" } }

-- q:configure({ pos = Pos.WIN_TOP} ):show():wait()
-- :configure({ pos = Pos.WIN_BOTTOM}):show()

-- q:configure({ pos = Pos.WIN_TOP, wincfg = {border = "none"} })
-- :show():wait():fade()
-- :configure({ pos = Pos.WIN_BOTTOM, wincfg = {border = "none"} })
-- :show():wait():fade():hide()

-- q:configure({ pos = Pos.EDITOR_CENTER, wincfg = {border = "none"} }):show():wait()
-- :configure({ pos = Pos.EDITOR_CENTER_LEFT, wincfg = {border = "none"} }):show():wait()
-- :configure({ pos = Pos.EDITOR_CENTER_RIGHT, wincfg = {border = "none"} }):show():wait()
-- :configure({ pos = Pos.EDITOR_CENTER_TOP, wincfg = {border = "none"} }):show():wait()
-- :configure({ pos = Pos.EDITOR_CENTER_BOTTOM, wincfg = {border = "none"} }):show()

-- q:configure({ pos = Pos.EDITOR_LEFT_WIDE}):show():wait()
-- :configure({ pos = Pos.EDITOR_RIGHT_WIDE}):show()

-- q:configure({ pos = Pos.EDITOR_TOP_WIDE}):show():wait()
-- :configure({ pos = Pos.EDITOR_BOTTOM_WIDE}):show()

-- q:configure({ pos = Pos.EDITOR_TOPLEFT, wincfg = {border = "none"} }):show():wait()
-- :configure({ pos = Pos.EDITOR_TOPRIGHT, wincfg = {border = "none"} }):show():wait()
-- :configure({ pos = Pos.EDITOR_BOTLEFT, wincfg = {border = "none"} }):show():wait()
-- :configure({ pos = Pos.EDITOR_BOTRIGHT, wincfg = {border = "none"} }):show()

-------------------------------------------------------------------------------
-- A slideshow
-------------------------------------------------------------------------------
-- r is currently configured to show 'git status', let's use the other buffer
-- instead: when popup.bfn is defined, it takes precedence over popup.buf.
-- It is made nil if you assign a different buffer with `configure`, as in this
-- case. Just so you know that the previous `bfn` field will be gone.
-- Press @w on the paragraph below.

-- r { buf = lorem, wincfg = { border = "single" } }
-- :configure({ pos = Pos.WIN_TOP }):show():wait():fade(0.5)
-- :configure({ pos = Pos.WIN_BOTTOM }):show():wait():fade(0.5)
-- :configure({ pos = Pos.WIN_TOP, wincfg = {border = "none"} }):show():wait():fade(0.5)
-- :configure({ pos = Pos.WIN_BOTTOM }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_CENTER }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_CENTER_LEFT }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_CENTER_RIGHT }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_CENTER_TOP }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_CENTER_BOTTOM }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_LEFT_WIDE, wincfg = {border = "single"} }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_RIGHT_WIDE }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_TOP_WIDE }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_BOTTOM_WIDE }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_TOPLEFT, wincfg = {border = "none"} }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_TOPRIGHT }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_BOTLEFT }):show():wait():fade(0.5)
-- :configure({ pos = Pos.EDITOR_BOTRIGHT }):show():wait():fade(0.5):hide()
