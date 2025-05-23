---@module 'dap'

local conf = require('neotest-busted._conf')

---Collects the name of a node and all its ancestors in order from outer-most
---down to the given node.
---@param node  neotest.Tree  Current Neotest node
---@param names string[]      Collected node names so far
---@return string[]  Final result of collecting names
local function collect_node_names(node, names)
  local data = node:data()
  if data.type ~= 'test' and data.type ~= 'namespace' then
    return names
  end
  table.insert(names, 1, data.name)
  local parent = node:parent()
  if not parent then
    return names
  end
  return collect_node_names(parent, names)
end

---@param tree neotest.Tree
---@return string[]
local function get_roots(tree)
  local data = tree:data()

  if data.type ~= 'dir' then
    return { data.path }
  end

  local paths = {}
  for _, child in ipairs(tree:children()) do
    local child_paths = get_roots(child)
    vim.list_extend(paths, child_paths)
  end

  return paths
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
local function build_spec(args)
  local tree = args.tree
  if not tree then
    return nil
  end
  local data = tree:data()
  local type = data.type

  local command = vim
    .iter({
      vim.g.bustedprg or 'busted',
    })
    :flatten()
    :totable()

  local additional_args = {
    '--output',
    require('neotest-busted._output-handler').source,
  }
  -- The user has selected a specific node inside the file
  if type == 'test' or type == 'namespace' then
    -- Names joined by space, from outer-most to inner-most
    local filter = table.concat(collect_node_names(tree, {}), ' ')
    -- Escape special characters
    filter = filter:gsub('%%', '%%%%'):gsub('%s', '%%s'):gsub('-', '%%-')

    vim.list_extend(additional_args, { '--filter', filter })
  end

  local _, _, bustedrc = conf.get()
  if bustedrc then
    vim.list_extend(additional_args, { '--config-file', bustedrc })
  end

  vim.list_extend(additional_args, { '--' })
  local roots = get_roots(tree)
  if #roots == 0 then
    return nil
  end
  vim.list_extend(additional_args, roots)

  local strategy_config
  if args.strategy == 'dap' then
    ---@type dap.Configuration
    strategy_config = {
      name = 'Neotest Busted Test',
      type = 'local-lua',
      request = 'launch',
      cwd = '${workspaceFolder}',
      program = {
        command = 'busted',
      },
      args = vim.list_extend({
        '-e',
        '"require(\'lldebugger\').start()"',
        '--no-coverage',
      }, additional_args),
    }
  end

  vim.list_extend(command, additional_args)
  return {
    command = command,
    strategy = strategy_config,
  }
end

return build_spec
