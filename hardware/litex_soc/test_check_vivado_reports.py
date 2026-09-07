from __future__ import annotations

import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path

from hardware.litex_soc.check_vivado_reports import (
    CANONICAL_SOURCES,
    DEFAULT_GATEWARE_DIR,
    GateConfig,
    GateFailure,
    REPOSITORY_ROOT,
    main,
    validate_gate,
)


class VivadoReportGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.gateware_dir = self.root / "gateware"
        self.rtl_dir = self.root / "rtl"
        self.gateware_dir.mkdir()
        self.rtl_dir.mkdir()
        for source_name in CANONICAL_SOURCES:
            (self.rtl_dir / source_name).write_text("// synthetic RTL\n")
        self.tcl_path = self.gateware_dir / "fixture.tcl"
        source_lines = "\n".join(
            (
                f'read_verilog "{self.rtl_dir / source_name}"'
                if index % 2
                else f"read_verilog {{{self.rtl_dir / source_name}}}"
            )
            for index, source_name in enumerate(CANONICAL_SOURCES)
        )
        self.tcl_path.write_text(
            "create_project -force -name fixture -part xc7s50csga324-1\n"
            f"{source_lines}\n"
            "synth_design -top fixture -part xc7s50csga324-1\n"
        )
        self.report_path = self.gateware_dir / "fixture_timing.rpt"
        self.report_path.write_text(
            "unrelated values -99.0 -88.0\n"
            "check_timing report\n"
            "1. checking no_clock (0)\n"
            "4. checking unconstrained_internal_endpoints (0)\n"
            "| Design Timing Summary |\n"
            "WNS(ns) TNS(ns) TNS Failing Endpoints\n"
            "------- ------- ---------------------\n"
            "1.250 0.000 0\n"
        )
        os.utime(self.tcl_path, ns=(2_000_000_100, 2_000_000_100))
        os.utime(self.report_path, ns=(2_000_000_200, 2_000_000_200))
        for source_name in CANONICAL_SOURCES:
            source_path = self.rtl_dir / source_name
            os.utime(source_path, ns=(2_000_000_000, 2_000_000_000))

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def config(self) -> GateConfig:
        return GateConfig(
            gateware_dir=self.gateware_dir,
            rtl_dir=self.rtl_dir,
        )

    def assert_gate_fails(self, message: str) -> None:
        with self.assertRaises(GateFailure) as raised:
            validate_gate(self.config())
        self.assertIn(message, str(raised.exception))

    def test_success_uses_design_timing_summary(self) -> None:
        # Given: a complete, fresh synthetic gateware/TCL/report fixture.
        # When: the host-side acceptance gate validates it.
        # Then: the gate accepts the Design Timing Summary row.
        validate_gate(self.config())

    def test_default_gateware_dir_is_repository_root_relative(self) -> None:
        # Given: LiteX is run from the repository root.
        # When: the default gateware directory is inspected.
        # Then: it points to the repository-root build output.
        self.assertEqual(
            DEFAULT_GATEWARE_DIR,
            REPOSITORY_ROOT / "build/realdigital_urbana/gateware",
        )

    def test_cli_success_is_concise(self) -> None:
        # Given: a complete synthetic fixture.
        stdout = io.StringIO()
        stderr = io.StringIO()
        # When: the CLI is invoked with both directory options.
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = main(
                [
                    "--gateware-dir",
                    str(self.gateware_dir),
                    "--rtl-dir",
                    str(self.rtl_dir),
                ]
            )
        # Then: success is one concise stdout line with no stderr noise.
        self.assertEqual(status, 0)
        self.assertEqual(stdout.getvalue(), "Vivado report gate: PASS\n")
        self.assertEqual(stderr.getvalue(), "")

    def test_wrong_directory_with_same_basename_is_rejected(self) -> None:
        # Given: another directory contains a same-basename source.
        other_dir = self.root / "other"
        other_dir.mkdir()
        wrong_path = other_dir / CANONICAL_SOURCES[0]
        wrong_path.write_text("// wrong provenance\n")
        tcl_text = self.tcl_path.read_text()
        self.tcl_path.write_text(
            tcl_text.replace(str(self.rtl_dir / CANONICAL_SOURCES[0]), str(wrong_path))
        )
        # When: the gate checks resolved TCL source paths.
        # Then: basename-only provenance is not accepted.
        self.assert_gate_fails("selected RTL directory")

    def test_missing_canonical_source_is_rejected(self) -> None:
        # Given: a canonical RTL artifact is absent from the selected directory.
        (self.rtl_dir / CANONICAL_SOURCES[-1]).unlink()
        # When: the gate validates required artifacts.
        # Then: the missing source is named in the failure.
        self.assert_gate_fails(CANONICAL_SOURCES[-1])

    def test_older_tcl_with_exact_canonical_paths_is_accepted(self) -> None:
        # Given: TCL is older than every canonical RTL source, but uses exact paths.
        os.utime(self.tcl_path, ns=(1_000_000_000, 1_000_000_000))
        for source_name in CANONICAL_SOURCES:
            source_path = self.rtl_dir / source_name
            os.utime(source_path, ns=(2_000_000_000, 2_000_000_000))
        os.utime(self.report_path, ns=(3_000_000_000, 3_000_000_000))
        # When: the gate validates artifact provenance freshness.
        # Then: an older recipe is accepted because routed evidence is newer than all RTL.
        validate_gate(self.config())

    def test_stale_timing_report_relative_to_rtl_is_rejected(self) -> None:
        # Given: the routed report predates one canonical RTL source but is newer than TCL.
        os.utime(self.tcl_path, ns=(1_000_000_000, 1_000_000_000))
        for source_name in CANONICAL_SOURCES:
            source_path = self.rtl_dir / source_name
            source_mtime = (
                4_000_000_000
                if source_name == CANONICAL_SOURCES[0]
                else 2_000_000_000
            )
            os.utime(source_path, ns=(source_mtime, source_mtime))
        os.utime(self.report_path, ns=(3_000_000_000, 3_000_000_000))
        # When: the gate validates artifact provenance freshness.
        # Then: the stale routed evidence names the canonical RTL freshness violation.
        self.assert_gate_fails("routed timing report is older than canonical RTL source")

    def test_stale_timing_report_is_rejected(self) -> None:
        # Given: the routed report predates generated TCL.
        os.utime(self.report_path, ns=(1_000_000_000, 1_000_000_000))
        # When: the gate validates artifact freshness.
        # Then: stale routed evidence is rejected.
        self.assert_gate_fails("timing report is older")

    def test_negative_wns_is_rejected(self) -> None:
        # Given: the Design Timing Summary has negative WNS.
        self.report_path.write_text(self.report_path.read_text().replace("1.250 0.000", "-0.001 0.000"))
        # When: the gate validates timing.
        # Then: negative WNS is actionable.
        self.assert_gate_fails("WNS")

    def test_nonzero_tns_is_rejected(self) -> None:
        # Given: the Design Timing Summary has nonzero TNS.
        self.report_path.write_text(self.report_path.read_text().replace("1.250 0.000", "0.000 0.001"))
        # When: the gate validates timing.
        # Then: nonzero TNS is actionable.
        self.assert_gate_fails("TNS")

    def test_nonzero_no_clock_count_is_rejected(self) -> None:
        # Given: check_timing reports a no-clock violation.
        self.report_path.write_text(self.report_path.read_text().replace("no_clock (0)", "no_clock (1)"))
        # When: the gate validates timing checks.
        # Then: the no-clock count is rejected.
        self.assert_gate_fails("no_clock")

    def test_nonzero_unconstrained_count_is_rejected(self) -> None:
        # Given: check_timing reports unconstrained internal endpoints.
        self.report_path.write_text(
            self.report_path.read_text().replace(
                "unconstrained_internal_endpoints (0)",
                "unconstrained_internal_endpoints (2)",
            )
        )
        # When: the gate validates timing checks.
        # Then: the unconstrained count is rejected.
        self.assert_gate_fails("unconstrained_internal_endpoints")

    def test_wrong_part_is_rejected(self) -> None:
        # Given: generated TCL targets a different exact FPGA part.
        self.tcl_path.write_text(
            self.tcl_path.read_text().replace("xc7s50csga324-1", "xc7s25csga324-1")
        )
        # When: the gate validates the generated target.
        # Then: the wrong part is rejected.
        self.assert_gate_fails("non-exact -part target")

    def test_missing_timing_report_is_rejected(self) -> None:
        # Given: the routed timing report artifact is absent.
        self.report_path.unlink()
        # When: the CLI gate validates required artifacts.
        # Then: the missing report is named in the failure.
        self.assert_gate_fails("timing report")


if __name__ == "__main__":
    unittest.main()
