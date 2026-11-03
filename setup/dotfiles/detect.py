"""Host detection: distro, chassis and feature probes."""

from __future__ import annotations

import os
import shutil
import socket
import sys
from dataclasses import dataclass, field
from pathlib import Path

OS_RELEASE = Path("/etc/os-release")
ARCH_RELEASE = Path("/etc/arch-release")
CHASSIS_TYPE = Path("/sys/class/dmi/id/chassis_type")
POWER_SUPPLY = Path("/sys/class/power_supply")
SYS_VENDOR = Path("/sys/class/dmi/id/sys_vendor")
PRODUCT_NAME = Path("/sys/class/dmi/id/product_name")
ACCEL_DIR = Path("/sys/class/accel")
USB_DEVICES = Path("/sys/bus/usb/devices")
BITLAND_WMI_DEV = Path("/sys/bus/wmi/drivers/bitland-mifs-wmi/B60BFB48-3E5B-49E4-A0E9-8CFFE1B3434B-4")

LAPTOP_CHASSIS = frozenset({8, 9, 10, 14})
CHARGE_LIMIT_VENDORS = ("XIAOMI", "REDMI BOOK")
FINGERPRINT_VENDORS = frozenset({"27c6", "138a", "06cb", "04f3", "08ff", "1c7a"})


class UnsupportedHost(RuntimeError):
    """Raised when the host is not a supported Arch-derived Linux."""


@dataclass(frozen=True)
class Device:
    hostname: str
    distro: str
    chassis: str
    detected: dict[str, bool] = field(default_factory=dict)


def hostname() -> str:
    return socket.gethostname()


def os_release(path: Path = OS_RELEASE) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return values
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        values[key] = raw.strip().strip('"').strip("'")
    return values


def distro() -> str:
    return os_release().get("ID", "unknown") or "unknown"


def is_arch_derived() -> bool:
    if ARCH_RELEASE.exists():
        return True
    values = os_release()
    ids = {values.get("ID", "")}
    ids.update(values.get("ID_LIKE", "").split())
    return "arch" in ids


def check_host() -> str:
    """Return the distro label or raise UnsupportedHost."""
    if sys.platform != "linux":
        raise UnsupportedHost(f"{sys.platform}/{distro()}")
    if not is_arch_derived():
        raise UnsupportedHost(f"linux/{distro()} is not Arch-derived")
    return distro()


def chassis(path: Path = CHASSIS_TYPE) -> str:
    try:
        raw = path.read_text(encoding="utf-8").strip()
    except OSError:
        return "unknown"
    try:
        value = int(raw)
    except ValueError:
        return "unknown"
    return "laptop" if value in LAPTOP_CHASSIS else "desktop"


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def battery(power_supply: Path = POWER_SUPPLY) -> bool:
    """True when a ``BAT*`` power supply reports type ``Battery``."""
    try:
        entries = sorted(power_supply.glob("BAT*"))
    except OSError:
        return False
    return any(_read(entry / "type") == "Battery" for entry in entries)


def charge_limit(battery_present: bool, vendor: Path = SYS_VENDOR,
                 product: Path = PRODUCT_NAME) -> bool:
    """True when the vendor firmware implements the WMI ``WMAA`` call."""
    if not battery_present:
        return False
    model = f"{_read(vendor)} {_read(product)}".upper()
    return any(marker in model for marker in CHARGE_LIMIT_VENDORS)


def npu(accel: Path = ACCEL_DIR) -> bool:
    """True when an accel node exists and is driven by ``intel_vpu``."""
    node = accel / "accel0"
    if not node.exists():
        return False
    uevent = _read(node / "device" / "uevent")
    driver = next(
        (line.partition("=")[2] for line in uevent.splitlines()
         if line.startswith("DRIVER=")),
        "",
    )
    if driver:
        return driver == "intel_vpu"
    link = node / "device" / "driver"
    try:
        return Path(os.readlink(link)).name == "intel_vpu"
    except OSError:
        return True


def fingerprint(usb: Path = USB_DEVICES,
                vendors: frozenset[str] = FINGERPRINT_VENDORS) -> bool:
    """True when a known USB fingerprint reader vendor is present."""
    try:
        id_files = list(usb.glob("*/idVendor"))
    except OSError:
        return False
    return any(_read(path).lower() in vendors for path in id_files)


def docker() -> bool:
    return shutil.which("docker") is not None


def bitland_sleep_fix(dev: Path = BITLAND_WMI_DEV) -> bool:
    """True when the bitland-mifs-wmi control device is present."""
    return dev.is_dir()


def device() -> Device:
    """Describe this host and probe its hardware features."""
    has_battery = battery()
    return Device(
        hostname=hostname(),
        distro=distro(),
        chassis=chassis(),
        detected={
            "fingerprint": fingerprint(),
            "battery": has_battery,
            "charge_limit": charge_limit(has_battery),
            "npu": npu(),
            "docker": docker(),
            "bitland_sleep_fix": bitland_sleep_fix(),
        },
    )
