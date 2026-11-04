import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("publish-release.sh")


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        tools = self.root / "bin"
        tools.mkdir()
        self.gh_args = self.root / "gh-args"
        stubs = {
            "git": '#!/bin/sh\nprintf "%s\\n" "$TEST_REMOTE_REFS"\nexit "$TEST_GIT_EXIT"\n',
            "gh": '#!/bin/sh\nprintf "%s\\n" "$@" > "$TEST_GH_ARGS"\nexit "$TEST_GH_EXIT"\n',
        }
        for name, content in stubs.items():
            path = tools / name
            path.write_text(content, encoding="utf-8")
            path.chmod(0o755)
        self.commit = "1" * 40
        self.env = {
            **os.environ,
            "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "RELEASE_TAG": "1.2.3",
            "EXPECTED_COMMIT": self.commit,
            "SDK_REPOSITORY_URL": "https://github.com/example/sdk.git",
            "GITHUB_REPOSITORY": "example/sdk",
            "TEST_REMOTE_REFS": self.commit + "\trefs/tags/1.2.3",
            "TEST_GH_ARGS": str(self.gh_args),
            "TEST_GIT_EXIT": "0",
            "TEST_GH_EXIT": "0",
        }

    def run_publish(self):
        return subprocess.run(
            ["bash", str(SCRIPT)], env=self.env, capture_output=True, text=True, check=False
        )

    def test_verified_lightweight_tag_publishes_with_expected_arguments(self):
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.gh_args.read_text().splitlines(), [
            "release", "create", "1.2.3", "--repo", "example/sdk",
            "--verify-tag", "--generate-notes", "--title", "Release 1.2.3",
        ])

    def test_annotated_tag_compares_peeled_commit(self):
        self.env["TEST_REMOTE_REFS"] = (
            "2" * 40 + "\trefs/tags/1.2.3\n" + self.commit + "\trefs/tags/1.2.3^{}"
        )
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.gh_args.is_file())

    def test_changed_tag_does_not_publish(self):
        self.env["TEST_REMOTE_REFS"] = "2" * 40 + "\trefs/tags/1.2.3"
        result = self.run_publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no longer points to verified commit", result.stderr)
        self.assertFalse(self.gh_args.exists())

    def test_missing_remote_tag_does_not_publish(self):
        self.env.update(TEST_REMOTE_REFS="", TEST_GIT_EXIT="2")
        result = self.run_publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.gh_args.exists())

    def test_prerelease_does_not_become_latest(self):
        self.env.update(
            RELEASE_TAG="1.2.3-rc.1",
            TEST_REMOTE_REFS=self.commit + "\trefs/tags/1.2.3-rc.1",
        )
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.gh_args.read_text().splitlines()
        self.assertIn("--prerelease", args)
        self.assertIn("--latest=false", args)

    def test_publication_failure_is_not_hidden(self):
        self.env["TEST_GH_EXIT"] = "7"
        self.assertEqual(self.run_publish().returncode, 7)


if __name__ == "__main__":
    unittest.main()
