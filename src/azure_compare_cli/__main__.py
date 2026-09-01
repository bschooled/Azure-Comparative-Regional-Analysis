from __future__ import annotations

import argparse
from pathlib import Path

from .catalog import (
    build_catalog_snapshot,
    build_canonical_identity_snapshot,
    build_identity_gap_report,
    build_catalog_sqlite,
    enrich_record,
    load_json,
    parse_zone_flag,
    write_json,
)
from .provider_report import render_provider_comparison


def build_catalog_command(args: argparse.Namespace) -> int:
    source = Path(args.source)
    output_json = Path(args.output_json)
    output_sqlite = Path(args.output_sqlite)
    output_identity_json = Path(args.output_identity_json) if args.output_identity_json else None

    snapshot = build_catalog_snapshot(source)
    write_json(output_json, snapshot)
    build_catalog_sqlite(snapshot, output_sqlite)
    if output_identity_json is not None:
        write_json(output_identity_json, build_canonical_identity_snapshot(snapshot))
    return 0


def enrich_provider_comparison_command(args: argparse.Namespace) -> int:
    input_path = Path(args.input)
    output_path = Path(args.output)
    catalog_path = Path(args.catalog)

    rows = load_json(input_path)
    snapshot = load_json(catalog_path)
    source_region_has_zones = parse_zone_flag(args.source_region_has_zones)
    target_region_has_zones = parse_zone_flag(args.target_region_has_zones)

    enriched = [
        enrich_record(snapshot, row, source_region_has_zones, target_region_has_zones)
        for row in rows
    ]
    write_json(output_path, enriched)
    return 0


def render_provider_comparison_command(args: argparse.Namespace) -> int:
    render_provider_comparison(Path(args.input), Path(args.output) if args.output else None)
    return 0


def build_identity_gap_report_command(args: argparse.Namespace) -> int:
    rows = load_json(Path(args.input))
    write_json(Path(args.output), build_identity_gap_report(rows))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="azure-region-compare")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_catalog = subparsers.add_parser("build-catalog", help="Build JSON and SQLite artifacts from the curated catalog")
    build_catalog.add_argument("--source", required=True)
    build_catalog.add_argument("--output-json", required=True)
    build_catalog.add_argument("--output-sqlite", required=True)
    build_catalog.add_argument("--output-identity-json")
    build_catalog.set_defaults(func=build_catalog_command)

    enrich_provider = subparsers.add_parser("enrich-provider-comparison", help="Add curated metadata to provider comparison JSON")
    enrich_provider.add_argument("--input", required=True)
    enrich_provider.add_argument("--output", required=True)
    enrich_provider.add_argument("--catalog", required=True)
    enrich_provider.add_argument("--source-region-has-zones", default="unknown")
    enrich_provider.add_argument("--target-region-has-zones", default="unknown")
    enrich_provider.set_defaults(func=enrich_provider_comparison_command)

    render_provider = subparsers.add_parser("render-provider-comparison", help="Render a rich provider comparison report")
    render_provider.add_argument("--input", required=True)
    render_provider.add_argument("--output")
    render_provider.set_defaults(func=render_provider_comparison_command)

    build_identity_gap = subparsers.add_parser("build-identity-gap-report", help="Build a fallback identity curation report from comparison rows")
    build_identity_gap.add_argument("--input", required=True)
    build_identity_gap.add_argument("--output", required=True)
    build_identity_gap.set_defaults(func=build_identity_gap_report_command)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())