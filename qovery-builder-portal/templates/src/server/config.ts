import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import type { PortalConfig, Template } from '../shared/types';

let cachedConfig: PortalConfig | null = null;

export function loadConfig(): PortalConfig {
  if (cachedConfig) return cachedConfig;

  const configPath = process.env.BUILDER_PLATFORM_CONFIG_PATH
    || path.resolve(process.cwd(), 'builder-platform-config.yaml');

  if (!fs.existsSync(configPath)) {
    throw new Error(
      `builder-platform-config.yaml not found at ${configPath}. ` +
      'Set BUILDER_PLATFORM_CONFIG_PATH or run the qovery-builder-env skill first.'
    );
  }

  const raw = yaml.load(fs.readFileSync(configPath, 'utf8')) as Record<string, any>;

  cachedConfig = {
    organizationId: raw.organization_id,
    clusterId: raw.cluster_id,
    isolation: raw.isolation || 'project-per-builder',
    sharedProjectId: raw.shared_project_id,
    builderRoleId: raw.builder_role_id,
    templates: (raw.templates || []).map((t: any) => ({
      id: t.blueprint_env_id,
      name: t.name,
      description: t.description,
      icon: t.icon || 'code',
      blueprintEnvId: t.blueprint_env_id,
    })) as Template[],
    maxEnvironmentsPerBuilder: parseInt(process.env.MAX_ENVIRONMENTS_PER_BUILDER || raw.max_environments_per_builder || '3', 10),
    ttl: {
      stopAfter: raw.ttl?.stop_after || '24h',
      deleteAfter: raw.ttl?.delete_after || 'none',
      cronSchedule: raw.ttl?.cron_schedule || '0 20 * * 1-5',
    },
    canExtendTtl: raw.can_extend_ttl !== false,
    maxTtlExtension: raw.max_ttl_extension || '48h',
    canDeleteEnvironment: raw.can_delete_environment !== false,
  };

  return cachedConfig;
}
