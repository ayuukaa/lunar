local AST = require "lunar.ast"
local BaseParser = require "lunar.compiler.syntax.base_parser"
local TokenType = require "lunar.compiler.lexical.token_type"
local SyntaxKind = require "lunar.ast.syntax_kind"

local Parser = setmetatable({}, BaseParser)
Parser.__index = Parser

function Parser.new(tokens)
  local super = BaseParser.new(tokens)
  local self = setmetatable(super, Parser)

  self.binary_op_map = {
    ["+"] = AST.BinaryOpKind.addition_op,
    ["-"] = AST.BinaryOpKind.subtraction_op,
    ["*"] = AST.BinaryOpKind.multiplication_op,
    ["/"] = AST.BinaryOpKind.division_op,
    ["%"] = AST.BinaryOpKind.modulus_op,
    ["^"] = AST.BinaryOpKind.power_op,
    [".."] = AST.BinaryOpKind.concatenation_op,
    ["~="] = AST.BinaryOpKind.not_equal_op,
    ["=="] = AST.BinaryOpKind.equal_op,
    ["<"] = AST.BinaryOpKind.less_than_op,
    ["<="] = AST.BinaryOpKind.less_or_equal_op,
    [">"] = AST.BinaryOpKind.greater_than_op,
    [">="] = AST.BinaryOpKind.greater_or_equal_op,
    ["and"] = AST.BinaryOpKind.and_op,
    ["or"] = AST.BinaryOpKind.or_op,
  }

  self.unary_op_map = {
    ["-"] = AST.UnaryOpKind.negative_op,
    ["not"] = AST.UnaryOpKind.not_op,
    ["#"] = AST.UnaryOpKind.length_op,
  }

  self.self_assignment_op_map = {
    ["="] = AST.SelfAssignmentOpKind.equal_op,
    ["..="] = AST.SelfAssignmentOpKind.concatenation_equal_op,
    ["+="] = AST.SelfAssignmentOpKind.addition_equal_op,
    ["-="] = AST.SelfAssignmentOpKind.subtraction_equal_op,
    ["*="] = AST.SelfAssignmentOpKind.multiplication_equal_op,
    ["/="] = AST.SelfAssignmentOpKind.division_equal_op,
    ["^="] = AST.SelfAssignmentOpKind.power_equal_op,
  }

  return self
end

function Parser:parse()
  local block = self:block()

  if not self:is_finished() then
    local weird_token = self:peek()
    error(("Unexpected token '%s' at %d"):format(weird_token.value, weird_token.position))
  end

  return block
end

function Parser:block()
  local stats = {}

  while not self:is_finished() do
    local stat = self:statement()
    if stat ~= nil then
      table.insert(stats, stat)
      self:match(TokenType.semi_colon)
    end

    local last = self:last_statement()
    if last ~= nil then
      table.insert(stats, last)
      self:match(TokenType.semi_colon)
      break
    end

    if (stat or last) == nil then
      break
    end
  end

  return stats
end

function Parser:class_member()
  if self:peek().value == "constructor" then
    self:move(1)
    self:expect(TokenType.left_paren, "Expected '(' after 'constructor'")
    local params = self:parameter_list()
    self:expect(TokenType.right_paren, "Expected ')' to close '('")
    local block = self:block()
    self:expect(TokenType.end_keyword, "Expected 'end' to close 'constructor'")

    return AST.ConstructorDeclaration.new(params, block)
  end

  -- possibly a static member?
  local old_position = self.position
  local is_static = self:peek().value == "static"
  if is_static then
    self:move(1)
  end

  if self:match(TokenType.function_keyword) then
    local name = self:expect(TokenType.identifier, "Expected identifier after 'function'").value
    self:expect(TokenType.left_paren, "Expected '(' after " .. name)
    local params = self:parameter_list()
    self:expect(TokenType.right_paren, "Expected ')' to close '(' after 'function " .. name .. "'")

    local return_type_annotation = nil
    if self:match(TokenType.colon) then
      return_type_annotation = self:type_expression()
    end

    local block = self:block()

    self:expect(TokenType.end_keyword, "Expected 'end' to close 'function " .. name .. "'")

    return AST.ClassFunctionDeclaration.new(is_static, AST.Identifier.new(name), params, block, return_type_annotation)
  end

  -- nothing was returned and we did something with the 'static' token so we need to move the position back
  self.position = old_position
end

function Parser:statement()
  -- 'class' identifier ['<<' identifier] {class_member} 'end'
  -- 'class' is a contextual keyword that depends on the next token being an identifier
  if self:peek().value == "class" and self:peek(1).token_type == TokenType.identifier then
    self:move(1)
    local name = self:expect(TokenType.identifier, "Expected identifier after 'class'").value

    local super_identifier
    if self:match(TokenType.double_left_angle) then
      super_identifier = AST.Identifier.new(self:expect(TokenType.identifier, "Expected an identifier after '<<'").value)
    end

    local members = {}
    repeat
      local member = self:class_member()

      if member ~= nil then
        table.insert(members, member)
      end
    until member == nil
    self:expect(TokenType.end_keyword, "Expected 'end' to close 'class'")

    return AST.ClassStatement.new(AST.Identifier.new(name), super_identifier, members)
  end

  local primaryexpr = self:primary_expression()
  if primaryexpr ~= nil then
    -- immediately return this if it is a FunctionCallExpression as an ExpressionStatement
    if primaryexpr.syntax_kind == SyntaxKind.function_call_expression then
      return AST.ExpressionStatement.new(primaryexpr)
    elseif primaryexpr.syntax_kind == SyntaxKind.member_expression
      or primaryexpr.syntax_kind == SyntaxKind.index_expression
      or primaryexpr.syntax_kind == SyntaxKind.identifier then
      local variables = { primaryexpr }

      while self:match(TokenType.comma) do
        local expr = self:primary_expression()
        if expr and (expr.syntax_kind == SyntaxKind.member_expression
          or primaryexpr.syntax_kind == SyntaxKind.index_expression
          or  primaryexpr.syntax_kind == SyntaxKind.identifier) then
          table.insert(variables, expr)
        else
          return nil
        end
      end

      local self_assignable_ops = {
        TokenType.equal,
        TokenType.double_dot_equal,
        TokenType.plus_equal,
        TokenType.minus_equal,
        TokenType.asterisk_equal,
        TokenType.slash_equal,
        TokenType.caret_equal
      }

      local op
      if not self:assert(unpack(self_assignable_ops)) then
        self:expect(TokenType.equal, "Expected '=' to follow this variable")
      else
        op = self:consume(unpack(self_assignable_ops))
      end
      local exprs = self:expression_list()

      return AST.AssignmentStatement.new(variables, self.self_assignment_op_map[op.value], exprs)
    else
      -- no other cases are allowed from primary_expression, so we bail out and let the error bubble up
      return nil
    end
  end

  -- 'do' block 'end'
  if self:match(TokenType.do_keyword) then
    local block = self:block()
    self:expect(TokenType.end_keyword, "Expected 'end' to close 'do'")

    return AST.DoStatement.new(block)
  end

  -- 'while' expr 'do' block 'end'
  if self:match(TokenType.while_keyword) then
    local expr = self:expression()
    self:expect(TokenType.do_keyword, "Expected 'do' to close 'while'")
    local block = self:block()
    self:expect(TokenType.end_keyword, "Expected 'end' to close 'do'")

    return AST.WhileStatement.new(expr, block)
  end

  -- 'repeat' block 'until' expr
  if self:match(TokenType.repeat_keyword) then
    local block = self:block()
    self:expect(TokenType.until_keyword, "Expected 'until' to close 'repeat'")
    local expr = self:expression()

    return AST.RepeatUntilStatement.new(block, expr)
  end

  -- 'if' expr 'then' block {'elseif' expr 'then' block} ['else' block] 'end'
  if self:match(TokenType.if_keyword) then
    local expr = self:expression()
    self:expect(TokenType.then_keyword, "Expected 'then' to close 'if'")
    local block = self:block()
    local if_statement = AST.IfStatement.new(expr, block)

    while self:match(TokenType.elseif_keyword) do
      local elseif_expr = self:expression()
      self:expect(TokenType.then_keyword, "Expected 'then' to close 'elseif'")
      local elseif_block = self:block()

      if_statement:push_elseif(AST.IfStatement.new(elseif_expr, elseif_block))
    end

    if self:match(TokenType.else_keyword) then
      local else_block = self:block()
      if_statement:set_else(AST.IfStatement.new(nil, else_block))
    end

    self:expect(TokenType.end_keyword, "Expected 'end' to close 'if'")
    return if_statement
  end

  -- 'for' identifier
  if self:match(TokenType.for_keyword) and self:assert(TokenType.identifier) then
    local first_identifier = self:consume()

    -- '=' expr ',' expr [',' expr] 'do' block 'end'
    if self:match(TokenType.equal) then
      local start_expr = self:expression()
      self:expect(TokenType.comma, "Expected ',' after first expression")
      local end_expr = self:expression()

      local incremental_expr
      if self:match(TokenType.comma) then
        incremental_expr = self:expression()
      end

      self:expect(TokenType.do_keyword, "Expected 'do' to close 'for'")
      local block = self:block()
      self:expect(TokenType.end_keyword, "Expected 'end' to close 'for'")

      return AST.RangeForStatement.new(AST.Identifier.new(first_identifier.value), start_expr, end_expr, incremental_expr, block)
    end

    -- {',' identifier} 'in' exprlist 'do' block 'end'
    if self:assert(TokenType.comma, TokenType.in_keyword) then
      local identifiers = { AST.Identifier.new(first_identifier.value) }

      while self:match(TokenType.comma) do
        local identifier_token = self:expect(TokenType.identifier, "Expected identifier after ','")
        local type_annotation = nil
        if self:match(TokenType.colon) then
          type_annotation = self:type_expression()
        end

        table.insert(identifiers, AST.Identifier.new(identifier_token.value, type_annotation))
      end

      self:expect(TokenType.in_keyword, "Expected 'in' after identifier list")
      local exprlist = self:expression_list()
      self:expect(TokenType.do_keyword, "Expected 'do' to close 'for'")
      local block = self:block()
      self:expect(TokenType.end_keyword, "Expected 'end' to close 'for'")

      return AST.GenericForStatement.new(identifiers, exprlist, block)
    end
  end

  -- 'function' identifier {'.' identifier} [':' identifier] '(' [paramlist] ')' block 'end'
  if self:match(TokenType.function_keyword) then
    local first_identifier = self:expect(TokenType.identifier, "Expected identifier after 'function'")
    local base = AST.Identifier.new(first_identifier.value)

    while self:match(TokenType.dot) do
      local identifier = self:expect(TokenType.identifier, "Expected identifier after '.'")
      base = AST.MemberExpression.new(base, AST.Identifier.new(identifier.value))
    end

    if self:match(TokenType.colon) then
      local identifier = self:expect(TokenType.identifier, "Expected identifier after ':'")
      base = AST.MemberExpression.new(base, AST.Identifier.new(identifier.value), true)
    end

    self:expect(TokenType.left_paren, "Expected '(' to start 'function'")
    local paramlist = self:parameter_list()
    self:expect(TokenType.right_paren, "Expected ')' to close '('")

    local return_type_annotation = nil
    if self:match(TokenType.colon) then
      return_type_annotation = self:type_expression()
    end

    local block = self:block()
    self:expect(TokenType.end_keyword, "Expected 'end' to close 'function'")

    return AST.FunctionStatement.new(base, paramlist, block, return_type_annotation)
  end

  -- 'local'
  if self:match(TokenType.local_keyword) then
    -- 'function' identifier '(' [paramlist] ')' block 'end'
    if self:match(TokenType.function_keyword) then
      local name = self:expect(TokenType.identifier, "Expected identifier after 'function'").value
      self:expect(TokenType.left_paren, "Expected '(' to start 'function'")
      local paramlist = self:parameter_list()
      self:expect(TokenType.right_paren, "Expected ')' to close '('")

      local return_type_annotation = nil
      if self:match(TokenType.colon) then
        return_type_annotation = self:type_expression()
      end

      local block = self:block()
      self:expect(TokenType.end_keyword, "Expected 'end' to close 'function'")

      return AST.FunctionStatement.new(AST.Identifier.new(name), paramlist, block, return_type_annotation, true)
    end

    -- identifier {',' identifier} ['=' exprlist]
    if self:assert(TokenType.identifier) then
      local identlist = {}
      local exprlist

      local i = 0
      repeat
        i = i + 1
        local name = self:expect(TokenType.identifier, "Expected identifier after ','").value
        local type_annotation = nil
        if self:match(TokenType.colon) then
          type_annotation = self:type_expression()
        end
        table.insert(identlist, AST.Identifier.new(name, type_annotation))
      until not self:match(TokenType.comma)

      if self:match(TokenType.equal) then
        exprlist = self:expression_list()
      end

      return AST.VariableStatement.new(identlist, exprlist)
    end
  end
end

function Parser:last_statement()
  -- 'break'
  if self:match(TokenType.break_keyword) then
    return AST.BreakStatement.new()
  end

  -- 'return' [exprlist]
  if self:match(TokenType.return_keyword) then
    local exprlist = self:expression_list()

    -- prefer nil if there is no expressions
    if #exprlist == 0 then
      return AST.ReturnStatement.new(nil)
    end

    return AST.ReturnStatement.new(exprlist)
  end
end

function Parser:function_arg()
  -- expr
  local expr = self:expression()
  if expr ~= nil then
    return AST.ArgumentExpression.new(expr)
  end
end

function Parser:function_arg_list()
  -- '(' arg {',' arg} ')'
  if self:match(TokenType.left_paren) then
    local args = {}

    repeat
      local arg = self:function_arg()

      if arg ~= nil then
        table.insert(args, arg)
      end
    until not self:match(TokenType.comma)

    self:expect(TokenType.right_paren, "Expected ')' to close '('")

    return args
  end

  -- string | TableLiteralExpression
  if self:assert(TokenType.string, TokenType.left_brace) then
    return { self:function_arg() }
  end
end

function Parser:prefix_expression()
  -- '(' expr ')'
  if self:match(TokenType.left_paren) then
    local expr = AST.PrefixExpression.new(self:expression())
    self:expect(TokenType.right_paren, "Expected ')' to close '('")

    return expr
  end

  -- identifier
  if self:assert(TokenType.identifier) then
    local identifier = self:consume()

    return AST.Identifier.new(identifier.value)
  end
end

function Parser:expression()
  return self:sub_expression(0)
end

function Parser:primary_expression()
  local expr = self:prefix_expression()

  while true do
    if self:match(TokenType.dot) then
      local identifier = self:expect(TokenType.identifier, "Expected identifier after '.'")
      expr = AST.MemberExpression.new(expr, AST.Identifier.new(identifier.value))
    elseif self:match(TokenType.left_bracket) then
      local inner_expr = self:expression()
      self:expect(TokenType.right_bracket, "Expected ']' to close '['")
      expr = AST.IndexExpression.new(expr, inner_expr)
    elseif self:match(TokenType.colon) then
      local identifier = self:expect(TokenType.identifier, "Expected identifier after ':'")
      local args = self:function_arg_list()
      expr = AST.FunctionCallExpression.new(
        AST.MemberExpression.new(expr, AST.Identifier.new(identifier.value), true),
        args
      )
    elseif self:assert(TokenType.left_paren, TokenType.string, TokenType.left_brace) then
      local args = self:function_arg_list()
      expr = AST.FunctionCallExpression.new(expr, args)
    else
      return expr
    end
  end
end

function Parser:simple_expression()
  -- 'nil'
  if self:match(TokenType.nil_keyword) then
    return AST.NilLiteralExpression.new()
  end

  -- 'true' | 'false'
  if self:assert(TokenType.true_keyword, TokenType.false_keyword) then
    local boolean_token = self:consume()
    return AST.BooleanLiteralExpression.new(boolean_token.token_type == TokenType.true_keyword)
  end

  -- number
  if self:assert(TokenType.number) then
    local number_token = self:consume()
    return AST.NumberLiteralExpression.new(tonumber(number_token.value))
  end

  -- string
  if self:assert(TokenType.string) then
    local string_token = self:consume()
    return AST.StringLiteralExpression.new(string_token.value)
  end

  -- '{' [fieldlist] '}'
  if self:match(TokenType.left_brace) then
    local fieldlist = self:field_list()
    self:expect(TokenType.right_brace, "Expected '}' to close '{'")

    return AST.TableLiteralExpression.new(fieldlist)
  end

  -- '...'
  if self:match(TokenType.triple_dot) then
    return AST.VariableArgumentExpression.new()
  end

  -- 'function' '(' [paramlist] ')' block 'end'
  if self:match(TokenType.function_keyword) then
    self:expect(TokenType.left_paren, "Expected '(' to start 'function'")
    local paramlist = self:parameter_list()
    self:expect(TokenType.right_paren, "Expected ')' to close '('")

    local return_type_annotation = nil
    if self:match(TokenType.colon) then
      return_type_annotation = self:type_expression()
    end

    local block = self:block()
    self:expect(TokenType.end_keyword, "Expected 'end' to close 'function'")

    return AST.FunctionExpression.new(paramlist, block, return_type_annotation)
  end

  -- ['|' paramlist '|'] 'do' block 'end | '|' [paramlist] '|' expr
  if self:match(TokenType.bar) then
    local params = self:parameter_list()
    self:expect(TokenType.bar, "Expected '|' to close '|'")

    local return_type_annotation = nil
    if self:match(TokenType.colon) then
      return_type_annotation = self:type_expression()
    end

    -- need to make sure this doesn't return another lambda!
    if self:match(TokenType.do_keyword) then
      local block = self:block()
      self:expect(TokenType.end_keyword, "Expected 'end' to close 'do'")

      return AST.LambdaExpression.new(params, block, false, return_type_annotation)
    else
      local expr = self:expression()

      return AST.LambdaExpression.new(params, expr, true, return_type_annotation)
    end
  elseif self:match(TokenType.do_keyword) then
    local block = self:block()
    self:expect(TokenType.end_keyword, "Expected 'end' to close 'do'")

    return AST.LambdaExpression.new({}, block, false, nil)
  end

  return self:primary_expression()
end

function Parser:type_expression()
  -- Allow certain keywords to overload as type identifiers
  if self:assert(TokenType.nil_keyword)
    or self:assert(TokenType.function_keyword)
    or self:assert(TokenType.true_keyword)
    or self:assert(TokenType.false_keyword) then
    return AST.Identifier.new(self:consume().value)
  end
  if self:assert(TokenType.identifier) then
    return AST.Identifier.new(self:consume().value)
  else
    error("Expected identifier in type expression")
  end
end

-- using this as the basis for unary, binary, and simple expressions
-- https://github.com/lua/lua/blob/98194db4295726069137d13b8d24fca8cbf892b6/lparser.c#L778-L853
function Parser:get_unary_op()
  local ops = {
    TokenType.minus,
    TokenType.not_keyword,
    TokenType.pound,
  }

  if self:assert(unpack(ops)) then
    local op = self:peek()
    return self.unary_op_map[op.value]
  end
end

function Parser:get_binary_op()
  local ops = {
    TokenType.plus,
    TokenType.minus,
    TokenType.asterisk,
    TokenType.slash,
    TokenType.percent,
    TokenType.caret,
    TokenType.double_dot,
    TokenType.tilde_equal,
    TokenType.double_equal,
    TokenType.left_angle,
    TokenType.left_angle_equal,
    TokenType.right_angle,
    TokenType.right_angle_equal,
    TokenType.and_keyword,
    TokenType.or_keyword,
  }

  if self:assert(unpack(ops)) then
    local op = self:peek()
    return self.binary_op_map[op.value]
  end
end

local unary_priority = 8
local priority = {
  -- '+' | '-' | '*' | '/' | '%'
  { 6, 6 }, { 6, 6 }, { 7, 7 }, { 7, 7 }, { 7, 7 },
  -- '^' | '..'
  { 10, 9 }, { 5, 4 },
  -- '==' | '~='
  { 3, 3 }, { 3, 3 },
  -- '<', | '<=' | '>' | '>='
  { 3, 3 }, { 3, 3 }, { 3, 3 }, { 3, 3 },
  -- 'and' | 'or'
  { 2, 2 }, { 1, 1 },
}

function Parser:sub_expression(limit)
  local expr

  local unary_op = self:get_unary_op()
  if unary_op ~= nil then
    self:consume()
    expr = AST.UnaryOpExpression.new(unary_op, self:sub_expression(unary_priority))
  else
    expr = self:simple_expression()
  end

  local binary_op = self:get_binary_op()
  -- if binary_op is not nil and left priority of this binary_op is greater than current limit
  while binary_op ~= nil and priority[binary_op][1] > limit do
    self:consume()
    -- parse a new sub_expression with the right priority of this binary_op
    local next_expr = self:sub_expression(priority[binary_op][2])
    expr = AST.BinaryOpExpression.new(expr, binary_op, next_expr)

    -- is there any binary op after this?
    binary_op = self:get_binary_op()
  end

  -- Type assertions
  while self:match(TokenType.as_keyword) do
    -- Parse a type expression
    expr = AST.TypeAssertionExpression.new(expr, self:type_expression())
  end

  return expr
end

function Parser:expression_list()
  -- expr {',' expr}
  local exprlist = {}

  repeat
    local expr = self:expression()

    if expr ~= nil then
      table.insert(exprlist, expr)
    end
  until not self:match(TokenType.comma)

  return exprlist
end

function Parser:parameter_declaration()
  -- identifier | '...'
  if self:assert(TokenType.identifier, TokenType.triple_dot) then
    local param = self:consume()

    local type_annotation = nil
    if self:match(TokenType.colon) then
      type_annotation = self:type_expression()
    end

    return AST.ParameterDeclaration.new(AST.Identifier.new(param.value, type_annotation))
  end
end

function Parser:parameter_list()
  -- param {',' param} [',' '...']
  -- keep parsing params until we see '...' or there's no ','
  local paramlist = {}
  local param

  repeat
    param = self:parameter_declaration()
    if param ~= nil then
      table.insert(paramlist, param)
    end
  until not self:match(TokenType.comma) or param.identifier.name == "..."

  return paramlist
end

function Parser:field_declaration()
  -- '[' expr ']' '=' expr
  if self:match(TokenType.left_bracket) then
    local key = self:expression()
    self:expect(TokenType.right_bracket, "Expected ']' to close '['")
    self:expect(TokenType.equal, "Expected '=' near ']'")
    local value = self:expression()

    return AST.IndexFieldDeclaration.new(key, value)
  end

  -- identifier '=' expr
  if self:peek(1) and self:peek(1).token_type == TokenType.equal then
    local key = self:expect(TokenType.identifier, "Expected identifier to start this field")
    self:consume() -- consumes the equal token, because we asserted it earlier
    local value = self:expression()

    return AST.MemberFieldDeclaration.new(AST.Identifier.new(key.value), value)
  end

  -- expr
  local value = self:expression()
  if value ~= nil then
    return AST.SequentialFieldDeclaration.new(value)
  end
end

function Parser:field_list()
  -- field {(',' | ';') field} [(',' | ';')]
  local fieldlist = {}
  local lastfield

  repeat
    lastfield = self:field_declaration()
 
    if lastfield ~= nil then
      table.insert(fieldlist, lastfield)
      self:match(TokenType.comma, TokenType.semi_colon)
    end
  until lastfield == nil

  return fieldlist
end

return Parser
