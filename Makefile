

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