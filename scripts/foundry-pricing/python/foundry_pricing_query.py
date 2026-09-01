#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import difflib
import json
import re
import sys
from pathlib import Path
from typing import Any


DEFAULT_COLUMNS = [
    "model_hint",
    "provider",
    "region",
    "pricing_category",
    "token_direction",
    "deployment_scope",
    "unit_price",
    "currency",
    "unit",
    "sku",
]
SEARCH_COLUMNS = ["model_hint", "sku", "meter", "product", "provider"]
TOOLKIT_ROOT = Path(__file__).resolve().parent.parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fuzzy-search and filter a foundry-pricing.csv file."
    )
    parser.add_argument(
        "query",
        nargs="?",
        default="",
        help="Model/name search, for example: kimi, gpt-5.4, or firewroks.",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        dest="csv_path",
        help="CSV to query. Defaults to the newest output/**/foundry-pricing.csv.",
    )
    parser.add_argument("--region", action="append", default=[])
    parser.add_argument("--provider", action="append", default=[])
    parser.add_argument("--product", action="append", default=[])
    parser.add_argument("--sku", action="append", default=[])
    parser.add_argument("--scope", action="append", default=[])
    parser.add_argument("--category", action="append", default=[])
    parser.add_argument("--direction", action="append", default=[])
    parser.add_argument("--price-type", action="append", default=[])
    parser.add_argument("--unit", action="append", default=[])
    parser.add_argument("--min-price", type=float)
    parser.add_argument("--max-price", type=float)
    parser.add_argument("--ptu-only", action="store_true")
    parser.add_argument("--fireworks-only", action="store_true")
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.6,
        help="Minimum fuzzy score from 0 to 1 (default: 0.6).",
    )
    parser.add_argument(
        "--sort",
        choices=["relevance", "price", "model", "provider", "region"],
        default="relevance",
    )
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument(
        "--columns",
        help="Comma-separated output columns.",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON instead of a table.")
    parser.add_argument("--no-truncate", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.threshold <= 1:
        parser.error("--threshold must be between 0 and 1")
    if args.limit < 1:
        parser.error("--limit must be greater than zero")
    return args


def flatten(values: list[str]) -> list[str]:
    return [
        item.strip().lower()
        for value in values
        for item in value.split(",")
        if item.strip()
    ]


def find_default_csv() -> Path:
    candidates = list(TOOLKIT_ROOT.glob("output/**/foundry-pricing.csv"))
    if not candidates:
        raise FileNotFoundError(
            f"No foundry-pricing.csv found under {TOOLKIT_ROOT / 'output'}. "
            "Pass one with --csv."
        )
    return max(candidates, key=lambda path: path.stat().st_mtime)


def fuzzy_score(query: str, row: dict[str, str]) -> float:
    if not query:
        return 1.0
    query_normalized = query.lower().strip()
    values = [row.get(column, "").lower() for column in SEARCH_COLUMNS]
    combined = " ".join(values)
    if query_normalized in combined:
        return 1.0

    query_tokens = re.findall(r"[a-z0-9.]+", query_normalized)
    candidate_tokens = re.findall(r"[a-z0-9.]+", combined)
    token_scores = [
        max(
            (
                difflib.SequenceMatcher(None, query_token, candidate_token).ratio()
                for candidate_token in candidate_tokens
                if query_token[:1] == candidate_token[:1]
            ),
            default=0.0,
        )
        for query_token in query_tokens
    ]
    field_scores = [
        difflib.SequenceMatcher(None, query_normalized, value).ratio()
        for value in values
        if value
    ]
    all_tokens_score = min(token_scores, default=0.0)
    return max([0.0, all_tokens_score, *field_scores])


def includes_any(value: str, filters: list[str]) -> bool:
    return not filters or any(filter_value in value.lower() for filter_value in filters)


def parse_price(row: dict[str, str]) -> float | None:
    try:
        return float(row.get("unit_price", ""))
    except ValueError:
        return None


def matches_filters(row: dict[str, str], args: argparse.Namespace) -> bool:
    filters = {
        "region": flatten(args.region),
        "provider": flatten(args.provider),
        "product": flatten(args.product),
        "sku": flatten(args.sku),
        "deployment_scope": flatten(args.scope),
        "pricing_category": flatten(args.category),
        "token_direction": flatten(args.direction),
        "price_type": flatten(args.price_type),
        "unit": flatten(args.unit),
    }
    if any(not includes_any(row.get(column, ""), values) for column, values in filters.items()):
        return False
    if args.ptu_only and "provisioned" not in row.get("pricing_category", "").lower():
        return False
    if args.fireworks_only and "fireworks" not in (
        f"{row.get('provider', '')} {row.get('product', '')}".lower()
    ):
        return False
    price = parse_price(row)
    if args.min_price is not None and (price is None or price < args.min_price):
        return False
    if args.max_price is not None and (price is None or price > args.max_price):
        return False
    return True


def sort_rows(
    rows: list[tuple[float, dict[str, str]]],
    sort_key: str,
) -> list[tuple[float, dict[str, str]]]:
    if sort_key == "price":
        return sorted(
            rows,
            key=lambda item: (
                parse_price(item[1]) is None,
                parse_price(item[1]) or 0,
                item[1].get("model_hint", "").lower(),
            ),
        )
    if sort_key in {"model", "provider", "region"}:
        column = {"model": "model_hint", "provider": "provider", "region": "region"}[sort_key]
        return sorted(
            rows,
            key=lambda item: (
                item[1].get(column, "").lower(),
                -item[0],
                parse_price(item[1]) or 0,
            ),
        )
    return sorted(
        rows,
        key=lambda item: (
            -item[0],
            item[1].get("model_hint", "").lower(),
            parse_price(item[1]) or 0,
        ),
    )


def display_value(column: str, value: str) -> str:
    if column == "unit_price":
        try:
            return f"{float(value):,.8g}"
        except ValueError:
            return value
    return value


def print_table(
    rows: list[dict[str, Any]],
    columns: list[str],
    *,
    truncate: bool,
) -> None:
    if not rows:
        print("No matching pricing rows.")
        return

    max_width = 36 if truncate else 200
    rendered = [
        {
            column: display_value(column, str(row.get(column, "")))
            for column in columns
        }
        for row in rows
    ]
    widths = {
        column: min(
            max(len(column), *(len(row[column]) for row in rendered)),
            max_width,
        )
        for column in columns
    }

    def cell(value: str, width: int) -> str:
        if len(value) > width:
            value = value[: max(1, width - 3)] + "..."
        return value.ljust(width)

    print(" | ".join(cell(column, widths[column]) for column in columns))
    print("-+-".join("-" * widths[column] for column in columns))
    for row in rendered:
        print(" | ".join(cell(row[column], widths[column]) for column in columns))


def main() -> int:
    args = parse_args()
    csv_path = args.csv_path or find_default_csv()
    if not csv_path.is_file():
        raise FileNotFoundError(f"CSV does not exist: {csv_path}")

    with csv_path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        available_columns = reader.fieldnames or []
        matches: list[tuple[float, dict[str, str]]] = []
        for row in reader:
            if not matches_filters(row, args):
                continue
            score = fuzzy_score(args.query, row)
            if args.query and score < args.threshold:
                continue
            matches.append((score, row))

    matches = sort_rows(matches, args.sort)
    total = len(matches)
    matches = matches[: args.limit]
    output_rows = [{**row, "relevance": round(score, 3)} for score, row in matches]

    if args.columns:
        columns = [column.strip() for column in args.columns.split(",") if column.strip()]
    else:
        columns = ["relevance", *DEFAULT_COLUMNS] if args.query else DEFAULT_COLUMNS
    unknown = [column for column in columns if column not in [*available_columns, "relevance"]]
    if unknown:
        raise ValueError(f"Unknown columns: {', '.join(unknown)}")

    if args.json:
        print(json.dumps(output_rows, indent=2))
    else:
        print(f"Source: {csv_path}")
        print(f"Matches: {total} (showing {len(output_rows)})\n")
        print_table(output_rows, columns, truncate=not args.no_truncate)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        raise SystemExit(130)
