// Decoding Lua 5.1 literal tokens into values.

requires "lua-number.k"

module LUA-LITERAL
  imports LUA-NUMBER

  // Numerals are valid luaO_str2d input by construction.
  syntax Float ::= #numeral(Numeral) [function]
  rule #numeral(N) => {#str2num(Numeral2String(N))}:>Float

  syntax String ::= #decodeLString(String) [function]
  // Short strings: drop the quotes, process escapes.
  rule #decodeLString(S) => #unescape(substrString(S, 1, lengthString(S) -Int 1), "")
    requires #startsWith(S, "\"") orBool #startsWith(S, "'")
  // Long strings [==[ ... ]==]: drop the brackets, skip one leading newline,
  // and turn each newline sequence into "\n" (llex.c read_long_string).
  rule #decodeLString(S) => #longBody(S, findString(S, "[", 1) -Int 1) [owise]

  syntax String ::= #longBody(String, Int) [function]
  rule #longBody(S, N) => #normNewlines(#skipNewline(
         substrString(S, N +Int 2, lengthString(S) -Int (N +Int 2))))

  syntax String ::= #skipNewline(String) [function, total]
  rule #skipNewline(S) => substrString(S, 2, lengthString(S))
    requires #startsWith(S, "\r\n") orBool #startsWith(S, "\n\r")
  rule #skipNewline(S) => substrString(S, 1, lengthString(S))
    requires notBool (#startsWith(S, "\r\n") orBool #startsWith(S, "\n\r"))
     andBool (#startsWith(S, "\n") orBool #startsWith(S, "\r"))
  rule #skipNewline(S) => S [owise]

  syntax String ::= #normNewlines(String) [function, total]
  rule #normNewlines(S) => replaceAll(replaceAll(replaceAll(S, "\r\n", "\n"), "\n\r", "\n"), "\r", "\n")

  // Escapes (llex.c read_string): \a \b \f \n \r \t \v \\ \" \', a backslash
  // before a newline gives a newline, \ddd (up to three decimal digits) gives
  // that byte, and any other escaped character stands for itself.
  syntax String ::= #unescape(String, String) [function]
                  | #escape(String, String, String) [function]  // rest after '\', escaped char, acc
  rule #unescape(S, Acc) => Acc +String S requires findString(S, "\\", 0) <Int 0
  rule #unescape(S, Acc) =>
         #escape(substrString(S, findString(S, "\\", 0) +Int 2, lengthString(S)),
                 #charAt(S, findString(S, "\\", 0) +Int 1),
                 Acc +String substrString(S, 0, findString(S, "\\", 0)))
    [owise]

  rule #escape(R, "a", Acc) => #unescape(R, Acc +String chrChar(7))
  rule #escape(R, "b", Acc) => #unescape(R, Acc +String chrChar(8))
  rule #escape(R, "f", Acc) => #unescape(R, Acc +String chrChar(12))
  rule #escape(R, "n", Acc) => #unescape(R, Acc +String "\n")
  rule #escape(R, "r", Acc) => #unescape(R, Acc +String "\r")
  rule #escape(R, "t", Acc) => #unescape(R, Acc +String "\t")
  rule #escape(R, "v", Acc) => #unescape(R, Acc +String chrChar(11))
  rule #escape(R, "\n", Acc) => #unescape(#skipPair(R, "\r"), Acc +String "\n")
  rule #escape(R, "\r", Acc) => #unescape(#skipPair(R, "\n"), Acc +String "\n")
  rule #escape(R, C, Acc) => #unescape(#dropDigits(R, #numDigits(R, 0)),
                                       Acc +String chrChar(String2Int(C +String substrString(R, 0, #numDigits(R, 0)))))
    requires #isDigitAt(C, 0)
  rule #escape(R, C, Acc) => #unescape(R, Acc +String C) [owise]

  // After "\<newline>", a following complementary newline char is part of it.
  syntax String ::= #skipPair(String, String) [function, total]
  rule #skipPair(R, C) => substrString(R, 1, lengthString(R)) requires #startsWith(R, C)
  rule #skipPair(R, _) => R [owise]

  // How many more digits (at most 2) follow the first one of a \ddd escape.
  syntax Int ::= #numDigits(String, Int) [function, total]
  rule #numDigits(R, N) => #numDigits(R, N +Int 1) requires N <Int 2 andBool #isDigitAt(R, N)
  rule #numDigits(_, N) => N [owise]

  syntax String ::= #dropDigits(String, Int) [function, total]
  rule #dropDigits(R, N) => substrString(R, N, lengthString(R))
endmodule
