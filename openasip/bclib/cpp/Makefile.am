srclib_datadir = ${prefix}/share/openasip/srclibs/
srclib_data_DATA = libcpp.sa

src_datadir = ${srclib_datadir}/cpp
src_data_DATA =  exception_handling.c terminate.cc


# Soft-float conversion wrappers for 64-bit TTA. Linked by oacc when the
# target is 64-bit and software floating point is in use.
srclib_data_DATA += libsoftfloat.sa
src_data_DATA += softfloat_wrappers.c
