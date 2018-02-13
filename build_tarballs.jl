using BinaryBuilder

platforms = [
  BinaryProvider.Windows(:i686),
  BinaryProvider.Windows(:x86_64),
  BinaryProvider.Linux(:i686, :glibc),
  BinaryProvider.Linux(:x86_64, :glibc),

  # It appears that aarch64 isn't recognized by Ipopt's build system
  BinaryProvider.Linux(:aarch64, :glibc),
  BinaryProvider.Linux(:armv7l, :glibc),
  BinaryProvider.Linux(:powerpc64le, :glibc),
  
  BinaryProvider.MacOS()
]

sources = [
    "https://www.coin-or.org/download/source/Ipopt/Ipopt-3.12.8.tgz" =>
    "62c6de314220851b8f4d6898b9ae8cf0a8f1e96b68429be1161f8550bb7ddb03",
]

script = raw"""
cd $WORKSPACE/srcdir/Ipopt-3.12.8

# Get BLAS
(cd ThirdParty/Blas; \
    ./get.Blas; \
    ./configure --prefix=$prefix --disable-shared --with-pic --host=$target; \
    make -j${nproc}; \
    make install)

# Get LAPACK
(cd ThirdParty/Lapack; \
    ./get.Lapack; \
    ./configure --prefix=$prefix --disable-shared --with-pic --host=$target; \
    make -j${nproc}; \
    make install)

#(cd ThirdParty/ASL; ./get.ASL)
(cd ThirdParty/Mumps; ./get.Mumps)

# The Ipopt buildsystem blows up if we use a full path to our AR.
# By default it is using a tripleted name, so this doesn't actually change anything.
export AR=$(basename $AR)

# Finally, build Ipopt itself.  For some strange reason, Ipopt's build
# system doesn't like to find cross-compiled static libraries, so it
# must be coerced into using them via  `--with-blas` and `--with-lapack`.
./configure --prefix=$prefix --with-blas="$prefix/lib/libcoinblas.a -lgfortran" --with-lapack="$prefix/lib/libcoinlapack.a" lt_cv_deplibs_check_method=pass_all --host=$target
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
