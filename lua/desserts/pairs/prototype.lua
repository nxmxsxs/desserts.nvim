local M = {}

M.NS = vim.api.nvim_create_namespace("desserts.pairs.ctx")

local Pairs = require("desserts.pairs")
local State = Pairs.state()

local MatchingCtx = {}

---@class MatchingCtx
---@field cursor desserts.util.trie.Node
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

---@param c string
---@return boolean
function MatchingCtx.O:advance(c)
	if self.cursor then
		if self.cursor.pat then
			local input = self.matching and self.matching .. c or c
			local id = self.cursor.pat:match(input)
			if id then
				self.matching = input
				self.captures[id] = self.matching
			else
				self.matching = nil
				self.cursor = self.cursor.children[string.byte(c)]
			end
		else
			self.cursor = self.cursor.children[string.byte(c)]
		end
	end

	return not not self.cursor
end

---@param extmark_id integer
---@return MatchingCtx
function MatchingCtx.O:clone(extmark_id)
	return setmetatable({ cursor = self.cursor, extmark_id = extmark_id }, MatchingCtx.I.mt)
end

---@param key string
---@return MatchingCtx|nil
function MatchingCtx.O:peek(key)
	if self.cursor.pat then
		local input = self.matching and self.matching .. key or key
		local captured_id = self.cursor.pat:match(input)
		if captured_id then
			self.matching = input
			self.captures[captured_id] = self.matching

			return self
		elseif not self.matching then
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

	local next_dyn_node = self.cursor.children[self.cursor]

	if not next_dyn_node then
		return nil
	end

	assert(next_dyn_node.pat)

	local captured_id = next_dyn_node.pat:match(key)

	-- Snacks.debug.inspect({
	-- 	captured_id = captured_id or "nil",
	-- 	from = key,
	-- 	-- ctx = string.format("%p", self),
	-- 	-- pat = self.cursor.pat or "nil",
	-- })
	if captured_id then
		local next_matching_ctx = MatchingCtx.I.new({
			cursor = next_dyn_node,
			open_extmark_id = self.open_extmark_id,
			captures = vim.tbl_deep_extend("error", self.captures, { [captured_id] = key }),
			matching = key,
		})

		return next_matching_ctx
	end

	return nil
end

---@type table<integer, MatchingCtx>
local open_state = {}

---@type table<integer, MatchingCtx>
local pending_pairs = {}
---@type table<integer, integer>
local expanded_pairs = {}

print(vim.api.nvim_get_current_buf(), M.NS)

vim.keymap.set("n", "<M-o>", function()
	-- local r = {}
	-- for _, v in pairs(s) do
	-- 	local m = vim.api.nvim_buf_get_extmark_by_id(0, M.NS, v.extmark_id, { details = true })
	-- 	table.insert(
	-- 		r,
	-- 		vim.api.nvim_buf_get_text(
	-- 			0,
	-- 			m[1],
	-- 			m[2],
	-- 			m[3] and m[3].end_row or m[1],
	-- 			m[3] and m[3].end_col or m[2] + 1,
	-- 			{}
	-- 		)
	-- 	)
	-- end
	--
	-- local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	-- local marks = vim.api.nvim_buf_get_extmarks(0, M.NS, { row - 1, col }, { row - 1, col }, {
	-- 	details = true,
	-- 	-- limit = 1,
	-- 	overlap = true,
	-- })
	-- Snacks.debug.inspect({ marks = marks or "nil", row = row - 1, col = col })

	Snacks.debug.inspect({ state = Pairs.state().open_trie })
end, { buffer = true })

vim.on_key(function(key, typed)
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= "i" then
		return
	end

	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))

	local marks = vim.api.nvim_buf_get_extmarks(buf, M.NS, { row - 1, col - 1 }, { row - 1, col - 1 }, {
		details = true,
		-- limit = 1,
		overlap = true,
	})

	if key == vim.keycode("<BS>") then
		local curr_extmark_id = marks[#marks][1]
		local curr_matching_ctx = open_state[curr_extmark_id]
		return
		-- print("backspace")
	elseif key == vim.keycode("<CR>") then
		-- print("return")
	elseif key == vim.keycode("<Space>") then
		-- print("space")
	end

	local match_from_root, curr_extmark_id, curr_matching_ctx, curr_extmark, next_matching_ctx = (function()
		if #marks == 0 then
			return true, nil, nil, nil, nil
		else
			local curr_extmark_id = marks[#marks][1]
			local curr_matching_ctx = open_state[curr_extmark_id]
			local curr_extmark =
				vim.api.nvim_buf_get_extmark_by_id(buf, M.NS, curr_matching_ctx.open_extmark_id, { details = true })
			local next_matching_ctx = curr_matching_ctx:peek(key)

			-- Snacks.debug.inspect({
			-- 	next_matching_ctx = next_matching_ctx or "nil",
			-- 	curr_matching_ctx = curr_matching_ctx,
			-- })
			if next_matching_ctx or curr_matching_ctx.cursor.leaf then
				return false, curr_extmark_id, curr_matching_ctx, curr_extmark, next_matching_ctx
			else
				-- if not curr_matching_ctx.cursor.leaf then
				vim.api.nvim_buf_del_extmark(buf, M.NS, curr_extmark_id)
				open_state[curr_extmark_id] = nil
				-- end

				return true, nil, nil, nil, nil
			end
		end
	end)()

	if match_from_root then
		--- TODO: handle patterns in root node
		local cur = State.open_trie.root.children[string.byte(key)]
		-- single char pairs
		if cur then
			-- Snacks.debug.inspect({ cur = cur, marks = marks })
			vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { key })
			local open_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col, {
				undo_restore = false,
				invalidate = true,
			})
			vim.api.nvim_win_set_cursor(win, { row, col + 1 })
			-- Snacks.debug.inspect({ set_extmark_at = { row - 1, col } })

			local matching_ctx = MatchingCtx.I.new({ cursor = cur, open_extmark_id = open_extmark_id })
			open_state[open_extmark_id] = matching_ctx

			local expanded = cur:expand({ captures = {} })
			if expanded then
				vim.api.nvim_buf_set_text(buf, row - 1, col + 1, row - 1, col + 1, { expanded })
				matching_ctx.close_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, row - 1, col + 1, {
					end_row = row - 1,
					end_col = col + 1 + #expanded,
					invalidate = true,
					undo_restore = false,
				})
			end

			return ""
		end
	else
		curr_extmark_id = assert(curr_extmark_id)
		curr_matching_ctx = assert(curr_matching_ctx)
		curr_extmark = assert(curr_extmark)

		-- TODO: handle lookahead (or atleast I think that's what it called???)
		if
			curr_matching_ctx.cursor:expand({ captures = curr_matching_ctx.captures }) == key
			and curr_matching_ctx.close_extmark_id
		then
			local close_extmark = vim.api.nvim_buf_get_extmark_by_id(buf, M.NS, curr_matching_ctx.close_extmark_id, {
				details = true,
			})

			vim.api.nvim_win_set_cursor(
				win,
				{ close_extmark[1] + 1, close_extmark[3] and close_extmark[3].end_col or close_extmark[2] + 1 }
			)
		else
			vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { key })
			vim.api.nvim_win_set_cursor(win, { row, col + 1 })
		end
		-- local lookahead = not (close_cur and close_cur.leaf)
		-- if lookahead then
		-- end
		-- Snacks.debug.inspect({ close_cur = close_cur or "nil", key = key })
		if next_matching_ctx then
			if curr_matching_ctx.cursor.leaf then
				-- continue/extend from current matching ctx
				local new_extmark_id = vim.api.nvim_buf_set_extmark(buf, M.NS, curr_extmark[1], curr_extmark[2], {
					end_row = row - 1,
					end_col = col + 1,
					undo_restore = false,
					invalidate = true,
				})

				-- Snacks.debug.inspect(vim.api.nvim_buf_get_text(buf, curr_extmark[1], curr_extmark[2], row - 1, col, {}))
				next_matching_ctx.open_extmark_id = new_extmark_id
				open_state[new_extmark_id] = next_matching_ctx

				local expanded = next_matching_ctx.cursor:expand({ captures = next_matching_ctx.captures })
				if expanded and not next_matching_ctx.matching then
					vim.api.nvim_buf_set_text(buf, row - 1, col + 1, row - 1, col + 1, { expanded })
				end
			else
				if curr_matching_ctx ~= next_matching_ctx then
					curr_matching_ctx.cursor = curr_matching_ctx.cursor.children[string.byte(key)]
					-- assert(curr_matching_ctx.cursor)
				end

				vim.api.nvim_buf_set_extmark(buf, M.NS, curr_extmark[1], curr_extmark[2], {
					id = curr_matching_ctx.open_extmark_id,
					end_row = row - 1,
					end_col = col + 1,
				})

				local expanded = curr_matching_ctx.cursor:expand({ captures = curr_matching_ctx.captures })
				if expanded then
					vim.api.nvim_buf_set_text(buf, row - 1, col + 1, row - 1, col + 1, { expanded })
				end
			end
		end

		return ""
	end
end, M.NS)

vim.api.nvim_buf_attach(0, false, {
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
		if true then
			return
		end

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

		Snacks.debug.inspect(e)
	end,
})

return M
