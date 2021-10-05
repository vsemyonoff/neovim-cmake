local dap = require('dap')
local utils = require('cmake.utils')
local config = require('cmake.config')
local Path = require('plenary.path')
local cmake = {}

function cmake.setup(values)
  setmetatable(config, { __index = vim.tbl_extend('force', config.defaults, values) })
end

function cmake.configure(...)
  local cmakelists = Path:new('CMakeLists.txt')
  if not cmakelists:is_file() then
    vim.notify('Unable to find ' .. tostring(cmakelists), vim.log.levels.ERROR, { title = 'CMake' })
    return
  end

  local parameters = utils.get_parameters()
  local build_dir = utils.get_build_dir(parameters)
  local command = table.concat({ 'cmake', config.configure_arguments, table.concat({ ... }, ' '), '-D', 'CMAKE_BUILD_TYPE=' .. parameters['buildType'], '-B', tostring(build_dir) }, ' ')
  build_dir:mkdir({ parents = true })
  if not utils.make_query_files(build_dir) then
    return
  end
  utils.asyncrun_callback("require('cmake.utils').copy_compile_commands()")
  vim.fn['asyncrun#run']('', config.asyncrun_options, command)
end

function cmake.build(...)
  local parameters = utils.get_parameters()
  local target_name = parameters['currentTarget']
  if not target_name or #target_name == 0 then
    vim.notify('You need to select target first', vim.log.levels.ERROR, { title = 'CMake' })
    return
  end

  local command = table.concat({ 'cmake', '--build', tostring(utils.get_build_dir(parameters)), '--target', target_name, config.build_arguments, ... }, ' ')
  utils.autoclose_quickfix(config.asyncrun_options)
  utils.asyncrun_callback("require('cmake.utils').copy_compile_commands()")
  vim.fn['asyncrun#run']('', config.asyncrun_options, command)
end

function cmake.build_all(...)
  local command = table.concat({ 'cmake', '--build', tostring(utils.get_build_dir()), ... }, ' ')
  utils.autoclose_quickfix(config.asyncrun_options)
  utils.asyncrun_callback("require('cmake.utils').copy_compile_commands()")
  vim.fn['asyncrun#run']('', config.asyncrun_options, command)
end

function cmake.run(...)
  local target_dir, target, arguments = utils.get_current_target(utils.get_parameters())
  if not target then
    return
  end

  local command = table.concat({ tostring(target), arguments, ... }, ' ')
  utils.autoclose_quickfix(config.target_asyncrun_options)
  vim.fn['asyncrun#run']('', vim.tbl_extend('force', { cwd = tostring(target_dir) }, config.target_asyncrun_options), command)
end

function cmake.debug(...)
  local parameters = utils.get_parameters()
  if not utils.check_debugging_build_type(parameters) then
    return
  end

  local target_dir, target, arguments = utils.get_current_target(parameters)
  if not target then
    return
  end

  -- Split on spaces unless "in quotes"
  local splitted_args
  if arguments then
    splitted_args = vim.fn.split(arguments, [[\s\%(\%([^'"]*\(['"]\)[^'"]*\1\)*[^'"]*$\)\@=]])
  else
    splitted_args = {}
  end

  -- Remove quotes
  for i, arg in ipairs(splitted_args) do
    splitted_args[i] = arg:gsub('"', ''):gsub("'", '')
  end

  vim.list_extend(splitted_args, { ... })

  vim.api.nvim_command('cclose')
  local dap_config = {
    name = parameters['currentTarget'],
    program = tostring(target),
    args = splitted_args,
    cwd = tostring(target_dir),
  }
  dap.run(vim.tbl_extend('force', dap_config, config.dap_configuration))
  if config.dap_open_command then
    config.dap_open_command()
  end
end

function cmake.clean(...)
  local command = table.concat({ 'cmake', table.concat({ ... }, ' '), '--build', tostring(utils.get_build_dir()), '--target', 'clean' }, ' ')
  utils.autoclose_quickfix(config.asyncrun_options)
  utils.asyncrun_callback("require('cmake.utils').copy_compile_commands()")
  vim.fn['asyncrun#run']('', config.asyncrun_options, command)
end

function cmake.build_and_run(...)
  local parameters = utils.get_parameters()
  if not utils.get_current_executable_info(parameters, utils.get_build_dir(parameters)) then
    return
  end

  utils.asyncrun_callback("require('cmake').run()")
  cmake.build(...)
end

function cmake.build_and_debug(...)
  local parameters = utils.get_parameters()
  if not utils.get_current_executable_info(parameters, utils.get_build_dir(parameters)) then
    return
  end

  if not utils.check_debugging_build_type(parameters) then
    return
  end

  utils.asyncrun_callback("require('cmake').debug()")
  cmake.build(...)
end

function cmake.set_target_arguments()
  local parameters = utils.get_parameters()
  local current_target = utils.get_current_executable_info(parameters, utils.get_build_dir(parameters))
  if not current_target then
    return
  end

  local current_target_name = current_target['name']
  parameters['arguments'][current_target_name] = vim.fn.input(current_target_name .. ' arguments: ', parameters['arguments'][current_target_name] or '', 'file')
  utils.set_parameters(parameters)
end

function cmake.clear_cache()
  local cache_file = utils.get_build_dir() / 'CMakeCache.txt'
  if not cache_file:is_file() then
    vim.notify('Cache file ' .. tostring(cache_file) .. ' does not exists', vim.log.levels.ERROR, { title = 'CMake' })
    return
  end

  cache_file:rm()
end

function cmake.open_build_dir()
  local program = vim.fn.has('win32') == 1 and 'start ' or 'xdg-open '
  vim.fn.system(program .. tostring(utils.get_build_dir()))
end

return cmake
