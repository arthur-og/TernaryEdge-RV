#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Final, Sequence

TARGET_PART: Final = "xc7s50csga324-1"
CANONICAL_SOURCES: Final[tuple[str, ...]] = (
    "npu_v2_pkg.v",
    "ternary_mac.v",
    "ternary_mac_array.v",
    "adder_tree_64.v",
    "postprocess_unit.v",
    "wishbone_master.v",
    "npu_ternaria_top_v2.v",
)
REPOSITORY_ROOT: Final = Path(__file__).resolve().parents[2]
DEFAULT_GATEWARE_DIR: Final = REPOSITORY_ROOT / "build/realdigital_urbana/gateware"
DEFAULT_RTL_DIR: Final = REPOSITORY_ROOT / "hardware/npu_rtl"

_TCL_ARGUMENT: Final = r"(?:\{([^{}]*)\}|\"([^\"]*)\"|'([^']*)'|(\S+))"
_PART_ARGUMENT: Final = re.compile(rf"(?<!\S)-part\s+{_TCL_ARGUMENT}(?=\s|$)")
_READ_VERILOG: Final = re.compile(rf"^\s*read_verilog\s+{_TCL_ARGUMENT}")
_NUMBER: Final = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
_SUMMARY_TITLE: Final = re.compile(r"^\s*\|?\s*Design Timing Summary\s*\|?\s*$")
_SUMMARY_HEADER: Final = re.compile(r"\bWNS\(ns\)\s+TNS\(ns\)")
_SUMMARY_ROW: Final = re.compile(rf"^\s*\|?\s*({_NUMBER})\s+({_NUMBER})\b")


@dataclass(frozen=True, slots=True)
class GateConfig:
    gateware_dir: Path
    rtl_dir: Path


@dataclass(frozen=True, slots=True)
class TimingSummary:
    wns: Decimal
    tns: Decimal


@dataclass(frozen=True, slots=True)
class GateFailure(Exception):
    messages: tuple[str, ...]

    def __str__(self) -> str:
        return "\n".join(self.messages)


def _argument_value(match: re.Match[str]) -> str | None:
    return next((group for group in match.groups() if group is not None), None)


def _single_artifact(directory: Path, pattern: str, label: str) -> Path | None:
    candidates = tuple(sorted(path for path in directory.glob(pattern) if path.is_file()))
    if not candidates:
        return None
    if len(candidates) > 1:
        names = ", ".join(str(path) for path in candidates)
        raise GateFailure((f"expected one {label} matching {pattern}, found: {names}",))
    return candidates[0]


def _resolved_tcl_sources(tcl_path: Path, tcl_text: str) -> tuple[Path, ...]:
    paths: list[Path] = []
    for line in tcl_text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        match = _READ_VERILOG.match(line)
        if match is None:
            continue
        raw_path = _argument_value(match)
        if raw_path is None:
            continue
        source_path = Path(raw_path).expanduser()
        if not source_path.is_absolute():
            source_path = tcl_path.parent / source_path
        paths.append(source_path.resolve())
    return tuple(paths)


def _tcl_parts(tcl_text: str) -> tuple[str, ...]:
    parts: list[str] = []
    for line in tcl_text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        for match in _PART_ARGUMENT.finditer(line):
            part = _argument_value(match)
            if part is not None:
                parts.append(part)
    return tuple(parts)


def _parse_timing_summary(report_text: str) -> TimingSummary:
    in_summary = False
    saw_header = False
    for line in report_text.splitlines():
        if _SUMMARY_TITLE.match(line) is not None:
            in_summary = True
            continue
        if not in_summary:
            continue
        if not saw_header:
            saw_header = _SUMMARY_HEADER.search(line) is not None
            continue
        row = _SUMMARY_ROW.match(line)
        if row is not None:
            return TimingSummary(Decimal(row.group(1)), Decimal(row.group(2)))
    raise GateFailure(("routed timing report lacks a Design Timing Summary data row",))


def _check_timing_count(report_text: str, check_name: str) -> int | None:
    pattern = re.compile(rf"checking\s+{re.escape(check_name)}\s*\((\d+)\)")
    counts = tuple(int(match.group(1)) for match in pattern.finditer(report_text))
    return max(counts) if counts else None


def _validate_tcl(
    tcl_path: Path,
    rtl_dir: Path,
    errors: list[str],
) -> None:
    tcl_text = tcl_path.read_text(encoding="utf-8")
    parts = _tcl_parts(tcl_text)
    if not parts:
        errors.append(f"generated TCL has no -part target; expected {TARGET_PART}")
    elif any(part != TARGET_PART for part in parts):
        errors.append(f"generated TCL has non-exact -part target(s): {', '.join(parts)}")

    resolved_sources = set(_resolved_tcl_sources(tcl_path, tcl_text))
    for source_name in CANONICAL_SOURCES:
        source_path = (rtl_dir / source_name).resolve()
        if not source_path.is_file():
            errors.append(f"missing canonical RTL source: {source_path}")
            continue
        if source_path not in resolved_sources:
            errors.append(
                f"canonical source {source_name} is not read from selected RTL directory; "
                f"expected {source_path}"
            )


def _validate_report(report_path: Path, errors: list[str]) -> None:
    report_text = report_path.read_text(encoding="utf-8")
    try:
        summary = _parse_timing_summary(report_text)
    except GateFailure as failure:
        errors.extend(failure.messages)
    else:
        if summary.wns < Decimal("0"):
            errors.append(f"Design Timing Summary WNS is negative: {summary.wns}")
        if summary.tns != Decimal("0"):
            errors.append(f"Design Timing Summary TNS is nonzero: {summary.tns}")

    for check_name in ("no_clock", "unconstrained_internal_endpoints"):
        count = _check_timing_count(report_text, check_name)
        if count is None:
            errors.append(f"routed timing report lacks checking {check_name} count")
        elif count != 0:
            errors.append(f"checking {check_name} count is nonzero: {count}")


def validate_gate(config: GateConfig) -> None:
    errors: list[str] = []
    gateware_dir = config.gateware_dir.resolve()
    rtl_dir = config.rtl_dir.resolve()
    if not gateware_dir.is_dir():
        errors.append(f"missing gateware directory: {gateware_dir}")
    if not rtl_dir.is_dir():
        errors.append(f"missing RTL directory: {rtl_dir}")
    if errors:
        raise GateFailure(tuple(errors))

    tcl_path = _single_artifact(gateware_dir, "*.tcl", "generated TCL")
    report_path = _single_artifact(gateware_dir, "*_timing.rpt", "routed timing report")
    if tcl_path is None:
        errors.append(f"missing generated TCL in {gateware_dir}")
    if report_path is None:
        errors.append(f"missing routed timing report (*_timing.rpt) in {gateware_dir}")
    if tcl_path is not None:
        _validate_tcl(tcl_path, rtl_dir, errors)
    if report_path is not None:
        if tcl_path is not None and report_path.stat().st_mtime_ns < tcl_path.stat().st_mtime_ns:
            errors.append(f"routed timing report is older than generated TCL: {report_path}")
        report_mtime = report_path.stat().st_mtime_ns
        for source_name in CANONICAL_SOURCES:
            source_path = (rtl_dir / source_name).resolve()
            if source_path.is_file() and report_mtime < source_path.stat().st_mtime_ns:
                errors.append(
                    f"routed timing report is older than canonical RTL source {source_path}"
                )
        _validate_report(report_path, errors)
    if errors:
        raise GateFailure(tuple(errors))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate Vivado gateware provenance and routed timing.")
    parser.add_argument("--gateware-dir", type=Path, default=DEFAULT_GATEWARE_DIR)
    parser.add_argument("--rtl-dir", type=Path, default=DEFAULT_RTL_DIR)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    config = GateConfig(gateware_dir=args.gateware_dir, rtl_dir=args.rtl_dir)
    try:
        validate_gate(config)
    except GateFailure as failure:
        print("Vivado report gate: FAIL", file=sys.stderr)
        for message in failure.messages:
            print(f"- {message}", file=sys.stderr)
        return 1
    except (OSError, UnicodeError) as error:
        print(f"Vivado report gate: FAIL: unable to read artifacts: {error}", file=sys.stderr)
        return 1
    print("Vivado report gate: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
