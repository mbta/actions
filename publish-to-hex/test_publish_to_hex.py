import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ACTION_PATH = Path(__file__).resolve().parent
ACTION = yaml.safe_load((ACTION_PATH / "action.yml").read_text())
STEPS = {step["name"]: step for step in ACTION["runs"]["steps"]}


class PublishToHexTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.project = Path(cls.temp.name) / "project"
        cls.project.mkdir()
        (cls.project / "mix.exs").write_text(
            'defmodule Fixture.MixProject do\n'
            '  use Mix.Project\n'
            '  def project, do: [app: :fixture, version: "1.2.3"]\n'
            'end\n'
        )
        cls.command("mix", "compile")
        cls.command("git", "init", "--initial-branch=main")
        cls.command("git", "add", "mix.exs")
        cls.command(
            "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-m", "Fixture"
        )
        cls.sha = cls.command("git", "rev-parse", "HEAD").stdout.strip()
        cls.command("git", "update-ref", "refs/remotes/origin/main", cls.sha)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    @classmethod
    def command(cls, *args):
        return subprocess.run(
            args, cwd=cls.project, text=True, capture_output=True, check=True
        )

    def run_step(self, name, cwd=None, **env):
        return subprocess.run(
            ["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", STEPS[name]["run"]],
            cwd=cwd or self.project,
            env={
                **os.environ,
                "GITHUB_EVENT_NAME": "push",
                "GITHUB_REF_TYPE": "tag",
                "GITHUB_SHA": self.sha,
                "VALIDATE_ONLY": "true",
                "ACTION_PATH": str(ACTION_PATH),
                "RELEASE_TAG": "v1.2.3",
                **env,
            },
            text=True,
            capture_output=True,
        )

    def assert_failure(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stdout + result.stderr)

    def test_release_context(self):
        result = self.run_step("Check release context")
        self.assertEqual(result.returncode, 0, result.stderr)
        for env in (
            {"GITHUB_EVENT_NAME": "pull_request"},
            {"GITHUB_EVENT_NAME": "workflow_dispatch"},
            {"GITHUB_REF_TYPE": "branch"},
        ):
            with self.subTest(env=env):
                self.assert_failure(
                    self.run_step("Check release context", **env),
                    "Releases must run on a pushed tag",
                )

    def test_invalid_mode(self):
        self.assert_failure(
            self.run_step("Check release context", VALIDATE_ONLY="tru"),
            "validate-only must be true or false",
        )

    def test_wrong_checkout(self):
        self.assert_failure(
            self.run_step("Check release context", GITHUB_SHA="0" * 40),
            "Checkout must match the pushed release commit",
        )

    def test_commit_not_on_main(self):
        tree = self.command("git", "rev-parse", "HEAD^{tree}").stdout.strip()
        unrelated = self.command(
            "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit-tree", tree, "-m", "Unrelated"
        ).stdout.strip()
        self.command("git", "update-ref", "refs/remotes/origin/main", unrelated)
        try:
            self.assert_failure(
                self.run_step("Check release context"), "Release commit must be on main"
            )
        finally:
            self.command("git", "update-ref", "refs/remotes/origin/main", self.sha)

    def test_shallow_checkout(self):
        clone = Path(self.temp.name) / "shallow"
        self.command("git", "clone", "--depth=1", self.project.as_uri(), str(clone))
        self.assert_failure(
            self.run_step("Check release context", cwd=clone), "Checkout must use fetch-depth: 0"
        )

    def test_matching_version(self):
        result = self.run_step("Validate release version")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_mismatching_stable_version(self):
        for tag in ("v1.2.4", "v0.0.0", "v10.20.30"):
            with self.subTest(tag=tag):
                self.assert_failure(
                    self.run_step("Validate release version", RELEASE_TAG=tag),
                    "does not match project version",
                )

    def test_invalid_versions(self):
        for tag in (
            "1.2.3", "v01.2.3", "v1.02.3", "v1.2.03", "v1.2", "v1.2.3.4",
            "v1.2.3-rc.1", "v1.2.3+build", "v1.2.3\n", "v1.2.3; echo injected",
        ):
            with self.subTest(tag=tag):
                self.assert_failure(
                    self.run_step("Validate release version", RELEASE_TAG=tag),
                    "Release tag must be a stable semantic version prefixed with v",
                )

    def test_missing_key(self):
        self.assert_failure(
            self.run_step("Publish package and documentation", HEX_API_KEY=""),
            "hex-api-key is required to publish",
        )

    def test_publish_command_without_publishing(self):
        bin_path = Path(self.temp.name) / "bin"
        bin_path.mkdir()
        mix = bin_path / "mix"
        mix.write_text('#!/bin/bash\nprintf "%s\\n" "$*"\n')
        mix.chmod(0o755)
        result = self.run_step(
            "Publish package and documentation", HEX_API_KEY="test-only",
            PATH=str(bin_path) + os.pathsep + os.environ["PATH"],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "hex.publish --yes")

    def test_secret_isolation_and_validation_only(self):
        self.assertEqual(ACTION["inputs"]["validate-only"]["default"], "false")
        for name, step in STEPS.items():
            with self.subTest(step=name):
                if name != "Publish package and documentation":
                    self.assertNotIn("hex-api-key", str(step))
                    self.assertNotIn("HEX_API_KEY", str(step))
                if name not in ("Check release context", "Validate release version"):
                    self.assertIn("inputs.validate-only != 'true'", step["if"])

    def test_shellcheck(self):
        for name, step in STEPS.items():
            if "run" in step:
                with self.subTest(step=name):
                    result = subprocess.run(
                        ["shellcheck", "--shell=bash", "--severity=warning", "-"],
                        input=step["run"], text=True, capture_output=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
