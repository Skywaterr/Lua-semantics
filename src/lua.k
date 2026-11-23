// Lua 5.1.5 semantics in K. See ROADMAP.md for the milestone plan.
//
// Files, each requiring the one before it:
//   lua-syntax.k   LUA-COMMON (abstract grammar), LUA-SYNTAX (program parser)
//   lua-values.k   LUA-VALUES   value sorts and small helpers
//   lua-number.k   LUA-NUMBER   %.14g formatting, string -> number
//   lua-literal.k  LUA-LITERAL  decoding numerals and string literals
//   lua-config.k   LUA-CONFIG   the configuration; tables, locals, output, errors
//   lua-eval.k     LUA-EVAL     expressions and statements
//   lua-function.k LUA-FUNCTION closures, calls, returns, varargs, generic for
//   lua-table.k    LUA-TABLE    constructors, next/pairs/ipairs, table library
//   lua-math.k     LUA-MATH     math library
//   lua-stdlib.k   LUA-STDLIB   the global table and library functions

requires "lua-stdlib.k"

module LUA
  imports LUA-STDLIB
endmodule
