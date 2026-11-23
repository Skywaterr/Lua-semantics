

SRCS := $(wildcard tests/*.lua)
OBJS := $(patsubst tests/%.lua,reference-output/%.out,$(SRCS))

.PHONY: generate clean compare

# Execute each .lua file in tests and shove the output into
# a corresponding .out file in reference-output of the same name.
generate: $(OBJS)

#compare:
#	lua compare.lua

reference-output/%.out: tests/%.lua | reference-output
	lua "$<" > "$@"

reference-output:
	mkdir -p reference-output

clean:
	rm -rf reference-output