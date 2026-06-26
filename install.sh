#!/bin/bash

GPUMKAT_VERSION="1.3"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or use sudo"
  exit
fi

cmake -B build && make -C build

install_dir="/usr/local/Cellar/gpumkat/$GPUMKAT_VERSION"

cmake --install build --prefix "$install_dir" --strip

cp README.md LICENSE "$install_dir/"

if [ -L "/usr/local/bin/gpumkat" ]; then
  rm "/usr/local/bin/gpumkat"
fi
ln -s "$install_dir/bin/gpumkat" "/usr/local/bin/gpumkat"

if [ -L "/usr/local/lib/libgpumkat.dylib" ]; then
  rm "/usr/local/lib/libgpumkat.dylib"
fi
ln -s "$install_dir/lib/libgpumkat.dylib" "/usr/local/lib/libgpumkat.dylib"

echo "Installation complete!"

