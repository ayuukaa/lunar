local SyntaxKind = require("lunar.ast.syntax_kind")
local SyntaxNode = require("lunar.ast.syntax_node")
local MemberExpression = require("lunar.ast.exprs.member_expression")
local FunctionStatement = require("lunar.ast.stats.function_statement")
local ClassFunctionDeclaration = setmetatable({}, {
  __index = SyntaxNode,
})
ClassFunctionDeclaration.__index = setmetatable({}, SyntaxNode)
function ClassFunctionDeclaration.new(start_pos, end_pos, is_static, identifier, params, block, return_type_annotation)
  return ClassFunctionDeclaration.constructor(setmetatable({}, ClassFunctionDeclaration), start_pos, end_pos, is_static, identifier, params, block, return_type_annotation)
end
function ClassFunctionDeclaration.constructor(self, start_pos, end_pos, is_static, identifier, params, block, return_type_annotation)
  SyntaxNode.constructor(self, SyntaxKind.class_function_declaration, start_pos, end_pos)
  self.is_static = is_static
  self.identifier = identifier
  self.params = params
  self.block = block
  self.return_type_annotation = return_type_annotation
  return self
end
function ClassFunctionDeclaration.__index:lower(class_member_expr)
  local new_class_member_expr = MemberExpression.new(nil, nil, class_member_expr, self.identifier, (not self.is_static))
  return FunctionStatement.new(nil, nil, new_class_member_expr, self.params, self.block, nil)
end
return ClassFunctionDeclaration
