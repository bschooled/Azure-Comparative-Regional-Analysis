from __future__ import annotations

from typing import Iterable

from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.data.tables import TableServiceClient, UpdateMode
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from shared.config import Settings
from shared.models import (
    ComparisonRecord,
    DETAILS_JSON_BLOB_FIELD,
    MAX_TABLE_STRING_CHARS,
    RefreshRun,
    _merge_chunked_details,
)


class ComparisonRepository:
    def __init__(self, settings: Settings) -> None:
        credential = DefaultAzureCredential(authority=settings.credential_authority)
        self._settings = settings
        self._comparison_table = TableServiceClient(
            endpoint=settings.table_service_uri,
            credential=credential,
        ).get_table_client(settings.comparison_table_name)
        self._runs_table = TableServiceClient(
            endpoint=settings.table_service_uri,
            credential=credential,
        ).get_table_client(settings.runs_table_name)
        self._details_container = None
        self._details_container_checked = False
        if settings.blob_service_uri:
            self._details_container = BlobServiceClient(
                account_url=settings.blob_service_uri,
                credential=credential,
            ).get_container_client(settings.details_container_name)

    def _ensure_details_container(self) -> None:
        if self._details_container is None or self._details_container_checked:
            return
        try:
            self._details_container.create_container()
        except ResourceExistsError:
            pass
        self._details_container_checked = True

    def _details_blob_name(self, *, partition_key: str, row_key: str, run_id: str) -> str:
        return f'{partition_key}/{run_id}/{row_key}.json'

    def _details_blob_write(self, *, blob_name: str, details_json: str) -> None:
        if self._details_container is None:
            return
        self._ensure_details_container()
        self._details_container.upload_blob(blob_name, details_json.encode('utf-8'), overwrite=True, content_type='application/json')

    def _details_blob_read(self, blob_name: str) -> str | None:
        if self._details_container is None or not blob_name:
            return None
        try:
            payload = self._details_container.download_blob(blob_name).readall()
        except ResourceNotFoundError:
            return None
        try:
            return payload.decode('utf-8')
        except UnicodeDecodeError:
            return None

    def _details_blob_delete(self, blob_name: str) -> None:
        if self._details_container is None or not blob_name:
            return
        try:
            self._details_container.delete_blob(blob_name)
        except Exception:
            pass

    def upsert_comparisons(self, records: Iterable[ComparisonRecord]) -> None:
        for record in records:
            entity = record.as_entity()
            if record.details_json and len(record.details_json) > MAX_TABLE_STRING_CHARS and self._details_container is not None:
                blob_name = self._details_blob_name(
                    partition_key=record.partition_key,
                    row_key=record.row_key,
                    run_id=record.run_id,
                )
                self._details_blob_write(blob_name=blob_name, details_json=record.details_json)
                entity[DETAILS_JSON_BLOB_FIELD] = blob_name
            self._comparison_table.upsert_entity(entity, mode=UpdateMode.REPLACE)

    def replace_current_comparisons(self, records: Iterable[ComparisonRecord]) -> None:
        existing = list(self._comparison_table.query_entities(query_filter="PartitionKey eq 'current'"))
        for entity in existing:
            self._details_blob_delete(str(entity.get(DETAILS_JSON_BLOB_FIELD) or ''))
            self._comparison_table.delete_entity(entity['PartitionKey'], entity['RowKey'])
        self.upsert_comparisons(records)

    def list_comparisons(self, *, partition_key: str = 'current') -> list[ComparisonRecord]:
        records: list[ComparisonRecord] = []
        entities = self._comparison_table.query_entities(query_filter=f"PartitionKey eq '{partition_key}'")
        for entity in entities:
            details_json = _merge_chunked_details(entity)
            blob_name = str(entity.get(DETAILS_JSON_BLOB_FIELD) or '')
            blob_details_json = self._details_blob_read(blob_name)
            if blob_details_json:
                details_json = blob_details_json
            records.append(
                ComparisonRecord(
                    partition_key=entity['PartitionKey'],
                    row_key=entity['RowKey'],
                    comparison_mode=entity.get('comparison_mode', 'inventory'),
                    service=entity['service'],
                    provider=entity['provider'],
                    service_family=entity['service_family'],
                    canonical_service_id=str(entity.get('canonical_service_id', '') or ''),
                    canonical_service_name=str(entity.get('canonical_service_name', '') or ''),
                    identity_source=str(entity.get('identity_source', '') or ''),
                    is_fallback_identity=bool(entity.get('is_fallback_identity', False)),
                    source_region=entity['source_region'],
                    target_region=entity['target_region'],
                    availability=entity['availability'],
                    notes=entity['notes'],
                    details_json=details_json,
                    refreshed_at=entity['refreshed_at'],
                    run_id=entity['run_id'],
                )
            )
        return records

    def upsert_run(self, run: RefreshRun) -> None:
        self._runs_table.upsert_entity(run.as_entity())

    def get_run(self, run_id: str) -> RefreshRun | None:
        try:
            entity = self._runs_table.get_entity(partition_key='runs', row_key=run_id)
        except Exception:
            return None

        return RefreshRun(
            partition_key=str(entity['PartitionKey']),
            row_key=str(entity['RowKey']),
            comparison_mode=str(entity.get('comparison_mode', 'inventory')),
            subscription_id=str(entity.get('subscription_id', '')),
            source_region=str(entity.get('source_region', '')),
            target_region=str(entity.get('target_region', '')),
            status=str(entity['status']),
            reason=str(entity['reason']),
            started_at=str(entity['started_at']),
            completed_at=str(entity['completed_at']),
            record_count=int(entity['record_count']),
        )

    def list_runs(self, *, limit: int = 25, comparison_mode: str | None = None) -> list[RefreshRun]:
        runs: list[RefreshRun] = []
        for entity in self._runs_table.query_entities(query_filter="PartitionKey eq 'runs'"):
            run = RefreshRun(
                partition_key=str(entity['PartitionKey']),
                row_key=str(entity['RowKey']),
                comparison_mode=str(entity.get('comparison_mode', 'inventory')),
                subscription_id=str(entity.get('subscription_id', '')),
                source_region=str(entity.get('source_region', '')),
                target_region=str(entity.get('target_region', '')),
                status=str(entity['status']),
                reason=str(entity['reason']),
                started_at=str(entity['started_at']),
                completed_at=str(entity['completed_at']),
                record_count=int(entity['record_count']),
            )
            if comparison_mode and run.comparison_mode != comparison_mode:
                continue
            runs.append(run)

        runs.sort(key=lambda item: item.row_key, reverse=True)
        return runs[:limit]

    def get_latest_run(self) -> RefreshRun | None:
        runs = self.list_runs(limit=1)
        if not runs:
            return None

        return runs[0]