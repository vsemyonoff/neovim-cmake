local os = require('ffi').os:lower()
local Path = require('plenary.path')
local config = require('cmake.config')
local utils = {}

function utils.get_parameters()
  local parameters_file = Path:new(config.parameters_file)
  if not parameters_file:is_file() then
    return { currentTarget = '', buildType = 'Debug', arguments = {} }
  end
  return vim.fn.json_decode(parameters_file:read())
end

function utils.set_parameters(parameters)
  local parameters_file = Path:new(config.parameters_file)
  parameters_file:write(vim.fn.json_encode(parameters), 'w')
end

function utils.get_build_dir(parameters)
  if not parameters then
    parameters = utils.get_parameters()
  end

  local build_dir = config.build_dir
  build_dir = build_dir:gsub('{cwd}', vim.fn.getcwd())
  build_dir = build_dir:gsub('{os}', os)
  build_dir = build_dir:gsub('{build_type}', parameters['buildType']:lower())
  return Path:new(build_dir)
end

function utils.get_reply_dir(build_dir)
  return build_dir / '.cmake/api/v1/reply'
end

function utils.get_codemodel_targets(reply_dir)
  local codemodel_json = vim.fn.json_decode(vim.fn.readfile(vim.fn.globpath(tostring(reply_dir), 'codemodel*')))
  return codemodel_json['configurations'][1]['targets']
end

function utils.get_target_info(reply_dir, codemodel_target)
  return vim.fn.json_decode((reply_dir / codemodel_target['jsonFile']):read())
end

-- Tell CMake to generate codemodel
function utils.make_query_files(build_dir)
  local query_dir = build_dir / '.cmake/api/v1/query'
  if not query_dir:mkdir({ parents = true }) then
    vim.notify('Unable to create folder ' .. tostring(query_dir), vim.log.levels.ERROR, { title = 'CMake' })
    return false
  end

  local codemodel_file = query_dir / 'codemodel-v2'
  if not codemodel_file:is_file() then
    if not codemodel_file:touch() then
      vim.notify('Unable to create file ' .. tostring(codemodel_file), vim.log.levels.ERROR, { title = 'CMake' })
      return false
    end
  end
  return true
end

function utils.get_current_executable_info(parameters, build_dir)
  if not build_dir:is_dir() then
    vim.notify('You need to configure first', vim.log.levels.ERROR, { title = 'CMake' })
    return nil
  end

  local target_name = parameters['currentTarget']
  if not target_name then
    vim.notify('You need to select target first', vim.log.levels.ERROR, { title = 'CMake' })
    return nil
  end

  local reply_dir = utils.get_reply_dir(build_dir)
  for _, target in ipairs(utils.get_codemodel_targets(reply_dir)) do
    if target_name == target['name'] then
      local target_info = utils.get_target_info(reply_dir, target)
      if target_info['type'] ~= 'EXECUTABLE' then
        vim.notify('Specified target is not executable: ' .. target_name, vim.log.levels.ERROR, { title = 'CMake' })
        return nil
      end
      return target_info
    end
  end

  vim.notify('Unable to find the following target: ' .. target_name, vim.log.levels.ERROR, { title = 'CMake' })
  return nil
end

function utils.get_current_target(parameters)
  local build_dir = utils.get_build_dir(parameters)
  local target_info = utils.get_current_executable_info(parameters, build_dir)
  if not target_info then
    return nil, nil
  end

  local target = build_dir / target_info['artifacts'][1]['path']
  if not target:is_file() then
    vim.notify('Selected target is not built: ' .. tostring(target), vim.log.levels.ERROR, { title = 'CMake' })
    return nil, nil
  end

  local target_dir
  local run_dir = parameters['runDir']
  if run_dir == nil then
    target_dir = target:parent()
  else
    local target_dir = Path:new(run_dir)
    if not target_dir:is_absolute() then
      target_dir = build_dir / run_dir
    end
    target = target:make_relative(target_dir)
  end
  local arguments = parameters['arguments'][target_info['name']]
  return target_dir, target, arguments
end

function utils.asyncrun_callback(function_string)
  vim.api.nvim_command('autocmd User AsyncRunStop ++once if g:asyncrun_status ==? "success" | call luaeval("' .. function_string .. '") | endif')
end

function utils.copy_compile_commands()
  local compile_commands = utils.get_build_dir() / 'compile_commands.json'
  compile_commands:copy({ destination = vim.fn.getcwd() .. '/compile_commands.json' })
end

function utils.copy_folder(folder, destination)
  destination:mkdir()
  for _, entry in ipairs(vim.fn.readdir(tostring(folder))) do
    local source_entry = folder / entry
    local target_entry = destination / entry
    if source_entry:is_file() then
      if not source_entry:copy({ destination = tostring(target_entry) }) then
        error('Unable to copy ' .. target_entry)
      end
    else
      utils.copy_folder(source_entry, target_entry)
    end
  end
end

function utils.autoclose_quickfix(options)
  local mode = options['mode']
  if not mode or mode ~= 'async' then
    vim.api.nvim_command('cclose')
  end
end

function utils.check_debugging_build_type(parameters)
  local buildType = parameters['buildType']
  if buildType ~= 'Debug' and buildType ~= 'RelWithDebInfo' then
    vim.notify('For debugging you need to use Debug or RelWithDebInfo, but currently your build type is ' .. buildType, vim.log.levels.ERROR, { title = 'CMake' })
    return false
  end
  return true
end

return utils
