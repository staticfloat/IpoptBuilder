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
]

script = raw"""
cd $WORKSPACE/srcdir/Ipopt-3.12.8
./configure --prefix=/ --host=$target
make -j3
make install
"""

products = prefix -> [
  LibraryProduct(prefix,"libipopt"),
]

product_hashes = Dict()
autobuild(pwd(), "Ipopt", platforms, sources, script, products, product_hashes)
print_buildjl(product_hashes)
