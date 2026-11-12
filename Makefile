# Standalone checker. Other projects run the binary on their own C tree.
NIM ?= nim
OUT := build/cite
SRCS := src/cite.nim src/lex.nim src/rules.nim src/check.nim

.PHONY: all clean test
all: $(OUT)

$(OUT): $(SRCS)
	mkdir -p build
	$(NIM) c --hints:off -d:release -o:$@ src/cite.nim

test: $(OUT)
	$(OUT) --self-test

clean:
	rm -rf build
