This is a (WIP) library for popup generation inside Neovim.

Goals:

- easy to use
- useful out-of-the-box
- powerful

To a lesser extent:

- extensible
- eye-candies

Currently done:

✔  popup creation at different positions (cursor, editor, window)  
✔  methods chaining (async queue)  
✔  fade to background (also border and text)  
✔  move, animate  
✔  drag/resize with mouse  

To do next:

☐  popup during completion, working also for built-in completion  
☐  signature help, independent from lsp (should also work with tags)  

Lower priority:

☐  draggable title bar  

There is an interactive test file, you can take a look in this repo at:

    test.lua

Note: this is just a library you can load with `require("popup")` where you
want to use it, for example:
```lua
local popup = require("popup")
local p = popup.new {
  "Good one!",
  wincfg = { border = "rounded" },
  }:show():fade():hide(0.2) -- show, fade, hide for 0.2s and show again
```

Some asciinema takes (there are artifacts):

- [chainable methods](https://asciinema.org/a/Q6kEqK2PeI76vS4d7lASQLBwV)
- [different positions](https://asciinema.org/a/fRlYbybzLt7zZITqyH1G7xJ8l)
- [draggable/resizable popups](https://asciinema.org/a/1Drquqwk0XvTzENlM5woYhQSc)
- [animated popups](https://asciinema.org/a/A405KJEyNci9m5lmOqwgJKith)
- [custom popup methods](https://asciinema.org/a/HszyYcdYZlXNRGSAz0WHfU7iP)
