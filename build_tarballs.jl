using BinaryBuilder

# Collection of sources required to build Ipopt
sources = [
    "https://www.coin-or.org/download/source/Ipopt/Ipopt-3.12.8.tgz" =>
    "62c6de314220851b8f4d6898b9ae8cf0a8f1e96b68429be1161f8550bb7ddb03",

    # Ipopt 3.12.8 uses these particular BLAS/LAPACK/MUMPS dependencies
    "http://www.coin-or.org/BuildTools/Blas/blas-20130815.tgz" =>
    "ea87df6dc44829ee0a1733226d130c550b17a0bc51c8dbfcd662fb15520b23b5",
    "http://www.coin-or.org/BuildTools/Lapack/lapack-3.4.2.tgz" =>
    "60a65daaf16ec315034675942618a2230521ea7adf85eea788ee54841072faf0",
    "http://mumps.enseeiht.fr/MUMPS_4.10.0.tar.gz" =>
    "d0f86f91a74c51a17a2ff1be9c9cee2338976f13a6d00896ba5b43a5ca05d933",
    
    # ASL sources
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


# Install Third-Party sources as Ipopt desires...
cd $WORKSPACE/srcdir/Ipopt-*/ThirdParty
cp -r $WORKSPACE/srcdir/BLAS/*.f ./Blas/
cp -r $WORKSPACE/srcdir/lapack-* ./Lapack/LAPACK
cp -r $WORKSPACE/srcdir/MUMPS_* ./Mumps/MUMPS

# Next, install Ipopt
cd $WORKSPACE/srcdir/Ipopt-*

# The Ipopt buildsystem has a very old config.{sub,guess}.  Update those.
update_configure_scripts

# Build BLAS
(cd ThirdParty/Blas; \
    ./configure --prefix=$prefix --disable-shared --with-pic --host=$target; \
    make -j${nproc}; \
    make install)

# Build LAPACK
(cd ThirdParty/Lapack; \
    ./configure --prefix=$prefix --disable-shared --with-pic --host=$target; \
    make -j${nproc}; \
    make install)

(cd ThirdParty/Mumps; \
    patch -p0 < mumps.patch; \
    patch -p0 < mumps_mpi.patch; \
    mv MUMPS/libseq/mpi.h MUMPS/libseq/mumps_mpi.h; \
    ./configure --prefix=$prefix --disable-shared --with-pic --host=$target; \
    make -j${nproc}; \
    make install)

# Finally, build Ipopt itself.  Ipopt does some unusual things with pkg-config
# paths that don't play well with our definition of PKG_CONFIG_SYSROOT_DIR, so
# we have to define --with-mumps-incdir.  And we do so with extreme prejudice,
# and an extra helping of flag-injection hackiness.  We also need to give it
# asl since it doesn't know how to look for our updated asl automatically.
./configure --prefix=$prefix \
            lt_cv_deplibs_check_method=pass_all \
            --with-mumps-incdir="$(pwd)/ThirdParty/Mumps/MUMPS/include -I$(pwd)/ThirdParty/Mumps/MUMPS/libseq -DCOIN_USE_MUMPS_MPI_H" \
            --with-mumps-lib="-L$(pwd)/ThirdParty/Mumps/MUMPS/.libs -lcoinmumps" \
            --with-asl-lib="$prefix/lib/libasl.a" \
            --with-asl-incdir="$prefix/include/asl" \
            --host=$target
            
            #--with-blas="$prefix/lib/libcoinblas.a -lgfortran" \
            #--with-lapack="$prefix/lib/libcoinlapack.a" \

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
