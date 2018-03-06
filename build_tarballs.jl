using BinaryBuilder

# Collection of sources required to build Ipopt
sources = [
    "https://www.coin-or.org/download/source/Ipopt/Ipopt-3.12.8.tgz" =>
    "62c6de314220851b8f4d6898b9ae8cf0a8f1e96b68429be1161f8550bb7ddb03",
    "https://github.com/ampl/mp/archive/3.1.0.tar.gz" =>
    "587c1a88f4c8f57bef95b58a8586956145417c8039f59b1758365ccc5a309ae9",
    "https://github.com/staticfloat/mp-extra/archive/v3.1.0-2.tar.gz" =>
    "2f227175437f73d9237d3502aea2b4355b136e29054267ec0678a19b91e9236e",
]

# Bash recipe for building across all platforms
script = raw"""
set -e

# First, install ASL
cd $WORKSPACE/srcdir/mp-3.1.0

# Remove benchmarking library (this is already done on the latest
# ampl/mp master branch, but we don't use that, so backport the removal)
rm -rf thirdparty/benchmark
patch -p1 < $WORKSPACE/srcdir/mp-extra-3.1.0-2/no_benchmark.patch

# Build ASL
mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX=$prefix \
      -DCMAKE_TOOLCHAIN_FILE=/opt/$target/$target.toolchain \
      -DRUN_HAVE_STD_REGEX=0 \
      -DRUN_HAVE_STEADY_CLOCK=0 \
      ../

# Copy over pregenerated files after building arithchk, so as to fake out cmake,
# because cmake will delete our arith.h
make arithchk VERBOSE=1
mkdir -p src/asl
cp -v $WORKSPACE/srcdir/mp-extra-3.1.0-2/expr-info.cc ../src/expr-info.cc
cp -v $WORKSPACE/srcdir/mp-extra-3.1.0-2/arith.h.${target} src/asl/arith.h

# Build and install ASL
make -j${nproc} VERBOSE=1
make install VERBOSE=1

# Next, install Ipopt
cd $WORKSPACE/srcdir/Ipopt-3.12.8

# The Ipopt buildsystem has a very old config.{sub,guess}.  Update those.
curl -L 'http://git.savannah.gnu.org/cgit/config.git/plain/config.guess' > config.guess
curl -L 'http://git.savannah.gnu.org/cgit/config.git/plain/config.sub' > config.sub

# Get BLAS
(cd ThirdParty/Blas; \
    ./get.Blas; \
    cp ../../config.guess .; \
    cp ../../config.sub .; \
    ./configure --prefix=$prefix --disable-shared --with-pic --host=$target; \
    make -j${nproc}; \
    make install)

# Get LAPACK
(cd ThirdParty/Lapack; \
    ./get.Lapack; \
    cp ../../config.guess .; \
    cp ../../config.sub .; \
    ./configure --prefix=$prefix --disable-shared --with-pic --host=$target; \
    make -j${nproc}; \
    make install)

# Download a much newer version of ASL than we would otherwise get through Ipopt
(cd ThirdParty/Mumps; \
    ./get.Mumps; \
    cp ../../config.guess .; \
    cp ../../config.sub .)

# Finally, build Ipopt itself.  For some strange reason, Ipopt's build
# system doesn't like to find cross-compiled static libraries, so it
# must be coerced into using them via  `--with-blas` and `--with-lapack`.
./configure --prefix=$prefix \
            --with-blas="$prefix/lib/libcoinblas.a -lgfortran" \
            --with-lapack="$prefix/lib/libcoinlapack.a" \
            --with-asl-lib="$prefix/lib/libasl.a" \
            --with-asl-incdir="$prefix/include/asl" \
            lt_cv_deplibs_check_method=pass_all \
            --host=$target
make -j${nproc}
make install
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line.
platforms = [
    Windows(:i686),
    Windows(:x86_64),
    Linux(:i686, :glibc),
    Linux(:x86_64, :glibc),
    Linux(:aarch64, :glibc),
    Linux(:armv7l, :glibc),
    # ppc64le isn't working right now....
    #Linux(:powerpc64le, :glibc),
    MacOS()
]

# The products that we will ensure are always built
products(prefix) = [
    LibraryProduct(prefix, "libipopt", :libipopt),
    ExecutableProduct(prefix, "ipopt", :amplexe),
]

# Dependencies that must be installed before this package can be built
dependencies = [
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, "Ipopt", sources, script, platforms, products, dependencies)