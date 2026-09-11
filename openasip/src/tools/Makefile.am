noinst_LTLIBRARIES = libopenasiptools.la

# This should be always regenerated during a build and not
# distributed.
nodist_libopenasiptools_la_SOURCES = tce_version_string.h
BUILT_SOURCES = tce_version_string.h

libopenasiptools_la_SOURCES = Exception.cc CmdLineOptions.cc CmdLineOptionParser.cc \
	Environment.cc Application.cc XMLSerializer.cc ObjectState.cc \
	FileSystem.cc DOMBuilderErrorHandler.cc TextGenerator.cc \
	PluginTools.cc Conversion.cc StringTools.cc DataObject.cc SimValue.cc \
	ConfigurationFile.cc ProcessorConfigurationFile.cc Listener.cc \
	Informer.cc Options.cc OptionValue.cc CmdLineParser.cc MathTools.cc \
	BitMatrix.cc TCEString.cc HalfFloatWord.cc \
	RandomNumberGenerator.cc CompileTools.cc \
	LLVMIRTools.cc Reversible.cc IPXact.cc \
	LicenseGenerator.cc

if HAVE_SQLITE
  libopenasiptools_la_SOURCES += SQLiteConnection.cc RelationalDBQueryResult.cc \
	SQLiteQueryResult.cc SQLite.cc RelationalDBConnection.cc RelationalDB.cc
  libopenasiptools_la_LDFLAGS = ${SQLITE_LD_FLAGS} ${BOOST_LDFLAGS}
endif

PROJECT_ROOT = $(top_srcdir)
DOXYGEN_CONFIG_FILE = ${PROJECT_ROOT}/tools/Doxygen/doxygen.config
AM_CPPFLAGS = -I${PROJECT_ROOT} -I${PROJECT_ROOT}/src/base/memory \
    -I${PROJECT_ROOT}/src/bintools/Compiler/llvm-tce/ \
    -I$(PROJECT_ROOT)/src/applibs/Scheduler/Algorithms/ \
    -I$(PROJECT_ROOT)/src/base/mach \
    -I$(PROJECT_ROOT)/src/base/program \
    -I$(PROJECT_ROOT)/src/base/osal \
	-I$(PROJECT_ROOT)/src/base/idf \
	-I$(PROJECT_ROOT)/src/base/Graph \
	-I$(PROJECT_ROOT)/src/applibs/ProGe \
	-I$(PROJECT_ROOT)/src/applibs/hdb \
	-I$(PROJECT_ROOT)/src/applibs/Explorer \
	-I$(PROJECT_ROOT)/src/applibs/dsdb \
	-I$(PROJECT_ROOT)/src/applibs/Simulator \
	-I$(PROJECT_ROOT)/src/applibs/Estimator \
	-I$(PROJECT_ROOT)/src/procgen/ProGe \
	-I${PROJECT_ROOT}/src/applibs/LLVMBackend/
AM_LDFLAGS = -L../bintools/Compiler/llvm-tce/

include_HEADERS = Application.hh ObjectState.hh Exception.hh Exception.icc BaseType.hh \
	SimValue.hh Serializable.hh ObjectState.icc Conversion.hh \
	Conversion.icc MathTools.hh MathTools.icc TCEString.hh TCEString.icc \
	CmdLineOptions.hh CmdLineParser.hh CmdLineParser.icc StringTools.hh \
	CmdLineOptionParser.hh CmdLineOptionParser.icc MapTools.hh MapTools.icc \
	CIStringSet.hh ContainerTools.hh ContainerTools.icc Listener.hh \
	Informer.hh Informer.icc HalfFloatWord.hh tce_config_public.h \
	CompilerWarnings.hh SystemMacroCleanup.hh Environment.hh \
	RandomNumberGenerator.hh \
	LicenseGenerator.hh RISCVTools.hh \
	RISCVTools.icc

# NOTE: do not use `echo -n` here -- it is not POSIX, and the /bin/sh that
# $(shell ...) runs under on macOS prints the flags literally, which produced
# "-n -r" in the version string. macOS's `wc -l` also pads its output with
# leading spaces, so strip them. See the matching fix at configure.ac:10.
REVNO=$(shell if git rev-list HEAD >/dev/null 2>&1; then printf -- "-r%s" "$$(git rev-list HEAD | wc -l | tr -d ' ')"; fi)

TCE_VERSION_STRING=@PACKAGE_VERSION@$(REVNO)

# ⛔ $(wildcard), NOT A BARE PATH. `tce_version_string.h: ../../../.git` makes the
#    build IMPOSSIBLE in any tree without a .git — a source tarball, an exported
#    tree, or our public cut — with "No rule to make target '../../../.git'".
#    Nothing else in the build needs git, so this single prerequisite is the only
#    thing tying a source build to a working copy.
# ⚠ THE PATH IS DELIBERATELY LEFT AS ../../../.git RATHER THAN $(top_srcdir)/.git.
#   $(top_srcdir) here is openasip/, so $(top_srcdir)/.git is openasip/.git — which
#   exists in NEITHER upstream's layout nor ours. It would silently drop the
#   revision from the version string rather than fail, so the tidier form is the
#   dangerous one. ../../../.git resolves to the REPO ROOT's .git, which is where
#   it actually lives.
#   ⛔ AND THE REASON IS NOT "the two layouts differ but happen to coincide" — an
#      earlier version of this comment claimed that and it was WRONG. Measured at
#      f2282048f: upstream's repo root is .github/.gitignore/CONTRIBUTING.md/
#      LICENSE.txt/README.md/openasip/testsuite, and openasip/src/tools/Makefile.am
#      exists there at that same path. UPSTREAM NESTS openasip/ EXACTLY AS WE DO,
#      so the path works identically because THE LAYOUTS ARE THE SAME. Recorded
#      because the wrong reason is the part that gets reused: anyone carrying
#      "upstream's openasip is the repo root" forward will mis-derive the next path.
#      Caught by the Linux seat while confirming the fix, not while disputing it.
# Wrapping preserves today's behaviour exactly where .git exists and only removes
# the prerequisite where it does not.
tce_version_string.h: $(wildcard ../../../.git)
	@echo "Setting TCE_VERSION_STRING to $(TCE_VERSION_STRING)"
	@echo '#define TCE_VERSION_STRING "$(TCE_VERSION_STRING)"' > $@

# A hack, we'll see if something breaks.
../../../.bzr/branch/last-revision:
	@echo "Not compiling in a bazaar branch"

## headers start
libopenasiptools_la_SOURCES += \
	BitMatrix.hh RelationalDBQueryResult.hh \
	MathTools.hh OptionValue.hh \
	CIStringSet.hh hash_set.hh \
	DOMBuilderErrorHandler.hh VectorTools.hh \
	StringTools.hh Serializer.hh \
	PluginTools.hh SequenceTools.hh \
	PagedArray.hh HalfFloatWord.hh \
	SQLiteQueryResult.hh Exception.hh \
	SparseVectorMap.hh ConfigurationFile.hh \
	CmdLineOptionParser.hh ProcessorConfigurationFile.hh \
	RelationalDB.hh DBTypes.hh \
	ContainerTools.hh TextGenerator.hh \
	SimValue.hh hash_map.hh \
	SQLite.hh XMLSerializer.hh \
	SetTools.hh SQLiteConnection.hh \
	TCEString.hh DataObject.hh \
	Serializable.hh ObjectState.hh \
	Application.hh MapTools.hh \
	Options.hh CmdLineOptions.hh \
	Conversion.hh RelationalDBConnection.hh \
	FileSystem.hh Environment.hh \
	Informer.hh Listener.hh \
	CmdLineParser.hh BaseType.hh \
	AssocTools.hh CmdLineOptionParser.icc \
	Exception.icc Conversion.icc \
	DataObject.icc PluginTools.icc \
	MapTools.icc MathTools.icc \
	CmdLineParser.icc SequenceTools.icc \
	PagedArray.icc ObjectState.icc \
	AssocTools.icc FileSystem.icc \
	ContainerTools.icc BitMatrix.icc \
	TCEString.icc SetTools.icc \
	Informer.icc VectorTools.icc \
	RandomNumberGenerator.hh CompileTools.hh\
	LLVMIRTools.hh \
	LicenseGenerator.hh RISCVTools.hh \
	RISCVTools.icc 

## headers end
