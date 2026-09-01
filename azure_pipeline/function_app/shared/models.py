from __future__ import annotations

from dataclasses import asdict, dataclass
import json


MAX_TABLE_PROPERTY_STRING_CHARS = 30000
# Azure Table string properties top out at 64 KiB and an entity can reach 1 MiB total.
# Keep each chunk conservative at 30k chars, but allow many more chunks before compacting so
# rich VM and disk payloads fit without degrading to the omission banner.
MAX_TABLE_DETAIL_CHUNK_COUNT = 20
MAX_TABLE_STRING_CHARS = MAX_TABLE_PROPERTY_STRING_CHARS * MAX_TABLE_DETAIL_CHUNK_COUNT
DETAILS_JSON_CHUNK_PREFIX = 'details_json_'
DETAILS_JSON_CHUNK_COUNT_FIELD = 'details_json_chunk_count'
DETAILS_JSON_BLOB_FIELD = 'details_json_blob'


def _serialize_compact_json(payload: object) -> str:
    return json.dumps(payload, separators=(',', ':'))


def _chunk_string(value: str, chunk_size: int = MAX_TABLE_PROPERTY_STRING_CHARS) -> list[str]:
    if not value:
        return ['']
    return [value[index:index + chunk_size] for index in range(0, len(value), chunk_size)]


def _merge_chunked_details(entity: dict[str, object]) -> str:
    chunk_count_value = entity.get(DETAILS_JSON_CHUNK_COUNT_FIELD)
    try:
        chunk_count = max(1, int(chunk_count_value or 1))
    except (TypeError, ValueError):
        chunk_count = 1

    chunks = [str(entity.get('details_json') or '')]
    for index in range(1, chunk_count):
        chunks.append(str(entity.get(f'{DETAILS_JSON_CHUNK_PREFIX}{index:02d}') or ''))
    return ''.join(chunks)


def _serialize_if_within_limit(payload: object) -> str | None:
    serialized = _serialize_compact_json(payload)
    if len(serialized) <= MAX_TABLE_STRING_CHARS:
        return serialized
    return None


def _trim_section_items(section: dict[str, object], limit: int) -> dict[str, object]:
    items = list(section.get('items') or [])
    trimmed = items[:limit]
    result = dict(section)
    result['items'] = trimmed
    result['count'] = len(trimmed)
    if len(items) > limit:
        result['truncated'] = True
        result['truncatedCount'] = len(items) - limit
    return result


def _trim_expanded_section(section: dict[str, object], group_limit: int, item_limit: int) -> dict[str, object]:
    groups = list(section.get('groups') or [])
    trimmed_groups = [_trim_section_items(dict(group), item_limit) for group in groups[:group_limit]]
    result = dict(section)
    result['groups'] = trimmed_groups
    result['count'] = sum(int(group.get('count', 0)) for group in trimmed_groups)
    if len(groups) > group_limit:
        result['truncated'] = True
        result['truncatedGroupCount'] = len(groups) - group_limit
    return result


def _trim_pricing_item(item: dict[str, object]) -> dict[str, object]:
    trimmed: dict[str, object] = {}
    for key in (
        'key',
        'label',
        'offerLabel',
        'meterName',
        'productName',
        'skuName',
        'armSkuName',
        'sourcePrice',
        'targetPrice',
        'delta',
        'deltaPercent',
        'cheaperRegion',
        'currencyCode',
        'unitOfMeasure',
        'sourceMeterName',
        'targetMeterName',
        'sourceArmSkuName',
        'targetArmSkuName',
        'sourcePriceType',
        'targetPriceType',
        'sourceReservationTerm',
        'targetReservationTerm',
        'sourceAvailable',
        'targetAvailable',
    ):
        value = item.get(key)
        if value not in (None, ''):
            trimmed[key] = value

    source_savings = item.get('sourceSavingsPlan')
    if isinstance(source_savings, list) and source_savings:
        trimmed['sourceSavingsPlan'] = [
            {
                key: entry.get(key)
                for key in ('term', 'retailPrice', 'unitPrice')
                if entry.get(key) not in (None, '')
            }
            for entry in source_savings[:3]
            if isinstance(entry, dict)
        ]

    target_savings = item.get('targetSavingsPlan')
    if isinstance(target_savings, list) and target_savings:
        trimmed['targetSavingsPlan'] = [
            {
                key: entry.get(key)
                for key in ('term', 'retailPrice', 'unitPrice')
                if entry.get(key) not in (None, '')
            }
            for entry in target_savings[:3]
            if isinstance(entry, dict)
        ]
    return trimmed


def _trim_inline_pricing(item: object) -> dict[str, object] | None:
    if not isinstance(item, dict):
        return None

    trimmed: dict[str, object] = {}
    for key in (
        'label',
        'offerLabel',
        'sourcePrice',
        'targetPrice',
        'delta',
        'deltaPercent',
        'cheaperRegion',
        'currencyCode',
        'unitOfMeasure',
        'sourceAvailable',
        'targetAvailable',
        'sourceMeterName',
        'targetMeterName',
        'sourcePriceType',
        'targetPriceType',
        'sourceReservationTerm',
        'targetReservationTerm',
    ):
        value = item.get(key)
        if value not in (None, ''):
            trimmed[key] = value

    source_savings = item.get('sourceSavingsPlan')
    if isinstance(source_savings, list) and source_savings:
        trimmed['sourceSavingsPlan'] = [
            {
                key: entry.get(key)
                for key in ('term', 'retailPrice', 'unitPrice')
                if entry.get(key) not in (None, '')
            }
            for entry in source_savings[:3]
            if isinstance(entry, dict)
        ]

    target_savings = item.get('targetSavingsPlan')
    if isinstance(target_savings, list) and target_savings:
        trimmed['targetSavingsPlan'] = [
            {
                key: entry.get(key)
                for key in ('term', 'retailPrice', 'unitPrice')
                if entry.get(key) not in (None, '')
            }
            for entry in target_savings[:3]
            if isinstance(entry, dict)
        ]

    return trimmed or None


def _trim_row_pricing_details(
    item: object,
    *,
    group_limit: int = 2,
    item_limit: int = 1,
    vm_model_limit: int = 5,
    vm_row_limit: int = 30,
) -> dict[str, object] | None:
    if not isinstance(item, dict):
        return None

    trimmed: dict[str, object] = {
        key: value
        for key in ('kind', 'offerCount', 'matchedItemCount')
        for value in [item.get(key)]
        if value not in (None, '')
    }

    summary = _trim_inline_pricing(item.get('summary'))
    if summary:
        trimmed['summary'] = summary

    if item.get('kind') == 'vm':
        models = [
            {
                key: model.get(key)
                for key in ('key', 'title')
                if model.get(key) not in (None, '')
            }
            for model in list(item.get('models') or [])[:vm_model_limit]
            if isinstance(model, dict)
        ]
        if models:
            trimmed['models'] = models
        model_keys = {str(model.get('key') or '') for model in models if model.get('key') not in (None, '')}

        trimmed_rows: list[dict[str, object]] = []
        for row in list(item.get('rows') or [])[:vm_row_limit]:
            if not isinstance(row, dict):
                continue
            trimmed_row: dict[str, object] = {
                key: row.get(key)
                for key in ('key', 'sku')
                if row.get(key) not in (None, '')
            }
            offers = row.get('offers') if isinstance(row.get('offers'), dict) else None
            if offers:
                trimmed_row['offers'] = {
                    str(key): compact
                    for key, compact in (
                        (offer_key, _trim_pricing_item(dict(offer_value)))
                        for offer_key, offer_value in offers.items()
                        if isinstance(offer_value, dict) and (not model_keys or str(offer_key) in model_keys)
                    )
                    if compact
                }
            if trimmed_row:
                trimmed_rows.append(trimmed_row)
        if trimmed_rows:
            trimmed['rows'] = trimmed_rows
            trimmed['rowCount'] = item.get('rowCount', len(trimmed_rows))

    groups = list(item.get('groups') or [])
    trimmed_groups: list[dict[str, object]] = []
    for group in groups[:group_limit]:
        if not isinstance(group, dict):
            continue
        group_items = [
            _trim_pricing_item(dict(group_item))
            for group_item in list(group.get('items') or [])[:item_limit]
            if isinstance(group_item, dict)
        ]
        trimmed_groups.append({
            key: value
            for key in ('key', 'title', 'count')
            for value in [group.get(key)]
            if value not in (None, '')
        } | {'items': group_items})

    if trimmed_groups:
        trimmed['groups'] = trimmed_groups

    return trimmed or None


def _trim_family_rows(
    rows: object,
    limit: int = 20,
    *,
    vm_model_limit: int = 3,
    vm_row_limit: int = 8,
) -> list[dict[str, object]]:
    if not isinstance(rows, list):
        return []

    trimmed_rows: list[dict[str, object]] = []
    for row in rows[:limit]:
        if not isinstance(row, dict):
            continue

        trimmed: dict[str, object] = {}
        for key in ('family', 'sourceCount', 'targetCount', 'delta', 'status'):
            value = row.get(key)
            if value not in (None, ''):
                trimmed[key] = value

        pricing = _trim_inline_pricing(row.get('pricing'))
        if pricing:
            trimmed['pricing'] = pricing

        pricing_details = _trim_row_pricing_details(
            row.get('pricingDetails'),
            group_limit=1,
            item_limit=1,
            vm_model_limit=vm_model_limit,
            vm_row_limit=vm_row_limit,
        )
        if pricing_details:
            trimmed['pricingDetails'] = pricing_details
        trimmed_rows.append(trimmed)

    return trimmed_rows


def _trim_disk_rows(
    rows: object,
    limit: int = 20,
    *,
    vm_model_limit: int = 5,
    vm_row_limit: int = 30,
) -> list[dict[str, object]]:
    if not isinstance(rows, list):
        return []

    trimmed_rows: list[dict[str, object]] = []
    for row in rows[:limit]:
        if not isinstance(row, dict):
            continue

        trimmed: dict[str, object] = {}
        for key in ('sku', 'tier', 'sourceAvailable', 'targetAvailable', 'sourceRestricted', 'targetRestricted', 'status'):
            value = row.get(key)
            if value not in (None, ''):
                trimmed[key] = value

        pricing = _trim_inline_pricing(row.get('pricing'))
        if pricing:
            trimmed['pricing'] = pricing

        pricing_details = _trim_row_pricing_details(
            row.get('pricingDetails'),
            vm_model_limit=vm_model_limit,
            vm_row_limit=vm_row_limit,
        )
        if pricing_details:
            trimmed['pricingDetails'] = pricing_details
        trimmed_rows.append(trimmed)

    return trimmed_rows


def _trim_tier_rows(rows: object) -> list[dict[str, object]]:
    if not isinstance(rows, list):
        return []

    trimmed_rows: list[dict[str, object]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue

        trimmed: dict[str, object] = {}
        for key in ('tier', 'sourceCount', 'targetCount'):
            value = row.get(key)
            if value not in (None, ''):
                trimmed[key] = value
        trimmed_rows.append(trimmed)

    return trimmed_rows


def _trim_pricing_comparison(comparison: dict[str, object], item_limit: int) -> dict[str, object]:
    items = list(comparison.get('items') or [])
    trimmed = dict(comparison)
    trimmed['items'] = [_trim_pricing_item(dict(item)) for item in items[:item_limit] if isinstance(item, dict)]
    trimmed['returnedItems'] = len(trimmed['items'])
    trimmed['totalItems'] = comparison.get('totalItems', len(items))
    trimmed['truncated'] = len(items) > item_limit or bool(comparison.get('truncated'))
    return trimmed


def _trim_region_summary(region: object) -> dict[str, object] | None:
    if not isinstance(region, dict):
        return None

    trimmed: dict[str, object] = {}
    for key in ('serviceAvailable', 'notes', 'displayName'):
        value = region.get(key)
        if value not in (None, ''):
            trimmed[key] = value

    zone_support = region.get('zoneSupport')
    if isinstance(zone_support, dict):
        trimmed['zoneSupport'] = {
            key: value
            for key, value in zone_support.items()
            if key in {'mode', 'label', 'notes'} and value not in (None, '')
        }

    return trimmed or None


def _minimal_details_payload(
    payload: dict[str, object],
    *,
    family_limit: int = 20,
    family_vm_model_limit: int = 3,
    family_vm_row_limit: int = 8,
    sku_limit: int = 20,
) -> dict[str, object]:
    curated = payload.get('curated') if isinstance(payload.get('curated'), dict) else None
    minimal_curated: dict[str, object] | None = None
    if curated:
        capabilities = list(curated.get('capabilities') or [])
        minimal_curated = {
            'matched': curated.get('matched'),
            'serviceKey': curated.get('serviceKey'),
            'displayName': curated.get('displayName'),
            'family': curated.get('family'),
            'summary': curated.get('summary'),
            'capabilities': capabilities[:6],
            'sourceRegion': _trim_region_summary(curated.get('sourceRegion')),
            'targetRegion': _trim_region_summary(curated.get('targetRegion')),
            'summaryStats': curated.get('summaryStats'),
            'detailsTruncated': True,
        }

    pricing_comparison = payload.get('pricingComparison') if isinstance(payload.get('pricingComparison'), dict) else None
    minimal_payload = {
        'layout': payload.get('layout', 'summary'),
        'providerNamespace': payload.get('providerNamespace'),
        'providerLabel': payload.get('providerLabel'),
        'summary': payload.get('summary'),
        'pricingSummary': payload.get('pricingSummary'),
        'pricingComparison': _trim_pricing_comparison(pricing_comparison, item_limit=6) if pricing_comparison else None,
        'metricCards': list(payload.get('metricCards') or [])[:4],
        'summaryText': 'Detailed capability payload was trimmed to fit Azure Table Storage limits.',
        'curated': minimal_curated,
        'detailsTruncated': True,
    }

    layout = minimal_payload['layout']
    if layout == 'family-breakdown':
        minimal_payload['families'] = _trim_family_rows(
            payload.get('families'),
            limit=family_limit,
            vm_model_limit=family_vm_model_limit,
            vm_row_limit=family_vm_row_limit,
        )
        minimal_payload['pricingMatchSummary'] = payload.get('pricingMatchSummary')
    elif layout == 'sku-breakdown':
        minimal_payload['skus'] = _trim_disk_rows(payload.get('skus'), limit=sku_limit)
        minimal_payload['tierSummary'] = _trim_tier_rows(payload.get('tierSummary'))
        minimal_payload['pricingMatchSummary'] = payload.get('pricingMatchSummary')

    return minimal_payload


def _compact_details_json(details_json: str) -> str:
    if not details_json or len(details_json) <= MAX_TABLE_STRING_CHARS:
        return details_json

    try:
        payload = json.loads(details_json)
    except json.JSONDecodeError:
        return details_json[:MAX_TABLE_STRING_CHARS]

    if not isinstance(payload, dict):
        return details_json[:MAX_TABLE_STRING_CHARS]

    compact = dict(payload)
    curated = compact.get('curated') if isinstance(compact.get('curated'), dict) else None
    if curated:
        curated = dict(curated)
        expanded = list(curated.get('expandedCapabilities') or [])
        if expanded:
            curated['expandedCapabilities'] = [
                _trim_expanded_section(dict(section), group_limit=3, item_limit=8)
                for section in expanded[:3]
            ]
            curated['detailsTruncated'] = True
        compact['curated'] = curated

    pricing_comparison = compact.get('pricingComparison') if isinstance(compact.get('pricingComparison'), dict) else None
    if pricing_comparison:
        compact['pricingComparison'] = _trim_pricing_comparison(pricing_comparison, item_limit=12)

    serialized = _serialize_if_within_limit(compact)
    if serialized is not None:
        return serialized

    pricing_comparison = compact.get('pricingComparison') if isinstance(compact.get('pricingComparison'), dict) else None
    if pricing_comparison:
        compact = dict(compact)
        compact['pricingComparison'] = _trim_pricing_comparison(pricing_comparison, item_limit=6)

    serialized = _serialize_if_within_limit(compact)
    if serialized is not None:
        return serialized

    compact = dict(compact)
    compact.pop('metricCards', None)
    serialized = _serialize_if_within_limit(compact)
    if serialized is not None:
        return serialized

    compact = dict(compact)
    compact.pop('pricingComparison', None)
    compact.pop('pricingSummary', None)
    serialized = _serialize_if_within_limit(compact)
    if serialized is not None:
        return serialized

    compact = dict(compact)
    if isinstance(compact.get('curated'), dict):
        compact_curated = dict(compact['curated'])
        compact_curated['sourceRegion'] = _trim_region_summary(compact_curated.get('sourceRegion'))
        compact_curated['targetRegion'] = _trim_region_summary(compact_curated.get('targetRegion'))
        capabilities = list(compact_curated.get('capabilities') or [])
        compact_curated['capabilities'] = capabilities[:6]
        compact_curated['expandedCapabilities'] = []
        compact_curated['detailsTruncated'] = True
        compact['curated'] = compact_curated

    serialized = _serialize_if_within_limit(compact)
    if serialized is not None:
        return serialized

    compact = dict(compact)
    if isinstance(compact.get('curated'), dict):
        compact_curated = dict(compact['curated'])
        compact_curated['capabilities'] = []
        compact_curated['summaryStats'] = None
        compact['curated'] = compact_curated

    serialized = _serialize_if_within_limit(compact)
    if serialized is not None:
        return serialized

    compact = dict(compact)
    for key in ('rawSections', 'sections'):
        sections = compact.get(key)
        if isinstance(sections, list) and sections:
            compact[key] = [_trim_section_items(dict(section), 8) for section in sections[:3] if isinstance(section, dict)]

    serialized = _serialize_if_within_limit(compact)
    if serialized is not None:
        return serialized

    minimal_payload = _minimal_details_payload(payload)
    serialized = _serialize_if_within_limit(minimal_payload)
    if serialized is not None:
        return serialized

    slimmer_minimal_payload = _minimal_details_payload(
        payload,
        family_limit=8,
        family_vm_model_limit=2,
        family_vm_row_limit=4,
        sku_limit=12,
    )
    slimmer_minimal_payload.pop('pricingComparison', None)
    slimmer_minimal_payload.pop('pricingSummary', None)
    slimmer_minimal_payload['metricCards'] = list(slimmer_minimal_payload.get('metricCards') or [])[:2]
    serialized = _serialize_if_within_limit(slimmer_minimal_payload)
    if serialized is not None:
        return serialized

    minimal_payload = dict(minimal_payload)
    minimal_payload.pop('pricingComparison', None)
    minimal_payload.pop('pricingSummary', None)
    serialized = _serialize_if_within_limit(minimal_payload)
    if serialized is not None:
        return serialized

    minimal_payload = dict(minimal_payload)
    minimal_payload['curated'] = None
    serialized = _serialize_if_within_limit(minimal_payload)
    if serialized is not None:
        return serialized

    ultra_minimal_payload = _minimal_details_payload(
        payload,
        family_limit=3,
        family_vm_model_limit=1,
        family_vm_row_limit=2,
        sku_limit=6,
    )
    ultra_minimal_payload.pop('pricingComparison', None)
    ultra_minimal_payload.pop('pricingSummary', None)
    ultra_minimal_payload['metricCards'] = []
    ultra_minimal_payload['curated'] = None
    serialized = _serialize_if_within_limit(ultra_minimal_payload)
    if serialized is not None:
        return serialized

    summary_only = {
        'layout': payload.get('layout', 'summary'),
        'providerNamespace': payload.get('providerNamespace'),
        'providerLabel': payload.get('providerLabel'),
        'summaryText': 'Detailed capability payload was omitted to fit Azure Table Storage limits.',
        'detailsTruncated': True,
    }
    serialized = _serialize_if_within_limit(summary_only)
    if serialized is not None:
        return serialized

    return _serialize_compact_json(summary_only)[:MAX_TABLE_STRING_CHARS]


@dataclass(frozen=True)
class ComparisonRecord:
    partition_key: str
    row_key: str
    comparison_mode: str
    service: str
    provider: str
    service_family: str
    source_region: str
    target_region: str
    availability: str
    notes: str
    refreshed_at: str
    run_id: str
    canonical_service_id: str = ''
    canonical_service_name: str = ''
    identity_source: str = ''
    is_fallback_identity: bool = False
    details_json: str = ''

    def as_entity(self) -> dict[str, object]:
        entity = asdict(self)
        compact_details_json = _compact_details_json(entity.get('details_json', ''))
        detail_chunks = _chunk_string(compact_details_json)
        entity['details_json'] = detail_chunks[0]
        entity[DETAILS_JSON_CHUNK_COUNT_FIELD] = len(detail_chunks)
        for index, chunk in enumerate(detail_chunks[1:], start=1):
            entity[f'{DETAILS_JSON_CHUNK_PREFIX}{index:02d}'] = chunk
        entity['PartitionKey'] = entity.pop('partition_key')
        entity['RowKey'] = entity.pop('row_key')
        return entity

    def as_dict(self) -> dict[str, str]:
        return asdict(self)


@dataclass(frozen=True)
class RefreshRun:
    partition_key: str
    row_key: str
    comparison_mode: str
    subscription_id: str
    source_region: str
    target_region: str
    status: str
    reason: str
    started_at: str
    completed_at: str
    record_count: int

    def as_entity(self) -> dict[str, object]:
        entity = asdict(self)
        entity['PartitionKey'] = entity.pop('partition_key')
        entity['RowKey'] = entity.pop('row_key')
        return entity