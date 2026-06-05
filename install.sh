#!/bin/bash

cmake -B build && make -C build     

GPUMKAT_VERSION="1.22"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or use sudo"
  exit
fi

files_to_copy=("build/gpumkat" "build/libgpumkat.dylib" "include" \
    "README.md" "LICENSE" "gpumkat_icon.png" \
    "gpumkat_logs.png")

install_dir="/usr/local/Cellar/gpumkat/$GPUMKAT_VERSION"

mkdir -p "$install_dir/lib" "$install_dir/include" \
    "$install_dir/bin"

for item in "${files_to_copy[@]}"; do
  if [ -d "$item" ]; then
    if [ "$item" == "include" ]; then
      if [ -d "$install_dir/include/gpumkat" ]; then
        rm -rf "$install_dir/include/gpumkat"
        echo "Deleted existing directory \
$install_dir/include/gpumkat"
      fi
      cp -r "$item" "$install_dir/include/gpumkat/"

      if [ $? -eq 0 ]; then
        echo "Directory $item copied successfully to \
$install_dir/include/gpumkat"
      else
        echo "Failed to copy the directory $item"
      fi
    else
      cp -r "$item" "$install_dir/"

      if [ $? -eq 0 ]; then
        echo "Directory $item copied successfully to \
$install_dir"
      else
        echo "Failed to copy the directory $item"
      fi
    fi
  elif [ -f "$item" ]; then
    if [ "$item" == "gpumkat" ]; then
      if [ -L "/usr/local/bin/gpumkat" ]; then
        rm "/usr/local/bin/gpumkat"
        echo "Deleted existing symbolic link \
/usr/local/bin/gpumkat"
      fi

      if [ -f "$install_dir/bin/$item" ]; then
        rm "$install_dir/bin/$item"
        echo "Deleted existing file $install_dir/bin/$item"
      fi
      cp "$item" "$install_dir/bin/"

      if [ $? -eq 0 ]; then
        echo "Executable $item copied successfully to \
$install_dir/bin"
      else
        echo "Failed to copy the executable $item"
      fi

      ln -s "$install_dir/bin/gpumkat" \
          "/usr/local/bin/gpumkat"
      if [ $? -eq 0 ]; then
        echo "Symbolic link created in /usr/local/bin \
pointing to $install_dir/bin/gpumkat"
      else
        echo "Failed to create symbolic link in \
/usr/local/bin"
      fi
    elif [ "$item" == "libgpumkat.dylib" ]; then
      if [ -L "/usr/local/lib/libgpumkat.dylib" ]; then
        rm "/usr/local/lib/libgpumkat.dylib"
        echo "Deleted existing symbolic link \
/usr/local/lib/libgpumkat.dylib"
      fi

      if [ -f "$install_dir/lib/$item" ]; then
        rm "$install_dir/lib/$item"
        echo "Deleted existing file $install_dir/lib/$item"
      fi
      cp "$item" "$install_dir/lib/"

      if [ $? -eq 0 ]; then
        echo "File $item copied successfully to \
$install_dir/lib"
      else
        echo "Failed to copy the file $item"
      fi

      ln -s "$install_dir/lib/libgpumkat.dylib" \
          "/usr/local/lib/libgpumkat.dylib"
      if [ $? -eq 0 ]; then
        echo "Symbolic link created in /usr/local/lib \
pointing to $install_dir/lib/libgpumkat.dylib"
      else
        echo "Failed to create symbolic link in \
/usr/local/lib"
      fi
    else
      cp "$item" "$install_dir/"

      if [ $? -eq 0 ]; then
        echo "File $item copied successfully to \
$install_dir"
      else
        echo "Failed to copy the file $item"
      fi
    fi
  else
    echo "$item does not exist or is not a valid file or \
directory"
  fi
done

echo "Installation complete!"

