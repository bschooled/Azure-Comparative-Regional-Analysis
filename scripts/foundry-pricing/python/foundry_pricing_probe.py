#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Iterable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RETAIL_PRICES_URL = "https://prices.azure.com/api/retail/prices"
DEFAULT_SERVICE = "Foundry Models"
DEFAULT_API_VERSION = "2025-06-01"
TOOLKIT_ROOT = Path(__file__).resolve().parent.parent
CSV_COLUMNS = [
    "region",
    "service",
    "product",
    "provider",
    "model_hint",
    "sku",
    "meter",
    "pricing_category",
    "token_direction",
    "deployment_scope",
    "unit_price",
    "currency",
    "unit",
    "price_type",
    "reservation_term",
    "effective_start_date",
    "meter_id",
    "arm_sku_name",
    "source",
]


class ProbeError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Collect Foundry model availability, PTU quota, Retail Prices, "
            "and optionally authenticated Azure pricing."
        )
    )
    parser.add_argument("--resource-group")
    parser.add_argument("--account")
    parser.add_argument("--project")
    parser.add_argument(
        "--subscription",
        help="Subscription name or ID. Defaults to the active Azure CLI subscription.",
    )
    parser.add_argument(
        "--region",
        action="append",
        default=[],
        help=(
            "Region to query. Repeat the flag or use comma-separated values. "
            "Defaults to the Foundry account location."
        ),
    )
    parser.add_argument("--currency", default="USD")
    parser.add_argument("--service-name", default=DEFAULT_SERVICE)
    parser.add_argument(
        "--product",
        action="append",
        default=[],
        help="Retail productName to query. Repeat for multiple products.",
    )
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument(
        "--retail-only",
        action="store_true",
        help="Query the unauthenticated Retail Prices API without Azure CLI or ARM.",
    )
    parser.add_argument(
        "--skip-retail",
        action="store_true",
        help="Collect only authenticated ARM/model/quota data.",
    )
    parser.add_argument(
        "--authenticated-pricing",
        action="store_true",
        help=(
            "Opt in to Microsoft.Commerce Rate Card and Microsoft.Consumption "
            "Price Sheet probes using the Azure CLI identity."
        ),
    )
    parser.add_argument(
        "--rate-card-offer-id",
        help="Override the offer durable ID used by the authenticated Rate Card API.",
    )
    parser.add_argument("--rate-card-locale", default="en-US")
    parser.add_argument("--rate-card-region", default="US")
    parser.add_argument(
        "--billing-account",
        help="Billing account for a billing-profile-scoped Price Sheet request.",
    )
    parser.add_argument(
        "--billing-profile",
        help="Billing profile for a billing-profile-scoped Price Sheet request.",
    )
    parser.add_argument(
        "--query-fireworks-catalog",
        action="store_true",
        help=(
            "Run the optional 'az ml model list --registry-name azureml-fireworks' "
            "catalog query. Requires a working Azure CLI ml extension."
        ),
    )
    parser.add_argument(
        "--skip-project-check",
        action="store_true",
        help="Do not verify that the named Foundry project exists.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=120,
        help="HTTP and Azure CLI timeout in seconds (default: 120).",
    )
    parser.add_argument(
        "--api-version",
        default=DEFAULT_API_VERSION,
        help=f"Cognitive Services ARM API version (default: {DEFAULT_API_VERSION}).",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print external commands and Retail Prices page progress.",
    )
    args = parser.parse_args()

    if args.retail_only and args.skip_retail:
        parser.error("--retail-only and --skip-retail cannot be used together")
    if args.retail_only and args.authenticated_pricing:
        parser.error("--authenticated-pricing requires ARM and cannot be used with --retail-only")
    if bool(args.billing_account) != bool(args.billing_profile):
        parser.error("--billing-account and --billing-profile must be supplied together")
    if args.timeout < 1:
        parser.error("--timeout must be greater than zero")
    if not args.retail_only and (not args.resource_group or not args.account):
        parser.error("--resource-group and --account are required unless --retail-only is used")
    return args


def flatten_values(values: Iterable[str]) -> list[str]:
    result: list[str] = []
    for value in values:
        for item in value.split(","):
            normalized = item.strip().lower()
            if normalized and normalized not in result:
                result.append(normalized)
    return result


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_json_output(result: subprocess.CompletedProcess[str], description: str) -> Any:
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ProbeError(f"{description} returned invalid JSON: {exc}") from exc


def run_command(
    command: list[str],
    *,
    timeout: int,
    verbose: bool,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    if verbose:
        print("+", " ".join(command), file=sys.stderr)
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise ProbeError(f"Command timed out after {timeout}s: {' '.join(command)}") from exc
    if check and result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "unknown error"
        raise ProbeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{message}")
    return result


def run_az(
    arguments: list[str],
    *,
    timeout: int,
    verbose: bool,
    subscription: str | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    command = ["az", *arguments]
    if subscription and "--subscription" not in arguments:
        command.extend(["--subscription", subscription])
    return run_command(command, timeout=timeout, verbose=verbose, check=check)


def az_json(
    arguments: list[str],
    *,
    timeout: int,
    verbose: bool,
    subscription: str | None = None,
) -> Any:
    result = run_az(
        [*arguments, "--output", "json"],
        timeout=timeout,
        verbose=verbose,
        subscription=subscription,
    )
    return read_json_output(result, "Azure CLI")


def http_get_json(url: str, params: dict[str, str], timeout: int) -> dict[str, Any]:
    request_url = f"{url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(
        request_url,
        headers={"User-Agent": "foundry-pricing-probe/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise ProbeError(f"HTTP {exc.code} from {url}: {body}") from exc
    except urllib.error.URLError as exc:
        raise ProbeError(f"Unable to reach {url}: {exc.reason}") from exc


def odata_quote(value: str) -> str:
    return value.replace("'", "''")


def retail_prices(
    *,
    service: str,
    region: str,
    currency: str,
    products: list[str],
    timeout: int,
    verbose: bool,
) -> tuple[str, list[dict[str, Any]]]:
    clauses = [
        f"serviceName eq '{odata_quote(service)}'",
        f"armRegionName eq '{odata_quote(region)}'",
    ]
    if products:
        product_filter = " or ".join(
            f"productName eq '{odata_quote(product)}'" for product in products
        )
        clauses.append(f"({product_filter})")
    filter_text = " and ".join(clauses)
    items: list[dict[str, Any]] = []
    skip = 0

    while True:
        page = http_get_json(
            RETAIL_PRICES_URL,
            {
                "currencyCode": f"'{currency}'",
                "$filter": filter_text,
                "$skip": str(skip),
            },
            timeout,
        )
        page_items = page.get("Items")
        if not isinstance(page_items, list):
            raise ProbeError("Retail Prices API response did not contain an Items array")
        items.extend(item for item in page_items if isinstance(item, dict))
        if verbose:
            print(
                f"Retail Prices {region}: received {len(page_items)} rows "
                f"(total {len(items)})",
                file=sys.stderr,
            )
        if len(page_items) < 1000:
            break
        skip += len(page_items)
    return filter_text, items


def provider_from_product(product: str) -> str:
    replacements = {
        "Azure OpenAI": "OpenAI",
        "Azure Fireworks Models": "Fireworks",
        "Azure Deepseek Models": "DeepSeek",
        "Azure Mistral Models": "Mistral AI",
        "Azure Llama Models": "Meta",
        "Azure Grok Models": "xAI",
        "Azure Kimi": "MoonshotAI",
        "Azure BFL Flux Models": "Black Forest Labs",
        "Azure Phi Models": "Microsoft",
        "MAI Models": "Microsoft",
    }
    for prefix, provider in replacements.items():
        if product.startswith(prefix):
            return provider
    return product.removeprefix("Azure ").removesuffix(" Models").strip()


def pricing_category(item: dict[str, Any]) -> str:
    text = " ".join(
        str(item.get(key, "")) for key in ("productName", "skuName", "meterName")
    ).lower()
    if "provisioned" in text or re.search(r"\bptu\b", text):
        return "Provisioned"
    if "batch" in text:
        return "Batch"
    if "fine" in text and "tun" in text:
        return "Fine-tuning"
    if "embedding" in text:
        return "Embedding"
    return "Pay-as-you-go"


def token_direction(item: dict[str, Any]) -> str:
    text = f"{item.get('skuName', '')} {item.get('meterName', '')}".lower()
    if re.search(r"\b(cache|cached|cd)\b.*\b(inp|input|in)\b", text):
        return "Cached input"
    if re.search(r"\b(inp|input)\b", text):
        return "Input"
    if re.search(r"\b(outp|output|opt)\b", text):
        return "Output"
    return ""


def deployment_scope(item: dict[str, Any]) -> str:
    text = f"{item.get('skuName', '')} {item.get('meterName', '')}".lower()
    if re.search(r"\b(data zone|dzone|dz)\b", text):
        return "Data Zone"
    if re.search(r"\b(global|glbl|\bgl\b)\b", text):
        return "Global"
    if re.search(r"\b(regional|regnl)\b", text):
        return "Regional"
    return ""


def model_hint(item: dict[str, Any]) -> str:
    text = str(item.get("skuName") or item.get("meterName") or "").strip()
    patterns = [
        r"\s+(?:cache|cached|cd|ch)\s+(?:inp|input|in)\b.*$",
        r"\s+(?:inp|input|in|outp|output|opt)\b.*$",
        r"\s+(?:tokens?|units?)\b.*$",
        r"\s+(?:global|glbl|regional|regnl|data zone|dzone|dz)\b.*$",
    ]
    previous = None
    while text != previous:
        previous = text
        for pattern in patterns:
            text = re.sub(pattern, "", text, flags=re.IGNORECASE).strip(" -")
    return text


def normalize_retail_row(item: dict[str, Any]) -> dict[str, Any]:
    product = str(item.get("productName") or "")
    return {
        "region": item.get("armRegionName") or "",
        "service": item.get("serviceName") or "",
        "product": product,
        "provider": provider_from_product(product),
        "model_hint": model_hint(item),
        "sku": item.get("skuName") or "",
        "meter": item.get("meterName") or "",
        "pricing_category": pricing_category(item),
        "token_direction": token_direction(item),
        "deployment_scope": deployment_scope(item),
        "unit_price": item.get("unitPrice"),
        "currency": item.get("currencyCode") or "",
        "unit": item.get("unitOfMeasure") or "",
        "price_type": item.get("type") or "",
        "reservation_term": item.get("reservationTerm") or "",
        "effective_start_date": item.get("effectiveStartDate") or "",
        "meter_id": item.get("meterId") or "",
        "arm_sku_name": item.get("armSkuName") or "",
        "source": "Retail Prices",
    }


def write_csv(path: Path, rows: Iterable[dict[str, Any]], columns: list[str]) -> int:
    count = 0
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in columns})
            count += 1
    return count


def deduplicate_models(values: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    unique: dict[tuple[str, ...], dict[str, Any]] = {}
    for value in values:
        model = value.get("model", value)
        if not isinstance(model, dict):
            continue
        key = (
            str(model.get("name") or ""),
            str(model.get("version") or ""),
            str(model.get("format") or value.get("kind") or ""),
        )
        current = unique.setdefault(
            key,
            {
                "name": key[0],
                "version": key[1],
                "format": key[2],
                "lifecycleStatus": model.get("lifecycleStatus") or "",
                "isDefaultVersion": model.get("isDefaultVersion"),
                "capabilities": model.get("capabilities") or {},
                "skus": [],
            },
        )
        seen_skus = {
            (sku.get("name"), sku.get("usageName"))
            for sku in current["skus"]
            if isinstance(sku, dict)
        }
        for sku in model.get("skus") or []:
            if isinstance(sku, dict) and (sku.get("name"), sku.get("usageName")) not in seen_skus:
                current["skus"].append(sku)
                seen_skus.add((sku.get("name"), sku.get("usageName")))
    return sorted(unique.values(), key=lambda item: (item["format"], item["name"], item["version"]))


def model_csv_rows(region: str, models: list[dict[str, Any]]) -> Iterable[dict[str, Any]]:
    for model in models:
        skus = model.get("skus") or [{}]
        for sku in skus:
            capacity = sku.get("capacity") or {}
            yield {
                "region": region,
                "model": model.get("name") or "",
                "version": model.get("version") or "",
                "format": model.get("format") or "",
                "lifecycle": model.get("lifecycleStatus") or "",
                "default_version": model.get("isDefaultVersion"),
                "sku": sku.get("name") or "",
                "usage_name": sku.get("usageName") or "",
                "minimum": capacity.get("minimum"),
                "default": capacity.get("default"),
                "maximum": capacity.get("maximum"),
                "step": capacity.get("step"),
                "ptu_capable": "provisioned" in str(sku.get("name") or "").lower(),
            }


def arm_rest_json(
    url: str,
    *,
    args: argparse.Namespace,
    check: bool = True,
) -> tuple[Any | None, subprocess.CompletedProcess[str]]:
    result = run_az(
        ["rest", "--method", "get", "--url", url, "--output", "json"],
        timeout=args.timeout,
        verbose=args.verbose,
        subscription=args.subscription,
        check=check,
    )
    if result.returncode != 0:
        return None, result
    return read_json_output(result, "az rest"), result


def collect_arm(
    args: argparse.Namespace,
    output_dir: Path,
    regions: list[str],
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    account = az_json(
        [
            "cognitiveservices",
            "account",
            "show",
            "--resource-group",
            args.resource_group,
            "--name",
            args.account,
        ],
        timeout=args.timeout,
        verbose=args.verbose,
        subscription=args.subscription,
    )
    write_json(output_dir / "account.json", account)

    subscription_id = str(account["id"]).split("/")[2]
    cloud = az_json(
        ["cloud", "show"],
        timeout=args.timeout,
        verbose=args.verbose,
    )
    resource_manager = str(cloud["endpoints"]["resourceManager"]).rstrip("/")

    if args.project and not args.skip_project_check:
        project_id = (
            f"/subscriptions/{subscription_id}/resourceGroups/{args.resource_group}"
            f"/providers/Microsoft.CognitiveServices/accounts/{args.account}"
            f"/projects/{args.project}"
        )
        project = az_json(
            ["resource", "show", "--ids", project_id],
            timeout=args.timeout,
            verbose=args.verbose,
            subscription=args.subscription,
        )
        write_json(output_dir / "project.json", project)

    all_model_rows: list[dict[str, Any]] = []
    ptu_quota_rows: list[dict[str, Any]] = []
    for region in regions:
        models_url = (
            f"{resource_manager}/subscriptions/{subscription_id}"
            f"/providers/Microsoft.CognitiveServices/locations/{region}/models"
            f"?api-version={urllib.parse.quote(args.api_version)}"
        )
        raw_models, _ = arm_rest_json(models_url, args=args)
        assert isinstance(raw_models, dict)
        write_json(output_dir / f"models-{region}.json", raw_models)
        models = deduplicate_models(raw_models.get("value") or [])
        write_json(output_dir / f"models-{region}-normalized.json", models)
        all_model_rows.extend(model_csv_rows(region, models))

        quota_url = (
            f"{resource_manager}/subscriptions/{subscription_id}"
            f"/providers/Microsoft.CognitiveServices/locations/{region}/usages"
            f"?api-version={urllib.parse.quote(args.api_version)}"
        )
        raw_quota, _ = arm_rest_json(quota_url, args=args)
        assert isinstance(raw_quota, dict)
        write_json(output_dir / f"quota-{region}.json", raw_quota)
        for quota in raw_quota.get("value") or []:
            name = quota.get("name") or {}
            combined_name = f"{name.get('value', '')} {name.get('localizedValue', '')}".lower()
            if "provisioned" not in combined_name:
                continue
            current = quota.get("currentValue") or 0
            limit = quota.get("limit") or 0
            ptu_quota_rows.append(
                {
                    "region": region,
                    "quota_name": name.get("localizedValue") or "",
                    "quota_key": name.get("value") or "",
                    "current": current,
                    "limit": limit,
                    "available": limit - current,
                    "unit": quota.get("unit") or "",
                }
            )

    model_columns = [
        "region",
        "model",
        "version",
        "format",
        "lifecycle",
        "default_version",
        "sku",
        "usage_name",
        "minimum",
        "default",
        "maximum",
        "step",
        "ptu_capable",
    ]
    write_csv(output_dir / "foundry-models.csv", all_model_rows, model_columns)
    write_csv(
        output_dir / "foundry-ptu-models.csv",
        (row for row in all_model_rows if row["ptu_capable"]),
        model_columns,
    )
    write_csv(
        output_dir / "foundry-ptu-quota.csv",
        ptu_quota_rows,
        ["region", "quota_name", "quota_key", "current", "limit", "available", "unit"],
    )
    return account, all_model_rows, ptu_quota_rows


def collect_fireworks_catalog(args: argparse.Namespace, output_dir: Path) -> dict[str, Any]:
    if not args.query_fireworks_catalog:
        return {"attempted": False, "available": False, "reason": "Not requested."}

    extension = run_az(
        ["extension", "show", "--name", "ml", "--output", "json"],
        timeout=args.timeout,
        verbose=args.verbose,
        check=False,
    )
    if extension.returncode != 0:
        return {
            "attempted": True,
            "available": False,
            "reason": "The Azure CLI ml extension is not installed.",
            "installCommand": "az extension add --name ml",
        }

    result = run_az(
        [
            "ml",
            "model",
            "list",
            "--registry-name",
            "azureml-fireworks",
            "--output",
            "json",
        ],
        timeout=args.timeout,
        verbose=args.verbose,
        subscription=args.subscription,
        check=False,
    )
    if result.returncode != 0:
        return {
            "attempted": True,
            "available": False,
            "reason": "The Fireworks Azure ML registry query failed.",
            "error": result.stderr.strip() or result.stdout.strip(),
        }

    catalog = read_json_output(result, "Fireworks catalog query")
    write_json(output_dir / "fireworks-catalog.json", catalog)
    rows = []
    for item in catalog if isinstance(catalog, list) else []:
        properties = item.get("properties") or {}
        tags = item.get("tags") or {}
        rows.append(
            {
                "name": item.get("name") or "",
                "version": item.get("version") or "",
                "type": item.get("type") or "",
                "publisher": properties.get("publisher") or tags.get("publisher") or "Fireworks",
                "azure_offers": properties.get("azureOffers") or tags.get("azureOffers") or "",
                "description": item.get("description") or properties.get("description") or "",
            }
        )
    write_csv(
        output_dir / "fireworks-catalog.csv",
        rows,
        ["name", "version", "type", "publisher", "azure_offers", "description"],
    )
    return {"attempted": True, "available": True, "models": len(rows)}


def authenticated_pricing(
    args: argparse.Namespace,
    output_dir: Path,
    account: dict[str, Any],
    retail_rows: list[dict[str, Any]],
) -> dict[str, Any]:
    if not args.authenticated_pricing:
        return {"attempted": False, "reason": "Enable with --authenticated-pricing."}

    subscription_id = str(account["id"]).split("/")[2]
    cloud = az_json(
        ["cloud", "show"],
        timeout=args.timeout,
        verbose=args.verbose,
    )
    resource_manager = str(cloud["endpoints"]["resourceManager"]).rstrip("/")
    subscription_url = (
        f"{resource_manager}/subscriptions/{subscription_id}?api-version=2022-12-01"
    )
    subscription, _ = arm_rest_json(subscription_url, args=args)
    assert isinstance(subscription, dict)
    write_json(output_dir / "subscription.json", subscription)

    offer_id = args.rate_card_offer_id or (
        subscription.get("subscriptionPolicies") or {}
    ).get("quotaId")
    rate_card_status: dict[str, Any]
    rate_card: dict[str, Any] | None = None
    if offer_id:
        rate_filter = (
            f"OfferDurableId eq '{offer_id}' and Currency eq '{args.currency}' "
            f"and Locale eq '{args.rate_card_locale}' "
            f"and RegionInfo eq '{args.rate_card_region}'"
        )
        rate_url = (
            f"{resource_manager}/subscriptions/{subscription_id}"
            "/providers/Microsoft.Commerce/rateCard"
            "?api-version=2016-08-31-preview&$filter="
            f"{urllib.parse.quote(rate_filter)}"
        )
        value, result = arm_rest_json(rate_url, args=args, check=False)
        if isinstance(value, dict):
            rate_card = value
            write_json(output_dir / "authenticated-rate-card.json", rate_card)
            rate_card_status = {
                "attempted": True,
                "available": True,
                "offerId": offer_id,
                "meters": len(rate_card.get("Meters") or []),
            }
        else:
            rate_card_status = {
                "attempted": True,
                "available": False,
                "offerId": offer_id,
                "error": result.stderr.strip() or result.stdout.strip(),
            }
    else:
        rate_card_status = {
            "attempted": False,
            "available": False,
            "reason": "No offer ID was supplied or returned by the subscription.",
        }

    if args.billing_account and args.billing_profile:
        price_sheet_url = (
            f"{resource_manager}/providers/Microsoft.Billing/billingAccounts/"
            f"{urllib.parse.quote(args.billing_account, safe='')}/billingProfiles/"
            f"{urllib.parse.quote(args.billing_profile, safe='')}"
            "/providers/Microsoft.Consumption/pricesheets/default"
            "?api-version=2023-05-01"
        )
        price_sheet_scope = "billing-profile"
    else:
        price_sheet_url = (
            f"{resource_manager}/subscriptions/{subscription_id}"
            "/providers/Microsoft.Consumption/pricesheets/default"
            "?api-version=2023-05-01"
        )
        price_sheet_scope = "subscription"

    price_sheet, price_result = arm_rest_json(price_sheet_url, args=args, check=False)
    if isinstance(price_sheet, dict):
        write_json(output_dir / "authenticated-price-sheet.json", price_sheet)
        price_sheet_status = {
            "attempted": True,
            "available": True,
            "scope": price_sheet_scope,
        }
    else:
        price_sheet_status = {
            "attempted": True,
            "available": False,
            "scope": price_sheet_scope,
            "error": price_result.stderr.strip() or price_result.stdout.strip(),
        }

    comparison_count = 0
    if rate_card:
        rate_by_meter = {
            str(meter.get("MeterId")): meter
            for meter in rate_card.get("Meters") or []
            if meter.get("MeterId")
        }
        comparison_rows = []
        for row in retail_rows:
            authenticated = rate_by_meter.get(str(row.get("meter_id") or ""))
            if not authenticated:
                continue
            comparison_rows.append(
                {
                    **row,
                    "authenticated_meter_rates": json.dumps(
                        authenticated.get("MeterRates") or {},
                        sort_keys=True,
                    ),
                }
            )
        comparison_count = write_csv(
            output_dir / "retail-vs-authenticated.csv",
            comparison_rows,
            [*CSV_COLUMNS, "authenticated_meter_rates"],
        )

    status = {
        "attempted": True,
        "rateCard": rate_card_status,
        "priceSheet": price_sheet_status,
        "matchedRetailMeters": comparison_count,
    }
    write_json(output_dir / "authenticated-pricing-status.json", status)
    return status


def default_output_dir(account: str | None, regions: list[str]) -> Path:
    region_label = "-".join(regions) if regions else "retail"
    account_label = account or "retail"
    return TOOLKIT_ROOT / "output" / f"{account_label}-{region_label}"


def print_summary(summary: dict[str, Any], output_dir: Path) -> None:
    print(f"\nResults written to: {output_dir}")
    pricing_csv = output_dir / "foundry-pricing.csv"
    if pricing_csv.is_file():
        print(f"Pricing CSV: {pricing_csv}")
    print(json.dumps(summary, indent=2, sort_keys=True))


def main() -> int:
    args = parse_args()
    args.region = flatten_values(args.region)
    args.product = [item.strip() for item in args.product if item.strip()]

    if args.retail_only and not args.region:
        raise ProbeError("--retail-only requires at least one --region")
    if not args.retail_only and not shutil.which("az"):
        raise ProbeError(
            "Azure CLI is required unless --retail-only is used. "
            "Install it from https://learn.microsoft.com/cli/azure/install-azure-cli"
        )

    account: dict[str, Any] = {}
    if not args.retail_only:
        login = run_az(
            ["account", "show", "--output", "json"],
            timeout=args.timeout,
            verbose=args.verbose,
            subscription=args.subscription,
            check=False,
        )
        if login.returncode != 0:
            raise ProbeError("Azure CLI is not logged in. Run 'az login' first.")
        active_account = read_json_output(login, "az account show")
        if not args.region:
            account_preview = az_json(
                [
                    "cognitiveservices",
                    "account",
                    "show",
                    "--resource-group",
                    args.resource_group,
                    "--name",
                    args.account,
                ],
                timeout=args.timeout,
                verbose=args.verbose,
                subscription=args.subscription,
            )
            account = account_preview
            args.region = [str(account_preview["location"]).lower()]

    regions = args.region
    output_dir = args.output_dir or default_output_dir(args.account, regions)
    output_dir.mkdir(parents=True, exist_ok=True)

    model_rows: list[dict[str, Any]] = []
    ptu_quota_rows: list[dict[str, Any]] = []
    if not args.retail_only:
        account, model_rows, ptu_quota_rows = collect_arm(
            args,
            output_dir,
            regions,
        )

    retail_rows: list[dict[str, Any]] = []
    retail_counts: dict[str, int] = {}
    if not args.skip_retail:
        for region in regions:
            filter_text, items = retail_prices(
                service=args.service_name,
                region=region,
                currency=args.currency.upper(),
                products=args.product,
                timeout=args.timeout,
                verbose=args.verbose,
            )
            write_json(
                output_dir / f"retail-{region}.json",
                {
                    "currency": args.currency.upper(),
                    "filter": filter_text,
                    "count": len(items),
                    "items": items,
                },
            )
            region_rows = [normalize_retail_row(item) for item in items]
            retail_rows.extend(region_rows)
            retail_counts[region] = len(region_rows)
        retail_rows.sort(
            key=lambda row: (
                str(row["region"]),
                str(row["provider"]),
                str(row["model_hint"]),
                str(row["sku"]),
                str(row["price_type"]),
            )
        )
        write_csv(output_dir / "foundry-pricing.csv", retail_rows, CSV_COLUMNS)

    fireworks_status = (
        collect_fireworks_catalog(args, output_dir)
        if not args.retail_only
        else {"attempted": False, "reason": "ARM disabled by --retail-only."}
    )
    auth_status = (
        authenticated_pricing(args, output_dir, account, retail_rows)
        if not args.retail_only
        else {"attempted": False, "reason": "ARM disabled by --retail-only."}
    )

    summary = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "resourceGroup": None if args.retail_only else args.resource_group,
        "account": None if args.retail_only else args.account,
        "project": None if args.retail_only else args.project,
        "regions": regions,
        "currency": args.currency.upper(),
        "products": args.product or ["all"],
        "modelSkuRows": len(model_rows),
        "ptuModelSkuRows": sum(bool(row["ptu_capable"]) for row in model_rows),
        "ptuQuotaRows": len(ptu_quota_rows),
        "retailRows": len(retail_rows),
        "retailRowsByRegion": retail_counts,
        "fireworksCatalog": fireworks_status,
        "authenticatedPricing": auth_status,
    }
    write_json(output_dir / "summary.json", summary)
    print_summary(summary, output_dir)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProbeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        raise SystemExit(130)
