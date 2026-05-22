#!/usr/bin/env bash
# summarize-csharp.sh
# Usage: ./summarize-csharp.sh > ../summary.txt

clear; {

  echo "===== Solution File ====="
  ls *.sln 2>/dev/null || echo "(No .sln file found)"
  echo

  echo "===== Project Files ====="
  for proj in *.csproj; do
    echo "# $proj"
    echo "===== $proj ====="
    cat "$proj" 2>/dev/null || echo "(Cannot read $proj)"
    echo
  done

  echo "===== Source Files ====="
  find . -type f \( -iname "*.cs" -o -iname "*.resx" -o -iname "*.Designer.cs" \) \
    -print0 | sort -z | while IFS= read -r -d '' file; do
      echo "# $file"
      echo "===== $(basename "$file") ====="
      cat "$file"
      echo
    done

  echo "===== Project Tree ====="
  command -v tree >/dev/null && tree . || find . -print

  echo
  echo "===== .NET SDK & Runtime ====="
  dotnet --list-sdks 2>/dev/null || echo ".NET SDK not found"
  dotnet --list-runtimes 2>/dev/null || echo ".NET runtime not found"
}
