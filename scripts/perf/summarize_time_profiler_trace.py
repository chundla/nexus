#!/usr/bin/env python3
import argparse
import collections
import pathlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

TIME_PROFILE_XPATH = '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'


def export_xctrace(trace_path: pathlib.Path, xpath: str) -> str:
    with tempfile.NamedTemporaryFile(suffix='.xml', delete=False) as handle:
        output_path = pathlib.Path(handle.name)

    try:
        subprocess.run(
            [
                'xcrun', 'xctrace', 'export',
                '--input', str(trace_path),
                '--xpath', xpath,
                '--output', str(output_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        return output_path.read_text()
    finally:
        output_path.unlink(missing_ok=True)


def export_toc(trace_path: pathlib.Path) -> str:
    result = subprocess.run(
        ['xcrun', 'xctrace', 'export', '--input', str(trace_path), '--toc'],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def parse_trace_metadata(toc_xml: str) -> dict[str, str]:
    root = ET.fromstring(toc_xml)
    run = root.find('./run')
    if run is None:
        return {}

    process = run.find('./info/target/process')
    summary = run.find('./info/summary')
    environment = run.findall('./info/target/environment/item')

    metadata = {
        'process': process.get('name', 'unknown') if process is not None else 'unknown',
        'duration': summary.findtext('duration', default='unknown') if summary is not None else 'unknown',
        'template': summary.findtext('template-name', default='unknown') if summary is not None else 'unknown',
        'end_reason': summary.findtext('end-reason', default='unknown') if summary is not None else 'unknown',
    }

    scenario = next((item.get('value') for item in environment if item.get('key') == 'NEXUS_BENCHMARK_SCENARIO'), None)
    if scenario:
        metadata['scenario'] = scenario

    return metadata


def summarize_time_profile(time_profile_xml: str) -> collections.Counter[str]:
    matches = re.findall(r'tagged-backtrace[^>]*fmt="([^"]+)"', time_profile_xml)
    leaves = [match.split(' ← ')[0] for match in matches]
    return collections.Counter(leaves)


def render_markdown(trace_path: pathlib.Path, metadata: dict[str, str], counts: collections.Counter[str], limit: int) -> str:
    lines = ['# Time Profiler summary', '']
    lines.append(f'- trace: `{trace_path}`')
    if scenario := metadata.get('scenario'):
        lines.append(f'- scenario: `{scenario}`')
    lines.append(f"- process: `{metadata.get('process', 'unknown')}`")
    lines.append(f"- template: `{metadata.get('template', 'unknown')}`")
    lines.append(f"- duration: `{metadata.get('duration', 'unknown')}s`")
    lines.append(f"- end reason: `{metadata.get('end_reason', 'unknown')}`")
    lines.append(f'- symbolicated sample rows: `{sum(counts.values())}`')
    lines.append('')
    lines.append('| rows | leaf frame |')
    lines.append('| ---: | --- |')
    for leaf, count in counts.most_common(limit):
        safe_leaf = leaf.replace('|', '\\|')
        lines.append(f'| {count} | `{safe_leaf}` |')
    if not counts:
        lines.append('| 0 | `No symbolicated time-profile rows were exported.` |')
    lines.append('')
    return '\n'.join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description='Summarize symbolicated Time Profiler rows from an xctrace .trace bundle.')
    parser.add_argument('trace', type=pathlib.Path)
    parser.add_argument('--limit', type=int, default=12)
    args = parser.parse_args()

    trace_path = args.trace.expanduser().resolve()
    toc_xml = export_toc(trace_path)
    time_profile_xml = export_xctrace(trace_path, TIME_PROFILE_XPATH)
    metadata = parse_trace_metadata(toc_xml)
    counts = summarize_time_profile(time_profile_xml)
    sys.stdout.write(render_markdown(trace_path, metadata, counts, args.limit))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
