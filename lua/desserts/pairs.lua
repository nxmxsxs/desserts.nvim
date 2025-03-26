local M = {}

M.NS = vim.api.nvim_create_namespace("desserts.pairs.ctx")

local Pairs = {
	state = {},
}

local MatchingCtx = {}

---@class MatchingCtx
---@field cursor desserts.pairs.Node
---@field extmark_id integer
---@field matching? string
---@field captures table<string, string>
MatchingCtx.O = {}

MatchingCtx.I = {
	mt = {
		__index = MatchingCtx.O,
		__metatable = true,
	},
}

---@param opts { cursor: desserts.pairs.Node, extmark_id: integer, matching?: string, captures?: table<string,string> }
function MatchingCtx.I.new(opts)
	local self = setmetatable({}, MatchingCtx.I.mt)

	self.cursor = opts.cursor
	self.extmark_id = opts.extmark_id
	self.matching = opts.matching
	self.captures = opts.captures or {}

	return self
end

--- ---@param extmark_id integer
--- ---@return MatchingCtx
--- function MatchingCtx.O:clone(extmark_id)
--- 	return setmetatable({ cursor = self.cursor, extmark_id = extmark_id }, MatchingCtx.I.mt)
--- end

---@param key string
---@return MatchingCtx|nil
function MatchingCtx.O:peek(key)
	if self.cursor.pat then
		local input = self.matching and self.matching .. key or key
		local captured_id = self.cursor.pat:match(input)
		if captured_id then
			self.matching = input
			self.captures[captured_id] = self.matching
			-- Snacks.debug.inspect({ captures = self.captures })

			return self
		elseif not self.matching then
			-- Snacks.debug.inspect({ not_matching = key, matching_ctx = self })
			return nil
		end
	end

	local next_node = self.cursor.children[string.byte(key)]
	if next_node then
		return MatchingCtx.I.new({
			cursor = next_node,
			extmark_id = self.extmark_id,
			captures = self.captures,
		})
	end

	next_node = self.cursor.children[self.cursor]
	if not next_node then
		-- self.matching = nil
		-- self.captures = {}

		return nil
	end
	assert(next_node.pat)

	local captured_id = next_node.pat:match(key)
	-- Snacks.debug.inspect({
	-- 	captured_id = captured_id or "nil",
	-- 	from = key,
	-- 	-- ctx = string.format("%p", self),
	-- 	-- pat = self.cursor.pat or "nil",
	-- })
	if not captured_id then
		return nil
	end

	-- Snacks.debug.inspect({ captures = { [captured_id] = key } })
	local next_matching_ctx = MatchingCtx.I.new({
		cursor = next_node,
		extmark_id = self.extmark_id,
		captures = vim.tbl_deep_extend("error", self.captures, { [captured_id] = key }),
		matching = key,
	})

	return next_matching_ctx
end

---@param key string
---@return MatchingCtx|nil
function MatchingCtx.O:advance(key)
	local next_node, data = (function()
		if self.cursor.pat then
			local input = self.matching and self.matching .. key or key
			local captured_id = self.cursor.pat:match(input)
			if captured_id then
				self.matching = input
				self.captures[captured_id] = self.matching
				-- Snacks.debug.inspect({ captures = self.captures })

				return self.cursor, nil
			elseif not self.matching then
				-- Snacks.debug.inspect({ not_matching = key, matching_ctx = self })
				return nil, nil
			end
		end

		local next_node = self.cursor.children[string.byte(key)]
		if next_node then
			return next_node, nil
		end

		next_node = self.cursor.children[self.cursor]
		if not next_node then
			return nil, nil
		end
		assert(next_node.pat)

		local captured_id = next_node.pat:match(key)
		if not captured_id then
			return nil, nil
		else
			return next_node, { matching = key, captures = { [captured_id] = key } }
		end
	end)()

	if self.cursor.leaf then
		if not next_node then
			return nil
		end

		return MatchingCtx.I.new({
			cursor = next_node,
			extmark_id = self.extmark_id,
			captures = vim.tbl_deep_extend("error", self.captures, data and data.captures or {}),
			matching = data and data.matching,
		})

		-- return nil
	else
		if not next_node then
			self.matching = nil
			self.captures = {}

			return nil
		end

		self.cursor = next_node
		if data then
			self.matching = data.matching
			local k, v = next(data.captures)
			self.captures[k] = v
		end

		return self
	end
end

function MatchingCtx.O:expand()
	return self.cursor:expand({ captures = self.captures })
end

local State = {}

---@class desserts.pairs.State
---@field open_trie desserts.pairs.Trie
---@field close_trie desserts.pairs.Trie
---@field leaves_map table<desserts.pairs.Node, desserts.pairs.Node>
---@field bufstate table<integer, desserts.pairs.BufState>
State.O = {}

State.I = {
	mt = {
		__index = State.O,
		__metatable = true,
	},
}

function State.I.new()
	local m_trie = require("desserts.pairs.core.trie")
	local m_config = require("desserts.pairs.config")

	local self = setmetatable({}, State.I.mt)
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

local BufState = {}

---@class (private) desserts.pairs.BufState
---@field pairs table<integer, desserts.pairs.Pair>
---@field matchers { open: table<integer, MatchingCtx>, close: table<integer, MatchingCtx> }
---@field pending desserts.pairs.PendingPairState
BufState.O = {}

BufState.I = {
	mt = {
		__index = BufState.O,
	},
}

local PendingPairState = {}

---@class (private) desserts.pairs.PendingPairState
---@field open_tree desserts.util.RBTree
---@field close_tree desserts.util.RBTree
---@field buf integer
---@field ns integer
PendingPairState.O = {}

PendingPairState.I = {
	mt = {
		__index = PendingPairState.O,
	},
}

---@param opts {buf: integer, ns: integer}
function PendingPairState.I.new(opts)
	local m_rbtree = require("desserts.util.rbtree")

	local o = setmetatable({}, PendingPairState.I.mt)

	o.buf = opts.buf
	o.ns = opts.ns
	o.open_tree = m_rbtree.new()
	o.close_tree = m_rbtree.new()

	return o
end

---@param opts {buf: integer, ns: integer}
function BufState.I.new(opts)
	local self = setmetatable({}, BufState.I.mt)
	self.matchers = { open = {}, close = {} }
	self.pairs = {}
	self.pending = PendingPairState.I.new(opts)
	return self
end

PendingPairState.NodeKey = {}

---@class PendingPairState.NodeKey: desserts.util.RBNodeKey
---@field buf integer
---@field ns integer
---@field extmark_id integer
PendingPairState.NodeKey.O = {}

PendingPairState.NodeKey.I = {
	mt = {
		__index = PendingPairState.NodeKey.O,
	},
}

---NOTE: Code no good, Code Bad, Very Bad
---@param a PendingPairState.NodeKey
---@param b PendingPairState.NodeKey
---@return -1|0|1
function PendingPairState.NodeKey.I.cmp(a, b)
	assert(a.buf == b.buf)
	assert(a.ns == b.ns)

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
function PendingPairState.NodeKey.I.mt.__eq(a, b)
	return PendingPairState.NodeKey.I.cmp(a, b) == 0
end

---@param a PendingPairState.NodeKey
---@param b PendingPairState.NodeKey
---@return boolean
function PendingPairState.NodeKey.I.mt.__lt(a, b)
	return PendingPairState.NodeKey.I.cmp(a, b) == -1
end

---@param a PendingPairState.NodeKey
---@param b PendingPairState.NodeKey
---@return boolean
function PendingPairState.NodeKey.I.mt.__le(a, b)
	local cmp = PendingPairState.NodeKey.I.cmp(a, b)

	return cmp == -1 or cmp == 0
end

---@param extmark_id integer
---@return PendingPairState.NodeKey
function PendingPairState.O:node_key(extmark_id)
	local o = setmetatable({}, PendingPairState.NodeKey.I.mt)
	o.buf = self.buf
	o.ns = self.ns
	o.extmark_id = extmark_id

	return o
end

---@param emid integer
function PendingPairState.O:open_insert(emid)
	self.open_tree:insert(self:node_key(emid))
end

---@param s_key_em vim.api.keyset.get_extmark_item_by_id
---@return fun(node_key: PendingPairState.NodeKey): -1|0|1
function PendingPairState.NodeKey.I.extmark_cmp(s_key_em)
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

---@param s_key PendingPairState.NodeKey
function PendingPairState.O:open_delete_by_key(s_key)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	local s_key_em = vim.api.nvim_buf_get_extmark_by_id(s_key.buf, s_key.ns, s_key.extmark_id, { details = true })
	self.open_tree:delete_with(PendingPairState.NodeKey.I.extmark_cmp(s_key_em))
end

---@param row integer
---@param col integer
---@return fun(key: PendingPairState.NodeKey): -1|0|1
function PendingPairState.NodeKey.I.row_col_cmp(row, col)
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
function PendingPairState.O:open_node_keys_le(row, col)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	return self.open_tree:node_keys_le(PendingPairState.NodeKey.I.row_col_cmp(row, col))
end

---@param emid integer
function PendingPairState.O:close_insert(emid)
	self.close_tree:insert(self:node_key(emid))
end

-- ---@param cmp fun(node: PendingPairState.NodeKey): -1|0|1
---@param row integer
---@param col integer
---@return PendingPairState.NodeKey[]
function PendingPairState.O:close_node_keys_gt(row, col)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	return self.close_tree:node_keys_gt(PendingPairState.NodeKey.I.row_col_cmp(row, col))
end

---@param s_key PendingPairState.NodeKey
function PendingPairState.O:close_delete_by_key(s_key)
	---@type table<integer, vim.api.keyset.get_extmark_item_by_id>
	local cache = {}

	local s_key_em = vim.api.nvim_buf_get_extmark_by_id(s_key.buf, s_key.ns, s_key.extmark_id, { details = true })
	self.close_tree:delete_with(PendingPairState.NodeKey.I.extmark_cmp(s_key_em))
end

function State.O:on_backspace(buf, win)
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))
	local state = assert(self.bufstate[buf])

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
		},
		---@param m vim.api.keyset.get_extmark_item
		function(acc, m)
			local p = state.pairs[m[1]]

			if m[1] == p.open_extmark_id then
				table.insert(acc.open, m)
			elseif m[1] == p.close_extmark_id then
				table.insert(acc.close, m)
			elseif m[1] == p.openclose_extmark_id then
				table.insert(acc.openclose, m)
			else
				error("skill_issue!()")
			end

			return acc
		end
	)

	local cm = marks.close[#marks.close]
	local om = marks.open[#marks.open]
	-- Snacks.debug.inspect({ om = om or "nil" })
	if cm then
		if cm[4].end_col - cm[3] == 1 then
			local open_pair = state.pairs[cm[1]]
			Snacks.debug.inspect({ new_broken_open = true })
			state.pending:open_insert(open_pair.open_extmark_id)
		end
	elseif om then
		if om[4].end_col - om[3] == 1 then
			local pair = state.pairs[om[1]]
			if pair.close_extmark_id then
				Snacks.debug.inspect({ new_broken_close = true, pair = pair })

				state.pending:close_insert(pair.close_extmark_id)

				state.pairs[pair.open_extmark_id] = nil
				pair.open_extmark_id = -1
			end
		end
	end

	return
end

function State.O:on_insert(key, typed, buf, win)
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))
	local state = assert(self.bufstate[buf])

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
		},
		---@param m vim.api.keyset.get_extmark_item
		function(acc, m)
			local p = state.pairs[m[1]]

			if m[1] == p.open_extmark_id then
				table.insert(acc.open, m)
			elseif m[1] == p.close_extmark_id then
				table.insert(acc.close, m)
			elseif m[1] == p.openclose_extmark_id then
				table.insert(acc.openclose, m)
			else
				error("skill_issue!()")
			end

			return acc
		end
	)

	-- Snacks.debug.inspect({ marks = marks or "nil", row = row - 1, col = col })

	local lookahead, surr_close_mark, surr_openclose_mark = (function()
		if next(marks.openclose) then
			local surr_openclose_mark = vim.iter(marks.openclose):rev():find(
				---@param m vim.api.keyset.get_extmark_item
				function(m)
					return m[2] <= row - 1 and row - 1 <= m[4].end_row and m[3] <= col and col < m[4].end_col
				end
			) --[[@as vim.api.keyset.get_extmark_item?]]

			if not surr_openclose_mark then
				return false, nil
			end

			local surr_close_mark = vim.api.nvim_buf_get_extmark_by_id(
				buf,
				M.NS,
				state.pairs[surr_openclose_mark[1]].close_extmark_id,
				{ details = true }
			)
			local close_text = surr_close_mark[1] == surr_close_mark[3].end_row
				and surr_close_mark[3].end_col - surr_close_mark[2] == 1
				and vim.api.nvim_buf_get_text(
					buf,
					surr_close_mark[1],
					surr_close_mark[2],
					surr_close_mark[3].end_row,
					surr_close_mark[3].end_col,
					{}
				)[1]
			-- Snacks.debug.inspect({ close_text = close_text })

			return close_text == key, surr_close_mark, surr_openclose_mark
		else
			return false, nil
		end
	end)()

	local curr_open_matching_ctx, next_open_matching_ctx, curr_open_extmark = (function()
		local curr_open_extmark = marks.open[#marks.open]
		if curr_open_extmark then
			local curr_open_matching_ctx = state.matchers.open[curr_open_extmark[1]]
			local next_open_matching_ctx = curr_open_matching_ctx:advance(key)

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

				return curr_open_matching_ctx, next_open_matching_ctx, curr_open_extmark
			end
		end

		local new_open_matching_ctx = MatchingCtx.I.new({
			cursor = self.open_trie.root,
			extmark_id = -1,
		})
		local next_open_matching_ctx = new_open_matching_ctx:advance(key)
		if next_open_matching_ctx then
			-- Snacks.debug.inspect({
			-- 	new_open_matching_ctx = new_open_matching_ctx,
			-- 	next_open_matching_ctx = next_open_matching_ctx,
			-- })
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
				next_open_matching_ctx,
				{
					new_open_matching_ctx.extmark_id,
					row - 1,
					col,
					{ end_row = row - 1, end_col = col, right_gravity = true, ns_id = M.NS },
				}
		end
	end)()

	if next_open_matching_ctx and curr_open_matching_ctx.cursor.leaf then
		curr_open_matching_ctx = next_open_matching_ctx
	end

	if curr_open_matching_ctx then
		-- Snacks.debug.inspect({ lookahead = lookahead, surr_close_mark = surr_close_mark })

		-- Snacks.debug.inspect({
		-- 	curr_open_matching_ctx = curr_open_matching_ctx or "nil",
		-- 	-- next_open_matching_ctx = next_open_matching_ctx or "nil",
		-- 	-- curr_open_extmark = curr_open_extmark or "nil",
		-- })

		if curr_open_matching_ctx.cursor.leaf then
			for _, cnk in ipairs(state.pending:close_node_keys_gt(row - 1, col - 1)) do
				local cmcx = state.matchers.close[cnk.extmark_id]
        -- TODO: closing cursor might not be a leaf???
				if self.leaves_map[curr_open_matching_ctx.cursor] == cmcx.cursor then
					vim.api.nvim_put({ key }, "c", false, true)
					vim.api.nvim_buf_set_extmark(buf, M.NS, curr_open_extmark[2], curr_open_extmark[3], {
						id = curr_open_extmark[1],
						end_row = curr_open_extmark[4].end_row,
						end_col = curr_open_extmark[4].end_col + 1,
					})

					state.pending:close_delete_by_key(cnk)

					-- NOTE: update open pair, etc...
					local pair = state.pairs[cnk.extmark_id]
					Snacks.debug.inspect({ close_u_complete_me = true, pair = pair })

					pair.open_extmark_id = curr_open_matching_ctx.extmark_id
					state.pairs[curr_open_matching_ctx.extmark_id] = pair

					return ""
				end
			end
		end

		-- elseif close_cur then
		-- 	local open_node_keys = state.pending:open_node_keys_le(row - 1, col - 1)
		-- 	-- Snacks.debug.inspect(node_keys)
		-- 	for _, onk in ipairs(open_node_keys) do
		-- 		local mcx = state.matchers.open[onk.extmark_id]
		-- 		local expanded = mcx:expand()
		-- 		if expanded == key then
		-- 			vim.api.nvim_put({ key }, "c", false, true)
		--
		-- 			state.pending:open_delete_by_key(onk)
		-- 			Snacks.debug.inspect({ open_u_complete_me = true })
		--
		-- 			-- NOTE: update close pair, etc...
		--
		-- 			return ""
		-- 		end
		-- 	end
		--
		-- 	return
		-- end

		if lookahead then
			surr_close_mark = assert(surr_close_mark)

			-- mark pos are (0-0) indexed, win pos are (1-0) indexed
			vim.api.nvim_win_set_cursor(win, { surr_close_mark[3].end_row + 1, surr_close_mark[3].end_col })
		else
			vim.api.nvim_put({ key }, "c", false, true)
		end

		vim.api.nvim_buf_set_extmark(buf, M.NS, curr_open_extmark[2], curr_open_extmark[3], {
			id = curr_open_extmark[1],
			end_row = curr_open_extmark[4].end_row,
			end_col = curr_open_extmark[4].end_col + 1,
		})

		local expanded = curr_open_matching_ctx:expand()
		if expanded then
			local p = state.pairs[curr_open_matching_ctx.extmark_id]

			vim.api.nvim_put({ expanded }, "b", false, false)

			local close_matching_ctx = MatchingCtx.I.new({
				cursor = assert(self.leaves_map[curr_open_matching_ctx.cursor]),
				extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col + 1, {
					end_row = row - 1,
					end_col = col + 1 + #expanded,
					invalidate = true,
					undo_restore = false,
				}),
			})

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

		local row, col = unpack(vim.api.nvim_win_get_cursor(0))
		local marks = vim.api.nvim_buf_get_extmarks(0, M.NS, { row - 1, col }, { row - 1, col }, {
			details = true,
			-- limit = 1,
			overlap = true,
		})
		Snacks.debug.inspect({ marks = marks or "nil", row = row - 1, col = col })
	end)

	vim.on_key(function(key, typed)
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

		if key == vim.keycode("<BS>") then
			return s:on_backspace(buf, win)
		elseif key == vim.keycode("<Del>") then
			return
		elseif key == vim.keycode("<CR>") then
			return
		elseif key == vim.keycode("<Space>") then
			return
		elseif key == vim.keycode("<Esc>") then
			return
		else
			return s:on_insert(key, typed, buf, win)
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
