// Number <-> string conversion, matching C's printf("%.14g") and Lua 5.1's
// luaO_str2d (strtod plus hex), which is what tostring/tonumber, print,
// io.write and `..` use.
//
// K's Float2String(F, format) is not implemented by the LLVM backend, and
// rounding Float2String(F)'s 17 digits again would sometimes round twice.
// So formatting works from the exact value: a finite double is M * 2^E for
// integers M, E, which K's big integers turn into an exact decimal D * 10^E.

requires "lua-values.k"

module LUA-NUMBER
  imports LUA-VALUES

  syntax String ::= #num2str(Float) [function, total]
  rule #num2str(F) => #fmtG(F, 14)

  // ------------------------------------------------------------- %.Pg
  // K never sets the sign of a NaN, while x86 Lua prints 0/0 as "-nan" and
  // -(0/0) as "nan". Printing "-nan" matches the common case.
  syntax String ::= #fmtG(Float, Int) [function, total]
  rule #fmtG(F, _) => "-nan" requires isNaN(F)
  rule #fmtG(F, _) => "inf"  requires F ==Float Infinity
  rule #fmtG(F, _) => "-inf" requires F ==Float -Infinity
  rule #fmtG(F, P) => "-" +String #fmtGPos(--Float F, P)
    requires notBool isNaN(F) andBool notBool isInfinite(F) andBool signFloat(F)
  rule #fmtG(F, P) => #fmtGPos(F, P) [owise]

  // F is finite and >= 0 (including -0 after negation, which is 0).
  syntax String ::= #fmtGPos(Float, Int) [function, total]
  rule #fmtGPos(F, _) => "0" requires F ==Float 0.0
  // Fast path: integers with at most P digits print exactly.
  rule #fmtGPos(F, P) => Int2String(Float2Int(F))
    requires F >Float 0.0 andBool F ==Float floorFloat(F)
     andBool P <=Int 15 andBool F <Float Int2Float(10 ^Int P, 53, 11)
  rule #fmtGPos(F, P) => #fmtGDec(#decimal(F), P) [owise]

  // Exact decimal: F = D * 10^E.
  syntax Dec ::= #dec(Int, Int)
               | #decimal(Float)      [function, total]
               | #decimal2(Int, Int)  [function, total]
  rule #decimal(F) => #decimal2(#mant(F), exponentFloat(F) -Int 54)
  rule #decimal2(M, E) => #dec(M *Int (2 ^Int E), 0) requires E >=Int 0
  rule #decimal2(M, E) => #dec(M *Int (5 ^Int (0 -Int E)), E) [owise]

  // F * 2^(54 - exponent) is an integer of at most 55 bits, both for normal
  // numbers (exponentFloat uses the IEEE convention, 1.0 -> 0) and for
  // subnormals (exponentFloat reports the minimum, -1023).
  syntax Int ::= #mant(Float) [function, total]
  rule #mant(F) => Float2Int(#scale2(F, 54 -Int exponentFloat(F)))

  // F * 2^K exactly, in steps that stay inside the double range.
  syntax Float ::= #scale2(Float, Int) [function, total]
                 | #pow2(Int)          [function, total]
  rule #scale2(F, K) => #scale2(F *Float #pow2(1000), K -Int 1000) requires K >Int 1000
  rule #scale2(F, K) => #scale2(F /Float #pow2(1000), K +Int 1000) requires K <Int -1000
  rule #scale2(F, K) => F *Float #pow2(K) requires K >=Int 0 andBool K <=Int 1000
  rule #scale2(F, K) => F /Float #pow2(0 -Int K) requires K <Int 0 andBool K >=Int -1000
  rule #pow2(K) => Int2Float(2 ^Int K, 53, 11)

  // Round D * 10^E to P significant digits (ties to even, like glibc), then
  // lay it out: exponent form if the decimal exponent X < -4 or X >= P,
  // fixed form otherwise; trailing zeros are dropped (no '#' flag).
  syntax String ::= #fmtGDec(Dec, Int)              [function, total]
                  | #fmtGRound(Int, Int, Int, Int)  [function, total]
                  | #fmtGSig(Int, Int, Int)         [function, total]
  rule #fmtGDec(#dec(D, E), P) => #fmtGRound(D, lengthString(Int2String(D)), E, P)
  rule #fmtGDec(_, _) => "?" [owise]
  rule #fmtGRound(D, L, E, P) => #fmtGSig(#roundDigits(D, L -Int P), L -Int 1 +Int E, P)
    requires L >Int P
  rule #fmtGRound(D, L, E, P) => #fmtGSig(D *Int (10 ^Int (P -Int L)), L -Int 1 +Int E, P)
    [owise]
  // K holds the P significant digits (P + 1 after a rounding carry), X is
  // the decimal exponent of the first one.
  rule #fmtGSig(K, X, P) => #fmtGSig(K /Int 10, X +Int 1, P) requires K >=Int 10 ^Int P
  rule #fmtGSig(K, X, P) => #fmtE(Int2String(K), X)
    requires K <Int 10 ^Int P andBool (X <Int -4 orBool X >=Int P)
  rule #fmtGSig(K, X, _) => #fmtF(Int2String(K), X) [owise]

  // Drop N trailing digits of D, rounding half to even.
  syntax Int ::= #roundDigits(Int, Int) [function, total]
               | #roundHE(Int, Int, Int) [function, total]
  rule #roundDigits(D, N) => #roundHE(D /Int (10 ^Int N), D %Int (10 ^Int N), 10 ^Int N)
  rule #roundHE(K, R, Q) => K +Int 1
    requires R *Int 2 >Int Q orBool (R *Int 2 ==Int Q andBool K %Int 2 ==Int 1)
  rule #roundHE(K, _, _) => K [owise]

  // Ds: significant digits, X: exponent of the first digit.
  syntax String ::= #fmtE(String, Int) [function, total]
                  | #fmtF(String, Int) [function, total]
                  | #expPart(Int)      [function, total]
                  | #dotFrac(String)   [function, total]
                  | #stripZeros(String) [function, total]
  rule #fmtE(Ds, X) => #charAt(Ds, 0)
                       +String #dotFrac(#stripZeros(substrString(Ds, 1, lengthString(Ds))))
                       +String #expPart(X)
  rule #fmtF(Ds, X) => substrString(Ds, 0, X +Int 1)
                       +String #dotFrac(#stripZeros(substrString(Ds, X +Int 1, lengthString(Ds))))
    requires X >=Int 0
  rule #fmtF(Ds, X) => "0." +String #rep("0", (0 -Int X) -Int 1) +String #stripZeros(Ds) [owise]
  rule #expPart(X) => "e-" +String #pad2(0 -Int X) requires X <Int 0
  rule #expPart(X) => "e+" +String #pad2(X) [owise]
  rule #dotFrac("") => ""
  rule #dotFrac(S) => "." +String S [owise]
  rule #stripZeros(S) => #stripZeros(substrString(S, 0, lengthString(S) -Int 1))
    requires #endsWith(S, "0")
  rule #stripZeros(S) => S [owise]

  syntax String ::= #pad2(Int) [function, total]
  rule #pad2(N) => "0" +String Int2String(N) requires N <Int 10
  rule #pad2(N) => Int2String(N) [owise]

  // ------------------------------------------------------------ str2num
  // Lua 5.1 luaO_str2d: strtod, or hex via strtoul; surrounding whitespace
  // allowed; anything else left over makes it fail (nil).
  syntax Val ::= #str2num(String)    [function, total]
               | #s2n(String)        [function, total]
               | #s2nU(String)       [function, total]
               | #negate(Val, Bool)  [function, total]
  rule #str2num(S) => #s2n(#trim(S))
  rule #s2n(S) => #negate(#s2nU(substrString(S, 1, lengthString(S))), true)
    requires #startsWith(S, "-")
  rule #s2n(S) => #negate(#s2nU(substrString(S, 1, lengthString(S))), false)
    requires #startsWith(S, "+")
  rule #s2n(S) => #s2nU(S) [owise]

  rule #negate(F:Float, true) => --Float F
  rule #negate(V, _) => V [owise]

  rule #s2nU(S) => Int2Float(String2Base(substrString(S, 2, lengthString(S)), 16), 53, 11)
    requires (#startsWith(S, "0x") orBool #startsWith(S, "0X"))
     andBool lengthString(S) >Int 2 andBool #allHex(S, 2)
  rule #s2nU(S) => Infinity
    requires #lower(S) ==String "inf" orBool #lower(S) ==String "infinity"
  rule #s2nU(S) => NaN requires #lower(S) ==String "nan"
  // K does not clamp a parsed float to the double range; roundFloat does.
  rule #s2nU(S) => roundFloat(String2Float(S), 53, 11) requires #isDecimal(S)
  rule #s2nU(_) => nil [owise]

  syntax Bool ::= #allHex(String, Int) [function, total]
                | #isHex(String)       [function, total]
  rule #allHex(S, I) => true requires I >=Int lengthString(S)
  rule #allHex(S, I) => #isHex(#charAt(S, I)) andBool #allHex(S, I +Int 1) [owise]
  rule #isHex(C) => findString("0123456789abcdefABCDEF", C, 0) >=Int 0 andBool lengthString(C) ==Int 1

  // digits [. digits] [(e|E) [+|-] digits], at least one mantissa digit.
  syntax Bool ::= #isDecimal(String)                [function, total]
                | #decInt(String, Int, Int)         [function, total]
                | #decFrac(String, Int, Int)        [function, total]
                | #decExp(String, Int)              [function, total]
                | #decExpDigits(String, Int, Bool)  [function, total]
  rule #isDecimal(S) => #decInt(S, 0, 0)
  // #decInt(S, I, digits seen so far)
  rule #decInt(S, I, D) => D >Int 0 requires I >=Int lengthString(S)
  rule #decInt(S, I, D) => #decInt(S, I +Int 1, D +Int 1) requires #isDigitAt(S, I)
  rule #decInt(S, I, D) => #decFrac(S, I +Int 1, D)
    requires I <Int lengthString(S) andBool #charAt(S, I) ==String "."
  rule #decInt(S, I, D) => #decExp(S, I +Int 1)
    requires I <Int lengthString(S) andBool D >Int 0
     andBool (#charAt(S, I) ==String "e" orBool #charAt(S, I) ==String "E")
  rule #decInt(_, _, _) => false [owise]
  rule #decFrac(S, I, D) => D >Int 0 requires I >=Int lengthString(S)
  rule #decFrac(S, I, D) => #decFrac(S, I +Int 1, D +Int 1) requires #isDigitAt(S, I)
  rule #decFrac(S, I, D) => #decExp(S, I +Int 1)
    requires I <Int lengthString(S) andBool D >Int 0
     andBool (#charAt(S, I) ==String "e" orBool #charAt(S, I) ==String "E")
  rule #decFrac(_, _, _) => false [owise]
  rule #decExp(S, I) => #decExpDigits(S, I +Int 1, false)
    requires I <Int lengthString(S) andBool (#charAt(S, I) ==String "+" orBool #charAt(S, I) ==String "-")
  rule #decExp(S, I) => #decExpDigits(S, I, false) [owise]
  rule #decExpDigits(S, I, Seen) => Seen requires I >=Int lengthString(S)
  rule #decExpDigits(S, I, _) => #decExpDigits(S, I +Int 1, true) requires #isDigitAt(S, I)
  rule #decExpDigits(_, _, _) => false [owise]

  // Coercion used by arithmetic and tonumber: numbers stay, strings parse.
  syntax Val ::= #tonumber(Val) [function, total]
  rule #tonumber(F:Float)  => F
  rule #tonumber(S:String) => #str2num(S)
  rule #tonumber(_) => nil [owise]

  // Coercion used by `..` and io.write: strings stay, numbers format.
  syntax Val ::= #tostringCoerce(Val) [function, total]
  rule #tostringCoerce(S:String) => S
  rule #tostringCoerce(F:Float)  => #num2str(F)
  rule #tostringCoerce(_) => nil [owise]
endmodule
