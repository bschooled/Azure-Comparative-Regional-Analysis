from __future__ import annotations

from collections.abc import Iterable

from shared.models import ComparisonRecord


def filter_records(
    records: Iterable[ComparisonRecord],
    *,
    comparison_mode: str | None,
    source_region: str | None,
    target_region: str | None,
    service_family: str | None,
    availability: str | None,
) -> list[ComparisonRecord]:
    normalized_mode = None if not comparison_mode or comparison_mode == 'all' else comparison_mode.lower()
    normalized_family = None if not service_family or service_family == 'all' else service_family.lower()
    normalized_availability = None if not availability else availability.upper()

    filtered: list[ComparisonRecord] = []
    for record in records:
        if normalized_mode and record.comparison_mode.lower() != normalized_mode:
            continue
        if source_region and record.source_region != source_region:
            continue
        if target_region and record.target_region != target_region:
            continue
        if normalized_family and record.service_family.lower() != normalized_family:
            continue
        if normalized_availability and record.availability.upper() != normalized_availability:
            continue
        filtered.append(record)
    return filtered