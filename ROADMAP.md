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
- **Modules:** split `src/lua.k` into `lua-syntax.k`, `lua-config.k`, `lua-values.k`, `lua-semantics.k`, `lua-stdlib.k`, `lua-string-format.k` and `lua-coroutines.k`. `lua.k` imports them all. A single file is also fine until about M4.
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
- **Source positions:** `debug.getinfo().currentline` and `short_src` are needed by `trace-globals`/`trace-calls` and by error messages. Use K's `[locations]` attribute on the statement and expression sorts so terms carry `#location(..., File, Line, ...)`. A rule records the current line as it executes.

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
- Done when: `kast` parses all 15 tests plus a grammar stress file (`tests/syntax-*.lua`).

### M2 — Core evaluation
Literals, arithmetic, string↔number coercion, comparison, `and`/`or` short-circuit returning operands, `not`, `..`, `==` (by reference for tables and functions), globals in `_G`, locals with block scoping, `if`/`while`/`repeat` (the `until` condition sees the body's locals), `break`, and numeric `for` (start, limit and step evaluated once; hidden control variable; fresh local each iteration; float steps).
- **Number→string:** `tostring` uses `%.14g`. Check early whether K's `Float2String(Float, String)` format hook exists in v7.1. If not, write `%g` formatting in K.
- **Builtins:** `print` (tab-separated, uses `tostring`), `io.write` (numbers formatted with `%.14g`), `_VERSION = "Lua 5.1"`.
- Tests that turn green: `hello`, `factorial2`.

### M3 — Functions, closures, multiple values
Function definitions, calls, upvalues (shared Locs), recursion, method sugar `:`, varargs `...`, `select('#',…)`, `unpack`, multiple assignment (evaluate everything, then assign), multiple returns with adjustment, tail calls (no stack growth), and the 5.1 `arg` table in vararg functions (`LUA_COMPAT_VARARG`).
- Tests that turn green: `factorial` (Y combinator), `bisect` once M5's `string.format` lands.

### M4 — Tables
Constructors, `t[k]`/`t.k` get and set, float keys normalized (`1.0` ≡ `1`), `nil`/NaN key errors, assigning `nil` deletes, `#t` (border; match 5.1's array-part behavior on the tests), `next`/`pairs`/`ipairs`, and `table.getn/insert/remove/concat/sort` (`sort` with a comparator).
- Tests that turn green: `sort` (`math.random` only picks pivots, so any PRNG gives the same output), `life` (also a performance check).

### M5 — String library and `string.format`
- **`string.format`:** a format-spec parser for `%d %i %s %q %c %x %X %o %e %E %f %g %G %%`, with flags, width and precision (`%3.0f`, `%.17g`, `%.1e`).
- **Other functions:** `len sub upper lower rep reverse byte char`. The string metatable (`("x"):rep(3)`, `s:sub`).
- **Lua patterns:** `find match gmatch gsub`, implemented as a small backtracking matcher in K. This is a sizable sub-project: character classes `%a %d %s %w %p %l %u %c %x`, sets `[...]`, quantifiers `* + - ?`, anchors, captures including position captures, `%b`, and `%f` (undocumented in 5.1).
- Tests that turn green: `printf`, `cf`, `bisect`.

### M6 — Metatables and environments
`setmetatable`/`getmetatable` (including the `__metatable` protection), `__index` and `__newindex` (table or function, chained), `__call`, arithmetic events (`__add __sub __mul __div __mod __pow __unm`), `__concat`, `__eq` (only when both operands share the same handler), `__lt`, `__le` (falls back to `not __lt(b,a)`), `__tostring`, `rawget/rawset/rawequal`, and `getfenv`/`setfenv` with levels 0, 1 and 2 and with function arguments. Globals are read and written through the function's fenv table, so metatables on `_G` apply.
- `os.getenv` comes from a hook, or from an env map passed in as a config variable.
- Tests that turn green: most of `trace-globals` (it also needs `debug.getinfo(3,"Sl")` from M9). Add a deterministic `feature-env.lua` that uses `setmetatable(getfenv(), {__index=...})` without `os.getenv`.

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
