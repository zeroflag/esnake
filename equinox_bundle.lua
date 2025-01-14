do
local _ENV = _ENV
package.preload[ "ast" ] = function( ... ) local arg = _G.arg;
local ast = {}

local id_counter = 1

function ast.gen_id(prefix)
  id_counter = id_counter + 1
  return prefix .. id_counter
end

function ast.func_header(func_name, global)
  return {
    name = "func_header",
    func_name = func_name,
    params = {},
    global = global
  }
end

function ast.func_call(func_name, ...)
  return {
    name = "func_call",
    func_name = func_name,
    args = {...}
  }
end

function ast.pop()
  return {name = "stack_consume", op  = "pop"}
end

function ast.pop2nd()
  return {name = "stack_consume", op  = "pop2nd"}
end

function ast.pop3rd()
  return {name = "stack_consume", op  = "pop3rd"}
end

function ast.stack_peek(operation)
  return {name = "stack_peek", op = operation}
end

function ast.stack_op(operation)
  return {name = "stack_op", op = operation}
end

function ast.aux_op(operation)
  return {name = "aux_op", op = operation}
end

function ast.push(item)
  return {name  = "push", item = item}
end

function ast.push_many(func_call)
  return {name  = "push_many", func_call = func_call}
end

function ast.aux_push(item)
  return {name  = "push_aux", item = item}
end

function ast._while(cond)
  return {
    name = "while",
    cond = cond
  }
end

function ast._until(cond)
  return {
    name = "until",
    cond = cond
  }
end

function ast.literal(kind, value)
  return {
    name = "literal",
    kind = kind,
    value = value
  }
end

function ast.str(val)
  return ast.literal("string", val)
end

function ast.bin_op(operator, param1, param2)
  return {
    name = "bin_op",
    op = operator,
    p1 = param1,
    p2 = param2
  }
end

function ast.unary_op(operator, operand)
  return {name = "unary_op", op = operator, exp = operand}
end

function ast.assignment(var, exp)
  return {name = "assignment", var  = var, exp  = exp}
end

function ast.init_local(var, exp)
  return {name = "init_local", var = var, exp = exp}
end

function ast._if(cond, body)
  return {name = "if", exp = cond, body = body}
end

function ast.def_local(var)
  return {name = "local", var = var}
end

function ast.new_table()
  return {name = "table_new"}
end

function ast.table_at(tbl, key)
  return {name = "table_at", key = key, tbl = tbl}
end

function ast.table_put(tbl, key, value)
  return {
    name = "table_put",
    tbl = tbl,
    key = key,
    value = value
  }
end

function ast.keyword(keyword)
  return {name = "keyword", keyword = keyword}
end

function ast.identifier(id)
  return {name = "identifier", id = id}
end

function ast._return(opt_arg)
  return {name = "return", arg = opt_arg}
end

function ast._for(loop_var, start, stop, step)
  return {
    name = "for",
    loop_var = loop_var,
    start = start,
    stop = stop,
    step = step
  }
end

function ast._foreach(loop_var1, loop_var2, iterable)
  return {
    name = "for_each",
    loop_var1 = loop_var1,
    loop_var2 = loop_var2,
    iterable = iterable
  }
end

function ast._ipairs(iterable)
  return {name = "ipairs", iterable = iterable}
end

function ast._pairs(iterable)
  return {name = "pairs", iterable = iterable}
end

return ast
end
end

do
local _ENV = _ENV
package.preload[ "ast_matchers" ] = function( ... ) local arg = _G.arg;
local AstMatcher = {}

local function is(ast, name) return ast.name == name end
local function is_literal(ast) return is(ast, "literal") end
local function is_identifier(ast) return is(ast, "identifier") end
local function is_stack_consume(ast) return is(ast, "stack_consume") end
local function any(ast) return ast ~= nil end

local function is_literal_tbl_at(ast)
  return is(ast, "table_at")
    and (is_identifier(ast.tbl) or is_literal(ast.tbl))
    and (is_identifier(ast.key) or is_literal(ast.key))
end

local function is_const(ast)
  return is_identifier(ast)
    or is_literal(ast)
    or is_literal_tbl_at(ast)
end

local function is_push_const(ast)
  return is(ast, "push") and is_const(ast.item)
end

local function OR(...)
  local fs = {...}
  return function(ast)
    local result = false
    for i, f in ipairs(fs) do
      result = result or f(ast)
    end
    return result
  end
end

local function NOT(f)
  return function(ast)
    return not f(ast)
  end
end

local function is_stack_op(op)
  return function(ast)
    return is(ast, "stack_op") and ast.op == op
  end
end

local function is_push_binop(ast)
  return is(ast, "push") and is(ast.item, "bin_op")
end

local function is_push_binop_pop(ast)
  return is_push_binop(ast)
    and is_stack_consume(ast.item.p1)
    and is_stack_consume(ast.item.p2)
end

local function is_push_unop(ast)
  return is(ast, "push") and is(ast.item, "unary_op")
end

local function is_push_unop_pop(ast)
  return is_push_unop(ast) and is_stack_consume(ast.item.exp)
end

local function is_tbl_at(ast)
  return is(ast, "push")
    and is(ast.item, "table_at")
    and is_stack_consume(ast.item.tbl)
    and is_stack_consume(ast.item.key)
end

local function is_tbl_put(ast)
  return is(ast, "table_put") -- no push here
    and is_stack_consume(ast.tbl)
    and is_stack_consume(ast.key)
end

local function is_assignment(ast)
  return is(ast, "assignment") and is_stack_consume(ast.exp)
end

local function is_if(ast)
  return is(ast, "if") and is_stack_consume(ast.exp)
end

local function is_init_local(ast)
  return is(ast, "init_local") and is_stack_consume(ast.exp)
end

function AstMatcher:new(name, parts)
  local obj = {name = name, parts = parts, logging = false}
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function AstMatcher:matches(ast, start)
  for i, matcher in ipairs(self.parts) do
    if start + i -1 > #ast then return false end
    local node = ast[start + i -1]
    if not matcher(node) then
      return false
    end
  end
  return true
end

function AstMatcher:optimize(ast, i, result)
  error("not implemented")
end

function AstMatcher:log(message)
  if self.logging then
    print("[OPTI] " .. self.name .. ": " .. message)
  end
end

function AstMatcher:size()
  return #self.parts
end

AtParamsInline = AstMatcher:new()
AtParamsInlineP2 = AstMatcher:new()
PutParamsInline = AstMatcher:new()
StackOpBinaryInline = AstMatcher:new()
BinaryInline = AstMatcher:new()
BinaryInlineP2 = AstMatcher:new()
InlineGeneralUnary = AstMatcher:new()

--[[
 Inline table at parameters
  1.)  t  4 at   =>   PUSH(t[4])
]]--
function AtParamsInline:optimize(ast, i, result)
  self:log("inlining tbl at params")
  local tbl, idx, op = ast[i], ast[i + 1], ast[i + 2]
  op.item.tbl = tbl.item
  op.item.key = idx.item
  table.insert(result, op)
end

--[[
 Inline table at index parameter
  1.)  ... 4 at   =>   PUSH(POP[4])
]]--
function AtParamsInlineP2:optimize(ast, i, result)
  self:log("inlining tbl at 2nd param")
  local tbl, idx, op = ast[i], ast[i + 1], ast[i + 2]
  if op.item.tbl.name == "stack_consume" and
     op.item.tbl.op == "pop2nd"
  then
    op.item.tbl.op = "pop"
  end
  op.item.key = idx.item
  table.insert(result, tbl)
  table.insert(result, op)
end

--[[
 Inline table put parameters
  1.)  t 4 "abc" put   =>   t[4]="abc"
]]--
function PutParamsInline:optimize(ast, i, result)
  self:log("inlining tbl put params")
  local tbl, key, val, op = ast[i], ast[i + 1], ast[i + 2], ast[i + 3]
  op.tbl = tbl.item
  op.key = key.item
  op.value = val.item
  table.insert(result, op)
end

--[[
 Inline assignment/init-local(used internal) operator's value operand

  1.) 123 -> v   =>   v = 123
  2.) false not   =>   PUSH(not false)
  3.) false not IF ... THEN   =>   IF not false THEN ... END
  4.) 10 v  <   IF ... THEN   =>   IF 10 < v    THEN ... END
  5.)    v      IF ... THEN   =>   IF v         THEN ... END
  6.) DUP IF .. THEN   =>   TOS IF .. THEN
  7.) OVER IF .. THEN   =>   TOS2 IF .. THEN
  8.) [ 1 2 3 ] DUP size   =>   PUSH(#TOS)
  9.) true false over not => PUSH(NOT TOS2)
]]--
function InlineGeneralUnary:optimize(ast, i, result)
  local p1, operator = ast[i], ast[i + 1]
  local target
  if is_push_unop_pop(operator) then
    -- unary is embedded into a push
    target = operator.item
  else
    target = operator
  end

  if is_stack_op("dup")(p1) then
    self:log(operator.name .. " (dup)")
    target.exp.op = "tos"
    target.exp.name ="stack_peek"
  elseif is_stack_op("over")(p1) then
    self:log(operator.name .. " (over)")
    target.exp.op = "tos2"
    target.exp.name ="stack_peek"
  else
    self:log(operator.name)
    target.exp = p1.item
  end

  table.insert(result, operator)
end

--[[
 Inline DUP followed by binary operator

  1.) 3 DUP *      =>   PUSH(TOS * POP)
  2.) DUP DUP *    =>   PUSH(TOS * TOS)
  3.) 3 7 OVER +   =>   PUSH(TOS2 + POP)
  4.) 3 7 OVER -   =>   PUSH(POP  - TOS)
  5.) 1 2 2DUP +   =>   PUSH(TOS + TOS)
]]--
function StackOpBinaryInline:optimize(ast, i, result)
  local p1, p2, op = ast[i], ast[i + 1], ast[i + 2]
  if is_stack_op("dup")(p1) and is_stack_op("dup")(p2) then
    -- double dup
    self:log("dup dup")
    op.item.p1.op = "tos"
    op.item.p2.op = "tos"
    op.item.p1.name = "stack_peek"
    op.item.p2.name = "stack_peek"
    table.insert(result, op)
  elseif is_stack_op("dup2")(p2) then
    self:log("2dup")
    op.item.p1.op = "tos2"
    op.item.p2.op = "tos"
    op.item.p1.name = "stack_peek"
    op.item.p2.name = "stack_peek"
    table.insert(result, p1)
    table.insert(result, op)
  elseif is_stack_op("dup")(p2) then
    -- single dup
    self:log("single dup")
    op.item.p1.op = "tos"
    op.item.p1.name = "stack_peek"
    table.insert(result, p1)
    table.insert(result, op)
  elseif is_stack_op("over")(p2) then
    -- single over
    self:log("over")
    op.item.p1.op = "pop"
    op.item.p1.name = "stack_peek"
    op.item.p2.op = "tos"
    op.item.p2.name = "stack_peek"
    table.insert(result, p1)
    table.insert(result, op)
  else
    error("Unexpected p2: " .. tostring(p2.name))
  end
end

--[[
 Inline binary operator's ALL constant operands

  1.) 12      45 +   =>   PUSH(12   + 45)
  2.) 12      v1 +   =>   PUSH(12   + v1)
  3.) t 1 at  45 +   =>   PUSH(t[1] + 45)
]]--
function BinaryInline:optimize(ast, i, result)
  self:log("inlining binary operator params")
  local p1, p2, op = ast[i], ast[i + 1], ast[i + 2]
  op.item.p1 = p1.item
  op.item.p2 = p2.item
  table.insert(result, op)
end

--[[
 Inline binary operator's 2nd, constant operand
 Additonally replace DUP with DROP if applicable

  1.)      123 +   =>   PUSH(POP + 123)
  2.)  DUP 123 +   =>   PUSH(TOS + 123)
]]--
function BinaryInlineP2:optimize(ast, i, result)
  self:log("inlining binary operator's 2nd param")
  local p1, p2, op = ast[i], ast[i + 1], ast[i + 2]
  if op.item.p1.name == "stack_consume" then
    if op.item.p1.op == "pop2nd" then
      op.item.p1.op = "pop"
    end
    if is_stack_op("dup")(p1) then
      op.item.p1.op = "tos" -- inline if dup
      op.item.p1.name = "stack_peek"
    end
  end
  op.item.p2 = p2.item -- inline const param
  if not is_stack_op("dup")(p1) then -- dup was inlined skip it
    table.insert(result, p1)
  end
  table.insert(result, op)
end

return {

  PutParamsInline:new(
    "inline put params ",
    {is_push_const, is_push_const, is_push_const, is_tbl_put}),

  AtParamsInline:new(
    "inline at params",
    {is_push_const, is_push_const, is_tbl_at}),

  AtParamsInlineP2:new(
    "inline at p2",
    {NOT(is_push_const), is_push_const, is_tbl_at}),

  BinaryInline:new(
    "binary inline",
    {is_push_const, is_push_const, is_push_binop_pop}),

  BinaryInlineP2:new(
    "binary p2 inline",
    {NOT(is_push_const), is_push_const, is_push_binop_pop}),

  StackOpBinaryInline:new(
    "stackop binary inline",
    {any, OR(is_stack_op("dup"),
             is_stack_op("dup2"), -- 2dup
             is_stack_op("over")), is_push_binop_pop}),

  InlineGeneralUnary:new(
    "inline general unary",
    {OR(is_stack_op("dup"),
        is_stack_op("over"),
        is_push_const,
        is_push_unop,
        is_push_binop),
     OR(is_init_local,  -- init-local only optimizes one parameter
        is_assignment,
        is_if,
        is_push_unop_pop)}),

}
end
end

do
local _ENV = _ENV
package.preload[ "ast_optimizer" ] = function( ... ) local arg = _G.arg;
local Optimizer = {}
local matchers = require("ast_matchers")

function Optimizer.new()
  local obj = {logging = false, enabled = true}
  setmetatable(obj, {__index = Optimizer})
  return obj
end

function Optimizer:enable_logging(bool)
  self.logging = bool
end

function Optimizer:enable(bool)
  self.enabled = bool
end

function Optimizer:log_ast(node)
  --require("tests/json")
  --self:log("AST: " .. to_json_str(node))
end

function Optimizer:log(txt)
  if self.logging then
    print("[OPTI] " .. txt)
  end
end

function Optimizer:optimize_iteratively(ast)
  if not self.enabled then return ast end
  local num_of_optimizations, iterations = 0, 0
  repeat
    ast, num_of_optimizations = self:optimize(ast)
    iterations = iterations + 1
    self:log(string.format(
          "Iteration: %d finished. Number of optimizations: %d",
          iterations, num_of_optimizations))
  until num_of_optimizations == 0
  return ast
end

function Optimizer:optimize(ast)
  local result, i, num_matches = {}, 1, 0
  while i <= #ast do
    local node = ast[i]
    self:log_ast(node)
    local found = false
    for _, matcher in ipairs(matchers) do
      if matcher:matches(ast, i) then
        matcher.logging = self.logging
        matcher:optimize(ast, i, result)
        i = i + matcher:size()
        num_matches = num_matches + 1
        found = true
      end
    end
    if not found then
      table.insert(result, node)
      i = i + 1
    end
  end
  return result, num_matches
end

return Optimizer
end
end

do
local _ENV = _ENV
package.preload[ "aux" ] = function( ... ) local arg = _G.arg;
local Stack = require("stack_def")
local aux = Stack.new("aux-stack")

return aux
end
end

do
local _ENV = _ENV
package.preload[ "codegen" ] = function( ... ) local arg = _G.arg;
local CodeGen = {}

function CodeGen.new()
  local obj = {}
  setmetatable(obj, {__index = CodeGen})
  return obj
end

function CodeGen:gen(ast)
  if "stack_op" == ast.name
    or "stack_consume" == ast.name
    or "stack_peek" == ast.name then
    return "stack:" .. ast.op .. "()"
  end
  if "aux_op" == ast.name then
    return "aux:" .. ast.op .. "()"
  end
  if "push" == ast.name then
    return string.format("stack:push(%s)", self:gen(ast.item))
  end
  if "push_many" == ast.name then
    return string.format("stack:push_many(%s)", self:gen(ast.func_call))
  end
  if "push_aux" == ast.name then
    return string.format("aux:push(%s)", self:gen(ast.item))
  end
  if "unary_op" == ast.name then
    return string.format("%s %s", ast.op, self:gen(ast.exp))
  end
  if "bin_op" == ast.name then
    return string.format(
      "%s %s %s", self:gen(ast.p1), ast.op, self:gen(ast.p2))
  end
  if "local" == ast.name then
    return "local " .. ast.var
  end
  if "init_local" == ast.name then
    return "local " .. ast.var .. "=" .. self:gen(ast.exp)
  end
  if "assignment" == ast.name then
    return ast.var .. " = " .. self:gen(ast.exp)
  end
  if "literal" == ast.name and "boolean" == ast.kind then
    return ast.value
  end
  if "literal" == ast.name and "string" == ast.kind then
    return '"' .. ast.value .. '"'
  end
  if "literal" == ast.name and "number" == ast.kind then
    return ast.value
  end
  if "while" == ast.name then
    return string.format("while(%s)do", self:gen(ast.cond))
  end
  if "until" == ast.name then
    return string.format("until %s", self:gen(ast.cond))
  end
  if "for" == ast.name and not ast.step then
      return string.format(
        "for %s=%s,%s do",
        ast.loop_var, self:gen(ast.start), self:gen(ast.stop))
  end
  if "for" == ast.name and ast.step then
      return string.format(
        "for %s=%s,%s,%s do",
        ast.loop_var,
        self:gen(ast.start),
        self:gen(ast.stop),
        self:gen(ast.step))
  end
  if "for_each" == ast.name then
      return string.format(
        "for %s,%s in %s do",
        ast.loop_var1, ast.loop_var2, self:gen(ast.iterable))
  end
  if "pairs" == ast.name then
    return string.format("pairs(%s)", self:gen(ast.iterable))
  end
  if "ipairs" == ast.name then
    return string.format("ipairs(%s)", self:gen(ast.iterable))
  end
  if "if" == ast.name then
    if ast.body then
      return "if " .. self:gen(ast.exp) .. " then " .. self:gen(ast.body) .. " end"
    else
      return "if " .. self:gen(ast.exp) .. " then"
    end
  end
  if "return" == ast.name then
    if ast.arg then
      return "return " .. self:gen(ast.arg)
    else
      return "do return end"
    end
  end
  if "keyword" == ast.name then return ast.keyword end
  if "identifier" == ast.name then return ast.id end
  if "table_new" == ast.name then return "stack:push({})" end
  if "table_at" == ast.name then
    return string.format("%s[%s]",
                         self:gen(ast.tbl), self:gen(ast.key))
  end
  if "table_put" == ast.name then
    return string.format(
      "%s[%s]=%s",
      self:gen(ast.tbl), self:gen(ast.key), self:gen(ast.value))
  end
  if "func_call" == ast.name then
    local params = ""
    for i, p in ipairs(ast.args) do
      params = params .. self:gen(p)
      if i < #ast.args then
        params = params .. ","
      end
    end
    return string.format("%s(%s)", ast.func_name, params)
  end
  if "code_seq" == ast.name then
    local result = ""
    for i, c in ipairs(ast.code) do
      result = result .. self:gen(c)
      if i < #ast.code then
        result = result .. "\n"
      end
    end
    return result
  end
  if "func_header" == ast.name then
    local prefix = ""
    if not ast.global then prefix = "local " end
    local result = string.format("%sfunction %s(", prefix, ast.func_name)
    for i, p in ipairs(ast.params) do
      result = result .. p
      if i < #ast.params then result = result .. "," end
    end
    return result .. ")\n"
  end
  error("Unknown AST: " .. tostring(ast) ..
        " with name: " .. tostring(ast.name))
end

return CodeGen
end
end

do
local _ENV = _ENV
package.preload[ "compiler" ] = function( ... ) local arg = _G.arg;
-- TODO
-- tab auto complete repl (linenoise/readline)
-- tbl lookup check var name (t.x)
-- basic syntax check
-- debuginfo level (assert)
-- inline

local stack = require("stack")
local macros = require("macros")
local Stack = require("stack_def")
local Dict = require("dict")
local Parser = require("parser")
local LineMapping = require("line_mapping")
local Output = require("output")
local Env = require("env")
local interop = require("interop")
local ast = require("ast")
local unpack = table.unpack or unpack

local Compiler = {}

function Compiler.new(codegen, optimizer)
  local obj = {
    parser = nil,
    output = nil,
    code_start = 1,
    line_mapping = nil,
    env = Env.new(nil, "root"),
    optimizer = codegen,
    codegen = optimizer,
    chunk_name = "<<compiled eqx code>>",
    dict = Dict.new()
  }
  obj.env:def_var_unsafe("true", "true")
  obj.env:def_var_unsafe("false", "false")
  obj.env:def_var_unsafe("nil", "NIL")
  setmetatable(obj, {__index = Compiler})
  return obj
end

function Compiler:init(text)
  self.parser = Parser.new(text)
  self.output = Output.new(self.chunk_name)
  self.line_mapping = LineMapping.new()
  self.output:append("local stack = require(\"stack\")")
  self.output:new_line()
  self.output:append("local aux = require(\"aux\")")
  self.output:new_line()
  self.ast = {}
  self.code_start = self.output:size()
end

function Compiler:new_env(name)
  self.env = Env.new(self.env, name)
end

function Compiler:remove_env(name)
  if name and self.env.name ~= name then
    error("Incorrect nesting: " .. name)
  end
  if self.env.parent then
    self.env = self.env.parent
  else
    error("cannot drop root environment")
  end
end

function Compiler:def_var(name)
  self.env:def_var(name)
end

function Compiler:has_var(name)
  return self.env:has_var(name)
end

function Compiler:word()
  return self.parser:next_item().token
end

function Compiler:find(forth_name)
  return self.dict:find(forth_name)
end

function Compiler:next_chr()
  return self.parser:next_chr()
end

function Compiler:peek_chr()
  return self.parser:peek_chr()
end

function Compiler:word_list()
  return self.dict:word_list()
end

function Compiler:alias(lua_name, forth_alias)
  return self.dict:def_lua_alias(lua_name, forth_alias)
end

function Compiler:lua_call(name, arity, void)
  local params = {}
  local stmts = {}
  if arity > 0 then
    for i = 1, arity do
      table.insert(params,
        ast.identifier(ast.gen_id("__p")))
    end
    for i = arity, 1, -1 do -- reverse parameter order
      table.insert(stmts,
        ast.init_local(params[i].id, ast.pop()))
    end
  end
  if void then
    table.insert(stmts, ast.func_call(name, unpack(params)))
  else
    table.insert(stmts, ast.push_many(
                   ast.func_call(name, unpack(params))))
  end
  return stmts
end

function Compiler:def_word(alias, name, immediate)
  self.dict:def_word(alias, name, immediate)
end

function Compiler:exec_macro(word)
  local mod, fun = self.dict:find(word).lua_name:match("^(.-)%.(.+)$")
  if mod == "macros" and type(macros[fun]) == "function" then
    return macros[fun](self)
  else
    error("Unknown macro " .. word)
  end
end

function Compiler:add_ast_nodes(nodes, item)
  if #nodes > 0 then
    for i, each in ipairs(nodes) do
      each.forth_line_number = item.line_number
      table.insert(self.ast, each)
    end
  else
    nodes.forth_line_number = item.line_number
    table.insert(self.ast, nodes) -- single node
  end
end

function Compiler:compile_token(item)
  if item.kind == "symbol" then
    return ast.push(ast.literal("string", item.token:sub(2)))
  end
  if item.kind == "number" then
    return ast.push(ast.literal(item.kind, tonumber(item.token)))
  end
  if item.kind == "string" then
    return ast.push(ast.literal(item.kind, item.token:sub(2, -2)))
  end
  if item.kind == "word" then
    local word = self.dict:find(item.token)
    if word and word.immediate then
      return self:exec_macro(item.token)
    end
    if word and word.is_lua_alias then
      local res = interop.parse_signature(word.lua_name)
      if res then -- lua alias
        return self:lua_call(res.name, res.arity, res.void)
      else        -- normal alias
        return ast.func_call(word.lua_name)
      end
    end
    if self.env:has_var(item.token) then -- Forth variable
      return ast.push(ast.identifier(item.token))
    end
    if word then -- Regular Forth word
      return ast.func_call(word.lua_name)
    end
    if interop.is_lua_prop_lookup(item.token) then
      -- Lua/Forth table lookup like: math.pi or tbl.key
      local tbl = interop.table_name(item.token)
      if self.env:has_var(tbl) or
         interop.resolve_lua_obj(item.token)
      then
        return ast.push(ast.identifier(item.token))
      else
        error("Unkown variable: " .. tbl .. " at: " .. item.token)
      end
    end
    local res = interop.parse_signature(item.token)
    if res then
      -- Lua call with spec. signature such as math.pow/2 or io.write~
      return self:lua_call(res.name, res.arity, res.void)
    end
    if interop.resolve_lua_obj(item.token) then
      -- Lua globals from _G, such as math, table, io
      return ast.push(ast.identifier(item.token))
    end
  end
  error("Unknown token: " .. item.token .. " kind: " .. item.kind)
end

function Compiler:compile(text)
  self:init(text)
  local item = self.parser:next_item()
  while item do
    local node = self:compile_token(item)
    if node then self:add_ast_nodes(node, item) end
    item = self.parser:next_item()
  end
  self.ast = self.optimizer:optimize_iteratively(self.ast)
  return self:generate_code()
end

function Compiler:generate_code()
  for i, ast in ipairs(self.ast) do
    local code = self.codegen:gen(ast)
    if ast.forth_line_number then
      self.line_mapping:set_target_source(
        ast.forth_line_number,
        self.output.line_number)
    end
    self.output:append(code)
    self.output:new_line()
  end
  return self.output
end

function Compiler:error_handler(err)
  local info = debug.getinfo(3, "lS")
  if info and info.source ~= self.chunk_name then
    info = debug.getinfo(4, "lS") -- if it was error/1
  end
  if info then
    local src_line_num =
      self.line_mapping:resolve_target(info.currentline)
    if src_line_num then
      print(string.format(
              "Error occurred at line: %d", src_line_num))
      for i = src_line_num -2, src_line_num +2 do
        local line = self.parser.lines[i]
        if line then
          local mark = "  "
          if i == src_line_num then mark = "=>" end
          print(string.format("%s%03d.  %s", mark, i , line))
        end
      end
      print()
    end
    print(string.format("Original Error: %d", info.currentline))
    print(debug.traceback())
  end
  return err
end

function Compiler:eval(text, log_result)
  local code = self:compile_and_load(text, log_result)
  local success, result = xpcall(code, function() self:error_handler() end)
  if success then
    return result
  else
    error(err)
  end
end

function Compiler:compile_and_load(text, log_result)
  local out = self:compile(text)
  if log_result then
    io.write(self.output:text(self.code_start))
  end
  return out:load()
end

function Compiler:eval_file(path, log_result)
  local file = io.open(path, "r")
  if not file then
    error("Could not open file: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return self:eval(content, log_result)
end

return Compiler
end
end

do
local _ENV = _ENV
package.preload[ "dict" ] = function( ... ) local arg = _G.arg;
local interop = require("interop")

local Dict = {}

function Dict.new()
  local obj = {words = {}}
  setmetatable(obj, {__index = Dict})
  obj:init()
  return obj
end

local function entry(forth_name, lua_name, immediate, is_lua_alias)
  return {
    forth_name = forth_name,
    lua_name = lua_name,
    immediate = immediate,
    is_lua_alias = is_lua_alias
  }
end

local function is_valid_lua_identifier(name)
  local keywords = {
      ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
      ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true,
      ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
      ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
      ["until"] = true, ["while"] = true }
  if keywords[name] then
      return false
  end
  return name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") ~= nil
end

function Dict:def_word(forth_name, lua_name, immediate)
  table.insert(self.words, entry(forth_name, lua_name, immediate, false))
end

function Dict:def_macro(forth_name, lua_name)
  self:def_word(forth_name, lua_name, true)
end

function Dict:def_lua_alias(lua_name, forth_name)
  table.insert(self.words, entry(forth_name, lua_name, immediate, true))
end

function Dict:find(forth_name)
  for i = #self.words, 1, -1 do
    local each = self.words[i]
    if each.forth_name == forth_name then
      return each
    end
  end
  return nil
end

function Dict:word_list()
  local result, seen = {}, {}
  for i, each in ipairs(self.words) do
    if not seen[each.forth_name] then
      if interop.resolve_lua_func(each.lua_name) or
         each.immediate
      then
        table.insert(result, each.forth_name)
      end
      seen[each.forth_name] = true
    end
  end
  return result
end

function Dict:init()
  self:def_macro("+", "macros.add")
  self:def_macro("-", "macros.sub")
  self:def_macro("*", "macros.mul")
  self:def_macro("/", "macros.div")
  self:def_macro("%", "macros.mod")
  self:def_macro(".", "macros.dot")
  self:def_macro("cr", "macros.cr")
  self:def_macro("=", "macros.eq")
  self:def_macro("!=", "macros.neq")
  self:def_macro(">", "macros.lt")
  self:def_macro(">=", "macros.lte")
  self:def_macro("<", "macros.gt")
  self:def_macro("<=", "macros.gte")
  self:def_macro("swap", "macros.swap")
  self:def_macro("over", "macros.over")
  self:def_macro("rot", "macros.rot")
  self:def_macro("-rot", "macros.mrot")
  self:def_macro("nip", "macros.nip")
  self:def_macro("drop", "macros.drop")
  self:def_macro("dup", "macros.dup")
  self:def_macro("2dup", "macros.dup2")
  self:def_macro("tuck", "macros.tuck")
  self:def_macro("depth", "macros.depth")
  self:def_macro("pick", "macros.pick")
  self:def_macro("adepth", "macros.adepth")
  self:def_macro("not", "macros._not")
  self:def_macro("and", "macros._and")
  self:def_macro("or", "macros._or")
  self:def_macro("..", "macros.concat")
  self:def_macro(">a", "macros.to_aux")
  self:def_macro("a>", "macros.from_aux")
  self:def_macro("{}", "macros.new_table")
  self:def_macro("[]", "macros.new_table")
  self:def_macro("size", "macros.table_size")
  self:def_macro("at", "macros.table_at")
  self:def_macro("@", "macros.table_at")
  self:def_macro("put", "macros.table_put")
  self:def_macro("!", "macros.table_put")
  self:def_macro("words", "macros.words")
  self:def_macro("exit", "macros._exit")
  self:def_macro("return", "macros.ret")
  self:def_macro("if", "macros._if")
  self:def_macro("then", "macros._then")
  self:def_macro("else", "macros._else")
  self:def_macro("begin", "macros._begin")
  self:def_macro("until", "macros._until")
  self:def_macro("while", "macros._while")
  self:def_macro("repeat", "macros._end")
  self:def_macro("again", "macros._end")
  self:def_macro("case", "macros._case")
  self:def_macro("of", "macros._of")
  self:def_macro("endof", "macros._endof")
  self:def_macro("endcase", "macros._endcase")
  self:def_macro("do", "macros._do")
  self:def_macro("loop", "macros._loop")
  self:def_macro("ipairs:", "macros.for_ipairs")
  self:def_macro("pairs:", "macros.for_pairs")
  self:def_macro("to:", "macros._to")
  self:def_macro("step:", "macros._step")
  self:def_macro("->", "macros.assignment")
  self:def_macro("var", "macros.var")
  self:def_macro("(", "macros.comment")
  self:def_macro("\\", "macros.single_line_comment")
  self:def_macro("alias:", "macros.def_alias")
  self:def_macro(":", "macros.colon")
  self:def_macro("::", "macros.local_colon")
  self:def_macro(";", "macros.end_word")
  self:def_macro("exec", "macros.exec")
  self:def_macro("'", "macros.tick")
  self:def_macro("$", "macros.keyval")
  self:def_macro("(:", "macros.formal_params")
  self:def_macro("block", "macros.block")
  self:def_macro("end", "macros._end")
end

return Dict
end
end

do
local _ENV = _ENV
package.preload[ "env" ] = function( ... ) local arg = _G.arg;
local Env = {}

function Env.new(parent, name)
  local obj = {parent = parent,
               name = name,
               vars = {}}
  setmetatable(obj, {__index = Env})
  return obj
end

local function is_valid_lua_identifier(name)
  local keywords = {
      ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
      ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true,
      ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
      ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
      ["until"] = true, ["while"] = true }
  if keywords[name] then
    return false
  end
  return name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") ~= nil
end

function Env:def_var_unsafe(forth_name, lua_name)
  table.insert(self.vars, {forth_name = forth_name,
                           lua_name = lua_name})
end

function Env:def_var(name)
  if is_valid_lua_identifier(name) then
    self:def_var_unsafe(name, name)
  else
    error(name .. " is not a valid variable name. Avoid reserved keywords and special characters.")
  end
end

function Env:has_var(forth_name)
  for i, each in ipairs(self.vars) do
    if each.forth_name == forth_name then
      return true
    end
  end
  return self.parent and self.parent:has_var(forth_name)
end

return Env
end
end

do
local _ENV = _ENV
package.preload[ "interop" ] = function( ... ) local arg = _G.arg;
local interop = {}

function interop.resolve_lua_obj(name)
  local obj = _G
  for part in name:gmatch("[^%.]+") do
    obj = obj[part]
    if obj == nil then return nil end
  end
  return obj
end

function interop.resolve_lua_func(name)
  local obj = interop.resolve_lua_obj(name)
  if obj and type(obj) == "function" then
    return obj
  else
    return nil
  end
end

local function parse_arity(arity)
  if arity and #arity > 0 then
    return tonumber(arity)
  else
    return 0
  end
end

function interop.table_name(token)
  return string.match(token, "^[^.]+")
end

function interop.parse_signature(signature)
  local name, arity = string.match(signature, "([^%/]+)%/(%d*)")
  if name then
    return {name=name, arity=parse_arity(arity), void=false}
  end
  local name, arity = string.match(signature, "([^%/]+)%~(%d*)")
  if name then
    return {name=name, arity=parse_arity(arity), void=true}
  end
  return nil
end

function interop.is_lua_prop_lookup(token)
  return string.match(token, ".+%..+") and
    not string.match(token, "([/~]%d*)$")
end

return interop
end
end

do
local _ENV = _ENV
package.preload[ "line_mapping" ] = function( ... ) local arg = _G.arg;
local LineMapping = {}

function LineMapping.new(name)
  local obj = {
    name = name,
    target_source = {},
  }
  setmetatable(obj, {__index = LineMapping})
  return obj
end

function LineMapping:set_target_source(source_line_num, target_line_num)
  self.target_source[target_line_num] = source_line_num
end

function LineMapping:resolve_target(target_line_num)
  return self.target_source[target_line_num]
end


return LineMapping
end
end

do
local _ENV = _ENV
package.preload[ "macros" ] = function( ... ) local arg = _G.arg;
local stack = require("stack")
local aux = require("aux")
local interop = require("interop")
local ast = require("ast")

local macros = {}
local sequence = 1

local function sanitize(str)
  str = str:gsub("-", "_mi_")
    :gsub("%+", "_pu_")
    :gsub("%%", "_pe_")
    :gsub("/", "_fs_")
    :gsub("\\", "_bs_")
    :gsub("~", "_ti_")
    :gsub("#", "_hs_")
    :gsub("%*", "_sr_")
    :gsub(";", "_sc_")
    :gsub("&", "_an_")
    :gsub("|", "_or_")
    :gsub("@", "_at_")
    :gsub("`", "_bt_")
    :gsub("=", "_eq_")
    :gsub("'", "_sq_")
    :gsub('"', "_dq_")
    :gsub("?", "_qe_")
    :gsub("!", "_ex_")
    :gsub(",", "_ca_")
    :gsub(":", "_cm_")
    :gsub("%{", "_c1_")
    :gsub("%}", "_c2_")
    :gsub("%[", "_b1_")
    :gsub("%]", "_b2_")
    :gsub("%(", "_p1_")
    :gsub("%(", "_p2_")
  if str:match("^%d+") then
    str = "_" .. str
  end
  if str:match("^%.") then
    str = "dot_" .. str:sub(2)
  end
  return str
end

function macros.add()
  return ast.push(ast.bin_op("+", ast.pop(), ast.pop()))
end

function macros.mul()
  return ast.push(ast.bin_op("*", ast.pop(), ast.pop()))
end

function macros.sub()
  return ast.push(ast.bin_op("-", ast.pop2nd(), ast.pop()))
end

function macros.div()
  return ast.push(ast.bin_op("/", ast.pop2nd(), ast.pop()))
end

function macros.mod()
  return ast.push(ast.bin_op("%", ast.pop2nd(), ast.pop()))
end

function macros.eq()
  return ast.push(ast.bin_op("==", ast.pop(), ast.pop()))
end

function macros.neq()
  return ast.push(ast.bin_op("~=", ast.pop(), ast.pop()))
end

function macros.lt()
  return ast.push(ast.bin_op(">", ast.pop2nd(), ast.pop()))
end

function macros.lte()
  return ast.push(ast.bin_op(">=", ast.pop2nd(), ast.pop()))
end

function macros.gt()
  return ast.push(ast.bin_op("<", ast.pop2nd(), ast.pop()))
end

function macros.gte()
  return ast.push(ast.bin_op("<=", ast.pop2nd(), ast.pop()))
end

function macros._not()
  return ast.push(ast.unary_op("not", ast.pop()))
end

function macros._and()
  return ast.stack_op("_and")
end

function macros._or()
  return ast.stack_op("_or")
end

function macros.concat()
  return ast.push(ast.bin_op("..", ast.pop2nd(), ast.pop()))
end

function macros.new_table()
  return ast.new_table()
end

function macros.table_size()
  return ast.push(ast.unary_op("#", ast.pop()))
end

function macros.table_at()
  return ast.push(ast.table_at(ast.pop2nd(), ast.pop()))
end

function macros.table_put()
  return ast.table_put(ast.pop3rd(), ast.pop2nd(), ast.pop())
end

function macros.depth()
  return ast.push(ast.stack_op("depth"))
end

function macros.adepth()
  return ast.push(ast.aux_op("depth"))
end

function macros.dup()
  return ast.stack_op("dup")
end

function macros.drop()
  return ast.pop()
end

function macros.over()
  return ast.stack_op("over")
end

function macros.nip()
  return ast.stack_op("nip")
end

function macros.dup2()
  return ast.stack_op("dup2")
end

function macros.mrot()
  return ast.stack_op("mrot")
end

function macros.tuck()
  return ast.stack_op("tuck")
end

function macros.rot()
  return ast.stack_op("rot")
end

function macros.swap()
  return ast.stack_op("swap")
end

function macros.to_aux()
  return ast.aux_push(ast.pop())
end

function macros.from_aux()
  return ast.push(ast.aux_op("pop"))
end

function macros.pick()
  return ast.push(ast.func_call("stack:at", ast.pop()))
end

function macros.dot()
  return {
    ast.func_call("io.write", ast.func_call("tostring", ast.pop())),
    ast.func_call("io.write", ast.str(" "))
  }
end

function macros.cr()
  return ast.func_call("print")
end

function macros.def_alias(compiler)
  local lua_name = compiler:word()
  forth_alias = compiler:word()
  compiler:alias(lua_name, forth_alias)
end

local function def_word(compiler, is_global)
  compiler:new_env()
  local forth_name = compiler:word()
  local lua_name = sanitize(forth_name)
  if compiler:find(forth_name) then
    lua_name = lua_name .. "__s" .. sequence
  end
  sequence = sequence + 1
  compiler:def_word(forth_name, lua_name, false)
  local header = ast.func_header(lua_name, is_global)
  stack:push(header)
  return header
end

function macros.colon(compiler)
  return def_word(compiler, true)
end

function macros.local_colon(compiler)
  return def_word(compiler, false)
end

function macros.tick(compiler)
  local name = compiler:word()
  local word = compiler:find(name)
  if not word then
    error(name .. " is not found in dictionary")
  elseif word.immediate then
    error("' cannot be used on a macro: " .. name)
  end
  return ast.push(ast.identifier(word.lua_name))
end

function macros.exec(compiler)
  return ast.func_call("stack:pop()")
end

function macros.ret(compiler)
  return ast._return(ast.pop())
end

function macros.comment(compiler)
  repeat until ")" == compiler:next_chr()
end

function macros.single_line_comment(compiler)
  local ch
  repeat
    ch = compiler:next_chr()
  until "\n" == ch or "\r" == ch
  if ch == "\r" and compiler:peek_chr() == "\n" then
    compiler:next_chr()
  end
end

function macros.var(compiler)
  local name = compiler:word()
  compiler:def_var(name)
  return ast.def_local(name)
end

local function valid_tbl_assignment(compiler, name)
  if interop.is_lua_prop_lookup(name) then
    local tbl = interop.table_name(name)
    return compiler:has_var(tbl)
      or interop.resolve_lua_obj(name)
  end
  return false
end

function macros.assignment(compiler)
  local name = compiler:word()
  if name == "var" then
    -- declare and assign of a new var
    name = compiler:word()
    compiler:def_var(name)
    return ast.init_local(name, ast.pop())
  else
    -- assignment of existing var
    if compiler:has_var(name) or
       valid_tbl_assignment(compiler, name) -- 123 -> tbl.x
    then
      return ast.assignment(name, ast.pop())
    else
      error("Undeclared variable: " .. name)
    end
  end
end

function macros._if()
  return ast._if(ast.pop())
end

function macros._else()
  return ast.keyword("else")
end

function macros._begin(compiler)
  -- begin..until / begin..again / begin..while..repeat
  compiler:new_env('BEGIN_LOOP')
  return ast._while(ast.literal("boolean", "true"))
end

function macros._until(compiler)
  compiler:remove_env('BEGIN_LOOP')
  return {
    ast._if(ast.pop(), ast.keyword("break")),
    ast.keyword("end")
  }
end

function macros.block(compiler)
  compiler:new_env('BLOCK')
  return ast.keyword("do")
end

function macros._while()
  return ast._if(ast.unary_op("not", ast.pop()), ast.keyword("break"))
end

function macros._case() -- simulate goto with break, in pre lua5.2 since GOTO was not yet supported
  return ast.keyword("repeat")
end

function macros._of()
  return {
    ast.stack_op("over"),
    ast._if(ast.bin_op("==", ast.pop(), ast.pop())),
    ast.pop() -- drop selector
  }
end

function macros._endof() -- GOTO endcase
  return { ast.keyword("break"), ast.keyword("end") }
end

function macros._endcase()
  return ast._until(ast.literal("boolean", "true"))
end

function macros._exit()
  return ast._return(nil) -- exit from Forth word
end

local do_loop_nesting = 0
local do_loop_vars = {"i", "j", "k"}

function macros._do(compiler)
  do_loop_nesting = do_loop_nesting + 1
  local loop_var = do_loop_vars[((do_loop_nesting -1) % #do_loop_vars) +1]
  compiler:new_env('DO_LOOP')
  compiler:def_var(loop_var)
  return ast._for(
      loop_var,
      ast.pop(),
      ast.bin_op("-", ast.pop(), ast.literal("number", 1)),
      nil)
end

function macros._loop(compiler)
  compiler:remove_env('DO_LOOP')
  do_loop_nesting = do_loop_nesting - 1
  return ast.keyword("end")
end

function macros.for_ipairs(compiler)
  local var_name1 = compiler:word()
  local var_name2 = compiler:word()
  compiler:new_env('IPAIRS_LOOP')
  compiler:def_var(var_name1)
  compiler:def_var(var_name2)
  return ast._foreach(var_name1, var_name2, ast._ipairs(ast.pop()))
end

function macros.for_pairs(compiler)
  local var_name1 = compiler:word()
  local var_name2 = compiler:word()
  compiler:new_env('PAIRS_LOOP')
  compiler:def_var(var_name1)
  compiler:def_var(var_name2)
  return ast._foreach(var_name1, var_name2, ast._pairs(ast.pop()))
end

function macros._to(compiler)
  local loop_var = compiler:word()
  compiler:new_env('TO_LOOP')
  compiler:def_var(loop_var)
  return ast._for(loop_var, ast.pop2nd(), ast.pop(), nil)
end

function macros._step(compiler)
  local loop_var = compiler:word()
  compiler:new_env('STEP_LOOP')
  compiler:def_var(loop_var)
  return ast._for(loop_var, ast.pop3rd(), ast.pop2nd(), ast.pop(), nil)
end

function macros._then(compiler)
  return ast.keyword("end")
end

function macros._end(compiler)
  compiler:remove_env()
  return ast.keyword("end")
end

function macros.end_word(compiler)
  if stack:depth() == 0 or
     stack:tos().name ~= "func_header"
  then
    error("Unexpected semicolon") -- TODO line num
  end
  stack:pop()
  return macros._end(compiler)
end

function macros.keyval(compiler)
  local name = compiler:word()
  return {
    ast.push(ast.str(name)),
    ast.push(ast.identifier(name))
  }
end

function macros.formal_params(compiler)
  if stack:depth() == 0 or
     stack:tos().name ~= "func_header"
  then
    error("Unexpected (:") -- TODO line num
  end
  local func_header = stack:tos()
  local param_name = compiler:word()
  while param_name ~= ":)" do
    compiler:def_var(param_name)
    table.insert(func_header.params, param_name)
    param_name = compiler:word()
  end
  return result
end

function macros.words(compiler)
  for i, each in ipairs(compiler:word_list()) do
    io.write(each .. " ")
  end
  print()
end

return macros
end
end

do
local _ENV = _ENV
package.preload[ "output" ] = function( ... ) local arg = _G.arg;
local Output = {}

function Output.new(name)
  local obj = {lines = {""}, line_number = 1, name = name}
  setmetatable(obj, {__index = Output})
  return obj
end

function Output:append(str)
  self.lines[self:size()] = self.lines[self:size()] .. str
end

function Output:new_line()
  self.line_number = self.line_number +1
  table.insert(self.lines, "")
end

function Output:size()
  return #self.lines
end

function Output:text(from)
  return table.concat(self.lines, "\n", from)
end

function Output:load()
  local text = self:text()
  if loadstring then
    return loadstring(text, self.name)
  else -- Since Lua 5.2, loadstring has been replaced by load.
    return load(text, self.name)
  end
end

return Output
end
end

do
local _ENV = _ENV
package.preload[ "parser" ] = function( ... ) local arg = _G.arg;
local interop = require("interop")

local Parser = {}

local function lines_of(input)
  local lines = {}
  for line in input:gmatch("([^\r\n]*)\r?\n?") do
    table.insert(lines, line)
  end
  return lines
end

function Parser.new(source)
  local obj = {index = 1,
               line_number = 1,
               source = source,
               lines = lines_of(source)}
  setmetatable(obj, {__index = Parser})
  return obj
end

function Parser:parse_all()
  local result = {}
  local item = self:next_item()
  while item do
    table.insert(result, item)
    item = self:next_item()
  end
  return result
end

local function is_quote(chr)
  return chr:match('"')
end

local function is_escape(chr)
  return chr:match("\\")
end

local function is_whitespace(chr)
  return chr:match("%s")
end

function Parser:next_item()
  local token = ""
  local begin_str = false
  local stop = false
  local kind = "word"
  while not self:ended() and not stop do
    local chr = self:read_chr()
    if is_quote(chr) then
      if begin_str then
        stop = true
      else
        kind = "string"
        begin_str = true
      end
      token = token .. chr
    elseif begin_str
      and is_escape(chr)
      and is_quote(self:peek_chr()) then
      token = token .. chr .. self:read_chr() -- consume \"
    elseif begin_str and ("\r" == chr or "\n" == chr) then
      error(string.format(
           "Unterminated string: %s at line: %d", token, self.line_number))
    elseif is_whitespace(chr) and not begin_str then
      if #token > 0 then
        self.index = self.index -1 -- don't consume next WS as it breaks single line comment
        stop = true
      else
        self:update_line_number(chr)
      end
    else
      token = token .. chr
    end
  end
  if token == "" then
    return nil -- EOF
  end
  if token:match("^$.+") then kind = "symbol" end
  if tonumber(token) then kind = "number" end
  return {token=token, kind=kind, line_number=self.line_number}
end

function Parser:update_line_number(chr)
  if chr == '\r' then
    if self:peek_chr() == '\n' then self:read_chr() end
    self.line_number = self.line_number +1
  elseif chr == '\n' then
    self.line_number = self.line_number +1
  end
end

function Parser:next_chr()
  local chr = self:read_chr()
  self:update_line_number(chr)
  return chr
end

function Parser:read_chr()
  local chr = self:peek_chr()
  self.index = self.index + 1
  return chr
end

function Parser:peek_chr()
  return self.source:sub(self.index, self.index)
end

function Parser:ended()
  return self.index > #self.source
end

return Parser
end
end

do
local _ENV = _ENV
package.preload[ "repl" ] = function( ... ) local arg = _G.arg;
local stack = require("stack")

local SINGLE_LINE = 1
local MULTI_LINE = 2

local Repl = {}

local repl_ext = "repl_ext.eqx"

local function file_exists(filename)
  local file = io.open(filename, "r")
  if file then file:close() return true
  else return false end
end

local function extension(filename)
  return filename:match("^.+(%.[^%.]+)$")
end

function Repl.new(compiler, optimizer)
  local obj = {compiler = compiler,
               optimizer = optimizer,
               mode = SINGLE_LINE,
               always_show_stack = false,
               repl_ext_loaded = false,
               input = "",
               log_result = false }
  setmetatable(obj, {__index = Repl})
  return obj
end

local messages = {
  "The Prime Directive: Preserve Stack Integrity at All Costs.",
  "Engage warp speed and may your stack never overflow.",
  "Welcome Commander. The stack is ready for your orders.",
  "Our mission is to explore new words and seek out new stack operations.",
  "Welcome, Officer. May your debugging skills be as sharp as a phaser.",
  "Your mission is to PUSH the boundaries of programming.",
  "In the Delta Quadrant every stack operation is a new discovery.",
  "One wrong stack move and your program could warp into an infinite loop.",
  "Take responsibility for your code as errors will affect the entire fleet.",
  "Picard's programming tip: Complexity can be a form of the enemy.",
  "Spock's programming tip: Logic is the foundation of all good code.",
  "Spock's programming tip: Do not let emotion cloud your debugging.",
  "Worf's programming tip: A true programmer fights for correctness.",
  "Worf's programming tip: When facing a bug, fire your phasers at full power.",
  "One misplaced DROP can send your code into warp core breach.",
  "To reach warp speed, the code must be optimized for maximum efficiency.",
  "Working in Forth sometimes feels like working in a Jeffries tube.",
  "A balanced stack is a stable warp core. Keep it well protected.",
  "All systems are stable, commander. Stack integrity is 100%.",
  "Captain, the stack is clear and ready for warp.",
  "Deflector shields holding steady captain, the stack is well protected."
}

math.randomseed(os.time())

function Repl:welcome(version)
  print("Equinox Forth Console (" .. _VERSION .. ") @ Delta Quadrant.")
  print(messages[math.random(1, #messages)])
  print("\27[1;96m")
  print(string.format([[
 ___________________          _-_
 \__(==========/_=_/ ____.---'---`---.____
             \_ \    \----._________.----/
               \ \   /  /    `-_-'
          ___,--`.`-'..'-_
         /____          (|
               `--.____,-'   v%s
]], version))
  print("\27[0m")
  print("Type 'words' for wordlist, 'bye' to exit or 'help'.")
  print("First time Forth user? Type: load-file tutorial")
end

local function show_help()
  print([[
- log-on "turn on logging"
- log-off "turn off logging"
- opt-on "turn on optimization"
- opt-off "turn off optimization"
- load-file <path> "load an eqx file"
- stack-on "always show stack after each input"
- stack-off "don't show stack after each input"
- bye "exit repl"
- help "show this help"
  ]])
end

function Repl:prompt()
  if self.mode == SINGLE_LINE then
    return "#"
  else
    return "..."
  end
end

function Repl:show_prompt()
  io.write(string.format("\27[1;95m%s \27[0m", self:prompt()))
end

function Repl:read()
  if self.mode == SINGLE_LINE then
    self.input = io.read()
  else
    self.input = self.input .. "\n" .. io.read()
  end
end

local function trim(str)
  return str:match("^%s*(.-)%s*$")
end

function Repl:process_commands()
  local command = trim(self.input)
  if command == "bye" then
    os.exit(0)
  end
  if command == "help" then
    show_help()
    return true
  end
  if command == "log-on" then
    self.log_result = true
    print("Log turned on")
    return true
  end
  if command == "log-off" then
    self.log_result = false
    print("Log turned off")
    return true
  end
  if command == "stack-on" then
    if self.repl_ext_loaded then
      self.always_show_stack = true
      print("Show stack after input is on")
    else
      print("Requires " .. repl_ext)
    end
    return true
  end
  if command == "stack-off" then
    self.always_show_stack = off
    print("Show stack after input is off")
    return true
  end
  if command == "opt-on" then
    self.optimizer:enable(true)
    print("Optimization turned on")
    return true
  end
  if command == "opt-off" then
    self.optimizer:enable(false)
    print("Optimization turned off")
    return true
  end
  local path = command:match("load%-file%s+(.+)")
  if path then
    if not file_exists(path) and not extension(path) then
      path = path .. ".eqx"
    end
    if file_exists(path) then
      self:safe_call(function() self.compiler:eval_file(path) end)
    else
      print("File does not exist: " .. path)
    end
    return true
  end
  return false
end

function Repl:print_err(result)
  print("\27[91m" .. "Red Alert: " .. "\27[0m" .. result)
end

function Repl:print_ok()
  if stack:depth() > 0 then
    print("\27[92m" .. "OK(".. stack:depth()  .. ")" .. "\27[0m")
    if self.always_show_stack and self.repl_ext_loaded then
      self.compiler:eval(".s")
    end
  else
    print("\27[92mOK\27[0m")
  end
end

function Repl:safe_call(func)
  local success, result = pcall(func)
  if success then
    self:print_ok()
  else
    self:print_err(result)
  end
end

function Repl:start()
  if file_exists(repl_ext) then
    self.compiler:eval_file(repl_ext)
    self.repl_ext_loaded = true
  end
  local prompt = "#"
  while true do
    self:show_prompt()
    self:read()
    if not self:process_commands() then
      local success, result = pcall(function ()
          return self.compiler:compile_and_load(self.input, self.log_result)
      end)
      if not success then
        self:print_err(result)
      elseif not result then
        self.mode = MULTI_LINE
      else
        self.mode = SINGLE_LINE
        self:safe_call(function() result() end)
      end
    end
  end
end

return Repl
end
end

do
local _ENV = _ENV
package.preload[ "stack" ] = function( ... ) local arg = _G.arg;
local Stack = require("stack_def")
local stack = Stack.new("data-stack")

return stack
end
end

do
local _ENV = _ENV
package.preload[ "stack_def" ] = function( ... ) local arg = _G.arg;
local Stack = {}
local NIL = {} -- nil cannot be stored in table, use this placeholder

function Stack.new(name)
  local obj = {stack = {nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil},
               name = name}
  setmetatable(obj, {__index = Stack})
  return obj
end

function Stack:push(e)
  if e ~= nil then
    self.stack[#self.stack + 1] = e
  else
    self.stack[#self.stack + 1] = NIL
  end
end

function Stack:push_many(...)
  local args = {...}
  local stack = self.stack
  local n = #stack
  for i = 1, #args do
    if args[i] ~= nil then
      stack[n + i] = args[i]
    else
      stack[n + i] = NIL
    end
  end
end

function Stack:pop()
  local stack = self.stack
  local size = #stack
  if size == 0 then
    error("Stack underflow: " .. self.name)
  end
  local item = stack[size]
  stack[size] = nil
  if item ~= NIL then return item else return nil end
end

function Stack:pop2nd()
  local stack = self.stack
  local n = #stack
  if n < 2 then
    error("Stack underflow: " .. self.name)
  end
  local item = stack[n - 1]
  stack[n -1] = stack[n]
  stack[n] = nil
  if item ~= NIL then return item else return nil end
end

function Stack:pop3rd()
  local n = #self.stack
  if n < 3 then
    error("Stack underflow: " .. self.name)
  end
  local item = table.remove(self.stack, n - 2)
  if item ~= NIL then return item else return nil end
end

function Stack:swap()
  local stack = self.stack
  local n = #stack
  if n < 2 then
    error("Stack underflow: " .. self.name)
  end
  stack[n], stack[n - 1] = stack[n - 1], stack[n]
end

function Stack:rot()
  local stack = self.stack
  local n = #stack
  if n < 3 then
    error("Stack underflow: " .. self.name)
  end
  local new_top = stack[n -2]
  table.remove(stack, n - 2)
  stack[n] = new_top
end

function Stack:mrot()
  local stack = self.stack
  local n = #stack
  if n < 3 then
    error("Stack underflow: " .. self.name)
  end
  local temp = stack[n]
  stack[n] = nil
  table.insert(stack, n - 2, temp)
end

function Stack:over()
  local stack = self.stack
  local n = #stack
  if n < 2 then
    error("Stack underflow: " .. self.name)
  end
  stack[n + 1] = stack[n - 1]
end

function Stack:tuck()
  local n = #self.stack
  if n < 2 then
    error("Stack underflow: " .. self.name)
  end
  table.insert(self.stack, n - 1, self.stack[n])
end

function Stack:nip()
  local stack = self.stack
  local n = #stack
  if n < 2 then
    error("Stack underflow: " .. self.name)
  end
  stack[n - 1] = stack[n]
  stack[n] = nil
end

function Stack:dup()
  local stack = self.stack
  local n = #stack
  if n < 1 then
    error("Stack underflow: " .. self.name)
  end
  stack[n + 1] = stack[n]
end

function Stack:dup2()
  local stack = self.stack
  local n = #stack
  if n < 2 then
    error("Stack underflow: " .. self.name)
  end
  local tos1 = stack[n]
  local tos2 = stack[n - 1]
  stack[n + 1] = tos2
  stack[n + 2] = tos1
end

function Stack:tos()
  local item = self.stack[#self.stack]
  if item == nil then
    error("Stack underflow: " .. self.name)
  end
  if item ~= NIL then return item else return nil end
end

function Stack:tos2()
  local item = self.stack[#self.stack - 1]
  if item == nil then
    error("Stack underflow: " .. self.name)
  end
  if item ~= NIL then return item else return nil end
end

function Stack:_and()
  local a, b = self:pop(), self:pop()
  self:push(a and b)
end

function Stack:_or()
  local a, b = self:pop(), self:pop()
  self:push(a or b)
end

function Stack:depth()
  return #self.stack
end

function Stack:at(index)
  local item = self.stack[#self.stack - index]
  if item == nil then
    error("Stack underflow: " .. self.name)
  end
  if item ~= NIL then return item else return nil end
end

return Stack
end
end

__VERSION__="0.0.1621"

local Compiler = require("compiler")
local Optimizer = require("ast_optimizer")
local CodeGen = require("codegen")
local Repl = require("repl")

local equinox = {}
local optimizer = Optimizer.new()
local compiler = Compiler.new(optimizer, CodeGen.new())
local repl = Repl.new(compiler, optimizer)

local lua_require = require

function require(module_name)
  if module_name:lower():match("%.eqx$") then
    return equinox.eval_file(module_name, false)
  else
    return lua_require(module_name)
  end
end

local lib = [[
alias: table.insert~2 append
alias: table.insert~3 insert
alias: table.remove~2 remove
alias: tostring/1 >str
alias: require/1 need

: assert-true assert~1 ;
: assert-false not assert-true ;
: =assert = assert-true ;

: [ depth >a ;
: ]
  []
  depth a> - 1 - 0
  do
    dup >a
    1 rot insert ( tbl idx value )
    a>
  loop ;

: { depth >a ;
: }
    {}
    depth a> - 1 -
    dup 2 % 0 != if
      "Table needs even number of items" error/1
    then
    2 / 0 do
      dup >a -rot put a>
    loop ;
]]

local function version()
  if __VERSION__ then
    return __VERSION__
  else
    version = require("version/version")
    version.load()
    return version.current
  end
end

local function start_repl()
  repl:welcome(version())
  repl:start()
end

function equinox.eval_files(files, log_result)
  local result = nil
  for i, filename in ipairs(files) do
    if log_result then
      print("Loading " .. filename)
    end
    result = equinox.eval_file(filename, log_result)
  end
  return result
end

function equinox.init()
  compiler:eval(lib)
end

function equinox.main()
  if #arg < 1 then
    equinox.init()
    start_repl()
  else
    local log_result, repl = false, false
    local files = {}
    for i, param in ipairs(arg) do
      if param == "-d" then
        log_result = true
      elseif param == "-o0" then
        optimizer:enable(false)
      elseif param == "-o1" then
        optimizer:enable(true)
      elseif param == "-od" then
        optimizer:enable_logging(true)
      elseif param == "-repl" then
        repl = true
      else
        table.insert(files, param)
      end
    end
    equinox.init()
    equinox.eval_files(files, log_result)
    if repl then start_repl() end
  end
end

function equinox.eval(str, log_result)
  return compiler:eval(str, log_result)
end

function equinox.eval_file(str, log_result)
  return compiler:eval_file(str, log_result)
end

if arg and arg[0] and
  (arg[0]:match("equinox.lua$") or
   arg[0]:match("equinox_bundle.lua$")) then
  equinox.main(arg)
end

return equinox
