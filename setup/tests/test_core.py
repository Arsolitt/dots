"""std-lib unittest coverage for the installer core."""

from __future__ import annotations

import importlib.util
import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from dotfiles import detect as detector
from dotfiles import links as linker
from dotfiles import profile as profiles
from dotfiles import steps as stepmod
from dotfiles.steps import s55_session as session_step

SETUP_DIR = Path(__file__).resolve().parents[1]


class RecordingContext:
    """Minimal Context stand-in that records log lines instead of printing."""

    def __init__(self, dry_run: bool = False, features: dict[str, bool] | None = None) -> None:
        self.root = Path("/")
        self.dry_run = dry_run
        self.assume_yes = False
        self.no_backup = False
        self.features = features or {}
        self.errors: list[str] = []
        self.logs: list[tuple[str, str]] = []

    def feature(self, name: str) -> bool:
        return bool(self.features.get(name, False))

    def log_info(self, message: str) -> None:
        self.logs.append(("info", message))

    def log_ok(self, message: str) -> None:
        self.logs.append(("ok", message))

    def log_skip(self, message: str) -> None:
        self.logs.append(("skip", message))

    def log_warn(self, message: str) -> None:
        self.logs.append(("warn", message))

    def log_err(self, message: str) -> None:
        self.errors.append(message)
        self.logs.append(("err", message))

    def ensure_dir(self, path: str | Path) -> None:
        if not self.dry_run:
            Path(path).mkdir(parents=True, exist_ok=True)


class LinkerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root = base / "dots"
        self.home = base / "home"
        self.root.mkdir()
        self.home.mkdir()
        self.ctx = RecordingContext()
        self.linker = linker.Linker(self.ctx, self.root, home=self.home)

    def _source(self, name: str = "tool.conf") -> Path:
        src = self.root / name
        src.write_text("repo content", encoding="utf-8")
        return src

    def test_fresh_link_created(self) -> None:
        src = self._source()
        dst = self.home / ".config" / "tool.conf"
        created = self.linker.reconcile([linker.Link(src, dst)])
        self.assertEqual(created, 1)
        self.assertTrue(dst.is_symlink())
        self.assertEqual(os.readlink(dst), str(src))

    def test_second_reconcile_is_skip(self) -> None:
        src = self._source()
        dst = self.home / ".config" / "tool.conf"
        self.linker.reconcile([linker.Link(src, dst)])
        self.ctx.logs.clear()
        created = self.linker.reconcile([linker.Link(src, dst)])
        self.assertEqual(created, 0)
        self.assertIn(("skip", f"already linked: {dst}"), self.ctx.logs)
        self.assertEqual(list(dst.parent.glob("tool.conf.backup-*")), [])

    def test_backup_naming(self) -> None:
        src = self._source()
        dst = self.home / ".config" / "tool.conf"
        dst.parent.mkdir(parents=True)
        dst.write_text("old content", encoding="utf-8")

        self.linker.reconcile([linker.Link(src, dst)])

        backups = list(dst.parent.glob("tool.conf.backup-*"))
        self.assertEqual(len(backups), 1)
        self.assertRegex(backups[0].name, r"^tool\.conf\.backup-\d{8}-\d{6}$")
        self.assertEqual(backups[0].read_text(encoding="utf-8"), "old content")
        self.assertTrue(dst.is_symlink())

    def test_no_backup_replaces_existing(self) -> None:
        src = self._source()
        dst = self.home / ".config" / "tool.conf"
        dst.parent.mkdir(parents=True)
        dst.write_text("old content", encoding="utf-8")
        no_backup = linker.Linker(self.ctx, self.root, backup=False, home=self.home)

        no_backup.reconcile([linker.Link(src, dst)])

        self.assertTrue(dst.is_symlink())
        self.assertEqual(os.readlink(dst), str(src))
        self.assertEqual(list(dst.parent.glob("tool.conf.backup-*")), [])

    def test_source_equals_destination_guard(self) -> None:
        src = self._source()
        created = self.linker.reconcile([linker.Link(src, src)])
        self.assertEqual(created, 0)
        self.assertFalse(src.is_symlink())
        self.assertEqual(src.read_text(encoding="utf-8"), "repo content")
        self.assertIn(("warn", f"source equals destination, skip: {src}"), self.ctx.logs)


class CleanupTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root = base / "dots"
        self.home = base / "home"
        self.config = self.home / ".config"
        self.outside = base / "outside"
        for directory in (self.root, self.config, self.outside):
            directory.mkdir(parents=True)
        self.ctx = RecordingContext()
        self.linker = linker.Linker(self.ctx, self.root, home=self.home)

    def test_cleanup_removes_only_repo_broken_links(self) -> None:
        existing = self.root / "live.conf"
        existing.write_text("x", encoding="utf-8")
        repo_broken = self.config / "repo-broken"
        foreign_broken = self.config / "foreign-broken"
        valid_repo = self.config / "valid-repo"
        regular = self.config / "regular"
        os.symlink(self.root / "gone.conf", repo_broken)
        os.symlink(self.outside / "gone.conf", foreign_broken)
        os.symlink(existing, valid_repo)
        regular.write_text("plain", encoding="utf-8")

        removed = self.linker.cleanup([self.config])

        self.assertEqual(removed, 1)
        self.assertFalse(os.path.lexists(repo_broken))
        self.assertTrue(os.path.lexists(foreign_broken))
        self.assertTrue(valid_repo.is_symlink())
        self.assertTrue(regular.is_file())
        self.assertTrue(os.path.exists(existing))

    def test_cleanup_scans_home_one_level_and_skips_directories(self) -> None:
        home_broken = self.home / "mimeapps.list"
        os.symlink(self.root / "gone.list", home_broken)
        nested = self.home / "nested"
        nested.mkdir()
        nested_broken = nested / "settings.conf"
        os.symlink(self.root / "gone.conf", nested_broken)

        removed = self.linker.cleanup([])

        self.assertEqual(removed, 1)
        self.assertFalse(os.path.lexists(home_broken))
        self.assertTrue(os.path.lexists(nested_broken))


class ProfileTest(unittest.TestCase):
    def test_auto_uses_detected(self) -> None:
        profile = profiles.Profile(features={"npu": "auto", "docker": "auto"})
        resolved = profiles.resolve({"npu": True, "docker": False}, profile)
        self.assertEqual(resolved, {"docker": False, "npu": True})

    def test_on_and_off_override_detection(self) -> None:
        profile = profiles.Profile(
            features={"npu": "off", "docker": "on", "fingerprint": "on"}
        )
        resolved = profiles.resolve({"npu": True, "docker": False}, profile)
        self.assertEqual(
            resolved,
            {"docker": True, "fingerprint": True, "npu": False},
        )

    def test_invalid_value_raises(self) -> None:
        profile = profiles.Profile(features={"npu": "maybe"})
        with self.assertRaises(ValueError) as caught:
            profiles.resolve({"npu": True}, profile)
        self.assertIn("npu", str(caught.exception))
        self.assertIn("maybe", str(caught.exception))

    def test_device_profile_then_explicit_overlay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            devices = root / "setup" / "devices"
            devices.mkdir(parents=True)
            (devices / "host.toml").write_text(
                '[features]\nnpu = "auto"\ndocker = "on"\n'
                '[packages]\nextra = ["btop"]\n'
                '[links]\nskip = ["kitty"]\n',
                encoding="utf-8",
            )
            explicit = root / "local.toml"
            explicit.write_text(
                '[features]\nnpu = "on"\n'
                '[packages]\nextra = ["tmux"]\n'
                '[links]\nskip = ["waybar"]\n',
                encoding="utf-8",
            )

            loaded = profiles.load(root, "host", explicit)

        self.assertEqual(loaded.features, {"npu": "on", "docker": "on"})
        self.assertEqual(loaded.extra_packages, ["btop", "tmux"])
        self.assertEqual(loaded.skip_links, ["kitty", "waybar"])

    def test_extra_links_merge(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            devices = root / "setup" / "devices"
            devices.mkdir(parents=True)
            (devices / "host.toml").write_text(
                '[links]\nskip = []\n'
                '[[links.extra]]\nsrc = "nvim"\ndst = "~/.config/nvim"\n',
                encoding="utf-8",
            )
            loaded = profiles.load(root, "host")

        self.assertEqual(loaded.extra_links, [("nvim", "~/.config/nvim")])

    def test_extra_link_requires_both_paths(self) -> None:
        for body in (
            '[[links.extra]]\nsrc = "nvim"\n',
            '[[links.extra]]\ndst = "~/.config/nvim"\n',
        ):
            with self.subTest(body=body), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                devices = root / "setup" / "devices"
                devices.mkdir(parents=True)
                (devices / "host.toml").write_text(body, encoding="utf-8")
                with self.assertRaises(ValueError) as caught:
                    profiles.load(root, "host")
                self.assertIn("links.extra", str(caught.exception))

    def test_missing_profile_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            loaded = profiles.load(Path(tmp), "no-such-host")
        self.assertEqual(loaded.features, {})
        self.assertEqual(loaded.extra_packages, [])
        self.assertEqual(loaded.skip_links, [])


class DetectTest(unittest.TestCase):
    def test_battery_reads_power_supply_type(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            supply = Path(tmp)
            (supply / "BAT0").mkdir()
            (supply / "BAT0" / "type").write_text("Battery\n", encoding="utf-8")
            (supply / "AC").mkdir()
            (supply / "AC" / "type").write_text("Mains\n", encoding="utf-8")
            self.assertTrue(detector.battery(supply))
            self.assertFalse(detector.battery(supply / "missing"))

    def test_charge_limit_needs_battery_and_known_vendor(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            vendor = Path(tmp) / "sys_vendor"
            product = Path(tmp) / "product_name"
            vendor.write_text("XIAOMI\n", encoding="utf-8")
            product.write_text("Redmi Book Pro 16 2026\n", encoding="utf-8")
            self.assertTrue(detector.charge_limit(True, vendor, product))
            self.assertFalse(detector.charge_limit(False, vendor, product))
            vendor.write_text("LENOVO\n", encoding="utf-8")
            product.write_text("ThinkPad X1\n", encoding="utf-8")
            self.assertFalse(detector.charge_limit(True, vendor, product))

    def test_npu_reads_device_driver(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            accel = Path(tmp) / "accel"
            device = accel / "accel0" / "device"
            device.mkdir(parents=True)
            uevent = device / "uevent"
            uevent.write_text("DRIVER=intel_vpu\n", encoding="utf-8")
            self.assertTrue(detector.npu(accel))
            uevent.write_text("DRIVER=virtio\n", encoding="utf-8")
            self.assertFalse(detector.npu(accel))
            self.assertFalse(detector.npu(accel / "missing"))

    def test_npu_falls_back_to_node_existence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            accel = Path(tmp) / "accel"
            (accel / "accel0").mkdir(parents=True)
            self.assertTrue(detector.npu(accel))

    def test_fingerprint_matches_usb_vendor(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            usb = Path(tmp)
            (usb / "1-1").mkdir()
            (usb / "1-1" / "idVendor").write_text("27c6\n", encoding="utf-8")
            self.assertTrue(detector.fingerprint(usb))
            (usb / "1-1" / "idVendor").write_text("1d6b\n", encoding="utf-8")
            self.assertFalse(detector.fingerprint(usb))


class StepsPlanTest(unittest.TestCase):
    def setUp(self) -> None:
        self.steps = [
            stepmod.Step("pacman", "packages"),
            stepmod.Step("npu", "NPU denoiser", requires=("npu",)),
            stepmod.Step("configs", "config symlinks"),
        ]

    def test_only_filters_unselected_steps(self) -> None:
        rows = stepmod.plan(self.steps, RecordingContext(features={"npu": True}), only=["configs"])
        self.assertEqual(
            [(step.name, run, reason) for step, run, reason in rows],
            [
                ("pacman", False, "not selected"),
                ("npu", False, "not selected"),
                ("configs", True, ""),
            ],
        )

    def test_skip_flag_reason(self) -> None:
        rows = stepmod.plan(
            self.steps,
            RecordingContext(features={"npu": True}),
            skip=["pacman"],
        )
        self.assertEqual(rows[0][1:], (False, "skipped by flag"))
        self.assertTrue(rows[1][1])

    def test_missing_requirement_is_a_skip(self) -> None:
        rows = stepmod.plan(self.steps, RecordingContext(features={"npu": False}))
        self.assertEqual(rows[1][1:], (False, "requires npu"))
        self.assertTrue(rows[2][1])

    def test_requirement_satisfied_by_profile(self) -> None:
        rows = stepmod.plan(self.steps, RecordingContext(features={"npu": True}))
        self.assertEqual(rows[1][1:], (True, ""))

    def test_discover_returns_list(self) -> None:
        self.assertIsInstance(stepmod.discover(), list)


class SessionContext(RecordingContext):
    """RecordingContext extended with the probe and run surface of steps."""

    def __init__(self, dry_run: bool = False) -> None:
        super().__init__(dry_run=dry_run)
        self.runs: list[tuple[list[str], bool]] = []
        self.enabled: set[str] = set()

    def have(self, command: str) -> bool:
        return True

    def ok(self, cmd, sudo: bool = False, cwd=None) -> bool:
        argv = [str(part) for part in cmd]
        return argv[-1] in self.enabled

    def run(self, cmd, sudo: bool = False, cwd=None, check=True, capture=False):
        self.runs.append(([str(part) for part in cmd], sudo))
        return "" if capture else None


class SessionStepTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        (self.repo / "greetd").mkdir()
        self.artifact = self.repo / "greetd" / "config.toml"
        self.artifact.write_text("[terminal]\nvt = 1\n", encoding="utf-8")
        self.target = self.repo / "etc-greetd-config.toml"
        self.unit_dir = self.repo / "units"
        self.unit_dir.mkdir()
        (self.unit_dir / "greetd.service").write_text("", encoding="utf-8")
        for name, value in (("CONFIG", self.target), ("UNIT_DIRS", (self.unit_dir,))):
            patcher = mock.patch.object(session_step, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def _ctx(self) -> SessionContext:
        ctx = SessionContext()
        ctx.root = self.repo
        return ctx

    def test_matching_config_is_skipped(self) -> None:
        self.target.write_text(self.artifact.read_text(encoding="utf-8"), encoding="utf-8")
        ctx = self._ctx()
        with mock.patch.object(session_step, "UNITS", ()):
            session_step.STEP.run(ctx)
        self.assertEqual(ctx.runs, [])
        self.assertIn(
            ("skip", f"session: {self.target} already matches the repo artifact"),
            ctx.logs,
        )

    def test_changed_config_backs_up_and_installs(self) -> None:
        self.target.write_text("old\n", encoding="utf-8")
        ctx = self._ctx()
        with mock.patch.object(session_step, "UNITS", ()):
            session_step.STEP.run(ctx)
        self.assertEqual(len(ctx.runs), 2)
        backup_cmd, backup_sudo = ctx.runs[0]
        self.assertEqual(backup_cmd[:3], ["cp", "-p", str(self.target)])
        self.assertIn(".dots-backup-", backup_cmd[3])
        self.assertTrue(backup_sudo)
        self.assertEqual(
            ctx.runs[1],
            (["install", "-m", "0644", str(self.artifact), str(self.target)], True),
        )

    def test_disabled_unit_is_enabled(self) -> None:
        self.target.write_text(self.artifact.read_text(encoding="utf-8"), encoding="utf-8")
        ctx = self._ctx()
        ctx.enabled = set()
        with mock.patch.object(session_step, "UNITS", ("greetd",)):
            session_step.STEP.run(ctx)
        self.assertIn((["systemctl", "enable", "greetd"], True), ctx.runs)

    def test_enabled_unit_is_skipped(self) -> None:
        self.target.write_text(self.artifact.read_text(encoding="utf-8"), encoding="utf-8")
        ctx = self._ctx()
        ctx.enabled = {"greetd"}
        with mock.patch.object(session_step, "UNITS", ("greetd",)):
            session_step.STEP.run(ctx)
        self.assertEqual(ctx.runs, [])
        self.assertIn(("skip", "session: greetd already enabled"), ctx.logs)

    def test_absent_unit_file_is_skipped(self) -> None:
        self.target.write_text(self.artifact.read_text(encoding="utf-8"), encoding="utf-8")
        (self.unit_dir / "greetd.service").unlink()
        ctx = self._ctx()
        with mock.patch.object(session_step, "UNITS", ("greetd",)):
            session_step.STEP.run(ctx)
        self.assertEqual(ctx.runs, [])
        self.assertIn(("skip", "session: no unit file for greetd"), ctx.logs)


def _load_entrypoint(name: str):
    path = SETUP_DIR / f"{name}.py"
    spec = importlib.util.spec_from_file_location(f"dots_{name}", path)
    module = importlib.util.module_from_spec(spec)
    with redirect_stdout(io.StringIO()):
        spec.loader.exec_module(module)
    return module


class EntrypointCliTest(unittest.TestCase):
    def test_install_parser_flags_and_help(self) -> None:
        module = _load_entrypoint("install")
        parser = module.build_parser()
        args = parser.parse_args(
            ["--dry-run", "--only", "configs", "--skip", "npu", "--profile", "/tmp/p.toml",
             "--no-backup", "--list"]
        )
        self.assertTrue(args.dry_run)
        self.assertEqual(args.only, ["configs"])
        self.assertEqual(args.skip, ["npu"])
        self.assertEqual(args.profile, "/tmp/p.toml")
        self.assertTrue(args.no_backup)
        self.assertTrue(args.list)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                parser.parse_args(["--help"])
        self.assertEqual(caught.exception.code, 0)

    def test_links_parser_flags_and_help(self) -> None:
        module = _load_entrypoint("links")
        parser = module.build_parser()
        args = parser.parse_args(
            ["--dry-run", "--no-backup", "--cleanup", "--profile", "/tmp/p.toml"]
        )
        self.assertTrue(args.dry_run)
        self.assertTrue(args.no_backup)
        self.assertTrue(args.cleanup)
        self.assertEqual(args.profile, "/tmp/p.toml")
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                parser.parse_args(["--help"])
        self.assertEqual(caught.exception.code, 0)


class ContextRunTest(unittest.TestCase):
    def test_dry_run_logs_and_skips_subprocess(self) -> None:
        from dotfiles import cli

        ctx = cli.Context(root=Path("/tmp"), dry_run=True)
        with redirect_stdout(io.StringIO()) as out:
            ctx.run(["definitely-not-a-real-command"])
        self.assertIn("would run: definitely-not-a-real-command", out.getvalue())
        self.assertEqual(ctx.errors, [])

    def test_failed_command_is_recorded(self) -> None:
        from dotfiles import cli

        ctx = cli.Context(root=Path("/tmp"))
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as err:
            ctx.run(["false"], check=True)
        self.assertEqual(len(ctx.errors), 1)
        self.assertIn("command failed", err.getvalue())

    def test_quiet_capture_never_records(self) -> None:
        from dotfiles import cli

        ctx = cli.Context(root=Path("/tmp"))
        stdout = ctx.capture(["sh", "-c", "printf probe; exit 3"])
        self.assertEqual(stdout, "probe")
        self.assertEqual(ctx.errors, [])


if __name__ == "__main__":
    unittest.main()
