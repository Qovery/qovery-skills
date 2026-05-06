import type { BuilderEnvironment } from '../../shared/types';
import { StatusBadge } from './StatusBadge';
import { ServiceLinks } from './ServiceLinks';
import { api } from '../lib/api';
import { useState } from 'react';

interface Props {
  env: BuilderEnvironment;
  canDelete: boolean;
  onRefresh: () => void;
}

export function EnvironmentCard({ env, canDelete, onRefresh }: Props) {
  const [loading, setLoading] = useState<string | null>(null);

  const handleAction = async (action: 'start' | 'stop' | 'delete') => {
    setLoading(action);
    try {
      if (action === 'start') await api.startEnvironment(env.id);
      if (action === 'stop') await api.stopEnvironment(env.id);
      if (action === 'delete') {
        if (!confirm('Are you sure you want to delete this workspace? This cannot be undone.')) {
          setLoading(null);
          return;
        }
        await api.deleteEnvironment(env.id);
      }
      // Wait a moment for the status to change, then refresh
      setTimeout(onRefresh, 2000);
    } catch (err: any) {
      alert(err.message);
    } finally {
      setLoading(null);
    }
  };

  const isRunning = env.status === 'DEPLOYED';
  const isStopped = env.status === 'STOPPED';
  const isTransitioning = ['DEPLOYING', 'STOPPING', 'DELETING', 'BUILDING', 'QUEUED'].includes(env.status);

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm hover:shadow-md transition-shadow">
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="font-semibold text-lg text-gray-900">{env.name}</h3>
          <p className="text-sm text-gray-500 mt-1">{env.templateName}</p>
        </div>
        <StatusBadge status={env.status} />
      </div>

      {isRunning && env.serviceUrls.length > 0 && (
        <ServiceLinks urls={env.serviceUrls} />
      )}

      {isTransitioning && (
        <div className="flex items-center gap-2 text-sm text-gray-500 mt-4">
          <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <span>{env.status.toLowerCase().replace('_', ' ')}...</span>
        </div>
      )}

      <div className="flex gap-2 mt-4 pt-4 border-t border-gray-100">
        {isStopped && (
          <button
            onClick={() => handleAction('start')}
            disabled={!!loading}
            className="px-3 py-1.5 text-sm font-medium rounded-lg bg-green-50 text-green-700 hover:bg-green-100 disabled:opacity-50"
          >
            {loading === 'start' ? 'Starting...' : 'Start'}
          </button>
        )}
        {isRunning && (
          <button
            onClick={() => handleAction('stop')}
            disabled={!!loading}
            className="px-3 py-1.5 text-sm font-medium rounded-lg bg-yellow-50 text-yellow-700 hover:bg-yellow-100 disabled:opacity-50"
          >
            {loading === 'stop' ? 'Stopping...' : 'Stop'}
          </button>
        )}
        {canDelete && !isTransitioning && (
          <button
            onClick={() => handleAction('delete')}
            disabled={!!loading}
            className="px-3 py-1.5 text-sm font-medium rounded-lg bg-red-50 text-red-700 hover:bg-red-100 disabled:opacity-50 ml-auto"
          >
            {loading === 'delete' ? 'Deleting...' : 'Delete'}
          </button>
        )}
      </div>
    </div>
  );
}
