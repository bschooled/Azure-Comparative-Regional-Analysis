from __future__ import annotations

import csv
import hashlib
import io
import json
import logging
import re
import time
import zipfile
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib import error, parse, request

from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from shared.config import Settings


logger = logging.getLogger(__name__)
PRIVATE_PRICING_STATUS_BLOB = 'private-pricing/status.json'
PRIVATE_PRICING_ARTIFACT_BLOB = 'private-pricing/latest.zip'
PRIVATE_PRICING_INDEX_BLOB = 'private-pricing/latest-index.json'
PRIVATE_PRICING_API_VERSION = '2025-03-01'
BILLING_API_VERSION = '2024-04-01'
RETAIL_PAGE_SIZE = 1000
RETAIL_COMPARISON_PAGE_SIZE = 5
RETAIL_CACHE_BLOB_PREFIX = 'retail-pricing'
RETAIL_CACHE_TTL = timedelta(hours=24)
RETAIL_STALE_FALLBACK_TTL = timedelta(days=7)
RETAIL_FAILURE_CACHE_TTL = timedelta(minutes=15)
RETAIL_MAX_RETRIES = 3
RETAIL_INITIAL_BACKOFF_SECONDS = 2
RETAIL_RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}
RETAIL_CACHE_SCHEMA_VERSION = 'v3'
SUPPORTED_PRIVATE_AGREEMENTS = {
    'enterpriseagreement',
    'microsoftcustomeragreement',
    'microsoftpartneragreement',
}


@dataclass(frozen=True)
class BillingScope:
    agreement_type: str
    billing_account_name: str
    billing_profile_name: str | None = None
    billing_period_name: str | None = None


class PricingStore:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._service: BlobServiceClient | None = None
        self._container_client = None
        self._container_checked = False
        if settings.blob_service_uri:
            self._service = BlobServiceClient(
                account_url=settings.blob_service_uri,
                credential=DefaultAzureCredential(authority=settings.credential_authority),
            )
            self._container_client = self._service.get_container_client(settings.pricing_container_name)

    @property
    def enabled(self) -> bool:
        return self._service is not None

    def _container(self):
        if self._container_client is None:
            raise RuntimeError('Blob storage is not configured for pricing cache.')
        return self._container_client

    def _ensure_container(self) -> None:
        container = self._container()
        if self._container_checked:
            return
        try:
            container.create_container()
        except ResourceExistsError:
            pass
        self._container_checked = True

    def write_json(self, blob_name: str, payload: dict[str, Any]) -> None:
        self._ensure_container()
        self._container().upload_blob(blob_name, json.dumps(payload, separators=(',', ':')).encode('utf-8'), overwrite=True)

    def read_json(self, blob_name: str) -> dict[str, Any] | None:
        try:
            payload = self._container().download_blob(blob_name).readall()
        except ResourceNotFoundError:
            return None
        try:
            return json.loads(payload.decode('utf-8'))
        except json.JSONDecodeError:
            return None

    def write_bytes(self, blob_name: str, payload: bytes, *, content_type: str) -> None:
        self._ensure_container()
        self._container().upload_blob(blob_name, payload, overwrite=True, content_type=content_type)


class PricingClient:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._credential = DefaultAzureCredential(authority=settings.credential_authority)
        self._store = PricingStore(settings)
        self._retail_cache: dict[tuple[str, str, str, str, str, str], dict[str, Any] | None] = {}
        self._retail_store_enabled = self._store.enabled
        self._prefetched_regions: set[str] = set()

    def _retail_cache_key(self, *, provider: str, service: str, sku: str, region: str, service_key: str) -> tuple[str, str, str, str, str, str]:
        return (
            RETAIL_CACHE_SCHEMA_VERSION,
            provider.lower(),
            service.lower(),
            sku.lower(),
            region.lower(),
            service_key.lower(),
        )

    def _access_token(self) -> str:
        return self._credential.get_token(self._settings.management_scope).token

    def _request_json(self, method: str, url: str, body: dict[str, Any] | None = None, headers: dict[str, str] | None = None) -> dict[str, Any]:
        payload = None if body is None else json.dumps(body).encode('utf-8')
        request_headers = {
            'Accept': 'application/json',
            **(headers or {}),
        }
        if body is not None:
            request_headers['Content-Type'] = 'application/json'
        response = request.urlopen(request.Request(url, data=payload, headers=request_headers, method=method), timeout=120)
        return json.loads(response.read().decode('utf-8'))

    def _request_bytes(self, url: str, headers: dict[str, str] | None = None) -> bytes:
        response = request.urlopen(request.Request(url, headers=headers or {}, method='GET'), timeout=300)
        return response.read()

    def _request_retail_json(self, url: str) -> dict[str, Any]:
        for attempt in range(RETAIL_MAX_RETRIES + 1):
            try:
                return self._request_json('GET', url)
            except error.HTTPError as exc:
                if exc.code not in RETAIL_RETRYABLE_STATUS_CODES or attempt >= RETAIL_MAX_RETRIES:
                    raise
                delay = _retail_retry_delay_seconds(exc.headers, attempt)
                logger.warning(
                    'Retail pricing request throttled status=%s retry_in=%ss attempt=%s/%s url=%s',
                    exc.code,
                    delay,
                    attempt + 1,
                    RETAIL_MAX_RETRIES + 1,
                    url,
                )
                time.sleep(delay)
            except error.URLError:
                if attempt >= RETAIL_MAX_RETRIES:
                    raise
                delay = RETAIL_INITIAL_BACKOFF_SECONDS * (2**attempt)
                logger.warning(
                    'Retail pricing request transient failure retry_in=%ss attempt=%s/%s url=%s',
                    delay,
                    attempt + 1,
                    RETAIL_MAX_RETRIES + 1,
                    url,
                )
                time.sleep(delay)

        raise RuntimeError('Retail pricing request exhausted retries without returning a response.')

    def _retail_items_from_url(self, url: str) -> list[dict[str, Any]]:
        collected: list[dict[str, Any]] = []
        next_url = url
        while next_url:
            response = self._request_retail_json(next_url)
            collected.extend(list(response.get('Items') or []))
            next_url = str(response.get('NextPageLink') or '').strip()
        return collected

    def _retail_cache_blob_name(self, cache_key: tuple[str, str, str, str, str, str]) -> str:
        digest = hashlib.sha256(json.dumps(cache_key, separators=(',', ':')).encode('utf-8')).hexdigest()
        return f'{RETAIL_CACHE_BLOB_PREFIX}/{digest}.json'

    def _retail_cache_entry(self, cache_key: tuple[str, str, str, str, str, str]) -> dict[str, Any] | None:
        cached = self._retail_cache.get(cache_key)
        if cached is not None:
            return cached

        if not self._retail_store_enabled:
            return None

        cached = self._store.read_json(self._retail_cache_blob_name(cache_key))
        if cached is not None:
            self._retail_cache[cache_key] = cached
        return cached

    def _write_retail_cache(
        self,
        cache_key: tuple[str, str, str, str, str, str],
        items: list[dict[str, Any]],
        *,
        ttl: timedelta = RETAIL_CACHE_TTL,
    ) -> None:
        now = datetime.now(UTC)
        payload = {
            'cachedAt': now.isoformat(),
            'expiresAt': (now + ttl).isoformat(),
            'items': items,
        }
        self._retail_cache[cache_key] = payload
        if self._retail_store_enabled:
            try:
                self._store.write_json(self._retail_cache_blob_name(cache_key), payload)
            except Exception as exc:
                self._retail_store_enabled = False
                logger.warning('Disabling blob-backed retail cache after write failure: %s', exc)

    def _management_json(self, method: str, url: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        return self._request_json(method, url, body, headers={'Authorization': f'Bearer {self._access_token()}'} )

    def _management_url(self, path: str) -> str:
        return self._settings.management_url(path)

    def prefetch_retail_region(self, *, region: str, entries: list[dict[str, Any]]) -> None:
        if not self._settings.retail_pricing_supported:
            self._prefetched_regions.add(region.lower())
            return

        region_key = region.lower()
        if region_key in self._prefetched_regions:
            return

        entry_queries: list[tuple[dict[str, Any], str]] = []
        for entry in entries:
            queries = _combine_retail_filters(
                _build_retail_filters(
                    provider=str(entry.get('provider') or ''),
                    service=str(entry.get('service') or ''),
                    sku=str(entry.get('sku') or ''),
                    region=region,
                    pricing_identity=entry.get('pricing_identity'),
                )
            )
            for query in queries:
                entry_queries.append((entry, query))

        unique_queries = [query for query in dict.fromkeys(query for _, query in entry_queries)]
        if not unique_queries:
            self._prefetched_regions.add(region_key)
            return

        prefetched_items: list[dict[str, Any]] = []
        had_prefetch_failure = False
        for batch_query in _batched_retail_filters(unique_queries):
            params = {
                'api-version': self._settings.retail_prices_api_version,
                '$filter': batch_query,
            }
            if self._settings.pricing_currency_code:
                params['currencyCode'] = self._settings.pricing_currency_code
            url = f'{self._settings.retail_prices_api_url}?{parse.urlencode(params)}'
            try:
                prefetched_items.extend(self._retail_items_from_url(url))
            except Exception as exc:
                had_prefetch_failure = True
                logger.warning('Retail pricing prefetch failed for region=%s query=%s: %s', region, batch_query, exc)

        for entry in entries:
            cache_key = self._retail_cache_key(
                provider=str(entry.get('provider') or ''),
                service=str(entry.get('service') or ''),
                sku=str(entry.get('sku') or ''),
                region=region_key,
                service_key=str((entry.get('pricing_identity') or {}).get('serviceKey') or ''),
            )
            matched_items: dict[tuple[str, str, str, str, str, str, str], dict[str, Any]] = {}
            for item in prefetched_items:
                if _retail_item_matches_identity(item, region=region, entry=entry):
                    matched_items.setdefault(_retail_item_key(item), item)
            if matched_items:
                self._write_retail_cache(cache_key, list(matched_items.values()))
                continue

            if had_prefetch_failure or not prefetched_items:
                continue

            self._write_retail_cache(cache_key, [])

        self._prefetched_regions.add(region_key)

    def get_private_pricing_status(self) -> dict[str, Any]:
        status = self._store.read_json(PRIVATE_PRICING_STATUS_BLOB) if self._store.enabled else None
        return status or {
            'status': 'not-configured' if not self._store.enabled else 'idle',
            'updatedAt': None,
            'agreementType': None,
            'billingAccountName': None,
            'billingProfileName': None,
            'billingPeriodName': None,
            'artifactBlob': PRIVATE_PRICING_ARTIFACT_BLOB if self._store.enabled else None,
            'indexBlob': PRIVATE_PRICING_INDEX_BLOB if self._store.enabled else None,
            'message': 'Private pricing has not been hydrated yet.',
        }

    def _write_status(self, payload: dict[str, Any]) -> None:
        if not self._store.enabled:
            return
        merged = {
            **self.get_private_pricing_status(),
            **payload,
            'updatedAt': datetime.now(UTC).isoformat(),
        }
        self._store.write_json(PRIVATE_PRICING_STATUS_BLOB, merged)

    def mark_private_pricing_failed(self, message: str, *, scope: BillingScope | None = None) -> dict[str, Any]:
        payload: dict[str, Any] = {
            'status': 'failed',
            'message': message,
        }
        if scope is not None:
            payload.update(
                {
                    'agreementType': scope.agreement_type,
                    'billingAccountName': scope.billing_account_name,
                    'billingProfileName': scope.billing_profile_name,
                    'billingPeriodName': scope.billing_period_name,
                }
            )
        self._write_status(payload)
        return self.get_private_pricing_status()

    def discover_billing_scope(self) -> BillingScope:
        configured_agreement = (self._settings.pricing_billing_agreement_type or '').strip()
        configured_account = (self._settings.pricing_billing_account_name or '').strip()
        configured_profile = (self._settings.pricing_billing_profile_name or '').strip()
        configured_period = (self._settings.pricing_billing_period_name or '').strip()

        if configured_account and configured_agreement:
            agreement_type = configured_agreement.lower()
            if agreement_type == 'enterpriseagreement':
                period_name = configured_period or datetime.now(UTC).strftime('%Y%m')
                return BillingScope(agreement_type=agreement_type, billing_account_name=configured_account, billing_period_name=period_name)
            return BillingScope(
                agreement_type=agreement_type,
                billing_account_name=configured_account,
                billing_profile_name=configured_profile or None,
            )

        accounts = self._management_json(
            'GET',
            self._management_url(f'/providers/Microsoft.Billing/billingAccounts?api-version={BILLING_API_VERSION}'),
        ).get('value', [])
        if not accounts:
            raise RuntimeError('No accessible billing accounts were returned by Microsoft.Billing.')

        for account in accounts:
            properties = account.get('properties', {})
            agreement_type = str(properties.get('agreementType', '')).strip().lower()
            account_name = str(account.get('name', '')).strip()
            if not account_name or agreement_type not in SUPPORTED_PRIVATE_AGREEMENTS:
                continue
            if agreement_type == 'enterpriseagreement':
                return BillingScope(
                    agreement_type=agreement_type,
                    billing_account_name=account_name,
                    billing_period_name=datetime.now(UTC).strftime('%Y%m'),
                )

            profiles = self._management_json(
                'GET',
                self._management_url(
                    f'/providers/Microsoft.Billing/billingAccounts/{parse.quote(account_name, safe="")}/billingProfiles?api-version={BILLING_API_VERSION}'
                ),
            ).get('value', [])
            if not profiles:
                continue
            profile_name = str(profiles[0].get('name', '')).strip()
            if profile_name:
                return BillingScope(
                    agreement_type=agreement_type,
                    billing_account_name=account_name,
                    billing_profile_name=profile_name,
                )

        raise RuntimeError('No accessible supported billing scope was discovered for private price-sheet hydration.')

    def hydrate_private_pricing(self, *, force: bool = False) -> dict[str, Any]:
        if not self._store.enabled:
            raise RuntimeError('Blob storage is required for private price-sheet hydration.')

        current = self.get_private_pricing_status()
        if current.get('status') == 'ready' and not force:
            return current

        self._write_status({'status': 'hydrating', 'message': 'Starting private price-sheet hydration.'})
        scope: BillingScope | None = None
        try:
            scope = self.discover_billing_scope()

            if scope.agreement_type == 'enterpriseagreement':
                url = self._management_url(
                    '/providers/Microsoft.Billing/billingAccounts/'
                    f'{parse.quote(scope.billing_account_name, safe="")}/billingPeriods/{parse.quote(scope.billing_period_name or datetime.now(UTC).strftime("%Y%m"), safe="")}'
                    f'/providers/Microsoft.CostManagement/pricesheets/default/download?api-version={PRIVATE_PRICING_API_VERSION}'
                )
            else:
                if not scope.billing_profile_name:
                    raise RuntimeError('Billing profile name is required for MCA/MPA price-sheet downloads.')
                url = self._management_url(
                    '/providers/Microsoft.Billing/billingAccounts/'
                    f'{parse.quote(scope.billing_account_name, safe="")}/billingProfiles/{parse.quote(scope.billing_profile_name, safe="")}'
                    f'/providers/Microsoft.CostManagement/pricesheets/default/download?api-version={PRIVATE_PRICING_API_VERSION}'
                )

            download_info = self._begin_price_sheet_download(url)
            download_url = str(download_info.get('downloadUrl') or download_info.get('properties', {}).get('reportUrl') or '')
            if not download_url:
                raise RuntimeError('Price-sheet download did not return a usable download URL.')

            artifact = self._request_bytes(download_url)
            self._store.write_bytes(PRIVATE_PRICING_ARTIFACT_BLOB, artifact, content_type='application/zip')
            normalized = self._normalize_price_sheet_archive(artifact)
            self._store.write_json(PRIVATE_PRICING_INDEX_BLOB, normalized)

            result = {
                'status': 'ready',
                'agreementType': scope.agreement_type,
                'billingAccountName': scope.billing_account_name,
                'billingProfileName': scope.billing_profile_name,
                'billingPeriodName': scope.billing_period_name,
                'artifactBlob': PRIVATE_PRICING_ARTIFACT_BLOB,
                'indexBlob': PRIVATE_PRICING_INDEX_BLOB,
                'recordCount': normalized.get('recordCount', 0),
                'message': 'Private price-sheet hydration completed.',
            }
            self._write_status(result)
            return self.get_private_pricing_status()
        except Exception as exc:
            self.mark_private_pricing_failed(str(exc), scope=scope)
            raise

    def _begin_price_sheet_download(self, url: str) -> dict[str, Any]:
        request_headers = {
            'Authorization': f'Bearer {self._access_token()}',
            'Accept': 'application/json',
        }
        req = request.Request(url, data=b'', headers=request_headers, method='POST')
        try:
            response = request.urlopen(req, timeout=120)
            payload = response.read().decode('utf-8')
            return json.loads(payload) if payload else {}
        except error.HTTPError as exc:
            if exc.code != 202:
                body = exc.read().decode('utf-8', errors='ignore')
                raise RuntimeError(f'Price-sheet request failed: HTTP {exc.code} {body}') from exc
            location = exc.headers.get('Location')
            if not location:
                raise RuntimeError('Price-sheet request returned 202 without a Location header.') from exc
            return self._poll_price_sheet_operation(location, request_headers)

    def _poll_price_sheet_operation(self, url: str, headers: dict[str, str]) -> dict[str, Any]:
        last_payload: dict[str, Any] = {}
        for _ in range(10):
            response = request.urlopen(request.Request(url, headers=headers, method='GET'), timeout=120)
            payload = json.loads(response.read().decode('utf-8'))
            last_payload = payload
            status = str(payload.get('status', '')).lower()
            if status in {'completed', 'succeeded'}:
                return payload
            if 'downloadUrl' in payload or 'properties' in payload:
                return payload
        return last_payload

    def _normalize_price_sheet_archive(self, payload: bytes) -> dict[str, Any]:
        normalized_rows: list[dict[str, Any]] = []
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            for name in archive.namelist():
                if not name.lower().endswith('.csv'):
                    continue
                with archive.open(name) as handle:
                    text_stream = io.TextIOWrapper(handle, encoding='utf-8-sig', newline='')
                    reader = csv.DictReader(text_stream)
                    for row in reader:
                        normalized = _normalize_price_sheet_row(row)
                        if normalized:
                            normalized_rows.append(normalized)
        return {
            'generatedAt': datetime.now(UTC).isoformat(),
            'recordCount': len(normalized_rows),
            'items': normalized_rows[:5000],
            'truncated': len(normalized_rows) > 5000,
        }

    def _retail_items(self, *, provider: str, service: str, sku: str, region: str, pricing_identity: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        if not self._settings.retail_pricing_supported:
            return []

        service_key = str((pricing_identity or {}).get('serviceKey') or '').lower()
        cache_key = self._retail_cache_key(provider=provider, service=service, sku=sku, region=region, service_key=service_key)
        cached_entry = self._retail_cache_entry(cache_key)
        stale_items: list[dict[str, Any]] | None = None
        if cached_entry is not None:
            cached_items = list(cached_entry.get('items') or [])
            expires_at = _parse_cache_datetime(cached_entry.get('expiresAt'))
            if expires_at is not None and expires_at > datetime.now(UTC):
                return cached_items
            cached_at = _parse_cache_datetime(cached_entry.get('cachedAt'))
            if cached_at is not None and cached_at + RETAIL_STALE_FALLBACK_TTL > datetime.now(UTC):
                stale_items = cached_items

        queries = _combine_retail_filters(
            _build_retail_filters(provider=provider, service=service, sku=sku, region=region, pricing_identity=pricing_identity)
        )
        if not queries:
            self._write_retail_cache(cache_key, [])
            return []

        deduped: dict[tuple[str, str, str, str, str, str, str], dict[str, Any]] = {}
        had_lookup_failure = False
        query_mode = str((pricing_identity or {}).get('pricing', {}).get('query_mode') or 'first-match').strip().lower()
        for query in queries:
            params = {
                'api-version': self._settings.retail_prices_api_version,
                '$filter': query,
            }
            if self._settings.pricing_currency_code:
                params['currencyCode'] = self._settings.pricing_currency_code

            url = f'{self._settings.retail_prices_api_url}?{parse.urlencode(params)}'
            try:
                items = self._retail_items_from_url(url)
            except Exception as exc:
                had_lookup_failure = True
                logger.warning('Retail pricing lookup failed for provider=%s sku=%s region=%s query=%s: %s', provider, sku, region, query, exc)
                continue

            for item in items:
                deduped.setdefault(_retail_item_key(item), item)
            if items and query_mode != 'merge':
                break

        items = list(deduped.values())
        if items:
            self._write_retail_cache(cache_key, items)
            return list(items)

        if stale_items is not None:
            self._write_retail_cache(cache_key, stale_items, ttl=RETAIL_FAILURE_CACHE_TTL)
            logger.info(
                'Using stale retail pricing cache for provider=%s sku=%s region=%s after live lookup returned no items.',
                provider,
                sku,
                region,
            )
            return list(stale_items)

        self._write_retail_cache(cache_key, [], ttl=RETAIL_FAILURE_CACHE_TTL if had_lookup_failure else RETAIL_CACHE_TTL)
        return []

    def retail_summary(self, *, provider: str, service: str, sku: str, region: str, pricing_identity: dict[str, Any] | None = None) -> dict[str, Any] | None:
        items = self._retail_items(provider=provider, service=service, sku=sku, region=region, pricing_identity=pricing_identity)
        if not items:
            return None

        choice = _select_retail_item(items)
        if choice is None:
            return None

        return _retail_summary_from_item(choice)

    def retail_comparison(
        self,
        *,
        provider: str,
        service: str,
        sku: str,
        source_region: str,
        target_region: str,
        pricing_identity: dict[str, Any] | None = None,
        limit: int | None = None,
    ) -> dict[str, Any] | None:
        source_items = self._retail_items(provider=provider, service=service, sku=sku, region=source_region, pricing_identity=pricing_identity)
        target_items = self._retail_items(provider=provider, service=service, sku=sku, region=target_region, pricing_identity=pricing_identity)
        if not source_items and not target_items:
            return None

        source_lookup = _index_retail_items(source_items)
        target_lookup = _index_retail_items(target_items)
        ranked_keys = _rank_retail_comparison_keys(source_lookup, target_lookup)
        limited_keys = ranked_keys if limit is None else ranked_keys[:max(1, limit)]
        comparison_items = [
            _build_retail_comparison_item(key, source_lookup.get(key), target_lookup.get(key), source_region=source_region, target_region=target_region)
            for key in limited_keys
        ]
        currencies = {
            currency
            for currency in [
                *[str(item.get('currencyCode') or '') for item in comparison_items],
                str(_retail_summary_from_item(_select_retail_item(source_items) or {}).get('currencyCode') or '') if source_items else '',
                str(_retail_summary_from_item(_select_retail_item(target_items) or {}).get('currencyCode') or '') if target_items else '',
            ]
            if currency
        }
        source_best = self.retail_summary(provider=provider, service=service, sku=sku, region=source_region, pricing_identity=pricing_identity)
        target_best = self.retail_summary(provider=provider, service=service, sku=sku, region=target_region, pricing_identity=pricing_identity)
        return {
            'source': 'retail',
            'sourceRegion': source_region,
            'targetRegion': target_region,
            'pageSize': RETAIL_COMPARISON_PAGE_SIZE,
            'totalItems': len(ranked_keys),
            'returnedItems': len(comparison_items),
            'truncated': len(ranked_keys) > len(comparison_items),
            'currencyCode': next(iter(currencies), (source_best or target_best or {}).get('currencyCode')),
            'sourceBest': source_best,
            'targetBest': target_best,
            'items': comparison_items,
        }


def _retail_summary_from_item(choice: dict[str, Any]) -> dict[str, Any]:
    return {
        'source': 'retail',
        'serviceName': choice.get('serviceName'),
        'serviceFamily': choice.get('serviceFamily'),
        'productName': choice.get('productName'),
        'skuName': choice.get('skuName'),
        'meterName': choice.get('meterName'),
        'meterId': choice.get('meterId'),
        'armSkuName': choice.get('armSkuName'),
        'armRegionName': choice.get('armRegionName'),
        'unitOfMeasure': choice.get('unitOfMeasure'),
        'retailPrice': choice.get('retailPrice'),
        'currencyCode': choice.get('currencyCode'),
        'priceType': choice.get('type') or choice.get('priceType'),
        'reservationTerm': choice.get('reservationTerm'),
        'savingsPlan': choice.get('savingsPlan'),
        'isPrimaryMeterRegion': choice.get('isPrimaryMeterRegion'),
    }


def _retail_item_key(item: dict[str, Any]) -> tuple[str, str, str, str, str, str, str]:
    return (
        str(item.get('meterName') or '').strip().lower(),
        str(item.get('productName') or '').strip().lower(),
        str(item.get('skuName') or '').strip().lower(),
        str(item.get('armSkuName') or '').strip().lower(),
        str(item.get('unitOfMeasure') or '').strip().lower(),
        str(item.get('type') or item.get('priceType') or '').strip().lower(),
        str(item.get('reservationTerm') or '').strip().lower(),
    )


def _index_retail_items(items: list[dict[str, Any]]) -> dict[tuple[str, str, str, str, str, str, str], dict[str, Any]]:
    indexed: dict[tuple[str, str, str, str, str, str, str], dict[str, Any]] = {}
    for item in sorted(items, key=_retail_item_sort_key):
        key = _retail_item_key(item)
        if not any(key):
            continue
        indexed.setdefault(key, item)
    return indexed


def _retail_item_sort_key(item: dict[str, Any]) -> tuple[int, int, float, str]:
    price_type = str(item.get('type') or item.get('priceType') or '')
    return (
        0 if price_type == 'Consumption' else 1,
        0 if item.get('isPrimaryMeterRegion') else 1,
        float(item.get('retailPrice') or item.get('unitPrice') or 0.0),
        str(item.get('meterName') or ''),
    )


def _rank_retail_comparison_keys(
    source_lookup: dict[tuple[str, str, str, str, str, str, str], dict[str, Any]],
    target_lookup: dict[tuple[str, str, str, str, str, str, str], dict[str, Any]],
) -> list[tuple[str, str, str, str, str, str, str]]:
    combined = set(source_lookup) | set(target_lookup)

    def sort_key(key: tuple[str, str, str, str, str, str, str]) -> tuple[int, int, int, float, str, str, str]:
        source_item = source_lookup.get(key)
        target_item = target_lookup.get(key)
        matched = 0 if source_item and target_item else 1
        available = 0 if source_item or target_item else 1
        price_type = str((source_item or target_item or {}).get('type') or (source_item or target_item or {}).get('priceType') or '')
        type_rank = 0 if price_type == 'Consumption' else 1 if price_type == 'Reservation' else 2
        source_price = _coerce_price(source_item)
        target_price = _coerce_price(target_item)
        lowest_price = min(price for price in [source_price, target_price] if price is not None) if any(price is not None for price in [source_price, target_price]) else float('inf')
        name = str((source_item or target_item or {}).get('meterName') or '')
        product = str((source_item or target_item or {}).get('productName') or '')
        reservation_term = str((source_item or target_item or {}).get('reservationTerm') or '')
        return (matched, available, type_rank, lowest_price, reservation_term, product, name)

    return sorted(combined, key=sort_key)


def _coerce_price(item: dict[str, Any] | None) -> float | None:
    if not item:
        return None
    raw_value = item.get('retailPrice') or item.get('unitPrice')
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return None


def _build_retail_comparison_item(
    key: tuple[str, str, str, str, str, str, str],
    source_item: dict[str, Any] | None,
    target_item: dict[str, Any] | None,
    *,
    source_region: str,
    target_region: str,
) -> dict[str, Any]:
    source_price = _coerce_price(source_item)
    target_price = _coerce_price(target_item)
    delta = None if source_price is None or target_price is None else target_price - source_price
    cheaper_region = None
    if source_price is not None and target_price is not None:
        if source_price < target_price:
            cheaper_region = source_region
        elif target_price < source_price:
            cheaper_region = target_region
        else:
            cheaper_region = 'same'

    reference = source_item or target_item or {}
    return {
        'key': '|'.join(key),
        'label': str(reference.get('meterName') or reference.get('skuName') or reference.get('productName') or 'Meter'),
        'meterId': reference.get('meterId'),
        'meterName': reference.get('meterName'),
        'productName': reference.get('productName'),
        'skuName': reference.get('skuName'),
        'armSkuName': reference.get('armSkuName'),
        'unitOfMeasure': reference.get('unitOfMeasure'),
        'currencyCode': reference.get('currencyCode'),
        'sourcePrice': source_price,
        'targetPrice': target_price,
        'sourceAvailable': source_price is not None,
        'targetAvailable': target_price is not None,
        'delta': delta,
        'deltaPercent': None if delta is None or not source_price else (delta / source_price) * 100,
        'cheaperRegion': cheaper_region,
        'sourceMeterName': source_item.get('meterName') if source_item else None,
        'targetMeterName': target_item.get('meterName') if target_item else None,
        'sourceMeterId': source_item.get('meterId') if source_item else None,
        'targetMeterId': target_item.get('meterId') if target_item else None,
        'sourceArmSkuName': source_item.get('armSkuName') if source_item else None,
        'targetArmSkuName': target_item.get('armSkuName') if target_item else None,
        'sourcePriceType': source_item.get('type') or source_item.get('priceType') if source_item else None,
        'targetPriceType': target_item.get('type') or target_item.get('priceType') if target_item else None,
        'sourceReservationTerm': source_item.get('reservationTerm') if source_item else None,
        'targetReservationTerm': target_item.get('reservationTerm') if target_item else None,
        'sourceSavingsPlan': source_item.get('savingsPlan') if source_item else None,
        'targetSavingsPlan': target_item.get('savingsPlan') if target_item else None,
    }


def _normalize_price_sheet_row(row: dict[str, Any]) -> dict[str, Any] | None:
    lowered = {str(key).strip().lower(): value for key, value in row.items()}
    meter_id = str(lowered.get('meterid') or lowered.get('meter id') or '').strip()
    unit_price = str(lowered.get('unitprice') or lowered.get('unit price') or '').strip()
    meter_name = str(lowered.get('metername') or lowered.get('meter name') or '').strip()
    if not meter_id and not meter_name:
        return None
    return {
        'meterId': meter_id or None,
        'meterName': meter_name or None,
        'product': str(lowered.get('product') or lowered.get('productname') or lowered.get('product name') or '').strip() or None,
        'productId': str(lowered.get('productid') or lowered.get('product id') or '').strip() or None,
        'skuId': str(lowered.get('skuid') or lowered.get('sku id') or '').strip() or None,
        'skuName': str(lowered.get('skuname') or lowered.get('sku name') or '').strip() or None,
        'unitOfMeasure': str(lowered.get('unitofmeasure') or lowered.get('unit of measure') or '').strip() or None,
        'unitPrice': unit_price or None,
        'currency': str(lowered.get('currency') or lowered.get('billingcurrency') or '').strip() or None,
        'meterRegion': str(lowered.get('meterregion') or lowered.get('meter region') or '').strip() or None,
        'serviceFamily': str(lowered.get('servicefamily') or lowered.get('service family') or '').strip() or None,
        'priceType': str(lowered.get('pricetype') or lowered.get('price type') or '').strip() or None,
    }


def _quote_retail_value(value: str) -> str:
    return re.sub(r"'", "''", str(value or ''))


def _parse_cache_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value))
    except ValueError:
        return None


def _retail_retry_delay_seconds(headers: Any, attempt: int) -> int:
    retry_after = None
    if headers is not None:
        retry_after = headers.get('x-ms-ratelimit-microsoft.consumption-retry-after') or headers.get('Retry-After')
    if retry_after is not None:
        try:
            return max(1, int(str(retry_after).strip()))
        except ValueError:
            pass
    return RETAIL_INITIAL_BACKOFF_SECONDS * (2**attempt)


def _build_retail_filter_from_spec(*, spec: dict[str, Any], sku: str, region: str) -> str | None:
    region_value = region.lower()
    parts = [f"armRegionName eq '{region_value}'"]

    service_family = str(spec.get('service_family') or '').strip()
    service_name = str(spec.get('service_name') or '').strip()
    product_name = str(spec.get('product_name') or '').strip()
    product_name_contains = str(spec.get('product_name_contains') or '').strip()
    price_type = str(spec.get('price_type') or '').strip()

    if service_family:
        parts.append(f"serviceFamily eq '{_quote_retail_value(service_family)}'")
    if service_name:
        parts.append(f"serviceName eq '{_quote_retail_value(service_name)}'")
    if product_name:
        parts.append(f"productName eq '{_quote_retail_value(product_name)}'")
    if product_name_contains:
        parts.append(f"contains(productName,'{_quote_retail_value(product_name_contains)}')")
    if price_type:
        parts.append(f"priceType eq '{_quote_retail_value(price_type)}'")
    if sku:
        safe_sku = _quote_retail_value(sku)
        parts.append(f"(armSkuName eq '{safe_sku}' or skuName eq '{safe_sku}')")
    return ' and '.join(parts) if parts else None


def _build_retail_filters(*, provider: str, service: str, sku: str, region: str, pricing_identity: dict[str, Any] | None = None) -> list[str]:
    if pricing_identity:
        pricing = pricing_identity.get('pricing') or {}
        filters: list[str] = []
        for spec in pricing.get('filters') or []:
            filter_query = _build_retail_filter_from_spec(spec=spec, sku=sku, region=region)
            if filter_query:
                filters.append(filter_query)
        if not filters:
            for service_name in pricing.get('serviceNames') or []:
                filter_query = _build_retail_filter_from_spec(spec={'service_name': service_name}, sku=sku, region=region)
                if filter_query:
                    filters.append(filter_query)
            for product_name in pricing.get('productNames') or []:
                filter_query = _build_retail_filter_from_spec(spec={'product_name_contains': product_name}, sku=sku, region=region)
                if filter_query:
                    filters.append(filter_query)
            if sku:
                for service_family in pricing.get('serviceFamilies') or []:
                    filter_query = _build_retail_filter_from_spec(spec={'service_family': service_family}, sku=sku, region=region)
                    if filter_query:
                        filters.append(filter_query)

        deduped: list[str] = []
        seen: set[str] = set()
        for filter_query in filters:
            if filter_query in seen:
                continue
            seen.add(filter_query)
            deduped.append(filter_query)
        if deduped:
            return deduped

    provider_key = provider.lower()
    region_value = region.lower()
    normalized_service = re.sub(r'^azure\s+', '', service or '', flags=re.IGNORECASE).strip()
    if provider_key == 'microsoft.compute/virtualmachines' and sku:
        return [
            f"serviceName eq 'Virtual Machines' and armRegionName eq '{region_value}' and armSkuName eq '{sku}' and priceType eq 'Consumption'"
        ]
    if provider_key == 'microsoft.compute/disks' and sku:
        return [
            f"serviceFamily eq 'Storage' and armRegionName eq '{region_value}' and (armSkuName eq '{sku}' or skuName eq '{sku}')"
        ]
    if provider_key == 'microsoft.storage/storageaccounts' and sku:
        return [
            f"serviceFamily eq 'Storage' and armRegionName eq '{region_value}' and armSkuName eq '{sku}'"
        ]
    if provider_key.startswith('microsoft.network') and sku:
        return [
            f"serviceFamily eq 'Networking' and armRegionName eq '{region_value}' and (armSkuName eq '{sku}' or skuName eq '{sku}')"
        ]
    if provider_key.startswith('microsoft.sql') and sku:
        return [
            f"serviceFamily eq 'Databases' and armRegionName eq '{region_value}' and (armSkuName eq '{sku}' or skuName eq '{sku}')"
        ]
    if provider_key.startswith('microsoft.cache') and sku:
        return [
            f"serviceFamily eq 'Databases' and armRegionName eq '{region_value}' and (armSkuName eq '{sku}' or skuName eq '{sku}')"
        ]
    if provider_key.startswith('microsoft.web/serverfarms') and sku:
        return [
            f"serviceFamily eq 'Web' and armRegionName eq '{region_value}' and (armSkuName eq '{sku}' or skuName eq '{sku}')"
        ]
    if provider_key.startswith('microsoft.web') and service:
        safe_service = re.sub(r"'", "''", service)
        return [f"serviceFamily eq 'Web' and armRegionName eq '{region_value}' and serviceName eq '{safe_service}'"]
    if provider_key.startswith('microsoft.apimanagement'):
        return [f"serviceName eq 'API Management' and armRegionName eq '{region_value}'"]
    if provider_key.startswith('microsoft.cache') and not sku:
        return [f"serviceName eq 'Azure Cache for Redis' and armRegionName eq '{region_value}'"]
    if provider_key.startswith('microsoft.operationalinsights'):
        return [f"serviceName eq 'Log Analytics' and armRegionName eq '{region_value}'"]
    if provider_key.startswith('microsoft.insights'):
        return [f"serviceName eq 'Azure Monitor' and armRegionName eq '{region_value}'"]
    if normalized_service:
        safe_service = re.sub(r"'", "''", normalized_service)
        return [f"serviceName eq '{safe_service}' and armRegionName eq '{region_value}'"]
    return []


def _combine_retail_filters(filters: list[str]) -> list[str]:
    deduped: list[str] = []
    seen: set[str] = set()
    for filter_query in filters:
        normalized = str(filter_query or '').strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        deduped.append(normalized)

    if len(deduped) <= 1:
        return deduped

    # The Retail Prices API rejects some compound OData filters that mix
    # repeated contains(...) clauses with OR. Keep those as individual lookups
    # and let the caller merge the result sets.
    if any('contains(' in filter_query for filter_query in deduped):
        return deduped

    return [' or '.join(f'({filter_query})' for filter_query in deduped)]


def _batched_retail_filters(filters: list[str], *, max_clauses: int = 12, max_length: int = 7000) -> list[str]:
    deduped: list[str] = []
    seen: set[str] = set()
    for filter_query in filters:
        normalized = str(filter_query or '').strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        deduped.append(normalized)
    if len(deduped) <= 1:
        return deduped

    batches: list[str] = []
    current: list[str] = []
    current_length = 0
    for filter_query in deduped:
        clause = f'({filter_query})'
        projected_length = current_length + len(clause) + (4 if current else 0)
        if current and (len(current) >= max_clauses or projected_length > max_length):
            batches.append(' or '.join(current))
            current = [clause]
            current_length = len(clause)
            continue
        current.append(clause)
        current_length = projected_length if len(current) > 1 else len(clause)

    if current:
        batches.append(' or '.join(current))
    return batches


def _item_text(value: Any) -> str:
    return str(value or '').strip()


def _retail_item_matches_spec(item: dict[str, Any], *, spec: dict[str, Any], sku: str, region: str) -> bool:
    if _item_text(item.get('armRegionName')).lower() != region.lower():
        return False

    service_family = _item_text(spec.get('service_family'))
    service_name = _item_text(spec.get('service_name'))
    product_name = _item_text(spec.get('product_name'))
    product_name_contains = _item_text(spec.get('product_name_contains'))
    price_type = _item_text(spec.get('price_type'))

    if service_family and _item_text(item.get('serviceFamily')) != service_family:
        return False
    if service_name and _item_text(item.get('serviceName')) != service_name:
        return False
    if product_name and _item_text(item.get('productName')) != product_name:
        return False
    if product_name_contains and product_name_contains not in _item_text(item.get('productName')):
        return False
    if price_type and _item_text(item.get('priceType') or item.get('type')) != price_type:
        return False
    if sku:
        item_arm_sku = _item_text(item.get('armSkuName'))
        item_sku = _item_text(item.get('skuName'))
        if sku not in {item_arm_sku, item_sku}:
            return False
    return True


def _retail_item_matches_identity(item: dict[str, Any], *, region: str, entry: dict[str, Any]) -> bool:
    pricing_identity = entry.get('pricing_identity') or {}
    pricing = pricing_identity.get('pricing') or {}
    sku = str(entry.get('sku') or '')

    for spec in pricing.get('filters') or []:
        if _retail_item_matches_spec(item, spec=spec, sku=sku, region=region):
            return True

    service_names = list(pricing.get('serviceNames') or [])
    product_names = list(pricing.get('productNames') or [])
    service_families = list(pricing.get('serviceFamilies') or [])

    fallback_specs: list[dict[str, Any]] = []
    for service_name in service_names:
        fallback_specs.append({'service_name': service_name})
    for product_name in product_names:
        fallback_specs.append({'product_name_contains': product_name})
    if sku:
        for service_family in service_families:
            fallback_specs.append({'service_family': service_family})

    for spec in fallback_specs:
        if _retail_item_matches_spec(item, spec=spec, sku=sku, region=region):
            return True
    return False


def _select_retail_item(items: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not items:
        return None

    return sorted(items, key=_retail_item_sort_key)[0]