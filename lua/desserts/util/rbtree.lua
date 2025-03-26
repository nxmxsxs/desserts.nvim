local M = {}

local RBTree = {
	I = {},
}

---@class desserts.util.RBTree
---@field root desserts.util.RBNode
RBTree.O = {}

RBTree.I.mt = {
	__index = RBTree.O,
}

---@class desserts.util.RBNodeKey
local RBNodeKey = {}

--- ---@param other desserts.util.RBNodeKey
--- ---@return integer
--- function RBNodeKey:compare(other)
--- 	error("`RBNodeKey:compare` not implemented")
--- end

local RBNode = {
	I = {},
}

---@enum desserts.util.RBNode.Color
RBNode.Color = {
	Red = 1,
	Black = 2,
}

---@class desserts.util.RBNode
---@field key desserts.util.RBNodeKey?
---@field p desserts.util.RBNode
---@field l desserts.util.RBNode
---@field r desserts.util.RBNode
---@field color desserts.util.RBNode.Color
RBNode.O = {}

RBNode.I.mt = {
	__index = RBNode.O,
}

function RBNode.I.Nil()
	return setmetatable({ key = nil, color = RBNode.Color.Black }, RBNode.I.mt)
end

---@param key any
---@param color desserts.util.RBNode.Color
---@return desserts.util.RBNode
function RBNode.I.new(key, color)
	local self = setmetatable({}, RBNode.I.mt)

	self.key = key
	self.p = RBNode.I.Nil()
	self.l = RBNode.I.Nil()
	self.r = RBNode.I.Nil()
	self.color = color

	return self
end

function RBTree.I.new()
	local self = setmetatable({}, RBTree.I.mt)

	self.root = RBNode.I.Nil()

	return self
end

---@param x desserts.util.RBNode
function RBTree.I.minimum(x)
	while x.l.key do
		x = x.l
	end
	return x
end

---@param key desserts.util.RBNodeKey
---@return desserts.util.RBNode
function RBTree.O:search(key)
	local x = self.root

	while x.key and key ~= x.key do
		x = key < x.key and x.l or x.r
	end

	return not x.key and RBNode.I.Nil() or x
	-- return x
end

---@param cmp fun(key: desserts.util.RBNodeKey): -1|0|1
-- ---@param key any
---@return desserts.util.RBNode
function RBTree.O:search_with(cmp)
	local x = self.root

	while x.key do
		local r = cmp(x.key)

		if r == 0 then
			break
		end

		x = r == -1 and x.l or x.r
	end

	return not x.key and RBNode.I.Nil() or x
	-- return x
end

---@param tree desserts.util.RBTree
---@param x desserts.util.RBNode
function RBTree.I.left_rotate(tree, x)
	local y = x.r
	x.r = y.l

	if y.l.key then
		y.l.p = x
	end

	y.p = x.p

	if not x.p.key then
		tree.root = y
	elseif x == x.p.l then
		x.p.l = y
	else
		x.p.r = y
	end

	y.l = x
	x.p = y
end

---@param tree desserts.util.RBTree
---@param x desserts.util.RBNode
function RBTree.I.right_rotate(tree, x)
	local y = x.l
	x.l = y.r

	if y.r.key then
		y.r.p = x
	end

	y.p = x.p

	if x.p.key then
		tree.root = y
	elseif x == x.p.r then
		x.p.r = y
	else
		x.p.l = y
	end

	y.r = x
	x.p = y
end

---@param tree desserts.util.RBTree
---@param z desserts.util.RBNode
function RBTree.I.insert_fixup(tree, z)
	while z.p.color == RBNode.Color.Red do
		if z.p == z.p.p.l then
			local y = z.p.p.r

			if y.color == RBNode.Color.Red then
				z.p.color = RBNode.Color.Black
				y.color = RBNode.Color.Black
				z.p.p.color = RBNode.Color.Red
				z = z.p.p
			else
				if z == z.p.r then
					z = z.p
					RBTree.I.left_rotate(tree, z)
				end

				z.p.color = RBNode.Color.Black
				z.p.p.color = RBNode.Color.Red
				RBTree.I.right_rotate(tree, z.p.p)
			end
		else
			local y = z.p.p.l

			if y.color == RBNode.Color.Red then
				z.p.color = RBNode.Color.Black
				y.color = RBNode.Color.Black
				z.p.p.color = RBNode.Color.Red
				z = z.p.p
			else
				if z == z.p.l then
					z = z.p
					RBTree.I.right_rotate(tree, z)
				end

				z.p.color = RBNode.Color.Black
				z.p.p.color = RBNode.Color.Red
				RBTree.I.left_rotate(tree, z.p.p)
			end
		end
	end

	tree.root.color = RBNode.Color.Black
end

---@param key desserts.util.RBNodeKey
function RBTree.O:insert(key)
	local z = RBNode.I.new(key, RBNode.Color.Red)

	local y = RBNode.I.Nil()
	local x = self.root

	while x.key do
		y = x
		x = z.key < x.key and x.l or x.r
	end

	z.p = y
	if not y.key then
		self.root = z
	elseif z.key < y.key then
		y.l = z
	else
		y.r = z
	end

	RBTree.I.insert_fixup(self, z)
end

---@param tree desserts.util.RBTree
---@param u desserts.util.RBNode
---@param v desserts.util.RBNode
function RBTree.I.transplant(tree, u, v)
	if not u.p.key then
		tree.root = v
	elseif u == u.p.l then
		u.p.l = v
	else
		u.p.r = v
	end

	v.p = u.p
end

---@param tree desserts.util.RBTree
---@param x desserts.util.RBNode
function RBTree.I.delete_fixup(tree, x)
	while x ~= tree.root and x.color == RBNode.Color.Black do
		if x == x.p.l then
			local w = x.p.r
			if w.color == RBNode.Color.Red then
				w.color = RBNode.Color.Black
				x.p.color = RBNode.Color.Red
				RBTree.I.left_rotate(tree, x.p)
				w = x.p.r
			end

			if w.l.color == RBNode.Color.Black and w.r.color == RBNode.Color.Black then
				w.color = RBNode.Color.Red
				x = x.p
			else
				if w.r.color == RBNode.Color.Black then
					w.l.color = RBNode.Color.Black
					w.color = RBNode.Color.Red
					RBTree.I.right_rotate(tree, w)
					w = x.p.r
				end
				w.color = x.p.color
				x.p.color = RBNode.Color.Black
				w.r.color = RBNode.Color.Black
				RBTree.I.left_rotate(tree, x.p)
				x = tree.root
			end
		else
			local w = x.p.l
			if w.color == RBNode.Color.Red then
				w.color = RBNode.Color.Black
				x.p.color = RBNode.Color.Red
				RBTree.I.right_rotate(tree, x.p)
				w = x.p.l
			end

			if w.r.color == RBNode.Color.Black and w.l.color == RBNode.Color.Black then
				w.color = RBNode.Color.Red
				x = x.p
			else
				if w.l.color == RBNode.Color.Black then
					w.r.color = RBNode.Color.Black
					w.color = RBNode.Color.Red
					RBTree.I.left_rotate(tree, w)
					w = x.p.l
				end
				w.color = x.p.color
				x.p.color = RBNode.Color.Black
				w.l.color = RBNode.Color.Black
				RBTree.I.right_rotate(tree, x.p)
				x = tree.root
			end
		end
	end

	x.color = RBNode.Color.Black
end

---@param key desserts.util.RBNodeKey
function RBTree.O:delete(key)
	local z = self:search(key)

	if not z.key then
		return
	end

	local y = z
	local y_orig_color = y.color
	local x

	if not z.l.key then
		x = z.r
		RBTree.I.transplant(self, z, x)
	elseif not z.r.key then
		x = z.l
		RBTree.I.transplant(self, z, x)
	else
		y = RBTree.I.minimum(z.r)
		y_orig_color = y.color
		x = y.r

		if y.p == z then
			x.p = y
		else
			RBTree.I.transplant(self, y, x)
			y.r = z.r
			y.r.p = y
		end

		RBTree.I.transplant(self, z, y)
		y.l = z.l
		y.l.p = y
		y.color = z.color
	end

	if y_orig_color == RBNode.Color.Black then
		RBTree.I.delete_fixup(self, x)
	end
end

---@param cmp fun(key: desserts.util.RBNodeKey): -1|0|1
-- ---@param key desserts.util.RBNodeKey
function RBTree.O:delete_with(cmp)
	local z = self:search_with(cmp)

	if not z.key then
		return
	end

	local y = z
	local y_orig_color = y.color
	local x

	if not z.l.key then
		x = z.r
		RBTree.I.transplant(self, z, x)
	elseif not z.r.key then
		x = z.l
		RBTree.I.transplant(self, z, x)
	else
		y = RBTree.I.minimum(z.r)
		y_orig_color = y.color
		x = y.r

		if y.p == z then
			x.p = y
		else
			RBTree.I.transplant(self, y, x)
			y.r = z.r
			y.r.p = y
		end

		RBTree.I.transplant(self, z, y)
		y.l = z.l
		y.l.p = y
		y.color = z.color
	end

	if y_orig_color == RBNode.Color.Black then
		RBTree.I.delete_fixup(self, x)
	end
end

---@param cmp fun(node: desserts.util.RBNodeKey): -1|0|1
---@return desserts.util.RBNodeKey[]
function RBTree.O:node_keys_le(cmp)
	---@param node desserts.util.RBNode
	---@param acc desserts.util.RBNode[]
	---@return desserts.util.RBNode[]
	local function collect(node, acc)
		if not node.key then
			return acc
		end

		local r = cmp(node.key)
		-- If node.key > key, only explore left subtree
		if r == 1 then
			return collect(node.l, acc)
		end

		-- If node.key ≤ key, process left, then node, then right
		acc = collect(node.l, acc)
		table.insert(acc, node.key)
		return collect(node.r, acc)
	end

	return collect(self.root, {})
end

---@param cmp fun(node: desserts.util.RBNodeKey): -1|0|1
---@return desserts.util.RBNodeKey[]
function RBTree.O:node_keys_gt(cmp)
	---@param node desserts.util.RBNode
	---@param acc desserts.util.RBNode[]
	---@return desserts.util.RBNode[]
	local function collect(node, acc)
		if not node.key then
			return acc
		end

		local r = cmp(node.key)
		-- If node.key <= key, only explore right subtree
		if r == -1 or r == 0 then
			return collect(node.r, acc)
		end

		-- If node.key > key, process left, then node, then right
		acc = collect(node.l, acc)
		table.insert(acc, node.key)
		return collect(node.r, acc)
	end

	return collect(self.root, {})
end

M.new = RBTree.I.new

return M
