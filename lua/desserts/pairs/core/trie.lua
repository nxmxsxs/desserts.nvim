local M = {}

local Node = {}

---@class desserts.pairs.Node
---@field children table<(integer|desserts.pairs.Node), desserts.pairs.Node>
---@field len integer
---@field pat? vim.lpeg.Pattern
---@field leaf? desserts.pairs.trie.ParsedNode[]
Node.O = {}

Node.I = {
	mt = {
		__index = Node.O,
		__metatable = true,
	},
}

function Node.I.new()
	local self = setmetatable({}, Node.I.mt)

	self.children = {}
	self.len = 0

	return self
end

--- ---@param ecx { captures: table<string, string> }
--- function Node.O:expand(ecx)
--- 	if not self.leaf then
--- 		return nil
--- 	end
---
--- 	local out = {}
--- 	for _, n in ipairs(self.leaf) do
--- 		table.insert(out, n:expand(ecx))
--- 	end
---
--- 	return table.concat(out, "")
--- end

---@class (private) desserts.pairs.Node.Ref
---@field value desserts.pairs.Node
---@overload fun(): desserts.pairs.Node?

---@return desserts.pairs.Node.Ref
function Node.O:ref()
	return setmetatable({ value = self }, {
		__call = function(o)
			return o.value
		end,
		__mode = "v",
	})
end

---@param input string
---@return desserts.pairs.Node?, {id: string, match: string}?
function Node.O:match(input)
	if self.pat then
		local capture = self.pat:match(input)

		if capture then
			return self, { id = capture, match = input }
		end
	end

	local key = input:sub(#input, #input)

	local next_node = self.children[string.byte(key)]
	if next_node then
		return next_node, nil
	end

	next_node = self.children[self]
	if not next_node then
		return nil, nil
	end
	assert(next_node.pat)

	local capture = next_node.pat:match(key)
	if not capture then
		return nil, nil
	end

	return next_node, { id = capture, match = input }
end

local Trie = {}

---@class desserts.pairs.Trie
---@field root desserts.pairs.Node
Trie.O = {}

Trie.I = {
	mt = {
		__index = Trie.O,
		__metatable = true,
	},
}

---@return desserts.pairs.Trie
function Trie.I.new()
	local self = setmetatable({}, Trie.I.mt) --[[@as desserts.pairs.Trie]]

	self.root = Node.I.new()

	return self
end

---@param parsed_nodes desserts.pairs.trie.ParsedNode[]
---@param leaf desserts.pairs.trie.ParsedNode[]
---@return desserts.pairs.Node
function Trie.O:insert(parsed_nodes, leaf)
	local curr = self.root
	for _, parsed_node in ipairs(parsed_nodes) do
		curr = parsed_node:extend_node(curr)
	end
	assert(not curr.pat, "pattern nodes cannot be leaf nodes")
	curr.leaf = leaf

	return curr
end

--- ---@param s desserts.util.trie.Node
--- ---@param b integer?
--- ---@return string[]
--- local function print_trie_table(s, b)
--- 	local mark
--- 	if not s then
--- 		return { "nil" }
--- 	end
--- 	if b then
--- 		if s.leaf then
--- 			mark = string.char(b) .. ";"
--- 		else
--- 			mark = string.char(b) .. "─"
--- 		end
--- 	else
--- 		mark = "├─"
--- 	end
--- 	if s.len == 0 then
--- 		return { mark }
--- 	end
--- 	local lines = {} ---@type string[]
--- 	for char, child in pairs(s.children) do
--- 		local child_lines = print_trie_table(child, char)
--- 		for _, child_line in ipairs(child_lines) do
--- 			table.insert(lines, child_line)
--- 		end
--- 	end
--- 	local child_count = 0
--- 	for i, line in ipairs(lines) do
--- 		local line_parts = {}
--- 		if line:match("^[a-zA-Z%p]") then
--- 			child_count = child_count + 1
--- 			if i == 1 then
--- 				line_parts = { mark }
--- 			elseif i == #lines or child_count == s.len then
--- 				line_parts = { "└─" }
--- 			else
--- 				line_parts = { "├─" }
--- 			end
--- 		else
--- 			if i == 1 then
--- 				line_parts = { mark }
--- 			elseif s.len > 1 and child_count ~= s.len then
--- 				line_parts = { "│ " }
--- 			else
--- 				line_parts = { "  " }
--- 			end
--- 		end
--- 		table.insert(line_parts, line)
--- 		lines[i] = table.concat(line_parts)
--- 	end
--- 	return lines
--- end
---
--- ---@param o desserts.util.trie.Trie
--- function Trie.I.mt.__tostring(o)
--- 	return table.concat(print_trie_table(o.root), "\n")
--- end

M.new = Trie.I.new

M.Node = {
	new = Node.I.new,
}

return M
