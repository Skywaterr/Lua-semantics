// string.format (lstrlib.c str_format): each conversion is formatted the way
// glibc's printf formats it, computed exactly from the decimal expansion of
// the double (lua-number.k), rounding ties to even.

requires "lua-number.k"

module LUA-FORMAT
  imports LUA-NUMBER

  // A parsed conversion: flags, width (-1: none), precision (-1: none).
  syntax Spec ::= #spec(String, Int, Int)

  syntax Bool ::= #hasFlag(Spec, String) [function, total]
  rule #hasFlag(#spec(Fl, _, _), F) => findString(Fl, F, 0) >=Int 0

  // The result of formatting: the text, or an error message.
  syntax FmtRes ::= #fok(String) | #ferr(String)

  // ============================================================ driver
  // #format(fmt, position in fmt, args, argument number, output so far)
  syntax FmtRes ::= #format(String, Int, List, Int, String) [function, total]
  rule #format(F, I, _, _, Acc) => #fok(Acc +String substrString(F, I, lengthString(F)))
    requires findString(F, "%", I) <Int 0
  rule #format(F, I, Args, N, Acc) => #fmtSpec(F, findString(F, "%", I) +Int 1, Args, N,
                                               Acc +String substrString(F, I, findString(F, "%", I)))
    [owise]

  // scanformat: up to 5 flags, at most 2 width digits, '.', at most 2
  // precision digits, then the conversion character.
  syntax FmtRes ::= #fmtSpec(String, Int, List, Int, String) [function, total]
                  | #fmtSpec2(String, Int, Int, List, Int, String) [function, total]   // flags end
  rule #fmtSpec(F, I, Args, N, Acc) => #format(F, I +Int 1, Args, N, Acc +String "%")
    requires #at2(F, I) ==String "%"
  rule #fmtSpec(F, I, Args, N, Acc) => #fmtSpec2(F, I, #skipFlags(F, I), Args, N, Acc) [owise]
  rule #fmtSpec2(_, I, J, _, _, _) => #ferr("invalid format (repeated flags)") requires J -Int I >=Int 6
  rule #fmtSpec2(F, I, J, Args, N, Acc) =>
         #fmtConv(F, #afterPrec(F, #afterWidth(F, J)),
                  #spec(substrString(F, I, J), #digitsVal(F, J, #afterWidth(F, J)), #precVal(F, #afterWidth(F, J))),
                  Args, N, Acc)
    [owise]

  syntax String ::= #at2(String, Int) [function, total]
  rule #at2(S, I) => substrString(S, I, I +Int 1) requires I >=Int 0 andBool I <Int lengthString(S)
  rule #at2(_, _) => "" [owise]

  syntax Int ::= #skipFlags(String, Int) [function, total]
               | #afterWidth(String, Int) [function, total]
               | #afterPrec(String, Int) [function, total]
               | #upTo2Digits(String, Int) [function, total]
               | #digitsVal(String, Int, Int) [function, total]
               | #precVal(String, Int) [function, total]
  rule #skipFlags(F, I) => #skipFlags(F, I +Int 1)
    requires #at2(F, I) =/=String "" andBool findString("-+ #0", #at2(F, I), 0) >=Int 0
  rule #skipFlags(_, I) => I [owise]
  rule #upTo2Digits(F, I) => #if #isDigitAt(F, I) #then (#if #isDigitAt(F, I +Int 1) #then I +Int 2 #else I +Int 1 #fi) #else I #fi
  rule #afterWidth(F, I) => #upTo2Digits(F, I)
  rule #afterPrec(F, I) => #upTo2Digits(F, I +Int 1) requires #at2(F, I) ==String "."
  rule #afterPrec(_, I) => I [owise]
  rule #digitsVal(F, I, J) => String2Int(substrString(F, I, J)) requires J >Int I
  rule #digitsVal(_, _, _) => -1 [owise]
  // "%.f" has precision 0
  rule #precVal(F, I) => #if #upTo2Digits(F, I +Int 1) >Int I +Int 1
                         #then String2Int(substrString(F, I +Int 1, #upTo2Digits(F, I +Int 1))) #else 0 #fi
    requires #at2(F, I) ==String "."
  rule #precVal(_, _) => -1 [owise]

  // C is the conversion character at position I.
  syntax FmtRes ::= #fmtConv(String, Int, Spec, List, Int, String) [function, total]
                  | #fmtNext(FmtRes, String, Int, List, Int, String) [function, total]
  rule #fmtConv(F, I, _, _, _, _) => #ferr("invalid format (width or precision too long)")
    requires #isDigitAt(F, I)
  rule #fmtConv(F, I, Sp, Args, N, Acc) =>
         #fmtNext(#fmtOne(#at2(F, I), Sp, #head(Args), size(Args) >Int 0, N), F, I +Int 1, #tail(Args), N +Int 1, Acc)
    [owise]
  rule #fmtNext(#fok(S), F, I, Args, N, Acc) => #format(F, I, Args, N, Acc +String S)
  rule #fmtNext(E, _, _, _, _, _) => E [owise]

  // =============================================== one conversion
  // #fmtOne(conversion, spec, argument, argument present, argument number)
  syntax FmtRes ::= #fmtOne(String, Spec, Val, Bool, Int) [function, total]
  rule #fmtOne(C, _, _, _, _) => #ferr("invalid option '%" +String C +String "' to 'format'")
    requires findString("cdiouxXeEfgGqs", C, 0) <Int 0 orBool lengthString(C) =/=Int 1
  rule #fmtOne(C, _, _, false, N) => #badArg(N, #if C ==String "s" orBool C ==String "q" #then "string" #else "number" #fi, "no value")
    requires findString("cdiouxXeEfgGqs", C, 0) >=Int 0 andBool lengthString(C) ==Int 1
  rule #fmtOne(C, _, V, true, N) => #badArg(N, "number", #type(V))
    requires findString("cdiouxXeEfgG", C, 0) >=Int 0 andBool lengthString(C) ==Int 1
     andBool notBool isFloat(#tonumber(V))
  rule #fmtOne(C, _, V, true, N) => #badArg(N, "string", #type(V))
    requires (C ==String "s" orBool C ==String "q") andBool #tostringCoerce(V) ==K nil
  rule #fmtOne("q", _, V, true, _) => #fok(#quoted({#tostringCoerce(V)}:>String))
    requires #tostringCoerce(V) =/=K nil
  rule #fmtOne("s", Sp, V, true, _) => #fok(#fmtStr(Sp, {#tostringCoerce(V)}:>String))
    requires #tostringCoerce(V) =/=K nil
  rule #fmtOne(C, Sp, V, true, _) => #fok(#fmtNum(C, Sp, {#tonumber(V)}:>Float))
    requires findString("cdiouxXeEfgG", C, 0) >=Int 0 andBool lengthString(C) ==Int 1
     andBool isFloat(#tonumber(V))

  syntax FmtRes ::= #badArg(Int, String, String) [function, total]
  rule #badArg(N, Want, Got) => #ferr("bad argument #" +String Int2String(N) +String " to 'format' ("
                                      +String Want +String " expected, got " +String Got +String ")")

  // ------------------------------------------------------------ padding
  // Pad to the width: on the right with '-', else on the left with spaces,
  // or with zeros after the sign/prefix when ZeroOk.
  syntax String ::= #pad(Spec, String, String, Bool) [function, total]   // spec, prefix (sign/0x), body, zero padding allowed
  rule #pad(#spec(Fl, W, P), Pre, Body, _) => Pre +String Body +String #rep(" ", W -Int lengthString(Pre +String Body))
    requires #hasFlag(#spec(Fl, W, P), "-")
  rule #pad(#spec(Fl, W, P), Pre, Body, true) => Pre +String #rep("0", W -Int lengthString(Pre +String Body)) +String Body
    requires notBool #hasFlag(#spec(Fl, W, P), "-") andBool #hasFlag(#spec(Fl, W, P), "0")
  rule #pad(#spec(_, W, _), Pre, Body, _) => #rep(" ", W -Int lengthString(Pre +String Body)) +String Pre +String Body [owise]

  // ------------------------------------------------------------ strings
  // %s: precision truncates; %q quotes for reading back.
  syntax String ::= #fmtStr(Spec, String) [function, total]
  rule #fmtStr(#spec(Fl, W, P), S) => #pad(#spec(Fl, W, P), "", substrString(S, 0, P), false)
    requires P >=Int 0 andBool P <Int lengthString(S)
  rule #fmtStr(Sp, S) => #pad(Sp, "", S, false) [owise]

  syntax String ::= #quoted(String) [function, total]
                  | #quoteFrom(String, Int, String) [function, total]
  rule #quoted(S) => "\"" +String #quoteFrom(S, 0, "") +String "\""
  rule #quoteFrom(S, I, Acc) => Acc requires I >=Int lengthString(S)
  rule #quoteFrom(S, I, Acc) => #quoteFrom(S, I +Int 1, Acc +String #quoteChar(#at2(S, I))) [owise]
  syntax String ::= #quoteChar(String) [function, total]
  rule #quoteChar("\"") => "\\\""
  rule #quoteChar("\\") => "\\\\"
  rule #quoteChar("\n") => "\\\n"
  rule #quoteChar("\r") => "\\r"
  rule #quoteChar(C) => "\\000" requires ordChar(C) ==Int 0
  rule #quoteChar(C) => C [owise]

  // ------------------------------------------------------------ numbers
  syntax String ::= #fmtNum(String, Spec, Float) [function, total]
  // %c: the byte (int) x
  rule #fmtNum("c", Sp, X) => #pad(Sp, "", chrChar(#truncInt(X) modInt 256), false)
  // %d %i: (long) x
  rule #fmtNum(C, Sp, X) => #fmtInt(Sp, #truncInt(X), 10, false, "")
    requires C ==String "d" orBool C ==String "i"
  // %u %o %x %X: (unsigned long) x
  rule #fmtNum("u", Sp, X) => #fmtInt(Sp, #toUnsigned(#truncInt(X)), 10, true, "")
  rule #fmtNum("o", Sp, X) => #fmtInt(Sp, #toUnsigned(#truncInt(X)), 8, true, "o")
  rule #fmtNum("x", Sp, X) => #fmtInt(Sp, #toUnsigned(#truncInt(X)), 16, true, "x")
  rule #fmtNum("X", Sp, X) => #fmtInt(Sp, #toUnsigned(#truncInt(X)), 16, true, "X")
  // %e %E %f %g %G
  rule #fmtNum(C, Sp, X) => #fmtFloat(C, Sp, X) [owise]

  syntax Int ::= #toUnsigned(Int) [function, total]
  rule #toUnsigned(I) => I +Int 18446744073709551616 requires I <Int 0
  rule #toUnsigned(I) => I [owise]

  // #fmtInt(spec, value, base, unsigned, alternate-form kind)
  syntax String ::= #fmtInt(Spec, Int, Int, Bool, String) [function, total]
  rule #fmtInt(#spec(Fl, W, P), V, B, U, Alt) =>
         #pad(#spec(Fl, W, P),
              #intSign(#spec(Fl, W, P), V, U) +String #altPrefix(#spec(Fl, W, P), Alt, V),
              #altOctal(#spec(Fl, W, P), Alt, #precDigits(#digitsIn(absInt(V), B, Alt), P, V)),
              P <Int 0)

  syntax String ::= #digitsIn(Int, Int, String) [function, total]
  rule #digitsIn(V, 16, "X") => #upperHex(Base2String(V, 16))
  rule #digitsIn(V, B, _) => #lowerHex(Base2String(V, B)) [owise]
  // with a precision: at least that many digits; precision 0 prints 0 as ""
  syntax String ::= #precDigits(String, Int, Int) [function, total]
  rule #precDigits(_, 0, 0) => ""
  rule #precDigits(D, P, _) => #rep("0", P -Int lengthString(D)) +String D [owise]
  syntax String ::= #intSign(Spec, Int, Bool) [function, total]
  rule #intSign(_, V, false) => "-" requires V <Int 0
  rule #intSign(Sp, V, false) => "+" requires V >=Int 0 andBool #hasFlag(Sp, "+")
  rule #intSign(Sp, V, false) => " " requires V >=Int 0 andBool notBool #hasFlag(Sp, "+") andBool #hasFlag(Sp, " ")
  rule #intSign(_, _, _) => "" [owise]
  // '#': 0x / 0X for non-zero hex; octal gets a leading 0 if it has none
  syntax String ::= #altPrefix(Spec, String, Int) [function, total]
  rule #altPrefix(Sp, "x", V) => "0x" requires #hasFlag(Sp, "#") andBool V =/=Int 0
  rule #altPrefix(Sp, "X", V) => "0X" requires #hasFlag(Sp, "#") andBool V =/=Int 0
  rule #altPrefix(_, _, _) => "" [owise]
  syntax String ::= #altOctal(Spec, String, String) [function, total]
  rule #altOctal(Sp, "o", D) => "0" +String D requires #hasFlag(Sp, "#") andBool notBool #startsWith(D, "0")
  rule #altOctal(_, _, D) => D [owise]

  // Base2String's letter case is backend-defined.
  syntax String ::= #upperHex(String) [function, total] | #lowerHex(String) [function, total]
  rule #upperHex(S) => replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(S,
                         "a", "A"), "b", "B"), "c", "C"), "d", "D"), "e", "E"), "f", "F")
  rule #lowerHex(S) => replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(S,
                         "A", "a"), "B", "b"), "C", "c"), "D", "d"), "E", "e"), "F", "f")

  // ------------------------------------------------------------ floats
  syntax String ::= #fmtFloat(String, Spec, Float) [function, total]
  rule #fmtFloat(C, Sp, X) => #pad(Sp, #floatSign(Sp, X), #caseFor(C, #if isNaN(X) #then "nan" #else "inf" #fi), false)
    requires isNaN(X) orBool isInfinite(X)
  rule #fmtFloat(C, Sp, X) => #pad(Sp, #floatSign(Sp, X), #caseFor(C, #floatBody(C, Sp, absFloat(X))), true) [owise]

  // K never sets a NaN's sign; print "-nan" like tostring (lua-number.k).
  syntax String ::= #floatSign(Spec, Float) [function, total]
  rule #floatSign(_, X) => "-" requires isNaN(X) orBool signFloat(X)
  rule #floatSign(Sp, X) => "+" requires notBool (isNaN(X) orBool signFloat(X)) andBool #hasFlag(Sp, "+")
  rule #floatSign(Sp, X) => " "
    requires notBool (isNaN(X) orBool signFloat(X)) andBool notBool #hasFlag(Sp, "+") andBool #hasFlag(Sp, " ")
  rule #floatSign(_, _) => "" [owise]

  syntax String ::= #caseFor(String, String) [function, total]
  rule #caseFor(C, S) => #upperAscii(S) requires C ==String "E" orBool C ==String "G"
  rule #caseFor(_, S) => S [owise]
  syntax String ::= #upperAscii(String) [function, total]
  rule #upperAscii(S) => replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(S, "e", "E"), "n", "N"), "a", "A"), "i", "I"), "f", "F")

  // X >= 0 and finite. Default precision 6.
  syntax String ::= #floatBody(String, Spec, Float) [function, total]
  rule #floatBody(C, #spec(Fl, W, P), X) => #floatBody(C, #spec(Fl, W, 6), X) requires P <Int 0
  rule #floatBody("f", #spec(Fl, W, P), X) => #fixed(#scaledRound(X, P), P, #hasFlag(#spec(Fl, W, P), "#"))
    requires P >=Int 0
  rule #floatBody(C, #spec(Fl, W, P), X) => #expo(#sigDigits(X, P +Int 1), P, #hasFlag(#spec(Fl, W, P), "#"))
    requires P >=Int 0 andBool (C ==String "e" orBool C ==String "E")
  rule #floatBody(C, #spec(Fl, W, P), X) => #general(#sigDigits(X, maxInt(P, 1)), maxInt(P, 1), #hasFlag(#spec(Fl, W, P), "#"))
    requires P >=Int 0 andBool (C ==String "g" orBool C ==String "G")
  rule #floatBody(_, _, _) => "?" [owise]

  // round(X * 10^P), ties to even
  syntax Int ::= #scaledRound(Float, Int) [function, total] | #scaledRound2(Dec, Int) [function, total]
  rule #scaledRound(X, _) => 0 requires X ==Float 0.0
  rule #scaledRound(X, P) => #scaledRound2(#decimal(X), P) [owise]
  rule #scaledRound2(#dec(D, E), P) => D *Int (10 ^Int (E +Int P)) requires E +Int P >=Int 0
  rule #scaledRound2(#dec(D, E), P) => #roundDigits(D, 0 -Int (E +Int P)) [owise]

  // N = round(X * 10^P) laid out with P decimals.
  syntax String ::= #fixed(Int, Int, Bool) [function, total] | #fixedDigits(String, Int, Bool) [function, total]
  rule #fixed(N, P, Alt) => #fixedDigits(#rep("0", P +Int 1 -Int lengthString(Int2String(N))) +String Int2String(N), P, Alt)
  rule #fixedDigits(D, 0, Alt) => D +String #if Alt #then "." #else "" #fi
  rule #fixedDigits(D, P, _) => substrString(D, 0, lengthString(D) -Int P) +String "." +String substrString(D, lengthString(D) -Int P, lengthString(D)) [owise]

  // N significant digits of X: #sig(digits, exponent of the first one).
  syntax Sig ::= #sig(String, Int)
  syntax Sig ::= #sigDigits(Float, Int) [function, total] | #sigDigits2(Dec, Int) [function, total]
               | #sigFix(Int, Int, Int) [function, total]
  rule #sigDigits(X, N) => #sig(#rep("0", N), 0) requires X ==Float 0.0
  rule #sigDigits(X, N) => #sigDigits2(#decimal(X), N) [owise]
  rule #sigDigits2(#dec(D, E), N) => #sigFix(#roundDigits(D, lengthString(Int2String(D)) -Int N), lengthString(Int2String(D)) -Int 1 +Int E, N)
    requires lengthString(Int2String(D)) >Int N
  rule #sigDigits2(#dec(D, E), N) => #sigFix(D *Int (10 ^Int (N -Int lengthString(Int2String(D)))), lengthString(Int2String(D)) -Int 1 +Int E, N) [owise]
  rule #sigFix(K, X, N) => #sig(Int2String(K /Int 10), X +Int 1) requires K >=Int 10 ^Int N
  rule #sigFix(K, X, _) => #sig(Int2String(K), X) [owise]

  // d.ddde+XX with P decimals.
  syntax String ::= #expo(Sig, Int, Bool) [function, total]
  rule #expo(#sig(Ds, X), P, Alt) => substrString(Ds, 0, 1)
         +String #if P >Int 0 orBool Alt #then "." #else "" #fi
         +String substrString(Ds, 1, lengthString(Ds)) +String #expPart(X)

  // %g: P significant digits; exponent form if X < -4 or X >= P; trailing
  // zeros (and a bare '.') removed unless '#'.
  syntax String ::= #general(Sig, Int, Bool) [function, total]
                  | #trimG(String, Bool) [function, total]
  rule #general(#sig(Ds, X), P, Alt) => #trimGExp(#trimG(substrString(Ds, 0, 1) +String "." +String substrString(Ds, 1, lengthString(Ds)), Alt), X)
    requires X <Int -4 orBool X >=Int P
  rule #general(#sig(Ds, X), P, Alt) => #trimG(substrString(Ds, 0, X +Int 1) +String "." +String substrString(Ds, X +Int 1, lengthString(Ds)), Alt)
    requires X >=Int 0 andBool X <Int P
  rule #general(#sig(Ds, X), _, Alt) => #trimG("0." +String #rep("0", (0 -Int X) -Int 1) +String Ds, Alt)
    requires X <Int 0 andBool X >=Int -4
  rule #trimG(S, true) => S
  rule #trimG(S, false) => #dropDot(#stripZeros(S)) requires findString(S, ".", 0) >=Int 0
  rule #trimG(S, _) => S [owise]
  syntax String ::= #dropDot(String) [function, total] | #trimGExp(String, Int) [function, total]
  rule #dropDot(S) => substrString(S, 0, lengthString(S) -Int 1) requires #endsWith(S, ".")
  rule #dropDot(S) => S [owise]
  rule #trimGExp(S, X) => S +String #expPart(X)
endmodule
