# Deployment diagnostics

The hosted deployment automatically creates one Log Analytics workspace and a workspace-based Application Insights component. Azure Monitor diagnostic settings send platform logs and metrics from both App Service apps, Azure Container Registry, and the blob, queue, and table storage services to that workspace.

## Resources and defaults

- The workspace uses the `PerGB2018` consumption SKU and 30-day retention.
- Application Insights uses Microsoft Entra authentication (`DisableLocalAuth`) and stores telemetry in the workspace.
- Web App, Function App, and Container Registry diagnostic settings collect the supported `allLogs` category group and `AllMetrics`.
- The `qa` Web App and Function App slots have separate diagnostic settings because slot diagnostics do not swap with application content.
- Storage diagnostic settings are attached to the blob, queue, and table service resource scopes—not the storage-account parent—so data-plane logs are collected. The deployment package blob service is included for deployment auditing.
- Names, locations, resource IDs, workspace customer ID, and diagnostic-setting IDs are returned as Bicep/`azd` deployment outputs.

Diagnostic settings can take several minutes to begin delivering records. Application telemetry and Azure resource logs use different workspace tables.

## Find the deployment outputs

```bash
azd env get-values | grep -Ei 'logAnalytics|applicationInsights'

az deployment group show \
  --resource-group <resource-group> \
  --name <deployment-name> \
  --query properties.outputs
```

To open the workspace in the current Azure cloud's portal, locate the `logAnalyticsWorkspaceName` output in the deployed resource group. No public-cloud portal hostname or ingestion endpoint is embedded in the infrastructure, which preserves sovereign-cloud deployment support.

## Starter queries

Run these in **Log Analytics workspace > Logs**:

```kusto
// Recent App Service and Function platform events
union isfuzzy=true AppServiceHTTPLogs, AppServiceConsoleLogs, AppServiceAppLogs,
  AppServicePlatformLogs, FunctionAppLogs
| where TimeGenerated > ago(1h)
| order by TimeGenerated desc
| take 100
```

```kusto
// Recent storage operations
StorageBlobLogs
| union isfuzzy=true StorageQueueLogs, StorageTableLogs
| where TimeGenerated > ago(1h)
| summarize Operations=count(), Failures=countif(toint(StatusCode) >= 400)
  by _ResourceId, OperationName
| order by Failures desc
```

```kusto
// Application Insights requests and failures
AppRequests
| where TimeGenerated > ago(1h)
| summarize Requests=count(), Failures=countif(Success == false),
  P95Duration=percentile(DurationMs, 95) by AppRoleName
```

Tables are created only after matching telemetry arrives. Use `search * | where TimeGenerated > ago(15m) | summarize count() by $table` to discover populated tables.

Filter slot telemetry by resource ID:

```kusto
union isfuzzy=true AppServiceHTTPLogs, AppServiceConsoleLogs, AppServiceAppLogs,
  AppServicePlatformLogs, FunctionAppLogs
| where TimeGenerated > ago(1h)
| extend DeploymentSlot = iff(_ResourceId has "/slots/qa", "qa", "prod")
| summarize Events=count() by DeploymentSlot, $table
```

## Operations and cost

- Review ingestion in **Log Analytics workspace > Usage and estimated costs** and set a daily cap or budget alert if required. A cap can cause loss of diagnostic data and is not enabled by default.
- Tune retention and categories to match organizational compliance requirements. Increasing retention improves investigation coverage but increases cost.
- For production, add Azure Monitor scheduled-query alerts and action groups for availability, failed requests, authentication failures, and ingestion health. Alert routing is intentionally environment-specific and is not provisioned by this baseline.

## References

- [Create a workspace-based Application Insights resource](https://learn.microsoft.com/azure/azure-monitor/app/create-workspace-resource)
- [Diagnostic settings in Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/platform/diagnostic-settings)
- [Supported Microsoft.Web/sites logs](https://learn.microsoft.com/azure/azure-monitor/reference/supported-logs/microsoft-web-sites-logs)
- [Supported Storage blob service logs](https://learn.microsoft.com/azure/azure-monitor/reference/supported-logs/microsoft-storage-storageaccounts-blobservices-logs)
- [Supported Azure Container Registry logs](https://learn.microsoft.com/azure/azure-monitor/reference/supported-logs/microsoft-containerregistry-registries-logs)
