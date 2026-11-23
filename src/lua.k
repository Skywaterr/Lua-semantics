// Lua 5.1.5 semantics in K. See ROADMAP.md for the milestone plan.

module LUA-SYNTAX
  imports STRING-SYNTAX

  // Whitespace and line comments. Long comments `--[[ ... ]]` arrive in M1.
  syntax #Layout ::= r"(--[^\\n\\r]*)|([\\ \\n\\r\\t])"

  // Placeholder statement until the full grammar lands in M1.
  syntax Stmt  ::= ";"
  syntax Block ::= List{Stmt, ""}
endmodule

module LUA
  imports LUA-SYNTAX
  imports DOMAINS

  // ARGS holds the script name, which becomes arg[0] once tables exist (M4).
  configuration
    <lua>
      <k> $PGM:Block </k>
      <args> $ARGS:String </args>
      <output stream="stdout"> .List </output>
    </lua>

  rule <k> S:Stmt Ss:Block => S ~> Ss ... </k>
  rule <k> .Block => .K ... </k>
  rule <k> ; => .K ... </k>
endmodule
