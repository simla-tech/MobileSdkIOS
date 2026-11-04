"""Check that SDK versions and documented installation versions agree."""

import argparse
from pathlib import Path
import re
from typing import Optional


POD_NAMES = (
    "SimlaCore",
    "SimlaOnlineConsultant",
    "SimlaPushNotificationExtension",
    "SimlaPushService",
    "SimlaRecommendations",
    "SimlaSDKConfiguration",
    "SimlaSQLiteStorage",
    "SimlaTracker",
)

NUMBER = r"(?:0|[1-9][0-9]*)"
PRERELEASE = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
SEMVER = (
    rf"{NUMBER}\.{NUMBER}\.{NUMBER}"
    rf"(?:-{PRERELEASE}(?:\.{PRERELEASE})*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def validate(root: Path, tag: Optional[str] = None) -> list[str]:
    if tag is not None and re.fullmatch(SEMVER, tag) is None:
        return [f"Release tag must be a semantic version without a 'v' prefix; got {tag!r}."]
    podspecs = {f"{name}.podspec" for name in POD_NAMES}
    podspecs.update(path.name for path in root.glob("*.podspec"))
    fields = [
        (name, "podspec version", r"^\s*s\.version\s*=\s*['\"]([^'\"]+)['\"]", False)
        for name in sorted(podspecs)
    ]
    for name, label in (
        ("Sources/Core/Session/SessionRuntime.swift", "SessionRuntime.version"),
        ("Sources/PushService/PushService+Version.swift", "PushService.version"),
    ):
        fields.append((name, label, r'\bstatic\s+let\s+version\s*=\s*"([^"]+)"', False))
    for language in ("en", "ru"):
        name = f"docs/{language}/sdk.md"
        fields.extend([
            (name, "SPM example", r"Exact Version\s*→\s*([^*\r\n]+)", True),
            (name, "CocoaPods example", r":tag\s*=>\s*['\"]([^'\"]+)['\"]", True),
        ])

    errors = []
    versions = []
    for name, label, pattern, multiple in fields:
        path = root / name
        if not path.is_file():
            errors.append(f"{name}: missing file ({label}).")
            continue
        content = path.read_text(encoding="utf-8")
        matches = list(re.finditer(pattern, content, re.MULTILINE))
        if not matches or (not multiple and len(matches) != 1):
            expected = "at least one" if multiple else "exactly one"
            errors.append(f"{name}: expected {expected} {label}, found {len(matches)}.")
        for match in matches:
            version = match.group(1).strip()
            line = content.count("\n", 0, match.start(1)) + 1
            versions.append((name, line, label, version))

    if tag is not None:
        errors.extend(
            f"{name}:{line}: {label} = {version!r}, expected release tag {tag!r}."
            for name, line, label, version in versions if version != tag
        )
    elif len({version for _, _, _, version in versions}) > 1:
        errors.append("SDK versions do not match:")
        errors.extend(
            f"{name}:{line}: {label} = {version!r}"
            for name, line, label, version in versions
        )
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', help='Also require every version to match this release tag.')
    args = parser.parse_args()
    errors = validate(Path(__file__).resolve().parents[2], args.tag)
    if errors:
        raise SystemExit("Version check failed:\n" + "\n".join(errors))
    print("All podspec, Swift and documented installation versions match.")
