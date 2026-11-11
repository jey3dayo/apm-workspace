fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}
