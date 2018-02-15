using BinaryBuilder

platforms = [
  BinaryProvider.Windows(:i686),
  BinaryProvider.Windows(:x86_64),
  BinaryProvider.Linux(:i686, :glibc),
  BinaryProvider.Linux(:x86_64, :glibc),
  BinaryProvider.Linux(:aarch64, :glibc),
  BinaryProvider.Linux(:armv7l, :glibc),
  BinaryProvider.Linux(:powerpc64le, :glibc),
  BinaryProvider.MacOS()
]

sources = [
    "https://www.coin-or.org/download/source/Ipopt/Ipopt-3.12.8.tgz" =>
    "62c6de314220851b8f4d6898b9ae8cf0a8f1e96b68429be1161f8550bb7ddb03",
    "https://github.com/ampl/mp/archive/3.1.0.tar.gz" =>
    "587c1a88f4c8f57bef95b58a8586956145417c8039f59b1758365ccc5a309ae9",
    "https://github.com/staticfloat/mp-extra/archive/v3.1.0-1.tar.gz" =>
    "941ce01d1e86edc7a1fe5eed55aedbc214e9454336c96074d7318d71a14ab5f0",
]

script = raw"""
set -e

# First, install ASL
cd $WORKSPACE/srcdir/mp-3.1.0

# Remove benchmarking library
rm -rf thirdparty/benchmark
patch -p1 < $WORKSPACE/srcdir/mp-extra-3.1.0-1/no_benchmark.patch

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
make arithchk
mkdir -p src/asl
cp -v $WORKSPACE/srcdir/mp-extra-3.1.0-1/expr-info.cc ../src/expr-info.cc
cp -v $WORKSPACE/srcdir/mp-extra-3.1.0-1/arith.h.${target} src/asl/arith.h
make arith-h

# Build and install ASL
make -j${nproc}
make install

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

# The Ipopt buildsystem blows up if we use a full path to our AR.
# By default it is using a tripleted name, so this doesn't actually change anything.
export AR=$(basename $AR)

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

products = prefix -> [
  LibraryProduct(prefix,"libipopt"),
]

# Be quiet unless we've passed `--verbose`
verbose = "--verbose" in ARGS
ARGS = filter!(x -> x != "--verbose", ARGS)

# Choose which platforms to build for; if we've got an argument use that one,
# otherwise default to just building all of them!
build_platforms = platforms
if length(ARGS) > 0
    build_platforms = platform_key.(split(ARGS[1], ","))
end
info("Building for $(join(triplet.(build_platforms), ", "))")


autobuild(pwd(), "Ipopt", build_platforms, sources, script, products; verbose=verbose)
