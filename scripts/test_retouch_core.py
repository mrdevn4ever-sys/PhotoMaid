#!/usr/bin/env python3
"""Run only the actual platform-neutral retouch sources and their regression tests.

This is an offline, focused SwiftPM harness, NOT the complete PhotoMaidCore suite
and NOT an iOS/SwiftUI build. The repository files are copied without rewriting.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    args = parser.parse_args()
    swift = shutil.which("swift")
    if swift is None:
        parser.error("Swift 6 or later must be installed and available on PATH.")
    root = Path(__file__).resolve().parents[1]
    sources = [root / "Sources/PhotoMaidCore/Edit" / name for name in (
        "Adjustments.swift", "LocalAdjustment.swift", "RetouchSelection.swift"
    )]
    tests = root / "Tests/PhotoMaidCoreTests/RetouchSelectionTests.swift"
    for path in [*sources, tests]:
        if not path.is_file():
            parser.error(f"Missing repository source: {path}")
    with tempfile.TemporaryDirectory(prefix="photomaid-retouch-") as directory:
        package = Path(directory)
        source_dir = package / "Sources/PhotoMaidCore"
        test_dir = package / "Tests/PhotoMaidCoreTests"
        source_dir.mkdir(parents=True)
        test_dir.mkdir(parents=True)
        for source in sources:
            shutil.copy2(source, source_dir / source.name)
        shutil.copy2(tests, test_dir / tests.name)
        (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PhotoMaidRetouchFocusedTests", targets: [
    .target(name: "PhotoMaidCore", swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "PhotoMaidCoreTests", dependencies: ["PhotoMaidCore"],
                swiftSettings: [.swiftLanguageMode(.v6)])
])
''', encoding="utf-8")
        print("Focused retouch tests only; no iOS build or full repository test run.", flush=True)
        return subprocess.run(
            [swift, "test", "--package-path", str(package), "-c", args.configuration],
            check=False,
        ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
