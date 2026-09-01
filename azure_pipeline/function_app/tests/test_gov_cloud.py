from __future__ import annotations

import importlib
import os
import sys
import types
import unittest
from contextlib import contextmanager


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def _install_azure_functions_stub() -> None:
    try:
        import azure as azure_module  # type: ignore
    except ImportError:
        azure_module = types.ModuleType('azure')

    if 'azure.identity' not in sys.modules:
        identity_module = types.ModuleType('azure.identity')

        class AzureAuthorityHosts:  # pragma: no cover - stub constant container
            AZURE_PUBLIC_CLOUD = 'https://login.microsoftonline.com'
            AZURE_GOVERNMENT = 'https://login.microsoftonline.us'

        identity_module.AzureAuthorityHosts = AzureAuthorityHosts
        azure_module.identity = identity_module
        sys.modules['azure.identity'] = identity_module

    if 'azure.functions' in sys.modules:
        sys.modules['azure'] = azure_module
        return

    functions_module = types.ModuleType('azure.functions')

    class HttpRequest:  # pragma: no cover - stub type for imports only
        params: dict[str, str] = {}

        def get_json(self):
            return {}

    class HttpResponse:  # pragma: no cover - stub type for imports only
        def __init__(self, body=None, *, mimetype=None, status_code=200):
            self.body = body
            self.mimetype = mimetype
            self.status_code = status_code

    class TimerRequest:  # pragma: no cover - stub type for imports only
        past_due = False

    functions_module.HttpRequest = HttpRequest
    functions_module.HttpResponse = HttpResponse
    functions_module.TimerRequest = TimerRequest
    azure_module.functions = functions_module

    sys.modules['azure'] = azure_module
    sys.modules['azure.functions'] = functions_module


@contextmanager
def environment(overrides: dict[str, str | None]):
    original = {key: os.environ.get(key) for key in overrides}
    try:
        for key, value in overrides.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        yield
    finally:
        for key, value in original.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


class GovCloudSettingsTests(unittest.TestCase):
    def setUp(self) -> None:
        _install_azure_functions_stub()

    def test_load_settings_uses_gov_defaults(self) -> None:
        from shared import config

        with environment(
            {
                'AZURE_CLOUD_ENVIRONMENT': 'AzureUSGovernment',
                'DATA_STORAGE__tableServiceUri': 'https://example.table.core.usgovcloudapi.net',
                'ANALYSIS_SUBSCRIPTION_ID': '00000000-0000-0000-0000-000000000000',
                'ANALYSIS_SOURCE_REGION': None,
                'ANALYSIS_TARGET_REGION': None,
            }
        ):
            importlib.reload(config)
            settings = config.load_settings()

        self.assertEqual(settings.cloud_environment, 'AzureUSGovernment')
        self.assertEqual(settings.arm_endpoint, 'https://management.usgovcloudapi.net')
        self.assertEqual(settings.management_scope, 'https://management.usgovcloudapi.net/.default')
        self.assertEqual(settings.default_source_region, 'usgovvirginia')
        self.assertEqual(settings.default_target_region, 'usgovarizona')
        self.assertFalse(settings.retail_pricing_supported)

    def test_public_cloud_rejects_gov_regions(self) -> None:
        import handlers

        settings = types.SimpleNamespace(cloud_environment='AzureCloud')
        with self.assertRaisesRegex(ValueError, 'Azure Government regions require'):
            handlers._validate_region_cloud_alignment(settings, 'usgovvirginia', 'eastus')

    def test_gov_cloud_rejects_public_regions(self) -> None:
        import handlers

        settings = types.SimpleNamespace(cloud_environment='AzureUSGovernment')
        with self.assertRaisesRegex(ValueError, 'only support Azure Government regions'):
            handlers._validate_region_cloud_alignment(settings, 'eastus', 'usgovarizona')

    def test_gov_cloud_accepts_gov_regions(self) -> None:
        import handlers

        settings = types.SimpleNamespace(cloud_environment='AzureUSGovernment')
        handlers._validate_region_cloud_alignment(settings, 'usgovvirginia', 'usgovarizona')


if __name__ == '__main__':
    unittest.main()