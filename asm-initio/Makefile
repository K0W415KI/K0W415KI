# ASM Initio -- solo necesita nasm y ld (binutils). Nada se linkea.
NASM    ?= nasm
LD      ?= ld
BUILD   := build
BIN     := $(BUILD)/asminitio

all: $(BIN)

SRC     := $(wildcard src/*.asm) src/defs.inc src/fonts.inc $(wildcard src/*.bin)

$(BUILD)/asminitio.o: $(SRC) | $(BUILD)
	$(NASM) -f elf64 -I src/ src/main.asm -o $@

$(BIN): $(BUILD)/asminitio.o
	$(LD) -s -o $@ $<

$(BUILD):
	mkdir -p $@

# Regenera las fuentes bitmap (requiere Python + Pillow; no hace falta para compilar)
fonts:
	python3 tools/genfont.py src

run: $(BIN)
	./$(BIN)

clean:
	rm -rf $(BUILD)

.PHONY: all fonts run clean
