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

local Pair = {}

---@class desserts.pairs.Pair
---@field open any
---@field close any
---@field captures table<string, string>
Pair.O = {}

Pair.I = {
	mt = {
		__index = Pair.O,
		__metatable = true,
	},
}

local ParsedNode = {}

---@class desserts.util.trie.ParsedNode
ParsedNode.O = {}

ParsedNode.I = {
	mt = {
		__index = ParsedNode.O,
		__metatable = true,
	},
}

---@param node desserts.util.trie.Node
---@return desserts.util.trie.Node
function ParsedNode.O:extend_node(node)
	error("`ParsedNode:extend_node` not implemented")
end

---@param ecx desserts.pairs.ExpandCtx
---@return string
function ParsedNode.O:expand(ecx)
	error("`ParsedNode:expand` not implemented")
end

local ParsedCharNode = {}

---@class desserts.util.trie.ParsedCharNode: desserts.util.trie.ParsedNode
---@field buf string
ParsedCharNode.O = {}

ParsedCharNode.I = {
	mt = {
		__index = ParsedCharNode.O,
		__metatable = true,
	},
}

function ParsedCharNode.O:extend_node(node)
	for i = 1, #self.buf do
		local c = self.buf:sub(i, i)
		node = node:insert_child(c)
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

---@class desserts.util.trie.ParsedPatNode: desserts.util.trie.ParsedNode
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
	if not node.pat then
		node.pat = self.pat
	else
		node.pat = node.pat + self.pat
	end

	return node
end

function ParsedPatNode.O:expand(ecx)
	return ecx.captures[self.name] or ""
end

---@param opts { pat: vim.lpeg.Pattern, name: string }
---@return desserts.util.trie.ParsedPatNode
function ParsedPatNode.I.new(opts)
	local self = setmetatable({}, ParsedPatNode.I.mt)

	self.pat = opts.pat
	self.name = opts.name

	return self
end

local ParsedNodeParts = {}

---@class (private) desserts.pairs.ParsedNodeParts
---@field parts desserts.util.trie.ParsedNode[]
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
---@return desserts.util.trie.ParsedNode[]
function M.parse(pair_str, opts)
	return pair_parser(opts):match(pair_str)
end

return M
