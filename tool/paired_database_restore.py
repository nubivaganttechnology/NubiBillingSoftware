"""Crash-recoverable paired SQLite restore. The pair is journaled, not atomic."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import sys
import uuid
from typing import Callable


STATES = {
    "PREPARED",
    "ACCOUNT_REPLACED",
    "CONFIG_REPLACED",
    "VERIFIED",
    "COMPLETE",
    "RECOVERY_REQUIRED",
}
MEMBERS = ("account", "publicConfig")
SIDECARS = ("-wal", "-shm", "-journal")
FaultHook = Callable[[str, dict], None]
HandleProbe = Callable[[Path], bool]


class RestoreError(RuntimeError):
    pass


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fsync_file(path: Path) -> None:
    with path.open("rb") as stream:
        os.fsync(stream.fileno())


def _fsync_directory(path: Path) -> None:
    unsupported = {errno.EBADF, errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP}
    try:
        descriptor = os.open(path, os.O_RDONLY)
    except OSError as error:
        if error.errno in unsupported:
            return
        raise
    try:
        try:
            os.fsync(descriptor)
        except OSError as error:
            if error.errno not in unsupported:
                raise
    finally:
        os.close(descriptor)


def _atomic_json(path: Path, value: dict) -> None:
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    encoded = (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def _integrity(path: Path) -> str:
    uri = path.as_uri() + "?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    try:
        connection.execute("PRAGMA query_only=ON")
        rows = connection.execute("PRAGMA integrity_check").fetchall()
        return "\n".join(str(row[0]) for row in rows)
    except sqlite3.Error as error:
        raise RestoreError(f"SQLite integrity check failed for {path}: {error}") from error
    finally:
        connection.close()


def _require_integrity(path: Path) -> None:
    result = _integrity(path)
    if result != "ok":
        raise RestoreError(f"integrity_check for {path} returned {result!r}")


def _sidecars(path: Path) -> list[str]:
    return [str(Path(str(path) + suffix)) for suffix in SIDECARS if Path(str(path) + suffix).exists()]


def _has_open_handle(path: Path) -> bool:
    executable = shutil.which("lsof")
    if not executable:
        raise RestoreError("lsof is unavailable; exact-path handle check cannot be proven")
    try:
        result = subprocess.run(
            [executable, "-t", "--", str(path)],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RestoreError(f"lsof exact-path check failed for {path}: {error}") from error
    if result.returncode == 1:
        return False
    if result.returncode != 0:
        raise RestoreError(f"lsof failed for {path}: {result.stderr.strip()}")
    return bool(result.stdout.strip())


def _assert_quiescent(path: Path, handle_probe: HandleProbe | None) -> None:
    sidecars = _sidecars(path)
    if sidecars:
        raise RestoreError(f"SQLite sidecars exist for {path}: {sidecars}")
    is_open = handle_probe(path) if handle_probe else _has_open_handle(path)
    if is_open:
        raise RestoreError(f"an exact-path database handle is open: {path}")


def _absolute_file(value: str | Path, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise RestoreError(f"{label} must be an absolute path: {path}")
    if path.is_symlink() or not path.is_file():
        raise RestoreError(f"{label} must be an existing regular, non-symlink file: {path}")
    return path.resolve(strict=True)


def _copy_durable(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as output_stream:
            with source.open("rb") as input_stream:
                shutil.copyfileobj(input_stream, output_stream, 1024 * 1024)
                output_stream.flush()
                os.fsync(output_stream.fileno())
    except BaseException:
        if destination.exists():
            destination.unlink()
        raise
    _fsync_file(destination)
    _fsync_directory(destination.parent)


def _record(manifest: dict, state: str, detail: str) -> None:
    manifest["state"] = state
    manifest["updatedAtUtc"] = _now()
    manifest["events"].append({"atUtc": manifest["updatedAtUtc"], "state": state, "detail": detail})


def _write(manifest_path: Path, manifest: dict, state: str, detail: str) -> None:
    _record(manifest, state, detail)
    _atomic_json(manifest_path, manifest)


def _mark_recovery_required(manifest_path: Path, manifest: dict, error: str) -> None:
    manifest["lastError"] = error
    if manifest["state"] != "RECOVERY_REQUIRED":
        _write(manifest_path, manifest, "RECOVERY_REQUIRED", error)


@contextmanager
def _manifest_lock(manifest_path: Path):
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = manifest_path.with_name(manifest_path.name + ".lock")
    with lock_path.open("a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def _make_manifest(
    operation_id: str,
    manifest_path: Path,
    targets: dict[str, Path],
    backups: dict[str, Path],
    expected_hashes: dict[str, str],
    pre_restore_hashes: dict[str, str],
    forensic_dir: Path,
    maintenance_ack: str,
    rollback_authority: str,
) -> dict:
    members = {}
    for member in MEMBERS:
        target = targets[member]
        backup = backups[member]
        members[member] = {
            "targetPath": str(target),
            "preRestoreSha256": pre_restore_hashes[member],
            "backupPath": str(backup),
            "expectedBackupSha256": expected_hashes[member],
            "stagingPath": str(target.with_name(f".{target.name}.{operation_id}.restore-stage")),
            "forensicPath": str(forensic_dir / f"{operation_id}-{member}-postimage.db"),
        }
    return {
        "schemaVersion": 1,
        "operationId": operation_id,
        "state": "PREPARED",
        "createdAtUtc": _now(),
        "updatedAtUtc": _now(),
        "targets": members,
        "replacementProgress": {member: False for member in MEMBERS},
        "verification": {"account": "PENDING", "publicConfig": "PENDING", "pair": "PENDING"},
        "maintenanceAcknowledgement": maintenance_ack,
        "rollbackAuthority": rollback_authority,
        "manifestPath": str(manifest_path),
        "pairAtomicityClaimed": False,
        "publishedFileMode": "0600",
        "lastError": None,
        "events": [{"atUtc": _now(), "state": "PREPARED", "detail": "both stages and forensic copies durable"}],
    }


def _validate_new_request(
    account_backup: str | Path,
    account_sha256: str,
    config_backup: str | Path,
    config_sha256: str,
    account_target: str | Path,
    config_target: str | Path,
    manifest: str | Path,
    forensic_dir: str | Path,
    maintenance_ack: str,
    rollback_authority: str,
    handle_probe: HandleProbe | None,
) -> tuple[dict[str, Path], dict[str, Path], dict[str, str], Path, Path]:
    if not maintenance_ack.strip():
        raise RestoreError("explicit maintenance acknowledgement is required")
    if not rollback_authority.strip():
        raise RestoreError("named rollback authority is required")
    targets = {
        "account": _absolute_file(account_target, "account target"),
        "publicConfig": _absolute_file(config_target, "public-config target"),
    }
    backups = {
        "account": _absolute_file(account_backup, "account backup"),
        "publicConfig": _absolute_file(config_backup, "public-config backup"),
    }
    expected = {"account": account_sha256.lower(), "publicConfig": config_sha256.lower()}
    for member in MEMBERS:
        if len(expected[member]) != 64 or any(char not in "0123456789abcdef" for char in expected[member]):
            raise RestoreError(f"invalid expected SHA-256 for {member}")
        if _sha256(backups[member]) != expected[member]:
            raise RestoreError(f"approved backup hash mismatch for {member}")
        _require_integrity(backups[member])
        if backups[member] == targets[member]:
            raise RestoreError(f"backup and target paths must differ for {member}")
    if targets["account"] == targets["publicConfig"]:
        raise RestoreError("account and public-config targets must be distinct")
    all_paths = [*targets.values(), *backups.values()]
    for index, path in enumerate(all_paths):
        if any(path.samefile(other) for other in all_paths[index + 1:]):
            raise RestoreError("target and backup paths must identify four distinct files")
    for target in targets.values():
        if target.stat().st_uid != os.geteuid():
            raise RestoreError(f"operator must own target before restore: {target}")
        _assert_quiescent(target, handle_probe)
    manifest_path = Path(manifest)
    if not manifest_path.is_absolute():
        raise RestoreError("manifest path must be absolute")
    manifest_path = manifest_path.parent.resolve() / manifest_path.name
    if manifest_path.exists():
        raise RestoreError(f"manifest already exists: {manifest_path}")
    forensic_path = Path(forensic_dir)
    if not forensic_path.is_absolute():
        raise RestoreError("forensic directory must be an absolute path")
    forensic_path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not forensic_path.is_dir():
        raise RestoreError("forensic path is not a directory")
    forensic_stat = forensic_path.stat()
    if forensic_stat.st_uid != os.geteuid() or stat.S_IMODE(forensic_stat.st_mode) & 0o077:
        raise RestoreError("forensic directory must be owned by the operator and mode 0700")
    return targets, backups, expected, manifest_path, forensic_path


def restore_pair(
    *,
    account_backup: str | Path,
    account_sha256: str,
    config_backup: str | Path,
    config_sha256: str,
    account_target: str | Path,
    config_target: str | Path,
    manifest: str | Path,
    forensic_dir: str | Path,
    maintenance_ack: str,
    rollback_authority: str,
    handle_probe: HandleProbe | None = None,
    fault_hook: FaultHook | None = None,
) -> dict:
    manifest_path = Path(manifest)
    if not manifest_path.is_absolute():
        raise RestoreError("manifest path must be absolute")
    manifest_path = manifest_path.parent.resolve() / manifest_path.name
    with _manifest_lock(manifest_path):
        targets, backups, expected, manifest_path, forensic_path = _validate_new_request(
            account_backup, account_sha256, config_backup, config_sha256,
            account_target, config_target, manifest_path, forensic_dir,
            maintenance_ack, rollback_authority, handle_probe,
        )
        operation_id = uuid.uuid4().hex
        pre_restore_hashes = {}
        for member in MEMBERS:
            _copy_durable(targets[member], forensic_path / f"{operation_id}-{member}-postimage.db")
            pre_restore_hashes[member] = _sha256(forensic_path / f"{operation_id}-{member}-postimage.db")
            if pre_restore_hashes[member] != _sha256(targets[member]):
                raise RestoreError(f"forensic copy verification failed for {member}")
            stage = targets[member].with_name(f".{targets[member].name}.{operation_id}.restore-stage")
            _copy_durable(backups[member], stage)
            if _sha256(stage) != expected[member]:
                raise RestoreError(f"staged backup hash mismatch for {member}")
            _require_integrity(stage)
        if fault_hook:
            fault_hook("after_staging", {})
        for member in MEMBERS:
            stage = targets[member].with_name(f".{targets[member].name}.{operation_id}.restore-stage")
            if _sha256(stage) != expected[member]:
                raise RestoreError(f"staged backup changed before PREPARED for {member}")
            _assert_quiescent(targets[member], handle_probe)
            if _sha256(targets[member]) != pre_restore_hashes[member]:
                raise RestoreError(f"{member} target changed while restore was being prepared")
        journal = _make_manifest(
            operation_id, manifest_path, targets, backups, expected, pre_restore_hashes, forensic_path,
            maintenance_ack, rollback_authority,
        )
        _atomic_json(manifest_path, journal)
        if fault_hook:
            fault_hook("after_prepared", journal)
        return _drive(manifest_path, journal, handle_probe, fault_hook)


def _load_manifest(path: Path) -> dict:
    try:
        manifest = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RestoreError(f"cannot read restore manifest; fail closed: {error}") from error
    required = {"schemaVersion", "operationId", "state", "targets", "replacementProgress", "verification", "events"}
    if not isinstance(manifest, dict) or not required.issubset(manifest):
        raise RestoreError("restore manifest schema is incomplete; fail closed")
    if manifest["schemaVersion"] != 1 or manifest["state"] not in STATES:
        raise RestoreError("unsupported or invalid manifest state; fail closed")
    if set(manifest["targets"]) != set(MEMBERS):
        raise RestoreError("manifest does not describe both pair members; fail closed")
    for member in MEMBERS:
        item = manifest["targets"][member]
        if not all(key in item for key in ("targetPath", "preRestoreSha256", "backupPath", "expectedBackupSha256", "stagingPath", "forensicPath")):
            raise RestoreError(f"manifest member is incomplete for {member}; fail closed")
    return manifest


def recover_pair(
    *,
    manifest: str | Path,
    maintenance_ack: str,
    rollback_authority: str,
    handle_probe: HandleProbe | None = None,
    fault_hook: FaultHook | None = None,
) -> dict:
    manifest_path = Path(manifest)
    if not manifest_path.is_absolute() or not maintenance_ack.strip() or not rollback_authority.strip():
        raise RestoreError("absolute manifest, maintenance acknowledgement, and rollback authority are required")
    manifest_path = manifest_path.parent.resolve() / manifest_path.name
    with _manifest_lock(manifest_path):
        journal = _load_manifest(manifest_path)
        if journal["state"] == "RECOVERY_REQUIRED":
            raise RestoreError("manifest is RECOVERY_REQUIRED; do not resume automatically")
        if journal["state"] == "COMPLETE":
            _verify_pair(journal, handle_probe=handle_probe)
            return journal
        journal["maintenanceAcknowledgement"] = maintenance_ack
        journal["rollbackAuthority"] = rollback_authority
        return _drive(manifest_path, journal, handle_probe, fault_hook)


def _member_paths(journal: dict, member: str) -> tuple[Path, Path, Path]:
    item = journal["targets"][member]
    return Path(item["targetPath"]), Path(item["stagingPath"]), Path(item["backupPath"])


def _mark_progress_from_disk(journal: dict) -> None:
    for member in MEMBERS:
        target, _, _ = _member_paths(journal, member)
        item = journal["targets"][member]
        actual = _sha256(target)
        if actual not in {item["preRestoreSha256"], item["expectedBackupSha256"]}:
            raise RestoreError(f"unexpected {member} target hash {actual}; no automatic replacement permitted")
        journal["replacementProgress"][member] = actual == item["expectedBackupSha256"]
    state = journal["state"]
    if state == "ACCOUNT_REPLACED" and not journal["replacementProgress"]["account"]:
        raise RestoreError("manifest says account replaced but target is still pre-restore")
    if state in {"CONFIG_REPLACED", "VERIFIED", "COMPLETE"} and not all(journal["replacementProgress"].values()):
        raise RestoreError(f"manifest state {state} disagrees with target hashes")


def _replace_member(
    manifest_path: Path,
    journal: dict,
    member: str,
    handle_probe: HandleProbe | None,
    fault_hook: FaultHook | None,
) -> None:
    target, stage, _ = _member_paths(journal, member)
    item = journal["targets"][member]
    if target.is_symlink() or not target.is_file():
        raise RestoreError(f"{member} target is no longer a regular file")
    actual = _sha256(target)
    if actual == item["expectedBackupSha256"]:
        journal["replacementProgress"][member] = True
        return
    if actual != item["preRestoreSha256"]:
        raise RestoreError(f"{member} target changed unexpectedly before replacement")
    if not stage.is_file() or stage.is_symlink() or _sha256(stage) != item["expectedBackupSha256"]:
        raise RestoreError(f"verified stage missing or changed for {member}")
    _assert_quiescent(target, handle_probe)
    _write(manifest_path, journal, journal["state"], f"{member} replacement intent persisted")
    os.replace(stage, target)
    _fsync_directory(target.parent)
    if fault_hook:
        label = "account" if member == "account" else "config"
        fault_hook(f"after_{label}_replace_before_state", journal)
    if _sha256(target) != item["expectedBackupSha256"]:
        raise RestoreError(f"{member} target hash differs immediately after replacement")
    journal["replacementProgress"][member] = True
    next_state = "ACCOUNT_REPLACED" if member == "account" else "CONFIG_REPLACED"
    _write(manifest_path, journal, next_state, f"{member} atomically replaced and hash verified")


def _verify_pair(
    journal: dict,
    fault_hook: FaultHook | None = None,
    handle_probe: HandleProbe | None = None,
) -> None:
    for member in MEMBERS:
        target, _, _ = _member_paths(journal, member)
        item = journal["targets"][member]
        if _sha256(target) != item["expectedBackupSha256"]:
            raise RestoreError(f"final {member} hash does not match approved backup")
        _assert_quiescent(target, handle_probe)
        _require_integrity(target)
        journal["verification"][member] = "PASS"
        if member == "account" and fault_hook:
            fault_hook("during_verification", journal)
    journal["verification"]["pair"] = "PASS"


def _drive(
    manifest_path: Path,
    journal: dict,
    handle_probe: HandleProbe | None,
    fault_hook: FaultHook | None,
) -> dict:
    try:
        _mark_progress_from_disk(journal)
        if journal["state"] == "PREPARED" and journal["replacementProgress"]["account"]:
            _write(manifest_path, journal, "ACCOUNT_REPLACED", "account hash reconciled from disk after restart")
        if not journal["replacementProgress"]["account"]:
            _replace_member(manifest_path, journal, "account", handle_probe, fault_hook)
        if not journal["replacementProgress"]["account"]:
            raise RestoreError("account replacement is not verified")
        if journal["state"] == "PREPARED":
            _write(manifest_path, journal, "ACCOUNT_REPLACED", "account already matched approved backup")
        if journal["state"] == "PREPARED" or journal["state"] == "ACCOUNT_REPLACED":
            if fault_hook and journal["state"] == "ACCOUNT_REPLACED":
                fault_hook("after_account_state", journal)
            if not journal["replacementProgress"]["publicConfig"]:
                _replace_member(manifest_path, journal, "publicConfig", handle_probe, fault_hook)
        if not all(journal["replacementProgress"].values()):
            raise RestoreError("paired replacement progress is incomplete")
        if journal["state"] not in {"CONFIG_REPLACED", "VERIFIED"}:
            _write(manifest_path, journal, "CONFIG_REPLACED", "both target hashes match approved pair")
        _verify_pair(journal, fault_hook, handle_probe)
        if journal["state"] != "VERIFIED":
            _write(manifest_path, journal, "VERIFIED", "both hashes and integrity checks passed")
        if fault_hook:
            fault_hook("after_verified", journal)
        _write(manifest_path, journal, "COMPLETE", "paired rollback complete; application remains stopped")
        return journal
    except Exception as error:
        if journal.get("state") != "RECOVERY_REQUIRED":
            try:
                _mark_recovery_required(manifest_path, journal, str(error))
            except Exception:
                pass
        raise


def _add_restore_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--account-backup", required=True)
    parser.add_argument("--account-sha256", required=True)
    parser.add_argument("--config-backup", required=True)
    parser.add_argument("--config-sha256", required=True)
    parser.add_argument("--account-target", required=True)
    parser.add_argument("--config-target", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--forensic-dir", required=True)
    parser.add_argument("--maintenance-ack", required=True)
    parser.add_argument("--rollback-authority", required=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    restore_parser = commands.add_parser("restore", help="prepare and execute a paired restore")
    _add_restore_arguments(restore_parser)
    recover_parser = commands.add_parser("recover", help="resume a journaled paired restore")
    recover_parser.add_argument("--manifest", required=True)
    recover_parser.add_argument("--maintenance-ack", required=True)
    recover_parser.add_argument("--rollback-authority", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "restore":
            result = restore_pair(
                account_backup=args.account_backup,
                account_sha256=args.account_sha256,
                config_backup=args.config_backup,
                config_sha256=args.config_sha256,
                account_target=args.account_target,
                config_target=args.config_target,
                manifest=args.manifest,
                forensic_dir=args.forensic_dir,
                maintenance_ack=args.maintenance_ack,
                rollback_authority=args.rollback_authority,
            )
        else:
            result = recover_pair(
                manifest=args.manifest,
                maintenance_ack=args.maintenance_ack,
                rollback_authority=args.rollback_authority,
            )
    except (OSError, RestoreError, sqlite3.Error) as error:
        print(f"RESTORE STOP: {error}", file=sys.stderr)
        return 2
    print(json.dumps({"operationId": result["operationId"], "state": result["state"], "manifest": result["manifestPath"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())