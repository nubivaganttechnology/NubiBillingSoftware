"""Disposable-only paired restore, recovery, and fail-closed tests."""

import hashlib
import json
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest

from tool.paired_database_restore import RestoreError, _has_open_handle, recover_pair, restore_pair


class SimulatedCrash(BaseException):
    pass


class PairedRestoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.backups = self.root / "backups"
        self.targets = self.root / "targets"
        self.forensics = self.root / "forensics"
        self.backups.mkdir()
        self.targets.mkdir()
        self.forensics.mkdir(mode=0o700)
        self.account_backup = self._database(self.backups / "account.db", "approved-account")
        self.config_backup = self._database(self.backups / "config.db", "approved-config")
        self.account_target = self._database(self.targets / "account.db", "failed-account")
        self.config_target = self._database(self.targets / "config.db", "failed-config")
        self.account_hash = self._hash(self.account_backup)
        self.config_hash = self._hash(self.config_backup)
        self.manifest = self.root / "restore.json"

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def _database(path: Path, generation: str) -> Path:
        connection = sqlite3.connect(path)
        try:
            connection.execute("CREATE TABLE generation (value TEXT NOT NULL)")
            connection.execute("INSERT INTO generation VALUES (?)", (generation,))
            connection.commit()
        finally:
            connection.close()
        return path

    @staticmethod
    def _hash(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _restore(self, **overrides):
        args = {
            "account_backup": self.account_backup,
            "account_sha256": self.account_hash,
            "config_backup": self.config_backup,
            "config_sha256": self.config_hash,
            "account_target": self.account_target,
            "config_target": self.config_target,
            "manifest": self.manifest,
            "forensic_dir": self.forensics,
            "maintenance_ack": "MAINTENANCE ACTIVE THROUGH INDEPENDENT VERIFICATION",
            "rollback_authority": "SK SUMAN",
            "handle_probe": lambda _: False,
        }
        args.update(overrides)
        return restore_pair(**args)

    def _recover(self):
        return recover_pair(
            manifest=self.manifest,
            maintenance_ack="MAINTENANCE STILL ACTIVE",
            rollback_authority="SK SUMAN",
            handle_probe=lambda _: False,
        )

    def _assert_complete_pair(self, journal):
        self.assertEqual(journal["state"], "COMPLETE")
        self.assertEqual(self._hash(self.account_target), self.account_hash)
        self.assertEqual(self._hash(self.config_target), self.config_hash)
        for target in (self.account_target, self.config_target):
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            connection = sqlite3.connect(f"file:{target.resolve()}?mode=ro", uri=True)
            try:
                self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            finally:
                connection.close()

    def test_normal_paired_restore_completes_and_preserves_forensics(self):
        account_preimage = self._hash(self.account_target)
        config_preimage = self._hash(self.config_target)
        journal = self._restore()
        self._assert_complete_pair(journal)
        self.assertFalse(journal["pairAtomicityClaimed"])
        self.assertEqual(len(list(self.forensics.glob("*-postimage.db"))), 2)
        for member, preimage in (("account", account_preimage), ("publicConfig", config_preimage)):
            forensic = Path(journal["targets"][member]["forensicPath"])
            self.assertEqual(journal["targets"][member]["preRestoreSha256"], preimage)
            self.assertEqual(self._hash(forensic), preimage)

    def test_lsof_detects_an_open_exact_path(self):
        with self.account_target.open("rb"):
            self.assertTrue(_has_open_handle(self.account_target.resolve()))

    def test_restart_recovers_each_persisted_interruption_point(self):
        cases = (
            "after_prepared",
            "after_account_replace_before_state",
            "after_config_replace_before_state",
            "during_verification",
        )
        for case in cases:
            with self.subTest(case=case):
                self.temp.cleanup()
                self.setUp()
                source = r'''import os, sys
from tool.paired_database_restore import restore_pair
case, account_backup, account_sha, config_backup, config_sha, account_target, config_target, manifest, forensic = sys.argv[1:]
def stop(stage, _journal):
    if stage == case:
        os._exit(86)
restore_pair(account_backup=account_backup, account_sha256=account_sha,
    config_backup=config_backup, config_sha256=config_sha,
    account_target=account_target, config_target=config_target,
    manifest=manifest, forensic_dir=forensic,
    maintenance_ack="MAINTENANCE ACTIVE", rollback_authority="SK SUMAN",
    fault_hook=stop)
'''
                stopped = subprocess.run(
                    [
                        sys.executable,
                        "-c",
                        source,
                        case,
                        str(self.account_backup),
                        self.account_hash,
                        str(self.config_backup),
                        self.config_hash,
                        str(self.account_target),
                        str(self.config_target),
                        str(self.manifest),
                        str(self.forensics),
                    ],
                    check=False,
                )
                self.assertEqual(stopped.returncode, 86)
                utility = Path(__file__).parents[1] / "paired_database_restore.py"
                resumed = subprocess.run(
                    [
                        sys.executable,
                        str(utility),
                        "recover",
                        "--manifest",
                        str(self.manifest),
                        "--maintenance-ack",
                        "MAINTENANCE STILL ACTIVE",
                        "--rollback-authority",
                        "SK SUMAN",
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(resumed.returncode, 0, resumed.stderr)
                journal = json.loads(self.manifest.read_text())
                self._assert_complete_pair(journal)

    def test_wrong_account_hash_aborts_before_target_change(self):
        before = self._hash(self.account_target)
        with self.assertRaisesRegex(RestoreError, "backup hash mismatch for account"):
            self._restore(account_sha256="0" * 64)
        self.assertEqual(self._hash(self.account_target), before)
        self.assertFalse(self.manifest.exists())

    def test_wrong_config_hash_aborts_before_target_change(self):
        before = self._hash(self.config_target)
        with self.assertRaisesRegex(RestoreError, "backup hash mismatch for publicConfig"):
            self._restore(config_sha256="0" * 64)
        self.assertEqual(self._hash(self.config_target), before)
        self.assertFalse(self.manifest.exists())

    def test_corrupt_staged_copy_aborts_before_replacement(self):
        before = self._hash(self.account_target)

        def corrupt(stage, _):
            if stage == "after_staging":
                next(self.targets.glob(".*.restore-stage")).write_bytes(b"corrupt")

        with self.assertRaisesRegex(RestoreError, "staged backup changed before PREPARED"):
            self._restore(fault_hook=corrupt)
        self.assertEqual(self._hash(self.account_target), before)
        self.assertFalse(self.manifest.exists())

    def test_sidecar_open_handle_and_missing_ack_abort(self):
        sidecar = Path(str(self.account_target) + "-wal")
        sidecar.touch()
        with self.assertRaisesRegex(RestoreError, "sidecars exist"):
            self._restore()
        sidecar.unlink()
        with self.assertRaisesRegex(RestoreError, "exact-path database handle is open"):
            self._restore(handle_probe=lambda path: path == self.account_target.resolve())
        with self.assertRaisesRegex(RestoreError, "maintenance acknowledgement is required"):
            self._restore(maintenance_ack="")
        self.assertFalse(self.manifest.exists())

    def test_insecure_forensic_directory_aborts_before_staging(self):
        insecure = self.root / "insecure-forensics"
        insecure.mkdir(mode=0o755)
        with self.assertRaisesRegex(RestoreError, "forensic directory must be owned by the operator and mode 0700"):
            self._restore(forensic_dir=insecure)
        self.assertTrue(self.account_target.exists())
        self.assertFalse(self.manifest.exists())

    def test_manifest_filesystem_mismatch_fails_closed(self):
        def crash(stage, _):
            if stage == "after_prepared":
                raise SimulatedCrash(stage)

        with self.assertRaises(SimulatedCrash):
            self._restore(fault_hook=crash)
        self.account_target.write_bytes(b"unknown generation")
        with self.assertRaisesRegex(RestoreError, "unexpected account target hash"):
            self._recover()
        journal = json.loads(self.manifest.read_text())
        self.assertEqual(journal["state"], "RECOVERY_REQUIRED")
        with self.assertRaisesRegex(RestoreError, "do not resume automatically"):
            self._recover()

    def test_missing_pair_member_aborts(self):
        self.config_backup.unlink()
        with self.assertRaisesRegex(RestoreError, "public-config backup must be an existing"):
            self._restore()
        self.assertTrue(self.account_target.exists())
        self.assertFalse(self.manifest.exists())

    def test_manifest_without_pair_member_is_rejected(self):
        def crash(stage, _):
            if stage == "after_prepared":
                raise SimulatedCrash(stage)

        with self.assertRaises(SimulatedCrash):
            self._restore(fault_hook=crash)
        journal = json.loads(self.manifest.read_text())
        del journal["targets"]["publicConfig"]
        self.manifest.write_text(json.dumps(journal))
        with self.assertRaisesRegex(RestoreError, "does not describe both pair members"):
            self._recover()


if __name__ == "__main__":
    unittest.main()