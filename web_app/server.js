const express = require('express');
const fs = require('fs');
const path = require('path');
const { DefaultAzureCredential } = require('@azure/identity');

const app = express();
const frontendBuildPath = path.join(__dirname, 'dist');
const repoRootPath = path.resolve(__dirname, '..');
const generatedDataPaths = [
  path.join(repoRootPath, 'data', 'generated'),
  path.join(__dirname, 'data', 'generated'),
];
const port = Number(process.env.PORT || 8080);
const functionBaseUrl = process.env.FUNCTION_BASE_URL || '';
const functionApiKey = process.env.FUNCTION_API_KEY || '';
const functionAuthResource = process.env.FUNCTION_AUTH_RESOURCE || '';
const authorityHost = process.env.AZURE_AUTHORITY_HOST || '';
const configuredCloudEnvironment = normalizeCloudEnvironment(process.env.AZURE_CLOUD_ENVIRONMENT || process.env.CLOUD_ENVIRONMENT || 'AzureCloud');
const cacheTtlSeconds = Number(process.env.CACHE_TTL_SECONDS || 120);
const runCacheTtlSeconds = Number(process.env.RUN_CACHE_TTL_SECONDS || 600);

let functionCredential;
let cachedFunctionToken = null;

const publicRegionOptions = [
  'australiaeast', 'brazilsouth', 'canadacentral', 'canadaeast', 'centralus', 'eastasia',
  'eastus', 'eastus2', 'francecentral', 'germanywestcentral', 'italynorth', 'japaneast',
  'koreacentral', 'northcentralus', 'northeurope', 'norwayeast', 'polandcentral',
  'qatarcentral', 'southafricanorth', 'southcentralus', 'southeastasia', 'southindia',
  'spaincentral', 'swedencentral', 'switzerlandnorth', 'uaenorth', 'uksouth', 'westeurope',
  'westus', 'westus2', 'westus3'
];

const usGovRegionOptions = [
  'usgovarizona', 'usgovtexas', 'usgovvirginia', 'usdodcentral', 'usdodeast'
];

const cache = new Map();

process.on('uncaughtException', (error) => {
  console.error('Uncaught exception in web app process', error);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled rejection in web app process', reason);
});

function logApiEvent(level, message, details = {}) {
  const payload = Object.entries(details)
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([key, value]) => `${key}=${typeof value === 'string' ? value : JSON.stringify(value)}`)
    .join(' ');
  const line = payload ? `${message} ${payload}` : message;
  console[level](line);
}

function logStartupContext() {
  const frontendIndexPath = path.join(frontendBuildPath, 'index.html');
  console.log('Web app startup context', {
    cwd: process.cwd(),
    dirname: __dirname,
    nodeVersion: process.version,
    frontendBuildPath,
    frontendBuildExists: fs.existsSync(frontendBuildPath),
    frontendIndexExists: fs.existsSync(frontendIndexPath),
    cloudEnvironment: configuredCloudEnvironment,
    authorityHost: authorityHost || undefined,
    hasFunctionBaseUrl: Boolean(functionBaseUrl),
    hasFunctionApiKey: Boolean(functionApiKey),
    hasFunctionAuthResource: Boolean(functionAuthResource),
  });
}

function normalizeCloudEnvironment(value) {
  const normalized = String(value || 'AzureCloud').trim();
  if (!normalized) {
    return 'AzureCloud';
  }

  const aliases = {
    public: 'AzureCloud',
    azurepublic: 'AzureCloud',
    azurepubliccloud: 'AzureCloud',
    usgov: 'AzureUSGovernment',
    azuregov: 'AzureUSGovernment',
    azuregovernment: 'AzureUSGovernment',
  };

  return aliases[normalized.toLowerCase()] || normalized;
}

function isUsGovCloud(cloudEnvironment) {
  return normalizeCloudEnvironment(cloudEnvironment) === 'AzureUSGovernment';
}

function isUsGovRegion(region) {
  return String(region || '').toLowerCase().startsWith('usgov') || String(region || '').toLowerCase().startsWith('usdod');
}

function regionOptionsForCloud(cloudEnvironment) {
  return isUsGovCloud(cloudEnvironment) ? usGovRegionOptions : publicRegionOptions;
}

function defaultRegionsForCloud(cloudEnvironment) {
  if (isUsGovCloud(cloudEnvironment)) {
    return {
      sourceRegion: process.env.DEFAULT_SOURCE_REGION || 'usgovvirginia',
      targetRegion: process.env.DEFAULT_TARGET_REGION || 'usgovarizona',
    };
  }

  return {
    sourceRegion: process.env.DEFAULT_SOURCE_REGION || 'canadacentral',
    targetRegion: process.env.DEFAULT_TARGET_REGION || 'eastus',
  };
}

function validateRegionsForCloud(cloudEnvironment, sourceRegion, targetRegion) {
  const source = String(sourceRegion || '').trim().toLowerCase();
  const target = String(targetRegion || '').trim().toLowerCase();
  if (isUsGovCloud(cloudEnvironment)) {
    const invalid = [source, target].filter((region) => region && !isUsGovRegion(region));
    if (invalid.length) {
      return `Azure Government mode only supports Azure Government regions; received: ${invalid.join(', ')}.`;
    }
    return '';
  }

  const invalid = [source, target].filter((region) => isUsGovRegion(region));
  if (invalid.length) {
    return `Azure Government regions require AzureUSGovernment cloud configuration; received: ${invalid.join(', ')}.`;
  }

  return '';
}

function cacheKey(req) {
  return `${req.method}:${req.originalUrl}`;
}

function getCached(key) {
  const entry = cache.get(key);
  if (!entry) {
    return null;
  }

  if (entry.expiresAt < Date.now()) {
    cache.delete(key);
    return null;
  }

  return entry.payload;
}

function setCached(key, payload, ttlSeconds) {
  cache.set(key, {
    payload,
    expiresAt: Date.now() + ttlSeconds * 1000,
  });
}

function clearApiCache(prefix) {
  for (const key of cache.keys()) {
    if (!prefix || key.includes(prefix)) {
      cache.delete(key);
    }
  }
}

function getUserProfile(req) {
  return {
    name: req.headers['x-ms-client-principal-name'] || 'Signed-in user',
    id: req.headers['x-ms-client-principal-id'] || '',
    provider: req.headers['x-ms-client-principal-idp'] || 'aad',
  };
}

function readGeneratedArtifact(relativePath, label) {
  const artifactPath = generatedDataPaths
    .map((basePath) => path.join(basePath, relativePath))
    .find((candidatePath) => fs.existsSync(candidatePath));

  if (!artifactPath) {
    return {
      key: relativePath,
      label,
      present: false,
      relativePath: path.join('data', 'generated', relativePath),
    };
  }

  const stats = fs.statSync(artifactPath);
  return {
    key: relativePath,
    label,
    present: true,
    relativePath: path.relative(repoRootPath, artifactPath),
    sizeBytes: stats.size,
    updatedAt: stats.mtime.toISOString(),
  };
}

function getAppContext() {
  const generatedArtifacts = [
    readGeneratedArtifact('canonical_service_identity.snapshot.json', 'Canonical service identity snapshot'),
    readGeneratedArtifact('canonical_identity_gaps.snapshot.json', 'Canonical identity gap report'),
    readGeneratedArtifact('feature_catalog.snapshot.json', 'Feature catalog snapshot'),
    readGeneratedArtifact('feature_catalog.db', 'Feature catalog database'),
  ];

  return {
    runtime: {
      cloudEnvironment: configuredCloudEnvironment,
      authorityHost: authorityHost || undefined,
      hasFunctionBaseUrl: Boolean(functionBaseUrl),
      hasFunctionApiKey: Boolean(functionApiKey),
      hasFunctionAuthResource: Boolean(functionAuthResource),
      cacheTtlSeconds,
      runCacheTtlSeconds,
    },
    generatedArtifacts,
  };
}

function buildFunctionUrl(endpoint, query = {}) {
  const url = new URL(endpoint, functionBaseUrl.endsWith('/') ? functionBaseUrl : `${functionBaseUrl}/`);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  if (!functionAuthResource && functionApiKey) {
    url.searchParams.set('code', functionApiKey);
  }
  return url;
}

function getFunctionAuthScope() {
  if (!functionAuthResource) {
    return '';
  }

  return functionAuthResource.endsWith('/.default')
    ? functionAuthResource
    : `${functionAuthResource}/.default`;
}

async function getFunctionAuthorizationHeader() {
  if (!functionAuthResource) {
    return '';
  }

  const now = Date.now();
  if (cachedFunctionToken && cachedFunctionToken.expiresOnTimestamp > now + 60000) {
    return `Bearer ${cachedFunctionToken.token}`;
  }

  if (!functionCredential) {
    functionCredential = new DefaultAzureCredential(authorityHost ? { authorityHost } : undefined);
  }

  const accessToken = await functionCredential.getToken(getFunctionAuthScope());
  if (!accessToken || !accessToken.token) {
    throw new Error('Failed to acquire a managed identity token for the Function App.');
  }

  cachedFunctionToken = accessToken;
  return `Bearer ${accessToken.token}`;
}

async function proxyFunctionJson(method, endpoint, { query = {}, body } = {}) {
  if (!functionBaseUrl) {
    throw new Error('FUNCTION_BASE_URL is not configured.');
  }

  const url = buildFunctionUrl(endpoint, query);
  const startedAt = Date.now();
  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  const authorizationHeader = await getFunctionAuthorizationHeader();
  if (authorizationHeader) {
    headers.Authorization = authorizationHeader;
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text();
    const forbiddenIp = response.headers.get('x-ms-forbidden-ip') || '';
    logApiEvent('error', 'Function proxy request failed', {
      method,
      endpoint,
      status: response.status,
      forbiddenIp,
      durationMs: Date.now() - startedAt,
      query,
      body,
      responseText: text,
    });
    const networkDetail = forbiddenIp ? `; blocked egress IP ${forbiddenIp}` : '';
    throw new Error(`Function request failed (${response.status}${networkDetail}): ${text}`);
  }

  const payload = await response.json();
  logApiEvent('info', 'Function proxy request completed', {
    method,
    endpoint,
    status: response.status,
    durationMs: Date.now() - startedAt,
    query,
  });
  return payload;
}

app.disable('x-powered-by');
app.use(express.json());
app.use('/api', (req, _res, next) => {
  logApiEvent('info', 'Web API request received', {
    method: req.method,
    path: req.path,
    query: req.query,
  });
  next();
});
app.use(express.static(frontendBuildPath));

app.get('/api/session', async (req, res) => {
  let cloudEnvironment = configuredCloudEnvironment;
  let defaults = defaultRegionsForCloud(cloudEnvironment);

  if (functionBaseUrl) {
    try {
      const healthPayload = await proxyFunctionJson('GET', 'api/health');
      cloudEnvironment = normalizeCloudEnvironment(healthPayload.cloudEnvironment || cloudEnvironment);
      defaults = {
        sourceRegion: healthPayload.defaultSourceRegion || defaultRegionsForCloud(cloudEnvironment).sourceRegion,
        targetRegion: healthPayload.defaultTargetRegion || defaultRegionsForCloud(cloudEnvironment).targetRegion,
      };
    } catch (error) {
      logApiEvent('warning', 'Web session falling back to local cloud defaults', { error: error.message });
    }
  }

  res.json({
    user: getUserProfile(req),
    cloudEnvironment,
    defaults: {
      sourceRegion: defaults.sourceRegion,
      targetRegion: defaults.targetRegion,
      comparisonMode: 'inventory',
    },
    regions: regionOptionsForCloud(cloudEnvironment),
    comparisonModes: [
      { value: 'inventory', label: 'Inventory-based regional comparison' },
      { value: 'regional', label: 'Full regional comparison' },
    ],
    appContext: getAppContext(),
  });
});

app.get('/api/health', async (req, res) => {
  const key = cacheKey(req);
  const cached = getCached(key);
  if (cached) {
    return res.json(cached);
  }

  try {
    const payload = await proxyFunctionJson('GET', 'api/health');
    setCached(key, payload, cacheTtlSeconds);
    return res.json(payload);
  } catch (error) {
    logApiEvent('error', 'Web health request failed', { error: error.message });
    return res.status(502).json({ error: error.message });
  }
});

app.get('/api/runs', async (req, res) => {
  const key = cacheKey(req);
  const cached = getCached(key);
  if (cached) {
    return res.json(cached);
  }

  try {
    const payload = await proxyFunctionJson('GET', 'api/runs', { query: req.query });
    setCached(key, payload, cacheTtlSeconds);
    return res.json(payload);
  } catch (error) {
    logApiEvent('error', 'Web runs request failed', { error: error.message, query: req.query });
    return res.status(502).json({ error: error.message });
  }
});

app.get('/api/comparisons', async (req, res) => {
  const key = cacheKey(req);
  const cached = getCached(key);
  if (cached) {
    return res.json(cached);
  }

  try {
    const payload = await proxyFunctionJson('GET', 'api/comparisons', { query: req.query });
    const ttl = req.query.runId ? runCacheTtlSeconds : cacheTtlSeconds;
    setCached(key, payload, ttl);
    return res.json(payload);
  } catch (error) {
    logApiEvent('error', 'Web comparisons request failed', { error: error.message, query: req.query });
    return res.status(502).json({ error: error.message });
  }
});

app.post('/api/refresh', async (req, res) => {
  const cloudEnvironment = configuredCloudEnvironment;
  const validationError = validateRegionsForCloud(cloudEnvironment, req.body?.sourceRegion, req.body?.targetRegion);
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  try {
    const payload = await proxyFunctionJson('POST', 'api/refresh', { body: req.body });
    clearApiCache('/api/runs');
    clearApiCache('/api/comparisons');
    clearApiCache('/api/health');
    return res.json(payload);
  } catch (error) {
    logApiEvent('error', 'Web refresh request failed', { error: error.message, body: req.body });
    return res.status(502).json({ error: error.message });
  }
});

app.get('/{*splat}', (_req, res, next) => {
  const indexPath = path.join(frontendBuildPath, 'index.html');
  res.sendFile(indexPath, (error) => {
    if (error) {
      console.error('Failed to serve frontend index', {
        message: error.message,
        code: error.code,
        status: error.status,
        indexPath,
      });
      next(error);
    }
  });
});

app.use((error, req, res, next) => {
  console.error('Unhandled web app request error', {
    method: req.method,
    path: req.originalUrl,
    message: error?.message,
    stack: error?.stack,
  });

  if (res.headersSent) {
    return next(error);
  }

  return res.status(error?.status || 500).json({
    error: error?.message || 'Internal server error',
  });
});

logStartupContext();

app.listen(port, () => {
  console.log(`Web app listening on ${port}`);
});