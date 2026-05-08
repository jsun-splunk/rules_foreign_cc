#!/usr/bin/env bash

set -euo pipefail

set +u
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -d ' ' -f 2-)" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -d ' ' -f 2-)" 2>/dev/null || {
    echo >&2 "cannot find $f"
    exit 1
  }
set -u

usage() {
  echo "usage: $0 <binary-name> --binary-runfiles <path ...> [--expect-loaded <name> <path ...>]..." >&2
}

is_windows() {
  case "$(uname -s 2>/dev/null || true)" in
    CYGWIN*|MINGW*|MSYS*)
      return 0
      ;;
  esac
  return 1
}

append_arg_words_to_binary_candidates() {
  local words=()
  read -r -a words <<< "$1"
  binary_candidates+=("${words[@]}")
}

python_command() {
  if command -v python3 >/dev/null; then
    echo python3
    return
  fi
  echo python
}

windows_path() {
  if command -v cygpath >/dev/null; then
    cygpath -w "$1"
    return
  fi
  printf '%s\n' "$1"
}

windows_shell_path() {
  if command -v cygpath >/dev/null; then
    cygpath -u "$1"
    return
  fi
  printf '%s\n' "$1"
}

real_file_path() {
  if command -v realpath >/dev/null; then
    realpath "$1"
    return
  fi
  "$(python_command)" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

canonical_path() {
  local path="$1"
  if is_windows; then
    if command -v realpath >/dev/null; then
      path="$(realpath "$path")"
    fi
    if command -v cygpath >/dev/null; then
      path="$(cygpath -m "$path")"
    fi
    path="${path//\\//}"
    case "$path" in
      "//?/UNC/"*)
        path="//${path#"//?/UNC/"}"
        ;;
      "//?/unc/"*)
        path="//${path#"//?/unc/"}"
        ;;
      "//?/"*)
        path="${path#"//?/"}"
        ;;
    esac
    printf '%s\n' "$path" | tr '[:upper:]' '[:lower:]'
    return
  fi

  if command -v realpath >/dev/null; then
    realpath "$path" 2>/dev/null || printf '%s\n' "$path"
    return
  fi
  "$(python_command)" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$path"
}

shared_library_candidate() {
  case "$(basename "$1")" in
    *.so|*.so.*|*.dylib|*.dll)
      return 0
      ;;
  esac
  return 1
}

binary_name_matches() {
  local candidate_basename
  candidate_basename="$(basename "$1")"
  if [[ "$candidate_basename" == "$binary_name" ]]; then
    return 0
  fi
  if is_windows && [[ "$candidate_basename" == "${binary_name}.exe" ]]; then
    return 0
  fi
  return 1
}

loaded_path_for() {
  local name="$1"
  local line
  line="$(grep -m1 "^loaded ${name}: " "$stdout_file" || true)"
  if [[ -z "$line" ]]; then
    echo "missing loaded path for ${name}" >&2
    cat "$stdout_file" >&2
    exit 1
  fi
  printf '%s\n' "${line#loaded ${name}: }"
}

assert_loaded_from_expected() {
  local name="$1"
  local candidate_blob="$2"
  local candidate
  local candidate_canonical
  local loaded_path
  local loaded_canonical
  local expected_canonical_paths=()
  local resolved_candidate

  loaded_path="$(loaded_path_for "$name")"
  if [[ "$loaded_path" == \<*\> ]]; then
    echo "${name} did not resolve to a loaded shared library" >&2
    cat "$stdout_file" >&2
    exit 1
  fi
  loaded_canonical="$(canonical_path "$loaded_path")"

  while IFS= read -r candidate; do
    if [[ -z "$candidate" ]] || ! shared_library_candidate "$candidate"; then
      continue
    fi

    resolved_candidate="$(rlocation "$candidate")"
    if [[ -z "$resolved_candidate" || ! -e "$resolved_candidate" ]]; then
      continue
    fi

    candidate_canonical="$(canonical_path "$resolved_candidate")"
    expected_canonical_paths+=("$candidate_canonical")
    if [[ "$loaded_canonical" == "$candidate_canonical" ]]; then
      return
    fi
  done <<< "$candidate_blob"

  echo "${name} loaded from unexpected path" >&2
  echo "actual: $loaded_canonical" >&2
  echo "expected one of:" >&2
  printf '  %s\n' "${expected_canonical_paths[@]}" >&2
  exit 1
}

append_windows_dll_search_dir() {
  local candidate_dir="$1"
  local candidate_dir_path

  if [[ ! -d "$candidate_dir" ]]; then
    return
  fi

  candidate_dir_path="$(windows_shell_path "$candidate_dir")"
  case ":$windows_dll_search_path:" in
    *":$candidate_dir_path:"*)
      ;;
    *)
      if [[ -n "$windows_dll_search_path" ]]; then
        windows_dll_search_path+=":"
      fi
      windows_dll_search_path+="$candidate_dir_path"
      ;;
  esac
}

append_windows_dll_search_dirs() {
  local candidate_blob="$1"
  local candidate
  local resolved_candidate
  local candidate_dir

  while IFS= read -r candidate; do
    if [[ -z "$candidate" ]] || ! shared_library_candidate "$candidate"; then
      continue
    fi

    resolved_candidate="$(rlocation "$candidate")"
    if [[ -z "$resolved_candidate" || ! -e "$resolved_candidate" ]]; then
      continue
    fi

    resolved_candidate="$(real_file_path "$resolved_candidate")"
    candidate_dir="$(dirname "$resolved_candidate")"
    append_windows_dll_search_dir "$candidate_dir"
  done <<< "$candidate_blob"
}

if [[ "$#" -lt 3 ]]; then
  usage
  exit 1
fi

binary_name="$1"
shift
if [[ "$1" != "--binary-runfiles" ]]; then
  usage
  exit 1
fi
shift

binary_candidates=()
expected_names=()
expected_candidate_blobs=()

while [[ "$#" -gt 0 && "$1" != "--expect-loaded" ]]; do
  append_arg_words_to_binary_candidates "$1"
  shift
done

while [[ "$#" -gt 0 ]]; do
  if [[ "$#" -lt 3 || "$1" != "--expect-loaded" ]]; then
    usage
    exit 1
  fi
  shift

  expected_name="$1"
  shift
  expected_candidate_blob=""
  while [[ "$#" -gt 0 && "$1" != "--expect-loaded" ]]; do
    expected_candidate_words=()
    read -r -a expected_candidate_words <<< "$1"
    for expected_candidate in "${expected_candidate_words[@]}"; do
      expected_candidate_blob+="${expected_candidate}"$'\n'
    done
    shift
  done
  if [[ -z "$expected_candidate_blob" ]]; then
    echo "no expected runfile paths for $expected_name" >&2
    exit 1
  fi
  expected_names+=("$expected_name")
  expected_candidate_blobs+=("$expected_candidate_blob")
done

binary_runfile_path=""
for candidate in "${binary_candidates[@]}"; do
  if binary_name_matches "$candidate"; then
    binary_runfile_path="$candidate"
    break
  fi
done

if [[ -z "$binary_runfile_path" ]]; then
  echo "$binary_name runfile path not found in: ${binary_candidates[*]}" >&2
  exit 1
fi

binary="$(rlocation "$binary_runfile_path")"
if [[ -z "$binary" || ! -f "$binary" ]]; then
  echo "$binary_name is not executable: $binary_runfile_path" >&2
  exit 1
fi
if ! is_windows && [[ ! -x "$binary" ]]; then
  echo "$binary_name is not executable: $binary_runfile_path" >&2
  exit 1
fi
if is_windows; then
  binary="$(real_file_path "$binary")"
fi

stdout_file="$TEST_TMPDIR/transitive-matrix-stdout.txt"
stderr_file="$TEST_TMPDIR/transitive-matrix-stderr.txt"

set +e
if is_windows; then
  windows_dll_search_path=""
  for index in "${!expected_candidate_blobs[@]}"; do
    append_windows_dll_search_dirs "${expected_candidate_blobs[$index]}"
  done
  append_windows_dll_search_dir "/c/Windows/System32/downlevel"
  windows_child_path="$windows_dll_search_path"
  if [[ -n "$windows_child_path" && -n "${PATH:-}" ]]; then
    windows_child_path+=":"
  fi
  windows_child_path+="${PATH:-}"
  PATH="$windows_child_path" "$binary" >"$stdout_file" 2>"$stderr_file"
else
  env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH "$binary" >"$stdout_file" 2>"$stderr_file"
fi
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "$binary_name failed with exit code $status: $binary" >&2
  if is_windows; then
    echo "windows dll search path: ${windows_dll_search_path:-<empty>}" >&2
  fi
  cat "$stdout_file" >&2
  cat "$stderr_file" >&2
  exit "$status"
fi

expected="expected libarchive+zlib loaded: payload=rules_foreign_cc_transitive_test"
if ! grep -Fxq "$expected" "$stdout_file"; then
  echo "unexpected transitive matrix output" >&2
  echo "expected: $expected" >&2
  echo "actual:" >&2
  cat "$stdout_file" >&2
  cat "$stderr_file" >&2
  exit 1
fi

for index in "${!expected_names[@]}"; do
  assert_loaded_from_expected \
    "${expected_names[$index]}" \
    "${expected_candidate_blobs[$index]}"
done
