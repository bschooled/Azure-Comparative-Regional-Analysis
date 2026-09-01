# Foundry Pricing API Examples

> 🧪 Query the same Azure APIs used by the Foundry Model Pricing Toolkit
> without running the collector.

These examples are useful for troubleshooting, inspecting raw responses, or
building another integration. They use generic names and do not depend on the
rest of this repository.

## ⚠️ What each API can tell you

| API | Best used for | Important limitation |
|---|---|---|
| Azure Retail Prices | Public list prices and meter metadata | Does not prove that a model can be deployed in a region |
| Regional Models | Model versions, deployment SKUs, and SKU capacity ranges | Does not guarantee that quota or physical capacity is currently available |
| Regional Usages | Subscription quota limits and current usage | Quota availability is not the same as deployment capacity |
| Commerce Rate Card | Authenticated offer-specific meter rates | Available only for supported legacy offers and authorized identities |
| Consumption Price Sheet | Negotiated subscription or billing-profile prices | Availability depends on billing agreement and billing permissions |
| Azure ML registry | Optional Fireworks model catalog | Requires the Azure CLI `ml` extension and registry access |

The toolkit combines these sources because no single API provides a complete
model, price, quota, and deployability answer.

## ✅ Prerequisites

- Azure CLI for authenticated examples
- `az login`
- Permission to read the target subscription
- Billing permissions for Rate Card or Price Sheet examples
- `curl` for the Bash Retail Prices example
- PowerShell 7 or Windows PowerShell for `Invoke-RestMethod` examples

Select the intended subscription before running authenticated requests.

**Bash**

```bash
az login
az account set --subscription "<subscription-name-or-id>"
SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
REGION="eastus"
```

**PowerShell**

```powershell
az login
az account set --subscription "<subscription-name-or-id>"
$SubscriptionId = az account show --query id --output tsv
$Region = "eastus"
```

## 🌐 1. Query public Retail Prices

The Retail Prices API is unauthenticated. This example requests USD Foundry
Models meters for one Azure region.

**Bash**

```bash
FILTER="serviceName eq 'Foundry Models' and armRegionName eq 'eastus'"

curl --get "https://prices.azure.com/api/retail/prices" \
  --data-urlencode "currencyCode='USD'" \
  --data-urlencode "\$filter=${FILTER}" \
  --data-urlencode "\$skip=0" \
  --output retail-eastus.json
```

**PowerShell**

```powershell
$Filter = "serviceName eq 'Foundry Models' and armRegionName eq 'eastus'"
$EncodedFilter = [uri]::EscapeDataString($Filter)
$EncodedCurrency = [uri]::EscapeDataString("'USD'")
$Uri = "https://prices.azure.com/api/retail/prices" +
  "?currencyCode=$EncodedCurrency&`$filter=$EncodedFilter&`$skip=0"

Invoke-RestMethod -Method Get -Uri $Uri |
  ConvertTo-Json -Depth 100 |
  Set-Content .\retail-eastus.json
```

### Restrict the response to selected products

Add exact `productName` clauses to the OData filter:

```text
serviceName eq 'Foundry Models' and
armRegionName eq 'eastus' and
(productName eq 'Azure Fireworks Models' or productName eq 'Azure OpenAI')
```

Useful response properties include:

- `Items[].productName`
- `Items[].skuName`
- `Items[].meterName`
- `Items[].meterId`
- `Items[].retailPrice` and `Items[].unitPrice`
- `Items[].unitOfMeasure`
- `Items[].type` and `Items[].reservationTerm`

The service returns at most 1,000 rows per page. Increase `$skip` by the number
of returned items until a page contains fewer than 1,000 items.

## 🧠 2. List regional model versions and deployment SKUs

This ARM request returns the model catalog for a Cognitive Services location.
`az rest` authenticates automatically and derives the correct ARM endpoint from
the active Azure cloud, so the command also works with supported sovereign
clouds.

**Bash**

```bash
az rest \
  --method get \
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.CognitiveServices/locations/${REGION}/models" \
  --url-parameters api-version=2025-06-01 \
  --output-file "models-${REGION}.json"
```

**PowerShell**

```powershell
az rest `
  --method get `
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.CognitiveServices/locations/$Region/models" `
  --url-parameters api-version=2025-06-01 `
  --output-file "models-$Region.json"
```

The `{subscriptionId}` token is replaced automatically by `az rest`. Inspect:

- `value[].model.name`, `version`, and `format`
- `value[].model.lifecycleStatus`
- `value[].model.skus[].name`
- `value[].model.skus[].usageName`
- `value[].model.skus[].capacity`

The toolkit treats a model SKU as PTU-capable when its SKU name contains
`Provisioned`. Keep every version: model name alone is not sufficient to
determine deployment support.

## 📊 3. Query regional quota and PTU availability

The regional usages endpoint returns subscription quota limits and current
usage. The toolkit selects usage names containing `Provisioned` and calculates
`available = limit - currentValue`.

**Bash**

```bash
az rest \
  --method get \
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.CognitiveServices/locations/${REGION}/usages" \
  --url-parameters api-version=2025-06-01 \
  --output-file "usages-${REGION}.json"
```

**PowerShell**

```powershell
az rest `
  --method get `
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.CognitiveServices/locations/$Region/usages" `
  --url-parameters api-version=2025-06-01 `
  --output-file "usages-$Region.json"
```

Useful properties are:

- `value[].name.value`
- `value[].name.localizedValue`
- `value[].currentValue`
- `value[].limit`
- `value[].unit`

A positive remaining quota does not guarantee immediate deployment capacity.
Azure may still reject a deployment because capacity is unavailable for a
specific model, version, SKU, or region.

## 🏷️ 4. Read the subscription offer ID

The legacy Rate Card request needs an offer durable ID. The toolkit first reads
`subscriptionPolicies.quotaId` from the ARM subscription resource.

**Bash**

```bash
az rest \
  --method get \
  --url "/subscriptions/{subscriptionId}" \
  --url-parameters api-version=2022-12-01 \
  --query subscriptionPolicies.quotaId \
  --output tsv
```

**PowerShell**

```powershell
az rest `
  --method get `
  --url "/subscriptions/{subscriptionId}" `
  --url-parameters api-version=2022-12-01 `
  --query subscriptionPolicies.quotaId `
  --output tsv
```

The returned offer might not be supported by the legacy Commerce API. An HTTP
authorization or unsupported-offer response is not evidence that the
subscription has no prices.

## 💳 5. Query the authenticated Commerce Rate Card

Replace the sample offer ID if the previous request returned a different value.
The `$filter` parameter is a single OData expression.

**Bash**

```bash
az rest \
  --method get \
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.Commerce/rateCard" \
  --url-parameters \
    api-version=2016-08-31-preview \
    "\$filter=OfferDurableId eq 'MS-AZR-0003P' and Currency eq 'USD' and Locale eq 'en-US' and RegionInfo eq 'US'" \
  --output-file authenticated-rate-card.json
```

**PowerShell**

```powershell
az rest `
  --method get `
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.Commerce/rateCard" `
  --url-parameters `
    api-version=2016-08-31-preview `
    '$filter=OfferDurableId eq ''MS-AZR-0003P'' and Currency eq ''USD'' and Locale eq ''en-US'' and RegionInfo eq ''US''' `
  --output-file .\authenticated-rate-card.json
```

Compare `Meters[].MeterId` and `Meters[].MeterRates` with the Retail Prices
response. Meter IDs are a stronger comparison key than product or SKU display
names.

## 🧾 6. Query an authenticated Price Sheet

### Subscription scope

This is the simplest Price Sheet request, but it is available only for
supported subscription and billing arrangements.

**Bash**

```bash
az rest \
  --method get \
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.Consumption/pricesheets/default" \
  --url-parameters api-version=2023-05-01 \
  --output-file authenticated-price-sheet.json
```

**PowerShell**

```powershell
az rest `
  --method get `
  --url "/subscriptions/{subscriptionId}/providers/Microsoft.Consumption/pricesheets/default" `
  --url-parameters api-version=2023-05-01 `
  --output-file .\authenticated-price-sheet.json
```

### Billing-profile scope

Use this form when the caller has access to a Microsoft Customer Agreement
billing account and billing profile:

```text
/providers/Microsoft.Billing/billingAccounts/<url-encoded-billing-account-id>
/billingProfiles/<url-encoded-billing-profile-id>
/providers/Microsoft.Consumption/pricesheets/default
```

**Bash**

```bash
az rest \
  --method get \
  --url "/providers/Microsoft.Billing/billingAccounts/<url-encoded-billing-account-id>/billingProfiles/<url-encoded-billing-profile-id>/providers/Microsoft.Consumption/pricesheets/default" \
  --url-parameters api-version=2023-05-01 \
  --output-file authenticated-price-sheet.json
```

**PowerShell**

```powershell
az rest `
  --method get `
  --url "/providers/Microsoft.Billing/billingAccounts/<url-encoded-billing-account-id>/billingProfiles/<url-encoded-billing-profile-id>/providers/Microsoft.Consumption/pricesheets/default" `
  --url-parameters api-version=2023-05-01 `
  --output-file .\authenticated-price-sheet.json
```

URL-encode the complete billing account and billing profile identifiers before
placing them in the path. Access commonly requires a billing reader role at the
relevant billing scope.

## 🎆 7. Query the optional Fireworks registry catalog

The toolkit uses the Azure Machine Learning CLI extension for this optional
query. The extension handles registry authentication and API calls.

**Bash**

```bash
az extension add --name ml
az ml model list \
  --registry-name azureml-fireworks \
  --output json > fireworks-catalog.json
```

**PowerShell**

```powershell
az extension add --name ml
az ml model list `
  --registry-name azureml-fireworks `
  --output json |
  Set-Content .\fireworks-catalog.json
```

Registry availability can vary by cloud, tenant, subscription, and Azure ML
extension version. Failure of this optional query does not invalidate ARM model
or pricing results.

## 🔑 8. Send a direct bearer-token request

`az rest` is preferred because it avoids exposing access tokens and selects the
active cloud's ARM endpoint automatically. If another HTTP client is required,
derive both values from Azure CLI instead of hardcoding public Azure endpoints.

**Bash**

```bash
ARM_ENDPOINT="$(az cloud show --query endpoints.resourceManager --output tsv)"
ACCESS_TOKEN="$(az account get-access-token \
  --resource "$ARM_ENDPOINT" \
  --query accessToken \
  --output tsv)"

curl \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "Content-Type: application/json" \
  "${ARM_ENDPOINT}subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.CognitiveServices/locations/${REGION}/models?api-version=2025-06-01"
```

**PowerShell**

```powershell
$ArmEndpoint = az cloud show --query endpoints.resourceManager --output tsv
$AccessToken = az account get-access-token `
  --resource $ArmEndpoint `
  --query accessToken `
  --output tsv
$Uri = "${ArmEndpoint}subscriptions/$SubscriptionId/providers/" +
  "Microsoft.CognitiveServices/locations/$Region/models?api-version=2025-06-01"

Invoke-RestMethod `
  -Method Get `
  -Uri $Uri `
  -Headers @{ Authorization = "Bearer $AccessToken" }
```

Do not print, persist, or commit bearer tokens. They grant the permissions of
the signed-in identity until they expire.

## 🛠️ Common troubleshooting

| Result | Meaning or next check |
|---|---|
| `401 Unauthorized` | Sign in again and confirm the token audience matches the endpoint |
| `403 Forbidden` | Verify Azure RBAC or billing-scope permissions |
| `404 Not Found` | Check the active cloud, region, resource provider, scope, and API version |
| Empty model list | Confirm the region name and subscription access |
| Empty PTU quota selection | Inspect all usage names; quota labels can evolve |
| Retail rows but no deployable model | Retail pricing and deployment availability are independent |
| Rate Card unavailable | The subscription offer may not support the legacy API |
| Price Sheet unavailable | Verify the billing agreement and billing reader access |

## 📚 Official Microsoft references

- [Azure Retail Prices overview and sample calls](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
- [Azure AI Services Models - List REST API](https://learn.microsoft.com/rest/api/aiservices/accountmanagement/models/list?view=rest-aiservices-accountmanagement-2024-10-01)
- [Azure AI Services Usages - List REST API](https://learn.microsoft.com/rest/api/aiservices/accountmanagement/usages/list?view=rest-aiservices-accountmanagement-2024-10-01)
- [Azure Consumption Price Sheet - Get REST API](https://learn.microsoft.com/rest/api/consumption/price-sheet/get?view=rest-consumption-2023-05-01)
- [Microsoft Customer Agreement price sheet schema](https://learn.microsoft.com/azure/cost-management-billing/dataset-schema/price-sheet-mca?view=rest-consumption-2023-05-01)
- [Azure Rate Card resources](https://learn.microsoft.com/partner-center/developer/azure-rate-card-resources)
- [Azure CLI `az rest` reference](https://learn.microsoft.com/cli/azure/reference-index#az-rest)
- [Azure CLI Cognitive Services model commands](https://learn.microsoft.com/cli/azure/cognitiveservices/model)
- [Azure CLI Cognitive Services usage commands](https://learn.microsoft.com/cli/azure/cognitiveservices/usage)
- [Azure CLI ML model commands](https://learn.microsoft.com/cli/azure/ml/model#az-ml-model-list)
