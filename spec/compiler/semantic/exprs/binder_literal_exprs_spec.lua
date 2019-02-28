local require_dev = require "spec.helpers.require_dev"

describe("Bindings of literal expressions", function()
  require_dev()

  it("should not add symbols to any ast containing only literal expressions", function()
    local tokens = Lexer.new("local x = {1, 'hello', [{}] = nil, x = true}"):tokenize()
    local result = Parser.new(tokens):parse()
    Binder.new(result):bind()

    local var_stat = result[1]
    
    local table_literal_expression = var_stat.exprlist[1]
    assert.same(AST.TableLiteralExpression.new({
        AST.SequentialFieldDeclaration.new(
          AST.NumberLiteralExpression.new(1)
        ),
        AST.SequentialFieldDeclaration.new(
          AST.StringLiteralExpression.new("'hello'")
        ),
        AST.IndexFieldDeclaration.new(
          AST.TableLiteralExpression.new({}),
          AST.NilLiteralExpression.new()
        ),
        AST.MemberFieldDeclaration.new(
          AST.Identifier.new('x'),
          AST.BooleanLiteralExpression.new(true)
        ),
    }), table_literal_expression)
  end)
  
end)