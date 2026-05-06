// Shared types used by both frontend and backend

export interface Template {
  id: string;
  name: string;
  description: string;
  icon: string;
  blueprintEnvId: string;
}

export interface ServiceUrl {
  name: string;
  url: string;
  isWorkspace: boolean;
}

export interface BuilderEnvironment {
  id: string;
  name: string;
  projectId: string;
  status: 'DEPLOYING' | 'DEPLOYED' | 'STOPPING' | 'STOPPED' | 'DELETING' | 'ERROR' | 'BUILDING' | 'DEPLOYMENT_ERROR' | 'BUILD_ERROR' | 'QUEUED';
  templateName: string;
  serviceUrls: ServiceUrl[];
  createdAt: string;
  ttlExpiresAt?: string;
}

export interface UserProfile {
  email: string;
  name: string;
  avatarUrl?: string;
}

export interface PortalConfig {
  organizationId: string;
  clusterId: string;
  isolation: 'shared-project' | 'project-per-builder';
  sharedProjectId?: string;
  builderRoleId?: string;
  templates: Template[];
  maxEnvironmentsPerBuilder: number;
  ttl: {
    stopAfter: string;
    deleteAfter: string;
    cronSchedule: string;
  };
  canExtendTtl: boolean;
  maxTtlExtension?: string;
  canDeleteEnvironment: boolean;
}
