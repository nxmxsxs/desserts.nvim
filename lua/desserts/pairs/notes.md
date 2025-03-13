```lua
  local pairs = require("desserts.pairs")

  pairs.setup({
    pairs = {
      pairs.create_pair('"', '"'),
      pairs.create_pair("'", "'"),
      pairs.create_pair("{", "}"),
      pairs.create_pair("(", ")"),
      pairs.create_pair("[", "]"),
      pairs.create_pair("'''", "'''"),
      pairs.create_pair("<div>", "</div>")
      pairs.create_pair("<{id}{attrs}>", "</{id}{n}>", {
        defs = {
          id = vim.lpeg.P(""), -- only shared captures can be regex patterns...
          attrs = vim.lpeg.P(...) -- ignore all pattern,

          n = function(...)
            return ...
          end,
        },
        on_enter = function(...) end,
        on_backspace = function(...) end,
        on_space = function(...) end,
        on_open = function(...) end,
        on_close = function(...) end,
      }),
    },
  })

```
