basedir = ${prefix}/share/openasip/hdb
nobase_base_DATA =	$(srcdir)/asic_130nm_1.5V.hdb \
					$(srcdir)/vhdl/fu/* \
					$(srcdir)/vhdl/rf/* \
					$(srcdir)/vhdl/pkg/* \
					$(srcdir)/stratixII.hdb \
					$(srcdir)/stratixII_vhdl/fpga_lsu/* \
					$(srcdir)/stratixII_vhdl/led_io/* \
					$(srcdir)/stratixII_vhdl/rtc/* \
					$(srcdir)/stratixII_vhdl/sram_lsu/* \
					$(srcdir)/avalon.hdb \
					$(srcdir)/avalon_hdb_vhdl/* \
					$(srcdir)/hibi_adapter.hdb \
					$(srcdir)/hibi_adapter_vhdl/* \
					$(srcdir)/stream.hdb \
					$(srcdir)/stream_vhdl/* \
					$(srcdir)/fpu_embedded.hdb \
					$(srcdir)/fpu_embedded_vhdl/* \
					$(srcdir)/sabrewing/* \
					$(srcdir)/fpu_half.hdb \
					$(srcdir)/fpu_half_vhdl/* \
					$(srcdir)/altera_jtag_uart.hdb \
					$(srcdir)/altera_jtag_uart_vhdl/* \
					$(srcdir)/stratixIII.hdb \
					$(srcdir)/stratixIII_vhdl/fpga_lsu/* \
					$(srcdir)/stratixIII_vhdl/led_io/* \
					$(srcdir)/stratixIII_vhdl/pushbutton/* \
					$(srcdir)/stratixIII_vhdl/rtc/* \
					$(srcdir)/stratixIII_vhdl/switch/* \
					$(srcdir)/almaif.hdb \
					$(srcdir)/generate_base32.hdb \
					$(srcdir)/generate_base32/verilog/* \
					$(srcdir)/generate_base32/vhdl/* \
					$(srcdir)/generate_base64.hdb \
					$(srcdir)/generate_lsu_32.hdb \
					$(srcdir)/generate_lsu_64.hdb \
					$(srcdir)/generate_lsu/*/ipxact/* \
					$(srcdir)/generate_lsu/*/vhdl/* \
					$(srcdir)/generate_lsu/*/verilog/* \
					$(srcdir)/generate_lsu/shared/* \
					$(srcdir)/generate_rf_iu.hdb \
					$(srcdir)/generate_rf_iu/verilog/* \
					$(srcdir)/almaif_vhdl/* \
					$(srcdir)/xilinx_series7.hdb \
					$(srcdir)/xilinx_vhdl/*
EXTRA_DIST = ${nobase_base_DATA}

# Generated HDBs must build before `make install` copies them to
# $(prefix)/share/openasip/hdb. Listing them in BUILT_SOURCES wires
# them into the default `make` target via the all-am dependency,
# so they come into existence during a plain `make` (not just when
# a downstream target happens to pull them in).

generate_lsu_32.hdb: generate_lsu/shared/* generate_lsu/generate.py
	cd generate_lsu; ./generate.py generate_lsu_32.hdb

generate_lsu_64.hdb: generate_lsu/shared/* generate_lsu/generate.py
	cd generate_lsu; ./generate.py generate_lsu_64.hdb

# generate_base64.py is self-contained: writes generate_base64.hdb +
# generate_base64/{vhdl,verilog}/*.v(hd) next to itself. Mirrors the
# generate_lsu split (HDB file + sibling dir of snippets) so
# nobase_base_DATA picks them both up.
generate_base64.hdb: generate_base64.py
	./generate_base64.py

# the implementation files alongside the HDB metadata.

# HDB-adjacent snippet dirs get their freshness from the same rules
# that produce the HDBs; express the dependency so the per-SoC
# verilog/vhdl snippet dirs are recognised as products by make.
generate_lsu/*/ipxact/* generate_lsu/*/vhdl/* generate_lsu/*/verilog/*: generate_lsu_32.hdb generate_lsu_64.hdb
generate_base64/verilog/* generate_base64/vhdl/*: generate_base64.hdb

clean:
	rm -rf generate_lsu_*.hdb generate_lsu/{32,64}
	rm -rf generate_base64.hdb generate_base64

# install-data-hook: copy the generate_base64 snippet dir at install
# time, after BUILT_SOURCES has populated it. Listing the snippet
# files via a `nobase_base_DATA = $(srcdir)/generate_base64/vhdl/*`
# glob doesn't work here: automake appears to evaluate the `vhdl/*`
# pattern at configure time and silently drops it when the parent
# dir doesn't exist yet (true for fresh clones, since we untrack
# every file under generate_base64/). The sibling `generate_lsu`
# glob works because its `shared/` subdir is tracked, giving
# automake a parent directory to anchor against at configure time.
# base64 has no shared/, so we bypass the globbing path entirely
# and install recursively from the live tree.
install-data-hook: generate_base64.hdb
	$(MKDIR_P) "$(DESTDIR)$(basedir)/generate_base64/vhdl" \
	           "$(DESTDIR)$(basedir)/generate_base64/verilog"
	cp "$(srcdir)"/generate_base64/vhdl/*.vhd \
	   "$(DESTDIR)$(basedir)/generate_base64/vhdl/"
	cp "$(srcdir)"/generate_base64/verilog/*.v \
	   "$(DESTDIR)$(basedir)/generate_base64/verilog/"
