local api = vim.api
local fn = vim.fn
local U = {}

--- Proxies for api functions
U.api = setmetatable({}, {
  __index = function(t, k)
    if api["nvim_" .. k] then
      t[k] = api["nvim_" .. k]
      return t[k]
    end
    return api
  end,
})

--- Return true if a new scratch buffer was created for a popup.
function U.is_temp_buffer(buf)
  return U.api.buf_is_valid(buf or -1) and U.api.buf_get_var(buf, "popup_scratch_buffer")
end

function U.delete_popup_buffers(p)
  if U.is_temp_buffer(p.buf) then
    U.api.buf_delete(p.buf)
    local bbuf = p.buf - 1
    if p.wincfg.border and fn.bufexists(bbuf) == 1 and fn.buflisted(bbuf) == 0 then
      local lines = U.api.buf_get_lines(bbuf, 1, -1, true)
      if #lines == 1 and lines[1] == '' then
        U.api.buf_delete(bbuf)
      end
    end
  end
end

return U
