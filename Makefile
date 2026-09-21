NASM ?= nasm

.PHONY: all clean test audit

all: dist/PRE2GUS.COM dist/INSTALL.COM

dist/PRE2GUS.COM: src/pre2gus.asm
	mkdir -p dist
	$(NASM) -Wall -f bin -o $@ $<

dist/INSTALL.COM: tools/install_dos.asm
	mkdir -p dist
	$(NASM) -Wall -f bin -o $@ $<

test:
	python3 -m unittest discover -s tests -v

audit:
	python3 tools/audit_repository.py .

clean:
	rm -f dist/PRE2GUS.COM dist/INSTALL.COM
