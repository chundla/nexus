#!/usr/bin/env python3
"""Export comparable SwiftUI hitch metrics from an Instruments .trace file."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

FRAME_BUDGET_MS = 16.67


@dataclass(frozen=True)
class RunSummary:
    run: int
    platform: str
    device_name: str
    duration_seconds: float
    template_name: str


@dataclass(frozen=True)
class HitchMetrics:
    red_marked_count: int
    worst_red_marked_ms: float
    frame_lifetime_over_budget_count: int
    frame_lifetime_over_33ms_count: int
    worst_frame_lifetime_ms: float
    swiftui_update_groups_worst_ms: float
    top_swiftui_descriptions: tuple[str, ...]


def export_xpath(trace: Path, xpath: str) -> str:
    return subprocess.check_output(
        ["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", xpath],
        text=True,
    )


def export_toc(trace: Path) -> str:
    return subprocess.check_output(
        ["xcrun", "xctrace", "export", "--input", str(trace), "--toc"],
        text=True,
    )


def parse_run_summaries(trace: Path) -> list[RunSummary]:
    toc = export_toc(trace)
    root = ET.fromstring(toc)
    summaries: list[RunSummary] = []
    for run in root.findall("run"):
        number = int(run.get("number", "0"))
        summary = run.find("./info/summary")
        if summary is None:
            continue
        device = run.find("./info/target/device")
        summaries.append(
            RunSummary(
                run=number,
                platform=device.get("platform", "unknown") if device is not None else "unknown",
                device_name=device.get("name", "unknown") if device is not None else "unknown",
                duration_seconds=float(summary.findtext("duration") or "0"),
                template_name=summary.findtext("template-name") or "unknown",
            )
        )
    return summaries


def parse_durations_ms(xml: str) -> list[float]:
    return [float(match.group(1)) for match in re.finditer(r'fmt="([0-9]+\.?[0-9]*) ms"', xml)]


def parse_red_marked_hitches(xml: str) -> tuple[int, float]:
    rows = xml.split("<row>")[1:]
    durations_by_id: dict[str, float] = {}
    for match in re.finditer(
        r'<duration id="(\d+)"[^>]*fmt="([0-9.]+) ms"', xml
    ):
        durations_by_id[match.group(1)] = float(match.group(2))

    hitch_durations: list[float] = []
    for row in rows:
        if 'fmt="Red"' not in row:
            continue
        if not re.search(r"<uint32[^>]*fmt=\"1\">1</uint32>", row):
            continue
        inline = re.search(r'<duration[^>]*fmt="([0-9.]+) ms"', row)
        if inline:
            hitch_durations.append(float(inline.group(1)))
            continue
        ref = re.search(r'<duration ref="(\d+)"', row)
        if ref and ref.group(1) in durations_by_id:
            hitch_durations.append(durations_by_id[ref.group(1)])

    return len(hitch_durations), max(hitch_durations) if hitch_durations else 0.0


def parse_top_swiftui_descriptions(xml: str, limit: int = 12) -> tuple[str, ...]:
    strings = re.findall(r'<string[^>]*fmt="([^"]{12,})"', xml)
    keywords = (
        "StructuredSession",
        "ScrollView",
        "Scroll",
        "Markdown",
        "expensive",
        "Potentially",
        "ViewLayout",
        "offscreen",
    )
    filtered = [value for value in strings if any(key in value for key in keywords)]
    ranked: list[str] = []
    for value in filtered:
        if value not in ranked:
            ranked.append(value)
        if len(ranked) >= limit:
            break
    return tuple(ranked)


def collect_metrics(trace: Path, run: int) -> HitchMetrics:
    hitches_updates = export_xpath(
        trace, f'/trace-toc/run[@number="{run}"]/data/table[@schema="hitches-updates"]'
    )
    frame_lifetimes = export_xpath(
        trace, f'/trace-toc/run[@number="{run}"]/data/table[@schema="hitches-frame-lifetimes"]'
    )
    update_groups = export_xpath(
        trace, f'/trace-toc/run[@number="{run}"]/data/table[@schema="swiftui-update-groups"]'
    )

    red_count, worst_red = parse_red_marked_hitches(hitches_updates)
    frame_durations = parse_durations_ms(frame_lifetimes)
    group_durations = parse_durations_ms(update_groups)

    return HitchMetrics(
        red_marked_count=red_count,
        worst_red_marked_ms=worst_red,
        frame_lifetime_over_budget_count=sum(1 for value in frame_durations if value > FRAME_BUDGET_MS),
        frame_lifetime_over_33ms_count=sum(1 for value in frame_durations if value > 33),
        worst_frame_lifetime_ms=max(frame_durations) if frame_durations else 0.0,
        swiftui_update_groups_worst_ms=max(group_durations) if group_durations else 0.0,
        top_swiftui_descriptions=parse_top_swiftui_descriptions(update_groups),
    )


def build_report(trace: Path, run: int | None) -> dict:
    summaries = parse_run_summaries(trace)
    selected_runs = [run] if run is not None else [summary.run for summary in summaries]
    runs_payload = []
    for summary in summaries:
        if summary.run not in selected_runs:
            continue
        metrics = collect_metrics(trace, summary.run)
        runs_payload.append(
            {
                "run": summary.run,
                "platform": summary.platform,
                "device_name": summary.device_name,
                "template_name": summary.template_name,
                "duration_seconds": round(summary.duration_seconds, 3),
                "hitches": {
                    "red_marked_count": metrics.red_marked_count,
                    "worst_red_marked_ms": round(metrics.worst_red_marked_ms, 3),
                    "frame_lifetime_over_16_67ms_count": metrics.frame_lifetime_over_budget_count,
                    "frame_lifetime_over_33ms_count": metrics.frame_lifetime_over_33ms_count,
                    "worst_frame_lifetime_ms": round(metrics.worst_frame_lifetime_ms, 3),
                },
                "swiftui": {
                    "update_groups_worst_ms": round(metrics.swiftui_update_groups_worst_ms, 3),
                    "top_update_group_descriptions": list(metrics.top_swiftui_descriptions),
                },
            }
        )

    return {"trace": str(trace.resolve()), "runs": runs_payload}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=None, help="Path to a .trace bundle")
    parser.add_argument("--run", type=int, default=None, help="Optional run number (default: all runs)")
    parser.add_argument("--output", type=Path, default=None, help="Write JSON here (default: stdout)")
    parser.add_argument(
        "--fixture-xml",
        type=Path,
        default=None,
        help="Parse hitch XML fixture only (for tests; skips xctrace)",
    )
    args = parser.parse_args(argv)

    if args.fixture_xml is not None:
        xml = args.fixture_xml.read_text()
        count, worst = parse_red_marked_hitches(xml)
        payload = {
            "fixture": str(args.fixture_xml.resolve()),
            "hitches": {"red_marked_count": count, "worst_red_marked_ms": worst},
        }
        text = json.dumps(payload, indent=2)
        if args.output:
            args.output.write_text(text + "\n")
        else:
            print(text)
        return 0

    if args.input is None:
        parser.error("--input is required unless --fixture-xml is set")

    report = build_report(args.input, args.run)
    text = json.dumps(report, indent=2)
    if args.output:
        args.output.write_text(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())