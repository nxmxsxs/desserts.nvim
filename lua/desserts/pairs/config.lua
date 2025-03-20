local M = {}


---@class desserts.pairs.Config
local defaults = {
  ---@type desserts.pairs.PairDef[]
  pairs = {}
}

---@class desserts.pairs.Config
local config

function M.get(opts)
  if not config then
    M.setup()
  end

  return config
end

function M.setup(opts)
  opts = opts or {}
  config = config or {}
  config.pairs = config.pairs or {}
  config.pairs = vim.list_extend(config.pairs, opts.pairs or {})
end

return M
