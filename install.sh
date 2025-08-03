#!/bin/bash

# Define the version of the installation
GPUMKAT_VERSION="1.2"

# Check if the script is run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root or use sudo"
  exit
fi

# Define the files and directories to copy
files_to_copy=("gpumkat" "libgpumkat.dylib" "include" "README.md" "LICENSE" "gpumkat_icon.png" "gpumkat_logs.png")

# Define the destination directory
install_dir="/usr/local/Cellar/gpumkat/$GPUMKAT_VERSION"

# Create the installation directories
mkdir -p "$install_dir/lib" "$install_dir/include" "$install_dir/bin"

# Copy each file or directory
for item in "${files_to_copy[@]}"
do
  # Check if it's a directory or file
  if [ -d "$item" ]; then
    if [ "$item" == "include" ]; then
      if [ -d "$install_dir/include/gpumkat" ]; then
        rm -rf "$install_dir/include/gpumkat"
        echo "Deleted existing directory $install_dir/include/gpumkat"
      fi
      cp -r "$item" "$install_dir/include/gpumkat/"
      
      # Check if the copy was successful
      if [ $? -eq 0 ]; then
        echo "Directory $item copied successfully to $install_dir/include/gpumkat"
      else
        echo "Failed to copy the directory $item"
      fi
    else
      # For any other directory, copy it directly to the version folder
      cp -r "$item" "$install_dir/"
      
      # Check if the copy was successful
      if [ $? -eq 0 ]; then
        echo "Directory $item copied successfully to $install_dir"
      else
        echo "Failed to copy the directory $item"
      fi
    fi
  elif [ -f "$item" ]; then
    if [ "$item" == "gpumkat" ]; then
      # Check and delete existing symbolic link if present
      if [ -L "/usr/local/bin/gpumkat" ]; then
        rm "/usr/local/bin/gpumkat"
        echo "Deleted existing symbolic link /usr/local/bin/gpumkat"
      fi

      # Copy the executable to the bin folder in the versioned directory
      if [ -f "$install_dir/bin/$item" ]; then
        rm "$install_dir/bin/$item"
        echo "Deleted existing file $install_dir/bin/$item"
      fi
      cp "$item" "$install_dir/bin/"
      
      # Check if the copy was successful
      if [ $? -eq 0 ]; then
        echo "Executable $item copied successfully to $install_dir/bin"
      else
        echo "Failed to copy the executable $item"
      fi

      # Create a new symbolic link in /usr/local/bin pointing to the executable in the bin folder
      ln -s "$install_dir/bin/gpumkat" "/usr/local/bin/gpumkat"
      if [ $? -eq 0 ]; then
        echo "Symbolic link created in /usr/local/bin pointing to $install_dir/bin/gpumkat"
      else
        echo "Failed to create symbolic link in /usr/local/bin"
      fi
    elif [ "$item" == "libgpumkat.dylib" ]; then
      # Check and delete existing symbolic link if present
      if [ -L "/usr/local/lib/libgpumkat.dylib" ]; then
        rm "/usr/local/lib/libgpumkat.dylib"
        echo "Deleted existing symbolic link /usr/local/lib/libgpumkat.dylib"
      fi

      # For libgpumkat.dylib, copy to the lib folder in the versioned directory
      if [ -f "$install_dir/lib/$item" ]; then
        rm "$install_dir/lib/$item"
        echo "Deleted existing file $install_dir/lib/$item"
      fi
      cp "$item" "$install_dir/lib/"
      
      # Check if the copy was successful
      if [ $? -eq 0 ]; then
        echo "File $item copied successfully to $install_dir/lib"
      else
        echo "Failed to copy the file $item"
      fi

      # Create a new symbolic link in /usr/local/lib to the library
      ln -s "$install_dir/lib/libgpumkat.dylib" "/usr/local/lib/libgpumkat.dylib"
      if [ $? -eq 0 ]; then
        echo "Symbolic link created in /usr/local/lib pointing to $install_dir/lib/libgpumkat.dylib"
      else
        echo "Failed to create symbolic link in /usr/local/lib"
      fi
    else
      # For any other file, copy it directly into the version folder
      cp "$item" "$install_dir/"
      
      # Check if the copy was successful
      if [ $? -eq 0 ]; then
        echo "File $item copied successfully to $install_dir"
      else
        echo "Failed to copy the file $item"
      fi
    fi
  else
    echo "$item does not exist or is not a valid file or directory"
  fi
done

echo "Installation complete!"
