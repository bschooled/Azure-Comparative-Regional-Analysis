from __future__ import annotations

from pathlib import Path
from typing import Any

from .catalog import load_json


FAMILY_ORDER = [
    "databases",
    "analytics",
    "storage",
    "containers",
    "app-services",
]


def _status_style(status: str) -> str:
    return {
        "FULL_MATCH": "green",
        "AVAILABLE_NO_SKUS": "cyan",
        "SOURCE_EXTENDED": "yellow",
        "TARGET_EXTENDED": "magenta",
        "SOURCE_ONLY": "red",
        "TARGET_ONLY": "red",
    }.get(status, "white")


def _capability_style(status: str) -> str:
    return {
        "available": "green",
        "preview": "yellow",
        "unavailable": "red",
        "unsupported": "red",
        "unknown": "dim",
    }.get(status, "white")


def _family_sort_key(family: str) -> tuple[int, str]:
    if family in FAMILY_ORDER:
        return (FAMILY_ORDER.index(family), family)
    return (len(FAMILY_ORDER), family)


def _group_curated_rows(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        curated = row.get("curated", {})
        if not curated.get("matched"):
            continue
        family = curated.get("family") or "other"
        grouped.setdefault(family, []).append(row)
    return grouped


def render_provider_comparison_plain(rows: list[dict[str, Any]], output_path: Path | None = None) -> None:
    if not rows:
        text = "No provider comparison rows found.\n"
        if output_path:
            output_path.write_text(text, encoding="utf-8")
        else:
            print(text, end="")
        return

    source_region = rows[0].get("sourceRegion", {}).get("name", "unknown")
    target_region = rows[0].get("targetRegion", {}).get("name", "unknown")
    lines: list[str] = []
    lines.append("Azure Regional Capability Comparison")
    lines.append(f"{source_region} -> {target_region}")
    lines.append("")
    lines.append("Provider Summary")
    lines.append("Provider | Status | Source SKUs | Target SKUs | Curated Service | Zone Delta | Zone SKUs")

    ranked = sorted(
        rows,
        key=lambda item: (
            -abs(item.get("sourceRegion", {}).get("skuCount", 0) - item.get("targetRegion", {}).get("skuCount", 0)),
            item.get("provider", ""),
        ),
    )

    for row in ranked[:15]:
        curated = row.get("curated", {})
        source_zone = curated.get("sourceRegion", {}).get("zoneSupport", {}).get("label", "")
        target_zone = curated.get("targetRegion", {}).get("zoneSupport", {}).get("label", "")
        zone_delta = source_zone if source_zone == target_zone else f"{source_zone} / {target_zone}"
        src_zone_dep = row.get("sourceRegion", {}).get("zoneDependentSkuCount", 0)
        tgt_zone_dep = row.get("targetRegion", {}).get("zoneDependentSkuCount", 0)
        zone_sku_parts: list[str] = []
        if src_zone_dep:
            zone_sku_parts.append(f"src:{src_zone_dep}")
        if tgt_zone_dep:
            zone_sku_parts.append(f"tgt:{tgt_zone_dep}")
        zone_sku_info = " ".join(zone_sku_parts) or "-"
        lines.append(
            f"{row.get('provider', '')} | {row.get('status', '')} | "
            f"{row.get('sourceRegion', {}).get('skuCount', 0)} | {row.get('targetRegion', {}).get('skuCount', 0)} | "
            f"{curated.get('displayName') or '-'} | {zone_delta or '-'} | {zone_sku_info}"
        )

    grouped = _group_curated_rows(ranked)
    for family in sorted(grouped, key=_family_sort_key):
        family_rows = sorted(grouped[family], key=lambda row: row.get("curated", {}).get("displayName") or row.get("provider", ""))
        lines.append("")
        lines.append(f"Family: {family}")
        lines.append("Provider | Curated Service | Status | Source SKUs | Target SKUs")
        for row in family_rows:
            curated = row.get("curated", {})
            lines.append(
                f"{row.get('provider', '')} | {curated.get('displayName') or '-'} | {row.get('status', '')} | "
                f"{row.get('sourceRegion', {}).get('skuCount', 0)} | {row.get('targetRegion', {}).get('skuCount', 0)}"
            )

        for row in family_rows[:4]:
            curated = row["curated"]
            lines.append("")
            lines.append(f"{curated.get('displayName')} ({curated.get('family')})")
            lines.append("Capability | Source | Target | Importance | Source Notes | Target Notes")
            for capability in curated.get("capabilities", [])[:10]:
                lines.append(
                    f"{capability.get('label', '')} | {capability.get('sourceStatus', 'unknown')} | "
                    f"{capability.get('targetStatus', 'unknown')} | {capability.get('importance', '')} | "
                    f"{capability.get('sourceNotes', '') or '-'} | {capability.get('targetNotes', '') or '-'}"
                )

            source_zone = curated.get("sourceRegion", {}).get("zoneSupport", {}).get("label", "Unknown")
            target_zone = curated.get("targetRegion", {}).get("zoneSupport", {}).get("label", "Unknown")
            lines.append(f"Zone support: {source_region} = {source_zone}; {target_region} = {target_zone}")
            if curated.get("sourceRegion", {}).get("regionNote") or curated.get("targetRegion", {}).get("regionNote"):
                lines.append(
                    f"Regional caveats: {source_region} = {curated.get('sourceRegion', {}).get('regionNote') or '-'}; "
                    f"{target_region} = {curated.get('targetRegion', {}).get('regionNote') or '-'}"
                )
            lines.append(f"Summary: {curated.get('summary', '')}")

    text = "\n".join(lines) + "\n"
    if output_path:
        output_path.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


def render_provider_comparison(input_path: Path, output_path: Path | None = None) -> None:
    try:
        from rich.console import Console
        from rich.panel import Panel
        from rich.table import Table
        from rich.text import Text
    except ModuleNotFoundError:
        rows = load_json(input_path)
        render_provider_comparison_plain(rows, output_path)
        return

    rows: list[dict[str, Any]] = load_json(input_path)
    console = Console(record=bool(output_path), width=120)

    if not rows:
        console.print("No provider comparison rows found.")
        if output_path:
            output_path.write_text(console.export_text(), encoding="utf-8")
        return

    source_region = rows[0].get("sourceRegion", {}).get("name", "unknown")
    target_region = rows[0].get("targetRegion", {}).get("name", "unknown")

    header = Text("Azure Regional Capability Comparison", style="bold cyan")
    header.append(f"\n{source_region} → {target_region}", style="white")
    console.print(Panel(header, border_style="cyan"))

    summary = Table(title="Provider Summary", show_lines=False)
    summary.add_column("Provider", style="bold")
    summary.add_column("Status")
    summary.add_column(source_region, justify="right")
    summary.add_column(target_region, justify="right")
    summary.add_column("Curated Service")
    summary.add_column("Zone Delta")
    summary.add_column("Zone SKUs")

    ranked = sorted(
        rows,
        key=lambda item: (
            -abs(item.get("sourceRegion", {}).get("skuCount", 0) - item.get("targetRegion", {}).get("skuCount", 0)),
            item.get("provider", ""),
        ),
    )

    for row in ranked[:15]:
        curated = row.get("curated", {})
        source_zone = curated.get("sourceRegion", {}).get("zoneSupport", {}).get("label", "")
        target_zone = curated.get("targetRegion", {}).get("zoneSupport", {}).get("label", "")
        zone_delta = source_zone if source_zone == target_zone else f"{source_zone} / {target_zone}"
        src_zone_dep = row.get("sourceRegion", {}).get("zoneDependentSkuCount", 0)
        tgt_zone_dep = row.get("targetRegion", {}).get("zoneDependentSkuCount", 0)
        zone_sku_info = ""
        if src_zone_dep or tgt_zone_dep:
            src_eff = row.get("sourceRegion", {}).get("effectiveSkuCount")
            tgt_eff = row.get("targetRegion", {}).get("effectiveSkuCount")
            src_flag = row.get("sourceRegion", {}).get("regionHasAvailabilityZones", "unknown")
            tgt_flag = row.get("targetRegion", {}).get("regionHasAvailabilityZones", "unknown")
            parts = []
            if src_zone_dep and src_flag == "false":
                parts.append(f"[red]src:-{src_zone_dep}[/]")
            elif src_zone_dep:
                parts.append(f"src:{src_zone_dep}")
            if tgt_zone_dep and tgt_flag == "false":
                parts.append(f"[red]tgt:-{tgt_zone_dep}[/]")
            elif tgt_zone_dep:
                parts.append(f"tgt:{tgt_zone_dep}")
            zone_sku_info = " ".join(parts)

        summary.add_row(
            row.get("provider", ""),
            f"[{_status_style(row.get('status', ''))}]{row.get('status', '')}[/]",
            str(row.get("sourceRegion", {}).get("skuCount", 0)),
            str(row.get("targetRegion", {}).get("skuCount", 0)),
            curated.get("displayName") or "-",
            zone_delta or "-",
            zone_sku_info or "-",
        )

    console.print(summary)

    grouped = _group_curated_rows(ranked)
    for family in sorted(grouped, key=_family_sort_key):
        family_rows = sorted(grouped[family], key=lambda row: row.get("curated", {}).get("displayName") or row.get("provider", ""))
        console.print(Panel(Text(f"Service Family: {family}", style="bold white"), border_style="green"))

        family_table = Table(title=f"{family} providers", show_lines=False)
        family_table.add_column("Provider", style="bold")
        family_table.add_column("Curated Service")
        family_table.add_column("Status")
        family_table.add_column(source_region, justify="right")
        family_table.add_column(target_region, justify="right")
        for row in family_rows:
            curated = row.get("curated", {})
            family_table.add_row(
                row.get("provider", ""),
                curated.get("displayName") or "-",
                f"[{_status_style(row.get('status', ''))}]{row.get('status', '')}[/]",
                str(row.get("sourceRegion", {}).get("skuCount", 0)),
                str(row.get("targetRegion", {}).get("skuCount", 0)),
            )
        console.print(family_table)

        for row in family_rows[:4]:
            curated = row["curated"]
            title = f"{curated.get('displayName')} ({curated.get('family')})"
            capability_table = Table(title=title, box=None, show_header=True)
            capability_table.add_column("Capability", style="bold")
            capability_table.add_column(source_region)
            capability_table.add_column(target_region)
            capability_table.add_column("Importance")
            capability_table.add_column(f"{source_region} notes")
            capability_table.add_column(f"{target_region} notes")

            for capability in curated.get("capabilities", [])[:10]:
                capability_table.add_row(
                    capability.get("label", ""),
                    f"[{_capability_style(capability.get('sourceStatus', 'unknown'))}]{capability.get('sourceStatus', 'unknown')}[/]",
                    f"[{_capability_style(capability.get('targetStatus', 'unknown'))}]{capability.get('targetStatus', 'unknown')}[/]",
                    capability.get("importance", ""),
                    capability.get("sourceNotes", "") or "-",
                    capability.get("targetNotes", "") or "-",
                )

            source_zone = curated.get("sourceRegion", {}).get("zoneSupport", {}).get("label", "Unknown")
            target_zone = curated.get("targetRegion", {}).get("zoneSupport", {}).get("label", "Unknown")
            detail_lines = [
                f"Zone support: {source_region} = {source_zone}; {target_region} = {target_zone}",
                f"Summary: {curated.get('summary', '')}",
            ]
            if curated.get("sourceRegion", {}).get("regionNote") or curated.get("targetRegion", {}).get("regionNote"):
                detail_lines.append(
                    f"Regional caveats: {source_region} = {curated.get('sourceRegion', {}).get('regionNote') or '-'}; "
                    f"{target_region} = {curated.get('targetRegion', {}).get('regionNote') or '-'}"
                )

            console.print(capability_table)
            console.print(Panel("\n".join(detail_lines), border_style="blue"))

    if output_path:
        output_path.write_text(console.export_text(), encoding="utf-8")