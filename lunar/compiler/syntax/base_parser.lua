local TokenInfo = require "lunar.compiler.lexical.token_info"
local TokenType = require "lunar.compiler.lexical.token_type"

local BaseParser = {}
BaseParser.__index = BaseParser

function BaseParser.new(tokens)
  local self = setmetatable({}, BaseParser)
  self.tokens = tokens
  self.position = 1

  return self
end

function BaseParser:is_finished()
  return self.position > #self.tokens
end

function BaseParser:move(by)
  if by == nil then by = 1 end

  if not self:is_finished() then
    self.position = self.position + by
  end
end

-- Peeks at the current token where the parser is currently at
function BaseParser:peek()
  if not self:is_finished() then
    return self.tokens[self.position]
  end
end

function BaseParser:skip_tokens()
  repeat
    local token = self:peek()
    local trivial_token = token.token_type == TokenType.whitespace_trivia
      or token.token_type == TokenType.end_of_line_trivia
      or token.token_type == TokenType.comment

    -- we're done skipping trivial tokens, so break
    if not trivial_token then
      break
    end

    self:move(1)
  until self:is_finished()
end

-- Asserts whether the current token equals the given TokenType
function BaseParser:assert(token_type)
  if not self:is_finished() then
    self:skip_tokens()
    return self:peek().token_type == token_type
  end

  return false
end

-- Expects the current token to be the same as the given token_type, otherwise throws reason
function BaseParser:expect(token_type, reason)
  if not self:is_finished() then
    self:skip_tokens()

    if self:assert(token_type) then
      local token = self:peek()
      self:move(1)
      return token
    end

    error(reason)
  end
end

-- If current token is one of these expected TokenType, moves the position by one
function BaseParser:match_any(...)
  if not self:is_finished() then
    local token_types = { ... }

    self:skip_tokens()

    for _, token_type in pairs(token_types) do
      if self:assert(token_type) then
        self:move(1)
        return true
      end
    end
  end

  return false
end

return BaseParser