--------------------------------------------------------------------------------
-- Popup queue handling
--------------------------------------------------------------------------------

-- The queue table is stored in popup.queue. When popup methods are called,
-- many of them are queued rather than instantly invoked. Each method can have
-- an expected delay, depending on its arguments.
--
-- Some methods cannot be queued, therefore cannot be chained (for example
-- `is_visible` and other methods that aren't supposed to return the popup
-- object): in this case the Popup method is returned directly.

-- These methods don't want to be queued:
--    Popup.is_visible    -> bool
--    Popup.get_wincfg    -> table, 
--    Popup.hide_now      -> void, empties queue, removes autocommands
--    Popup.destroy_now   -> void, invalidates popup object

local ms = function(s) return s * 1000 end
local Popup = require("popup.popup")

local Queue = {}

function Queue:proceed(p)
  if #self.items > 0 then
    local item = table.remove(self.items, 1)
    if not self.waiting and item.wait then
      self.waiting = true
      vim.defer_fn(function()
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
  self.waiting = false
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

function Queue:notification(seconds)
  self({ "notification" })
  self:show(seconds)
end

function Queue:blend(val)
  self({ "blend", { val } })
end

function Queue:fade(for_seconds, endblend)
  self({ "fade", { for_seconds, endblend } })
end

function Queue:move(direction, cells)
  self({ "move", { direction, cells } })
end

function Queue:wait(seconds)
  self({ wait = ms(seconds or 1) })
end

function Queue:redraw()
  self({ "redraw" })
end

function Queue:custom(relative)
  self({ "custom", { relative } })
end

return Queue
