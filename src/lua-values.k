// Lua values and small helpers shared by the rest of the semantics.

requires "lua-syntax.k"

module LUA-VALUES
  imports LUA-COMMON
  imports DOMAINS
  imports FLOAT

  // Every Lua 5.1 number is a double, so numbers are K Floats (53-bit
  // precision, 11 exponent bits). Strings are K Strings whose characters are
  // all in 0..255, one per Lua byte (see scripts/klua).
  syntax Val  ::= Nil | Bool | Float | String | TRef | Fn
  syntax TRef ::= tref(Int)                // a table, by id in <tables>
  syntax Fn   ::= builtin(String)          // a library function, by name

  // Expressions evaluate to values in place.
  syntax Exp     ::= Val
  syntax KResult ::= Val

  // ----------------------------------------------------------- tokens
  syntax String ::= Name2String(Name)       [function, total, hook(STRING.token2string)]
                  | Numeral2String(Numeral) [function, total, hook(STRING.token2string)]
                  | LString2String(LString) [function, total, hook(STRING.token2string)]

  // ----------------------------------------------------------- basics
  syntax Bool ::= #truthy(Val) [function, total]
  rule #truthy(nil)   => false
  rule #truthy(false) => false
  rule #truthy(_)     => true [owise]

  syntax String ::= #type(Val) [function, total]
  rule #type(_:Nil)    => "nil"
  rule #type(_:Bool)   => "boolean"
  rule #type(_:Float)  => "number"
  rule #type(_:String) => "string"
  rule #type(_:TRef)   => "table"
  rule #type(_:Fn)     => "function"

  // Raw equality (no metamethods): numbers by value, so 0 == -0 and
  // NaN ~= NaN; everything else by identity or contents.
  syntax Bool ::= #rawEq(Val, Val) [function, total]
  rule #rawEq(A:Float, B:Float) => A ==Float B
  rule #rawEq(A, B) => A ==K B [owise]

  // First value of a list, nil if empty; and the rest.
  syntax Val  ::= #head(List) [function, total]
  rule #head(ListItem(V:Val) _) => V
  rule #head(_) => nil [owise]

  syntax List ::= #tail(List) [function, total]
  rule #tail(ListItem(_) L) => L
  rule #tail(.List) => .List

  // ----------------------------------------------------------- strings
  syntax String ::= #charAt(String, Int) [function, total]
  rule #charAt(S, I) => substrString(S, I, I +Int 1)

  syntax Bool ::= #isDigitAt(String, Int) [function, total]
  rule #isDigitAt(S, I) => I >=Int 0 andBool I <Int lengthString(S)
                   andBool ordChar(#charAt(S, I)) >=Int 48
                   andBool ordChar(#charAt(S, I)) <=Int 57

  syntax Bool ::= #startsWith(String, String) [function, total]
  rule #startsWith(S, P) => lengthString(S) >=Int lengthString(P)
                   andBool substrString(S, 0, lengthString(P)) ==String P

  syntax Bool ::= #endsWith(String, String) [function, total]
  rule #endsWith(S, P) => lengthString(S) >=Int lengthString(P)
                   andBool substrString(S, lengthString(S) -Int lengthString(P), lengthString(S)) ==String P

  syntax String ::= #rep(String, Int) [function, total]
  rule #rep(S, N) => S +String #rep(S, N -Int 1) requires N >Int 0
  rule #rep(_, _) => "" [owise]

  // C isspace: space, \t \n \v \f \r.
  syntax Bool ::= #isSpace(String) [function, total]
  rule #isSpace(C) => C ==String " " orBool (lengthString(C) ==Int 1
                      andBool ordChar(C) >=Int 9 andBool ordChar(C) <=Int 13)

  syntax String ::= #trim(String) [function, total]
                  | #trimRight(String) [function, total]
  rule #trim(S) => #trim(substrString(S, 1, lengthString(S)))
    requires lengthString(S) >Int 0 andBool #isSpace(#charAt(S, 0))
  rule #trim(S) => #trimRight(S) [owise]
  rule #trimRight(S) => #trimRight(substrString(S, 0, lengthString(S) -Int 1))
    requires lengthString(S) >Int 0 andBool #isSpace(#charAt(S, lengthString(S) -Int 1))
  rule #trimRight(S) => S [owise]

  // ASCII-only case mapping, as in the C locale.
  syntax String ::= #lower(String) [function, total]
  rule #lower(S) => #lowerFrom(S, 0, "")
  syntax String ::= #lowerFrom(String, Int, String) [function, total]
  rule #lowerFrom(S, I, Acc) => Acc requires I >=Int lengthString(S)
  rule #lowerFrom(S, I, Acc) => #lowerFrom(S, I +Int 1, Acc +String chrChar(ordChar(#charAt(S, I)) +Int 32))
    requires I <Int lengthString(S) andBool ordChar(#charAt(S, I)) >=Int 65 andBool ordChar(#charAt(S, I)) <=Int 90
  rule #lowerFrom(S, I, Acc) => #lowerFrom(S, I +Int 1, Acc +String #charAt(S, I)) [owise]
endmodule
