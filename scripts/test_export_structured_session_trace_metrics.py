#!/usr/bin/env python3

import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "export_structured_session_trace_metrics.py"
FIXTURE = REPO_ROOT / "Tests" / "Support" / "fixtures" / "hitches-updates-red-hitch.xml"


class ExportStructuredSessionTraceMetricsTests(unittest.TestCase):
    def test_parses_red_marked_hitch_from_fixture_xml(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--fixture-xml",
                str(FIXTURE),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        payload = json.loads(completed.stdout)
        self.assertEqual(payload["hitches"]["red_marked_count"], 1)
        self.assertAlmostEqual(payload["hitches"]["worst_red_marked_ms"], 31.93, places=2)


if __name__ == "__main__":
    unittest.main()