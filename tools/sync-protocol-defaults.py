#!/usr/bin/env python3
"""Regenerate offline defaults from Config/comci-protocol.json.
Usage: python3 tools/sync-protocol-defaults.py [--android /path/to/Android/project]
Remote edits require only the JSON; regenerate defaults when shipping a new app build.
"""
import argparse
import json
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--android', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = json.dumps(json.loads((root / 'Config/comci-protocol.json').read_text()), ensure_ascii=False, indent=2) + '\n'
(root / 'Config/comci-protocol.json').write_text(text)
(root / 'Shared/ComciProtocolDefaults.swift').write_text('import Foundation\n\nnonisolated enum ComciProtocolDefaults {\n    static let json = #"""\n' + text + '"""#\n}\n')
if args.android:
    (args.android / 'app/src/main/assets').mkdir(parents=True, exist_ok=True)
    (args.android / 'app/src/main/assets/comci-protocol.json').write_text(text)
    (args.android / 'app/src/main/java/com/yftech/comsigan/data/ComciProtocolDefaults.kt').write_text('package com.yftech.comsigan.data\n\ninternal object ComciProtocolDefaults {\n    val json = """\n' + text.replace('$', "${'$'}") + '""".trimIndent()\n}\n')
