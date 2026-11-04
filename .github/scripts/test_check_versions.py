import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "check_versions", Path(__file__).with_name("check-versions.py")
)
check_versions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_versions)


class VersionCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.files = {
            f"{name}.podspec": "Pod::Spec.new do |s|\n  s.version = '1.2.3'\nend\n"
            for name in (
                "SimlaCore", "SimlaOnlineConsultant", "SimlaPushNotificationExtension",
                "SimlaPushService", "SimlaRecommendations", "SimlaSDKConfiguration",
                "SimlaSQLiteStorage", "SimlaTracker",
            )
        }
        self.files.update({
            "Sources/Core/Session/SessionRuntime.swift":
                'nonisolated package static let version = "1.2.3"\n',
            "Sources/PushService/PushService+Version.swift":
                'static let version = "1.2.3"\n',
            "docs/en/sdk.md": "**Exact Version → 1.2.3**\n:tag => '1.2.3'\n",
            "docs/ru/sdk.md": "**Exact Version → 1.2.3**\n:tag => '1.2.3'\n",
        })
        for name, content in self.files.items():
            self.write(name, content)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def test_matching_versions_pass(self):
        self.assertEqual(check_versions.validate(self.root), [])

    def test_changing_all_versions_together_passes(self):
        for name, content in self.files.items():
            self.write(name, content.replace("1.2.3", "2.0.0"))
        self.assertEqual(check_versions.validate(self.root), [])

    def test_each_of_the_fourteen_version_fields_can_fail_independently(self):
        for name, content in self.files.items():
            parts = content.split("1.2.3")
            for index in range(len(parts) - 1):
                with self.subTest(file=name, occurrence=index):
                    changed = parts[0]
                    for occurrence, part in enumerate(parts[1:]):
                        changed += ("1.2.2" if occurrence == index else "1.2.3") + part
                    self.write(name, changed)
                    errors = check_versions.validate(self.root)
                    self.assertIn("SDK versions do not match:", errors)
                    line = content.count("\n", 0, content.index("1.2.3")) + 1
                    if name.startswith("docs/") and index == 1:
                        line = 2
                    self.assertTrue(any(
                        error.startswith(f"{name}:{line}:") and "'1.2.2'" in error
                        for error in errors
                    ), errors)
                    self.write(name, content)

    def test_missing_required_files_fail(self):
        for name, content in self.files.items():
            with self.subTest(file=name):
                (self.root / name).unlink()
                errors = check_versions.validate(self.root)
                self.assertTrue(any(
                    error.startswith(f"{name}: missing file") for error in errors
                ), errors)
                self.write(name, content)

    def test_missing_each_documentation_example_fails(self):
        for language in ("en", "ru"):
            name = f"docs/{language}/sdk.md"
            for retained_line in self.files[name].splitlines(keepends=True):
                with self.subTest(file=name, retained=retained_line):
                    self.write(name, retained_line)
                    errors = check_versions.validate(self.root)
                    self.assertTrue(any(
                        error.startswith(name + ":") and "found 0" in error
                        for error in errors
                    ), errors)
                    self.write(name, self.files[name])

    def test_missing_and_duplicate_constant_fail(self):
        name = "Sources/PushService/PushService+Version.swift"
        for content, count in (("", 0), (self.files[name] * 2, 2)):
            with self.subTest(count=count):
                self.write(name, content)
                self.assertTrue(any(
                    error.startswith(name + ":") and f"found {count}" in error
                    for error in check_versions.validate(self.root)
                ))

    def test_additional_examples_are_checked(self):
        name = "docs/en/sdk.md"
        self.write(name, self.files[name] + ":tag => '1.2.2'\n")
        errors = check_versions.validate(self.root)
        self.assertIn(f"{name}:3: CocoaPods example = '1.2.2'", errors)

    def test_additional_podspecs_are_checked(self):
        self.write("SimlaNewModule.podspec", "s.version = '1.2.2'\n")
        self.assertIn(
            "SimlaNewModule.podspec:1: podspec version = '1.2.2'",
            check_versions.validate(self.root),
        )


if __name__ == "__main__":
    unittest.main()
