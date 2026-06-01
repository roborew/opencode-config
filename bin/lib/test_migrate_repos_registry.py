#!/usr/bin/env python3
"""Tests for migrate_repos_registry.py."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import migrate_repos_registry as m  # noqa: E402


PARTIAL_REGISTRY = """# Spec repo registry

Custom header preserved by migration.

---

repos:
  - repo: myorg/my-web
    application_role: User-facing web application
    agent_owner: frontend-dev
    capabilities:
      - billing UI
      - admin surfaces
  - repo: myorg/my-api
    application_role: TBD — service/API role (confirm — not necessarily generic backend)
    agent_owner: developer
    capabilities:
      - TBD — add capabilities in setup-skills
"""

LEGACY_REGISTRY = """# Legacy registry

---

repos:
  - name: myorg/my-web
    role: target
  - name: myorg/my-api
    role: target
"""


class NormalizeEntryTests(unittest.TestCase):
    def test_preserves_filled_fields_when_other_repo_has_tbd(self) -> None:
        normalize = m.normalize_entry(
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "agent_owner": "frontend-dev",
                "capabilities": ["billing UI", "admin surfaces"],
            }
        )
        self.assertEqual(normalize["application_role"], "User-facing web application")
        self.assertEqual(normalize["capabilities"], ["billing UI", "admin surfaces"])

    def test_tbd_capabilities_replaced_non_tbd_role_kept(self) -> None:
        out = m.normalize_entry(
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "agent_owner": "frontend-dev",
                "capabilities": ["TBD — add capabilities in setup-skills"],
            }
        )
        self.assertEqual(out["application_role"], "User-facing web application")
        self.assertTrue(any("TBD" in c for c in out["capabilities"]))

    def test_mixed_capabilities_drop_tbd_keep_real(self) -> None:
        out = m.normalize_entry(
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "capabilities": ["billing UI", "TBD — add capabilities in setup-skills"],
            }
        )
        self.assertEqual(out["capabilities"], ["billing UI"])

    def test_legacy_name_migrated_to_repo(self) -> None:
        out = m.normalize_entry({"name": "myorg/my-web", "role": "target"})
        self.assertEqual(out["repo"], "myorg/my-web")
        self.assertIn("application_role", out)


class SchemaMigrationTests(unittest.TestCase):
    def test_needs_schema_migration_for_legacy_name(self) -> None:
        repos = [{"name": "myorg/my-web", "role": "target"}]
        self.assertTrue(m.needs_schema_migration(repos))

    def test_no_schema_migration_for_partial_tbd(self) -> None:
        repos = [
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "capabilities": ["billing UI"],
            }
        ]
        self.assertFalse(m.needs_schema_migration(repos))


class MainIntegrationTests(unittest.TestCase):
    def _run_migrate(self, content: str) -> tuple[int, str, Path]:
        tmp = tempfile.NamedTemporaryFile(suffix=".md", delete=False)
        path = Path(tmp.name)
        path.write_text(content, encoding="utf-8")
        tmp.close()
        proc = subprocess.run(
            [sys.executable, str(LIB / "migrate_repos_registry.py"), str(path)],
            capture_output=True,
            text=True,
        )
        output = proc.stdout + proc.stderr
        return proc.returncode, output, path

    def test_incomplete_does_not_rewrite(self) -> None:
        code, output, path = self._run_migrate(PARTIAL_REGISTRY)
        self.assertEqual(path.read_text(encoding="utf-8"), PARTIAL_REGISTRY)
        self.assertIn("no migration needed", output)
        self.assertIn("NEXT:", output)
        self.assertEqual(code, 3)
        path.unlink(missing_ok=True)

    def test_legacy_name_migrates_to_repo(self) -> None:
        code, output, path = self._run_migrate(LEGACY_REGISTRY)
        text = path.read_text(encoding="utf-8")
        self.assertIn("repo: myorg/my-web", text)
        self.assertNotIn("name: myorg/my-web", text)
        self.assertIn("migrated", output)
        self.assertEqual(code, 3)
        path.unlink(missing_ok=True)

    def test_partial_fill_preserved_after_legacy_migration(self) -> None:
        content = """# Registry

---

repos:
  - repo: myorg/my-web
    application_role: User-facing web application
    agent_owner: frontend-dev
    capabilities:
      - billing UI
  - name: myorg/my-api
    role: target
"""
        code, output, path = self._run_migrate(content)
        text = path.read_text(encoding="utf-8")
        self.assertIn("User-facing web application", text)
        self.assertIn("billing UI", text)
        self.assertIn("repo: myorg/my-api", text)
        self.assertIn("migrated", output)
        self.assertEqual(code, 3)
        path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
