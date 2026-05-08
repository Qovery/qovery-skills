import * as qovery from './qovery';
import { loadConfig } from '../config';
import type { PortalConfig } from '../../shared/types';

// Derive a username from the SSO email (e.g., alice@company.com → alice)
export function usernameFromEmail(email: string): string {
  return email.split('@')[0].toLowerCase().replace(/[^a-z0-9-]/g, '-');
}

// Build the environment name from user + template
export function buildEnvName(username: string, templateName: string, index: number): string {
  const sanitized = templateName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return `${username}-${sanitized}-${index}`;
}

// Count existing environments for a user
export async function countUserEnvironments(
  config: PortalConfig,
  username: string
): Promise<number> {
  const envs = await getUserEnvironments(config, username);
  return envs.length;
}

// List environments belonging to a user (by naming convention)
export async function getUserEnvironments(
  config: PortalConfig,
  username: string
): Promise<any[]> {
  if (config.isolation === 'project-per-builder') {
    // In project-per-builder mode, list projects matching builder-{username}
    const projects = await qovery.listProjects(config.organizationId);
    const builderProject = projects.find(
      (p: any) => p.name === `builder-${username}`
    );
    if (!builderProject) return [];
    const envs = await qovery.listEnvironments(builderProject.id);
    return envs.map((e: any) => ({ ...e, projectId: builderProject.id }));
  } else {
    // In shared project mode, list environments matching {username}-*
    if (!config.sharedProjectId) return [];
    const envs = await qovery.listEnvironments(config.sharedProjectId);
    return envs
      .filter((e: any) => e.name.startsWith(`${username}-`))
      .map((e: any) => ({ ...e, projectId: config.sharedProjectId }));
  }
}

// Provision a new builder environment
export async function provisionEnvironment(
  config: PortalConfig,
  userEmail: string,
  templateId: string
): Promise<{ envId: string; projectId: string; envName: string }> {
  const username = usernameFromEmail(userEmail);
  const template = config.templates.find(t => t.id === templateId);
  if (!template) throw new Error(`Template not found: ${templateId}`);

  // Check environment limit
  const currentCount = await countUserEnvironments(config, username);
  if (currentCount >= config.maxEnvironmentsPerBuilder) {
    throw new Error(
      `You have reached the maximum of ${config.maxEnvironmentsPerBuilder} environments. ` +
      'Stop or delete an existing environment to create a new one.'
    );
  }

  const envName = buildEnvName(username, template.name, currentCount + 1);
  let projectId: string;

  // Step 1: Create or find the project
  if (config.isolation === 'project-per-builder') {
    const projects = await qovery.listProjects(config.organizationId);
    const existing = projects.find((p: any) => p.name === `builder-${username}`);
    if (existing) {
      projectId = existing.id;
    } else {
      const project = await qovery.createProject(
        config.organizationId,
        `builder-${username}`,
        `Builder workspace for ${username}`
      );
      projectId = project.id;

      // Create per-builder RBAC role
      const roleId = await qovery.createCustomRole(
        config.organizationId,
        `Builder-${username}`,
        `Builder role for ${username} — access to builder-${username} project only`
      );
      await qovery.configureCustomRole(config.organizationId, roleId, {
        name: `Builder-${username}`,
        clusterId: config.clusterId,
        projectId,
      });

      // Invite the builder with their role
      await qovery.inviteMember(config.organizationId, userEmail, roleId);
    }
  } else {
    projectId = config.sharedProjectId!;
    if (config.builderRoleId) {
      await qovery.inviteMember(config.organizationId, userEmail, config.builderRoleId);
    }
  }

  // Step 2: Clone the blueprint
  const cloned = await qovery.cloneEnvironment(
    template.blueprintEnvId,
    envName,
    config.clusterId,
    'DEVELOPMENT',
    config.isolation === 'project-per-builder' ? projectId : undefined
  );
  const envId = cloned.id;

  // Step 3: Create TTL lifecycle job
  if (config.ttl.stopAfter && config.ttl.stopAfter !== 'none') {
    const shutdownToken = await qovery.createApiToken(
      config.organizationId,
      `portal-ttl-${envName}`
    );

    const ttlJob = await qovery.createCronJob(envId, {
      name: 'ttl-auto-shutdown',
      description: `Automatically stops this environment (TTL: ${config.ttl.stopAfter})`,
      cronSchedule: config.ttl.cronSchedule,
      command: `curl -sf -H "User-Agent: QoverySkill/qovery-builder-portal-ttl" -X POST https://api.qovery.com/environment/${envId}/stop -H "Authorization: Token $SHUTDOWN_TOKEN" && echo "Stopped by TTL" || echo "Already stopped"`,
    });

    await qovery.setJobSecret(ttlJob.id, 'SHUTDOWN_TOKEN', shutdownToken);
  }

  // Step 4: Deploy the environment
  await qovery.deployEnvironment(envId);

  return { envId, projectId, envName };
}
