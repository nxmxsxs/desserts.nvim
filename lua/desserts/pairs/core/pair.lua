local M = {}

local lpeg = vim.lpeg

local C = lpeg.C
local Ct = lpeg.Ct
local P = lpeg.P
local R = lpeg.R
local S = lpeg.S
local V = lpeg.V

local ParsedPair = {}

---@class desserts.pairs.ParsedPair
ParsedPair.O = {}

ParsedPair.I = {
	mt = {
		__index = ParsedPair.O,
		__metatable = true,
	},
}

-- NB:
-- so I would need some "extmark" to "pair" map
-- before that, each pair couple has its own extmark (open, close extmarks)
-- so I might need a way to differentiate between the different types of extmarks, a flag stored somewhere maybe...
-- Would I need a 3rd extmark that spans both open and close pairs? Could be useful for discovering parent pairs...
--  I might have to FAFO how much performance is impacted

local PairDef = {}

---@class (private) desserts.pairs.PairDef
---@field parsed_open desserts.pairs.trie.ParsedNode[]
---@field parsed_close desserts.pairs.trie.ParsedNode[]
---@field filetypes_pred? fun(...): boolean
---@field close_pred? fun(...): boolean
PairDef.O = {}

PairDef.I = {
	mt = {
		__index = PairDef.O,
		__metatable = true,
	},
}

---comment
---@param parsed_open desserts.pairs.trie.ParsedNode[]
---@param parsed_close desserts.pairs.trie.ParsedNode[]
function PairDef.I.new(parsed_open, parsed_close)
	local self = setmetatable({}, PairDef.I.mt)
	self.parsed_open = parsed_open
	self.parsed_close = parsed_close

	return self
end

local Pair = {}

---@class desserts.pairs.Pair
---@field open_extmark_id integer
---@field close_extmark_id? integer
---@field openclose_extmark_id? integer
Pair.O = {}

Pair.I = {
	mt = {
		__index = Pair.O,
		__metatable = true,
	},
}

---@param opts {open_extmark_id: integer, close_extmark_id: integer, openclose_extmark_id: integer, captures?: table<string, string>}
function Pair.I.new(opts)
	local self = setmetatable({}, Pair.I.mt)
	self.open_extmark_id = opts.open_extmark_id
	self.close_extmark_id = opts.close_extmark_id
	self.openclose_extmark_id = opts.openclose_extmark_id
	return self
end

local ParsedNode = {}

---@class desserts.pairs.trie.ParsedNode
ParsedNode.O = {}

ParsedNode.I = {
	mt = {
		__index = ParsedNode.O,
		__metatable = true,
	},
}

---@param node desserts.pairs.Node
---@return desserts.pairs.Node
function ParsedNode.O:extend_node(node)
	error("`ParsedNode:extend_node` not implemented")
end

---@param ecx desserts.pairs.ExpandCtx
---@return string
function ParsedNode.O:expand(ecx)
	error("`ParsedNode:expand` not implemented")
end

local ParsedCharNode = {}

---@class desserts.pairs.trie.ParsedCharNode: desserts.pairs.trie.ParsedNode
---@field buf string
ParsedCharNode.O = {}

ParsedCharNode.I = {
	mt = {
		__index = ParsedCharNode.O,
		__metatable = true,
	},
}

function ParsedCharNode.O:extend_node(node)
	local m_trie = require("desserts.pairs.core.trie")

	for i = 1, #self.buf do
		local c = self.buf:sub(i, i)
		local b = string.byte(c)
		if not node.children[b] then
			node.children[b] = m_trie.Node.new()
			node.len = node.len + 1
		end
		node = node.children[b]
	end
	return node
end

function ParsedCharNode.O:expand(ecx)
	return self.buf
end

---@param buf string
function ParsedCharNode.I.new(buf)
	local self = setmetatable({}, ParsedCharNode.I.mt)

	self.buf = buf

	return self
end

local ParsedPatNode = {}

---@class desserts.pairs.trie.ParsedPatNode: desserts.pairs.trie.ParsedNode
---@field name string
---@field pat vim.lpeg.Pattern
ParsedPatNode.O = {}

ParsedPatNode.I = {
	mt = {
		__index = ParsedPatNode.O,
		__metatable = true,
	},
}

function ParsedPatNode.O:extend_node(node)
	local m_trie = require("desserts.pairs.core.trie")

	if not node.children[node] then
		local new_node = m_trie.Node.new()
		new_node.pat = self.pat
		node.children[node] = new_node
	else
		local curr = node.children[node]
		curr.pat = curr.pat + self.pat
	end

	return node.children[node]
end

function ParsedPatNode.O:expand(ecx)
	return ecx.captures[self.name] or ""
end

---@param opts { pat: vim.lpeg.Pattern, name: string }
---@return desserts.pairs.trie.ParsedPatNode
function ParsedPatNode.I.new(opts)
	local self = setmetatable({}, ParsedPatNode.I.mt)

	self.pat = opts.pat
	self.name = opts.name

	return self
end

local ParsedNodeParts = {}

---@class (private) desserts.pairs.ParsedNodeParts
---@field parts desserts.pairs.trie.ParsedNode[]
ParsedNodeParts.O = {}

---@param opts { defs: table<string, vim.lpeg.Pattern> }
local function pair_parser(opts)
  -- stylua: ignore
  return P({
    "config",

    config = Ct(V("part") ^ 0),
    part = V("capture") + V("literal"),
    capture = P("{") * C((R("az", "AZ", "09") + S("_-")) ^ 1) * P("}") / function(name)
      local pat = opts.defs[name]
      if pat and type(pat) == "userdata" then
        pat = pat / function(capture)
          return name
        end
      end
      return ParsedPatNode.I.new({ name = name, pat = pat })
    end,
    literal = C((P(1) - V("capture")) ^ 1) / function(text)
      return ParsedCharNode.I.new(text)
    end,
  } --[[@as table]])
end

---@param pair_str string
---@param opts { defs: any }
---@return desserts.pairs.trie.ParsedNode[]
function M.parse(pair_str, opts)
	return pair_parser(opts):match(pair_str)
end

M.Pair = {
	new = Pair.I.new,
}

M.PairDef = {
	new = PairDef.I.new,
}

return M
