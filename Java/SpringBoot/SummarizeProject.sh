clear; {
  echo "===== build.gradle ====="
  cat build.gradle 2>/dev/null || echo "(No build.gradle found)"
  echo
  echo "===== Source Files ====="
  find ./src -type f \
    ! -iname "*.png" ! -iname "*.jpeg" ! -iname "*.jpg"  ! -iname "*.ico"  ! -iname "*.svg" \
    ! -iname "*.gif" ! -iname "*.class" ! -iname "*.wav" ! -iname "*.mp3" ! -iname "*.json" \
    ! -iname "*.p12" \
    -print0 | sort -z | while IFS= read -r -d '' file; do
      echo "# $file"
      echo "===== $(basename "$file") ====="
      cat "$file"
      echo
    done
  echo "===== Project Tree ====="
  command -v tree >/dev/null && tree . || find .
  echo
  echo "===== Java Version ====="
  java --version 2>/dev/null || echo "java not found"
  javac --version 2>/dev/null || echo "javac not found"
  ./gradlew -v 2>/dev/null || echo "gradlew not found or not executable"
} > ../summary.txt
