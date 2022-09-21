MOC ?= moc
WASMTIME_OPTIONS = --disable-cache

OUTDIR=_out

TESTS = $(wildcard *.mo)

TEST_TARGETS = $(patsubst %.mo,_out/%.checked,$(TESTS))

all: $(TEST_TARGETS) 

VESSEL_PKGS= $(shell vessel sources)

$(OUTDIR):
	@mkdir $@

$(OUTDIR)/%.wasm: %.mo | $(OUTDIR)
	$(MOC) -c $(VESSEL_PKGS) -wasi-system-api -o $@ $<

$(OUTDIR)/%.checked: $(OUTDIR)/%.wasm
	wasmtime run $(WASMTIME_OPTIONS) $<
	touch $@

clean:
	rm -rf $(OUTDIR)

.PRECIOUS: $(OUTDIR)/%.wasm
