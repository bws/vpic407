################################################################################
# PPE configure.ac
################################################################################
AC_INIT(VPIC_PPE, 3.1.2.1, bergen@lanl.gov)
AC_CONFIG_AUX_DIR(config)
VERSION_INFORMATION="-release 3.1.2.1 "
AC_SUBST(VERSION_INFORMATION)

################################################################################
# automake and libtool initialization
################################################################################
AM_INIT_AUTOMAKE
AC_PROG_LIBTOOL

################################################################################
# list targets for output
################################################################################
AC_CONFIG_FILES(Makefile \
	config/rules.mk \
	lib/Makefile \
	bin/Makefile \
	mprelay/Makefile \
	accelerator/Makefile \
	../../buildscript \
	../../vpic-build)

################################################################################
# append prefix with ppe
################################################################################
prefix=$prefix/ppe

################################################################################
# set absolute path to spe build directory
################################################################################
host_build_directory=`(cd ../..; pwd)`
host_ac_directory=`(cd $srcdir/../..; pwd)`
AC_SUBST(SPE_BUILDDIR, [$host_build_directory/cell/spe])
AC_SUBST(HOST_BUILDDIR, [$host_build_directory])
AC_SUBST(HOST_ACDIR, [$host_ac_directory])

################################################################################
# machine file specification
################################################################################
CCS_WITH_MACHINE("$host_ac_directory/machine")

################################################################################
# with options
################################################################################
CCS_WITH_BUILDSTYLE
CCS_WITH_ADDRESSING
CCS_WITH_PPU_COMPILER
CCS_WITH_LIBSPE2
CCS_WITH_SPU_MODULES

################################################################################
# enable options
################################################################################
CCS_ENABLE_OPENSSL
CCS_ENABLE_FFTW

################################################################################
# C/C++ configuration
################################################################################
AC_PROG_CC
CCS_TUNE_PCC
AC_PROG_CXX
CCS_TUNE_PCXX

################################################################################
# particle sorting
################################################################################
#case "$PARTICLE_SORT" in
#
#	in-place)
#		AC_DEFINE(IN_PLACE)
#	;;
#
#	out-of-place)
#		AC_DEFINE(OUT_OF_PLACE)
#	;;
#
#esac

################################################################################
# setup EXTRA
################################################################################
EXTRA_CPPFLAGS="$LIBSPE2_CPPFLAGS $TOOLCHAIN_CPPFLAGS $PPU_OPENSSL_CPPFLAGS"
EXTRA_LDFLAGS="$LIBSPE2_LDFLAGS $PPU_OPENSSL_LDFLAGS"
EXTRA_LIBS="$LIBSPE2_LIBS $PPU_OPENSSL_LIBS"

LIB_EXTENSION="ppu"
AC_SUBST(LIB_EXTENSION)

case "$buildstyle" in

	standard_cell)
		CCS_WITH_PPU_MPI

		AC_SUBST(PPEDIRS, ["lib bin"])

		EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_MPI_CPPFLAGS"
		EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_MPI_LDFLAGS"
		EXTRA_LIBS="$EXTRA_LIBS $PPU_MPI_LIBS"

		AC_DEFINE(CELL_PPU_BUILD)
		AC_DEFINE(USE_CELL_SPUS)
        use_cell_spus=true

		for file in "$SPU_MODULES" ; do
			EXTRA_O_FILES=${EXTRA_O_FILES}`echo emb-$file.o`
			EXTRA_LO_FILES=${EXTRA_LO_FILES}`echo emb-$file.lo`
		done
	;;

	standard_cell_ppe)
		CCS_WITH_PPU_MPI

		AC_SUBST(PPEDIRS, ["lib bin"])

		EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_MPI_CPPFLAGS"
		EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_MPI_LDFLAGS"
		EXTRA_LIBS="$EXTRA_LIBS $PPU_MPI_LIBS"

		AC_DEFINE(CELL_PPU_BUILD)
        use_cell_spus=false
	;;

	ompi_relay_cell)
		CCS_WITH_PPU_MPI

		AC_SUBST(PPEDIRS, ["lib  bin mprelay accelerator"])

		EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_MPI_CPPFLAGS"
		EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_MPI_LDFLAGS"
		EXTRA_LIBS="$EXTRA_LIBS $PPU_MPI_LIBS"

		AC_DEFINE(USE_MPRELAY)
		AC_DEFINE(USE_MPI_P2P)

		AC_DEFINE(CELL_PPU_BUILD)
		AC_DEFINE(USE_CELL_SPUS)
        use_cell_spus=true

		for file in "$SPU_MODULES" ; do
			EXTRA_O_FILES=${EXTRA_O_FILES}`echo emb-$file.o`
			EXTRA_LO_FILES=${EXTRA_LO_FILES}`echo emb-$file.lo`
		done
	;;

	ompi_relay_hybrid_cell)
		CCS_WITH_PPU_MPI

		AC_SUBST(PPEDIRS, ["lib bin accelerator"])

		EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_MPI_CPPFLAGS"
		EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_MPI_LDFLAGS"
		EXTRA_LIBS="$EXTRA_LIBS $PPU_MPI_LIBS"

		AC_DEFINE(USE_MPRELAY)
		AC_DEFINE(USE_MPI_P2P)

		AC_DEFINE(CELL_PPU_BUILD)
		AC_DEFINE(USE_CELL_SPUS)
        use_cell_spus=true

		for file in "$SPU_MODULES" ; do
			EXTRA_O_FILES=${EXTRA_O_FILES}`echo emb-$file.o`
			EXTRA_LO_FILES=${EXTRA_LO_FILES}`echo emb-$file.lo`
		done
	;;

	ompi_relay_hybrid_cell_ppe)
		CCS_WITH_PPU_MPI

		AC_SUBST(PPEDIRS, ["lib bin accelerator"])

		EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_MPI_CPPFLAGS"
		EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_MPI_LDFLAGS"
		EXTRA_LIBS="$EXTRA_LIBS $PPU_MPI_LIBS"

		AC_DEFINE(USE_MPRELAY)
		AC_DEFINE(USE_MPI_P2P)

		AC_DEFINE(CELL_PPU_BUILD)
        use_cell_spus=true
	;;

	dacs_relay_hybrid_cell)
		CCS_WITH_PPU_DACS(_hybrid)

		AC_SUBST(PPEDIRS, ["lib bin accelerator"])

		EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_DACS_CPPFLAGS"
		EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_DACS_LDFLAGS"
		EXTRA_LIBS="$EXTRA_LIBS $PPU_DACS_LIBS"

		AC_DEFINE(USE_MPRELAY)
		AC_DEFINE(USE_DACS_P2P)

		AC_DEFINE(CELL_PPU_BUILD)
		AC_DEFINE(USE_CELL_SPUS)
        use_cell_spus=true

		for file in "$SPU_MODULES" ; do
			EXTRA_O_FILES=${EXTRA_O_FILES}`echo emb-$file.o`
			EXTRA_LO_FILES=${EXTRA_LO_FILES}`echo emb-$file.lo`
		done
	;;

	dacs_relay_hybrid_cell_ppe)
		CCS_WITH_PPU_DACS(_hybrid)

		AC_SUBST(PPEDIRS, ["lib bin accelerator"])

		EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_DACS_CPPFLAGS"
		EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_DACS_LDFLAGS"
		EXTRA_LIBS="$EXTRA_LIBS $PPU_DACS_LIBS"

		AC_DEFINE(USE_MPRELAY)
		AC_DEFINE(USE_DACS_P2P)

		AC_DEFINE(CELL_PPU_BUILD)
        use_cell_spus=false
	;;

esac

if test "$enable_openssl" = "1" ; then
	CCS_WITH_PPU_OPENSSL
	EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_OPENSSL_CPPFLAGS"
	EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_OPENSSL_LDFLAGS"
	EXTRA_LIBS="$EXTRA_LIBS $PPU_OPENSSL_LIBS"
fi

if test "$enable_fftw" = "1" ; then
	CCS_WITH_PPU_FFTW
	EXTRA_CPPFLAGS="$EXTRA_CPPFLAGS $PPU_FFTW_CPPFLAGS"
	EXTRA_LDFLAGS="$EXTRA_LDFLAGS $PPU_FFTW_LDFLAGS"
	EXTRA_LIBS="$EXTRA_LIBS $PPU_FFTW_LIBS"
fi

AM_CONDITIONAL(USE_CELL_SPUS, $use_cell_spus)

# define needed for openmpi
AC_DEFINE(OMPI_SKIP_MPICXX)

AC_SUBST(EXTRA_CPPFLAGS)
AC_SUBST(EXTRA_LDFLAGS)
AC_SUBST(EXTRA_LIBS)

AC_SUBST(EXTRA_O_FILES)
AC_SUBST(EXTRA_LO_FILES)

################################################################################
# start output
################################################################################
AC_OUTPUT
