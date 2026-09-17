#!/usr/bin/env bash

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *)
      printf 'Expected output to contain: %s\nActual output:\n%s\n' "$2" "$1" >&2
      exit 1
      ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*)
      printf 'Expected output not to contain: %s\nActual output:\n%s\n' "$2" "$1" >&2
      exit 1
      ;;
    *) ;;
  esac
}

write_arg_printer() {
  local path="$1"
  local name="$2"

  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s' '$name'
for arg in "\$@"; do
  printf '\\n<%s>' "\$arg"
done
printf '\\n'
EOF
  chmod +x "$path"
}
