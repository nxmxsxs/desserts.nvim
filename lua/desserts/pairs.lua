local M = {}

M.NS = vim.api.nvim_create_namespace("desserts.pairs.ctx")

local Pairs = {
	state = {},
}

local MatchingCtx = {
	I = {},
	O = {},
}

---@class (private) desserts.pairs.MatchingCtx.Match
---@field node desserts.pairs.Node
---@field offset { [1]: integer, [2]: integer }
---@field matching? string

---@class (private) desserts.pairs.MatchingCtx
---@field root desserts.pairs.Node
---@field extmark_id integer
---@field captures table<string, string>
---@field matches desserts.pairs.MatchingCtx.Match[]
MatchingCtx.O.__index = {}

---@param opts { root: desserts.pairs.Node, extmark_id: integer, captures?: table<string, string> }
function MatchingCtx.I.new(opts)
	local self = setmetatable({}, MatchingCtx.O)

	self.root = opts.root
	self.extmark_id = opts.extmark_id
	self.captures = opts.captures or {}
	self.matches = {}

	return self
end

function MatchingCtx.O.__index:cursor()
	return assert(self.matches[#self.matches]).node
end
--- ---@param extmark_id integer
--- ---@return MatchingCtx
--- function MatchingCtx.O:clone(extmark_id)
--- 	return setmetatable({ cursor = self.cursor, extmark_id = extmark_id }, MatchingCtx.I.mt)
--- end

---@param key string
---@return desserts.pairs.MatchingCtx?
function MatchingCtx.O.__index:advance(key)
	local curr_match = next(self.matches) and self.matches[#self.matches] or { node = self.root, offset = { 0, 0 } }

	local input = curr_match.matching and curr_match.matching .. key or key
	local next_node, captured = curr_match.node:match(input)

	if curr_match.node.leaf then
		if not next_node then
			return nil
		end

		local new_mcx = MatchingCtx.I.new({ root = self.root, extmark_id = -1 })
		vim.list_extend(new_mcx.matches, self.matches or {})
		new_mcx.matches[#new_mcx.matches + 1] = {
			node = next_node,
			offset = { curr_match.offset[2], curr_match.offset[2] + 1 },
			matching = captured and captured.match,
		}
		if captured then
			new_mcx.captures[captured.id] = captured.match
		end

		return new_mcx
	else
		if not next_node then
			self.captures = {}

			return nil
		end

		if captured then
			self.captures[captured.id] = captured.match
		end

		local matching = captured and captured.match

		if curr_match.node == next_node then
			curr_match.offset[2] = curr_match.offset[2] + 1
			curr_match.matching = matching
		else
			table.insert(self.matches, {
				node = next_node,
				offset = { curr_match.offset[2], curr_match.offset[2] + 1 },
				matching = matching,
			})
		end

		return self
	end
end

-- function MatchingCtx.O:expand()
-- 	return self:cursor():expand({ captures = self.captures })
-- end

---@return desserts.pairs.ExpandCtx
function MatchingCtx.O.__index:ecx()
	local node = self.root
	local i = 0
	local out = {}

	---@class (private) desserts.pairs.ExpandCtx
	local ecx = {
		---@param cb fun(node: desserts.pairs.Node): desserts.pairs.Node, string
		add_match = function(cb)
			local next_node, s = cb(node)
			node = next_node

			local next_i = i + #s
			local offset = { i, next_i }
			i = next_i

			self.matches[#self.matches + 1] = { node = next_node, offset = offset, matching = s }
			out[#out + 1] = s
		end,

		---@param k string
		---@return string?
		capture = function(k)
			return self.captures[k]
		end,

		expanded = function()
			return table.concat(out, "")
		end,
	}

	return ecx
end

---@param leaf desserts.pairs.trie.ParsedNode[]
---@return string
function MatchingCtx.O.__index:expand(leaf)
	local ecx = self:ecx()

	for _, i in ipairs(leaf) do
		i:add_match(ecx)
	end

	return ecx.expanded()
end

local State = {
	I = {},
	O = {},
}

---@class desserts.pairs.State
---@field open_trie desserts.pairs.Trie
---@field close_trie desserts.pairs.Trie
---@field leaves_map table<desserts.pairs.Node, desserts.pairs.Node>
---@field bufstate table<integer, desserts.pairs.BufState>
State.O.__index = {}

function State.I.new()
	local m_trie = require("desserts.pairs.core.trie")
	local m_config = require("desserts.pairs.config")

	local self = setmetatable({}, State.O)
	self.open_trie = m_trie.new()
	self.close_trie = m_trie.new()
	self.leaves_map = {}

	local config = m_config.get({})
	for _, p in ipairs(config.pairs) do
		local open_leaf = self.open_trie:insert(p.parsed_open, p.parsed_close)
		local close_leaf = self.close_trie:insert(p.parsed_close, p.parsed_open)
		self.leaves_map[open_leaf] = close_leaf
		self.leaves_map[close_leaf] = open_leaf
	end

	self.bufstate = {}

	return self
end

local BufState = {
	I = {},
	O = {},
}

---@class (private) desserts.pairs.BufState
---@field pairs table<integer, desserts.pairs.Pair>
---@field matchers { open: table<integer, desserts.pairs.MatchingCtx>, close: table<integer, desserts.pairs.MatchingCtx> }
---@field pending desserts.pairs.PendingPairState
BufState.O.__index = {}

local PendingPairState = {
	I = {},
	O = {},
}

---@class (private) desserts.pairs.PendingPairState
---@field open_tree desserts.util.RBTree
---@field close_tree desserts.util.RBTree
---@field buf integer
---@field ns integer
PendingPairState.O.__index = {}

---@param opts {buf: integer, ns: integer}
function PendingPairState.I.new(opts)
	local m_rbtree = require("desserts.util.rbtree")

	local o = setmetatable({}, PendingPairState.O)

	o.buf = opts.buf
	o.ns = opts.ns
	o.open_tree = m_rbtree.new()
	o.close_tree = m_rbtree.new()

	return o
end

---@param opts {buf: integer, ns: integer}
function BufState.I.new(opts)
	local self = setmetatable({}, BufState.O)
	self.matchers = { open = {}, close = {} }
	self.pairs = {}
	self.pending = PendingPairState.I.new(opts)
	return self
end

local PendingPairStateNodeKey = {
	I = {},
	O = {},
}

---@class PendingPairState.NodeKey: desserts.util.RBNodeKey
---@field buf integer
---@field ns integer
---@field extmark_id integer
PendingPairStateNodeKey.O.__index = {}

---@param a PendingPairState.NodeKey
---@param b PendingPairState.NodeKey
---@return -1|0|1
function PendingPairStateNodeKey.I.cmp(a, b)
	assert(a.buf == b.buf)
	assert(a.ns == b.ns)

	if a.extmark_id == b.extmark_id then
		return 0
	end

	local a_mark = vim.api.nvim_buf_get_extmark_by_id(a.buf, a.ns, a.extmark_id, {
		details = true,
	})
	local b_mark = vim.api.nvim_buf_get_extmark_by_id(b.buf, b.ns, b.extmark_id, {
		details = true,
	})

	if a_mark[1] < b_mark[1] then
		return -1
	elseif a_mark[1] > b_mark[1] then
		return 1
	elseif a_mark[2] < b_mark[2] then
		return -1
	elseif a_mark[2] > b_mark[2] then
		return 1
	elseif a_mark[3].end_row < b_mark[3].end_row then
		return -1
	elseif a_mark[3].end_row > b_mark[3].end_row then
		return 1
	elseif a_mark[3].end_col < b_mark[3].end_col then
		return -1
	elseif a_mark[3].end_col > b_mark[3].end_col then
		return 1
	else
		return 0
	end
end

---@param a PendingPairState.NodeKey
---@param b PendingPairState.NodeKey
---@return boolean
function PendingPairStateNodeKey.O.__eq(a, b)
	return PendingPairStateNodeKey.I.cmp(a, b) == 0
end

---@param a PendingPairState.NodeKey
---@param b PendingPairState.NodeKey
---@return boolean
function PendingPairStateNodeKey.O.__lt(a, b)
	return PendingPairStateNodeKey.I.cmp(a, b) == -1
end

---@param a PendingPairState.NodeKey
---@param b PendingPairState.NodeKey
---@return boolean
function PendingPairStateNodeKey.O.__le(a, b)
	local cmp = PendingPairStateNodeKey.I.cmp(a, b)

	return cmp == -1 or cmp == 0
end

---@param extmark_id integer
---@return PendingPairState.NodeKey
function PendingPairState.O.__index:node_key(extmark_id)
	local o = setmetatable({}, PendingPairStateNodeKey.O)
	o.buf = self.buf
	o.ns = self.ns
	o.extmark_id = extmark_id

	return o
end

---@param emid integer
function PendingPairState.O.__index:open_insert(emid)
	self.open_tree:insert(self:node_key(emid))
end

---@param s_key_em vim.api.keyset.get_extmark_item_by_id
---@return fun(node_key: PendingPairState.NodeKey): -1|0|1
function PendingPairStateNodeKey.I.extmark_cmp(s_key_em)
	return function(node_key)
		local node_key_em =
			vim.api.nvim_buf_get_extmark_by_id(node_key.buf, node_key.ns, node_key.extmark_id, { details = true })

		if s_key_em[1] < node_key_em[1] then
			return -1
		elseif s_key_em[1] > node_key_em[1] then
			return 1
		elseif s_key_em[2] < node_key_em[2] then
			return -1
		elseif s_key_em[2] > node_key_em[2] then
			return 1
		elseif s_key_em[3].end_row < node_key_em[3].end_row then
			return -1
		elseif s_key_em[3].end_row > node_key_em[3].end_row then
			return 1
		elseif s_key_em[3].end_col < node_key_em[3].end_col then
			return -1
		elseif s_key_em[3].end_col > node_key_em[3].end_col then
			return 1
		else
			return 0
		end
	end
end

---@param open_extmark_id integer
function PendingPairState.O.__index:open_delete(open_extmark_id)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	local s_key_em = vim.api.nvim_buf_get_extmark_by_id(self.buf, self.ns, open_extmark_id, { details = true })
	self.open_tree:delete_with(
		---@param node_key PendingPairState.NodeKey
		function(node_key)
			if open_extmark_id == node_key.extmark_id then
				return 0
			end

			return PendingPairStateNodeKey.I.extmark_cmp(s_key_em)(node_key)
		end
	)
end

---@param row integer
---@param col integer
---@return fun(key: PendingPairState.NodeKey): -1|0|1
function PendingPairStateNodeKey.I.row_col_cmp(row, col)
	return function(key)
		local key_em = vim.api.nvim_buf_get_extmark_by_id(key.buf, key.ns, key.extmark_id, {})

		if key_em[1] > row then
			return 1
		elseif key_em[1] < row then
			return -1
		elseif key_em[2] > col then
			return 1
		elseif key_em[2] < col then
			return -1
		else
			return 0
		end
	end
end

-- ---@param cmp fun(node: PendingPairState.NodeKey): -1|0|1
---@param row integer
---@param col integer
---@return PendingPairState.NodeKey[]
function PendingPairState.O.__index:open_node_keys_le(row, col)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	return self.open_tree:node_keys_le(PendingPairStateNodeKey.I.row_col_cmp(row, col))
end

---@param emid integer
function PendingPairState.O.__index:close_insert(emid)
	self.close_tree:insert(self:node_key(emid))
end

-- ---@param cmp fun(node: PendingPairState.NodeKey): -1|0|1
---@param row integer
---@param col integer
---@return PendingPairState.NodeKey[]
function PendingPairState.O.__index:close_node_keys_gt(row, col)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	return self.close_tree:node_keys_gt(PendingPairStateNodeKey.I.row_col_cmp(row, col))
end

---@param close_extmark_id integer
function PendingPairState.O.__index:close_delete(close_extmark_id)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	local s_key_em = vim.api.nvim_buf_get_extmark_by_id(self.buf, self.ns, close_extmark_id, { details = true })

	self.close_tree:delete_with(
		---@param node_key PendingPairState.NodeKey
		function(node_key)
			if close_extmark_id == node_key.extmark_id then
				return 0
			end

			return PendingPairStateNodeKey.I.extmark_cmp(s_key_em)(node_key)
		end
	)
end

function State.O.__index:on_backspace(buf, win, icx)
	local row, col = icx.row, icx.col
	local state = assert(self.bufstate[buf])

	local cm = icx.marks.close[#icx.marks.close]
	local om = icx.marks.open[#icx.marks.open]
	-- Snacks.debug.inspect({
	-- 	om = om or "nil",
	-- 	cm = cm or "nil",
	-- 	row = row - 1,
	-- 	col = col,
	-- })
	if cm then
		if cm[2] == cm[4].end_row and cm[4].end_col - cm[3] == 1 then
			local pair = state.pairs[cm[1]]

			assert(cm[1] == pair.close_extmark_id)

			state.pending:close_delete(pair.close_extmark_id)
			vim.api.nvim_buf_del_extmark(buf, M.NS, pair.close_extmark_id)
			state.pairs[assert(pair.close_extmark_id)] = nil
			state.matchers.close[pair.close_extmark_id] = nil
			pair.close_extmark_id = nil

			if pair.openclose_extmark_id then
				vim.api.nvim_buf_del_extmark(buf, M.NS, pair.openclose_extmark_id)
				state.pairs[pair.openclose_extmark_id] = nil
				pair.openclose_extmark_id = nil
			end

			if pair.open_extmark_id then
				Snacks.debug.inspect({ new_broken_open = true, pair = pair })

				state.pending:open_insert(pair.open_extmark_id)
			end
		end
	elseif om then
		if om[2] == om[4].end_row and om[4].end_col - om[3] == 1 then
			local pair = state.pairs[om[1]]

			assert(om[1] == pair.open_extmark_id)

			state.pending:open_delete(pair.open_extmark_id)
			vim.api.nvim_buf_del_extmark(buf, M.NS, pair.open_extmark_id)
			state.pairs[pair.open_extmark_id] = nil
			state.matchers.open[pair.open_extmark_id] = nil
			pair.open_extmark_id = nil

			if pair.openclose_extmark_id then
				vim.api.nvim_buf_del_extmark(buf, M.NS, pair.openclose_extmark_id)
				state.pairs[pair.openclose_extmark_id] = nil
				pair.openclose_extmark_id = nil
			end

			if pair.close_extmark_id then
				Snacks.debug.inspect({ new_broken_close = true, pair = pair })

				state.pending:close_insert(pair.close_extmark_id)
			end
		end
	end

	return
end

function State.O.__index:on_insert(key, typed, buf, win, icx)
	local row, col = icx.row, icx.col
	local state = assert(self.bufstate[buf])

	-- Snacks.debug.inspect({ key = key, typed = typed })

	local curr_open_matching_ctx, curr_open_extmark, curr_open_advance_cursor = (function()
		local curr_open_extmark = icx.marks.open[#icx.marks.open]
		if curr_open_extmark then
			local curr_open_matching_ctx = state.matchers.open[curr_open_extmark[1]]
			local next_open_matching_ctx = curr_open_matching_ctx:advance(typed)

			if next_open_matching_ctx then
				if curr_open_matching_ctx ~= next_open_matching_ctx then
					next_open_matching_ctx.extmark_id =
						vim.api.nvim_buf_set_extmark(buf, M.NS, curr_open_extmark[2], curr_open_extmark[3], {
							end_row = curr_open_extmark[4].end_row,
							end_col = curr_open_extmark[4].end_col,
							invalidate = true,
							undo_restore = false,
						})
					curr_open_extmark[1] = next_open_matching_ctx.extmark_id
					state.pairs[next_open_matching_ctx.extmark_id] = require("desserts.pairs.core.pair").Pair.new({
						open_extmark_id = next_open_matching_ctx.extmark_id,
					})
					state.matchers.open[next_open_matching_ctx.extmark_id] = next_open_matching_ctx
				end

				if curr_open_matching_ctx:cursor().leaf then
					curr_open_matching_ctx = next_open_matching_ctx
				end

				return curr_open_matching_ctx,
					curr_open_extmark,
					vim.api.nvim_buf_get_text(buf, row - 1, col, row - 1, col + 1, {})[1] == typed
			end
		end

		-- Snacks.debug.inspect({
		-- 	-- surr_close_mark = surr_close_mark or "nil",
		-- 	-- surr_openclose_mark = surr_openclose_mark or "nil",
		-- 	close_text = close_text or "nil",
		-- 	key = key,
		-- 	curr_open_lookahead = curr_open_lookahead,
		-- 	marks_openclose = marks.openclose,
		-- 	-- curr_open_matching_ctx = curr_open_matching_ctx or "nil",
		-- 	-- curr_close_matching_ctx = curr_close_matching_ctx or "nil",
		-- 	row = row - 1,
		-- 	col = col,
		-- })

		local curr_open_lookahead = (function()
			if not next(icx.marks.lookahead_close) then
				return false
			end

			-- if next chaaracter is a lookahead key -> open,close char is the same, then don't start a new match
			local curr_lookahead_close_mark = icx.marks.lookahead_close[#icx.marks.lookahead_close]
			return curr_lookahead_close_mark[1] == row - 1 and curr_lookahead_close_mark[2] == col
		end)()
		if curr_open_lookahead then
			return nil, nil, false
		end

		local new_open_matching_ctx = MatchingCtx.I.new({
			root = self.open_trie.root,
			extmark_id = -1,
		})

		local next_open_matching_ctx = new_open_matching_ctx:advance(typed)
		if next_open_matching_ctx then
			new_open_matching_ctx.extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col, {
				end_row = row - 1,
				end_col = col,
				undo_restore = false,
				invalidate = true,
			})
			-- Snacks.debug.inspect({ new_opening = true })
			state.matchers.open[new_open_matching_ctx.extmark_id] = new_open_matching_ctx
			state.pairs[new_open_matching_ctx.extmark_id] = require("desserts.pairs.core.pair").Pair.new({
				open_extmark_id = new_open_matching_ctx.extmark_id,
			})

			return new_open_matching_ctx,
				{
					new_open_matching_ctx.extmark_id,
					row - 1,
					col,
					{ end_row = row - 1, end_col = col, right_gravity = true, ns_id = M.NS },
				},
				false
		end
	end)()

	local curr_close_matching_ctx, next_close_matching_ctx, curr_close_extmark = (function()
		local curr_close_extmark = icx.marks.close[#icx.marks.close]
		if curr_close_extmark then
			local curr_close_matching_ctx = state.matchers.close[curr_close_extmark[1]]
			local next_close_matching_ctx = curr_close_matching_ctx:advance(typed)

			if next_close_matching_ctx then
				return curr_close_matching_ctx, next_close_matching_ctx, curr_close_extmark
			end
		else
			local new_close_matching_ctx = MatchingCtx.I.new({ root = self.close_trie.root, extmark_id = -1 })
			local next_close_matching_ctx = new_close_matching_ctx:advance(typed)

			if next_close_matching_ctx then
				new_close_matching_ctx.extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col, {
					end_row = row - 1,
					end_col = col,
					undo_restore = false,
					invalidate = true,
				})
				state.matchers.close[new_close_matching_ctx.extmark_id] = new_close_matching_ctx
				state.pairs[new_close_matching_ctx.extmark_id] = require("desserts.pairs.core.pair").Pair.new({
					close_extmark_id = new_close_matching_ctx.extmark_id,
				})

				return new_close_matching_ctx,
					next_close_matching_ctx,
					{
						new_close_matching_ctx.extmark_id,
						row - 1,
						col,
						{ end_row = row - 1, end_col = col, right_gravity = true, ns_id = M.NS },
					}
			end
		end
	end)()

	-- Snacks.debug.inspect({
	-- 	surr_close_mark = surr_close_mark or "nil",
	-- 	curr_open_matching_ctx = curr_open_matching_ctx or "nil",
	-- 	curr_close_matching_ctx = curr_close_matching_ctx or "nil",
	-- 	row = row - 1,
	-- 	col = col,
	-- })

	if curr_open_matching_ctx then
		curr_open_extmark = assert(curr_open_extmark)

		local curr_cursor = curr_open_matching_ctx:cursor()
		local leaf = curr_cursor.leaf

		if leaf then
			for _, cnk in ipairs(state.pending:close_node_keys_gt(row - 1, col - 1)) do
				local cmcx = state.matchers.close[cnk.extmark_id]
				-- TODO: closing cursor might not be a leaf???
				if self.leaves_map[curr_cursor] == cmcx:cursor() then
					vim.api.nvim_put({ typed }, "c", false, true)
					vim.api.nvim_buf_set_extmark(buf, M.NS, curr_open_extmark[2], curr_open_extmark[3], {
						id = curr_open_extmark[1],
						end_row = curr_open_extmark[4].end_row,
						end_col = curr_open_extmark[4].end_col + 1,
					})
					curr_open_extmark[4].end_col = curr_open_extmark[4].end_col + 1

					state.pending:close_delete(cnk.extmark_id)

					-- NOTE: update open pair, etc...
					local pair = state.pairs[cnk.extmark_id]

					pair.open_extmark_id = curr_open_matching_ctx.extmark_id
					state.pairs[curr_open_matching_ctx.extmark_id] = pair

					local re_close_extmark =
						vim.api.nvim_buf_get_extmark_by_id(buf, M.NS, cnk.extmark_id, { details = true })

					pair.openclose_extmark_id =
						vim.api.nvim_buf_set_extmark(buf, M.NS, curr_open_extmark[2], curr_open_extmark[3], {
							end_row = re_close_extmark[3].end_row,
							end_col = re_close_extmark[3].end_col,
							invalidate = true,
							undo_restore = false,
						})
					state.pairs[pair.openclose_extmark_id] = pair

					Snacks.debug.inspect({
						close_u_complete_me = true,
						pair = pair,
						curr_open_extmark = curr_open_extmark,
						re_close_extmark = re_close_extmark,
					})

					return ""
				end
			end
		end

		-- Snacks.debug.inspect({
		-- 	curr_open_matching_ctx = curr_open_matching_ctx or "nil",
		-- 	-- next_open_matching_ctx = next_open_matching_ctx or "nil",
		-- 	-- curr_open_extmark = curr_open_extmark or "nil",
		-- })

		if curr_open_advance_cursor then
			vim.api.nvim_win_set_cursor(win, { row, col + 1 })
		else
			vim.api.nvim_put({ typed }, "c", false, true)
		end

		vim.api.nvim_buf_set_extmark(buf, M.NS, curr_open_extmark[2], curr_open_extmark[3], {
			id = curr_open_extmark[1],
			end_row = curr_open_extmark[4].end_row,
			end_col = curr_open_extmark[4].end_col + 1,
		})
		curr_open_extmark[4].end_col = curr_open_extmark[4].end_col + 1

		if leaf then
			local close_matching_ctx = MatchingCtx.I.new({
				root = self.close_trie.root,
				extmark_id = -1,
				captures = curr_open_matching_ctx.captures,
			})
			local expanded = close_matching_ctx:expand(leaf)
			-- vim.api.nvim_feedkeys("\003u", "m", true)
			-- vim.api.nvim_feedkeys("<C-g>u", "n", false)
			vim.api.nvim_put({ expanded }, "b", false, false)
			close_matching_ctx.extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col + 1, {
				end_row = row - 1,
				end_col = col + 1 + #expanded,
				invalidate = true,
				undo_restore = false,
			})

			local p = state.pairs[curr_open_matching_ctx.extmark_id]

			state.matchers.close[close_matching_ctx.extmark_id] = close_matching_ctx
			p.close_extmark_id = close_matching_ctx.extmark_id
			state.pairs[close_matching_ctx.extmark_id] = p

			local openclose_extmark_id =
				vim.api.nvim_buf_set_extmark(buf, M.NS, curr_open_extmark[2], curr_open_extmark[3], {
					end_row = row - 1,
					end_col = col + 1 + #expanded,
					invalidate = true,
					undo_restore = false,
				})
			p.openclose_extmark_id = openclose_extmark_id
			state.pairs[openclose_extmark_id] = p
		end

		return ""
	end

	if curr_close_matching_ctx then
		curr_close_extmark = assert(curr_close_extmark)

		if curr_close_matching_ctx:cursor().leaf then
			for _, onk in ipairs(state.pending:open_node_keys_le(row - 1, col - 1)) do
				local omcx = state.matchers.open[onk.extmark_id]
				if self.leaves_map[curr_close_matching_ctx:cursor()] == omcx:cursor() then
					vim.api.nvim_put({ typed }, "c", false, true)
					vim.api.nvim_buf_set_extmark(buf, M.NS, curr_close_extmark[2], curr_close_extmark[3], {
						id = curr_close_extmark[1],
						end_row = curr_close_extmark[4].end_row,
						end_col = curr_close_extmark[4].end_col + 1,
					})
					curr_close_extmark[4].end_col = curr_close_extmark[4].end_col + 1

					state.pending:open_delete(onk.extmark_id)

					-- NOTE: update close pair, etc...
					local pair = state.pairs[onk.extmark_id]

					pair.close_extmark_id = curr_close_matching_ctx.extmark_id
					state.pairs[curr_close_matching_ctx.extmark_id] = pair

					local renew_open_extmark =
						vim.api.nvim_buf_get_extmark_by_id(buf, M.NS, onk.extmark_id, { details = true })
					pair.openclose_extmark_id =
						vim.api.nvim_buf_set_extmark(buf, M.NS, renew_open_extmark[1], renew_open_extmark[2], {
							end_row = curr_close_extmark[4].end_row,
							end_col = curr_close_extmark[4].end_col,
							invalidate = true,
							undo_restore = false,
						})
					state.pairs[pair.openclose_extmark_id] = pair

					Snacks.debug.inspect({
						open_u_complete_me = true,
						pair = pair,
						renew_open_extmark = renew_open_extmark,
						curr_close_extmark = curr_close_extmark,
					})

					return ""
				end
			end
		end
	end

	if next(icx.marks.lookahead_close) then
		local curr_lookahead_close_mark = icx.marks.lookahead_close[#icx.marks.lookahead_close]
		-- Snacks.debug.inspect({
		-- 	marks_lookahead_close = marks.lookahead_close,
		-- })

		-- mark pos are (0-0) indexed, win pos are (1-0) indexed
		vim.api.nvim_win_set_cursor(
			win,
			{ curr_lookahead_close_mark[3].end_row + 1, curr_lookahead_close_mark[3].end_col }
		)

		return ""
	end

	-- if open_cur and close_cur then
	-- 	local ecx = { captures = {} }
	-- 	local bidirectional = open_cur:expand(ecx) == close_cur:expand(ecx)
	--
	-- 	-- NOTE:
	-- 	-- It would be cool to be able to `re-pair`:
	-- 	--    `<foo1`, `</foo1>`
	-- 	-- into:
	-- 	--    `<bar2>`, `</bar2>`
	-- 	return
	-- end
end

---@class (private) desserts.pairs.SetupOpts

---@param opts desserts.pairs.SetupOpts
function M.setup(opts)
	require("desserts.pairs.config").setup(opts)

	local s = State.I.new()

	vim.keymap.set("n", "<M-o>", function()
		-- local r = {}
		-- for _, v in pairs(open_state) do
		-- 	local m = vim.api.nvim_buf_get_extmark_by_id(0, M.NS, v.open_extmark_id, { details = true })
		-- 	table.insert(r, vim.api.nvim_buf_get_text(0, m[1], m[2], m[3].end_row, m[3].end_col, {}))
		-- end
		-- Snacks.debug.inspect(r)

		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)
		local row, col = unpack(vim.api.nvim_win_get_cursor(win))
		local marks = vim.api.nvim_buf_get_extmarks(buf, M.NS, { row - 1, col }, { row - 1, col }, {
			details = true,
			-- limit = 1,
			overlap = true,
		})
		Snacks.debug.inspect({
			marks = marks or "nil",
			row = row - 1,
			col = col,
			win = win,
			buf = buf,
		})
	end)

	vim.on_key(function(key, typed)
		if typed == "" then
			return
		end

		local mode = vim.api.nvim_get_mode().mode
		if mode ~= "i" then
			return
		end

		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)

		if not s.bufstate[buf] then
			s.bufstate[buf] = BufState.I.new({ buf = buf, ns = M.NS })

			vim.api.nvim_buf_attach(buf, false, {
				on_lines = function(
					_,
					bufnr,
					changedtick,
					first,
					last_old,
					last_new,
					byte_count,
					deleted_codepoints,
					deleted_codeunits
				)
				end,
				on_bytes = function(
					_,
					bufnr,
					changedtick,
					start_row,
					start_col,
					byte_off,
					old_end_row,
					old_end_col,
					old_end_byte,
					new_end_row,
					new_end_col,
					new_end_byte
				)
					-- if true then
					-- 	return
					-- end

					local e = {
						changedtick = changedtick,
						-- old_end_byte = old_end_byte,
						-- new_end_byte = new_end_byte,
						start = { start_row + 1, start_col },
						old_end = { old_end_row, old_end_col },
						new_end = { new_end_row, new_end_col },
						offset = { new_end_row - old_end_row, new_end_col - old_end_col },
						mode = vim.api.nvim_get_mode(),
					}

					-- handle single character insert mode buffer modifications in the `on_key` callback
					if e.mode.mode:find("i", 1, true) and e.offset[1] == 0 and math.abs(e.offset[2]) == 1 then
						return
					end

					-- Snacks.debug.inspect(e)

					-- local range = { start_row, start_col, start_row + e.offset[1], start_col + e.offset[2] }
					--
					-- local marks = vim.api.nvim_buf_get_extmarks(
					-- 	bufnr,
					-- 	M.NS,
					-- 	{ range[1], range[2] },
					-- 	{ range[3], range[4] },
					-- 	{
					-- 		details = true,
					-- 		overlap = true,
					-- 	}
					-- )
					--
					-- Snacks.debug.inspect(range, marks)
				end,
			})
		end

		local row, col = unpack(vim.api.nvim_win_get_cursor(win))
		local state = s.bufstate[buf]

		local marks = vim.iter(vim.api.nvim_buf_get_extmarks(buf, M.NS, { row - 1, col - 1 }, { row - 1, col - 1 }, {
			details = true,
			overlap = true,
		})):fold(
			{
				---@type vim.api.keyset.get_extmark_item[]
				open = {},
				---@type vim.api.keyset.get_extmark_item[]
				openclose = {},
				---@type vim.api.keyset.get_extmark_item[]
				close = {},
				---@type vim.api.keyset.get_extmark_item_by_id[]
				lookahead_close = {},
			},
			---@param m vim.api.keyset.get_extmark_item
			function(acc, m)
				-- `nvim_buf_get_extmarks` also includes marks on the upper bound (exclusive) which we dont want
				local p = state.pairs[m[1]]

				if m[1] == p.open_extmark_id then
					if (col - 1) < m[4].end_col then
						table.insert(acc.open, m)
					end
				elseif m[1] == p.close_extmark_id then
					if (col - 1) < m[4].end_col then
						table.insert(acc.close, m)
					end
				elseif m[1] == p.openclose_extmark_id then
					-- table.insert(o, {
					-- 	m_end_col = m[4].end_col,
					-- 	prev_col = col - 1,
					-- })
					if col < m[4].end_col then
						table.insert(acc.openclose, m)

						if not p.close_extmark_id then
							return nil
						end

						local surr_close_mark =
							vim.api.nvim_buf_get_extmark_by_id(buf, M.NS, p.close_extmark_id, { details = true })

						if
							surr_close_mark[1] == surr_close_mark[3].end_row
							and surr_close_mark[3].end_col - surr_close_mark[2] == 1
							and vim.api.nvim_buf_get_text(
									buf,
									surr_close_mark[1],
									surr_close_mark[2],
									surr_close_mark[3].end_row,
									surr_close_mark[3].end_col,
									{}
								)[1]
								== typed
						then
							-- Snacks.debug.inspect({
							-- 	m_end_col = m[4].end_col,
							-- 	surr_end_col = surr_close_mark[3].end_col,
							-- 	col = col,
							-- })
							table.insert(acc.lookahead_close, surr_close_mark)
						end
					end
				else
					error("skill_issue!()")
				end

				return acc
			end
		)

		local icx = {
			row = row,
			col = col,
			marks = marks,
		}

		if typed == vim.keycode("<BS>") then
			return s:on_backspace(buf, win, icx)
		elseif typed == vim.keycode("<Del>") then
			return
		elseif typed == vim.keycode("<CR>") then
			return
		elseif typed == vim.keycode("<Space>") then
			return
		elseif typed == vim.keycode("<Esc>") then
			return
		else
			return s:on_insert(key, typed, buf, win, icx)
		end
	end, M.NS)
end

---@class (private) desserts.pairs.CreatePairOpts
---@field defs? table<string, vim.lpeg.Pattern|fun(...: any): any>
---@field on_enter? fun(...: any): any
---@field on_backspace? fun(...: any): any
---@field on_space? fun(...: any): any
---@field on_open? fun(...: any): any
---@field on_close? fun(...: any): any

---Create a new pair
---@param open_str string
---@param close_str string
---@param opts desserts.pairs.CreatePairOpts
---@return desserts.pairs.PairDef
function M.create_pair(open_str, close_str, opts)
	local m_pair = require("desserts.pairs.core.pair")

	local parsed_open = m_pair.parse(open_str, { defs = opts.defs })
	local parsed_close = m_pair.parse(close_str, { defs = opts.defs })

	return m_pair.PairDef.new(parsed_open, parsed_close)
end

return M
