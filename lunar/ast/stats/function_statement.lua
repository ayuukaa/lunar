local SyntaxKind = require "lunar.ast.syntax_kind"
local SyntaxNode = require "lunar.ast.syntax_node"

local FunctionStatement = setmetatable({}, SyntaxNode)
FunctionStatement.__index = FunctionStatement

function FunctionStatement.new(name, parameters, block, is_local)
  if is_local == nil then is_local = false end

  local super = SyntaxNode.new(SyntaxKind.function_statement)
  local self = setmetatable(super, FunctionStatement)
  self.name = name -- should only be a TokenInfo if is_local is true
  self.parameters = parameters
  self.block = block
  self.is_local = is_local

  return self
end

return FunctionStatement