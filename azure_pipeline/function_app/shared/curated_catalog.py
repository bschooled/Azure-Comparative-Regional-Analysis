from __future__ import annotations

import re
from typing import Any


ZONE_MODE_LABELS = {
    'none': 'No zone-specific support',
    'regional': 'Regional service',
    'zonal': 'Zonal support',
    'zone-redundant': 'Zone-redundant support',
    'both': 'Zonal and zone-redundant support',
    'unknown': 'Unknown',
}


CATALOG: list[dict[str, Any]] = [
    {
        'service_key': 'azure-virtual-machines',
        'display_name': 'Virtual Machines',
        'family': 'compute',
        'summary': 'Compute service view for VM family and SKU comparisons across regions.',
        'providers': [{'namespace': 'microsoft.compute', 'resource_types': ['virtualmachines']}],
        'pricing': {
            'query_mode': 'first-match',
            'filters': [
                {'service_name': 'Virtual Machines', 'price_type': 'Consumption'},
                {'service_name': 'Virtual Machines', 'price_type': 'Reservation'},
            ],
        },
        'zone_support': {'default': 'zonal', 'notes': 'VM availability and zone posture depend on size family and regional capacity.'},
        'capabilities': [],
    },
    {
        'service_key': 'managed-disks',
        'display_name': 'Managed Disks',
        'family': 'storage',
        'summary': 'Managed disk service view for disk tier and SKU comparisons across regions.',
        'providers': [{'namespace': 'microsoft.compute', 'resource_types': ['disks']}],
        'pricing': {
            'query_mode': 'merge',
            'filters': [
                {'service_family': 'Storage', 'service_name': 'Storage', 'product_name_contains': 'Managed Disks'},
                {'service_family': 'Storage', 'service_name': 'Storage', 'product_name_contains': 'Premium SSD v2'},
                {'service_family': 'Storage', 'service_name': 'Storage', 'product_name_contains': 'Ultra Disks'},
            ],
        },
        'zone_support': {'default': 'regional', 'notes': 'Disk availability and redundancy posture depend on tier and SKU.'},
        'capabilities': [],
    },
    {
        'service_key': 'azure-app-service-platform',
        'display_name': 'Azure App Service Platform',
        'family': 'app-services',
        'summary': 'Shared fallback for Microsoft.Web comparisons when provider metadata is too coarse to separate App Service from Functions.',
        'providers': [
            {
                'namespace': 'microsoft.web',
                'resource_types': ['sites', 'serverfarms', 'functionapps'],
                'match_hints': {
                    'prefer_when_no_skus': True,
                    'shared_provider_fallback': True,
                    'resource_type_contains': ['sites', 'serverfarms', 'functionapps'],
                },
            },
        ],
        'zone_support': {
            'default': 'zonal',
            'notes': 'Use this shared view when provider metadata cannot cleanly split App Service and Functions hosting models.',
        },
        'capabilities': [
            {'key': 'private_endpoints', 'label': 'Private endpoint and private ingress patterns', 'importance': 'high', 'notes': 'Validate exact support by hosting plan when network isolation is required.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'vnet_integration', 'label': 'Virtual network integration', 'importance': 'high', 'notes': 'Important across both App Service and Functions migration scenarios.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'deployment_and_release', 'label': 'Deployment slots or controlled release features', 'importance': 'medium', 'notes': 'Validate exact rollout features by hosting model.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-app-service',
        'display_name': 'Azure App Service',
        'family': 'app-services',
        'summary': 'PaaS web hosting platform where networking, scale units, and resiliency features matter more than raw provider enumeration.',
        'providers': [
            {
                'namespace': 'microsoft.web',
                'resource_types': ['sites', 'serverfarms'],
                'match_hints': {
                    'resource_type_contains': ['serverfarms'],
                    'prefer_when_skus': True,
                },
            },
        ],
        'zone_support': {'default': 'zonal', 'notes': 'Exact plan behavior still depends on SKU family and deployment shape.'},
        'capabilities': [
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Lets the app stay off the public internet while keeping inbound web traffic on private address space.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'deployment_slots', 'label': 'Deployment slots', 'importance': 'medium', 'notes': 'Gives operators a warm-up and swap path so releases can cut over without redeploying production in place.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'vnet_integration', 'label': 'Virtual network integration', 'importance': 'high', 'notes': 'Keeps outbound application traffic on private routes for databases, APIs, and internal dependencies.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'app_service_environment', 'label': 'App Service Environment support', 'importance': 'medium', 'notes': 'Enables a fully isolated App Service stamp when tenancy, network control, or scale boundaries must be dedicated.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'managed_identity', 'label': 'Managed identity', 'importance': 'high', 'notes': 'Removes stored credentials from app settings when the site needs to call Azure services.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'entra_auth', 'label': 'Built-in Microsoft Entra authentication', 'importance': 'medium', 'notes': 'Lets the platform handle sign-in and token validation instead of pushing auth plumbing into the app code.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'backup_restore', 'label': 'Backup and restore', 'importance': 'medium', 'notes': 'Provides a platform recovery path for site content and configuration during migration rollback or incident response.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'autoscale', 'label': 'Autoscale', 'importance': 'medium', 'notes': 'Matches worker count to traffic so the target region can absorb peaks without permanently paying for peak capacity.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'health_check', 'label': 'Health check', 'importance': 'medium', 'notes': 'Helps App Service drain unhealthy instances before they keep serving bad responses during scale or patch events.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'custom_domains_tls', 'label': 'Custom domains and TLS', 'importance': 'medium', 'notes': 'Keeps first-party hostnames and certificate control intact after the service moves regions.', 'availability': {'default': 'available', 'regions': {}}},
        ],
        'regional_overrides': {
            'swedencentral': {'notes': 'Treat isolated hosting and advanced networking as explicit validation items for final migration design.'},
        },
    },
    {
        'service_key': 'azure-functions',
        'display_name': 'Azure Functions',
        'family': 'app-services',
        'summary': 'Event-driven compute platform where plan choice, networking, and scale semantics matter for region planning.',
        'providers': [
            {
                'namespace': 'microsoft.web',
                'resource_types': ['functionapps', 'sites'],
                'match_hints': {
                    'resource_type_contains': ['functionapps'],
                    'prefer_when_skus': True,
                },
            },
        ],
        'zone_support': {'default': 'zonal', 'notes': 'Availability zone support is documented at the service level, but plans still differ.'},
        'capabilities': [
            {'key': 'premium_plan', 'label': 'Premium plan', 'importance': 'high', 'notes': 'Removes cold-start tradeoffs and unlocks the hosting features most teams need for private or latency-sensitive functions.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'durable_functions', 'label': 'Durable Functions', 'importance': 'medium', 'notes': 'Supports stateful orchestrations so long-running workflows do not have to be rebuilt outside the Functions model.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'vnet_integration', 'label': 'Virtual network integration', 'importance': 'high', 'notes': 'Keeps function outbound traffic on private paths for databases, storage, and internal services.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'flex_consumption', 'label': 'Elastic or flexible consumption options', 'importance': 'medium', 'notes': 'Preserves a low-idle-cost serverless posture while still scaling with bursty event traffic.', 'availability': {'default': 'unknown', 'regions': {}}},
            {'key': 'deployment_slots', 'label': 'Deployment slots', 'importance': 'medium', 'notes': 'Lets operators warm and validate a new function build before swapping it into production traffic.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'managed_identity', 'label': 'Managed identity', 'importance': 'high', 'notes': 'Allows function code to access Azure services without putting keys or connection secrets in app settings.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'medium', 'notes': 'Keeps the function app reachable only from approved networks when public ingress is not acceptable.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'event_driven_scaling', 'label': 'Event-driven scaling', 'importance': 'high', 'notes': 'Determines whether the target region can absorb queue, timer, and message bursts without pre-provisioned workers.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'container_apps_hosting', 'label': 'Container Apps hosting option', 'importance': 'medium', 'notes': 'Provides a route to keep Functions triggers while adopting Container Apps networking, revisions, and workload profiles.', 'availability': {'default': 'available', 'regions': {}}},
        ],
        'regional_overrides': {
            'swedencentral': {
                'notes': 'Treat flexible consumption and advanced networking as validation items before finalizing region migration plans.',
                'capabilities': {
                    'flex_consumption': {
                        'status': 'unknown',
                        'notes': 'Validate elastic or flexible consumption plan support directly in-region before migration cutover.',
                    },
                },
            },
        },
    },
    {
        'service_key': 'azure-api-management',
        'display_name': 'Azure API Management',
        'family': 'app-services',
        'summary': 'Managed API gateway platform where networking mode, self-hosted gateway, and resiliency posture commonly drive regional decisions.',
        'providers': [{'namespace': 'microsoft.apimanagement', 'resource_types': ['service']}],
        'zone_support': {'default': 'both', 'notes': 'The availability-zones support matrix lists Azure API Management with both zonal and zone-redundant support.'},
        'capabilities': [
            {'key': 'internal_vnet', 'label': 'Internal virtual network mode', 'importance': 'high', 'notes': 'Common requirement for private API estates.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'self_hosted_gateway', 'label': 'Self-hosted gateway', 'importance': 'medium', 'notes': 'Relevant for hybrid and edge API topologies.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'multi_region', 'label': 'Multi-region deployment', 'importance': 'high', 'notes': 'Important when comparing active/active API edge patterns.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-app-configuration',
        'display_name': 'Azure App Configuration',
        'family': 'app-services',
        'summary': 'Managed configuration store where replication, private access, and consistency posture shape app-platform region planning.',
        'providers': [{'namespace': 'microsoft.appconfiguration', 'resource_types': ['configurationstores']}],
        'zone_support': {'default': 'zonal', 'notes': 'The availability-zones support matrix lists Azure App Configuration with zonal support.'},
        'capabilities': [
            {'key': 'geo_replication', 'label': 'Geo-replication', 'importance': 'high', 'notes': 'Important for multi-region configuration resiliency.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_link', 'label': 'Private Link', 'importance': 'high', 'notes': 'Frequently required in private application estates.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'key_vault_references', 'label': 'Key Vault references', 'importance': 'medium', 'notes': 'Useful for centralized config and secret consumption patterns.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-logic-apps',
        'display_name': 'Azure Logic Apps',
        'family': 'app-services',
        'summary': 'Workflow orchestration platform where hosting model, networking, and connector reachability are key region-selection concerns.',
        'providers': [{'namespace': 'microsoft.logic', 'resource_types': ['workflows', 'integrationserviceenvironments']}],
        'zone_support': {'default': 'zonal', 'notes': 'The availability-zones support matrix lists Azure Logic Apps with zonal support.'},
        'capabilities': [
            {'key': 'standard_workflows', 'label': 'Standard hosting model', 'importance': 'high', 'notes': 'Important when comparing dedicated versus multitenant workflow patterns.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'vnet_integration', 'label': 'Virtual network integration', 'importance': 'high', 'notes': 'Often necessary for private connector and hybrid patterns.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'medium', 'notes': 'Useful when isolating workflow entry points.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-spring-apps',
        'display_name': 'Azure Spring Apps',
        'family': 'app-services',
        'summary': 'Managed Spring platform where networking, build/runtime separation, and enterprise isolation features often drive regional choice.',
        'providers': [{'namespace': 'microsoft.appplatform', 'resource_types': ['spring', 'gateways']}],
        'zone_support': {'default': 'unknown', 'notes': 'Public service feature guidance is stronger than generic provider metadata for this platform.'},
        'capabilities': [
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Important for private app platform deployments.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'build_service', 'label': 'Build service and app lifecycle tooling', 'importance': 'high', 'notes': 'Useful for platform engineering workflows and one of the first capabilities to verify in newer regions.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-container-apps',
        'display_name': 'Azure Container Apps',
        'family': 'containers',
        'summary': 'Serverless container platform where environment availability and ingress/network options drive fit-for-region decisions.',
        'providers': [{'namespace': 'microsoft.app', 'resource_types': ['containerapps', 'managedenvironments']}],
        'zone_support': {'default': 'zonal', 'notes': 'Service support is documented, but environment capabilities still depend on region maturity.'},
        'capabilities': [
            {'key': 'zone_redundant_environment', 'label': 'Zone-redundant environment', 'importance': 'high', 'requires_zone_support': True, 'notes': 'Keeps the managed environment online through a single-zone failure when the region supports zonal placement.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'workload_profiles', 'label': 'Workload profiles', 'importance': 'high', 'notes': 'Lets teams mix serverless-style elasticity with dedicated compute shapes inside the same Container Apps environment.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'vnet_integration', 'label': 'Virtual network integration', 'importance': 'high', 'notes': 'Places app traffic on private network paths and is often a prerequisite for stricter enterprise landing zones.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Allows ingress to stay private so the app surface is not exposed on the public internet.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'revisions', 'label': 'Immutable revisions', 'importance': 'high', 'notes': 'Gives every rollout a stable snapshot so operators can validate or roll back without rebuilding the deployment model.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'traffic_splitting', 'label': 'Revision traffic splitting', 'importance': 'medium', 'notes': 'Supports progressive delivery by sending only part of production traffic to a new revision first.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'dapr', 'label': 'Dapr sidecar integration', 'importance': 'medium', 'notes': 'Adds service invocation, pub/sub, and state building blocks without forcing each microservice to reimplement them.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'jobs', 'label': 'Container Apps jobs', 'importance': 'medium', 'notes': 'Covers scheduled and event-driven background execution without standing up a separate worker platform.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'scale_to_zero', 'label': 'Scale to zero', 'importance': 'medium', 'notes': 'Preserves low idle cost when workloads only need compute during bursts or event windows.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'internal_ingress', 'label': 'Internal ingress and service discovery', 'importance': 'medium', 'notes': 'Keeps service-to-service traffic inside the environment boundary for private application topologies.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'functions_hosting', 'label': 'Azure Functions hosting on Container Apps', 'importance': 'medium', 'notes': 'Lets teams reuse Functions triggers while standardizing on the Container Apps environment and network model.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-cache',
        'display_name': 'Azure Cache for Redis / Managed Redis',
        'family': 'databases',
        'summary': 'Managed caching platform where zone posture, clustering, and network isolation are key regional planning factors.',
        'providers': [{'namespace': 'microsoft.cache', 'resource_types': ['redis', 'redisenterprise']}],
        'pricing': {
            'query_mode': 'first-match',
            'filters': [
                {'service_family': 'Databases', 'service_name': 'Redis Cache'},
            ],
        },
        'zone_support': {'default': 'both', 'notes': 'Availability zone support is documented for the service family, with tier-specific behavior differences.'},
        'capabilities': [
            {'key': 'active_geo_replication', 'label': 'Geo-replication', 'importance': 'high', 'notes': 'Important for cross-region cache continuity patterns.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'clustering', 'label': 'Clustered cache topology', 'importance': 'medium', 'notes': 'Relevant for higher-throughput cache architectures.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_link', 'label': 'Private Link', 'importance': 'high', 'notes': 'Common requirement in regulated landing zones.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-cosmos-db',
        'display_name': 'Azure Cosmos DB',
        'family': 'databases',
        'summary': 'Globally distributed NoSQL platform where regional presence and resiliency posture matter more than raw provider feature names.',
        'discovery_terms': ['cosmos', 'nosql', 'document database', 'mongodb', 'cassandra', 'gremlin', 'table api', 'vector database'],
        'providers': [{'namespace': 'microsoft.documentdb', 'resource_types': ['databaseaccounts', 'mongoclusters', 'cassandraclusters']}],
        'zone_support': {'default': 'zonal', 'notes': 'Zone support depends on API and account configuration.'},
        'capabilities': [
            {'key': 'nosql_accounts', 'label': 'NoSQL account model', 'importance': 'high', 'notes': 'Represents the core Cosmos DB account plane used for globally distributed document workloads and the wider API surface that hangs off a database account.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['databaseaccounts']},
            {'key': 'mongodb_compatibility', 'label': 'MongoDB-compatible API', 'importance': 'medium', 'notes': 'Keeps MongoDB-oriented application patterns visible in the regional comparison instead of leaving Mongo-specific resource types buried as raw provider metadata.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['mongoclusters']},
            {'key': 'cassandra_compatibility', 'label': 'Cassandra-compatible API', 'importance': 'medium', 'notes': 'Highlights Cassandra-style data models and migration paths directly in the curated matrix when the provider exposes Cassandra-specific resource types.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['cassandraclusters']},
            {'key': 'multi_region_writes', 'label': 'Multi-region writes', 'importance': 'high', 'notes': 'Lets the target region stay writable during failover instead of becoming a read-only secondary for the application tier.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'autoscale', 'label': 'Autoscale throughput', 'importance': 'medium', 'notes': 'Keeps RU capacity aligned with bursty demand so the move does not lock the workload into peak throughput pricing.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-sql-database',
        'display_name': 'Azure SQL Database',
        'family': 'databases',
        'summary': 'Managed relational database service with tier-dependent HA, scaling, and regional feature differences.',
        'providers': [{'namespace': 'microsoft.sql', 'resource_types': ['servers', 'servers/databases', 'elasticpools']}],
        'zone_support': {'default': 'zonal', 'notes': 'Zone support and resiliency depend on deployment model and selected tier.'},
        'capabilities': [
            {'key': 'serverless', 'label': 'Serverless compute option', 'importance': 'high', 'notes': 'Cuts idle database cost for intermittent workloads by pausing or shrinking compute when demand drops.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'hyperscale', 'label': 'Hyperscale tier', 'importance': 'high', 'notes': 'Supports very large OLTP estates, rapid storage growth, and read scale without redesigning the service model.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundancy', 'label': 'Zone redundant deployment option', 'importance': 'high', 'requires_zone_support': True, 'notes': 'Keeps the database service resilient to a single-zone failure when the selected tier supports it.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'geo_replication', 'label': 'Active geo-replication', 'importance': 'high', 'notes': 'Lets the target region participate in a live cross-region failover design instead of serving only as a restore location.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'auto_failover_groups', 'label': 'Auto-failover groups', 'importance': 'high', 'notes': 'Preserves stable listener endpoints so applications do not need a connection-string rewrite during failover.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Keeps the SQL data plane on private network paths for regulated or internal-only application estates.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'microsoft_entra_auth', 'label': 'Microsoft Entra authentication', 'importance': 'medium', 'notes': 'Aligns database access with centralized identity governance instead of SQL-only credential management.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'elastic_pools', 'label': 'Elastic pools', 'importance': 'medium', 'notes': 'Allows many databases to share a performance budget so migration cost stays predictable across pooled estates.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'long_term_retention', 'label': 'Long-term backup retention', 'importance': 'medium', 'notes': 'Provides the retention window many audit and recovery programs require after the move.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-sql-managed-instance',
        'display_name': 'Azure SQL Managed Instance',
        'family': 'databases',
        'summary': 'Managed SQL Server-compatible platform where failover groups, networking, and maintenance windows often determine target region fit.',
        'providers': [{'namespace': 'microsoft.sql', 'resource_types': ['managedinstances'], 'match_hints': {'resource_type_contains': ['managedinstances'], 'prefer_when_skus': True}}],
        'zone_support': {'default': 'zonal', 'notes': 'Feature configuration remains tier- and architecture-sensitive.'},
        'capabilities': [
            {'key': 'instance_failover_groups', 'label': 'Failover groups', 'importance': 'high', 'notes': 'Provides the cross-region continuity model most MI estates need for planned failover and disaster recovery.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'link_feature', 'label': 'SQL Server link capability', 'importance': 'medium', 'notes': 'Supports staged cutovers from SQL Server by keeping replication-based migration paths available.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private access patterns', 'importance': 'high', 'notes': 'Determines whether the instance can land in a private network posture without public SQL access.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'maintenance_window', 'label': 'Maintenance window scheduling', 'importance': 'high', 'notes': 'Lets platform updates align with business maintenance periods instead of forcing a platform-driven window.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundancy', 'label': 'Zone redundancy', 'importance': 'high', 'requires_zone_support': True, 'notes': 'Keeps the managed instance resilient to a zonal outage when the target region supports the configuration.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'instance_pools', 'label': 'Instance pools', 'importance': 'medium', 'notes': 'Speeds up provisioning and groups multiple managed instances under shared operational boundaries.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'license_free_dr', 'label': 'License-free disaster recovery replica', 'importance': 'medium', 'notes': 'Reduces the cost of keeping a standby MI recovery posture in a second region.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'geo_restore', 'label': 'Geo-restore', 'importance': 'medium', 'notes': 'Provides a backup-based recovery path when a live secondary instance is not part of the continuity design.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'service_tiers', 'label': 'General Purpose and Business Critical tiers', 'importance': 'medium', 'notes': 'Controls the latency, storage, and maintenance characteristics that often decide whether the region is a fit.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-postgresql',
        'display_name': 'Azure Database for PostgreSQL',
        'family': 'databases',
        'summary': 'Flexible server deployment with tier and HA options that vary by region and SKU availability.',
        'providers': [{'namespace': 'microsoft.dbforpostgresql', 'resource_types': ['flexibleservers', 'servergroupsv2']}],
        'zone_support': {'default': 'both', 'notes': 'Zonal and zone-redundant options depend on region and compute tier.'},
        'capabilities': [
            {'key': 'burstable', 'label': 'Burstable compute tier', 'importance': 'medium', 'notes': 'Useful for cost-sensitive workloads.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundant_ha', 'label': 'Zone-redundant high availability', 'importance': 'high', 'requires_zone_support': True, 'notes': 'Region and tier specific.', 'availability': {'default': 'available', 'regions': {}}},
        ],
        'regional_overrides': {
            'qatarcentral': {
                'notes': 'Recent comparison output shows flexible server provisioning restrictions in this region; validate live SKU availability before treating it as a PostgreSQL target',
                'capabilities': {
                    'burstable': {
                        'status': 'unavailable',
                        'notes': 'Treat burstable PostgreSQL flexible server availability as unavailable until live SKU output confirms otherwise in this region.',
                    },
                    'zone_redundant_ha': {
                        'status': 'unavailable',
                        'notes': 'Zone-redundant PostgreSQL high availability should be treated as unavailable when flexible server provisioning is restricted in this region.',
                    },
                },
            },
        },
    },
    {
        'service_key': 'azure-mysql',
        'display_name': 'Azure Database for MySQL',
        'family': 'databases',
        'summary': 'Flexible server database service with HA and burstable options that often drive region selection.',
        'providers': [{'namespace': 'microsoft.dbformysql', 'resource_types': ['flexibleservers']}],
        'zone_support': {'default': 'both', 'notes': 'Availability zone support is documented, but options can still be tier-dependent.'},
        'capabilities': [
            {'key': 'burstable', 'label': 'Burstable compute tier', 'importance': 'medium', 'notes': 'Useful for dev/test and seasonal workloads.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundant_ha', 'label': 'Zone-redundant high availability', 'importance': 'high', 'requires_zone_support': True, 'notes': 'Tier and region prerequisites still apply.', 'availability': {'default': 'available', 'regions': {}}},
        ],
        'regional_overrides': {
            'qatarcentral': {
                'notes': 'Recent comparison output returned no flexible server SKUs in this region; validate live service availability before treating it as a MySQL target',
                'capabilities': {
                    'burstable': {
                        'status': 'unavailable',
                        'notes': 'Treat burstable MySQL flexible server availability as unavailable until live SKU output confirms otherwise in this region.',
                    },
                    'zone_redundant_ha': {
                        'status': 'unavailable',
                        'notes': 'Zone-redundant MySQL high availability should be treated as unavailable when no flexible server SKUs are returned for this region.',
                    },
                },
            },
        },
    },
    {
        'service_key': 'azure-data-factory',
        'display_name': 'Azure Data Factory',
        'family': 'analytics',
        'summary': 'Managed orchestration service where managed virtual network and integration runtime patterns are more relevant than generic provider metadata.',
        'discovery_terms': ['fabric', 'data integration', 'etl', 'pipelines', 'lakehouse'],
        'providers': [{'namespace': 'microsoft.datafactory', 'resource_types': ['factories', 'integrationruntimes']}],
        'zone_support': {'default': 'zonal', 'notes': 'Service-level zone support is documented; specific execution paths can still vary.'},
        'capabilities': [
            {'key': 'factory_control_plane', 'label': 'Factory control plane', 'importance': 'high', 'notes': 'Keeps the core Data Factory workspace surface visible so orchestration reach is represented as a first-class capability instead of leftover provider metadata.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['factories']},
            {'key': 'managed_vnet', 'label': 'Managed virtual network', 'importance': 'high', 'notes': 'Important for private data estate connectivity.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'integration_runtime', 'label': 'Integration runtime patterns', 'importance': 'high', 'notes': 'Common requirement for hybrid data movement.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_link', 'label': 'Private Link', 'importance': 'medium', 'notes': 'Useful when isolating orchestration entry points.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-data-explorer',
        'display_name': 'Azure Data Explorer',
        'family': 'analytics',
        'summary': 'Managed analytics engine where ingestion, autoscale, and private networking posture commonly drive region selection.',
        'providers': [{'namespace': 'microsoft.kusto', 'resource_types': ['clusters', 'databases']}],
        'zone_support': {'default': 'zonal', 'notes': 'Validate exact cluster shape and networking posture in-region.'},
        'capabilities': [
            {'key': 'streaming_ingestion', 'label': 'Streaming ingestion', 'importance': 'high', 'notes': 'Important for near-real-time analytics workloads.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'autoscale', 'label': 'Autoscale clusters', 'importance': 'medium', 'notes': 'Useful for variable ingestion and query demand.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Common requirement in private analytical estates.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-storage',
        'display_name': 'Azure Storage',
        'family': 'storage',
        'summary': 'Core object, file, queue, and table storage platform where redundancy and network-isolation posture shape region selection.',
        'discovery_terms': ['fabric', 'onedlake', 'lakehouse', 'data lake', 'object storage'],
        'providers': [{'namespace': 'microsoft.storage', 'resource_types': ['storageaccounts', 'blobservices', 'fileservices', 'queueservices', 'tableservices']}],
        'zone_support': {'default': 'both', 'notes': 'Storage redundancy and zone posture depend on SKU and redundancy model.'},
        'capabilities': [
            {'key': 'zrs', 'label': 'Zone-redundant replication option', 'importance': 'high', 'requires_zone_support': True, 'notes': 'Keeps storage data available through a single-zone failure without changing the application storage endpoint.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'data_lake_gen2', 'label': 'Data Lake Storage Gen2', 'importance': 'high', 'notes': 'Preserves hierarchical namespace semantics needed for lakehouse, analytics, and big-data file patterns.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Allows blob, file, queue, and table access to stay on private network paths instead of public endpoints.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'sftp', 'label': 'SFTP endpoint support', 'importance': 'medium', 'notes': 'Keeps partner exchange and migration drop-zone workflows on the storage account without a separate gateway tier.', 'availability': {'default': 'unknown', 'regions': {}}},
            {'key': 'nfs_3', 'label': 'NFS 3.0 support', 'importance': 'medium', 'notes': 'Supports Linux and analytics workloads that expect file-system style access instead of object-only APIs.', 'availability': {'default': 'unknown', 'regions': {}}},
            {'key': 'large_file_shares', 'label': 'Large file shares', 'importance': 'medium', 'notes': 'Determines whether Azure Files can absorb larger enterprise file migrations without redesigning the share layout.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'blob_versioning', 'label': 'Blob versioning', 'importance': 'medium', 'notes': 'Provides built-in rollback protection when applications or operators overwrite or delete blob content.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'lifecycle_management', 'label': 'Lifecycle management', 'importance': 'medium', 'notes': 'Automates tiering, retention, and cleanup so storage cost posture stays controlled after migration.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'object_replication', 'label': 'Object replication', 'importance': 'medium', 'notes': 'Supports application-owned data movement patterns when account-level failover is not the only replication design.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'change_feed', 'label': 'Blob change feed', 'importance': 'medium', 'notes': 'Exposes an ordered blob-event history for downstream processing, audit, and event-driven storage workflows.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-kubernetes-service',
        'display_name': 'Azure Kubernetes Service',
        'family': 'containers',
        'summary': 'Managed Kubernetes platform where node pool, networking, and cluster operations posture drive region selection.',
        'providers': [{'namespace': 'microsoft.containerservice', 'resource_types': ['managedclusters']}],
        'zone_support': {'default': 'both', 'notes': 'Zonal and zone-redundant posture can vary by architecture and node pool design.'},
        'capabilities': [
            {'key': 'availability_zones', 'label': 'Availability-zone node pools', 'importance': 'high', 'requires_zone_support': True, 'notes': 'Lets control plane and node pools span zones so the cluster can keep serving through a zonal failure.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_cluster', 'label': 'Private cluster mode', 'importance': 'high', 'notes': 'Keeps the Kubernetes API private so cluster administration stays inside approved network boundaries.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'workload_identity', 'label': 'Workload identity', 'importance': 'medium', 'notes': 'Removes secret-based pod credentials by binding Kubernetes workloads directly to Microsoft Entra identities.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'cni_overlay', 'label': 'Azure CNI overlay networking', 'importance': 'medium', 'notes': 'Reduces VNet IP pressure when the target region has tighter address-planning constraints for pods.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'automatic_mode', 'label': 'AKS Automatic operating mode', 'importance': 'high', 'notes': 'Provides a more opinionated operating model when teams want Microsoft-managed defaults for day-2 platform work.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'node_autoprovisioning', 'label': 'Node autoprovisioning', 'importance': 'high', 'notes': 'Allows AKS to add new node shapes as workloads change instead of forcing operators to pre-model every pool.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'auto_upgrade', 'label': 'Automatic cluster upgrades', 'importance': 'high', 'notes': 'Keeps clusters in a supported version window without repeated manual upgrade choreography.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'planned_maintenance', 'label': 'Planned maintenance windows', 'importance': 'medium', 'notes': 'Lets upgrades and maintenance events land inside workload-approved operating windows.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'keda', 'label': 'KEDA event-driven scaling', 'importance': 'medium', 'notes': 'Supports queue- and event-driven workloads that need pod scale to follow bursty external signals.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'gitops', 'label': 'GitOps and config management', 'importance': 'medium', 'notes': 'Keeps cluster state declarative so platform teams can manage drift and promotion through source control.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-container-registry',
        'display_name': 'Azure Container Registry',
        'family': 'containers',
        'summary': 'Container image registry where replication, private networking, and content trust posture affect region planning.',
        'discovery_terms': ['acr', 'container registry', 'registry', 'oci registry', 'artifact registry', 'container images'],
        'providers': [{'namespace': 'microsoft.containerregistry', 'resource_types': ['registries']}],
        'zone_support': {'default': 'regional', 'notes': 'Registry service is regional; replication and network posture often matter more than raw zone semantics.'},
        'capabilities': [
            {'key': 'registry_endpoints', 'label': 'Registry endpoints and repositories', 'importance': 'high', 'notes': 'Represents the core ACR registry surface so image hosting and repository management show up as a curated capability instead of leftover raw provider metadata.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['registries']},
            {'key': 'geo_replication', 'label': 'Geo-replication', 'importance': 'high', 'notes': 'Pre-stages images in the destination region so clusters and app platforms are not pulling every rollout across regions.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_link', 'label': 'Private Link', 'importance': 'high', 'notes': 'Keeps image pulls and push workflows on private network paths when the supply chain cannot traverse the public internet.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'content_trust', 'label': 'Content trust and governance', 'importance': 'medium', 'notes': 'Protects release workflows with signing, retention, and governance controls so the replicated registry does not weaken deployment guardrails.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-synapse-analytics',
        'display_name': 'Azure Synapse Analytics',
        'family': 'analytics',
        'summary': 'Unified analytics service where managed networking, SQL pool choices, and Data Explorer availability are often more relevant than raw provider status.',
        'discovery_terms': ['fabric', 'lakehouse', 'warehouse', 'analytics', 'big data', 'onedlake'],
        'providers': [{'namespace': 'microsoft.synapse', 'resource_types': ['workspaces', 'sqlpools', 'bigdatapools', 'kustopools']}],
        'zone_support': {'default': 'unknown', 'notes': 'Use curated service guidance because public provider metadata is much less descriptive than workload-level architecture concerns.'},
        'capabilities': [
            {'key': 'workspace_plane', 'label': 'Workspace control plane', 'importance': 'high', 'notes': 'Captures the core Synapse workspace surface so shared analytics workspace reach is represented explicitly in the curated comparison.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['workspaces']},
            {'key': 'dedicated_sql_pools', 'label': 'Dedicated SQL pools', 'importance': 'high', 'notes': 'Key for data warehouse migration planning.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'data_explorer_pools', 'label': 'Data Explorer pools', 'importance': 'high', 'notes': 'Important when Synapse is being used for Kusto-backed analytics and log exploration workloads.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'managed_vnet', 'label': 'Managed virtual network', 'importance': 'high', 'notes': 'Common requirement for private data estate connectivity.', 'availability': {'default': 'available', 'regions': {}}},
        ],
        'regional_overrides': {
            'qatarcentral': {
                'notes': 'Recent comparison output showed no Synapse Kusto pool SKUs in this region; treat Data Explorer pool availability as a validation item.',
                'capabilities': {
                    'data_explorer_pools': {
                        'status': 'unavailable',
                        'notes': 'Treat Synapse Data Explorer pools as unavailable until live SKU output confirms Kusto pool support in this region.',
                    },
                },
            },
            'swedencentral': {
                'notes': 'Managed networking and dedicated SQL pool posture should be validated directly in-region.',
                'capabilities': {
                    'managed_vnet': {
                        'status': 'unknown',
                        'notes': 'Validate managed virtual network behavior directly in the target region before migration commitment.',
                    },
                },
            },
        },
    },
    {
        'service_key': 'azure-databricks',
        'display_name': 'Azure Databricks',
        'family': 'analytics',
        'summary': 'Managed lakehouse platform where private networking, SQL workload maturity, and governance features often shape region choice.',
        'discovery_terms': ['fabric', 'lakehouse', 'spark', 'delta lake', 'analytics'],
        'providers': [{'namespace': 'microsoft.databricks', 'resource_types': ['workspaces']}],
        'zone_support': {'default': 'zonal', 'notes': 'The availability-zones support matrix lists Azure Databricks with zonal service support.'},
        'capabilities': [
            {'key': 'workspace_plane', 'label': 'Workspace control plane', 'importance': 'high', 'notes': 'Captures the Databricks workspace layer directly so the primary platform surface is not left behind as raw provider metadata.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['workspaces']},
            {'key': 'private_link', 'label': 'Private Link and private connectivity', 'importance': 'high', 'notes': 'Important for controlled data-plane connectivity.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'unity_catalog', 'label': 'Unity Catalog governance', 'importance': 'high', 'notes': 'Often a core lakehouse platform requirement.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'sql_warehouses', 'label': 'SQL warehouses', 'importance': 'medium', 'notes': 'Relevant when consolidating BI and ad hoc analytics patterns.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-ai-services',
        'display_name': 'Azure AI Services',
        'family': 'machinelearningservices',
        'summary': 'Shared Azure AI services view for Cognitive Services style regional comparisons where pricing is published under product families rather than the provider namespace.',
        'discovery_terms': ['ai', 'azure ai', 'azure openai', 'openai', 'foundry', 'azure ai foundry', 'cognitive services', 'speech', 'vision', 'language', 'translator', 'document intelligence', 'content safety'],
        'providers': [{'namespace': 'microsoft.cognitiveservices', 'resource_types': ['accounts']}],
        'pricing': {
            'query_mode': 'merge',
            'filters': [
                {'service_family': 'AI + Machine Learning', 'service_name': 'Foundry Tools', 'product_name_contains': 'Azure Speech'},
                {'service_family': 'AI + Machine Learning', 'service_name': 'Foundry Tools', 'product_name_contains': 'Azure Vision'},
                {'service_family': 'AI + Machine Learning', 'service_name': 'Foundry Tools', 'product_name_contains': 'Azure Document Intelligence'},
                {'service_family': 'AI + Machine Learning', 'service_name': 'Foundry Tools', 'product_name_contains': 'Azure AI Language'},
                {'service_family': 'AI + Machine Learning', 'service_name': 'Foundry Tools', 'product_name_contains': 'Azure AI Content Safety'},
                {'service_family': 'AI + Machine Learning', 'service_name': 'Foundry Tools', 'product_name_contains': 'Azure Translator'},
            ],
        },
        'zone_support': {'default': 'unknown', 'notes': 'Validate the specific AI capability and SKU directly in-region before migration commitment.'},
        'capabilities': [
            {'key': 'ai_accounts', 'label': 'AI account surface', 'importance': 'high', 'notes': 'Represents the primary Azure AI account plane so core AI service reach is visible directly in the matrix.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['accounts']},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Common requirement for regulated AI workloads.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'managed_identity', 'label': 'Managed identity integration', 'importance': 'high', 'notes': 'Important for service-to-service Azure authentication.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-ai-search',
        'display_name': 'Azure AI Search',
        'family': 'analytics',
        'summary': 'Managed search platform where vector search, semantic ranking, indexing reach, and private connectivity shape region selection.',
        'discovery_terms': ['ai', 'azure ai', 'azure ai search', 'foundry', 'azure ai foundry', 'rag', 'retrieval augmented generation', 'vector search', 'semantic search', 'openai'],
        'providers': [{'namespace': 'microsoft.search', 'resource_types': ['searchservices']}],
        'pricing': {
            'query_mode': 'first-match',
            'filters': [
                {'service_name': 'Azure Cognitive Search'},
            ],
        },
        'zone_support': {'default': 'unknown', 'notes': 'Validate service tier and resiliency posture directly in the target region.'},
        'capabilities': [
            {'key': 'search_service_plane', 'label': 'Search service plane', 'importance': 'high', 'notes': 'Captures the managed search service surface directly so the core search endpoint is treated as curated capability coverage.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['searchservices']},
            {'key': 'vector_search', 'label': 'Vector search', 'importance': 'high', 'notes': 'Important for retrieval and knowledge-mining workloads.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'semantic_ranking', 'label': 'Semantic ranking', 'importance': 'high', 'notes': 'Often required for AI-assisted search relevance.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'indexers_skillsets', 'label': 'Indexers and skillsets', 'importance': 'high', 'notes': 'Useful when regional readiness is tied to ingestion pipelines.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Important for private search estates and regulated workloads.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'shared_private_link', 'label': 'Shared private link resources', 'importance': 'medium', 'notes': 'Relevant for tightly controlled data-plane connectivity.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-service-bus',
        'display_name': 'Azure Service Bus',
        'family': 'messaging',
        'summary': 'Enterprise messaging platform where premium capacity, private access, and disaster-recovery posture commonly drive regional decisions.',
        'discovery_terms': ['service bus', 'messaging', 'queues', 'topics', 'pubsub', 'namespace'],
        'providers': [{'namespace': 'microsoft.servicebus', 'resource_types': ['namespaces', 'queues', 'topics']}],
        'zone_support': {'default': 'unknown', 'notes': 'Validate the selected namespace tier and resiliency posture directly in-region.'},
        'capabilities': [
            {'key': 'namespace_plane', 'label': 'Namespace control plane', 'importance': 'high', 'notes': 'Represents the namespace boundary that owns queues, topics, networking, and tiering so the Service Bus control surface is explicit in the curated view.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['namespaces']},
            {'key': 'premium_tier', 'label': 'Premium messaging tier', 'importance': 'high', 'notes': 'Provides the isolated capacity and predictable latency many enterprise integration estates need before they can move regions cleanly.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'geo_disaster_recovery', 'label': 'Geo-disaster recovery', 'importance': 'high', 'notes': 'Preserves namespace failover aliases so producers and consumers are not forced into endpoint rewrites during regional recovery.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'notes': 'Keeps queues and topics reachable only from approved networks when messaging is part of a private integration backbone.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'sessions_transactions', 'label': 'Sessions and transactions', 'importance': 'medium', 'notes': 'Maintains ordered processing and exactly-once workflow guarantees so app behavior does not change after the move.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'partitioned_entities', 'label': 'Partitioned queues and topics', 'importance': 'medium', 'notes': 'Helps the target region absorb higher message volume without forcing a namespace redesign for throughput alone.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-machine-learning',
        'display_name': 'Azure Machine Learning',
        'family': 'machinelearningservices',
        'summary': 'Managed ML platform where workspace reach, managed endpoints, compute options, and private connectivity shape region selection.',
        'discovery_terms': ['ai', 'ml', 'machine learning', 'azure ml', 'foundry', 'azure ai foundry', 'model registry', 'training', 'inference'],
        'providers': [{'namespace': 'microsoft.machinelearningservices', 'resource_types': ['workspaces', 'workspaces/computes', 'workspaces/onlineendpoints', 'registries']}],
        'zone_support': {'default': 'unknown', 'notes': 'Validate workspace features, endpoint posture, and compute families directly in the target region.'},
        'capabilities': [
            {'key': 'workspace_plane', 'label': 'Workspace control plane', 'importance': 'high', 'notes': 'Represents the central Azure Machine Learning workspace surface that governs assets, networking, and team workflows in-region.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['workspaces']},
            {'key': 'managed_online_endpoints', 'label': 'Managed online endpoints', 'importance': 'high', 'notes': 'Important for real-time inference migration targets.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['workspaces/onlineendpoints']},
            {'key': 'batch_endpoints', 'label': 'Batch endpoints', 'importance': 'medium', 'notes': 'Useful when regional choice is driven by scheduled inference workflows.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'serverless_or_managed_compute', 'label': 'Managed and serverless compute options', 'importance': 'high', 'notes': 'Relevant for balancing experimentation, training, and cost posture.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['workspaces/computes']},
            {'key': 'model_registry', 'label': 'Model registry and workspace assets', 'importance': 'medium', 'notes': 'Important for promotion flows across regions and environments.', 'availability': {'default': 'available', 'regions': {}}, 'resource_types': ['registries']},
            {'key': 'private_networking', 'label': 'Private networking and isolated workspaces', 'importance': 'high', 'notes': 'Common requirement for secure ML platforms.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-application-insights',
        'display_name': 'Azure Monitor Application Insights',
        'family': 'monitoring',
        'summary': 'Observability platform where workspace integration, private telemetry paths, and live diagnostics maturity affect regional readiness.',
        'providers': [{'namespace': 'microsoft.insights', 'resource_types': ['components', 'actiongroups', 'metricalerts', 'scheduledqueryrules']}],
        'zone_support': {'default': 'regional', 'notes': 'Monitoring resources are regional; validate the exact data path and workspace architecture for production cutovers.'},
        'capabilities': [
            {'key': 'workspace_based_mode', 'label': 'Workspace-based telemetry', 'importance': 'high', 'notes': 'Important for modern Azure Monitor and Log Analytics integration.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'application_map', 'label': 'Application map and distributed tracing', 'importance': 'medium', 'notes': 'Useful for migration validation and dependency mapping.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'live_metrics', 'label': 'Live metrics and near-real-time diagnostics', 'importance': 'medium', 'notes': 'Relevant when operational visibility is part of the regional decision.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_link', 'label': 'Private Link and network-isolated ingestion', 'importance': 'high', 'notes': 'Important for regulated monitoring estates.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'alerting_automation', 'label': 'Alerting and automation hooks', 'importance': 'high', 'notes': 'Common requirement for production-grade monitoring rollouts.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-networking-platform',
        'display_name': 'Azure Networking Platform',
        'family': 'networking',
        'summary': 'Shared networking platform view for Microsoft.Network where private connectivity, ingress, egress, security, and observability features drive region selection more than a single resource type does.',
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['virtualnetworks', 'privateendpoints', 'applicationgateways', 'loadbalancers', 'azurefirewalls', 'vpngateways', 'networkwatchers']}],
        'zone_support': {'default': 'unknown', 'notes': 'Networking feature posture varies by resource type; validate the exact target architecture directly in-region.'},
        'capabilities': [
            {'key': 'private_connectivity', 'label': 'Private endpoints and private connectivity', 'importance': 'high', 'notes': 'Important when landing zones rely on private PaaS access.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'layer4_layer7_ingress', 'label': 'Layer 4 and Layer 7 ingress options', 'importance': 'high', 'notes': 'Useful when comparing application gateways, load balancers, and ingress patterns.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'hybrid_connectivity', 'label': 'Hybrid connectivity', 'importance': 'high', 'notes': 'Relevant for VPN, ExpressRoute, and cross-premises designs.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'network_security_controls', 'label': 'Firewall and security controls', 'importance': 'high', 'notes': 'Important for protected perimeter and east-west traffic designs.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'network_observability', 'label': 'Network observability', 'importance': 'medium', 'notes': 'Relevant for Network Watcher, diagnostics, and validation during cutovers.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-analysis-services',
        'display_name': 'Azure Analysis Services',
        'family': 'analytics',
        'summary': 'Managed semantic model platform where scale-out, backup posture, and migration readiness shape region selection.',
        'providers': [{'namespace': 'microsoft.analysisservices', 'resource_types': ['servers']}],
        'zone_support': {'default': 'unknown', 'notes': 'Public feature and zone semantics are less explicit than for newer analytics services.'},
        'capabilities': [
            {'key': 'query_scale_out', 'label': 'Query scale-out', 'importance': 'high', 'notes': 'Important for large BI model deployments.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'backup_restore', 'label': 'Backup and restore', 'importance': 'medium', 'notes': 'Frequently part of migration and DR planning.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-netapp-files',
        'display_name': 'Azure NetApp Files',
        'family': 'storage',
        'summary': 'Enterprise file storage platform where protocol support, replication, and performance tiers strongly influence regional fit.',
        'providers': [{'namespace': 'microsoft.netapp', 'resource_types': ['netappaccounts', 'capacitypools', 'volumes']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'The availability-zones support matrix lists Azure NetApp Files with zone-redundant support.'},
        'capabilities': [
            {'key': 'nfs_smb', 'label': 'NFS and SMB protocols', 'importance': 'high', 'notes': 'Important for enterprise NAS migrations.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'cross_region_replication', 'label': 'Cross-region replication', 'importance': 'high', 'notes': 'Often a deciding factor for business continuity patterns.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'snapshot_policies', 'label': 'Snapshot policies', 'importance': 'medium', 'notes': 'Relevant for enterprise backup and restore workflows.', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-key-vault',
        'display_name': 'Azure Key Vault',
        'family': 'security',
        'summary': 'Managed secrets, keys, and certificate management with HSM-backed options.',
        'discovery_terms': ['key vault', 'keyvault', 'secrets', 'certificates', 'hsm'],
        'providers': [{'namespace': 'microsoft.keyvault', 'resource_types': ['vaults', 'managedhsms']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Key Vault is zone-redundant by default in regions with AZs.'},
        'capabilities': [
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'managed_hsm', 'label': 'Managed HSM', 'importance': 'high', 'notes': 'HSM-backed key management; not available in all regions.', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'rbac_authorization', 'label': 'RBAC authorization', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-event-hubs',
        'display_name': 'Azure Event Hubs',
        'family': 'integration',
        'summary': 'Managed event streaming platform for big data pipelines and event-driven architectures.',
        'discovery_terms': ['event hubs', 'eventhub', 'kafka', 'streaming'],
        'providers': [{'namespace': 'microsoft.eventhub', 'resource_types': ['namespaces', 'clusters']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Premium and Dedicated tiers support zone-redundancy.'},
        'capabilities': [
            {'key': 'kafka_protocol', 'label': 'Kafka protocol support', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'schema_registry', 'label': 'Schema Registry', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundancy', 'label': 'Zone-redundant namespaces', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-event-grid',
        'display_name': 'Azure Event Grid',
        'family': 'integration',
        'summary': 'Serverless event routing service for event-driven architectures.',
        'discovery_terms': ['event grid', 'events', 'event routing'],
        'providers': [{'namespace': 'microsoft.eventgrid', 'resource_types': ['topics', 'domains', 'namespaces']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Automatically zone-redundant in regions with AZs.'},
        'capabilities': [
            {'key': 'custom_topics', 'label': 'Custom topics', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'namespace_topics', 'label': 'Namespace topics (pull delivery)', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-load-balancer',
        'display_name': 'Azure Load Balancer',
        'family': 'networking',
        'summary': 'Layer 4 load balancing for VMs and VMSS with Standard and Basic tiers.',
        'discovery_terms': ['load balancer', 'lb', 'layer 4'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['loadbalancers']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Standard Load Balancer is zone-redundant by default.'},
        'capabilities': [
            {'key': 'standard_sku', 'label': 'Standard SKU', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'cross_region_lb', 'label': 'Cross-region load balancing', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundancy', 'label': 'Zone-redundant frontend', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-application-gateway',
        'display_name': 'Azure Application Gateway',
        'family': 'networking',
        'summary': 'Layer 7 load balancer with WAF, SSL termination, and URL-based routing.',
        'discovery_terms': ['application gateway', 'app gateway', 'appgw', 'waf'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['applicationgateways']}],
        'zone_support': {'default': 'zonal', 'notes': 'V2 SKU supports zone-redundant deployments.'},
        'capabilities': [
            {'key': 'waf_v2', 'label': 'WAF v2 policy', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_link', 'label': 'Private Link support', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundancy', 'label': 'Zone-redundant deployment', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-firewall',
        'display_name': 'Azure Firewall',
        'family': 'networking',
        'summary': 'Cloud-native network firewall with threat intelligence and IDPS.',
        'discovery_terms': ['azure firewall', 'firewall', 'idps'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['azurefirewalls', 'firewallpolicies']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Zone-redundant by default when deployed across availability zones.'},
        'capabilities': [
            {'key': 'premium_tier', 'label': 'Premium tier (IDPS, TLS inspection)', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'forced_tunneling', 'label': 'Forced tunneling', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundancy', 'label': 'Zone-redundant deployment', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-vpn-gateway',
        'display_name': 'Azure VPN Gateway',
        'family': 'networking',
        'summary': 'Site-to-site, point-to-site, and VNet-to-VNet VPN connectivity.',
        'discovery_terms': ['vpn gateway', 'vpn', 's2s', 'p2s'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['virtualnetworkgateways', 'vpngateways']}],
        'zone_support': {'default': 'zonal', 'notes': 'AZ SKU variants provide zone-redundant deployment.'},
        'capabilities': [
            {'key': 'zone_redundant_sku', 'label': 'Zone-redundant gateway SKUs', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'active_active', 'label': 'Active-active configuration', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-front-door',
        'display_name': 'Azure Front Door',
        'family': 'networking',
        'summary': 'Global load balancer and CDN with WAF and SSL offloading.',
        'discovery_terms': ['front door', 'afd', 'cdn', 'global lb'],
        'providers': [{'namespace': 'microsoft.cdn', 'resource_types': ['profiles']}],
        'zone_support': {'default': 'regional', 'notes': 'Global service; not region-scoped for zone support.'},
        'capabilities': [
            {'key': 'waf_policy', 'label': 'WAF policy', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_link_origins', 'label': 'Private Link origins', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'rules_engine', 'label': 'Rules engine', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-dns',
        'display_name': 'Azure DNS',
        'family': 'networking',
        'summary': 'Managed DNS hosting and private DNS zones.',
        'discovery_terms': ['dns', 'private dns'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['dnszones', 'privatednszones']}],
        'zone_support': {'default': 'regional', 'notes': 'Global anycast service; region is for metadata.'},
        'capabilities': [
            {'key': 'private_dns_zones', 'label': 'Private DNS zones', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-nat-gateway',
        'display_name': 'Azure NAT Gateway',
        'family': 'networking',
        'summary': 'Managed outbound NAT for virtual networks.',
        'discovery_terms': ['nat gateway', 'outbound nat'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['natgateways']}],
        'zone_support': {'default': 'zonal', 'notes': 'Can be deployed zonally; zone-redundancy depends on configuration.'},
        'capabilities': [
            {'key': 'zone_isolation', 'label': 'Zone isolation', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-virtual-network',
        'display_name': 'Azure Virtual Network',
        'family': 'networking',
        'summary': 'Foundation networking service for private network isolation.',
        'discovery_terms': ['virtual network', 'vnet', 'nsg', 'subnet'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['virtualnetworks', 'publicipaddresses', 'networksecuritygroups']}],
        'zone_support': {'default': 'regional', 'notes': 'VNets span all availability zones in a region.'},
        'capabilities': [
            {'key': 'vnet_peering', 'label': 'VNet peering', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'service_endpoints', 'label': 'Service endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-expressroute',
        'display_name': 'Azure ExpressRoute',
        'family': 'networking',
        'summary': 'Private connectivity from on-premises to Azure via dedicated circuits.',
        'discovery_terms': ['expressroute', 'express route', 'private connectivity'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['expressroutecircuits', 'expressroutegateways']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'ExpressRoute gateways support zone-redundant SKUs.'},
        'capabilities': [
            {'key': 'zone_redundant_gateway', 'label': 'Zone-redundant gateway SKUs', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'fastpath', 'label': 'FastPath (Ultra performance)', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-traffic-manager',
        'display_name': 'Azure Traffic Manager',
        'family': 'networking',
        'summary': 'DNS-based traffic load balancer for global traffic distribution.',
        'discovery_terms': ['traffic manager', 'global dns lb'],
        'providers': [{'namespace': 'microsoft.network', 'resource_types': ['trafficmanagerprofiles']}],
        'zone_support': {'default': 'regional', 'notes': 'Global service; not AZ-scoped.'},
        'capabilities': [
            {'key': 'multi_value_routing', 'label': 'Multi-value routing', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-log-analytics',
        'display_name': 'Azure Log Analytics',
        'family': 'monitoring',
        'summary': 'Centralized log collection and KQL query engine for Azure Monitor.',
        'discovery_terms': ['log analytics', 'oms', 'kusto', 'kql'],
        'providers': [{'namespace': 'microsoft.operationalinsights', 'resource_types': ['workspaces', 'clusters']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Workspaces are zone-redundant in supported regions.'},
        'capabilities': [
            {'key': 'dedicated_clusters', 'label': 'Dedicated clusters', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'cmk_encryption', 'label': 'Customer-managed key encryption', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-batch',
        'display_name': 'Azure Batch',
        'family': 'compute',
        'summary': 'Managed HPC and batch processing service.',
        'discovery_terms': ['batch', 'hpc', 'batch processing'],
        'providers': [{'namespace': 'microsoft.batch', 'resource_types': ['batchaccounts']}],
        'zone_support': {'default': 'zonal', 'notes': 'Pools can target specific availability zones.'},
        'capabilities': [
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_redundancy', 'label': 'Zonal pool placement', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-backup',
        'display_name': 'Azure Backup',
        'family': 'management',
        'summary': 'Centralized backup service for VMs, databases, files, and workloads.',
        'discovery_terms': ['backup', 'recovery services', 'rsv'],
        'providers': [{'namespace': 'microsoft.recoveryservices', 'resource_types': ['vaults']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Recovery Services vaults support ZRS and GRS storage redundancy.'},
        'capabilities': [
            {'key': 'zrs_storage', 'label': 'ZRS vault storage', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'cross_region_restore', 'label': 'Cross-region restore', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-site-recovery',
        'display_name': 'Azure Site Recovery',
        'family': 'management',
        'summary': 'Disaster recovery orchestration for VMs and on-premises workloads.',
        'discovery_terms': ['site recovery', 'asr', 'disaster recovery', 'dr'],
        'providers': [{'namespace': 'microsoft.recoveryservices', 'resource_types': ['vaults']}],
        'zone_support': {'default': 'regional', 'notes': 'Cross-region service; vault is regional.'},
        'capabilities': [
            {'key': 'azure_to_azure', 'label': 'Azure-to-Azure replication', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-signalr-service',
        'display_name': 'Azure SignalR Service',
        'family': 'app-services',
        'summary': 'Managed real-time messaging service for web applications.',
        'discovery_terms': ['signalr', 'web pubsub', 'real-time'],
        'providers': [{'namespace': 'microsoft.signalrservice', 'resource_types': ['signalr', 'webpubsub']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Premium tier is zone-redundant.'},
        'capabilities': [
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-iot-hub',
        'display_name': 'Azure IoT Hub',
        'family': 'iot',
        'summary': 'Managed IoT message broker and device management platform.',
        'discovery_terms': ['iot hub', 'iot', 'devices'],
        'providers': [{'namespace': 'microsoft.devices', 'resource_types': ['iothubs', 'provisioningservices']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Zone-redundant in regions with availability zones.'},
        'capabilities': [
            {'key': 'device_provisioning', 'label': 'Device Provisioning Service', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-automation',
        'display_name': 'Azure Automation',
        'family': 'management',
        'summary': 'Cloud-based automation and configuration management (runbooks, DSC).',
        'discovery_terms': ['automation', 'runbooks', 'dsc'],
        'providers': [{'namespace': 'microsoft.automation', 'resource_types': ['automationaccounts']}],
        'zone_support': {'default': 'regional', 'notes': 'Regional service.'},
        'capabilities': [
            {'key': 'hybrid_runbook_worker', 'label': 'Hybrid Runbook Worker', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-stream-analytics',
        'display_name': 'Azure Stream Analytics',
        'family': 'analytics',
        'summary': 'Real-time stream processing and analytics engine.',
        'discovery_terms': ['stream analytics', 'asa', 'real-time analytics'],
        'providers': [{'namespace': 'microsoft.streamanalytics', 'resource_types': ['streamingjobs', 'clusters']}],
        'zone_support': {'default': 'regional', 'notes': 'Dedicated clusters support zone-redundancy.'},
        'capabilities': [
            {'key': 'dedicated_clusters', 'label': 'Dedicated clusters', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-purview',
        'display_name': 'Microsoft Purview',
        'family': 'analytics',
        'summary': 'Unified data governance and compliance service.',
        'discovery_terms': ['purview', 'data governance', 'data catalog'],
        'providers': [{'namespace': 'microsoft.purview', 'resource_types': ['accounts']}],
        'zone_support': {'default': 'regional', 'notes': 'Regional service.'},
        'capabilities': [
            {'key': 'data_map', 'label': 'Data Map', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-communication-services',
        'display_name': 'Azure Communication Services',
        'family': 'integration',
        'summary': 'Communication APIs for voice, video, chat, SMS, and email.',
        'discovery_terms': ['communication services', 'acs', 'sms', 'voice'],
        'providers': [{'namespace': 'microsoft.communication', 'resource_types': ['communicationservices']}],
        'zone_support': {'default': 'regional', 'notes': 'Global resource; region selection affects data residency.'},
        'capabilities': [
            {'key': 'voice_calling', 'label': 'Voice calling (PSTN)', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'email', 'label': 'Email communication', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-service-fabric',
        'display_name': 'Azure Service Fabric',
        'family': 'containers',
        'summary': 'Microservices platform for stateful and stateless service hosting.',
        'discovery_terms': ['service fabric', 'microservices platform'],
        'providers': [{'namespace': 'microsoft.servicefabric', 'resource_types': ['clusters', 'managedclusters']}],
        'zone_support': {'default': 'zonal', 'notes': 'Managed clusters support zone-spanning node types.'},
        'capabilities': [
            {'key': 'managed_clusters', 'label': 'Managed clusters', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'zone_spanning', 'label': 'Zone-spanning node types', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-red-hat-openshift',
        'display_name': 'Azure Red Hat OpenShift',
        'family': 'containers',
        'summary': 'Managed Red Hat OpenShift clusters on Azure.',
        'discovery_terms': ['aro', 'openshift', 'red hat'],
        'providers': [{'namespace': 'microsoft.redhatopenshift', 'resource_types': ['openshiftclusters']}],
        'zone_support': {'default': 'zonal', 'notes': 'Worker nodes can be spread across zones.'},
        'capabilities': [
            {'key': 'private_clusters', 'label': 'Private clusters', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-elastic-san',
        'display_name': 'Azure Elastic SAN',
        'family': 'storage',
        'summary': 'Cloud-native SAN service for block storage volumes.',
        'discovery_terms': ['elastic san', 'block storage', 'san'],
        'providers': [{'namespace': 'microsoft.elasticsan', 'resource_types': ['elasticsans']}],
        'zone_support': {'default': 'zone-redundant', 'notes': 'Supports LRS and ZRS redundancy options.'},
        'capabilities': [
            {'key': 'zrs_redundancy', 'label': 'Zone-redundant storage', 'importance': 'high', 'requires_zone_support': True, 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-relay',
        'display_name': 'Azure Relay',
        'family': 'integration',
        'summary': 'Hybrid connection service for exposing on-premises services to the cloud.',
        'discovery_terms': ['relay', 'hybrid connections'],
        'providers': [{'namespace': 'microsoft.relay', 'resource_types': ['namespaces']}],
        'zone_support': {'default': 'regional', 'notes': 'Regional service.'},
        'capabilities': [
            {'key': 'hybrid_connections', 'label': 'Hybrid Connections', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-notification-hubs',
        'display_name': 'Azure Notification Hubs',
        'family': 'integration',
        'summary': 'Push notification engine for mobile and web applications.',
        'discovery_terms': ['notification hubs', 'push notifications'],
        'providers': [{'namespace': 'microsoft.notificationhubs', 'resource_types': ['namespaces']}],
        'zone_support': {'default': 'regional', 'notes': 'Regional service.'},
        'capabilities': [
            {'key': 'premium_tier', 'label': 'Premium tier', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-chaos-studio',
        'display_name': 'Azure Chaos Studio',
        'family': 'management',
        'summary': 'Chaos engineering service for fault injection and resilience testing.',
        'discovery_terms': ['chaos studio', 'chaos engineering', 'fault injection'],
        'providers': [{'namespace': 'microsoft.chaos', 'resource_types': ['experiments', 'targets']}],
        'zone_support': {'default': 'regional', 'notes': 'Regional service.'},
        'capabilities': [],
    },
    {
        'service_key': 'azure-static-web-apps',
        'display_name': 'Azure Static Web Apps',
        'family': 'app-services',
        'summary': 'Hosting for static web apps with integrated serverless APIs.',
        'discovery_terms': ['static web apps', 'swa', 'jamstack'],
        'providers': [{'namespace': 'microsoft.web', 'resource_types': ['staticsites']}],
        'zone_support': {'default': 'regional', 'notes': 'Global CDN distribution; metadata is regional.'},
        'capabilities': [
            {'key': 'private_endpoints', 'label': 'Private endpoints', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
    {
        'service_key': 'azure-confidential-ledger',
        'display_name': 'Azure Confidential Ledger',
        'family': 'security',
        'summary': 'Tamper-proof, append-only ledger backed by confidential computing.',
        'discovery_terms': ['confidential ledger', 'tamper proof'],
        'providers': [{'namespace': 'microsoft.confidentialledger', 'resource_types': ['ledgers']}],
        'zone_support': {'default': 'regional', 'notes': 'Regional service.'},
        'capabilities': [],
    },
    {
        'service_key': 'azure-storage-mover',
        'display_name': 'Azure Storage Mover',
        'family': 'storage',
        'summary': 'Managed data migration service for Azure Storage.',
        'discovery_terms': ['storage mover', 'data migration'],
        'providers': [{'namespace': 'microsoft.storagemover', 'resource_types': ['storagemovers']}],
        'zone_support': {'default': 'regional', 'notes': 'Regional service.'},
        'capabilities': [],
    },
    {
        'service_key': 'azure-container-instances',
        'display_name': 'Azure Container Instances',
        'family': 'containers',
        'summary': 'Serverless containers without orchestration overhead.',
        'discovery_terms': ['container instances', 'aci', 'serverless containers'],
        'providers': [{'namespace': 'microsoft.containerinstance', 'resource_types': ['containergroups']}],
        'zone_support': {'default': 'zonal', 'notes': 'Zonal placement available in supported regions.'},
        'capabilities': [
            {'key': 'vnet_integration', 'label': 'VNet integration', 'importance': 'high', 'availability': {'default': 'available', 'regions': {}}},
            {'key': 'gpu_support', 'label': 'GPU-enabled container groups', 'importance': 'medium', 'availability': {'default': 'available', 'regions': {}}},
        ],
    },
]


PROVIDER_INDEX: dict[str, list[dict[str, Any]]] = {}
SERVICE_INDEX: dict[str, dict[str, Any]] = {}
for service in CATALOG:
    service_key = str(service.get('service_key', '')).lower()
    if service_key:
        SERVICE_INDEX[service_key] = service
    for binding in service.get('providers', []):
        namespace = str(binding.get('namespace', '')).lower()
        if namespace:
            PROVIDER_INDEX.setdefault(namespace, []).append(service)


def _unique_text(values: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for value in values:
        normalized = re.sub(r'\s+', ' ', str(value or '')).strip()
        if not normalized:
            continue
        key = normalized.lower()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(normalized)
    return ordered


def _slugify_identity(value: str) -> str:
    slug = re.sub(r'[^a-z0-9]+', '-', str(value or '').lower()).strip('-')
    return slug[:120] or 'service'


def _retail_family_candidates(service_family: str) -> list[str]:
    family_map = {
        'app-services': ['Web'],
        'compute': ['Compute', 'Virtual Machines'],
        'containers': ['Containers'],
        'databases': ['Databases'],
        'machinelearningservices': ['AI + Machine Learning'],
        'messaging': ['Integration'],
        'monitoring': ['Management and Governance', 'Monitoring'],
        'networking': ['Networking'],
        'storage': ['Storage'],
    }
    return family_map.get(service_family, [])


def _canonical_family_key(*, service_family: str, pricing_families: list[str], namespace: str) -> str:
    normalized_service_family = str(service_family or '').strip().lower()
    if normalized_service_family:
        return normalized_service_family

    family_aliases = {
        'ai + machine learning': 'machinelearningservices',
        'compute': 'compute',
        'virtual machines': 'compute',
        'containers': 'containers',
        'databases': 'databases',
        'integration': 'messaging',
        'management and governance': 'monitoring',
        'monitoring': 'monitoring',
        'networking': 'networking',
        'storage': 'storage',
        'web': 'app-services',
    }
    for pricing_family in pricing_families:
        mapped = family_aliases.get(str(pricing_family or '').strip().lower())
        if mapped:
            return mapped

    namespace_aliases = {
        'cache': 'cache',
        'cognitiveservices': 'machinelearningservices',
        'containerregistry': 'containers',
        'containerservice': 'containers',
        'eventhub': 'messaging',
        'machinelearningservices': 'machinelearningservices',
        'servicebus': 'messaging',
        'web': 'app-services',
    }
    normalized_namespace = str(namespace or '').strip().lower().removeprefix('microsoft.')
    return namespace_aliases.get(normalized_namespace, normalized_namespace or 'service')


def _default_pricing_profile(service: dict[str, Any] | None, *, provider: str, service_name: str) -> dict[str, Any]:
    display_name = str((service or {}).get('display_name') or service_name or '').strip()
    family = str((service or {}).get('family') or '').strip().lower()
    service_names = _unique_text(
        [
            display_name,
            re.sub(r'^Azure\s+', '', display_name, flags=re.IGNORECASE),
            service_name,
            re.sub(r'^Azure\s+', '', service_name or '', flags=re.IGNORECASE),
        ]
    )
    return {
        'query_mode': 'first-match',
        'filters': [],
        'serviceNames': service_names,
        'serviceFamilies': _retail_family_candidates(family),
        'productNames': [],
    }


def resolve_service_identity(provider: str, *, resource_types: set[str] | None = None, service_name: str = '') -> dict[str, Any]:
    provider_key = str(provider or '').strip().lower()
    namespace = provider_key.split('/')[0]
    resolved_types = {str(item).lower() for item in (resource_types or set()) if str(item).strip()}
    if '/' in provider_key:
        resolved_types.add(provider_key.split('/', 1)[1])

    service = match_service(namespace, resolved_types) if namespace else None
    display_name = str((service or {}).get('display_name') or service_name or provider or '').strip()
    family = str((service or {}).get('family') or '').strip() or namespace.removeprefix('microsoft.')
    pricing_profile = {
        **_default_pricing_profile(service, provider=provider_key, service_name=service_name or display_name),
        **((service or {}).get('pricing') or {}),
    }
    pricing_profile['filters'] = list((service or {}).get('pricing', {}).get('filters') or pricing_profile.get('filters') or [])
    service_names = _unique_text(list(pricing_profile.get('serviceNames') or []))
    service_families = _unique_text(list(pricing_profile.get('serviceFamilies') or []))
    search_keywords = _unique_text(list((service or {}).get('discovery_terms') or []))
    canonical_service_name = service_names[0] if service_names else display_name or provider
    canonical_family_key = _canonical_family_key(service_family=family, pricing_families=service_families, namespace=namespace)
    canonical_family = canonical_family_key
    canonical_service_id = _slugify_identity(canonical_service_name)
    identity_source = 'curated-catalog-pricing-profile' if service is not None else 'derived-pricing-fallback'
    match_strategy = 'curated-provider-binding' if service is not None else 'provider-service-name-fallback'
    identity_confidence = 'high' if service is not None else 'medium' if canonical_service_name else 'low'
    diagnostics: list[dict[str, str]] = []
    if service is None:
        diagnostics.append(
            {
                'code': 'missing-curated-binding',
                'message': f'No curated catalog binding matched provider namespace {namespace or provider_key}.',
            }
        )
        if resolved_types:
            diagnostics.append(
                {
                    'code': 'resource-types-observed',
                    'message': f'Observed resource types: {", ".join(sorted(resolved_types))}.',
                }
            )
        if canonical_service_name:
            diagnostics.append(
                {
                    'code': 'pricing-name-fallback',
                    'message': f'Canonical identity is currently derived from pricing/service naming fallback: {canonical_service_name}.',
                }
            )

    return {
        'matched': service is not None,
        'isFallbackIdentity': service is None,
        'serviceKey': str((service or {}).get('service_key') or re.sub(r'[^a-z0-9]+', '-', display_name.lower()).strip('-') or namespace or 'service'),
        'canonicalServiceId': canonical_service_id,
        'canonicalServiceName': canonical_service_name,
        'canonicalFamily': canonical_family,
        'canonicalFamilyKey': canonical_family_key,
        'displayName': display_name,
        'family': family,
        'provider': provider,
        'providerNamespace': namespace,
        'resourceTypes': sorted(resolved_types),
        'identitySource': identity_source,
        'identityConfidence': identity_confidence,
        'matchStrategy': match_strategy,
        'matchedServiceKey': str((service or {}).get('service_key') or ''),
        'diagnostics': diagnostics,
        'provenance': {
            'identitySource': identity_source,
            'identityConfidence': identity_confidence,
            'matchStrategy': match_strategy,
            'serviceNames': service_names,
            'serviceFamilies': service_families,
            'productNames': _unique_text(list(pricing_profile.get('productNames') or [])),
            'searchKeywords': search_keywords,
            'matchedServiceKey': str((service or {}).get('service_key') or ''),
            'diagnosticCount': len(diagnostics),
        },
        'pricing': pricing_profile,
    }


def get_regional_override(service: dict[str, Any], region: str) -> dict[str, Any]:
    return service.get('regional_overrides', {}).get(region, {})


def score_binding(binding: dict[str, Any], resource_types: set[str], has_skus: bool = False) -> int:
    score = 0
    binding_types = {str(item).lower() for item in binding.get('resource_types', [])}
    hints = binding.get('match_hints', {})

    score += len(binding_types.intersection(resource_types)) * 20

    for token in hints.get('resource_type_contains', []):
        token_lower = str(token).lower()
        if any(token_lower in resource_type for resource_type in resource_types):
            score += 8

    if has_skus and hints.get('prefer_when_skus'):
        score += 4
    if (not has_skus) and hints.get('prefer_when_no_skus'):
        score += 12
    if hints.get('shared_provider_fallback'):
        score += 2
    return score


def _binding_matches_resource_type(binding: dict[str, Any], resource_type: str) -> bool:
    resource_type_lower = str(resource_type or '').lower()
    binding_types = {str(item).lower() for item in binding.get('resource_types', [])}
    if resource_type_lower in binding_types:
        return True

    hints = binding.get('match_hints', {})
    for token in hints.get('resource_type_contains', []):
        if str(token).lower() in resource_type_lower:
            return True

    return False


def service_bound_resource_types(service: dict[str, Any], namespace: str, resource_types: set[str]) -> set[str]:
    namespace_lower = str(namespace or '').lower()
    resolved_types = {str(item).lower() for item in (resource_types or set()) if str(item).strip()}
    matched: set[str] = set()

    for binding in service.get('providers', []):
        if str(binding.get('namespace', '')).lower() != namespace_lower:
            continue
        matched.update(
            resource_type
            for resource_type in resolved_types
            if _binding_matches_resource_type(binding, resource_type)
        )

    return matched


def mapped_resource_types_for_service(service: dict[str, Any]) -> set[str]:
    mapped: set[str] = set()
    for capability in service.get('capabilities', []):
        mapped.update(
            str(resource_type).lower()
            for resource_type in capability.get('resource_types', []) or []
            if str(resource_type).strip()
        )
    return mapped


def match_services_for_namespace(namespace: str, resource_types: set[str]) -> list[dict[str, Any]]:
    namespace_lower = str(namespace or '').lower()
    resolved_types = {str(item).lower() for item in (resource_types or set()) if str(item).strip()}
    candidates = PROVIDER_INDEX.get(namespace_lower, [])
    if not candidates:
        return []

    scored: list[tuple[int, dict[str, Any], set[str]]] = []
    for service in candidates:
        best_score = 0
        for binding in service.get('providers', []):
            if str(binding.get('namespace', '')).lower() != namespace_lower:
                continue
            best_score = max(best_score, score_binding(binding, resolved_types, False))
        if best_score <= 0:
            continue
        matched_types = service_bound_resource_types(service, namespace_lower, resolved_types)
        scored.append((best_score, service, matched_types))

    if not scored:
        service = match_service(namespace_lower, resolved_types)
        if not service:
            return []
        return [
            {
                'service': service,
                'resourceTypes': sorted(service_bound_resource_types(service, namespace_lower, resolved_types) or resolved_types),
            }
        ]

    scored.sort(key=lambda item: (-item[0], item[1].get('service_key', '')))

    selected: list[dict[str, Any]] = []
    covered_types: set[str] = set()
    for _, service, matched_types in scored:
        effective_types = matched_types or set(resolved_types)
        if effective_types and effective_types.issubset(covered_types):
            continue
        selected.append(
            {
                'service': service,
                'resourceTypes': sorted(effective_types),
            }
        )
        covered_types.update(effective_types)

    return selected


def match_service(namespace: str, resource_types: set[str]) -> dict[str, Any] | None:
    candidates = PROVIDER_INDEX.get(namespace, [])
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]

    scored: list[tuple[int, dict[str, Any]]] = []
    for service in candidates:
        best_score = 0
        for binding in service.get('providers', []):
            if str(binding.get('namespace', '')).lower() != namespace:
                continue
            best_score = max(best_score, score_binding(binding, resource_types, False))
        scored.append((best_score, service))

    scored.sort(key=lambda item: (-item[0], item[1].get('service_key', '')))
    return scored[0][1] if scored else None


def build_curated_regional_details_for_service(
    service: dict[str, Any],
    source_region: str,
    target_region: str,
    source_types: set[str],
    target_types: set[str],
    *,
    source_region_has_zones: str = 'unknown',
    target_region_has_zones: str = 'unknown',
) -> dict[str, Any] | None:
    if not service:
        return None

    source_present = bool(source_types)
    target_present = bool(target_types)
    capabilities: list[dict[str, Any]] = []
    different_count = 0
    for capability in service.get('capabilities', []):
        source_details = resolve_capability_details(service, capability, source_region, source_present, source_region_has_zones)
        target_details = resolve_capability_details(service, capability, target_region, target_present, target_region_has_zones)
        if source_details['status'] != target_details['status']:
            different_count += 1
        capabilities.append(
            {
                'key': capability.get('key'),
                'label': capability.get('label'),
                'importance': capability.get('importance'),
                'sourceStatus': source_details['status'],
                'targetStatus': target_details['status'],
                'sourceNotes': source_details['notes'],
                'targetNotes': target_details['notes'],
            }
        )

    source_override = get_regional_override(service, source_region)
    target_override = get_regional_override(service, target_region)
    source_zone = resolve_zone_mode(service, source_region, source_region_has_zones, source_present)
    target_zone = resolve_zone_mode(service, target_region, target_region_has_zones, target_present)
    return {
        'matched': True,
        'serviceKey': service.get('service_key'),
        'displayName': service.get('display_name'),
        'family': service.get('family'),
        'summary': service.get('summary'),
        'mappedResourceTypes': sorted(mapped_resource_types_for_service(service)),
        'sourceRegion': {
            'name': source_region,
            'serviceAvailable': source_present,
            'regionHasAvailabilityZones': source_region_has_zones,
            'regionNote': source_override.get('notes', ''),
            'zoneSupport': source_zone,
        },
        'targetRegion': {
            'name': target_region,
            'serviceAvailable': target_present,
            'regionHasAvailabilityZones': target_region_has_zones,
            'regionNote': target_override.get('notes', ''),
            'zoneSupport': target_zone,
        },
        'capabilities': capabilities,
        'summaryStats': {
            'capabilityCount': len(capabilities),
            'differentCapabilityCount': different_count,
            'matchedCapabilityCount': len(capabilities) - different_count,
        },
    }


def resolve_zone_mode(service: dict[str, Any], region: str, region_has_zones: str, is_service_available: bool) -> dict[str, str]:
    zone_support = service.get('zone_support', {})
    override = get_regional_override(service, region)
    zone_override = override.get('zone_support', {})
    mode = zone_override.get('mode', zone_support.get('regions', {}).get(region, zone_support.get('default', 'unknown')))
    notes = zone_override.get('notes', zone_support.get('notes'))
    explicit_region_mode = 'mode' in zone_override or region in zone_support.get('regions', {})
    if not is_service_available:
        return {
            'mode': 'service-unavailable',
            'label': 'Service unavailable in region',
            'notes': notes or '',
        }

    if region_has_zones == 'false':
        return {
            'mode': 'region-without-zones',
            'label': 'Region does not expose availability zones',
            'notes': notes or '',
        }

    if region_has_zones == 'unknown' and not explicit_region_mode and mode in {'both', 'zonal', 'zone-redundant'}:
        return {
            'mode': 'zone-support-unverified',
            'label': 'Availability zone posture not verified',
            'notes': notes or '',
        }

    return {
        'mode': mode,
        'label': ZONE_MODE_LABELS.get(mode, mode),
        'notes': notes or '',
    }


def resolve_capability_details(service: dict[str, Any], capability: dict[str, Any], region: str, is_service_available: bool, region_has_zones: str = 'unknown') -> dict[str, str]:
    if not is_service_available:
        return {'status': 'unavailable', 'notes': capability.get('notes', '')}

    availability = capability.get('availability', {})
    override = get_regional_override(service, region).get('capabilities', {}).get(capability.get('key'), {})
    status = override.get('status', availability.get('regions', {}).get(region, availability.get('default', 'available')))
    notes = override.get('notes', capability.get('notes', ''))

    if capability.get('requires_zone_support') and status == 'available' and region_has_zones == 'false':
        return {'status': 'not-applicable', 'notes': 'Region does not expose availability zones'}

    return {'status': status, 'notes': notes}


def build_curated_regional_details(
    namespace: str,
    source_region: str,
    target_region: str,
    source_types: set[str],
    target_types: set[str],
    *,
    source_region_has_zones: str = 'unknown',
    target_region_has_zones: str = 'unknown',
) -> dict[str, Any] | None:
    service = match_service(namespace, source_types | target_types)
    return build_curated_regional_details_for_service(
        service,
        source_region,
        target_region,
        source_types,
        target_types,
        source_region_has_zones=source_region_has_zones,
        target_region_has_zones=target_region_has_zones,
    )