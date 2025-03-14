local M = {}

local Pairs = {
	state = {},
}

---@class (private) desserts.pairs.SetupOpts

---@param opts desserts.pairs.SetupOpts
function M.setup(opts) end

---@class (private) desserts.pairs.CreatePairOpts
---@field defs? table<string, vim.lpeg.Pattern|fun(...: any): any>
---@field on_enter? fun(...: any): any
---@field on_backspace? fun(...: any): any
---@field on_space? fun(...: any): any
---@field on_open? fun(...: any): any
---@field on_close? fun(...: any): any

Pairs.state.open_trie = require("desserts.pairs.core.trie").new()
Pairs.state.close_trie = require("desserts.pairs.core.trie").new()

---Create a new pair
---@param open_str string
---@param close_str string
---@param opts desserts.pairs.CreatePairOpts
function M.create_pair(open_str, close_str, opts)
	local parsed_open = require("desserts.pairs.core.pair").parse(open_str, { defs = opts.defs })
	local parsed_close = require("desserts.pairs.core.pair").parse(close_str, { defs = opts.defs })

	Pairs.state.open_trie:insert(parsed_open, parsed_close)
	Pairs.state.close_trie:insert(parsed_close, parsed_open)
end

M.create_pair("<{id}>", "</{id}{n}>", {
	defs = {
		id = ((vim.lpeg.R("az", "AZ", "09") + vim.lpeg.S("._-")) ^ 1 * -vim.lpeg.P(1)), -- only shared captures can be patterns, otherwise they would simply be expanded to an empty str
		attrs = vim.lpeg.P("@") * -vim.lpeg.P(1),

		n = function(...)
			return ...
		end,
	},
	on_enter = function(...) end,
	on_backspace = function(...) end,
	on_space = function(...) end,
	on_open = function(...) end,
	on_close = function(...) end,
})
M.create_pair("<", ">", {})
M.create_pair("'", "'", {})
M.create_pair('"', '"', {})
M.create_pair("{", "}", {})
M.create_pair("(", ")", {})
M.create_pair("[", "]", {})
M.create_pair("`", "`", {})

function M.state()
	return Pairs.state
end

return M
