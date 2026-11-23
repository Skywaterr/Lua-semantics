// Lua 5.1.5 semantics in K. See ROADMAP.md for the milestone plan.
//
// Module layout:
//   LUA-COMMON  the abstract grammar. Token sorts (Name, Numeral, LString)
//               are declared without lexical syntax, so rules in LUA can
//               mention K String literals without clashing with Lua strings.
//   LUA-SYNTAX  the program parser: LUA-COMMON plus token regexes and layout.
//   LUA         the semantics.

module LUA-COMMON

  // ---------------------------------------------------------------- tokens
  syntax Name    [token]   // identifiers
  syntax Numeral [token]   // decimal, exponent and hex numbers, still undecoded
  syntax LString [token]   // short and long strings, quotes/brackets included

  // ---------------------------------------------------------------- blocks
  // chunk ::= {stat [';']} [laststat [';']]
  // `return` and `break` must end a block; keeping them out of Stmt is what
  // stops `return` followed by `f(x)` from being ambiguous.
  // A block may also open with a statement that begins with `(` (see Stmt):
  // nothing before it can absorb the parenthesis as call arguments.
  syntax Block ::= Stmts
                 | Stmts LastStmt
                 | PStmt Stmts
                 | PStmt Stmts LastStmt

  syntax Stmts ::= List{Stmt, ""}

  syntax LastStmt ::= "return" Exps
                    | "return" Exps ";"
                    | "break"
                    | "break" ";"

  // ------------------------------------------------------------ statements
  // A statement may begin with `(` only right after `;` or at the start of a
  // block (PStmt). Without that rule `f(a)(b)(c)` is ambiguous: one chained
  // call, or `f(a)` followed by the statement `(b)(c)`. Lua reads it as one
  // call on the same line and rejects the split across lines ("ambiguous
  // syntax"), so for valid programs the call reading is always right. Every
  // other statement begins with a name (NVar/NCall) or a keyword.
  // Known gap: valid Lua such as `do end (f)()`, where the previous statement
  // ends in a keyword, needs a `;` here: `do end ;(f)()`.
  syntax Stmt ::= ";"                                   // optional separator
                | ";" PStmt                             // `;(f)(x)`
                | NVar "=" NeExps                       // assignment
                | NVar "," Vars "=" NeExps              // multiple assignment
                | NCall
                | "do" Block "end"
                | "while" Exp "do" Block "end"
                | "repeat" Block "until" Exp
                | "if" Exp "then" Block ElseIfs "end"
                | "if" Exp "then" Block ElseIfs "else" Block "end"
                | "for" Name "=" Exp "," Exp "do" Block "end"
                | "for" Name "=" Exp "," Exp "," Exp "do" Block "end"
                | "for" Names "in" NeExps "do" Block "end"
                | "function" FuncName FuncBody
                | "local" "function" Name FuncBody
                | "local" Names
                | "local" Names "=" NeExps

  // Statements that begin with `(`: only at the start of a block or after `;`.
  syntax PStmt ::= PVar "=" NeExps
                 | PVar "," Vars "=" NeExps
                 | PCall

  syntax ElseIf  ::= "elseif" Exp "then" Block
  syntax ElseIfs ::= List{ElseIf, ""}

  // funcname ::= Name {'.' Name} [':' Name]
  syntax DottedName ::= Name
                      | DottedName "." Name
  syntax FuncName   ::= DottedName
                      | DottedName ":" Name

  // --------------------------------------------------------- lists
  // Assignment, `local` and generic `for` need a non-empty right-hand side,
  // otherwise `x = f(y)` could also read as `x =` followed by `f(y)`.
  syntax Vars   ::= NeList{Var, ","}
  syntax Names  ::= NeList{Name, ","}
  syntax Params ::= List{Name, ","}
  syntax Exps   ::= List{Exp, ","}
  syntax NeExps ::= NeList{Exp, ","}

  // ------------------------------------------------------------ functions
  syntax FunctionDef ::= "function" FuncBody
  syntax FuncBody    ::= "(" ParList ")" Block "end"
  syntax ParList     ::= Params
                       | Names "," "..."
                       | "..."

  // ------------------------------------------------------ prefix expressions
  // Only prefix expressions can be called or indexed, so `"s":rep(2)` and
  // `{}.x` are rejected while `("s"):rep(2)` is accepted. Parentheses are a
  // real node: `(f())` truncates f's results to one value.
  //
  // Each form comes in two families, split by the first token, so that
  // statements can require a name-led head (see Stmt above):
  //   N*  starts with a Name         a.b[c]:d(e)
  //   P*  starts with `(` Exp `)`    (a).b[c]:d(e)
  // The suffix productions are the same in both; the semantics handles each
  // pair with one rule per family delegating to a shared operation.
  syntax PrefixExp    ::= NPrefix | PPrefix
  syntax Var          ::= NVar | PVar
  syntax FunctionCall ::= NCall | PCall

  syntax NPrefix ::= NVar | NCall
  syntax NVar    ::= Name
                   | NPrefix "[" Exp "]"
                   | NPrefix "." Name
  syntax NCall   ::= NPrefix Args
                   | NPrefix ":" Name Args

  syntax PPrefix ::= "(" Exp ")"
                   | PVar | PCall
  syntax PVar    ::= PPrefix "[" Exp "]"
                   | PPrefix "." Name
  syntax PCall   ::= PPrefix Args
                   | PPrefix ":" Name Args

  syntax Args         ::= "(" Exps ")"
                        | TableCons
                        | LString

  // ---------------------------------------------------------- tables
  syntax TableCons ::= "{" "}"
                     | "{" FieldList "}"
  syntax FieldList ::= Field
                     | Field FieldSep
                     | Field FieldSep FieldList
  syntax FieldSep  ::= "," | ";"
  syntax Field     ::= "[" Exp "]" "=" Exp
                     | Name "=" Exp
                     | Exp

  // -------------------------------------------------------- expressions
  // Precedence, loosest last (Lua 5.1 manual section 2.5.6):
  //   or < and < comparisons < .. < + - < * / % < not # -(unary) < ^
  // `..` and `^` are right associative. The right operand of `^` may be a
  // unary expression (`2^-3`), handled by the extra productions below.
  syntax Exp ::= PrefixExp
               | "nil" | "true" | "false"
               | Numeral
               | LString
               | "..."
               | FunctionDef
               | TableCons
               > right:
                 Exp "^" Exp
               | Exp "^" "-" Exp
               | Exp "^" "not" Exp
               | Exp "^" "#" Exp
               > "not" Exp
               | "#" Exp
               | "-" Exp
               > left:
                 Exp "*" Exp
               | Exp "/" Exp
               | Exp "%" Exp
               > left:
                 Exp "+" Exp
               | Exp "-" Exp
               > right:
                 Exp ".." Exp
               > left:
                 Exp "<" Exp
               | Exp ">" Exp
               | Exp "<=" Exp
               | Exp ">=" Exp
               | Exp "~=" Exp
               | Exp "==" Exp
               > left:
                 Exp "and" Exp
               > left:
                 Exp "or" Exp

endmodule


module LUA-SYNTAX
  imports LUA-COMMON

  syntax Name    ::= r"[A-Za-z_][A-Za-z0-9_]*" [token]

  syntax Numeral ::= r"(0[xX][0-9a-fA-F]+)|(([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+\\-]?[0-9]+)?)" [token]

  // Short strings with any escape (decoded in the semantics), then long
  // strings [[...]], [=[...]=] ... [====[...]====]. Flex has no
  // backreferences, so each level is spelled out (generated by a script:
  // the content after each `]` must not complete the closing bracket).
  syntax LString ::= r"(\\\"([^\\\"\\\\\\n]|\\\\(.|\\n))*\\\")|('([^'\\\\\\n]|\\\\(.|\\n))*')|(\\[\\[[^\\]]*(\\][^\\]]+)*\\]\\])|(\\[=\\[[^\\]]*(\\](={0,1}[^=\\]][^\\]]*|={2}[^\\]]*)?)*\\]=\\])|(\\[==\\[[^\\]]*(\\](={0,1}|={0,2}[^=\\]][^\\]]*|={3}[^\\]]*))*\\]==\\])|(\\[===\\[[^\\]]*(\\](={0,2}|={0,3}[^=\\]][^\\]]*|={4}[^\\]]*))*\\]===\\])|(\\[====\\[[^\\]]*(\\](={0,3}|={0,4}[^=\\]][^\\]]*|={5}[^\\]]*))*\\]====\\])" [token]

  // Whitespace, line comments `-- ...` (not starting with a long bracket),
  // and long comments `--[[ ... ]]` up to level 4. K's regex reader has no
  // \f or \v escape (it reads them as the letters f and v), so form feed
  // and vertical tab are not treated as whitespace.
  syntax #Layout ::= r"([\\ \\n\\r\\t])|(--([^\\[\\n][^\\n]*)?)|(--\\[=*([^\\[=\\n][^\\n]*)?)|(--((\\[\\[[^\\]]*(\\][^\\]]+)*\\]\\])|(\\[=\\[[^\\]]*(\\](={0,1}[^=\\]][^\\]]*|={2}[^\\]]*)?)*\\]=\\])|(\\[==\\[[^\\]]*(\\](={0,1}|={0,2}[^=\\]][^\\]]*|={3}[^\\]]*))*\\]==\\])|(\\[===\\[[^\\]]*(\\](={0,2}|={0,3}[^=\\]][^\\]]*|={4}[^\\]]*))*\\]===\\])|(\\[====\\[[^\\]]*(\\](={0,3}|={0,4}[^=\\]][^\\]]*|={5}[^\\]]*))*\\]====\\])))"

endmodule


module LUA
  imports LUA-COMMON
  imports DOMAINS

  // ARGS holds the script name, which becomes arg[0] once tables exist (M4).
  // krun exits with the value of <exit-code>: it starts at 1 and becomes 0
  // only when the program runs to completion, so a stuck run is a failure.
  configuration
    <lua>
      <k> $PGM:Block </k>
      <args> $ARGS:String </args>
      <output stream="stdout"> .List </output>
      <exit-code exit=""> 1 </exit-code>
    </lua>

  rule <k> .K </k> <exit-code> 1 => 0 </exit-code>

  // Placeholder evaluation until M2: run statements in order, skip `;`.
  rule <k> S:Stmt Ss:Stmts => S ~> Ss ... </k>
  rule <k> .Stmts => .K ... </k>
  rule <k> (;):Stmt => .K ... </k>
endmodule
