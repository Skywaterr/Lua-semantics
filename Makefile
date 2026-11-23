

SRCS := $(wildcard tests/*.lua)
OBJS := $(patsubst tests/%.lua,reference-output/%.out,$(SRCS))

.PHONY: generate clean compare

# Execute each .lua file in tests and shove the output into
# a corresponding .out file in reference-output of the same name.
generate: $(OBJS)

DIR1 ?= compare-test-output
DIR2 ?= reference-output

# Compare two directories for matching files and file contents.
# Defaults to running the test directory for the compare script.
# Change by running make compare DIR1=your_folder
compare:
	lua compare.lua "$(DIR1)" "$(DIR2)"

reference-output/%.out: tests/%.lua | reference-output
	lua "$<" > "$@"

reference-output:
	mkdir -p reference-output

clean:
	rm -rf reference-output

# ---------------------------------------------------------------------------
# K semantics (see ROADMAP.md)
# ---------------------------------------------------------------------------

K_DEF    := src/lua.k
KOMPILED := src/lua-kompiled
K_OUT    := k-output
K_LOGS   := k-logs

# Tests whose output depends on the machine or on timing. They are left out
# of run-k/test until ROADMAP.md milestone M11 decides how to verify them.
EXCLUDE  := env fib echo

K_SRCS := $(filter-out $(patsubst %,tests/%.lua,$(EXCLUDE)),$(SRCS))
K_OUTS := $(patsubst tests/%.lua,$(K_OUT)/%.out,$(K_SRCS))

# Grammar-only test programs, parsed by `make parse` but never run.
SYNTAX_SRCS := $(wildcard tests/syntax/*.lua)

.PHONY: kompile parse run-k test clean-k

# Compile the semantics. Rebuilds only when a .k file changes.
kompile: $(KOMPILED)/timestamp

$(KOMPILED)/timestamp: $(wildcard src/*.k)
	kompile $(K_DEF) --backend llvm -o $(KOMPILED)

# Parse every test program (including the excluded ones) and every
# tests/syntax/*.lua file. Fails if any of them does not parse.
parse: kompile
	@fail=0; \
	for f in $(SRCS) $(SYNTAX_SRCS); do \
		if scripts/klua --parse "$$f"; then echo "parse ok    $$f"; \
		else echo "parse FAIL  $$f"; fail=1; fi; \
	done; \
	exit $$fail

# Run every non-excluded test with scripts/klua. Program output goes to
# k-output/NAME.out, klua's stderr (with the final configuration if the run
# got stuck) to k-logs/NAME.err. A failing run leaves its (possibly partial)
# .out in place so compare counts it as failed.
run-k: $(K_OUTS)

$(K_OUT)/%.out: tests/%.lua $(KOMPILED)/timestamp | $(K_OUT) $(K_LOGS)
	@scripts/klua "$<" > "$@" 2> "$(K_LOGS)/$*.err" \
		|| echo "run failed: $< (see $(K_LOGS)/$*.err)"

# Run the semantics on the tests and compare against reference-output.
test: run-k
	@$(MAKE) --no-print-directory compare DIR1=$(K_OUT) DIR2=reference-output

$(K_OUT) $(K_LOGS):
	mkdir -p $@

clean-k:
	rm -rf $(K_OUT) $(K_LOGS)
