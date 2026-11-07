#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/comsigan-updates.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
cd "$project_dir"
swiftc -parse-as-library comsigan/AppUpdateChecker.swift Tests/AppUpdateChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$@"
