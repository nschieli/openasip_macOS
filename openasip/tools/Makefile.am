datadir = ${prefix}/share/openasip

# generate_dasm.py / generate_srcmap.py produce the debug-daemon's sidecars
# (<tpef>.dasm, <tpef>.srcmap). They must ship with the toolchain, not with a
# client: their output format is locked to what openasip-debug-daemon
# auto-discovers, and they wrap tcedisasm, so both the producer's dependency and
# its consumer are installed here. Before this they lived only in the source
# tree, which worked when the MCP server ran from a repo checkout and breaks the
# moment anything drives the debugger from an installed toolchain.
nobase_data_DATA = ${srcdir}/scripts/install_llvm_*.sh \
	${srcdir}/scripts/generate_dasm.py \
	${srcdir}/scripts/generate_srcmap.py \
	${srcdir}/patches/*.patch

EXTRA_DIST = ${nobase_data_DATA}

install-data-hook: $(pkgdata_SCRIPTS)
	chmod +x $(DESTDIR)/${datadir}/scripts/*

