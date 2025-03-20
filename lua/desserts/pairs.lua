local M = {}

M.NS = vim.api.nvim_create_namespace("desserts.pairs.ctx")

local Pairs = {
	state = {},
}

local MatchingCtx = {}

---@class MatchingCtx
---@field cursor desserts.pairs.Node
---@field open_extmark_id integer
---@field close_extmark_id? integer
---@field matching? string
---@field captures table<string, string>
MatchingCtx.O = {}

MatchingCtx.I = {
	mt = {
		__index = MatchingCtx.O,
		__metatable = true,
	},
}

---@param opts {}
function MatchingCtx.I.new(opts)
	local self = setmetatable({}, MatchingCtx.I.mt)

	self.cursor = opts.cursor
	self.open_extmark_id = opts.open_extmark_id
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
			Snacks.debug.inspect({ not_matching = key, matching_ctx = self })
			return nil
		end
	end

	local next_node = self.cursor.children[string.byte(key)]
	if next_node then
		return MatchingCtx.I.new({
			cursor = next_node,
			open_extmark_id = self.open_extmark_id,
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
		open_extmark_id = self.open_extmark_id,
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
				Snacks.debug.inspect({ not_matching = key, matching_ctx = self })
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
			open_extmark_id = self.open_extmark_id,
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
---@field bufstate table<integer, {pairs: table<integer, desserts.pairs.Pair>, matchers: table<integer, MatchingCtx>}>
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

	local config = m_config.get({})
	for _, p in ipairs(config.pairs) do
		self.open_trie:insert(p.parsed_open, p.parsed_close)
		self.close_trie:insert(p.parsed_close, p.parsed_open)
	end

	self.bufstate = {}

	return self
end

function State.O:on_backspace(pos)
	--
end

function State.O:on_insert(key, typed, buf, win)
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))
	if not self.bufstate[buf] then
		self.bufstate[buf] = { matchers = {}, pairs = {} }
	end
	local state = assert(self.bufstate[buf])

	local marks = vim.api.nvim_buf_get_extmarks(buf, M.NS, { row - 1, col - 1 }, { row - 1, col - 1 }, {
		details = true,
		overlap = true,
	})

	-- Snacks.debug.inspect({
	-- 	marks = marks or "nil",
	-- 	pairs = self.pairs,
	-- })
	---@type vim.api.keyset.get_extmark_item[]
	local open_marks = vim.iter(marks)
		:filter(function(m)
			---@cast m vim.api.keyset.get_extmark_item
			return m[1] == state.pairs[m[1]].open_extmark_id
		end)
		:totable()

	---@type vim.api.keyset.get_extmark_item[]
	local openclose_marks = vim.iter(marks)
		:filter(function(m)
			---@cast m vim.api.keyset.get_extmark_item
			return m[1] == state.pairs[m[1]].openclose_extmark_id
		end)
		:totable()

	-- Snacks.debug.inspect({ marks = marks or "nil", row = row - 1, col = col })

	local lookahead, surr_close_mark, surr_mark = (function()
		if next(openclose_marks) then
			local surr_mark = vim.iter(openclose_marks):rev():find(
				---@param mark vim.api.keyset.get_extmark_item
				function(mark)
					return mark[2] <= row - 1
						and row - 1 <= mark[4].end_row
						and mark[3] <= col
						and col < mark[4].end_col
				end
			) --[[@as vim.api.keyset.get_extmark_item]]

			if not surr_mark then
				return false, nil
			end

			local surr_close_mark = vim.api.nvim_buf_get_extmark_by_id(
				buf,
				M.NS,
				state.pairs[surr_mark[1]].close_extmark_id,
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

			return close_text == key, surr_close_mark, surr_mark
		else
			return false, nil
		end
	end)()

	local match_from_root, next_extmark, next_matching_ctx, curr_matching_ctx = (function()
		if not next(open_marks) then
			return true, nil, nil, nil
		else
			local curr_extmark = open_marks[#open_marks]
			local curr_matching_ctx = state.matchers[curr_extmark[1]]
			local next_matching_ctx = curr_matching_ctx:advance(key)
			local next_extmark = curr_extmark

			if not next_matching_ctx then
				return true, nil, nil, nil
			else
				if curr_matching_ctx ~= next_matching_ctx then
					next_matching_ctx.open_extmark_id =
						vim.api.nvim_buf_set_extmark(buf, M.NS, curr_extmark[2], curr_extmark[3], {
							end_row = curr_extmark[4].end_row,
							end_col = curr_extmark[4].end_col,
							invalidate = true,
							undo_restore = false,
						})
					next_extmark[1] = next_matching_ctx.open_extmark_id

					state.pairs[next_matching_ctx.open_extmark_id] = require("desserts.pairs.core.pair").Pair.new({
						open_extmark_id = next_matching_ctx.open_extmark_id,
					})
					state.matchers[next_matching_ctx.open_extmark_id] = next_matching_ctx
				end
				return false, next_extmark, next_matching_ctx, curr_matching_ctx
			end
		end
	end)()

	if lookahead then
		surr_close_mark = assert(surr_close_mark)

		-- mark pos are (0-0) indexed, win pos are (1-0) indexed
		vim.api.nvim_win_set_cursor(win, { surr_close_mark[3].end_row + 1, surr_close_mark[3].end_col })

		-- Snacks.debug.inspect({ next_matching_ctx = next_matching_ctx or "nil" })

		if next_matching_ctx then
			next_extmark = assert(next_extmark)
			assert(next_extmark[1] == next_matching_ctx.open_extmark_id)

			vim.api.nvim_buf_set_extmark(buf, M.NS, next_extmark[2], next_extmark[3], {
				id = next_extmark[1],
				end_row = next_extmark[4].end_row,
				end_col = next_extmark[4].end_col + 1,
			})
		end

		return ""
	elseif match_from_root then
		local cur = self.open_trie.root.children[string.byte(key)]

		if cur then
			vim.api.nvim_put({ key }, "c", false, true)
			-- vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { key })
			local open_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col, {
				end_row = row - 1,
				end_col = col + 1,
				undo_restore = false,
				invalidate = true,
			})
			-- vim.api.nvim_win_set_cursor(win, { row, col + 1 })

			local matching_ctx = MatchingCtx.I.new({ cursor = cur, open_extmark_id = open_extmark_id })
			state.matchers[open_extmark_id] = matching_ctx
			state.pairs[open_extmark_id] = require("desserts.pairs.core.pair").Pair.new({
				open_extmark_id = matching_ctx.open_extmark_id,
			})

			local expanded = cur:expand({ captures = {} })
			if expanded then
				local p = state.pairs[matching_ctx.open_extmark_id]

				-- vim.api.nvim_buf_set_text(buf, row - 1, col + 1, row - 1, col + 1, { expanded })
				vim.api.nvim_put({ expanded }, "b", false, false)
				matching_ctx.close_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col + 1, {
					end_row = row - 1,
					end_col = col + 1 + #expanded,
					invalidate = true,
					undo_restore = false,
				})
				p.close_extmark_id = matching_ctx.close_extmark_id
				state.pairs[matching_ctx.close_extmark_id] = p

				local openclose_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col, {
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
	else
		-- curr_matching_ctx = assert(curr_matching_ctx)
		next_extmark = assert(next_extmark)
		next_matching_ctx = assert(next_matching_ctx)
		assert(next_extmark[1] == next_matching_ctx.open_extmark_id)

		-- vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { key })
		vim.api.nvim_put({ key }, "c", false, true)
		-- Snacks.debug.inspect({ extending_curr_extmark = true })
		vim.api.nvim_buf_set_extmark(buf, M.NS, next_extmark[2], next_extmark[3], {
			id = next_extmark[1],
			end_row = next_extmark[4].end_row,
			end_col = next_extmark[4].end_col + 1,
		})
		-- vim.api.nvim_win_set_cursor(win, { row, col + 1 })

		local expanded = next_matching_ctx:expand()
		if expanded then
			-- Snacks.debug.inspect({ next_matching_ctx = next_matching_ctx })
			-- vim.api.nvim_buf_set_text(buf, row - 1, col + 1, row - 1, col + 1, { expanded })
			vim.api.nvim_put({ expanded }, "b", false, false)

			local p = state.pairs[next_matching_ctx.open_extmark_id]
			next_matching_ctx.close_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col + 1, {
				end_row = row - 1,
				end_col = col + 1 + #expanded,
				invalidate = true,
				undo_restore = false,
			})
			p.close_extmark_id = next_matching_ctx.close_extmark_id
			state.pairs[next_matching_ctx.close_extmark_id] = p

			local openclose_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, next_extmark[2], next_extmark[3], {
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
end

-- vim.api.nvim_buf_attach(0, false, {
-- 	on_bytes = function(
-- 		_,
-- 		bufnr,
-- 		changedtick,
-- 		start_row,
-- 		start_col,
-- 		byte_off,
-- 		old_end_row,
-- 		old_end_col,
-- 		old_end_byte,
-- 		new_end_row,
-- 		new_end_col,
-- 		new_end_byte
-- 	)
-- 		if true then
-- 			return
-- 		end
--
-- 		local e = {
-- 			changedtick = changedtick,
-- 			-- old_end_byte = old_end_byte,
-- 			-- new_end_byte = new_end_byte,
-- 			start = { start_row + 1, start_col },
-- 			old_end = { old_end_row, old_end_col },
-- 			new_end = { new_end_row, new_end_col },
-- 			offset = { new_end_row - old_end_row, new_end_col - old_end_col },
-- 			mode = vim.api.nvim_get_mode(),
-- 		}
--
-- 		-- handle single character insert mode buffer modifications in the `on_key` callback
-- 		if e.mode.mode:find("i", 1, true) and e.offset[1] == 0 and math.abs(e.offset[2]) == 1 then
-- 			return
-- 		end
--
-- 		Snacks.debug.inspect(e)
-- 	end,
-- })

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

		if key == vim.keycode("<BS>") then
			return
		-- print("backspace")
		elseif key == vim.keycode("<CR>") then
			return
		-- print("return")
		elseif key == vim.keycode("<Space>") then
			-- print("space")
			return
		elseif key == vim.keycode("<Esc>") then
			return
		else
			return s:on_insert(key, typed, buf, win)
		end
	end, M.NS)

	-- vim.api.nvim_create_autocmd({ "BufAdd" }, {
	-- 	callback = function(e)
	--      --
	--    end,
	-- })
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
