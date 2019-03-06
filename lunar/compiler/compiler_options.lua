local CompilerOptions = {}
CompilerOptions.__index = {}

function CompilerOptions.constructor(self, partial_options)
  self.root_dir = partial_options.root_dir or error("root directory must be included in compiler options")
  self.include = partial_options.include or {"src"}
  self.exclude = partial_options.exclude or {}
  self.map_import_path = partial_options.map_import_path or function(source_path, import_path)
    return import_path
  end
end

function CompilerOptions.__index:is_included(file_path)
  local includes_has = false
  for i = 1, #self.include do
    local include = self.include[i]
    if file_path:sub(1, #include + 1) == include .. "/" then
      includes_has = true
    end
  end

  if includes_has then
    local exclude_has = false
    for i = 1, #self.exclude do
      local exclude = self.exclude[i]
      if file_path:sub(1, #exclude + 1) == exclude .. "/" then
        exclude_has = true
      end
    end
    if exclude_has then
      return false
    end

    return true
  end

  return false
end

function CompilerOptions.new(...)
  local self = setmetatable({}, CompilerOptions)
  CompilerOptions.constructor(self)
  return self
end

return CompilerOptions