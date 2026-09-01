from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any
from urllib import parse, request

from azure.identity import DefaultAzureCredential
from shared.config import Settings, load_settings
from shared.curated_catalog import (
    build_curated_regional_details,
    build_curated_regional_details_for_service,
    match_services_for_namespace,
    resolve_service_identity,
    service_bound_resource_types,
)

RESOURCE_GRAPH_API_VERSION = '2024-04-01'
PROVIDERS_API_VERSION = '2021-04-01'
COMPUTE_SKUS_API_VERSION = '2024-03-01'
STORAGE_SKUS_API_VERSION = '2024-01-01'
LOCATIONS_API_VERSION = '2022-12-01'

CURATED_REGIONAL_PROVIDERS = {
    'microsoft.analysisservices',
    'microsoft.apimanagement',
    'microsoft.app',
    'microsoft.appconfiguration',
    'microsoft.appplatform',
    'microsoft.automation',
    'microsoft.batch',
    'microsoft.cache',
    'microsoft.cdn',
    'microsoft.chaos',
    'microsoft.cognitiveservices',
    'microsoft.communication',
    'microsoft.compute',
    'microsoft.confidentialledger',
    'microsoft.containerinstance',
    'microsoft.containerregistry',
    'microsoft.containerservice',
    'microsoft.datafactory',
    'microsoft.databricks',
    'microsoft.dbformysql',
    'microsoft.dbforpostgresql',
    'microsoft.devices',
    'microsoft.documentdb',
    'microsoft.elasticsan',
    'microsoft.eventgrid',
    'microsoft.eventhub',
    'microsoft.insights',
    'microsoft.keyvault',
    'microsoft.kusto',
    'microsoft.logic',
    'microsoft.machinelearningservices',
    'microsoft.network',
    'microsoft.netapp',
    'microsoft.notificationhubs',
    'microsoft.operationalinsights',
    'microsoft.purview',
    'microsoft.recoveryservices',
    'microsoft.redhatopenshift',
    'microsoft.relay',
    'microsoft.search',
    'microsoft.servicebus',
    'microsoft.servicefabric',
    'microsoft.signalrservice',
    'microsoft.sql',
    'microsoft.storage',
    'microsoft.storagemover',
    'microsoft.streamanalytics',
    'microsoft.synapse',
    'microsoft.web',
}

@dataclass(frozen=True)
class InventorySummary:
    service: str
    provider: str
    service_family: str
    sku: str
    count: int


def _slugify(value: str) -> str:
    slug = re.sub(r'[^a-z0-9]+', '-', value.lower()).strip('-')
    return slug[:120] or 'item'


def _normalize_region_name(value: str) -> str:
    return re.sub(r'[^a-z0-9]+', '', value.lower())


def _service_family(resource_type: str) -> str:
    namespace = resource_type.split('/')[0].lower()
    families = {
        'microsoft.compute': 'compute',
        'microsoft.storage': 'storage',
        'microsoft.network': 'networking',
        'microsoft.sql': 'databases',
        'microsoft.dbforpostgresql': 'databases',
        'microsoft.dbformysql': 'databases',
        'microsoft.documentdb': 'databases',
        'microsoft.cache': 'cache',
        'microsoft.web': 'app',
        'microsoft.insights': 'monitoring',
        'microsoft.containerservice': 'containers',
        'microsoft.kubernetes': 'containers',
    }
    return families.get(namespace, namespace.removeprefix('microsoft.'))


def _service_name(resource_type: str, sku: str) -> str:
    known = {
        'microsoft.compute/virtualmachines': 'Virtual Machine',
        'microsoft.compute/disks': 'Managed Disk',
        'microsoft.storage/storageaccounts': 'Storage Account',
        'microsoft.web/sites': 'App Service / Function App',
        'microsoft.insights/workbooks': 'Workbook',
        'microsoft.sql/servers/databases': 'Azure SQL Database',
        'microsoft.containerservice/managedclusters': 'Azure Kubernetes Service',
    }
    resource_key = resource_type.lower()
    if resource_key in known:
        return known[resource_key]

    leaf = resource_type.split('/')[-1]
    normalized = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', leaf).replace('-', ' ')
    normalized = normalized.replace('_', ' ')
    normalized = re.sub(r'\s+', ' ', normalized).strip()
    if sku:
        return f'{normalized.title()} ({sku})'
    return normalized.title()


def _humanize_resource_type(resource_type: str) -> str:
    segments: list[str] = []
    for segment in resource_type.split('/'):
        normalized = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', segment)
        normalized = normalized.replace('-', ' ').replace('_', ' ')
        normalized = re.sub(r'\s+', ' ', normalized).strip()
        if normalized:
            segments.append(normalized.title())
    return ' / '.join(segments) or resource_type


def _provider_display_name(namespace: str) -> str:
    normalized = namespace.removeprefix('microsoft.')
    normalized = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', normalized)
    normalized = normalized.replace('.', ' / ')
    normalized = re.sub(r'\s+', ' ', normalized).strip()
    return normalized.title() or namespace


def _pricing_identity(provider: str, *, service_name: str, resource_types: set[str] | None = None) -> dict[str, Any]:
    return resolve_service_identity(provider, resource_types=resource_types, service_name=service_name)


def _resolved_service_family(default_family: str, pricing_identity: dict[str, Any] | None) -> str:
    if pricing_identity is None:
        return default_family
    return str(
        pricing_identity.get('canonicalFamilyKey')
        or pricing_identity.get('canonicalFamily')
        or default_family
    )


def _authoritative_row_identity(
    pricing_identity: dict[str, Any] | None,
    *,
    service_name: str,
    service_family: str,
) -> dict[str, Any]:
    canonical_service_name = str(
        (pricing_identity or {}).get('canonicalServiceName')
        or (pricing_identity or {}).get('displayName')
        or service_name
    ).strip()
    canonical_service_id = str((pricing_identity or {}).get('canonicalServiceId') or _slugify(canonical_service_name)).strip()
    canonical_family = _resolved_service_family(service_family, pricing_identity)
    identity_source = str((pricing_identity or {}).get('identitySource') or '').strip()
    is_fallback_identity = bool((pricing_identity or {}).get('isFallbackIdentity')) or (pricing_identity or {}).get('matched') is False
    return {
        'service': canonical_service_name,
        'service_family': canonical_family,
        'canonical_service_id': canonical_service_id,
        'canonical_service_name': canonical_service_name,
        'identity_source': identity_source,
        'is_fallback_identity': is_fallback_identity,
    }


def _build_detail_section(title: str, resource_types: list[str], *, limit: int = 12) -> dict[str, Any]:
    preview = resource_types[:limit]
    return {
        'title': title,
        'count': len(resource_types),
        'items': [
            {
                'resourceType': item,
                'label': _humanize_resource_type(item),
            }
            for item in preview
        ],
        'omittedCount': max(0, len(resource_types) - len(preview)),
    }


def _build_regional_notes(*, source_region: str, target_region: str, shared_count: int, source_only_count: int, target_only_count: int) -> str:
    fragments: list[str] = []
    if shared_count:
        fragments.append(f'{shared_count} shared deployable capability type(s) appear in both regions.')
    if source_only_count:
        fragments.append(f'{source_region} adds {source_only_count} capability type(s) that are not listed in {target_region}.')
    if target_only_count:
        fragments.append(f'{target_region} adds {target_only_count} capability type(s) that are not listed in {source_region}.')
    if not fragments:
        return f'Provider metadata is available for both {source_region} and {target_region}, but no capability breakdown is available.'
    return ' '.join(fragments)


def _status_from_counts(source_count: int, target_count: int) -> str:
    if source_count == 0 and target_count == 0:
        return 'UNAVAILABLE'
    if source_count == target_count:
        return 'FULL_MATCH'
    if source_count > target_count:
        return 'SOURCE_EXTENDED'
    return 'TARGET_EXTENDED'


def _metric_cards(*pairs: tuple[str, int | str]) -> list[dict[str, int | str]]:
    return [{'label': label, 'value': value} for label, value in pairs]


def _capability_values(sku: dict[str, Any]) -> dict[str, str]:
    return {
        str(capability.get('name', '')).lower(): str(capability.get('value', ''))
        for capability in sku.get('capabilities', [])
    }


def _truthy(value: str | bool | None) -> bool:
    return str(value or '').strip().lower() in {'1', 'true', 'yes', 'supported', 'available'}


def _normalize_family_name(value: str) -> str:
    normalized = re.sub(r'(?i)^standard', '', value).strip('_- ')
    normalized = re.sub(r'(?i)family$', '', normalized).strip('_- ')
    normalized = normalized.replace('_', '')
    if not normalized:
        return value
    return normalized[0].upper() + normalized[1:]


def _vm_family_name(sku: dict[str, Any]) -> str:
    family = str(sku.get('family') or '')
    if family:
        return _normalize_family_name(family)

    size = str(sku.get('size') or sku.get('name') or '')
    size = re.sub(r'(?i)^standard_', '', size)
    match = re.match(r'([A-Za-z]+)\d+([A-Za-z]*)(?:_?(v\d+))?', size)
    if match:
        return f'{match.group(1)}{match.group(2)}{match.group(3) or ""}'
    return size or 'Unknown'


def _available_compute_entries(entries: list[dict[str, Any]], resource_type: str, *, include_restricted: bool = False) -> list[dict[str, Any]]:
    return [
        entry
        for entry in entries
        if str(entry.get('resourceType', '')).lower() == resource_type and (include_restricted or not (entry.get('restrictions') or []))
    ]


def _restriction_reason_codes(entry: dict[str, Any]) -> set[str]:
    return {
        str(restriction.get('reasonCode') or '').strip()
        for restriction in list(entry.get('restrictions') or [])
        if str(restriction.get('reasonCode') or '').strip()
    }


def _family_availability_rows(entries: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for entry in entries:
        family = _vm_family_name(entry)
        current = rows.setdefault(
            family,
            {
                'count': 0,
                'restrictedCount': 0,
                'restrictionReasonCodes': set(),
            },
        )
        current['count'] += 1
        restriction_codes = _restriction_reason_codes(entry)
        if restriction_codes:
            current['restrictedCount'] += 1
            current['restrictionReasonCodes'].update(restriction_codes)
    return rows


def _family_rows(entries: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for entry in entries:
        family = _vm_family_name(entry)
        counts[family] = counts.get(family, 0) + 1
    return counts


def _build_service_availability_details(
    curated: dict[str, Any],
    *,
    source_region: str,
    target_region: str,
    source_count: int,
    target_count: int,
) -> dict[str, Any]:
    source_available = bool(curated.get('sourceRegion', {}).get('serviceAvailable'))
    target_available = bool(curated.get('targetRegion', {}).get('serviceAvailable'))
    unavailable_region = source_region if not source_available else target_region if not target_available else ''
    available_region = target_region if not source_available else source_region if not target_available else ''
    summary = str(curated.get('summary') or '')
    if unavailable_region and available_region:
        summary = f'{curated.get("displayName") or "Service"} is not available in {unavailable_region}. {available_region} retains service availability.'

    return {
        'layout': 'service-availability',
        'providerNamespace': curated.get('serviceKey'),
        'summary': {
            'sourceCount': source_count,
            'targetCount': target_count,
            'sharedCount': 0,
            'sourceOnlyCount': source_count if source_available and not target_available else 0,
            'targetOnlyCount': target_count if target_available and not source_available else 0,
        },
        'metricCards': _metric_cards(
            ('Source metadata types', source_count),
            ('Target metadata types', target_count),
            ('Service available regions', int(source_available) + int(target_available)),
        ),
        'curated': {
            **curated,
            'summary': summary,
            'summaryStats': {
                'capabilityCount': 0,
                'differentCapabilityCount': 0,
                'matchedCapabilityCount': 0,
            },
            'capabilities': [],
        },
        'availabilitySummary': {
            'message': summary,
            'availableRegion': available_region,
            'unavailableRegion': unavailable_region,
        },
    }


def _family_filter_for_inventory(resources: list[dict[str, Any]], source_entries: list[dict[str, Any]]) -> set[str]:
    sku_index = {
        str(entry.get('name', '')).lower(): entry
        for entry in source_entries
        if str(entry.get('name', '')).strip()
    }
    families: set[str] = set()
    for resource in resources:
        vm_size = str(resource.get('vmSize') or resource.get('skuName') or '').strip()
        if not vm_size:
            continue
        sku_entry = sku_index.get(vm_size.lower())
        if sku_entry is not None:
            families.add(_vm_family_name(sku_entry))
            continue
        families.add(_vm_family_name({'family': '', 'size': vm_size}))
    return families


def _augment_curated_details(
    curated: dict[str, Any],
    *,
    source_region: str,
    target_region: str,
    source_types: list[str],
    target_types: list[str],
    shared_types: list[str],
    source_only_types: list[str],
    target_only_types: list[str],
    expanded_capabilities: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    capabilities = list(curated.get('capabilities') or [])
    mapped_types = {str(item).lower() for item in (curated.get('mappedResourceTypes') or []) if str(item).strip()}
    residual_shared_types = sorted(set(shared_types) - mapped_types)
    residual_source_only_types = sorted(set(source_only_types) - mapped_types)
    residual_target_only_types = sorted(set(target_only_types) - mapped_types)

    different_count = sum(
        1
        for capability in capabilities
        if str(capability.get('sourceStatus', '')) != str(capability.get('targetStatus', ''))
    )
    matched_count = len(capabilities) - different_count
    return {
        **curated,
        'capabilities': capabilities,
        'expandedCapabilities': expanded_capabilities
        if expanded_capabilities is not None
        else [
            section
            for section in [
                _build_provider_type_expansion(
                    source_region=source_region,
                    target_region=target_region,
                    shared_types=residual_shared_types,
                    source_only_types=residual_source_only_types,
                    target_only_types=residual_target_only_types,
                ),
            ]
            if section is not None
        ],
        'summaryStats': {
            **curated.get('summaryStats', {}),
            'capabilityCount': len(capabilities),
            'differentCapabilityCount': different_count,
            'matchedCapabilityCount': matched_count,
        },
    }


def _expanded_group(title: str, items: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not items:
        return None
    return {
        'title': title,
        'count': len(items),
        'items': items,
    }


def _build_provider_type_expansion(
    *,
    source_region: str,
    target_region: str,
    shared_types: list[str],
    source_only_types: list[str],
    target_only_types: list[str],
) -> dict[str, Any] | None:
    shared_items = [
        {
            'key': resource_type,
            'label': resource_type,
            'sourceValue': 'present',
            'targetValue': 'present',
            'sourceDetails': f'{resource_type} is exposed in {source_region} provider metadata.',
            'targetDetails': f'{resource_type} is exposed in {target_region} provider metadata.',
        }
        for resource_type in shared_types
    ]
    source_only_items = [
        {
            'key': resource_type,
            'label': resource_type,
            'sourceValue': 'present',
            'targetValue': 'missing',
            'sourceDetails': f'{resource_type} is exposed in {source_region} provider metadata.',
            'targetDetails': f'{resource_type} is not listed for {target_region}.',
        }
        for resource_type in source_only_types
    ]
    target_only_items = [
        {
            'key': resource_type,
            'label': resource_type,
            'sourceValue': 'missing',
            'targetValue': 'present',
            'sourceDetails': f'{resource_type} is not listed for {source_region}.',
            'targetDetails': f'{resource_type} is exposed in {target_region} provider metadata.',
        }
        for resource_type in target_only_types
    ]
    groups = [
        _expanded_group('Shared provider types', shared_items),
        _expanded_group(f'Only in {source_region}', source_only_items),
        _expanded_group(f'Only in {target_region}', target_only_items),
    ]
    groups = [group for group in groups if group is not None]
    total = len(shared_items) + len(source_only_items) + len(target_only_items)
    if not total:
        return None
    return {
        'key': 'provider-metadata-types',
        'title': 'Unmapped provider metadata',
        'description': 'Raw provider metadata types that are not directly represented by the seeded curated capability rows.',
        'count': total,
        'groups': groups,
    }


def _format_capability_value(values: set[str]) -> str:
    normalized = sorted(value for value in values if value)
    if not normalized:
        return 'missing'
    if len(normalized) == 1:
        return normalized[0]
    preview = ', '.join(normalized[:3])
    if len(normalized) > 3:
        return f'{preview} (+{len(normalized) - 3} more)'
    return preview


def _aggregate_capability_properties(
    entries: list[dict[str, Any]],
    *,
    region: str,
    excluded_keys: set[str],
) -> dict[str, dict[str, Any]]:
    aggregated: dict[str, dict[str, Any]] = {}
    for entry in entries:
        sku_name = str(entry.get('name', '')).strip() or 'unknown'
        for capability in entry.get('capabilities', []) or []:
            property_name = str(capability.get('name', '')).strip()
            if not property_name:
                continue
            property_key = property_name.lower()
            if property_key in excluded_keys:
                continue
            current = aggregated.setdefault(
                property_key,
                {
                    'label': property_name,
                    'values': set(),
                    'skus': set(),
                    'resourceTypes': set(),
                    'region': region,
                },
            )
            current['values'].add(str(capability.get('value', '')).strip())
            current['skus'].add(sku_name)
            resource_type = str(entry.get('resourceType', '')).strip()
            if resource_type:
                current['resourceTypes'].add(resource_type)
    return aggregated


def _build_storage_capability_expansion(
    *,
    source_region: str,
    target_region: str,
    source_entries: list[dict[str, Any]],
    target_entries: list[dict[str, Any]],
) -> dict[str, Any] | None:
    excluded_keys = {
        'supportshierarchicalnamespace',
        'supportssftp',
        'supportsnfsv3',
        'supportsnfsshare',
        'supportslargefileshares',
    }
    source_properties = _aggregate_capability_properties(source_entries, region=source_region, excluded_keys=excluded_keys)
    target_properties = _aggregate_capability_properties(target_entries, region=target_region, excluded_keys=excluded_keys)
    all_keys = sorted(set(source_properties) | set(target_properties))
    if not all_keys:
        return None

    shared_items: list[dict[str, Any]] = []
    source_only_items: list[dict[str, Any]] = []
    target_only_items: list[dict[str, Any]] = []
    for property_key in all_keys:
        source_property = source_properties.get(property_key)
        target_property = target_properties.get(property_key)
        label = str((source_property or target_property or {}).get('label') or property_key)
        source_value = _format_capability_value(set((source_property or {}).get('values') or set()))
        target_value = _format_capability_value(set((target_property or {}).get('values') or set()))
        source_skus = sorted((source_property or {}).get('skus') or [])
        target_skus = sorted((target_property or {}).get('skus') or [])
        source_types = sorted((source_property or {}).get('resourceTypes') or [])
        target_types = sorted((target_property or {}).get('resourceTypes') or [])
        item = {
            'key': property_key,
            'label': label,
            'sourceValue': source_value,
            'targetValue': target_value,
            'sourceDetails': f'{label} appears on {len(source_skus)} source SKU(s): {", ".join(source_skus[:4])}{" ..." if len(source_skus) > 4 else ""}' if source_skus else f'{label} is not present on sampled {source_region} storage SKUs.',
            'targetDetails': f'{label} appears on {len(target_skus)} target SKU(s): {", ".join(target_skus[:4])}{" ..." if len(target_skus) > 4 else ""}' if target_skus else f'{label} is not present on sampled {target_region} storage SKUs.',
            'sourceMeta': ', '.join(source_types[:2]) if source_types else '',
            'targetMeta': ', '.join(target_types[:2]) if target_types else '',
        }
        if source_property and target_property:
            shared_items.append(item)
        elif source_property:
            source_only_items.append(item)
        else:
            target_only_items.append(item)

    groups = [
        _expanded_group('Shared raw properties', shared_items),
        _expanded_group(f'Only in {source_region}', source_only_items),
        _expanded_group(f'Only in {target_region}', target_only_items),
    ]
    groups = [group for group in groups if group is not None]
    return {
        'key': 'storage-raw-properties',
        'title': 'Unmapped raw SKU properties',
        'description': 'Raw Azure Storage SKU capability properties that are not already covered by the seeded curated storage mappings.',
        'count': len(shared_items) + len(source_only_items) + len(target_only_items),
        'groups': groups,
    }


def _build_vm_family_details(
    *,
    source_region: str,
    target_region: str,
    source_entries: list[dict[str, Any]],
    target_entries: list[dict[str, Any]],
    family_filter: set[str] | None = None,
    inventory_resource_count: int | None = None,
) -> dict[str, Any]:
    source_rows = _family_availability_rows(source_entries)
    target_rows = _family_availability_rows(target_entries)
    source_counts = {family: int(values.get('count', 0)) for family, values in source_rows.items()}
    target_counts = {family: int(values.get('count', 0)) for family, values in target_rows.items()}
    families = sorted(set(source_counts) | set(target_counts))
    if family_filter:
        filtered_families = [family for family in families if family in family_filter]
        if filtered_families:
            families = filtered_families

    rows: list[dict[str, Any]] = []
    for family in families:
        source_count = source_counts.get(family, 0)
        target_count = target_counts.get(family, 0)
        source_restricted_count = int((source_rows.get(family) or {}).get('restrictedCount', 0))
        target_restricted_count = int((target_rows.get(family) or {}).get('restrictedCount', 0))
        rows.append(
            {
                'family': family,
                'sourceCount': source_count,
                'targetCount': target_count,
                'sourceRestrictedCount': source_restricted_count,
                'targetRestrictedCount': target_restricted_count,
                'sourceDeployableCount': max(0, source_count - source_restricted_count),
                'targetDeployableCount': max(0, target_count - target_restricted_count),
                'sourceRestrictionReasonCodes': sorted((source_rows.get(family) or {}).get('restrictionReasonCodes') or []),
                'targetRestrictionReasonCodes': sorted((target_rows.get(family) or {}).get('restrictionReasonCodes') or []),
                'delta': source_count - target_count,
                'status': 'CONDITIONAL' if (source_restricted_count or target_restricted_count) else _status_from_counts(source_count, target_count),
            }
        )

    shared_count = sum(1 for row in rows if row['sourceCount'] and row['targetCount'])
    source_only_count = sum(1 for row in rows if row['sourceCount'] and not row['targetCount'])
    target_only_count = sum(1 for row in rows if row['targetCount'] and not row['sourceCount'])
    summary_text = _build_regional_notes(
        source_region=source_region,
        target_region=target_region,
        shared_count=shared_count,
        source_only_count=source_only_count,
        target_only_count=target_only_count,
    )
    if inventory_resource_count is not None:
        summary_text = f'{inventory_resource_count} source VM resource(s) map to {len(families)} family group(s). {summary_text}'

    source_restricted_total = sum(int((source_rows.get(family) or {}).get('restrictedCount', 0)) for family in families)
    target_restricted_total = sum(int((target_rows.get(family) or {}).get('restrictedCount', 0)) for family in families)
    source_total = sum(source_counts.get(family, 0) for family in families)
    target_total = sum(target_counts.get(family, 0) for family in families)
    restriction_notes: list[str] = []
    if source_restricted_total:
        if source_total and source_restricted_total == source_total:
            restriction_notes.append(f'All {source_region} VM SKU entries returned by the subscription-scoped SKU API are marked restricted for this subscription.')
        else:
            restriction_notes.append(f'{source_region} includes {source_restricted_total} subscription-restricted VM SKU entr{("y" if source_restricted_total == 1 else "ies")}.')
    if target_restricted_total:
        if target_total and target_restricted_total == target_total:
            restriction_notes.append(f'All {target_region} VM SKU entries returned by the subscription-scoped SKU API are marked restricted for this subscription.')
        else:
            restriction_notes.append(f'{target_region} includes {target_restricted_total} subscription-restricted VM SKU entr{("y" if target_restricted_total == 1 else "ies")}.')
    if restriction_notes:
        summary_text = f"{summary_text} {' '.join(restriction_notes)}"

    return {
        'layout': 'family-breakdown',
        'summary': {
            'sourceCount': source_total,
            'targetCount': target_total,
            'sharedCount': shared_count,
            'sourceOnlyCount': source_only_count,
            'targetOnlyCount': target_only_count,
            'sourceRestrictedCount': source_restricted_total,
            'targetRestrictedCount': target_restricted_total,
            'sourceDeployableCount': max(0, source_total - source_restricted_total),
            'targetDeployableCount': max(0, target_total - target_restricted_total),
        },
        'summaryText': summary_text,
        'metricCards': _metric_cards(
            ('Source VM families', sum(1 for row in rows if row['sourceCount'])),
            ('Shared families', shared_count),
            ('Family differences', source_only_count + target_only_count),
            ('Target VM families', sum(1 for row in rows if row['targetCount'])),
        ),
        'families': rows,
    }


def _normalize_lookup_value(value: Any) -> str:
    return ''.join(ch for ch in str(value or '').lower() if ch.isalnum())


def _extract_parenthetical_values(value: str) -> list[str]:
    return re.findall(r'\(([^)]+)\)', value or '')


def _vm_family_key_from_arm_sku(value: Any) -> str:
    normalized = str(value or '').strip().lower()
    if not normalized:
        return ''

    normalized = re.sub(r'^(standard|basic)[_-]?', '', normalized)
    normalized = re.sub(r'[^a-z0-9_]+', '', normalized)
    version_match = re.search(r'(?:_|)(v\d+)$', normalized)
    version = version_match.group(1) if version_match else ''
    without_version = normalized[: normalized.rfind(version)].rstrip('_') if version else normalized
    base_token = re.sub(r'\d+', '', (without_version.split('_')[0] or without_version))
    return _normalize_lookup_value(f'{base_token}{version}')


def _vm_family_keys_from_text(value: Any) -> set[str]:
    return {
        _normalize_lookup_value(match)
        for match in re.findall(r'\b([a-z]{1,8}[a-z0-9]*v\d+)\b', str(value or '').lower())
        if match
    }


def _pricing_sort_value(item: dict[str, Any]) -> float:
    candidates = [value for value in (item.get('sourcePrice'), item.get('targetPrice')) if isinstance(value, (int, float))]
    return min(candidates) if candidates else float('inf')


def _best_pricing_match(items: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not items:
        return None

    def sort_key(item: dict[str, Any]) -> tuple[int, float, str]:
        matched = 0 if item.get('sourceAvailable') and item.get('targetAvailable') else 1
        return (matched, _pricing_sort_value(item), str(item.get('label') or ''))

    return sorted(items, key=sort_key)[0]


def _compact_inline_pricing(item: dict[str, Any] | None) -> dict[str, Any] | None:
    if not item:
        return None

    compact: dict[str, Any] = {}
    for source_key, target_key in (
        ('label', 'label'),
        ('sourcePrice', 'sourcePrice'),
        ('targetPrice', 'targetPrice'),
        ('delta', 'delta'),
        ('deltaPercent', 'deltaPercent'),
        ('cheaperRegion', 'cheaperRegion'),
        ('currencyCode', 'currencyCode'),
        ('unitOfMeasure', 'unitOfMeasure'),
        ('sourceAvailable', 'sourceAvailable'),
        ('targetAvailable', 'targetAvailable'),
        ('sourceMeterName', 'sourceMeterName'),
        ('targetMeterName', 'targetMeterName'),
        ('sourcePriceType', 'sourcePriceType'),
        ('targetPriceType', 'targetPriceType'),
        ('sourceReservationTerm', 'sourceReservationTerm'),
        ('targetReservationTerm', 'targetReservationTerm'),
        ('offerLabel', 'offerLabel'),
    ):
        value = item.get(source_key)
        if value not in (None, ''):
            compact[target_key] = value

    source_savings = item.get('sourceSavingsPlan')
    target_savings = item.get('targetSavingsPlan')
    if isinstance(source_savings, list) and source_savings:
        compact['sourceSavingsPlan'] = source_savings
    if isinstance(target_savings, list) and target_savings:
        compact['targetSavingsPlan'] = target_savings
    return compact or None


def _pricing_type(item: dict[str, Any] | None, *, side: str = '') -> str:
    if not item:
        return ''
    if side:
        return str(item.get(f'{side}PriceType') or item.get('priceType') or '').strip()
    return str(item.get('sourcePriceType') or item.get('targetPriceType') or item.get('priceType') or '').strip()


def _pricing_term(item: dict[str, Any] | None, *, side: str = '') -> str:
    if not item:
        return ''
    if side:
        return str(item.get(f'{side}ReservationTerm') or item.get('reservationTerm') or '').strip()
    return str(item.get('sourceReservationTerm') or item.get('targetReservationTerm') or item.get('reservationTerm') or '').strip()


def _savings_plan_entries(item: dict[str, Any] | None, *, side: str) -> list[dict[str, Any]]:
    if not item:
        return []
    entries = item.get(f'{side}SavingsPlan')
    if not isinstance(entries, list):
        return []
    normalized: list[dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        term = str(entry.get('term') or '').strip()
        retail_price = entry.get('retailPrice', entry.get('unitPrice'))
        if not term or retail_price in (None, ''):
            continue
        normalized.append({
            'term': term,
            'retailPrice': retail_price,
            'unitPrice': entry.get('unitPrice', retail_price),
        })
    return normalized


def _compact_pricing_overlay_item(item: dict[str, Any] | None) -> dict[str, Any] | None:
    return _compact_inline_pricing(item)


def _pricing_group(title: str, key: str, items: list[dict[str, Any]]) -> dict[str, Any] | None:
    compact_items = [compact for compact in (_compact_pricing_overlay_item(item) for item in items) if compact]
    if not compact_items:
        return None
    return {
        'key': key,
        'title': title,
        'count': len(compact_items),
        'items': compact_items,
    }


def _pricing_delta(source_price: float | None, target_price: float | None, *, source_region: str, target_region: str) -> tuple[float | None, float | None, str | None]:
    delta = None if source_price is None or target_price is None else target_price - source_price
    delta_percent = None if delta is None or not source_price else (delta / source_price) * 100
    cheaper_region = None
    if source_price is not None and target_price is not None:
        if source_price < target_price:
            cheaper_region = source_region
        elif target_price < source_price:
            cheaper_region = target_region
        else:
            cheaper_region = 'same'
    return delta, delta_percent, cheaper_region


def _coerce_numeric_price(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _build_savings_plan_item(
    base_item: dict[str, Any],
    *,
    source_entry: dict[str, Any] | None,
    target_entry: dict[str, Any] | None,
    term: str,
    source_region: str,
    target_region: str,
) -> dict[str, Any] | None:
    source_price = _coerce_numeric_price((source_entry or {}).get('retailPrice'))
    target_price = _coerce_numeric_price((target_entry or {}).get('retailPrice'))
    if source_price is None and target_price is None:
        return None

    delta, delta_percent, cheaper_region = _pricing_delta(source_price, target_price, source_region=source_region, target_region=target_region)
    return {
        'key': f"{base_item.get('key') or base_item.get('label') or 'pricing'}|savings-plan|{_normalize_lookup_value(term)}",
        'label': str(base_item.get('label') or base_item.get('meterName') or base_item.get('skuName') or 'Savings plan'),
        'offerLabel': f'Savings plan {term.lower()}',
        'meterName': base_item.get('meterName'),
        'productName': base_item.get('productName'),
        'skuName': base_item.get('skuName'),
        'armSkuName': base_item.get('armSkuName'),
        'unitOfMeasure': base_item.get('unitOfMeasure'),
        'currencyCode': base_item.get('currencyCode'),
        'sourcePrice': source_price,
        'targetPrice': target_price,
        'sourceAvailable': source_price is not None,
        'targetAvailable': target_price is not None,
        'delta': delta,
        'deltaPercent': delta_percent,
        'cheaperRegion': cheaper_region,
        'sourceMeterName': base_item.get('sourceMeterName') or base_item.get('meterName'),
        'targetMeterName': base_item.get('targetMeterName') or base_item.get('meterName'),
        'sourcePriceType': 'SavingsPlan' if source_price is not None else None,
        'targetPriceType': 'SavingsPlan' if target_price is not None else None,
        'sourceReservationTerm': term if source_price is not None else None,
        'targetReservationTerm': term if target_price is not None else None,
    }


def _vm_consumption_rank(item: dict[str, Any]) -> tuple[int, int, int, float, str]:
    meter_name = str(item.get('meterName') or '').lower()
    product_name = str(item.get('productName') or '').lower()
    sku_name = str(item.get('skuName') or '').lower()
    combined = ' '.join(part for part in (meter_name, product_name, sku_name) if part)
    has_savings_plan = 0 if _savings_plan_entries(item, side='source') or _savings_plan_entries(item, side='target') else 1
    is_priority_meter = 1 if any(token in combined for token in ('spot', 'low priority', 'low-priority', 'promo', 'dev/test', 'devtest')) else 0
    is_primary_meter = 0 if item.get('isPrimaryMeterRegion') else 1
    return (has_savings_plan, is_priority_meter, is_primary_meter, _pricing_sort_value(item), str(item.get('label') or meter_name))


def _preferred_vm_consumption_match(items: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not items:
        return None
    return sorted(items, key=_vm_consumption_rank)[0]


VM_PRICING_MODEL_ORDER: list[tuple[str, str]] = [
    ('paygo', 'Pay as you go'),
    ('savings-plan-1-year', 'Savings plan 1 year'),
    ('savings-plan-3-years', 'Savings plan 3 years'),
    ('reserved-1-year', 'Reserved instance 1 year'),
    ('reserved-3-years', 'Reserved instance 3 years'),
]


def _vm_term_key(term: str) -> str:
    normalized = str(term or '').strip().lower()
    return normalized.replace(' years', '-years').replace(' year', '-year').replace(' ', '-')


def _vm_sku_label(item: dict[str, Any]) -> str:
    arm_sku = str(item.get('armSkuName') or item.get('sourceArmSkuName') or item.get('targetArmSkuName') or '').strip()
    if arm_sku:
        normalized = re.sub(r'(?i)^standard_', '', arm_sku).replace('_', ' ')
        return re.sub(r'\s+', ' ', normalized).strip()

    sku_name = str(item.get('skuName') or item.get('label') or item.get('meterName') or '').strip()
    return re.sub(r'\s+', ' ', sku_name).strip()


def _vm_sku_key(item: dict[str, Any]) -> str:
    return _normalize_lookup_value(_vm_sku_label(item))


def _vm_pricing_models(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    present_keys = {
        model_key
        for row in rows
        for model_key in list((row.get('offers') or {}).keys())
    }
    return [
        {'key': key, 'title': title}
        for key, title in VM_PRICING_MODEL_ORDER
        if key in present_keys
    ]


def _match_vm_family_pricing(family: str, comparison_items: list[dict[str, Any]], *, source_region: str, target_region: str) -> dict[str, Any] | None:
    family_key = _normalize_lookup_value(family)
    if not family_key:
        return None

    matches: list[dict[str, Any]] = []
    for item in comparison_items:
        item_keys = {
            _vm_family_key_from_arm_sku(item.get('armSkuName')),
            _vm_family_key_from_arm_sku(item.get('sourceArmSkuName')),
            _vm_family_key_from_arm_sku(item.get('targetArmSkuName')),
            *_vm_family_keys_from_text(item.get('productName')),
            *_vm_family_keys_from_text(item.get('skuName')),
            *_vm_family_keys_from_text(item.get('meterName')),
            *_vm_family_keys_from_text(item.get('label')),
        }
        item_keys.discard('')
        if family_key in item_keys:
            matches.append(item)

    if not matches:
        return None

    consumption_matches = [item for item in matches if _pricing_type(item) == 'Consumption']
    reservation_matches = [item for item in matches if _pricing_type(item) == 'Reservation']
    representative = _best_pricing_match(consumption_matches or matches)
    rows_by_sku: dict[str, dict[str, Any]] = {}

    def ensure_row(item: dict[str, Any]) -> dict[str, Any]:
        sku_key = _vm_sku_key(item)
        row = rows_by_sku.get(sku_key)
        if row is not None:
            return row
        row = {
            'key': sku_key,
            'sku': _vm_sku_label(item),
            'offers': {},
        }
        rows_by_sku[sku_key] = row
        return row

    consumption_by_sku: dict[str, list[dict[str, Any]]] = {}
    for item in consumption_matches:
        consumption_by_sku.setdefault(_vm_sku_key(item), []).append(item)

    for sku_key, sku_items in consumption_by_sku.items():
        paygo = _preferred_vm_consumption_match(sku_items)
        if not paygo:
            continue
        row = ensure_row(paygo)
        row['offers']['paygo'] = _compact_pricing_overlay_item({**paygo, 'offerLabel': 'Pay as you go'})

        for term in ('1 Year', '3 Years'):
            source_entry = next((entry for entry in _savings_plan_entries(paygo, side='source') if str(entry.get('term') or '').strip().lower() == term.lower()), None)
            target_entry = next((entry for entry in _savings_plan_entries(paygo, side='target') if str(entry.get('term') or '').strip().lower() == term.lower()), None)
            savings_item = _build_savings_plan_item(paygo, source_entry=source_entry, target_entry=target_entry, term=term, source_region=source_region, target_region=target_region)
            compact_savings = _compact_pricing_overlay_item(savings_item)
            if compact_savings:
                row['offers'][f'savings-plan-{_vm_term_key(term)}'] = compact_savings

    reservation_by_sku_term: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for item in reservation_matches:
        reservation_by_sku_term.setdefault((_vm_sku_key(item), _pricing_term(item).lower()), []).append(item)

    for term in ('1 Year', '3 Years'):
        term_key = term.lower()
        for (sku_key, reservation_term), sku_items in reservation_by_sku_term.items():
            if reservation_term != term_key:
                continue
            reservation_item = _best_pricing_match(sku_items)
            if not reservation_item:
                continue
            row = ensure_row(reservation_item)
            compact_reservation = _compact_pricing_overlay_item({**reservation_item, 'offerLabel': f'Reserved instance {term.lower()}'})
            if compact_reservation:
                row['offers'][f'reserved-{_vm_term_key(term)}'] = compact_reservation

    rows = sorted(
        [row for row in rows_by_sku.values() if row.get('offers')],
        key=lambda row: _normalize_lookup_value(str(row.get('sku') or '')),
    )
    models = _vm_pricing_models(rows)
    groups: list[dict[str, Any]] = []
    for model in models:
        group_items = [
            offer
            for row in rows
            for offer in [dict((row.get('offers') or {}).get(str(model.get('key') or '')) or {})]
            if offer
        ]
        group = _pricing_group(str(model.get('title') or model.get('key') or ''), str(model.get('key') or ''), group_items)
        if group:
            groups.append(group)

    return {
        'kind': 'vm',
        'summary': _compact_inline_pricing(representative),
        'groups': groups,
        'models': models,
        'rows': rows,
        'rowCount': len(rows),
        'offerCount': sum(int(group.get('count', 0)) for group in groups),
        'matchedItemCount': len(matches),
    }


def _disk_pricing_group(value: str) -> tuple[str, str]:
    normalized = str(value or '').lower()
    if 'throughput' in normalized or 'mbps' in normalized:
        return ('throughput', 'Throughput')
    if 'iops' in normalized:
        return ('iops', 'IOPS')
    if 'operation' in normalized or 'transaction' in normalized:
        return ('operations', 'Operations')
    if 'mount' in normalized:
        return ('mount', 'Mounts')
    if any(token in normalized for token in ('disk', 'storage', 'provisioned', 'capacity', 'lrs', 'zrs', 'ssd', 'hdd')):
        return ('storage', 'Storage')
    return ('other', 'Other meters')


def _disk_sku_aliases(row_sku: str, base_sku: str) -> set[str]:
    normalized = _normalize_lookup_value(base_sku)
    aliases = {normalized} if normalized else set()
    aliases.update(
        _normalize_lookup_value(value)
        for value in _extract_parenthetical_values(row_sku or '')
        if len(_normalize_lookup_value(value)) > 1
    )

    aliases.discard('')
    if normalized == 'premiumv2lrs':
        aliases.update({'premiumv2', 'premiumssdv2', 'premiumssdv2lrs'})
    return aliases


def _disk_item_matches_sku(row_sku: str, base_sku: str, item: dict[str, Any]) -> bool:
    aliases = _disk_sku_aliases(row_sku, base_sku)
    if not aliases:
        return False

    parenthetical_values = [value.strip() for value in _extract_parenthetical_values(row_sku or '') if str(value or '').strip()]

    arm_sku_candidates = {
        _normalize_lookup_value(item.get('armSkuName')),
        _normalize_lookup_value(item.get('sourceArmSkuName')),
        _normalize_lookup_value(item.get('targetArmSkuName')),
        _normalize_lookup_value(item.get('skuName')),
    }
    arm_sku_candidates.discard('')
    if aliases & arm_sku_candidates:
        return True

    text_values = [
        str(item.get('productName') or ''),
        str(item.get('meterName') or ''),
        str(item.get('label') or ''),
    ]
    raw_values = [
        str(item.get('armSkuName') or ''),
        str(item.get('sourceArmSkuName') or ''),
        str(item.get('targetArmSkuName') or ''),
        str(item.get('skuName') or ''),
        *text_values,
    ]
    normalized_text = {_normalize_lookup_value(value) for value in text_values if value}
    normalized_text.discard('')

    if 'premiumv2lrs' in aliases:
        premium_v2_product = any(
            'premiumssdv2' in _normalize_lookup_value(value)
            for value in (
                item.get('productName'),
                item.get('meterName'),
                item.get('label'),
                item.get('sourceMeterName'),
                item.get('targetMeterName'),
            )
            if value
        )
        if not premium_v2_product:
            return False

        premium_v2_sku_candidates = {
            _normalize_lookup_value(item.get('armSkuName')),
            _normalize_lookup_value(item.get('sourceArmSkuName')),
            _normalize_lookup_value(item.get('targetArmSkuName')),
            _normalize_lookup_value(item.get('skuName')),
        }
        premium_v2_sku_candidates.discard('')
        if premium_v2_sku_candidates and not (premium_v2_sku_candidates & {'premiumlrs', 'premiumv2lrs', 'premiumssdv2', 'premiumssdv2lrs'}):
            return False

        if any(token in text for token in ('confidentialcompute', 'encryption') for text in normalized_text):
            return False

        group_key, _ = _disk_pricing_group(' '.join(text_values))
        return group_key in {'storage', 'iops', 'throughput'}

    if parenthetical_values:
        return any(
            re.search(rf'(?<![A-Za-z0-9]){re.escape(alias)}(?![A-Za-z0-9])', value, re.IGNORECASE)
            for alias in parenthetical_values
            for value in raw_values
            if value
        )

    return any(
        any(alias == text or alias in text for alias in aliases)
        for text in normalized_text
    )


def _match_disk_sku_pricing(row_sku: str, comparison_items: list[dict[str, Any]]) -> dict[str, Any] | None:
    base_sku = re.sub(r'\s*\([^)]*\)\s*', ' ', row_sku or '').strip()
    if not _disk_sku_aliases(row_sku, base_sku):
        return None

    matches: list[dict[str, Any]] = []
    for item in comparison_items:
        if _disk_item_matches_sku(row_sku, base_sku, item):
            matches.append(item)

    if not matches:
        return None

    grouped_matches: dict[str, dict[str, Any]] = {}
    for item in matches:
        group_key, title = _disk_pricing_group(str(item.get('meterName') or item.get('label') or item.get('productName') or ''))
        group = grouped_matches.setdefault(group_key, {'key': group_key, 'title': title, 'items': []})
        group['items'].append(item)

    ordered_groups: list[dict[str, Any]] = []
    for group_key in ('storage', 'iops', 'throughput', 'operations', 'mount', 'other'):
        group = grouped_matches.get(group_key)
        if not group:
            continue
        compact_group = _pricing_group(str(group.get('title') or group_key.title()), group_key, list(group.get('items') or []))
        if compact_group:
            ordered_groups.append(compact_group)

    return {
        'kind': 'disk',
        'summary': _compact_inline_pricing(_best_pricing_match(matches)),
        'groups': ordered_groups,
        'matchedItemCount': len(matches),
    }


def _attach_vm_inline_pricing(details: dict[str, Any], pricing_comparison: dict[str, Any] | None) -> dict[str, Any]:
    comparison_items = list((pricing_comparison or {}).get('items') or [])
    if not comparison_items:
        return details

    enriched = dict(details)
    families = []
    matched_count = 0
    for family in list(details.get('families') or []):
        family_row = dict(family)
        pricing_detail = _match_vm_family_pricing(
            str(family_row.get('family') or ''),
            comparison_items,
            source_region=str(details.get('sourceRegion') or details.get('summary', {}).get('sourceRegion') or ''),
            target_region=str(details.get('targetRegion') or details.get('summary', {}).get('targetRegion') or ''),
        )
        if pricing_detail:
            family_row['pricing'] = pricing_detail.get('summary')
            family_row['pricingDetails'] = pricing_detail
            matched_count += 1
        families.append(family_row)
    enriched['families'] = families
    enriched['pricingMatchedRows'] = matched_count
    enriched['pricingMatchSummary'] = f'Inline retail pricing matched for {matched_count} of {len(families)} VM families.'
    return enriched


def _attach_disk_inline_pricing(details: dict[str, Any], pricing_comparison: dict[str, Any] | None) -> dict[str, Any]:
    comparison_items = list((pricing_comparison or {}).get('items') or [])
    if not comparison_items:
        return details

    enriched = dict(details)
    skus = []
    matched_count = 0
    for sku in list(details.get('skus') or []):
        sku_row = dict(sku)
        pricing_detail = _match_disk_sku_pricing(str(sku_row.get('sku') or ''), comparison_items)
        if pricing_detail:
            sku_row['pricing'] = pricing_detail.get('summary')
            sku_row['pricingDetails'] = pricing_detail
            matched_count += 1
        skus.append(sku_row)
    enriched['skus'] = skus
    enriched['pricingMatchedRows'] = matched_count
    enriched['pricingMatchSummary'] = f'Inline retail pricing matched for {matched_count} of {len(skus)} managed disk SKUs.'
    return enriched


def _disk_sku_key(sku: dict[str, Any]) -> str:
    size = str(sku.get('size') or '')
    name = str(sku.get('name') or '')
    return f'{name}:{size}' if size else name


def _disk_sku_label(sku: dict[str, Any]) -> str:
    name = str(sku.get('name') or '')
    size = str(sku.get('size') or '')
    if size and size.upper() != name.upper():
        return f'{name} ({size})'
    return name


def _disk_tier_name(sku: dict[str, Any]) -> str:
    tier = str(sku.get('tier') or '')
    if tier:
        return tier
    name = str(sku.get('name') or '').lower()
    if name.startswith('ultra'):
        return 'Ultra'
    if name.startswith('premiumv2'):
        return 'Premium v2'
    if name.startswith('premium'):
        return 'Premium'
    if name.startswith('standardssd'):
        return 'Standard SSD'
    if name.startswith('standard'):
        return 'Standard HDD'
    return 'Other'


def _build_disk_sku_details(
    *,
    source_region: str,
    target_region: str,
    source_entries: list[dict[str, Any]],
    target_entries: list[dict[str, Any]],
    allowed_names: set[str] | None = None,
    inventory_resource_count: int | None = None,
) -> dict[str, Any]:
    source_map = {
        _disk_sku_key(entry): entry
        for entry in source_entries
        if allowed_names is None or str(entry.get('name') or '') in allowed_names
    }
    target_map = {
        _disk_sku_key(entry): entry
        for entry in target_entries
        if allowed_names is None or str(entry.get('name') or '') in allowed_names
    }
    keys = sorted(set(source_map) | set(target_map))

    rows: list[dict[str, Any]] = []
    source_tiers: dict[str, int] = {}
    target_tiers: dict[str, int] = {}
    for key in keys:
        source_entry = source_map.get(key)
        target_entry = target_map.get(key)
        exemplar = source_entry or target_entry or {}
        tier_name = _disk_tier_name(exemplar)
        source_restricted = bool((source_entry or {}).get('restrictions') or [])
        target_restricted = bool((target_entry or {}).get('restrictions') or [])
        if source_entry:
            source_tiers[tier_name] = source_tiers.get(tier_name, 0) + 1
        if target_entry:
            target_tiers[tier_name] = target_tiers.get(tier_name, 0) + 1
        rows.append(
            {
                'sku': _disk_sku_label(exemplar),
                'tier': tier_name,
                'sourceAvailable': bool(source_entry),
                'targetAvailable': bool(target_entry),
                'sourceRestricted': source_restricted,
                'targetRestricted': target_restricted,
                'status': 'CONDITIONAL' if (source_entry or target_entry) and (source_restricted or target_restricted) else 'FULL_MATCH' if source_entry and target_entry else 'SOURCE_EXTENDED' if source_entry else 'TARGET_EXTENDED',
            }
        )

    tier_rows = [
        {
            'tier': tier,
            'sourceCount': source_tiers.get(tier, 0),
            'targetCount': target_tiers.get(tier, 0),
        }
        for tier in sorted(set(source_tiers) | set(target_tiers))
    ]
    summary_text = f'{len(rows)} managed disk SKU entries compared between {source_region} and {target_region}.'
    if inventory_resource_count is not None:
        summary_text = f'{inventory_resource_count} source disk resource(s) detected. {summary_text}'

    return {
        'layout': 'sku-breakdown',
        'summary': {
            'sourceCount': len(source_map),
            'targetCount': len(target_map),
            'sharedCount': sum(1 for row in rows if row['sourceAvailable'] and row['targetAvailable']),
            'sourceOnlyCount': sum(1 for row in rows if row['sourceAvailable'] and not row['targetAvailable']),
            'targetOnlyCount': sum(1 for row in rows if row['targetAvailable'] and not row['sourceAvailable']),
        },
        'summaryText': summary_text,
        'metricCards': _metric_cards(
            ('Source disk SKUs', len(source_map)),
            ('Shared disk SKUs', sum(1 for row in rows if row['sourceAvailable'] and row['targetAvailable'])),
            ('SKU differences', sum(1 for row in rows if row['sourceAvailable'] != row['targetAvailable'])),
            ('Target disk SKUs', len(target_map)),
        ),
        'skus': rows,
        'tierSummary': tier_rows,
    }


def _storage_entries_for_region(entries: list[dict[str, Any]], region_normalized: str) -> list[dict[str, Any]]:
    return [
        entry
        for entry in entries
        if region_normalized in entry.get('locations', []) and not (entry.get('restrictions') or [])
    ]


def _storage_capability_status(entries: list[dict[str, Any]], predicate: Any) -> str:
    return 'available' if any(predicate(entry, _capability_values(entry)) for entry in entries) else 'unavailable'


_ZONE_DEPENDENT_SKU_RE = re.compile(r'(?i)(^|_)(g?z|rag?z)rs($|_)')


def _storage_zone_mode(entries: list[dict[str, Any]], *, region_has_zones: str = 'unknown') -> dict[str, str]:
    has_zrs = any('_zrs' in str(entry.get('name', '')).lower() for entry in entries)
    if has_zrs:
        if region_has_zones == 'false':
            return {'mode': 'zone-redundant-unavailable', 'label': 'Zone-redundant SKUs listed but region lacks AZs', 'notes': 'Azure returns ZRS/GZRS SKUs for this region but it has no availability zones, so zone-redundant replication is not functionally available.'}
        return {'mode': 'zone-redundant', 'label': 'Zone-redundant support', 'notes': 'At least one storage redundancy option includes zone-redundant replication.'}
    return {'mode': 'regional', 'label': 'Regional service', 'notes': 'No explicit zone-redundant storage SKU was identified in the available SKU set.'}


def _count_zone_dependent_skus(entries: list[dict[str, Any]]) -> int:
    """Count SKUs whose name implies zone-redundancy (ZRS, GZRS, RAGZRS)."""
    return sum(1 for e in entries if _ZONE_DEPENDENT_SKU_RE.search(str(e.get('name', ''))))


def _build_storage_capability_details(
    *,
    source_region: str,
    target_region: str,
    source_entries: list[dict[str, Any]],
    target_entries: list[dict[str, Any]],
    inventory_resource_count: int | None = None,
    source_region_has_zones: str = 'unknown',
    target_region_has_zones: str = 'unknown',
) -> dict[str, Any]:
    capability_specs = [
        ('zone_redundant_replication', 'Zone-redundant replication', 'high', 'Key migration signal for storage resiliency.', lambda entry, _: '_zrs' in str(entry.get('name', '')).lower()),
        ('premium_blob_storage', 'Premium blob storage', 'medium', 'Useful for latency-sensitive applications.', lambda entry, _: str(entry.get('tier', '')).lower() == 'premium' and str(entry.get('kind', '')).lower() == 'blockblobstorage'),
        ('premium_azure_files', 'Premium Azure Files', 'medium', 'Important for lift-and-shift file workloads.', lambda entry, _: str(entry.get('tier', '')).lower() == 'premium' and str(entry.get('kind', '')).lower() == 'filestorage'),
        ('data_lake_storage_gen2', 'Data Lake Storage Gen2', 'high', 'Important for lakehouse and analytics landing zones.', lambda _, capabilities: _truthy(capabilities.get('supportshierarchicalnamespace'))),
        ('sftp_endpoint_support', 'SFTP endpoint support', 'medium', 'Frequently required for partner and migration integrations.', lambda _, capabilities: _truthy(capabilities.get('supportssftp'))),
        ('nfs_3_0_support', 'NFS 3.0 support', 'medium', 'Useful for Linux and analytics workloads.', lambda _, capabilities: _truthy(capabilities.get('supportsnfsv3')) or _truthy(capabilities.get('supportsnfsshare'))),
        ('large_file_shares', 'Large file shares', 'medium', 'Important for enterprise file migration scenarios.', lambda _, capabilities: _truthy(capabilities.get('supportslargefileshares'))),
    ]

    capabilities: list[dict[str, Any]] = []
    different_count = 0
    matched_count = 0
    for key, label, importance, note, predicate in capability_specs:
        source_status = _storage_capability_status(source_entries, predicate)
        target_status = _storage_capability_status(target_entries, predicate)
        # For zone_redundant_replication, override status if region has no AZs
        if key == 'zone_redundant_replication':
            if source_status == 'available' and source_region_has_zones == 'false':
                source_status = 'not-applicable'
                note = 'ZRS/GZRS SKUs are listed by Azure but the region has no availability zones.'
            if target_status == 'available' and target_region_has_zones == 'false':
                target_status = 'not-applicable'
                note = 'ZRS/GZRS SKUs are listed by Azure but the region has no availability zones.'
        if source_status == target_status:
            matched_count += 1
        else:
            different_count += 1
        capabilities.append(
            {
                'key': key,
                'label': label,
                'importance': importance,
                'sourceStatus': source_status,
                'targetStatus': target_status,
                'sourceNotes': note,
                'targetNotes': note,
            }
        )

    # Compute zone-dependent SKU counts and effective counts
    source_zone_dep_count = _count_zone_dependent_skus(source_entries)
    target_zone_dep_count = _count_zone_dependent_skus(target_entries)
    source_effective = len(source_entries) - (source_zone_dep_count if source_region_has_zones == 'false' else 0)
    target_effective = len(target_entries) - (target_zone_dep_count if target_region_has_zones == 'false' else 0)

    summary_text = 'Storage account platform spanning blobs, files, queues, tables, and redundancy models with strong region-selection impact.'
    if inventory_resource_count is not None:
        summary_text = f'{inventory_resource_count} source storage account resource(s) detected. {summary_text}'

    return {
        'layout': 'capability-matrix',
        'providerNamespace': 'microsoft.storage',
        'providerLabel': 'Microsoft.Storage/storageAccounts',
        'summary': {
            'sourceCount': len(source_entries),
            'targetCount': len(target_entries),
            'sourceEffectiveCount': source_effective,
            'targetEffectiveCount': target_effective,
            'sourceZoneDependentSkuCount': source_zone_dep_count,
            'targetZoneDependentSkuCount': target_zone_dep_count,
            'sharedCount': matched_count,
            'sourceOnlyCount': 0,
            'targetOnlyCount': 0,
            'capabilityCount': len(capabilities),
            'differentCapabilityCount': different_count,
            'matchedCapabilityCount': matched_count,
        },
        'metricCards': _metric_cards(
            ('Source storage SKUs', len(source_entries)),
            ('Source effective SKUs', source_effective),
            ('Matched curated capabilities', matched_count),
            ('Capability differences', different_count),
            ('Target storage SKUs', len(target_entries)),
            ('Target effective SKUs', target_effective),
        ),
        'curated': {
            'matched': True,
            'serviceKey': 'azure-storage',
            'displayName': 'Azure Storage',
            'family': 'storage',
            'summary': summary_text,
            'capabilities': capabilities,
            'expandedCapabilities': [
                section
                for section in [
                    _build_storage_capability_expansion(
                        source_region=source_region,
                        target_region=target_region,
                        source_entries=source_entries,
                        target_entries=target_entries,
                    ),
                ]
                if section is not None
            ],
            'sourceRegion': {
                'name': source_region,
                'serviceAvailable': bool(source_entries),
                'regionNote': '',
                'zoneSupport': _storage_zone_mode(source_entries, region_has_zones=source_region_has_zones),
                'zoneDependentSkuCount': source_zone_dep_count,
                'effectiveSkuCount': source_effective,
            },
            'targetRegion': {
                'name': target_region,
                'serviceAvailable': bool(target_entries),
                'regionNote': '',
                'zoneSupport': _storage_zone_mode(target_entries, region_has_zones=target_region_has_zones),
                'zoneDependentSkuCount': target_zone_dep_count,
                'effectiveSkuCount': target_effective,
            },
            'summaryStats': {
                'capabilityCount': len(capabilities),
                'differentCapabilityCount': different_count,
                'matchedCapabilityCount': matched_count,
            },
        },
    }


class AzureQueryClient:
    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or load_settings()
        self._credential = DefaultAzureCredential(authority=self._settings.credential_authority)
        self._provider_locations_cache: dict[str, dict[str, set[str]]] = {}
        self._region_zone_support_cache: dict[str, dict[str, str]] = {}
        self._compute_sku_entries_cache: dict[tuple[str, str], list[dict[str, Any]]] = {}
        self._compute_sku_cache: dict[tuple[str, str], dict[str, dict[str, Any]]] = {}
        self._storage_sku_entries_cache: dict[str, list[dict[str, Any]]] = {}
        self._storage_sku_cache: dict[str, dict[str, dict[str, Any]]] = {}

    def _access_token(self) -> str:
        return self._credential.get_token(self._settings.management_scope).token

    def _request_json(self, method: str, url: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        payload = None if body is None else json.dumps(body).encode('utf-8')
        headers = {
            'Authorization': f'Bearer {self._access_token()}',
            'Accept': 'application/json',
        }
        if body is not None:
            headers['Content-Type'] = 'application/json'

        response = request.urlopen(request.Request(url, data=payload, headers=headers, method=method), timeout=60)
        return json.loads(response.read().decode('utf-8'))

    def query_inventory(self, subscription_id: str, source_region: str) -> list[dict[str, Any]]:
        url = self._settings.management_url(f'/providers/Microsoft.ResourceGraph/resources?api-version={RESOURCE_GRAPH_API_VERSION}')
        query = f"""
Resources
| where subscriptionId =~ '{subscription_id}'
| where tolower(location) == tolower('{source_region}')
| project id, name, type, location, subscriptionId, resourceGroup,
                    skuName=tostring(sku.name),
          vmSize=tostring(properties.hardwareProfile.vmSize),
                    kind
""".strip()

        items: list[dict[str, Any]] = []
        skip_token: str | None = None

        while True:
            options: dict[str, Any] = {
                '$top': 1000,
                'resultFormat': 'objectArray',
            }
            if skip_token:
                options['$skipToken'] = skip_token

            response = self._request_json(
                'POST',
                url,
                {
                    'subscriptions': [subscription_id],
                    'query': query,
                    'options': options,
                },
            )
            items.extend(response.get('data', []))
            skip_token = response.get('$skipToken') or response.get('skipToken')
            if not skip_token:
                break

        return items

    def provider_locations(self, subscription_id: str) -> dict[str, dict[str, set[str]]]:
        cached = self._provider_locations_cache.get(subscription_id)
        if cached is not None:
            return cached

        url = self._settings.management_url(
            f'/subscriptions/{subscription_id}/providers?api-version={PROVIDERS_API_VERSION}&$expand=resourceTypes/locations'
        )
        response = self._request_json('GET', url)

        providers: dict[str, dict[str, set[str]]] = {}
        for provider in response.get('value', []):
            namespace = str(provider.get('namespace', '')).lower()
            resource_types: dict[str, set[str]] = {}
            for resource_type in provider.get('resourceTypes', []):
                resource_name = str(resource_type.get('resourceType', '')).lower()
                resource_types[resource_name] = {
                    _normalize_region_name(str(location))
                    for location in resource_type.get('locations', [])
                }
            providers[namespace] = resource_types

        self._provider_locations_cache[subscription_id] = providers
        return providers

    def region_zone_support(self, subscription_id: str) -> dict[str, str]:
        cached = self._region_zone_support_cache.get(subscription_id)
        if cached is not None:
            return cached

        url = self._settings.management_url(
            f'/subscriptions/{subscription_id}/locations?api-version={LOCATIONS_API_VERSION}'
        )
        response = self._request_json('GET', url)

        region_support: dict[str, str] = {}
        for item in response.get('value', []):
            region_name = _normalize_region_name(str(item.get('name', '')))
            if not region_name:
                continue
            zone_mappings = item.get('availabilityZoneMappings')
            if isinstance(zone_mappings, list):
                region_support[region_name] = 'true' if zone_mappings else 'false'
            elif zone_mappings is None:
                region_support[region_name] = 'false'
            else:
                region_support[region_name] = 'unknown'

        self._region_zone_support_cache[subscription_id] = region_support
        return region_support

    def compute_sku_entries(self, subscription_id: str, target_region: str) -> list[dict[str, Any]]:
        cache_key = (subscription_id, target_region.lower())
        cached = self._compute_sku_entries_cache.get(cache_key)
        if cached is not None:
            return cached

        filter_value = parse.quote(f"location eq '{target_region}'", safe="'$")
        url = self._settings.management_url(
            f'/subscriptions/{subscription_id}/providers/Microsoft.Compute/skus?api-version={COMPUTE_SKUS_API_VERSION}&$filter={filter_value}'
        )
        response = self._request_json('GET', url)

        skus = response.get('value', [])
        for item in skus:
            item['locations'] = [_normalize_region_name(str(location)) for location in item.get('locations', [])]

        self._compute_sku_entries_cache[cache_key] = skus
        return skus

    def compute_skus(self, subscription_id: str, target_region: str) -> dict[str, dict[str, Any]]:
        cache_key = (subscription_id, target_region.lower())
        cached = self._compute_sku_cache.get(cache_key)
        if cached is not None:
            return cached

        skus = {
            str(item.get('name', '')).lower(): item
            for item in self.compute_sku_entries(subscription_id, target_region)
            if str(item.get('resourceType', '')).lower() == 'virtualmachines'
        }
        self._compute_sku_cache[cache_key] = skus
        return skus

    def disk_skus(self, subscription_id: str, target_region: str) -> list[dict[str, Any]]:
        return [
            item
            for item in self.compute_sku_entries(subscription_id, target_region)
            if str(item.get('resourceType', '')).lower() == 'disks'
        ]

    def storage_sku_entries(self, subscription_id: str) -> list[dict[str, Any]]:
        cached = self._storage_sku_entries_cache.get(subscription_id)
        if cached is not None:
            return cached

        url = self._settings.management_url(
            f'/subscriptions/{subscription_id}/providers/Microsoft.Storage/skus?api-version={STORAGE_SKUS_API_VERSION}'
        )
        response = self._request_json('GET', url)

        entries = response.get('value', [])
        for item in entries:
            item['locations'] = [_normalize_region_name(str(location)) for location in item.get('locations', [])]
        self._storage_sku_entries_cache[subscription_id] = entries
        return entries

    def storage_skus(self, subscription_id: str) -> dict[str, dict[str, Any]]:
        cached = self._storage_sku_cache.get(subscription_id)
        if cached is not None:
            return cached

        skus = {str(item.get('name', '')).lower(): item for item in self.storage_sku_entries(subscription_id)}
        self._storage_sku_cache[subscription_id] = skus
        return skus


def summarize_inventory(inventory: list[dict[str, Any]]) -> list[InventorySummary]:
    grouped: dict[tuple[str, str], InventorySummary] = {}
    for item in inventory:
        provider = str(item.get('type', ''))
        sku = str(item.get('vmSize') or item.get('skuName') or item.get('sku') or '')
        key = (provider.lower(), sku.lower())
        current = grouped.get(key)
        if current is None:
            grouped[key] = InventorySummary(
                service=_service_name(provider, sku),
                provider=provider,
                service_family=_service_family(provider),
                sku=sku,
                count=1,
            )
            continue

        grouped[key] = InventorySummary(
            service=current.service,
            provider=current.provider,
            service_family=current.service_family,
            sku=current.sku,
            count=current.count + 1,
        )

    return sorted(grouped.values(), key=lambda item: (item.service_family, item.service, item.sku))


def _attach_pricing_data(
    details_json: str,
    pricing_summary: dict[str, Any] | None,
    pricing_comparison: dict[str, Any] | None = None,
    service_identity: dict[str, Any] | None = None,
) -> str:
    if not pricing_summary and not pricing_comparison and not service_identity:
        return details_json

    try:
        payload = json.loads(details_json) if details_json else {}
    except json.JSONDecodeError:
        return details_json

    if not isinstance(payload, dict):
        return details_json

    if pricing_summary:
        payload['pricingSummary'] = pricing_summary
    if pricing_comparison:
        payload['pricingComparison'] = pricing_comparison
    if service_identity:
        payload['serviceIdentity'] = service_identity
    return json.dumps(payload, separators=(',', ':'))


def _pricing_note(pricing_summary: dict[str, Any] | None) -> str:
    if not pricing_summary:
        return ''

    retail_price = pricing_summary.get('retailPrice')
    currency_code = pricing_summary.get('currencyCode')
    unit = pricing_summary.get('unitOfMeasure')
    meter_name = pricing_summary.get('meterName')
    if retail_price in (None, ''):
        return ''

    fragments = [f'Retail price seed: {retail_price} {currency_code or ""}'.strip()]
    if unit:
        fragments.append(f'per {unit}')
    if meter_name:
        fragments.append(f'via {meter_name}')
    return ' '.join(fragments)


def compare_inventory(
    client: AzureQueryClient,
    *,
    subscription_id: str,
    source_region: str,
    target_region: str,
    pricing_client: Any | None = None,
) -> list[dict[str, str]]:
    inventory = client.query_inventory(subscription_id, source_region)
    grouped = summarize_inventory(inventory)
    provider_locations = client.provider_locations(subscription_id)
    region_zone_support = client.region_zone_support(subscription_id)
    source_compute_entries = client.compute_sku_entries(subscription_id, source_region)
    target_compute_entries = client.compute_sku_entries(subscription_id, target_region)
    compute_skus = client.compute_skus(subscription_id, target_region)
    source_disk_skus = client.disk_skus(subscription_id, source_region)
    target_disk_skus = client.disk_skus(subscription_id, target_region)
    storage_skus = client.storage_skus(subscription_id)
    storage_entries = client.storage_sku_entries(subscription_id)

    results: list[dict[str, str]] = []
    target_region_normalized = _normalize_region_name(target_region)
    source_region_normalized = _normalize_region_name(source_region)
    special_handlers_seen: set[str] = set()

    for item in grouped:
        availability = 'CONDITIONAL'
        notes = f'{item.count} source resource(s) discovered.'
        provider_key = item.provider.lower()

        if provider_key in {'microsoft.compute/virtualmachines', 'microsoft.compute/disks', 'microsoft.storage/storageaccounts'}:
            if provider_key in special_handlers_seen:
                continue
            special_handlers_seen.add(provider_key)

            if provider_key == 'microsoft.compute/virtualmachines':
                source_inventory_vms = [resource for resource in inventory if str(resource.get('type', '')).lower() == provider_key]
                source_family_filter = _family_filter_for_inventory(
                    source_inventory_vms,
                    _available_compute_entries(source_compute_entries, 'virtualmachines', include_restricted=True),
                )
                details = _build_vm_family_details(
                    source_region=source_region,
                    target_region=target_region,
                    source_entries=_available_compute_entries(source_compute_entries, 'virtualmachines', include_restricted=True),
                    target_entries=_available_compute_entries(target_compute_entries, 'virtualmachines', include_restricted=True),
                    family_filter=source_family_filter or None,
                    inventory_resource_count=len(source_inventory_vms),
                )
                results.append(
                    {
                        'row_key': _slugify(f'microsoft-compute-virtualmachines-{source_region}-{target_region}-inventory'),
                        'provider': 'Microsoft.Compute/virtualMachines',
                        'source_region': source_region,
                        'target_region': target_region,
                        'availability': _status_from_counts(details['summary']['sourceCount'], details['summary']['targetCount']),
                        'notes': details['summaryText'],
                        'details_json': _attach_pricing_data(
                            json.dumps(details, separators=(',', ':')),
                            None,
                            None,
                            _pricing_identity(
                                'Microsoft.Compute/virtualMachines',
                                service_name='Virtual Machines',
                                resource_types={'virtualmachines'},
                            ),
                        ),
                        **_authoritative_row_identity(
                            _pricing_identity(
                                'Microsoft.Compute/virtualMachines',
                                service_name='Virtual Machines',
                                resource_types={'virtualmachines'},
                            ),
                            service_name='Virtual Machines',
                            service_family='compute',
                        ),
                    }
                )
                continue

            if provider_key == 'microsoft.compute/disks':
                source_inventory_disks = [resource for resource in inventory if str(resource.get('type', '')).lower() == provider_key]
                disk_name_filter = {str(resource.get('sku') or resource.get('diskSku') or '') for resource in source_inventory_disks if str(resource.get('sku') or resource.get('diskSku') or '')}
                details = _build_disk_sku_details(
                    source_region=source_region,
                    target_region=target_region,
                    source_entries=_available_compute_entries(source_disk_skus, 'disks', include_restricted=True),
                    target_entries=_available_compute_entries(target_disk_skus, 'disks', include_restricted=True),
                    allowed_names=disk_name_filter or None,
                    inventory_resource_count=len(source_inventory_disks),
                )
                results.append(
                    {
                        'row_key': _slugify(f'microsoft-compute-disks-{source_region}-{target_region}-inventory'),
                        'provider': 'Microsoft.Compute/disks',
                        'source_region': source_region,
                        'target_region': target_region,
                        'availability': _status_from_counts(details['summary']['sourceCount'], details['summary']['targetCount']),
                        'notes': details['summaryText'],
                        'details_json': _attach_pricing_data(
                            json.dumps(details, separators=(',', ':')),
                            None,
                            None,
                            _pricing_identity(
                                'Microsoft.Compute/disks',
                                service_name='Managed Disks',
                                resource_types={'disks'},
                            ),
                        ),
                        **_authoritative_row_identity(
                            _pricing_identity(
                                'Microsoft.Compute/disks',
                                service_name='Managed Disks',
                                resource_types={'disks'},
                            ),
                            service_name='Managed Disks',
                            service_family='storage',
                        ),
                    }
                )
                continue

            source_inventory_storage = [resource for resource in inventory if str(resource.get('type', '')).lower() == provider_key]
            details = _build_storage_capability_details(
                source_region=source_region,
                target_region=target_region,
                source_entries=_storage_entries_for_region(storage_entries, source_region_normalized),
                target_entries=_storage_entries_for_region(storage_entries, target_region_normalized),
                inventory_resource_count=len(source_inventory_storage),
                source_region_has_zones=region_zone_support.get(source_region_normalized, 'unknown'),
                target_region_has_zones=region_zone_support.get(target_region_normalized, 'unknown'),
            )
            results.append(
                {
                    'row_key': _slugify(f'microsoft-storage-storageaccounts-{source_region}-{target_region}-inventory'),
                    'provider': 'Microsoft.Storage/storageAccounts',
                    'source_region': source_region,
                    'target_region': target_region,
                    'availability': _status_from_counts(details['summary']['sourceCount'], details['summary']['targetCount']),
                    'notes': details['curated']['summary'],
                    'details_json': _attach_pricing_data(
                        json.dumps(details, separators=(',', ':')),
                        None,
                        None,
                        _pricing_identity(
                            'Microsoft.Storage/storageAccounts',
                            service_name='Azure Storage',
                            resource_types={'storageaccounts'},
                        ),
                    ),
                    **_authoritative_row_identity(
                        _pricing_identity(
                            'Microsoft.Storage/storageAccounts',
                            service_name='Azure Storage',
                            resource_types={'storageaccounts'},
                        ),
                        service_name='Azure Storage',
                        service_family='storage',
                    ),
                }
            )
            continue

        namespace, _, resource_suffix = provider_key.partition('/')
        resource_map = provider_locations.get(namespace, {})
        target_types = sorted(
            resource_type
            for resource_type, locations in resource_map.items()
            if target_region_normalized in locations
        )
        source_types = [resource_suffix] if resource_suffix else []

        if provider_key == 'microsoft.compute/virtualmachines' and item.sku:
            sku_entry = compute_skus.get(item.sku.lower())
            if sku_entry is None:
                availability = 'UNAVAILABLE'
                notes = f'{notes} VM size {item.sku} is not returned for {target_region}.'
            else:
                restrictions = sku_entry.get('restrictions') or []
                if restrictions:
                    availability = 'CONDITIONAL'
                    notes = f'{notes} VM size {item.sku} has restrictions in {target_region}.'
                else:
                    availability = 'AVAILABLE'
                    notes = f'{notes} VM size {item.sku} is available in {target_region}.'
        elif provider_key == 'microsoft.storage/storageaccounts' and item.sku:
            sku_entry = storage_skus.get(item.sku.lower())
            locations = set((sku_entry or {}).get('locations', []))
            restrictions = (sku_entry or {}).get('restrictions') or []
            if sku_entry and target_region_normalized in locations and not restrictions:
                availability = 'AVAILABLE'
                notes = f'{notes} Storage SKU {item.sku} is available in {target_region}.'
            elif sku_entry and target_region_normalized in locations:
                availability = 'CONDITIONAL'
                notes = f'{notes} Storage SKU {item.sku} is present in {target_region} with restrictions.'
            else:
                availability = 'UNAVAILABLE'
                notes = f'{notes} Storage SKU {item.sku} is not present in {target_region}.'
        else:
            locations = resource_map.get(resource_suffix)
            if locations is None:
                availability = 'CONDITIONAL'
                notes = f'{notes} Provider metadata does not expose locations for {item.provider}.'
            elif target_region_normalized in locations:
                availability = 'AVAILABLE'
                notes = f'{notes} Provider metadata includes {target_region}.'
            else:
                availability = 'UNAVAILABLE'
                notes = f'{notes} Provider metadata does not include {target_region}.'

        shared_types = sorted(set(source_types) & set(target_types))
        source_only_types = sorted(set(source_types) - set(target_types))
        target_only_types = sorted(set(target_types) - set(source_types))
        curated = (
            build_curated_regional_details(
                namespace,
                source_region,
                target_region,
                set(source_types),
                set(target_types),
                source_region_has_zones=region_zone_support.get(source_region_normalized, 'unknown'),
                target_region_has_zones=region_zone_support.get(target_region_normalized, 'unknown'),
            )
            if namespace else None
        )
        if curated and curated.get('sourceRegion', {}).get('serviceAvailable') and curated.get('targetRegion', {}).get('serviceAvailable'):
            curated = _augment_curated_details(
                curated,
                source_region=source_region,
                target_region=target_region,
                source_types=source_types,
                target_types=target_types,
                shared_types=shared_types,
                source_only_types=source_only_types,
                target_only_types=target_only_types,
            )

        if curated and (not curated.get('sourceRegion', {}).get('serviceAvailable') or not curated.get('targetRegion', {}).get('serviceAvailable')):
            details_payload = _build_service_availability_details(
                curated,
                source_region=source_region,
                target_region=target_region,
                source_count=len(source_types),
                target_count=len(target_types),
            )
            details_json = json.dumps(details_payload, separators=(',', ':'))
        elif curated:
            details_json = json.dumps(
                {
                    'layout': 'capability-matrix',
                    'providerNamespace': namespace,
                    'providerLabel': item.provider,
                    'curated': curated,
                    'summary': {
                        'sourceCount': len(source_types),
                        'targetCount': len(target_types),
                        'sharedCount': len(shared_types),
                        'sourceOnlyCount': len(source_only_types),
                        'targetOnlyCount': len(target_only_types),
                        'capabilityCount': curated.get('summaryStats', {}).get('capabilityCount', 0),
                        'differentCapabilityCount': curated.get('summaryStats', {}).get('differentCapabilityCount', 0),
                        'matchedCapabilityCount': curated.get('summaryStats', {}).get('matchedCapabilityCount', 0),
                    },
                    'rawSections': [
                        _build_detail_section(f'Deployed in {source_region}', source_types),
                        _build_detail_section('Shared in both regions', shared_types),
                        _build_detail_section(f'Only in {target_region}', target_only_types),
                    ],
                },
                separators=(',', ':'),
            )
        else:
            details_json = json.dumps(
                {
                    'layout': 'raw-capability-overlap',
                    'providerNamespace': namespace,
                    'providerLabel': item.provider,
                    'summary': {
                        'sourceCount': len(source_types),
                        'targetCount': len(target_types),
                        'sharedCount': len(shared_types),
                        'sourceOnlyCount': len(source_only_types),
                        'targetOnlyCount': len(target_only_types),
                    },
                    'sections': [
                        _build_detail_section(f'Deployed in {source_region}', source_types),
                        _build_detail_section('Shared in both regions', shared_types),
                        _build_detail_section(f'Only in {target_region}', target_only_types),
                    ],
                },
                separators=(',', ':'),
            )

        pricing_identity = _pricing_identity(item.provider, service_name=item.service)
        pricing_summary = (
            pricing_client.retail_summary(
                provider=item.provider,
                service=item.service,
                sku=item.sku,
                region=source_region,
                pricing_identity=pricing_identity,
            )
            if pricing_client is not None and item.sku
            else None
        )
        pricing_comparison = (
            pricing_client.retail_comparison(
                provider=item.provider,
                service=item.service,
                sku=item.sku,
                source_region=source_region,
                target_region=target_region,
                pricing_identity=pricing_identity,
            )
            if pricing_client is not None and item.sku
            else None
        )
        results.append(
            {
                'row_key': _slugify(f'{item.provider}-{item.sku or "default"}-{source_region}-{target_region}'),
                'provider': item.provider,
                'source_region': source_region,
                'target_region': target_region,
                'availability': availability,
                'notes': f'{notes} {_pricing_note(pricing_summary)}'.strip() if pricing_summary else notes,
                'details_json': (
                    _attach_pricing_data(
                        details_json,
                        pricing_summary,
                        pricing_comparison,
                        pricing_identity,
                    )
                    if pricing_client is not None and item.sku
                    else _attach_pricing_data(details_json, None, None, pricing_identity)
                ),
                **_authoritative_row_identity(
                    pricing_identity,
                    service_name=item.service,
                    service_family=item.service_family,
                ),
            }
        )

    return results


def compare_regions(
    client: AzureQueryClient,
    *,
    subscription_id: str,
    source_region: str,
    target_region: str,
    pricing_client: Any | None = None,
) -> list[dict[str, str]]:
    provider_locations = client.provider_locations(subscription_id)
    region_zone_support = client.region_zone_support(subscription_id)
    source_compute_entries = client.compute_sku_entries(subscription_id, source_region)
    target_compute_entries = client.compute_sku_entries(subscription_id, target_region)
    source_disk_skus = client.disk_skus(subscription_id, source_region)
    target_disk_skus = client.disk_skus(subscription_id, target_region)
    storage_entries = client.storage_sku_entries(subscription_id)
    source_region_normalized = _normalize_region_name(source_region)
    target_region_normalized = _normalize_region_name(target_region)

    results: list[dict[str, str]] = []
    namespaces = sorted(
        namespace
        for namespace in provider_locations
        if namespace in CURATED_REGIONAL_PROVIDERS and namespace not in {'microsoft.compute', 'microsoft.storage'}
    )

    namespace_pricing_entries: dict[str, dict[str, Any]] = {}
    if pricing_client is not None:
        for namespace in namespaces:
            pricing_identity = _pricing_identity(
                namespace,
                service_name=_provider_display_name(namespace),
                resource_types=set(provider_locations.get(namespace, {}).keys()),
            )
            namespace_pricing_entries[namespace] = {
                'provider': namespace,
                'service': str(pricing_identity.get('displayName') or _provider_display_name(namespace)),
                'sku': '',
                'pricing_identity': pricing_identity,
            }

        regional_prefetch_entries = [
            *namespace_pricing_entries.values(),
            {
                'provider': 'Microsoft.Compute/virtualMachines',
                'service': 'Virtual Machines',
                'sku': '',
                'pricing_identity': _pricing_identity(
                    'Microsoft.Compute/virtualMachines',
                    service_name='Virtual Machines',
                    resource_types={'virtualmachines'},
                ),
            },
            {
                'provider': 'Microsoft.Compute/disks',
                'service': 'Managed Disks',
                'sku': '',
                'pricing_identity': _pricing_identity(
                    'Microsoft.Compute/disks',
                    service_name='Managed Disks',
                    resource_types={'disks'},
                ),
            },
            {
                'provider': 'Microsoft.Storage/storageAccounts',
                'service': 'Azure Storage',
                'sku': '',
                'pricing_identity': _pricing_identity(
                    'Microsoft.Storage/storageAccounts',
                    service_name='Azure Storage',
                    resource_types={'storageaccounts'},
                ),
            },
        ]
        pricing_client.prefetch_retail_region(region=source_region, entries=regional_prefetch_entries)
        pricing_client.prefetch_retail_region(region=target_region, entries=regional_prefetch_entries)

    def append_regional_result(
        *,
        row_key: str,
        provider_label: str,
        service_name: str,
        service_family: str,
        availability: str,
        notes: str,
        details_json: str,
        pricing_identity: dict[str, Any],
    ) -> None:
        pricing_summary = (
            pricing_client.retail_summary(
                provider=provider_label,
                service=service_name,
                sku='',
                region=source_region,
                pricing_identity=pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        pricing_comparison = (
            pricing_client.retail_comparison(
                provider=provider_label,
                service=service_name,
                sku='',
                source_region=source_region,
                target_region=target_region,
                pricing_identity=pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        results.append(
            {
                'row_key': row_key,
                'provider': provider_label,
                'source_region': source_region,
                'target_region': target_region,
                'availability': availability,
                'notes': f'{notes} {_pricing_note(pricing_summary)}'.strip() if pricing_summary else notes,
                'details_json': _attach_pricing_data(details_json, pricing_summary, pricing_comparison, pricing_identity),
                **_authoritative_row_identity(
                    pricing_identity,
                    service_name=service_name,
                    service_family=service_family,
                ),
            }
        )

    for namespace in namespaces:
        resource_types = provider_locations.get(namespace, {})
        source_types = sorted(resource_type for resource_type, locations in resource_types.items() if source_region_normalized in locations)
        target_types = sorted(resource_type for resource_type, locations in resource_types.items() if target_region_normalized in locations)
        namespace_matches = match_services_for_namespace(namespace, set(source_types) | set(target_types))
        service_rows = namespace_matches or [{'service': None, 'resourceTypes': sorted(set(source_types) | set(target_types))}]

        for service_row in service_rows:
            service = service_row.get('service')
            relevant_union_types = {str(item).lower() for item in (service_row.get('resourceTypes') or []) if str(item).strip()}
            relevant_source_types = sorted(
                service_bound_resource_types(service, namespace, set(source_types))
                if service is not None
                else [str(item).lower() for item in source_types]
            )
            relevant_target_types = sorted(
                service_bound_resource_types(service, namespace, set(target_types))
                if service is not None
                else [str(item).lower() for item in target_types]
            )

            source_count = len(relevant_source_types)
            target_count = len(relevant_target_types)
            if source_count == 0 and target_count == 0:
                continue

            shared_types = sorted(set(relevant_source_types) & set(relevant_target_types))
            source_only_types = sorted(set(relevant_source_types) - set(relevant_target_types))
            target_only_types = sorted(set(relevant_target_types) - set(relevant_source_types))

            if source_count == target_count:
                availability = 'FULL_MATCH'
            elif source_count > target_count:
                availability = 'SOURCE_EXTENDED'
            else:
                availability = 'TARGET_EXTENDED'

            curated = (
                build_curated_regional_details_for_service(
                    service,
                    source_region,
                    target_region,
                    set(relevant_source_types),
                    set(relevant_target_types),
                    source_region_has_zones=region_zone_support.get(source_region_normalized, 'unknown'),
                    target_region_has_zones=region_zone_support.get(target_region_normalized, 'unknown'),
                )
                if service is not None
                else build_curated_regional_details(
                    namespace,
                    source_region,
                    target_region,
                    set(relevant_source_types),
                    set(relevant_target_types),
                    source_region_has_zones=region_zone_support.get(source_region_normalized, 'unknown'),
                    target_region_has_zones=region_zone_support.get(target_region_normalized, 'unknown'),
                )
            )
            if curated and curated.get('sourceRegion', {}).get('serviceAvailable') and curated.get('targetRegion', {}).get('serviceAvailable'):
                curated = _augment_curated_details(
                    curated,
                    source_region=source_region,
                    target_region=target_region,
                    source_types=relevant_source_types,
                    target_types=relevant_target_types,
                    shared_types=shared_types,
                    source_only_types=source_only_types,
                    target_only_types=target_only_types,
                )

            if curated and (not curated.get('sourceRegion', {}).get('serviceAvailable') or not curated.get('targetRegion', {}).get('serviceAvailable')):
                notes = str(curated.get('summary') or '')
                details_json = json.dumps(
                    _build_service_availability_details(
                        curated,
                        source_region=source_region,
                        target_region=target_region,
                        source_count=source_count,
                        target_count=target_count,
                    ),
                    separators=(',', ':'),
                )
                service_name = str(curated.get('displayName') or _provider_display_name(namespace))
                service_family = str(curated.get('family') or _service_family(namespace))
            elif curated:
                notes = str(curated.get('summary') or _build_regional_notes(
                    source_region=source_region,
                    target_region=target_region,
                    shared_count=len(shared_types),
                    source_only_count=len(source_only_types),
                    target_only_count=len(target_only_types),
                ))
                details_json = json.dumps(
                    {
                        'layout': 'capability-matrix',
                        'providerNamespace': namespace,
                        'providerLabel': namespace,
                        'curated': curated,
                        'summary': {
                            'sourceCount': source_count,
                            'targetCount': target_count,
                            'sharedCount': len(shared_types),
                            'sourceOnlyCount': len(source_only_types),
                            'targetOnlyCount': len(target_only_types),
                            'capabilityCount': curated.get('summaryStats', {}).get('capabilityCount', 0),
                            'differentCapabilityCount': curated.get('summaryStats', {}).get('differentCapabilityCount', 0),
                            'matchedCapabilityCount': curated.get('summaryStats', {}).get('matchedCapabilityCount', 0),
                        },
                        'rawSections': [
                            _build_detail_section('Shared in both regions', shared_types),
                            _build_detail_section(f'Only in {source_region}', source_only_types),
                            _build_detail_section(f'Only in {target_region}', target_only_types),
                        ],
                    },
                    separators=(',', ':'),
                )
                service_name = str(curated.get('displayName') or _provider_display_name(namespace))
                service_family = str(curated.get('family') or _service_family(namespace))
            else:
                notes = _build_regional_notes(
                    source_region=source_region,
                    target_region=target_region,
                    shared_count=len(shared_types),
                    source_only_count=len(source_only_types),
                    target_only_count=len(target_only_types),
                )
                details_json = json.dumps(
                    {
                        'layout': 'raw-capability-overlap',
                        'providerNamespace': namespace,
                        'providerLabel': namespace,
                        'summary': {
                            'sourceCount': source_count,
                            'targetCount': target_count,
                            'sharedCount': len(shared_types),
                            'sourceOnlyCount': len(source_only_types),
                            'targetOnlyCount': len(target_only_types),
                        },
                        'sections': [
                            _build_detail_section('Shared in both regions', shared_types),
                            _build_detail_section(f'Only in {source_region}', source_only_types),
                            _build_detail_section(f'Only in {target_region}', target_only_types),
                        ],
                    },
                    separators=(',', ':'),
                )
                service_name = _provider_display_name(namespace)
                service_family = _service_family(namespace)

            pricing_identity = _pricing_identity(namespace, service_name=service_name, resource_types=relevant_union_types or (set(relevant_source_types) | set(relevant_target_types)))
            row_suffix = str((service or {}).get('service_key') or namespace)
            append_regional_result(
                row_key=_slugify(f'{namespace}-{row_suffix}-{source_region}-{target_region}-regional'),
                provider_label=namespace,
                service_name=service_name,
                service_family=service_family,
                availability=availability,
                notes=notes,
                details_json=details_json,
                pricing_identity=pricing_identity,
            )

    vm_details = _build_vm_family_details(
        source_region=source_region,
        target_region=target_region,
        source_entries=_available_compute_entries(source_compute_entries, 'virtualmachines', include_restricted=True),
        target_entries=_available_compute_entries(target_compute_entries, 'virtualmachines', include_restricted=True),
    )
    if vm_details['summary']['sourceCount'] or vm_details['summary']['targetCount']:
        vm_pricing_identity = _pricing_identity(
            'Microsoft.Compute/virtualMachines',
            service_name='Virtual Machines',
            resource_types={'virtualmachines'},
        )
        vm_pricing_summary = (
            pricing_client.retail_summary(
                provider='Microsoft.Compute/virtualMachines',
                service='Virtual Machines',
                sku='',
                region=source_region,
                pricing_identity=vm_pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        vm_pricing_comparison = (
            pricing_client.retail_comparison(
                provider='Microsoft.Compute/virtualMachines',
                service='Virtual Machines',
                sku='',
                source_region=source_region,
                target_region=target_region,
                pricing_identity=vm_pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        vm_details = _attach_vm_inline_pricing(vm_details, vm_pricing_comparison)
        results.append(
            {
                'row_key': _slugify(f'microsoft-compute-virtualmachines-{source_region}-{target_region}-regional'),
                'provider': 'Microsoft.Compute/virtualMachines',
                'source_region': source_region,
                'target_region': target_region,
                'availability': _status_from_counts(vm_details['summary']['sourceCount'], vm_details['summary']['targetCount']),
                'notes': f"{vm_details['summaryText']} {_pricing_note(vm_pricing_summary)}".strip() if vm_pricing_summary else vm_details['summaryText'],
                'details_json': _attach_pricing_data(json.dumps(vm_details, separators=(',', ':')), vm_pricing_summary, vm_pricing_comparison, vm_pricing_identity),
                **_authoritative_row_identity(
                    vm_pricing_identity,
                    service_name='Virtual Machines',
                    service_family='compute',
                ),
            }
        )

    disk_details = _build_disk_sku_details(
        source_region=source_region,
        target_region=target_region,
        source_entries=_available_compute_entries(source_disk_skus, 'disks', include_restricted=True),
        target_entries=_available_compute_entries(target_disk_skus, 'disks', include_restricted=True),
    )
    if disk_details['summary']['sourceCount'] or disk_details['summary']['targetCount']:
        disk_pricing_identity = _pricing_identity(
            'Microsoft.Compute/disks',
            service_name='Managed Disks',
            resource_types={'disks'},
        )
        disk_pricing_summary = (
            pricing_client.retail_summary(
                provider='Microsoft.Compute/disks',
                service='Managed Disks',
                sku='',
                region=source_region,
                pricing_identity=disk_pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        disk_pricing_comparison = (
            pricing_client.retail_comparison(
                provider='Microsoft.Compute/disks',
                service='Managed Disks',
                sku='',
                source_region=source_region,
                target_region=target_region,
                pricing_identity=disk_pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        disk_details = _attach_disk_inline_pricing(disk_details, disk_pricing_comparison)
        results.append(
            {
                'row_key': _slugify(f'microsoft-compute-disks-{source_region}-{target_region}-regional'),
                'provider': 'Microsoft.Compute/disks',
                'source_region': source_region,
                'target_region': target_region,
                'availability': _status_from_counts(disk_details['summary']['sourceCount'], disk_details['summary']['targetCount']),
                'notes': f"{disk_details['summaryText']} {_pricing_note(disk_pricing_summary)}".strip() if disk_pricing_summary else disk_details['summaryText'],
                'details_json': _attach_pricing_data(json.dumps(disk_details, separators=(',', ':')), disk_pricing_summary, None, disk_pricing_identity),
                **_authoritative_row_identity(
                    disk_pricing_identity,
                    service_name='Managed Disks',
                    service_family='storage',
                ),
            }
        )

    storage_details = _build_storage_capability_details(
        source_region=source_region,
        target_region=target_region,
        source_entries=_storage_entries_for_region(storage_entries, source_region_normalized),
        target_entries=_storage_entries_for_region(storage_entries, target_region_normalized),
        source_region_has_zones=region_zone_support.get(source_region_normalized, 'unknown'),
        target_region_has_zones=region_zone_support.get(target_region_normalized, 'unknown'),
    )
    if storage_details['summary']['sourceCount'] or storage_details['summary']['targetCount']:
        storage_pricing_identity = _pricing_identity(
            'Microsoft.Storage/storageAccounts',
            service_name='Azure Storage',
            resource_types={'storageaccounts'},
        )
        storage_pricing_summary = (
            pricing_client.retail_summary(
                provider='Microsoft.Storage/storageAccounts',
                service='Azure Storage',
                sku='',
                region=source_region,
                pricing_identity=storage_pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        storage_pricing_comparison = (
            pricing_client.retail_comparison(
                provider='Microsoft.Storage/storageAccounts',
                service='Azure Storage',
                sku='',
                source_region=source_region,
                target_region=target_region,
                pricing_identity=storage_pricing_identity,
            )
            if pricing_client is not None
            else None
        )
        results.append(
            {
                'row_key': _slugify(f'microsoft-storage-storageaccounts-{source_region}-{target_region}-regional'),
                'provider': 'Microsoft.Storage/storageAccounts',
                'source_region': source_region,
                'target_region': target_region,
                'availability': _status_from_counts(storage_details['summary']['sourceCount'], storage_details['summary']['targetCount']),
                'notes': f"{storage_details['curated']['summary']} {_pricing_note(storage_pricing_summary)}".strip() if storage_pricing_summary else str(storage_details['curated']['summary']),
                'details_json': _attach_pricing_data(json.dumps(storage_details, separators=(',', ':')), storage_pricing_summary, storage_pricing_comparison, storage_pricing_identity),
                **_authoritative_row_identity(
                    storage_pricing_identity,
                    service_name='Azure Storage',
                    service_family='storage',
                ),
            }
        )

    return results