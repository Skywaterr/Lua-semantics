# Roadmap: Lua 5.1.5 semantics in K

## Context
`src/lua.k` is an empty two-module skeleton (`LUA-SYNTAX`, `LUA`). The repo already has 15 test programs in `tests/`, reference outputs from real Lua 5.1.5 in `reference-output/`, and `compare.lua` + `make compare DIR1=… DIR2=…` for diffing output dirs. Toolchain present: K v7.1.337 (`kompile`, `krun`), Lua 5.1.5 at `/usr/local/bin/lua`.

Goal: a K definition that runs every deterministic program in `tests/` and matches the reference output (`env`, `fib` and `echo` are set aside until M11), and covers the rest of the Lua 5.1 language (and the parts of the standard library that matter) beyond what those tests use. The roadmap is ordered so each milestone turns a few more tests green. Implementation happens in later sessions, one milestone at a time.

## Before you start: fix the reference outputs
- The working tree has uncommitted changes: `reference-output/sieve.out` is cut down to just `2`, and `printf.out` gained a trailing newline. Running `lua tests/sieve.lua` now prints the full prime list, so the sieve file was probably produced by a different `lua`. Restore it (`git checkout reference-output/sieve.out`) or regenerate it with 5.1.5.
- **Set aside for now (decided):** tests whose output depends on the environment or isn't deterministic. They stay out of `make test` until M11:
  - `env` (`$USER`/`$PATH` from another machine)
  - `fib` (`os.clock()` timings)
  - `echo` (`arg[0]` depends on how the program is invoked)
  
  M0 handles this with an `EXCLUDE` list in the Makefile, so the files stay in the repo. The features they use (`getfenv`/`__index`, `os.getenv`, `os.clock`, `arg`) are still built in their milestones and covered by deterministic `feature-*` tests instead.

## Architecture decisions (set once, in M0/M1)
- **Backend:** LLVM (`kompile --backend llvm`), because `life.lua` runs 2000 generations and writes 42,000 lines. Haskell is too slow for that.
- **Modules:** split `src/lua.k` into `lua-syntax.k`, `lua-config.k`, `lua-values.k`, `lua-semantics.k`, `lua-stdlib.k`, `lua-string-format.k` and `lua-coroutines.k`. `lua.k` imports them all. A single file is also fine until about M4. (As built in M2: see the M2 status below.)
- **Values:** `nil | Bool | Float | String | tableRef(Int) | closure(...) | builtin(Name) | threadRef(Int)`. Every Lua 5.1 number is a double, so use K `Float` (double precision) throughout. Convert to `Int` only for indexing and `%d`.
- **Configuration (sketch):**
  ```
  <threads> <thread multiplicity="*"> <tid/> <k/> <env/> <stack/> <status/> </thread> </threads>
  <current/>
  <store/>      Loc → Value       (locals, upvalues shared through Locs)
  <tables/>     Id → Map          (+ <metas/> Id → Id, per-type metatable for strings)
  <genv/>       tableRef of _G
  <output stream="stdout"/>
  <nextLoc/> <nextId/>
  <hook/>       (debug.sethook state)
  ```
- **Closures:** capture the `<env>` (Name → Loc) at creation, plus a reference to their function environment (`fenv`, which `getfenv`/`setfenv` need).
- **Multiple values:** use an explicit `Values` list sort. Rules adjust it to one value in single-value contexts, and expand only the last expression of an explist, call-argument list or table constructor. `...` is a `Values` stored in the frame.
- **Non-local control flow:** `return` and `break` pop to markers in `<k>` or `<stack>`. `error` unwinds to the nearest `pcall` marker.
- **Source positions:** `debug.getinfo().currentline` and `short_src` are needed by `trace-globals`/`trace-calls` and by error messages. Use K's `[locations]` attribute on the statement and expression sorts so terms carry `#location(..., File, Line, ...)`. A rule records the current line as it executes. Not added in M1, to keep the AST plain while M2–M6 are written; add it in M7, where error messages first need lines. `short_src` comes from `<args>` (the script name), not from the location's file, which is `klua`'s recoded temporary copy.

## Milestones

### M0 — Build and test harness
- Makefile targets:
  - `kompile`: `kompile src/lua.k --backend llvm -o src/lua-kompiled`
  - `run-k`: krun each `tests/*.lua`, write to `k-output/%.out`
  - `test`: `run-k` followed by `make compare DIR1=k-output DIR2=reference-output`
- `EXCLUDE := env fib echo` filters those tests out of `run-k`/`test`. `compare.lua` only matches files that exist in both dirs, so either prune them from the comparison or pass a filtered reference dir; check how `compare.lua` handles missing files.
- Pass `arg` to the program through a config variable (`-cARGS=…` or a `$ARGS` cell).
- Add `k-output/` to `.gitignore`.
- Done when: an empty program runs and `make test` reports all tests failing, without crashing.

### M1 — Complete Lua 5.1 syntax (`LUA-SYNTAX`)
Do the whole grammar up front, since parsing problems shape everything downstream.
- **Statements:** chunk/block with optional `;`, `local`, multiple assignment, call statements, `do`, `while`, `repeat…until`, `if/elseif/else`, numeric and generic `for`, `function f.a.b:m()`, `local function`, `return` and `break` (last statement only).
- **Expressions:** the 5.1 precedence table (`or` < `and` < comparisons < `..` (right) < `+ -` < `* / %` < unary `not # -` < `^` (right)). Prefix expressions, calls `f(...)`, `f"str"`, `f{...}`, `o:m(...)`, `...`, function literals, and table constructors with `[k]=v`, `k=v`, positional entries and `,`/`;` separators.
- **Lexical:** names; numbers (decimal, exponent, hex `0x`); short strings with every escape (`\n`, `\ddd`, `\\`, `\"`, newline continuation, and so on), decoded by a K function; long strings `[[…]]` and `[=[…]=]` (support levels 0–4 with explicit regexes, because K regexes have no backreferences); comments `--` and `--[[ … ]]` declared as `#Layout`.
- **Risks:**
  - The prefix-expression grammar is ambiguous (`a.b(c)` and `f(x)(y)`). Use a `PrefixExp`/`Var`/`Call` sort hierarchy, not one flat `Exp` sort.
  - Longest-match lexing of `..` against numbers like `1..2`.
  - The ALIVE/DEAD string literals in `life.lua` use non-UTF-8 bytes. Make sure the lexer accepts them, since they are overwritten right away.
- Done when: `kast` parses all 15 tests plus a grammar stress file (`tests/syntax/*.lua`).

**Status: done.** `make parse` parses all 15 tests and `tests/syntax/stress.lua` (also checked with `luac -p`). What M1 decided, for later milestones:
- **Module split:** `LUA-COMMON` holds the abstract grammar, with the token sorts `Name`, `Numeral` and `LString` declared without regexes. `LUA-SYNTAX` adds the regexes and `#Layout`, and is only used to parse programs. `LUA` imports `LUA-COMMON`, so K `String` literals in rules don't clash with Lua string tokens.
- **Name-led and paren-led prefix expressions:** every prefix-expression form comes in two families, `NVar`/`NCall`/`NPrefix` (starting with a name) and `PVar`/`PCall`/`PPrefix` (starting with `(`). `Var`, `FunctionCall` and `PrefixExp` are their unions. A statement may begin with `(` (`PStmt`) only at the start of a block or right after `;`. Without this, `f(a)(b)(c)` is ambiguous and K's `prefer`/`avoid` can't fix it, because both readings have the same top production. M2 needs one rule per family for each suffix (`[e]`, `.n`, call, method call), each delegating to a shared operation. Known gap: `do end (f)()` needs a `;` before `(f)`.
- **Assignment** has two forms, `NVar = NeExps` and `NVar , Vars = NeExps` (the same two in `PStmt`). `local`, `for … in` and assignment use the non-empty lists `Names`/`NeExps`, `return` and calls use `Exps`, and parameters use `Params` (possibly empty). `Exp ^ - Exp`, `Exp ^ not Exp` and `Exp ^ # Exp` are separate productions for `2^-3`; M2 can turn them into `^` with a unary operand. `FieldList` keeps its separators (`Field FieldSep FieldList`).
- **Tokens are raw:** `LString` includes its quotes or brackets and undecoded escapes, and `Numeral` is undecoded text (hex included). M2 decodes both with `token2string`-style hooks.
- **Bytes:** `scripts/klua` recodes the source from Latin-1 to UTF-8 before K reads it, and the output back again, so one K character is one Lua byte (`life.lua` needs this). Rules must only produce characters 0–255.
- **Lexer limits:** K's regex reader reads `\f` and `\v` as letters, so form feed and vertical tab aren't whitespace. Long brackets are supported up to level 4.
- **Harness:** `<exit-code>` starts at 1 and becomes 0 when `<k>` empties, so a stuck run fails. `klua` then prints the final configuration to stderr, which `make run-k` saves in `k-logs/NAME.err`.

### M2 — Core evaluation
Literals, arithmetic, string↔number coercion, comparison, `and`/`or` short-circuit returning operands, `not`, `..`, `==` (by reference for tables and functions), globals in `_G`, locals with block scoping, `if`/`while`/`repeat` (the `until` condition sees the body's locals), `break`, and numeric `for` (start, limit and step evaluated once; hidden control variable; fresh local each iteration; float steps).
- **Number→string:** `tostring` uses `%.14g`. Check early whether K's `Float2String(Float, String)` format hook exists in v7.1. If not, write `%g` formatting in K.
- **Builtins:** `print` (tab-separated, uses `tostring`), `io.write` (numbers formatted with `%.14g`), `_VERSION = "Lua 5.1"`.
- Tests that turn green: `hello`, plus the new `tests/feature-core.lua`. `factorial2` moves to M3, because it defines a function.

**Status: done.** `make test` passes `hello` and `feature-core` (2/13). Every other test stops at its first function definition (M3), except `cf`, which stops at `string.format` (M5). What M2 decided, for later milestones:
- **Files:** `lua-syntax.k` → `lua-values.k` → `lua-number.k` → `lua-literal.k` → `lua-config.k` → `lua-eval.k` → `lua-stdlib.k` → `lua.k`. Each file requires the one before it, and `lua.k` lists them.
- **Values:** `Val ::= Nil | Bool | Float | String | TRef | Fn`, with `Exp ::= Val` and `KResult ::= Val`. Lua's `true`/`false` parse as K `Bool` tokens (`LUA-COMMON` imports `BOOL-SYNTAX`), and `nil` parses as the `Nil` sort, so these literals are already values. Library functions are `builtin("name")`, and M3 adds closures to `Fn`.
- **Evaluation:** an expression is evaluated in place on top of `<k>` and leaves a `Val` (single-value context; a call there goes through `#call(F) ~> #first`). Multi-value lists go through `#evalList(List)`, which leaves `#vals(List)`, and only the last expression keeps all of its values (`#multi`). Operators are first rewritten to strict internal forms `#bin(Op, A, B)`, `#un`, `#and`, `#or` and `#idx`, so `lua-syntax.k` has no strictness attributes. In rules, a Lua parenthesis is written `( E ):PPrefix` and call arguments `( Es ):Args`; the cast picks the Lua production over K's grouping brackets.
- **Statements** run as `#exec(S)`. Blocks restore `<env>` on exit through `#restoreEnv(Env, NextLoc, Epoch)`. If `<epoch>` hasn't changed since the block was entered, the store locations allocated inside the block are freed and reused, which keeps `<store>` small in long loops. **M3 must bump `<epoch>` whenever a closure is created, and M8 on every coroutine switch.** `break` drops `<k>` items up to `#breakTarget(Env)`. `return` currently only ends the main chunk (`#returnTop`).
- **Assignment** order matches Lua 5.1: target table and key expressions are evaluated left to right, then the right-hand side, then values are stored from the last target to the first (`a, a = 1, 2` leaves `1`).
- **Tables** are `<tables>`: `Id |-> Map`, with `_G` = table 0 and `io` = table 1. `-0` is normalized to `0` as a key; `nil` and NaN keys are errors. `#t` uses Lua's unbound search (doubling, then binary search). M4 should check that this matches 5.1's array-part behavior on tables with holes. `<fenv>` holds the current globals table; M6 makes closures save and restore it.
- **Numbers:** `Float2String(F, format)` is **not implemented** by the LLVM backend (it crashes). So `lua-number.k` formats `%.Pg` exactly: a double is `M·2^E`, which K's big integers turn into an exact decimal, rounded half-to-even. M5 can reuse `#decimal` for `%f` and `%e`. Parsing (`#str2num`) follows `luaO_str2d` (whitespace, sign, hex, `inf`/`nan`, decimal), and the result goes through `roundFloat(_, 53, 11)`, because K's `String2Float` doesn't clamp to the double range.
- **Known differences from Lua:**
  - K never sets a NaN's sign bit, so every NaN prints as `-nan`, x86 Lua's output for `0/0`. Real Lua prints `-(0/0)` and `tonumber("nan")` as `nan`.
  - Lua's constant folding makes the literal `-0` print as `0`; here it prints `-0`.
  - `tostring` addresses are made up (`table: 0x00000001`, `function: builtin: print`).
  - `io.write` returns nothing (M9: the file).
- **Errors:** `#error(msg)` halts the run and records `lua: msg` in `<errors>`. K has no `stderr` stream, so `klua` shows it in the final configuration (`k-logs/NAME.err`). The run exits non-zero.

### M3 — Functions, closures, multiple values
Function definitions, calls, upvalues (shared Locs), recursion, method sugar `:`, varargs `...`, `select('#',…)`, `unpack`, multiple assignment (evaluate everything, then assign), multiple returns with adjustment, tail calls (no stack growth), and the 5.1 `arg` table in vararg functions (`LUA_COMPAT_VARARG`).
- Tests that turn green: `factorial2`, `factorial` (Y combinator), and `bisect` once M5's `string.format` lands.

**Status: done.** `make test` passes 5/14: `hello`, `factorial`, `factorial2`, `feature-core` and the new `tests/feature-functions.lua`, which covers closures, shared and per-iteration upvalues, multiple results in every adjustment context, varargs, `select`, `arg`, methods, 100,000-deep tail recursion and the generic `for`. The rest stop at a library that doesn't exist yet: `math` (bisect), `string` (cf, printf), `coroutine` (fibfor, sieve), `debug` (trace-calls), or a table constructor (life, sort, trace-globals). What M3 decided, for later milestones:
- **Closures** are `closure(Id)`, with `<funcs>` holding `Id |-> #fun(Params, IsVararg, NeedsArg, Body, CapturedEnv, Fenv)`. Keeping only the id in the value makes equality and hashing cheap. Creating a closure bumps `<epoch>`.
- **Calls** (`lua-function.k`): `#apply(closure(I), Args)` switches to the closure's env, binds parameters to new locations, sets `<varargs>` and `<fenv>`, and runs `#run(Body) ~> #vals(.List) ~> #return ~> #returnTarget(caller env, varargs, fenv, nextLoc, epoch)`. `#return` drops `<k>` up to the target, and leaving a frame frees its locations when the epoch hasn't moved (`#popFrame`), so non-closure recursion uses bounded memory.
- **Tail calls:** `return f(x)`, unparenthesized, evaluates `f` and its arguments, pops the current frame, then applies `f` (`#tailMark`/`#tailApply`). M9's `debug.getinfo` levels and the `"tail return"` hook event have to account for these missing frames.
- **Main chunk** is a vararg closure with no `arg` local. Its `...` is empty for now; M4 should pass the script arguments (and set the global `arg`).
- **`arg` approximation:** every vararg function gets the 5.0-style local `arg` table (`{n = #extras, ...}`). Real 5.1 gives it only when the body never uses `...`, and otherwise the local is `nil`. Detecting `...` would need an AST walk; see M10 if it matters.
- **Generic `for`** is done here rather than in M4, because it only needs calls. M4 adds `next`/`pairs`/`ipairs`.
- **Grammar:** `...` has its own sort `Vararg` (match it as `_:Vararg`), because a bare `...` in a rule means K's cell frame. `FunctionCall` is *not* a subsort of `Exp` (it's the union of `NCall` and `PCall`), so rules use `#isCall(E)` where an `Exp` must be a call.
- **Rule-writing lesson:** two `[owise]` rules that can apply to the same term run in either order. The generic `attempt to call` rule therefore checks `#type(F) =/=String "function"`, and library functions must not use `[owise]` on `#apply` (they may on their own helper items).

### M4 — Tables
Constructors, `t[k]`/`t.k` get and set, float keys normalized (`1.0` ≡ `1`), `nil`/NaN key errors, assigning `nil` deletes, `#t` (border; match 5.1's array-part behavior on the tests), `next`/`pairs`/`ipairs`, and `table.getn/insert/remove/concat/sort` (`sort` with a comparator).
- Tests that turn green: `sort` (`math.random` only picks pivots, so any PRNG gives the same output), `life` (also a performance check).

**Status: done.** `make test` passes 8/15: `sort` and `life` now pass too. `life` produces all 42,000 lines byte for byte in about 4 minutes, using about 13 MB, so the location freeing from M2/M3 works. The other 7 tests stop at the library their milestone adds: `string.format` (bisect, cf, printf; M5), `setmetatable` (trace-globals; M6), `coroutine` (fibfor, sieve; M8) and `debug` (trace-calls; M9). The new `tests/feature-tables.lua` matches real Lua. It covers constructors (keyed, positional, trailing separators, multi-value last field, `...`), key normalization, identity keys, `#` on constructor tables with holes, `pairs`/`ipairs`/`next` (including clearing fields during a traversal), all of `ltablib`, sort tie order, basic `math`, `math.random` and `arg`. What M4 decided, for later milestones:
- **Table records** are `T |-> #tbl(Fields, ArraySize, Metatable)` (`lua-config.k`). `ArraySize` is what Lua 5.1 would give the array part. Only constructors set it: the positional count rounded as `luaO_int2fb` rounds it, grown to the number of values actually stored. `#border(M, A)` follows `luaH_getn`: a binary search inside the array part when its last slot is nil, otherwise `unbound_search` from `A`. Lua's rehash isn't modelled, so a table with holes that grew by assignment can get a different border than in `lua`; sequences always give `n`. The metatable slot is ready for M6.
- **Constructors** (`lua-table.k`) follow `lcode.c`: keyed fields are stored as they're evaluated, positional values at the end (as `OP_SETLIST` does, nils included), and the last field expands if it's a call or `...`.
- **Traversal order:** `next` returns the smallest key after the current one, ordering numbers (ascending), then strings, booleans, tables and functions. This matches Lua for the array part. For other keys Lua's order depends on its hash function and can't be reproduced, so tests must not print it. The order stays well defined when the current key is cleared mid-traversal. Each `next` call costs O(n), so a `pairs` loop is O(n²); M10 could cache a key order if that ever matters.
- **`table.sort`** is a step-by-step transcription of `ltablib.c` `auxsort` running on the table in place. Ties, inconsistent comparators and the `invalid order function for sorting` error therefore behave as in `lua`.
- **`math`** (`lua-math.k`): everything that maps onto K floats is there now (abs, ceil, floor, sqrt, exp, log, the trig functions, deg, rad, pow, fmod/mod, max, min, huge, pi). log10, frexp, ldexp, modf and the hyperbolic functions are left for M9. `fmod` is computed exactly with big integers, because K's `%Float` doesn't behave like an IEEE remainder for negative operands. **`math.random` reproduces glibc `rand()`**: the TYPE_3 additive generator, seeded with 1 until `randomseed`. Its outputs match `lua` on this machine, both before and after `randomseed`.
- **`arg`:** the global table holds `[-1] = "lua"` and `[0] =` the script path passed through `$ARGS`. The main chunk's `...` is still empty, since `klua` passes no script arguments.
- **Known difference:** in `lua`, a literal `-0` shares a constant slot with `0` (constant folding), so later literal `0`s in the same function print as `-0`. This semantics has no constant table. Tests should make negative zero at run time.
- **`#truncInt`** (C's `(int)` cast) now lives in `lua-values.k`. Argument errors use `#argError(N, fname, expected, got)` from `lua-table.k`.

### M5 — String library and `string.format`
- **`string.format`:** a format-spec parser for `%d %i %s %q %c %x %X %o %e %E %f %g %G %%`, with flags, width and precision (`%3.0f`, `%.17g`, `%.1e`).
- **Other functions:** `len sub upper lower rep reverse byte char`. The string metatable (`("x"):rep(3)`, `s:sub`).
- **Lua patterns:** `find match gmatch gsub`, implemented as a small backtracking matcher in K. This is a sizable sub-project: character classes `%a %d %s %w %p %l %u %c %x`, sets `[...]`, quantifiers `* + - ?`, anchors, captures including position captures, `%b`, and `%f` (undocumented in 5.1).
- Tests that turn green: `printf`, `cf`, `bisect`.

**Status: done.** `make test` passes 12/16. The 4 left stop at `coroutine` (fibfor, sieve; M8), `setmetatable` (trace-globals; M6) and `debug` (trace-calls; M9). `printf`, `cf` and `bisect` pass. The new `tests/feature-strings.lua` matches real Lua line for line. It covers every conversion and flag, ties in printf rounding (`%.2f` of 2.675, `%.0f` of 0.5/1.5/2.5), `%q`, all pattern items (`%b`, `%f`, back-references, position captures, `-` and `?`), `find` with `init` and `plain`, `gmatch`/`gfind`, and `gsub` with string, table and function replacements, a limit, anchors and empty matches. What M5 decided, for later milestones:
- **Patterns** (`lua-pattern.k`) transcribe `lstrlib.c` as *pure functions*. `#match(S, P, s, p, Caps)` returns `#mok(end, Caps)`, `#mfail` or `#merr(msg)`. Captures are passed in and returned instead of mutated, so backtracking just drops a failed branch's captures. Positions are 0-based, and the end of the pattern stands in for C's `'\0'`. Character classes use the C locale (bytes ≥ 128 are in no class). Only `gsub` needs `<k>` (for function and table replacements); `find`/`match`/`gmatch` are functions over the subject string.
- **`string.format`** (`lua-format.k`) reimplements glibc's `printf` for each conversion: flags `-+ #0`, width and precision (at most two digits each, as `scanformat` enforces, with the same error messages). Floats are formatted from the exact decimal expansion (`#decimal`, `#roundDigits` from `lua-number.k`), rounding ties to even like glibc. `%d`/`%i` cast to a C `long` by truncation, and `%u`/`%o`/`%x` to `unsigned long` (negative values wrap modulo 2^64).
- **String methods:** `#index(S:String, K)` goes straight to the string library (table 5). In M6 this becomes a real shared string metatable with `__index = string`, so that `getmetatable("")` works.
- **`gmatch` iterators** are a new function value, `gmatchIter(Id)`, with their state in `<iters>`.
- **Reference fix:** the committed `reference-output/printf.out` lacked the trailing newline that `lua tests/printf.lua` prints. It was regenerated with `make -B reference-output/printf.out`.
- **Constant-folding quirk again:** a literal `-0.0` also shares `0`'s constant slot in `lua`. Tests make negative zero at run time.

### M6 — Metatables and environments
`setmetatable`/`getmetatable` (including the `__metatable` protection), `__index` and `__newindex` (table or function, chained), `__call`, arithmetic events (`__add __sub __mul __div __mod __pow __unm`), `__concat`, `__eq` (only when both operands share the same handler), `__lt`, `__le` (falls back to `not __lt(b,a)`), `__tostring`, `rawget/rawset/rawequal`, and `getfenv`/`setfenv` with levels 0, 1 and 2 and with function arguments. Globals are read and written through the function's fenv table, so metatables on `_G` apply.
- `os.getenv` comes from a hook, or from an env map passed in as a config variable.
- Tests that turn green: most of `trace-globals` (it also needs `debug.getinfo(3,"Sl")` from M9). Add a deterministic `feature-env.lua` that uses `setmetatable(getfenv(), {__index=...})` without `os.getenv`.

**Status: done.** `make test` passes 13/17. The 4 left stop at `coroutine` (fibfor, sieve; M8) and `debug.getinfo`/`debug.sethook` (trace-globals, trace-calls; M9). `life` takes 268 s, up from about 250 s before metatable-aware indexing and stack-based globals. The new `tests/feature-metatables.lua`, which also covers the `feature-env.lua` idea, matches real Lua line for line. It covers `__index`/`__newindex` as tables, functions and chains, `rawget`/`rawset`/`rawequal`, OOP with inheritance, every arithmetic event from either side, `__unm`, `__concat` with strings on either side, `__eq` (only with a shared metamethod), `__lt`/`__le` and the `not (b < a)` fallback, `__call` (also in tail position), `__tostring` through `tostring` and `print`, `__metatable`, the string metatable, `getfenv`/`setfenv` by function and by level (including `setfenv(1, t)` from inside a running function), environments inherited by new closures, and `__index`/`__newindex` on the globals table. `trace-globals` now gets as far as `debug.getinfo` (M9). What M6 decided, for later milestones:
- **Environments:** there's no cached `<fenv>` any more. `<callStack>` holds `#frame(function, tail calls)` for every active Lua call, innermost first, and global reads and writes go through `#genv`, which is the environment of the innermost frame's closure, read from `<funcs>`. `setfenv` on a running function therefore takes effect immediately, as in Lua (`GETGLOBAL` reads `cl->env`). New closures take the creating function's environment. `<threadEnv>` is `getfenv(0)`; library functions see it, and `print` looks `tostring` up in it.
- **Stack levels** (`#level` in `lua-stdlib.k`) follow `lua_getstack`: level 1 is the innermost Lua frame, and a frame that replaced N tail calls stands for N more levels, where a lookup lands on a lost frame (`no function environment for tail call at level N`). Library functions aren't on `<callStack>`, so a level that would name a C function in `lua` names the next Lua function here. M9 has to push library frames too if `debug.getinfo`/hooks need `[C]` frames.
- **Tail calls:** only a Lua function replaces the caller's frame. A library function in tail position runs inside the caller's frame, as `OP_TAILCALL`/`luaD_precall` does it (found through `getfenv(2)` in a tail-called function).
- **Indexing** (`lua-config.k`) is `luaV_gettable`/`luaV_settable`: raw hit, else `__index`/`__newindex` (a function is called, anything else is indexed in turn), with a 100-level loop limit. A fast path keeps a present table field at one rewrite. `#getTM(V, event)` reads a metamethod raw from `#metaOf(V)`: a table's own metatable, `<strMeta>` (table 6, `{__index = string}`) for strings, nothing for other types (as there is no `debug.setmetatable`).
- **Operators** (`lua-eval.k`) fall back to metamethods as `lvm.c` does: `call_binTM` for arithmetic, `__unm` (called as `tm(a, a)`) and `__concat`; `get_compTM` for `__eq` (two different tables only); `call_orderTM` for `__lt`/`__le` (both operands must have the same metamethod; operands of different types are always an error). Calling a non-function uses `__call` with the callee as an extra first argument.
- **Not done:** `os.getenv` (env.lua, excluded; M9 with the rest of `os`). `__gc` and `__mode` have no effect (out of scope). `__len` applies only to userdata in 5.1, so it's correctly ignored.

### M7 — Errors
`error(msg, level)` with `"file:line: "` position prefixes, `pcall`, `xpcall`, `assert`, and runtime errors with 5.1's exact messages (`attempt to perform arithmetic on a nil value`, `attempt to index global 'x' (a nil value)`, `attempt to call …`, `attempt to compare …`). Uncaught errors print `lua: msg` plus a traceback to stderr. Comparisons only need stdout, so the traceback can be approximate.

### M8 — Coroutines
Multiple `<thread>` cells. Implement `coroutine.create/resume/yield/status/wrap/running`, passing values in both directions and propagating errors through `resume` (returns `false, msg`) and through `wrap` (re-raises). Also check status transitions (`suspended`, `running`, `normal`, `dead`) and resuming a dead coroutine.
- Tests that turn green: `fibfor`, `sieve` (also needs `math.mod`, a 5.1 alias of `fmod`).

### M9 — Remaining stdlib and the debug library
- **math:** `abs ceil floor sqrt sin cos tan asin acos atan atan2 exp log log10 pow fmod mod modf frexp ldexp huge pi min max random randomseed`.
- **os:** `clock time date getenv exit`.
- **io:** `write`, a minimal `read`, and `io.stdout:write`.
- **Base library:** `tonumber(s, base)`, `type`, `loadstring`/`load`/`dofile` (re-use the K parser through `#parse` or a parse hook; mark this as a stretch goal if that proves hard), and `collectgarbage` (a no-op that returns 0).
- **debug:** `getinfo` (fields `currentline short_src what name linedefined`, levels and the `"Sl"` options) and `sethook` with `"c"` and `"r"` events. This means firing a hook call around every function call and return, including builtins (`what = "C"`).
- Tests that turn green: `trace-calls`, `trace-globals`.

### M10 — Coverage beyond the given tests
Add focused tests (`tests/feature-*.lua`) for the parts the 15 programs never touch, each generated with `make generate`:
- `repeat` scope
- `for` loops with float or negative steps
- coercion edge cases
- long strings and escapes
- `%` with negatives (`a - floor(a/b)*b`)
- `^`
- `inf`/`nan` printing (`inf`, `-inf`, `nan`/`-nan`)
- every metamethod
- vararg edge cases
- `pcall` return shapes
- coroutine error paths
- every pattern feature
- string comparison (byte order)
- integer-valued float keys

### M11 — Verify the set-aside tests (later)
Pick a strategy for `env`, `fib` and `echo` once the rest is green. Candidate options, to be decided then:
- Generate both outputs on the same machine in the same run (real `lua` and `krun` back to back), so `$USER`/`$PATH` and `arg[0]` agree.
- Feed K a fixed environment through a config variable and regenerate the reference with the same values (`env -i USER=… PATH=… lua tests/env.lua`).
- For `fib`, mask the timing column before comparing (a filter step in `compare`), or check only the `value`/`evals` columns.

### Explicitly out of scope
Exact behavior that only shows up through garbage collection (`__gc`, weak tables via `__mode`, `collectgarbage` counts); `string.dump` and bytecode loading; real file I/O beyond stdout and stderr; `os.execute`/`remove`/`rename`; userdata; and printed addresses (`table: 0x…`). Addresses differ between runs anyway, so print something like `table: 0x<id>`.

## Files
- `src/lua.k` (later split into the modules above), `Makefile` (new targets `kompile`, `run-k`, `test`), `.gitignore` (`k-output/`), and new `tests/feature-*.lua` files with their `reference-output/*.out`.
- Reuse: `compare.lua` and the `compare` and `generate` targets as they are.

## Verification (every milestone)
1. Run `make kompile`; it must compile cleanly.
2. Run `make test`; `compare.lua` reports which files match. Each milestone's "tests that turn green" must match, and earlier ones must keep matching.
3. For syntax work, run `kast tests/X.lua` on every test.
4. For a new feature test, generate its expected output with real Lua 5.1.5 (`make generate`) before writing the K rules.
