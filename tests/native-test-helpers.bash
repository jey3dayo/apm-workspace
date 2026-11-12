copy_native_runtime() {
  local source_root="$1" fixture_root="$2"
  mkdir -p "$fixture_root/scripts/lib"
  cp "$source_root/scripts/native.sh" "$source_root/scripts/native-home.py" "$source_root/scripts/lock-hashes.py" "$fixture_root/scripts/"
  cp -R "$source_root/scripts/lib/." "$fixture_root/scripts/lib/"
}
