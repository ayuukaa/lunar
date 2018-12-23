local Lexer = require "lunar.compiler.lexical.lexer"
local TokenInfo = require "lunar.compiler.lexical.token_info"
local TokenType = require "lunar.compiler.lexical.token_type"

describe("Lexer tokenization for trivial tokens", function()
  it("should return one TokenType.whitespace_trivia", function()
    local tokens = Lexer.new(" "):tokenize()

    assert.same({
      TokenInfo.new(TokenType.whitespace_trivia, " ", 1)
    }, tokens)
  end)

  it("should return two TokenType.whitespace_trivia", function()
    local tokens = Lexer.new("  "):tokenize()

    assert.same({
      TokenInfo.new(TokenType.whitespace_trivia, " ", 1),
      TokenInfo.new(TokenType.whitespace_trivia, " ", 2)
    }, tokens)
  end)

  it("should return four TokenType.whitespace_trivia with mixed spaces and tabs", function()
    local tokens = Lexer.new(" \t \t"):tokenize()

    assert.same({
      TokenInfo.new(TokenType.whitespace_trivia, " ", 1),
      TokenInfo.new(TokenType.whitespace_trivia, "\t", 2),
      TokenInfo.new(TokenType.whitespace_trivia, " ", 3),
      TokenInfo.new(TokenType.whitespace_trivia, "\t", 4)
    }, tokens)
  end)

  it("should return TokenType.end_of_line_trivia with any EOL style", function()
    local tokens = Lexer.new("\r\r\n\n"):tokenize()

    assert.same({
      TokenInfo.new(TokenType.end_of_line_trivia, "\r", 1),
      TokenInfo.new(TokenType.end_of_line_trivia, "\r\n", 2),
      TokenInfo.new(TokenType.end_of_line_trivia, "\n", 4)
    }, tokens)
  end)
end)
