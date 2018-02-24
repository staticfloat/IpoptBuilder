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
    BinaryProvider.Windows(:i686),
    BinaryProvider.Windows(:x86_64),
    BinaryProvider.Linux(:i686, :glibc),
    BinaryProvider.Linux(:x86_64, :glibc),
    BinaryProvider.Linux(:aarch64, :glibc),
    BinaryProvider.Linux(:armv7l, :glibc),
    # ppc64le isn't working right now....
    #BinaryProvider.Linux(:powerpc64le, :glibc),
    BinaryProvider.MacOS()
]

# The products that we will ensure are always built
products(prefix) = [
    LibraryProduct(prefix, "libipopt", :libipopt),
    ExecutableProduct(prefix, "ampl", :amplexe),
]

# Dependencies that must be installed before this package can be built
dependencies = [
]

# Parse out some command-line arguments
BUILD_ARGS = ARGS

# This sets whether we should build verbosely or not
verbose = "--verbose" in BUILD_ARGS
BUILD_ARGS = filter!(x -> x != "--verbose", BUILD_ARGS)

# This flag skips actually building and instead attempts to reconstruct a
# build.jl from a GitHub release page.  Use this to automatically deploy a
# build.jl file even when sharding targets across multiple CI builds.
only_buildjl = "--only-buildjl" in BUILD_ARGS
BUILD_ARGS = filter!(x -> x != "--only-buildjl", BUILD_ARGS)

if !only_buildjl
    # If the user passed in a platform (or a few, comma-separated) on the
    # command-line, use that instead of our default platforms
    if length(BUILD_ARGS) > 0
        platforms = platform_key.(split(BUILD_ARGS[1], ","))
    end
    info("Building for $(join(triplet.(platforms), ", "))")

    # Build the given platforms using the given sources
    autobuild(pwd(), "Ipopt", platforms, sources, script, products;
                              dependencies=dependencies, verbose=verbose)
else
    # If we're only reconstructing a build.jl file on Travis, grab the information and do it
    if !haskey(ENV, "TRAVIS_REPO_SLUG") || !haskey(ENV, "TRAVIS_TAG")
        error("Must provide repository name and tag through Travis-style environment variables!")
    end

    repo_name = ENV["TRAVIS_REPO_SLUG"]
    tag_name = ENV["TRAVIS_TAG"]
    product_hashes = product_hashes_from_github_release(repo_name, tag_name; verbose=verbose)
    bin_path = "https://github.com/$(repo_name)/releases/download/$(tag_name)"
    dummy_prefix = Prefix(pwd())
    print_buildjl(pwd(), products(dummy_prefix), product_hashes, bin_path)

    if verbose
        info("Writing out the following reconstructed build.jl:")
        print_buildjl(STDOUT, product_hashes; products=products(dummy_prefix), bin_path)
    end
end

