local M = {}

local Pos = {
	I = {},
}

---@class desserts.util.Pos
---@field row integer
---@field col integer
Pos.O = {}

--- ---@param l desserts.Pos
--- ---@param r desserts.Pos
--- ---@return integer
--- local function cmp_pos(l, r)
--- 	if l.row < r.row then
--- 		return -1
--- 	elseif l.row > r.row then
--- 		return 1
--- 	elseif l.col < r.col then
--- 		return -1
--- 	elseif l.col > r.col then
--- 		return 1
--- 	else
--- 		return 0
--- 	end
--- end

Pos.I.mt = {
	__index = Pos.O,

	---@param l desserts.util.Pos
	---@param r desserts.util.Pos
	__eq = function(l, r)
		return l.row == r.row and l.col == r.col
	end,
	---@param l desserts.util.Pos
	---@param r desserts.util.Pos
	__lt = function(l, r)
		return l.row <= r.row and l.col < r.col
	end,
	---@param l desserts.util.Pos
	---@param r desserts.util.Pos
	__le = function(l, r)
		return l.row <= r.row and l.col <= r.col
	end,
}

---@param opts { row: integer, col: integer }
function Pos.I.new(opts)
	local self = setmetatable({}, Pos.I.mt)

	self.row = opts.row
	self.col = opts.col

	return self
end

M.new = Pos.I.new

return M
