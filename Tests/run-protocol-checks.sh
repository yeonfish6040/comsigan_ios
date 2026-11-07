#!/bin/sh
# Offline protocol regression checks; add --live for an actual school-search/timetable request.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/comsigan-protocol.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
cd "$project_dir"
swiftc -parse-as-library \
    Shared/ComciProtocolDefaults.swift \
    Shared/ComciProtocolConfig.swift \
    Shared/ComciEndpoint.swift \
    Shared/ComciDocument.swift \
    Shared/ComciService.swift \
    Shared/TimetableModels.swift \
    Shared/AppSettings.swift \
    Shared/WidgetTheme.swift \
    Tests/ComciProtocolChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$project_dir/Tests/Fixtures" "$@"
