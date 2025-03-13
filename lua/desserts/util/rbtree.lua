local M = {}

local RBTree = {
	I = {},
}

---@class desserts.util.RBTree
---@field root desserts.util.RBNode
RBTree.O = {}

RBTree.I.mt = {
	__index = RBTree.O,

	--- ---@param a util.RBNode.O
	--- ---@param b util.RBNode.O
	--- ---@return boolean
	--- __eq = function(a, b)
	--- 	return a.key == b.key
	--- end,
}

local RBNode = {
	I = {},
}

---@enum desserts.util.RBNode.Color
RBNode.Color = {
	Red = 1,
	Black = 2,
}

---@class desserts.util.RBNode
---@field key any
---@field p desserts.util.RBNode
---@field l desserts.util.RBNode
---@field r desserts.util.RBNode
---@field color desserts.util.RBNode.Color
RBNode.O = {}

RBNode.I.mt = {
	__index = RBNode.O,
}

do
	local NIL = {}

	function RBNode.I.Nil()
		return setmetatable({ key = NIL, color = RBNode.Color.Black }, RBNode.I.mt)
	end

	function RBNode.O:is_nil()
		return self.key == NIL
	end
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
	while not x.l:is_nil() do
		x = x.l
	end
	return x
end

---@param key any
---@return desserts.util.RBNode
function RBTree.O:search(key)
	local x = self.root

	while not x:is_nil() and key ~= x.key do
		x = key < x.key and x.l or x.r
	end

	return x:is_nil() and RBNode.I.Nil() or x
	-- return x
end

---@param tree desserts.util.RBTree
---@param x desserts.util.RBNode
function RBTree.I.left_rotate(tree, x)
	local y = x.r
	x.r = y.l

	if not y.l:is_nil() then
		y.l.p = x
	end

	y.p = x.p

	if x.p:is_nil() then
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

	if not y.r:is_nil() then
		y.r.p = x
	end

	y.p = x.p

	if x.p:is_nil() then
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

function RBTree.O:insert(key)
	local z = RBNode.I.new(key, RBNode.Color.Red)

	local y = RBNode.I.Nil()
	local x = self.root

	while not x:is_nil() do
		y = x
		x = z.key < x.key and x.l or x.r
	end

	z.p = y
	if y:is_nil() then
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
	if u.p:is_nil() then
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
		if x == x.p.l then -- if x is a left child
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

---@param key any
function RBTree.O:delete(key)
	local z = self:search(key)

	if z:is_nil() then
		return
	end

	local y = z
	local y_orig_color = y.color
	local x

	if z.l:is_nil() then
		x = z.r
		RBTree.I.transplant(self, z, x)
	elseif z.r:is_nil() then
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

M.new = RBTree.I.new

return M
