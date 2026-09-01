from __future__ import annotations

import json
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ZONE_MODE_LABELS = {
    "none": "No zone-specific support",
    "regional": "Regional service",
    "zonal": "Zonal support",
    "zone-redundant": "Zone-redundant support",
    "both": "Zonal and zone-redundant support",
    "unknown": "Unknown",
}


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=False)
        handle.write("\n")


def _slugify_identity(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", str(value or "").lower()).strip("-")
    return slug[:120] or "service"


def _unique_text(values: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for value in values:
        normalized = re.sub(r"\s+", " ", str(value or "")).strip()
        if not normalized:
            continue
        key = normalized.lower()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(normalized)
    return ordered


def build_canonical_identity_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    identities: list[dict[str, Any]] = []
    provider_index: dict[str, list[str]] = {}
    family_index: dict[str, list[str]] = {}

    for service in snapshot.get("services", []):
        display_name = str(service.get("display_name") or service.get("service_key") or "").strip()
        aliases = _unique_text([
            display_name,
            re.sub(r"^Azure\s+", "", display_name, flags=re.IGNORECASE),
            *list(service.get("aliases", [])),
        ])
        canonical_service_name = aliases[0] if aliases else display_name or str(service.get("service_key") or "service")
        canonical_service_id = _slugify_identity(canonical_service_name)
        canonical_family_key = str(service.get("family") or "service").strip().lower() or "service"
        provider_namespaces = sorted(
            {
                str(binding.get("namespace") or "").strip().lower()
                for binding in service.get("providers", [])
                if str(binding.get("namespace") or "").strip()
            }
        )
        resource_types = sorted(
            {
                str(resource_type).strip().lower()
                for binding in service.get("providers", [])
                for resource_type in binding.get("resource_types", [])
                if str(resource_type).strip()
            }
        )
        pricing = service.get("pricing") or {}
        pricing_filters = list(pricing.get("filters") or [])
        pricing_service_names = _unique_text([
            *(str(item.get("service_name") or "") for item in pricing_filters),
            *(str(value) for value in pricing.get("serviceNames") or []),
        ])
        pricing_service_families = _unique_text([
            *(str(item.get("service_family") or "") for item in pricing_filters),
            *(str(value) for value in pricing.get("serviceFamilies") or []),
        ])
        product_names = _unique_text([
            *(str(item.get("product_name_contains") or "") for item in pricing_filters),
            *(str(value) for value in pricing.get("productNames") or []),
        ])

        identities.append(
            {
                "serviceKey": str(service.get("service_key") or ""),
                "canonicalServiceId": canonical_service_id,
                "canonicalServiceName": canonical_service_name,
                "canonicalFamilyKey": canonical_family_key,
                "displayName": display_name,
                "providerNamespaces": provider_namespaces,
                "resourceTypes": resource_types,
                "aliases": aliases,
                "pricingServiceNames": pricing_service_names,
                "pricingServiceFamilies": pricing_service_families,
                "productNames": product_names,
            }
        )

        family_index.setdefault(canonical_family_key, []).append(canonical_service_id)
        for namespace in provider_namespaces:
            provider_index.setdefault(namespace, []).append(canonical_service_id)

    for mapping in (provider_index, family_index):
        for key, values in mapping.items():
            mapping[key] = sorted(dict.fromkeys(values))

    return {
        "schemaVersion": 1,
        "identityCount": len(identities),
        "identities": identities,
        "providerIndex": provider_index,
        "familyIndex": family_index,
    }


def _comparison_row_identity(row: dict[str, Any]) -> dict[str, Any]:
    details = row.get("details_json")
    service_identity: dict[str, Any] = {}
    if isinstance(details, str) and details:
        try:
            payload = json.loads(details)
        except json.JSONDecodeError:
            payload = None
        if isinstance(payload, dict) and isinstance(payload.get("serviceIdentity"), dict):
            service_identity = payload["serviceIdentity"]

    return {
        "canonicalServiceId": str(row.get("canonical_service_id") or service_identity.get("canonicalServiceId") or "").strip(),
        "canonicalServiceName": str(row.get("canonical_service_name") or row.get("service") or service_identity.get("canonicalServiceName") or "").strip(),
        "canonicalFamilyKey": str(row.get("service_family") or service_identity.get("canonicalFamilyKey") or service_identity.get("canonicalFamily") or "").strip(),
        "identitySource": str(row.get("identity_source") or service_identity.get("identitySource") or "").strip(),
        "isFallbackIdentity": bool(row.get("is_fallback_identity", False)) or bool(service_identity.get("isFallbackIdentity")) or service_identity.get("matched") is False,
        "diagnostics": list(service_identity.get("diagnostics") or []) if isinstance(service_identity.get("diagnostics"), list) else [],
    }


def build_identity_gap_report(rows: list[dict[str, Any]]) -> dict[str, Any]:
    fallback_rows: list[dict[str, Any]] = []
    provider_counts: dict[str, int] = {}
    service_counts: dict[str, int] = {}
    family_counts: dict[str, int] = {}
    identity_source_counts: dict[str, int] = {}

    for row in rows:
        identity = _comparison_row_identity(row)
        identity_source = identity["identitySource"]
        if identity_source:
            identity_source_counts[identity_source] = identity_source_counts.get(identity_source, 0) + 1
        if not identity["isFallbackIdentity"]:
            continue

        provider = str(row.get("provider") or "").strip()
        canonical_service_name = identity["canonicalServiceName"] or provider or str(row.get("row_key") or "row")
        canonical_service_id = identity["canonicalServiceId"] or _slugify_identity(canonical_service_name)
        canonical_family_key = identity["canonicalFamilyKey"] or "service"
        provider_counts[provider] = provider_counts.get(provider, 0) + 1
        service_counts[canonical_service_id] = service_counts.get(canonical_service_id, 0) + 1
        family_counts[canonical_family_key] = family_counts.get(canonical_family_key, 0) + 1
        fallback_rows.append(
            {
                "rowKey": str(row.get("row_key") or ""),
                "comparisonMode": str(row.get("comparison_mode") or ""),
                "provider": provider,
                "service": str(row.get("service") or canonical_service_name),
                "canonicalServiceId": canonical_service_id,
                "canonicalServiceName": canonical_service_name,
                "canonicalFamilyKey": canonical_family_key,
                "identitySource": identity_source,
                "availability": str(row.get("availability") or ""),
                "sourceRegion": str(row.get("source_region") or ""),
                "targetRegion": str(row.get("target_region") or ""),
                "diagnostics": identity["diagnostics"],
                "notes": str(row.get("notes") or ""),
            }
        )

    fallback_rows.sort(key=lambda item: (item["provider"], item["canonicalServiceName"], item["rowKey"]))
    return {
        "schemaVersion": 1,
        "rowCount": len(rows),
        "fallbackCount": len(fallback_rows),
        "identitySourceCounts": dict(sorted(identity_source_counts.items())),
        "topFallbackProviders": [
            {"provider": provider, "count": count}
            for provider, count in sorted(provider_counts.items(), key=lambda item: (-item[1], item[0]))[:10]
        ],
        "topFallbackServices": [
            {"canonicalServiceId": service_id, "count": count}
            for service_id, count in sorted(service_counts.items(), key=lambda item: (-item[1], item[0]))[:15]
        ],
        "familyCounts": dict(sorted(family_counts.items())),
        "fallbackRows": fallback_rows,
    }


def build_catalog_snapshot(source: Path) -> dict[str, Any]:
    payload = load_json(source)
    services = payload.get("services", [])
    provider_index: dict[str, list[str]] = {}

    for service in services:
        for binding in service.get("providers", []):
            namespace = str(binding.get("namespace", "")).lower()
            if namespace:
                provider_index.setdefault(namespace, []).append(service["service_key"])

    payload["provider_index"] = provider_index
    return payload


def collect_sku_names(record: dict[str, Any]) -> set[str]:
    sku_names: set[str] = set()
    for region_key in ("sourceRegion", "targetRegion"):
        for sku in record.get(region_key, {}).get("skus", []):
            name = sku.get("name")
            if name:
                sku_names.add(str(name).lower())
    return sku_names


def get_regional_override(service: dict[str, Any], region: str) -> dict[str, Any]:
    return service.get("regional_overrides", {}).get(region, {})


def score_binding(
    binding: dict[str, Any],
    resource_types: set[str],
    sku_names: set[str],
    has_skus: bool,
) -> int:
    score = 0
    binding_types = {str(item).lower() for item in binding.get("resource_types", [])}
    hints = binding.get("match_hints", {})

    exact_matches = len(binding_types.intersection(resource_types))
    score += exact_matches * 20

    for token in hints.get("resource_type_contains", []):
        token_lower = str(token).lower()
        if any(token_lower in resource_type for resource_type in resource_types):
            score += 8

    for token in hints.get("sku_name_contains", []):
        token_lower = str(token).lower()
        if any(token_lower in sku_name for sku_name in sku_names):
            score += 6

    if has_skus and hints.get("prefer_when_skus"):
        score += 4

    if (not has_skus) and hints.get("prefer_when_no_skus"):
        score += 12

    if hints.get("shared_provider_fallback"):
        score += 2

    return score


def build_catalog_sqlite(snapshot: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(output_path)
    try:
        cursor = connection.cursor()
        cursor.executescript(
            """
            DROP TABLE IF EXISTS services;
            DROP TABLE IF EXISTS provider_bindings;
            DROP TABLE IF EXISTS capabilities;
            DROP TABLE IF EXISTS evidence;

            CREATE TABLE services (
                service_key TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                family TEXT NOT NULL,
                summary TEXT,
                zone_mode TEXT,
                zone_notes TEXT
            );

            CREATE TABLE provider_bindings (
                service_key TEXT NOT NULL,
                namespace TEXT NOT NULL,
                resource_types_json TEXT,
                FOREIGN KEY(service_key) REFERENCES services(service_key)
            );

            CREATE TABLE capabilities (
                service_key TEXT NOT NULL,
                capability_key TEXT NOT NULL,
                label TEXT NOT NULL,
                category TEXT,
                importance TEXT,
                notes TEXT,
                availability_default TEXT,
                availability_regions_json TEXT,
                PRIMARY KEY(service_key, capability_key),
                FOREIGN KEY(service_key) REFERENCES services(service_key)
            );

            CREATE TABLE evidence (
                service_key TEXT NOT NULL,
                source_type TEXT,
                source_url TEXT,
                last_verified TEXT,
                notes TEXT,
                FOREIGN KEY(service_key) REFERENCES services(service_key)
            );
            """
        )

        for service in snapshot.get("services", []):
            zone_support = service.get("zone_support", {})
            cursor.execute(
                "INSERT INTO services VALUES (?, ?, ?, ?, ?, ?)",
                (
                    service["service_key"],
                    service.get("display_name"),
                    service.get("family"),
                    service.get("summary"),
                    zone_support.get("default", "unknown"),
                    zone_support.get("notes"),
                ),
            )

            for binding in service.get("providers", []):
                cursor.execute(
                    "INSERT INTO provider_bindings VALUES (?, ?, ?)",
                    (
                        service["service_key"],
                        binding.get("namespace"),
                        json.dumps(binding.get("resource_types", [])),
                    ),
                )

            for capability in service.get("capabilities", []):
                availability = capability.get("availability", {})
                cursor.execute(
                    "INSERT INTO capabilities VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        service["service_key"],
                        capability.get("key"),
                        capability.get("label"),
                        capability.get("category"),
                        capability.get("importance"),
                        capability.get("notes"),
                        availability.get("default", "available"),
                        json.dumps(availability.get("regions", {})),
                    ),
                )

            for evidence in service.get("evidence", []):
                cursor.execute(
                    "INSERT INTO evidence VALUES (?, ?, ?, ?, ?)",
                    (
                        service["service_key"],
                        evidence.get("source_type"),
                        evidence.get("source_url"),
                        evidence.get("last_verified"),
                        evidence.get("notes"),
                    ),
                )

        connection.commit()
    finally:
        connection.close()


def service_present(record: dict[str, Any], region_key: str) -> bool:
    status = record.get("status", "")
    if region_key == "sourceRegion":
        return status not in {"TARGET_ONLY", "NOT_AVAILABLE"}
    return status not in {"SOURCE_ONLY", "NOT_AVAILABLE"}


def collect_resource_types(record: dict[str, Any]) -> set[str]:
    resource_types: set[str] = set()
    for region_key in ("sourceRegion", "targetRegion"):
        for sku in record.get(region_key, {}).get("skus", []):
            resource_type = sku.get("resourceType")
            if resource_type:
                resource_types.add(str(resource_type).lower())
    return resource_types


def match_service(snapshot: dict[str, Any], record: dict[str, Any]) -> dict[str, Any] | None:
    provider = str(record.get("provider", "")).lower()
    namespace = provider.split("/")[0]
    candidates: list[str] = []

    provider_index = snapshot.get("provider_index", {})
    candidates.extend(provider_index.get(provider, []))
    if namespace != provider:
        candidates.extend(provider_index.get(namespace, []))
    if not candidates:
        candidates.extend(provider_index.get(namespace, []))

    if not candidates:
        return None

    services = {service["service_key"]: service for service in snapshot.get("services", [])}
    resource_types = collect_resource_types(record)
    sku_names = collect_sku_names(record)
    has_skus = bool(sku_names)

    unique_candidates = list(dict.fromkeys(candidates))

    if len(unique_candidates) == 1:
        return services[unique_candidates[0]]

    scored_candidates: list[tuple[int, str]] = []
    for candidate in unique_candidates:
        service = services[candidate]
        best_binding_score = 0
        for binding in service.get("providers", []):
            if str(binding.get("namespace", "")).lower() not in {provider, namespace}:
                continue
            best_binding_score = max(best_binding_score, score_binding(binding, resource_types, sku_names, has_skus))
        scored_candidates.append((best_binding_score, candidate))

    scored_candidates.sort(key=lambda item: (-item[0], item[1]))
    if scored_candidates and scored_candidates[0][0] > 0:
        return services[scored_candidates[0][1]]

    return services[unique_candidates[0]]


def parse_zone_flag(value: str) -> str:
    lowered = (value or "unknown").strip().lower()
    if lowered in {"true", "false", "unknown"}:
        return lowered
    return "unknown"


def resolve_zone_mode(service: dict[str, Any], region: str, region_has_zones: str, is_service_available: bool) -> dict[str, Any]:
    zone_support = service.get("zone_support", {})
    override = get_regional_override(service, region)
    zone_override = override.get("zone_support", {})
    mode = zone_override.get("mode", zone_support.get("regions", {}).get(region, zone_support.get("default", "unknown")))
    notes = zone_override.get("notes", zone_support.get("notes"))
    explicit_region_mode = "mode" in zone_override or region in zone_support.get("regions", {})

    if not is_service_available:
        return {
            "mode": "service-unavailable",
            "label": "Service unavailable in region",
            "notes": notes,
        }

    if region_has_zones == "false":
        return {
            "mode": "region-without-zones",
            "label": "Region does not expose availability zones",
            "notes": notes,
        }

    if region_has_zones == "unknown" and not explicit_region_mode and mode in {"both", "zonal", "zone-redundant"}:
        return {
            "mode": "zone-support-unverified",
            "label": "Availability zone posture not verified",
            "notes": notes,
        }

    return {
        "mode": mode,
        "label": ZONE_MODE_LABELS.get(mode, mode),
        "notes": notes,
    }


def resolve_capability_details(service: dict[str, Any], capability: dict[str, Any], region: str, is_service_available: bool, region_has_zones: str = 'unknown') -> dict[str, str]:
    if not is_service_available:
        return {"status": "unavailable", "notes": capability.get("notes", "")}

    availability = capability.get("availability", {})
    override = get_regional_override(service, region).get("capabilities", {}).get(capability.get("key"), {})
    status = override.get("status", availability.get("regions", {}).get(region, availability.get("default", "available")))
    notes = override.get("notes", capability.get("notes", ""))

    if capability.get("requires_zone_support") and status == "available" and region_has_zones == "false":
        return {"status": "not-applicable", "notes": "Region does not expose availability zones"}

    return {"status": status, "notes": notes}


def enrich_record(
    snapshot: dict[str, Any],
    record: dict[str, Any],
    source_region_has_zones: str,
    target_region_has_zones: str,
) -> dict[str, Any]:
    service = match_service(snapshot, record)
    if not service:
        record["curated"] = {
            "matched": False,
            "displayName": None,
            "family": None,
            "summary": None,
            "sourceRegion": {
                "regionHasAvailabilityZones": source_region_has_zones,
            },
            "targetRegion": {
                "regionHasAvailabilityZones": target_region_has_zones,
            },
            "summaryStats": {
                "capabilityCount": 0,
                "differentCapabilityCount": 0,
            },
        }
        return record

    source_region_name = record.get("sourceRegion", {}).get("name", "")
    target_region_name = record.get("targetRegion", {}).get("name", "")
    source_present = service_present(record, "sourceRegion")
    target_present = service_present(record, "targetRegion")

    capabilities = []
    different_count = 0
    for capability in service.get("capabilities", []):
        source_details = resolve_capability_details(service, capability, source_region_name, source_present, source_region_has_zones)
        target_details = resolve_capability_details(service, capability, target_region_name, target_present, target_region_has_zones)
        if source_details["status"] != target_details["status"]:
            different_count += 1
        capabilities.append(
            {
                "key": capability.get("key"),
                "label": capability.get("label"),
                "category": capability.get("category"),
                "importance": capability.get("importance"),
                "sourceStatus": source_details["status"],
                "targetStatus": target_details["status"],
                "notes": capability.get("notes"),
                "sourceNotes": source_details["notes"],
                "targetNotes": target_details["notes"],
            }
        )

    source_override = get_regional_override(service, source_region_name)
    target_override = get_regional_override(service, target_region_name)

    record["curated"] = {
        "matched": True,
        "serviceKey": service.get("service_key"),
        "displayName": service.get("display_name"),
        "family": service.get("family"),
        "summary": service.get("summary"),
        "capabilities": capabilities,
        "evidence": service.get("evidence", []),
        "sourceRegion": {
            "name": source_region_name,
            "serviceAvailable": source_present,
            "regionHasAvailabilityZones": source_region_has_zones,
            "regionNote": source_override.get("notes"),
            "zoneSupport": resolve_zone_mode(service, source_region_name, source_region_has_zones, source_present),
            "zoneDependentSkuCount": record.get("sourceRegion", {}).get("zoneDependentSkuCount", 0),
            "effectiveSkuCount": record.get("sourceRegion", {}).get("effectiveSkuCount"),
        },
        "targetRegion": {
            "name": target_region_name,
            "serviceAvailable": target_present,
            "regionHasAvailabilityZones": target_region_has_zones,
            "regionNote": target_override.get("notes"),
            "zoneSupport": resolve_zone_mode(service, target_region_name, target_region_has_zones, target_present),
            "zoneDependentSkuCount": record.get("targetRegion", {}).get("zoneDependentSkuCount", 0),
            "effectiveSkuCount": record.get("targetRegion", {}).get("effectiveSkuCount"),
        },
        "summaryStats": {
            "capabilityCount": len(capabilities),
            "differentCapabilityCount": different_count,
            "matchedCapabilityCount": len(capabilities) - different_count,
        },
    }
    return record


@dataclass
class BuildCatalogResult:
    snapshot: dict[str, Any]
    output_json: Path
    output_sqlite: Path