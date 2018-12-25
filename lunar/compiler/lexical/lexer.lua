local BaseLexer = require "lunar.compiler.lexical.base_lexer"
local StringUtils = require "lunar.utils.string_utils"
local TokenInfo = require "lunar.compiler.lexical.token_info"
local TokenType = require "lunar.compiler.lexical.token_type"

local Lexer = setmetatable({}, BaseLexer)
Lexer.__index = Lexer

function Lexer.new(source, file_name)
  if file_name == nil then file_name = "src" end

  local function pair(type, value)
    return { type = type, value = value }
  end

  local super = BaseLexer.new(source, file_name)
  local self = setmetatable(super, Lexer)

  -- we need to guarantee the order (pitfalls of lua hashmaps, yay...)
  -- so we don't end up falsly match \r in \r\n
  -- thanks a lot, old macOS, DOS, and linux: not helping the case of https://xkcd.com/927/
  self.trivias = {
    pair(TokenType.end_of_line_trivia, "\r\n"), -- CRLF
    pair(TokenType.end_of_line_trivia, "\n"), -- LF
    pair(TokenType.end_of_line_trivia, "\r"), -- CR
    -- now that we have support for spaces AND tabs, we're feeding into the classic spaces vs tabs flame wars.
    pair(TokenType.whitespace_trivia, " "),
    pair(TokenType.whitespace_trivia, "\t")
  }

  self.keywords = {
    pair(TokenType.and_keyword, "and"),
    pair(TokenType.break_keyword, "break"),
    pair(TokenType.do_keyword, "do"),
    -- elseif before else and if, otherwise same issue with \r and \r\n
    pair(TokenType.elseif_keyword, "elseif"),
    pair(TokenType.else_keyword, "else"),
    pair(TokenType.end_keyword, "end"),
    pair(TokenType.false_keyword, "false"),
    pair(TokenType.for_keyword, "for"),
    pair(TokenType.function_keyword, "function"),
    pair(TokenType.if_keyword, "if"),
    pair(TokenType.in_keyword, "in"),
    pair(TokenType.local_keyword, "local"),
    pair(TokenType.nil_keyword, "nil"),
    pair(TokenType.not_keyword, "not"),
    pair(TokenType.or_keyword, "or"),
    pair(TokenType.repeat_keyword, "repeat"),
    pair(TokenType.return_keyword, "return"),
    pair(TokenType.then_keyword, "then"),
    pair(TokenType.true_keyword, "true"),
    pair(TokenType.until_keyword, "until"),
    pair(TokenType.while_keyword, "while")
  }

  self.operators = {
    pair(TokenType.triple_dot, "..."),

    pair(TokenType.double_equal, "=="),
    pair(TokenType.tilde_equal, "~="),
    pair(TokenType.left_angle_equal, "<="),
    pair(TokenType.right_angle_equal, ">="),
    pair(TokenType.double_dot, ".."),

    pair(TokenType.left_paren, "("),
    pair(TokenType.right_paren, ")"),
    pair(TokenType.left_brace, "{"),
    pair(TokenType.right_brace, "}"),
    pair(TokenType.left_bracket, "["),
    pair(TokenType.right_bracket, "]"),
    pair(TokenType.plus, "+"),
    pair(TokenType.minus, "-"),
    pair(TokenType.asterisk, "*"),
    pair(TokenType.slash, "/"),
    pair(TokenType.percent, "%"),
    pair(TokenType.caret, "^"),
    pair(TokenType.pound, "#"),
    pair(TokenType.left_angle, "<"),
    pair(TokenType.right_angle, ">"),
    pair(TokenType.equal, "="),
    pair(TokenType.semi_colon, ";"),
    pair(TokenType.colon, ":"),
    pair(TokenType.comma, ","),
    pair(TokenType.dot, ".")
  }

  return self
end

function Lexer:tokenize()
  local tokens = {}
  local ok, token

  repeat
    ok, token = self:next_token()

    if ok then
      self:move(#token.value)
      table.insert(tokens, token)
    end
  until not ok

  -- if position has not reached the end of source, then we failed to tokenize something
  if self.position < #self.source then
    error(("lexical analysis failed at %d %s"):format(self.position, self:peek()))
  end

  return tokens
end

function Lexer:next_token()
  local token = self:next_trivia()
    or self:next_keyword()
    or self:next_identifier()
    or self:next_operator()

  return token ~= nil, token
end

function Lexer:next_trivia()
  for _, trivia in pairs(self.trivias) do
    if self:match(trivia.value) then
      return TokenInfo.new(trivia.type, trivia.value, self.position)
    end
  end
end

function Lexer:next_keyword()
  for _, keyword in pairs(self.keywords) do
    if self:match(keyword.value) then
      return TokenInfo.new(keyword.type, keyword.value, self.position)
    end
  end
end

function Lexer:next_identifier()
  local c = self:peek()

  if StringUtils.is_letter(c) or c == "_" then
    local start_pos = self.position -- to reset to when we finish scanning series of valid characters
    local buffer = ""
    local lookahead

    repeat
      buffer = buffer .. self:peek()
      self:move(1)
      lookahead = self:peek()
    until not (StringUtils.is_letter(lookahead) or lookahead == "_" or StringUtils.is_digit(lookahead))

    self.position = start_pos
    return TokenInfo.new(TokenType.identifier, buffer, self.position)
  end
end

function Lexer:next_operator()
  for _, op in pairs(self.operators) do
    if self:match(op.value) then
      return TokenInfo.new(op.type, op.value, self.position)
    end
  end
end

return Lexer
