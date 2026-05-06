import type { BuilderEnvironment, ServiceUrl } from '../../shared/types';

const BASE_URL = 'https://api.qovery.com';
const API_TOKEN = process.env.QOVERY_API_TOKEN!;

async function qoveryFetch(path: string, options: RequestInit = {}): Promise<any> {
  const res = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: {
      'Authorization': `Token ${API_TOKEN}`,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Qovery API error ${res.status}: ${text}`);
  }
  if (res.status === 204) return null;
  return res.json();
}

// List all environments in a project
export async function listEnvironments(projectId: string): Promise<any[]> {
  const data = await qoveryFetch(`/project/${projectId}/environment`);
  return data.results || [];
}

// List all projects in the organization
export async function listProjects(orgId: string): Promise<any[]> {
  const data = await qoveryFetch(`/organization/${orgId}/project`);
  return data.results || [];
}

// Get environment statuses (all services)
export async function getEnvironmentStatuses(envId: string): Promise<any> {
  return qoveryFetch(`/environment/${envId}/statuses`);
}

// Get public URLs for an application
export async function getApplicationLinks(appId: string): Promise<ServiceUrl[]> {
  try {
    const data = await qoveryFetch(`/application/${appId}/link`);
    return (data.results || []).map((link: any) => ({
      name: link.internal_domain_name || 'Service',
      url: link.url,
      isWorkspace: false, // Caller should set this based on service name
    }));
  } catch {
    return [];
  }
}

// List applications in an environment
export async function listApplications(envId: string): Promise<any[]> {
  const data = await qoveryFetch(`/environment/${envId}/application`);
  return data.results || [];
}

// Clone an environment
export async function cloneEnvironment(
  sourceEnvId: string,
  name: string,
  clusterId: string,
  mode: string,
  projectId?: string
): Promise<any> {
  const body: Record<string, string> = { name, cluster_id: clusterId, mode };
  if (projectId) body.project_id = projectId;
  return qoveryFetch(`/environment/${sourceEnvId}/clone`, {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

// Create a project
export async function createProject(orgId: string, name: string, description: string): Promise<any> {
  return qoveryFetch(`/organization/${orgId}/project`, {
    method: 'POST',
    body: JSON.stringify({ name, description }),
  });
}

// Deploy an environment
export async function deployEnvironment(envId: string): Promise<void> {
  await qoveryFetch(`/environment/${envId}/deploy`, { method: 'POST' });
}

// Stop an environment
export async function stopEnvironment(envId: string): Promise<void> {
  await qoveryFetch(`/environment/${envId}/stop`, { method: 'POST' });
}

// Delete an environment
export async function deleteEnvironment(envId: string): Promise<void> {
  await qoveryFetch(`/environment/${envId}`, { method: 'DELETE' });
}

// Create a cron job (TTL lifecycle job)
export async function createCronJob(envId: string, job: {
  name: string;
  description: string;
  cronSchedule: string;
  command: string;
}): Promise<any> {
  return qoveryFetch(`/environment/${envId}/job`, {
    method: 'POST',
    body: JSON.stringify({
      name: job.name,
      description: job.description,
      cpu: 250,
      memory: 256,
      max_nb_restart: 0,
      max_duration_seconds: 60,
      auto_preview: false,
      auto_deploy: false,
      healthchecks: {},
      source: {
        docker: {
          dockerfile_raw: 'FROM curlimages/curl:8.11.1\nENTRYPOINT ["sh", "-c"]',
        },
      },
      schedule: {
        cronjob: {
          entrypoint: 'sh',
          arguments: ['-c', job.command],
          scheduled_at: job.cronSchedule,
          timezone: 'Etc/UTC',
        },
      },
    }),
  });
}

// Set a secret on a job
export async function setJobSecret(jobId: string, key: string, value: string): Promise<void> {
  await qoveryFetch(`/application/${jobId}/secret`, {
    method: 'POST',
    body: JSON.stringify({ key, value }),
  });
}

// Create an API token (for TTL shutdown jobs)
export async function createApiToken(orgId: string, name: string): Promise<string> {
  const data = await qoveryFetch(`/organization/${orgId}/apiToken`, {
    method: 'POST',
    body: JSON.stringify({ name, description: `Auto-shutdown token for ${name}` }),
  });
  return data.token;
}

// Create a custom role
export async function createCustomRole(orgId: string, name: string, description: string): Promise<string> {
  const data = await qoveryFetch(`/organization/${orgId}/customRole`, {
    method: 'POST',
    body: JSON.stringify({ name, description }),
  });
  return data.id;
}

// Configure a custom role with project permissions
export async function configureCustomRole(orgId: string, roleId: string, config: {
  name: string;
  clusterId: string;
  projectId: string;
}): Promise<void> {
  await qoveryFetch(`/organization/${orgId}/customRole/${roleId}`, {
    method: 'PUT',
    body: JSON.stringify({
      name: config.name,
      cluster_permissions: [
        { cluster_id: config.clusterId, permission: 'ENV_CREATOR' },
      ],
      project_permissions: [
        {
          project_id: config.projectId,
          is_admin: false,
          permissions: [
            { environment_type: 'DEVELOPMENT', permission: 'DEPLOYER' },
            { environment_type: 'STAGING', permission: 'VIEWER' },
            { environment_type: 'PRODUCTION', permission: 'NO_ACCESS' },
            { environment_type: 'PREVIEW', permission: 'DEPLOYER' },
          ],
        },
      ],
    }),
  });
}

// Invite a member
export async function inviteMember(orgId: string, email: string, roleId: string): Promise<void> {
  try {
    await qoveryFetch(`/organization/${orgId}/inviteMember`, {
      method: 'POST',
      body: JSON.stringify({ email, role_id: roleId }),
    });
  } catch (e: any) {
    // 409 = already invited, that's fine
    if (!e.message.includes('409')) throw e;
  }
}
