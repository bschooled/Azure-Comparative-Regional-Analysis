from __future__ import annotations

import os
from dataclasses import dataclass

from azure.identity import AzureAuthorityHosts


DEFAULT_CLOUD_ENVIRONMENT = 'AzureCloud'

_CLOUD_ENDPOINTS = {
    'azurecloud': {
        'name': 'AzureCloud',
        'arm_endpoint': 'https://management.azure.com',
        'authority': AzureAuthorityHosts.AZURE_PUBLIC_CLOUD,
        'default_source_region': 'canadacentral',
        'default_target_region': 'eastus',
        'retail_pricing_supported': True,
    },
    'azureusgovernment': {
        'name': 'AzureUSGovernment',
        'arm_endpoint': 'https://management.usgovcloudapi.net',
        'authority': AzureAuthorityHosts.AZURE_GOVERNMENT,
        'default_source_region': 'usgovvirginia',
        'default_target_region': 'usgovarizona',
        'retail_pricing_supported': False,
    },
}


@dataclass(frozen=True)
class Settings:
    cloud_environment: str
    arm_endpoint: str
    management_scope: str
    credential_authority: str
    table_service_uri: str
    blob_service_uri: str | None
    comparison_table_name: str
    runs_table_name: str
    details_container_name: str
    refresh_schedule: str
    subscription_id: str
    default_source_region: str
    default_target_region: str
    pricing_container_name: str
    retail_prices_api_url: str
    retail_prices_api_version: str
    pricing_currency_code: str | None
    pricing_billing_account_name: str | None
    pricing_billing_profile_name: str | None
    pricing_billing_period_name: str | None
    pricing_billing_agreement_type: str | None
    retail_pricing_supported: bool

    def management_url(self, path: str) -> str:
        normalized_path = path if path.startswith('/') else f'/{path}'
        return f'{self.arm_endpoint}{normalized_path}'


def _normalized_cloud_environment(value: str | None) -> str:
    normalized = (value or DEFAULT_CLOUD_ENVIRONMENT).strip()
    if not normalized:
        return DEFAULT_CLOUD_ENVIRONMENT

    aliases = {
        'public': 'AzureCloud',
        'azurepubliccloud': 'AzureCloud',
        'azurepublic': 'AzureCloud',
        'usgov': 'AzureUSGovernment',
        'azuregovernment': 'AzureUSGovernment',
        'azuregov': 'AzureUSGovernment',
    }

    return aliases.get(normalized.lower(), normalized)


def _cloud_defaults(cloud_environment: str) -> dict[str, object]:
    normalized = _normalized_cloud_environment(cloud_environment)
    return _CLOUD_ENDPOINTS.get(normalized.lower(), _CLOUD_ENDPOINTS['azurecloud'])


def _require(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f'Missing required environment variable: {name}')
    return value


def load_settings() -> Settings:
    cloud_defaults = _cloud_defaults(os.getenv('AZURE_CLOUD_ENVIRONMENT') or os.getenv('CLOUD_ENVIRONMENT'))
    cloud_environment = str(cloud_defaults['name'])
    arm_endpoint = str(os.getenv('ARM_ENDPOINT') or cloud_defaults['arm_endpoint']).rstrip('/')
    management_scope = str(os.getenv('MANAGEMENT_SCOPE') or f'{arm_endpoint}/.default')
    credential_authority = str(os.getenv('AZURE_AUTHORITY_HOST') or cloud_defaults['authority'])

    return Settings(
        cloud_environment=cloud_environment,
        arm_endpoint=arm_endpoint,
        management_scope=management_scope,
        credential_authority=credential_authority,
        table_service_uri=_require('DATA_STORAGE__tableServiceUri'),
        blob_service_uri=os.getenv('BLOB_STORAGE__blobServiceUri'),
        comparison_table_name=os.getenv('COMPARISON_TABLE_NAME', 'CurrentComparisons'),
        runs_table_name=os.getenv('RUNS_TABLE_NAME', 'RefreshRuns'),
        details_container_name=os.getenv('DETAILS_CONTAINER_NAME', 'comparison-details'),
        refresh_schedule=os.getenv('REFRESH_SCHEDULE', '0 0 4 * * *'),
        subscription_id=_require('ANALYSIS_SUBSCRIPTION_ID'),
        default_source_region=os.getenv('ANALYSIS_SOURCE_REGION', str(cloud_defaults['default_source_region'])),
        default_target_region=os.getenv('ANALYSIS_TARGET_REGION', str(cloud_defaults['default_target_region'])),
        pricing_container_name=os.getenv('PRICING_CONTAINER_NAME', 'pricing-cache'),
        retail_prices_api_url=os.getenv('RETAIL_PRICES_API_URL', 'https://prices.azure.com/api/retail/prices'),
        retail_prices_api_version=os.getenv('RETAIL_PRICES_API_VERSION', '2023-01-01-preview'),
        pricing_currency_code=os.getenv('PRICING_CURRENCY_CODE'),
        pricing_billing_account_name=os.getenv('PRICING_BILLING_ACCOUNT_NAME'),
        pricing_billing_profile_name=os.getenv('PRICING_BILLING_PROFILE_NAME'),
        pricing_billing_period_name=os.getenv('PRICING_BILLING_PERIOD_NAME'),
        pricing_billing_agreement_type=os.getenv('PRICING_BILLING_AGREEMENT_TYPE'),
        retail_pricing_supported=bool(cloud_defaults['retail_pricing_supported']),
    )