import type { BuilderEnvironment, Template, UserProfile } from '../../shared/types';

const BASE = '/api';

async function apiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
    },
  });
  if (res.status === 401) {
    window.location.href = '/auth/login';
    throw new Error('Not authenticated');
  }
  if (!res.ok) {
    const data = await res.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(data.error || `HTTP ${res.status}`);
  }
  return res.json();
}

export const api = {
  getMe: () => apiFetch<UserProfile>('/me'),
  getEnvironments: () => apiFetch<BuilderEnvironment[]>('/environments'),
  getTemplates: () => apiFetch<Template[]>('/templates'),
  createEnvironment: (templateId: string) =>
    apiFetch<{ envId: string; projectId: string; envName: string }>('/environments', {
      method: 'POST',
      body: JSON.stringify({ templateId }),
    }),
  startEnvironment: (id: string) =>
    apiFetch<void>(`/environments/${id}/start`, { method: 'POST' }),
  stopEnvironment: (id: string) =>
    apiFetch<void>(`/environments/${id}/stop`, { method: 'POST' }),
  deleteEnvironment: (id: string) =>
    apiFetch<void>(`/environments/${id}`, { method: 'DELETE' }),
};
