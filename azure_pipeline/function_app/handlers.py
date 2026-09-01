from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from typing import TYPE_CHECKING

import azure.functions as func

if TYPE_CHECKING:
    from shared.config import Settings
    from shared.models import ComparisonRecord, RefreshRun


logger = logging.getLogger(__name__)

US_GOV_REGION_PREFIXES = ('usgov', 'usdod')


def _service_identity_from_record(record: ComparisonRecord) -> dict[str, object] | None:
    top_level_identity = {
        'canonicalServiceId': record.canonical_service_id,
        'canonicalServiceName': record.canonical_service_name or record.service,
        'canonicalFamilyKey': record.service_family,
        'identitySource': record.identity_source,
        'isFallbackIdentity': record.is_fallback_identity,
        'matched': not record.is_fallback_identity,
        'providerNamespace': record.provider.split('/')[0].lower() if record.provider else '',
    }
    try:
        payload = json.loads(record.details_json) if record.details_json else {}
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    service_identity = payload.get('serviceIdentity')
    if isinstance(service_identity, dict):
        return {**top_level_identity, **service_identity}
    if top_level_identity['canonicalServiceId'] or top_level_identity['canonicalServiceName']:
        return top_level_identity
    return None


def _build_coverage_diagnostics(records: list[ComparisonRecord]) -> dict[str, object]:
    fallback_provider_counts: dict[str, int] = {}
    fallback_service_counts: dict[str, dict[str, object]] = {}
    identity_source_counts: dict[str, int] = {}
    unique_canonical_services: set[str] = set()
    unique_canonical_families: set[str] = set()
    identity_record_count = 0
    fallback_count = 0
    diagnostic_count = 0

    for record in records:
        service_identity = _service_identity_from_record(record)
        if not service_identity:
            continue

        identity_record_count += 1
        canonical_service_id = str(service_identity.get('canonicalServiceId') or '').strip()
        canonical_service_name = str(service_identity.get('canonicalServiceName') or record.service or '').strip()
        canonical_family = str(service_identity.get('canonicalFamilyKey') or service_identity.get('canonicalFamily') or record.service_family or '').strip()
        identity_source = str(service_identity.get('identitySource') or '').strip()
        diagnostics = service_identity.get('diagnostics') if isinstance(service_identity.get('diagnostics'), list) else []
        is_fallback = bool(service_identity.get('isFallbackIdentity')) or service_identity.get('matched') is False

        if canonical_service_id:
            unique_canonical_services.add(canonical_service_id)
        if canonical_family:
            unique_canonical_families.add(canonical_family)
        if identity_source:
            identity_source_counts[identity_source] = identity_source_counts.get(identity_source, 0) + 1
        diagnostic_count += len(diagnostics)

        if not is_fallback:
            continue

        fallback_count += 1
        provider_namespace = str(service_identity.get('providerNamespace') or record.provider or '').strip()
        if provider_namespace:
            fallback_provider_counts[provider_namespace] = fallback_provider_counts.get(provider_namespace, 0) + 1

        fallback_key = canonical_service_id or canonical_service_name or record.row_key
        current = fallback_service_counts.setdefault(
            fallback_key,
            {
                'canonicalServiceId': canonical_service_id,
                'canonicalServiceName': canonical_service_name,
                'count': 0,
            },
        )
        current['count'] = int(current.get('count') or 0) + 1

    top_fallback_providers = [
        {'providerNamespace': provider_namespace, 'count': count}
        for provider_namespace, count in sorted(fallback_provider_counts.items(), key=lambda item: (-item[1], item[0]))[:5]
    ]
    top_fallback_services = sorted(
        fallback_service_counts.values(),
        key=lambda item: (-int(item.get('count') or 0), str(item.get('canonicalServiceName') or '')),
    )[:5]

    return {
        'identityRecordCount': identity_record_count,
        'fallbackCount': fallback_count,
        'matchedCount': max(0, identity_record_count - fallback_count),
        'diagnosticCount': diagnostic_count,
        'uniqueCanonicalServiceCount': len(unique_canonical_services),
        'uniqueCanonicalFamilyCount': len(unique_canonical_families),
        'identitySourceCounts': identity_source_counts,
        'topFallbackProviders': top_fallback_providers,
        'topFallbackServices': top_fallback_services,
    }


def _build_comparison_records(
    settings: Settings,
    *,
    comparison_mode: str,
    run_id: str,
    subscription_id: str,
    source_region: str,
    target_region: str,
) -> list[ComparisonRecord]:
    from shared.azure_queries import AzureQueryClient, compare_inventory, compare_regions
    from shared.models import ComparisonRecord
    from shared.pricing import PricingClient

    timestamp = datetime.now(UTC).isoformat()
    client = AzureQueryClient(settings)
    pricing_client = PricingClient(settings)
    if comparison_mode == 'regional':
        comparisons = compare_regions(
            client,
            subscription_id=subscription_id,
            source_region=source_region,
            target_region=target_region,
            pricing_client=pricing_client,
        )
    else:
        comparisons = compare_inventory(
            client,
            subscription_id=subscription_id,
            source_region=source_region,
            target_region=target_region,
            pricing_client=pricing_client,
        )

    return [
        ComparisonRecord(
            partition_key='current',
            row_key=item['row_key'],
            comparison_mode=comparison_mode,
            service=item['service'],
            provider=item['provider'],
            service_family=item['service_family'],
            canonical_service_id=item.get('canonical_service_id', ''),
            canonical_service_name=item.get('canonical_service_name', ''),
            identity_source=item.get('identity_source', ''),
            is_fallback_identity=bool(item.get('is_fallback_identity', False)),
            source_region=item['source_region'],
            target_region=item['target_region'],
            availability=item['availability'],
            notes=item['notes'],
            details_json=item.get('details_json', ''),
            refreshed_at=timestamp,
            run_id=run_id,
        )
        for item in comparisons
    ]


def _is_us_gov_cloud(cloud_environment: str) -> bool:
    return cloud_environment.strip().lower() == 'azureusgovernment'


def _is_us_gov_region(region: str) -> bool:
    normalized = region.strip().lower()
    return normalized.startswith(US_GOV_REGION_PREFIXES)


def _validate_region_cloud_alignment(settings: Settings, source_region: str, target_region: str) -> None:
    requested_regions = [source_region.strip(), target_region.strip()]
    if _is_us_gov_cloud(settings.cloud_environment):
        invalid = [region for region in requested_regions if region and not _is_us_gov_region(region)]
        if invalid:
            invalid_csv = ', '.join(invalid)
            raise ValueError(
                f'Azure Government deployments only support Azure Government regions; received: {invalid_csv}.'
            )
        return

    invalid = [region for region in requested_regions if region and _is_us_gov_region(region)]
    if invalid:
        invalid_csv = ', '.join(invalid)
        raise ValueError(
            'Azure Government regions require the Function App to run with AzureUSGovernment cloud settings; '
            f'received: {invalid_csv}.'
        )


def _resolve_refresh_request(
    settings: Settings,
    request: func.HttpRequest | None,
) -> tuple[str, str, str, str]:
    payload: dict[str, object] = {}
    if request is not None:
        try:
            request_payload = request.get_json()
            if isinstance(request_payload, dict):
                payload = request_payload
        except ValueError:
            payload = {}

    comparison_mode = str(payload.get('comparisonMode') or (request.params.get('comparisonMode') if request else None) or 'inventory').lower()
    source_region = str(payload.get('sourceRegion') or (request.params.get('sourceRegion') if request else None) or settings.default_source_region)
    target_region = str(payload.get('targetRegion') or (request.params.get('targetRegion') if request else None) or settings.default_target_region)
    subscription_id = str(payload.get('subscriptionId') or (request.params.get('subscriptionId') if request else None) or settings.subscription_id)
    _validate_region_cloud_alignment(settings, source_region, target_region)
    return comparison_mode, subscription_id, source_region, target_region


def _run_refresh(
    settings: Settings,
    *,
    reason: str,
    comparison_mode: str,
    subscription_id: str,
    source_region: str,
    target_region: str,
) -> dict[str, object]:
    from shared.models import ComparisonRecord, RefreshRun
    from shared.storage import ComparisonRepository

    repository = ComparisonRepository(settings)
    started_at = datetime.now(UTC)
    run_id = started_at.strftime('%Y%m%d%H%M%S')
    logger.info(
        'refresh starting run_id=%s reason=%s comparison_mode=%s subscription_id=%s source_region=%s target_region=%s',
        run_id,
        reason,
        comparison_mode,
        subscription_id,
        source_region,
        target_region,
    )
    repository.upsert_run(
        RefreshRun(
            partition_key='runs',
            row_key=run_id,
            comparison_mode=comparison_mode,
            subscription_id=subscription_id,
            source_region=source_region,
            target_region=target_region,
            status='running',
            reason=f'{reason}:{source_region}:{target_region}',
            started_at=started_at.isoformat(),
            completed_at='',
            record_count=0,
        )
    )

    try:
        records = _build_comparison_records(
            settings,
            comparison_mode=comparison_mode,
            run_id=run_id,
            subscription_id=subscription_id,
            source_region=source_region,
            target_region=target_region,
        )
        repository.replace_current_comparisons(records)
        repository.upsert_comparisons([
            ComparisonRecord(
                partition_key=run_id,
                row_key=record.row_key,
                comparison_mode=record.comparison_mode,
                service=record.service,
                provider=record.provider,
                service_family=record.service_family,
                canonical_service_id=record.canonical_service_id,
                canonical_service_name=record.canonical_service_name,
                identity_source=record.identity_source,
                is_fallback_identity=record.is_fallback_identity,
                source_region=record.source_region,
                target_region=record.target_region,
                availability=record.availability,
                notes=record.notes,
                details_json=record.details_json,
                refreshed_at=record.refreshed_at,
                run_id=record.run_id,
            )
            for record in records
        ])
        repository.upsert_run(
            RefreshRun(
                partition_key='runs',
                row_key=run_id,
                comparison_mode=comparison_mode,
                subscription_id=subscription_id,
                source_region=source_region,
                target_region=target_region,
                status='completed',
                reason=f'{reason}:{source_region}:{target_region}',
                started_at=started_at.isoformat(),
                completed_at=datetime.now(UTC).isoformat(),
                record_count=len(records),
            )
        )
        logging.info('Refresh completed with %d records for %s -> %s', len(records), source_region, target_region)
        return {
            'runId': run_id,
            'comparisonMode': comparison_mode,
            'status': 'completed',
            'recordCount': len(records),
            'subscriptionId': subscription_id,
            'sourceRegion': source_region,
            'targetRegion': target_region,
        }
    except Exception as exc:
        repository.upsert_run(
            RefreshRun(
                partition_key='runs',
                row_key=run_id,
                comparison_mode=comparison_mode,
                subscription_id=subscription_id,
                source_region=source_region,
                target_region=target_region,
                status='failed',
                reason=f'{reason}:{source_region}:{target_region}:{exc}',
                started_at=started_at.isoformat(),
                completed_at=datetime.now(UTC).isoformat(),
                record_count=0,
            )
        )
        logging.exception('Refresh failed')
        raise


def _build_comparison_payload(records: list[ComparisonRecord], latest_run: RefreshRun | None) -> dict[str, object]:
    refreshed_at = max((record.refreshed_at for record in records), default=None)
    return {
        'metadata': {
            'count': len(records),
            'refreshedAt': refreshed_at,
            'latestRunId': latest_run.row_key if latest_run else None,
            'latestRunStatus': latest_run.status if latest_run else None,
            'latestComparisonMode': latest_run.comparison_mode if latest_run else None,
            'coverageDiagnostics': _build_coverage_diagnostics(records),
        },
        'items': [record.as_dict() for record in records],
    }


def _build_runs_payload(runs: list[RefreshRun]) -> dict[str, object]:
    return {
        'metadata': {
            'count': len(runs),
        },
        'items': [run.as_entity() for run in runs],
    }


def scheduled_refresh_main(timer: func.TimerRequest) -> None:
    from shared.config import load_settings

    settings = load_settings()
    if timer.past_due:
        logging.warning('Scheduled refresh is running later than expected.')
    comparison_mode, subscription_id, source_region, target_region = _resolve_refresh_request(settings, None)
    _run_refresh(
        settings,
        reason='scheduled',
        comparison_mode=comparison_mode,
        subscription_id=subscription_id,
        source_region=source_region,
        target_region=target_region,
    )


def manual_refresh_main(request: func.HttpRequest) -> func.HttpResponse:
    from shared.config import load_settings

    settings = load_settings()
    try:
        comparison_mode, subscription_id, source_region, target_region = _resolve_refresh_request(settings, request)
    except ValueError as exc:
        return func.HttpResponse(
            json.dumps({'error': str(exc)}),
            mimetype='application/json',
            status_code=400,
        )
    logger.info(
        'manual_refresh requested comparison_mode=%s subscription_id=%s source_region=%s target_region=%s',
        comparison_mode,
        subscription_id,
        source_region,
        target_region,
    )
    result = _run_refresh(
        settings,
        reason='manual',
        comparison_mode=comparison_mode,
        subscription_id=subscription_id,
        source_region=source_region,
        target_region=target_region,
    )
    return func.HttpResponse(
        json.dumps(result),
        mimetype='application/json',
        status_code=200,
    )


def list_comparisons_main(request: func.HttpRequest) -> func.HttpResponse:
    from shared.config import load_settings
    from shared.queries import filter_records
    from shared.storage import ComparisonRepository

    settings = load_settings()
    repository = ComparisonRepository(settings)
    run_id = request.params.get('runId')
    records = repository.list_comparisons(partition_key=run_id or 'current')
    latest_run = repository.get_run(run_id) if run_id else repository.get_latest_run()
    filtered = filter_records(
        records,
        comparison_mode=request.params.get('comparisonMode'),
        source_region=request.params.get('sourceRegion'),
        target_region=request.params.get('targetRegion'),
        service_family=request.params.get('serviceFamily'),
        availability=request.params.get('availability'),
    )
    payload = _build_comparison_payload(filtered, latest_run)
    logger.info(
        'list_comparisons served run_id=%s count=%d latest_run_id=%s latest_run_status=%s',
        run_id or 'current',
        len(filtered),
        latest_run.row_key if latest_run else None,
        latest_run.status if latest_run else None,
    )
    return func.HttpResponse(
        json.dumps(payload),
        mimetype='application/json',
        status_code=200,
    )


def list_runs_main(request: func.HttpRequest) -> func.HttpResponse:
    from shared.config import load_settings
    from shared.storage import ComparisonRepository

    settings = load_settings()
    repository = ComparisonRepository(settings)
    limit = int(request.params.get('limit', '25'))
    comparison_mode = request.params.get('comparisonMode')
    runs = repository.list_runs(limit=limit, comparison_mode=comparison_mode)
    payload = _build_runs_payload(runs)
    logger.info(
        'list_runs served limit=%d comparison_mode=%s count=%d',
        limit,
        comparison_mode,
        len(runs),
    )
    return func.HttpResponse(
        json.dumps(payload),
        mimetype='application/json',
        status_code=200,
    )


def pricing_status_main(_: func.HttpRequest) -> func.HttpResponse:
    from shared.config import load_settings
    from shared.pricing import PricingClient

    settings = load_settings()
    payload = PricingClient(settings).get_private_pricing_status()
    logger.info('pricing_status served status=%s updated_at=%s', payload.get('status'), payload.get('updatedAt'))
    return func.HttpResponse(
        json.dumps(payload),
        mimetype='application/json',
        status_code=200,
    )


def pricing_hydrate_main(request: func.HttpRequest) -> func.HttpResponse:
    from shared.config import load_settings
    from shared.pricing import PricingClient

    settings = load_settings()
    force = str(request.params.get('force', 'false')).lower() in {'1', 'true', 'yes'}
    client = PricingClient(settings)
    try:
        payload = client.hydrate_private_pricing(force=force)
        status_code = 200
    except Exception as exc:
        logger.exception('pricing_hydrate failed')
        payload = client.get_private_pricing_status()
        payload.update(
            {
                'status': 'failed',
                'message': str(exc),
            }
        )
        status_code = 200

    logger.info('pricing_hydrate served status=%s force=%s', payload.get('status'), force)
    return func.HttpResponse(
        json.dumps(payload),
        mimetype='application/json',
        status_code=status_code,
    )


def health_check_main(_: func.HttpRequest) -> func.HttpResponse:
    from shared.config import load_settings
    from shared.pricing import PricingClient
    from shared.storage import ComparisonRepository

    settings = load_settings()
    repository = ComparisonRepository(settings)
    latest_run = repository.get_latest_run()
    pricing_status = PricingClient(settings).get_private_pricing_status()
    payload = {
        'status': 'ok',
        'cloudEnvironment': settings.cloud_environment,
        'comparisonTable': settings.comparison_table_name,
        'runsTable': settings.runs_table_name,
        'subscriptionId': settings.subscription_id,
        'defaultSourceRegion': settings.default_source_region,
        'defaultTargetRegion': settings.default_target_region,
        'retailPricingSupported': settings.retail_pricing_supported,
        'latestRunId': latest_run.row_key if latest_run else None,
        'latestRunStatus': latest_run.status if latest_run else None,
        'latestComparisonMode': latest_run.comparison_mode if latest_run else None,
        'pricingStatus': pricing_status.get('status'),
        'pricingUpdatedAt': pricing_status.get('updatedAt'),
    }
    logger.info(
        'health_check served status=%s latest_run_id=%s latest_run_status=%s comparison_table=%s runs_table=%s',
        payload['status'],
        payload['latestRunId'],
        payload['latestRunStatus'],
        payload['comparisonTable'],
        payload['runsTable'],
    )
    return func.HttpResponse(
        json.dumps(payload),
        mimetype='application/json',
        status_code=200,
    )