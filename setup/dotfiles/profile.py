"""Device profiles: feature overrides, extra packages and skipped links."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

PROFILE_ENV = "DOTS_PROFILE"
VALID_FEATURES = ("auto", "on", "off")


@dataclass
class Profile:
    features: dict[str, str] = field(default_factory=dict)
    extra_packages: list[str] = field(default_factory=list)
    skip_links: list[str] = field(default_factory=list)
    extra_links: list[tuple[str, str]] = field(default_factory=list)


def device_path(root: str | Path, hostname: str) -> Path:
    return Path(root) / "setup" / "devices" / f"{hostname}.toml"


def explicit_path(root: str | Path, explicit: str | Path | None) -> Path | None:
    chosen = explicit or os.environ.get(PROFILE_ENV)
    if not chosen:
        return None
    return Path(chosen).expanduser()


def path(root: str | Path, hostname: str, explicit: str | Path | None = None) -> Path | None:
    """Profile used for this run, or None when no profile file exists."""
    override = explicit_path(root, explicit)
    if override is not None:
        return override
    base = device_path(root, hostname)
    return base if base.is_file() else None


def _merge(into: Profile, source: Path) -> None:
    if not source.is_file():
        return
    data = tomllib.loads(source.read_text(encoding="utf-8"))

    features = data.get("features", {})
    if not isinstance(features, dict):
        raise ValueError(f"{source}: [features] must be a table")
    into.features.update(features)

    packages = data.get("packages", {})
    extra = packages.get("extra", []) if isinstance(packages, dict) else []
    if not isinstance(extra, list):
        raise ValueError(f"{source}: packages.extra must be a list")
    into.extra_packages.extend(str(item) for item in extra)

    links = data.get("links", {})
    skip = links.get("skip", []) if isinstance(links, dict) else []
    if not isinstance(skip, list):
        raise ValueError(f"{source}: links.skip must be a list")
    into.skip_links.extend(str(item) for item in skip)

    extra = links.get("extra", []) if isinstance(links, dict) else []
    if not isinstance(extra, list):
        raise ValueError(f"{source}: links.extra must be an array of tables")
    for index, entry in enumerate(extra, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{source}: links.extra[{index}] must be a table")
        pair: list[str] = []
        for key in ("src", "dst"):
            value = entry.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(
                    f"{source}: links.extra[{index}].{key} must be a non-empty string"
                )
            pair.append(value.strip())
        into.extra_links.append((pair[0], pair[1]))


def load(root: str | Path, hostname: str, explicit: str | Path | None = None) -> Profile:
    """Load the device profile, then overlay the explicit profile on top."""
    loaded = Profile()
    _merge(loaded, device_path(root, hostname))
    override = explicit_path(root, explicit)
    if override is not None:
        _merge(loaded, override)
    return loaded


def resolve(detected: dict[str, bool], profile: Profile) -> dict[str, bool]:
    resolved: dict[str, bool] = {}
    for name in sorted(set(detected) | set(profile.features)):
        raw = profile.features.get(name, "auto")
        resolved[name] = _resolve_one(name, raw, detected.get(name, False))
    return resolved


def _resolve_one(name: str, raw: object, detected_value: bool) -> bool:
    if raw == "auto":
        return bool(detected_value)
    if raw == "on":
        return True
    if raw == "off":
        return False
    raise ValueError(
        f"invalid feature value for {name}: {raw!r} (expected one of {', '.join(VALID_FEATURES)})"
    )
