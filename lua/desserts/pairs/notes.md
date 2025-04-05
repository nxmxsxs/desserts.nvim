# Notes

```lua
  local pairs = require("desserts.pairs")

  local singlequotes = pairs.create_pair("'", "'")
  local doublequotes = pairs.create_pair('"', '"')
  local curlybrackets = pairs.create_pair("{", "}")
  local parentheses = pairs.create_pair("(", ")")
  local squarebrackets = pairs.create_pair("[", "]")
  local singlequotes3 = pairs.create_pair("'''", "'''")
  local doublequotes3 = pairs.create_pair('"""', '"""')
  local xmltag = pairs.create_pair("<{id} {attrs}>", "</{id}>", {
    defs = {
      id = vim.lpeg.P(...),
      attrs = vim.lpeg.P(...)
    },
  })

  pairs.setup({
    pairs = {
      doublequotes,
      singlequotes,
      curlybrackets,
      parentheses,
      squarebrackets,
      singlequotes3,
      xmltag,
    },

  })

```

## Brainstorming

- I need to come up with a consistent scheme for handling `*quotes` and `*quotes3`
interactions or overlapping pairs in general
  - Using `singlequotes` and `singlequotes3` as an example:
    - buf=``; user inputs `'` which triggers a `singlequotes` expansion => buf=`'|'` (`|` is the cursor)
      - This registers an open_extmark spanning the left `'`, a close_extmark spanning the right `'` and an openclose_extmark spanning the entire pair
    - buf=`'|'`; user inputs `'`; This triggers a cursor jump as the insert char is equal to the char after the cursor => buf=`''|`
    - buf=`''|`; user inputs `'`; This triggers a `singlequotes3` expansion => buf=`'''|'''`
      - This registers an open_extmark spanning the left `'''`, a close_extmark spanning the right `'''` and an openclose_extmark spanning the entire pair
    - Problem is what to do with the first `singlequote` pair; I think it's effectively invalid and should be discarded but what would be the condition for discarding a pair?
