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

dependencies = [
    "https://raw.githubusercontent.com/staticfloat/OpenBLASBuilder/master/build.jl",
]

sources = [
    "https://www.coin-or.org/download/source/Ipopt/Ipopt-3.12.8.tgz" =>
    "62c6de314220851b8f4d6898b9ae8cf0a8f1e96b68429be1161f8550bb7ddb03",
]

script = """
cd \$WORKSPACE/srcdir/Ipopt-3.12.8
./configure --prefix=/ --with-blas-lib="-L$(libdir(Prefix("\$DESTDIR")))" --host=\$target
make -j3
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


autobuild(pwd(), "Ipopt", build_platforms, sources, script, products;
          dependencies=dependencies, verbose=verbose)
