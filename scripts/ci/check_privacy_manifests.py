#!/usr/bin/env python3
"""Check tracking declarations in every manifest in directories, SDK ZIPs or an IPA.

Read-only; never patches or re-signs vendor SDKs. Covers Apple TN3181's tracking
rules, not Apple's entire validation or the completeness of runtime domain lists.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import sys
from xml.parsers.expat import ExpatError
import zipfile


class UniqueKeys(dict):
    def __setitem__(self, key, value):
        if key in self:
            raise ValueError(f"Duplicate plist key: {key}")
        super().__setitem__(key, value)


DOMAIN = re.compile(r"(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+"
                    r"[a-zA-Z](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?")


def inspect_manifest(path, data):
    result = {"path": path, "sha256": hashlib.sha256(data).hexdigest(),
              "tracking": None, "domains": None, "errors": [], "warnings": []}
    errors = result["errors"]
    try:
        manifest = plistlib.loads(data, dict_type=UniqueKeys)
        if not isinstance(manifest, dict):
            raise ValueError("Manifest root must be a dictionary")
    except (ValueError, TypeError, OverflowError, plistlib.InvalidFileException, ExpatError) as error:
        errors.append(f"Invalid plist: {error}")
        return result

    tracking = manifest.get("NSPrivacyTracking")
    domains = manifest.get("NSPrivacyTrackingDomains")
    if "NSPrivacyTracking" in manifest and type(tracking) is not bool:
        errors.append("NSPrivacyTracking must be a Boolean")
    else:
        result["tracking"] = tracking
    if "NSPrivacyTrackingDomains" in manifest:
        if not isinstance(domains, list) or not all(isinstance(item, str) for item in domains):
            errors.append("NSPrivacyTrackingDomains must be an array of strings")
        else:
            result["domains"] = domains
            for domain in domains:
                if len(domain) > 253 or DOMAIN.fullmatch(domain) is None:
                    errors.append(f"Invalid tracking domain (hostname only): {domain!r}")
            if domains and tracking is not True:
                errors.append("Nonempty NSPrivacyTrackingDomains requires NSPrivacyTracking = true")
            if not domains and tracking is not True:
                result["warnings"].append("Remove the empty NSPrivacyTrackingDomains key when not tracking (TN3181)")
    if tracking is True and not domains:
        errors.append("NSPrivacyTracking = true requires at least one tracking domain (TN3181)")
    return result


def manifests_in(path):
    if path.is_dir():
        for item in sorted(path.rglob("*.xcprivacy")):
            yield str(item), item.read_bytes()
    elif path.suffix.lower() in (".zip", ".ipa"):
        with zipfile.ZipFile(path) as archive:
            for item in archive.infolist():
                if not item.is_dir() and item.filename.endswith(".xcprivacy"):
                    yield f"{path}!{item.filename}", archive.read(item)
    elif path.suffix == ".xcprivacy":
        yield str(path), path.read_bytes()
    else:
        raise ValueError(f"Expected a directory, .xcprivacy, SDK .zip or .ipa: {path}")


def audit(paths, require_app_manifest=False):
    results, errors = [], []
    for path in paths:
        if not path.exists():
            errors.append(f"Input does not exist: {path}")
            continue
        try:
            found = list(manifests_in(path))
            if not found:
                errors.append(f"No privacy manifests found in: {path}")
            results.extend(inspect_manifest(name, data) for name, data in found)
        except (OSError, ValueError, zipfile.BadZipFile) as error:
            errors.append(f"Could not read {path}: {error}")
    if require_app_manifest and not any(
        re.search(r"[!/]Payload/[^/]+\.app/PrivacyInfo\.xcprivacy$", item["path"])
        or re.search(r"/Products/Applications/[^/]+\.app/PrivacyInfo\.xcprivacy$", item["path"])
        for item in results
    ):
        errors.append("Missing main app PrivacyInfo.xcprivacy in the exported IPA/archive")
    return {"status": "FAIL" if errors or any(item["errors"] for item in results) else "PASS",
            "errors": errors, "manifests": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--require-app-manifest", action="store_true")
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()
    report = audit(args.paths, args.require_app_manifest)
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for error in report["errors"]:
        print(f"FAIL: {error}")
    for item in report["manifests"]:
        print(f"{'FAIL' if item['errors'] else 'PASS'}: {item['path']} "
              f"tracking={item['tracking']!r} domains={item['domains']!r}")
        for error in item["errors"]:
            print(f"  ERROR: {error}")
        for warning in item["warnings"]:
            print(f"  WARN: {warning}")
    print(f"Privacy tracking check: {report['status']} ({len(report['manifests'])} manifests)")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
