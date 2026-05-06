import { Router, Request, Response } from 'express';
import * as qovery from '../services/qovery';
import * as provisioner from '../services/provisioner';
import { loadConfig } from '../config';
import type { BuilderEnvironment, ServiceUrl } from '../../shared/types';

const router = Router();

// GET /api/environments — list my environments
router.get('/', async (req: Request, res: Response) => {
  try {
    const user = req.user as any;
    const config = loadConfig();
    const username = provisioner.usernameFromEmail(user.email);
    const rawEnvs = await provisioner.getUserEnvironments(config, username);

    const environments: BuilderEnvironment[] = await Promise.all(
      rawEnvs.map(async (env: any) => {
        // Get statuses
        let status = 'STOPPED';
        try {
          const statuses = await qovery.getEnvironmentStatuses(env.id);
          status = statuses.environment?.state || 'STOPPED';
        } catch { /* environment might be deploying */ }

        // Get service URLs
        let serviceUrls: ServiceUrl[] = [];
        try {
          const apps = await qovery.listApplications(env.id);
          for (const app of apps) {
            const links = await qovery.getApplicationLinks(app.id);
            serviceUrls.push(...links.map(link => ({
              ...link,
              name: app.name,
              isWorkspace: app.name.toLowerCase().includes('workspace') || app.name.toLowerCase().includes('ide'),
            })));
          }
        } catch { /* environment might not be deployed yet */ }

        // Derive template name from environment name
        const parts = env.name.split('-');
        const templateName = parts.length >= 3
          ? parts.slice(1, -1).join(' ')
          : env.name;

        return {
          id: env.id,
          name: env.name,
          projectId: env.projectId,
          status,
          templateName,
          serviceUrls,
          createdAt: env.created_at,
        } as BuilderEnvironment;
      })
    );

    res.json(environments);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/environments — create a new environment
router.post('/', async (req: Request, res: Response) => {
  try {
    const user = req.user as any;
    const config = loadConfig();
    const { templateId } = req.body;

    if (!templateId) {
      return res.status(400).json({ error: 'templateId is required' });
    }

    const result = await provisioner.provisionEnvironment(config, user.email, templateId);
    res.status(201).json(result);
  } catch (err: any) {
    const status = err.message.includes('maximum') ? 409 : 500;
    res.status(status).json({ error: err.message });
  }
});

// POST /api/environments/:id/start — restart a stopped environment
router.post('/:id/start', async (req: Request, res: Response) => {
  try {
    await qovery.deployEnvironment(req.params.id);
    res.json({ message: 'Deployment triggered' });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/environments/:id/stop — stop an environment
router.post('/:id/stop', async (req: Request, res: Response) => {
  try {
    await qovery.stopEnvironment(req.params.id);
    res.json({ message: 'Stop triggered' });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/environments/:id — delete an environment
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const config = loadConfig();
    if (!config.canDeleteEnvironment) {
      return res.status(403).json({ error: 'Deleting environments is disabled. Contact the platform team.' });
    }
    await qovery.deleteEnvironment(req.params.id);
    res.json({ message: 'Delete triggered' });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default router;
