local M = {}

local Node = {}

---@class desserts.util.trie.Node
---@field children table<integer, desserts.util.trie.Node>
---@field len integer
---@field pat? vim.lpeg.Pattern
---@field leaf? desserts.util.trie.ParsedNode[]
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

---@param key string
---@return desserts.util.trie.Node
function Node.O:insert_child(key)
	assert(key:len() == 1)

	local b = string.byte(key)
	if not self.children[b] then
		self.children[b] = Node.I.new()
    self.len = self.len + 1
	end
	return self.children[b]
end

function Node.O:next_child(key)
	assert(key:len() == 1)

	local b = string.byte(key)
	return self.children[b]
end

---@param ecx { captures: table<string, string> }
function Node.O:expand(ecx)
  if not self.leaf then
    return nil
  end

  local out = {}
  for _, n in ipairs(self.leaf) do
    table.insert(out, n:expand(ecx))
  end

  return table.concat(out, "")
end

local Trie = {}

---@class desserts.util.trie.Trie
---@field root desserts.util.trie.Node
Trie.O = {}

Trie.I = {
	mt = {
		__index = Trie.O,
		__metatable = true,
	},
}

---@return desserts.util.trie.Trie
function Trie.I.new()
	local self = setmetatable({}, Trie.I.mt) --[[@as desserts.util.trie.Trie]]

	self.root = Node.I.new()

	return self
end

---@param parsed_nodes desserts.util.trie.ParsedNode[]
---@param parsed_close desserts.util.trie.ParsedNode[]
---@return desserts.util.trie.Node
function Trie.O:insert(parsed_nodes, parsed_close)
	local curr = self.root
	for _, parsed_node in ipairs(parsed_nodes) do
		curr = parsed_node:extend_node(curr)
	end
	curr.leaf = parsed_close

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

return M
