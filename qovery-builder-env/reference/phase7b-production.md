## PHASE 7B: Production Graduation (Optional)

When a builder's application is ready to serve real users (internal or external), it needs to go through a controlled promotion process. This phase is optional — only include it if the platform engineer indicated in Phase 1.3 that some builder apps may go to production.

### 7B.1 Review Process

When a builder requests production deployment:

1. **Platform team reviews the application:**
   - Code quality (AI-generated code should be reviewed)
   - Security (no hardcoded secrets, proper authentication, input validation)
   - Dependencies (no vulnerable packages, no unnecessary dependencies)
   - Data handling (PII protection, GDPR compliance if applicable)

2. **Create a staging environment:**
   ```bash
   curl -s -X POST "https://api.qovery.com/environment/{builderEnvId}/clone" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "staging-{app-name}",
       "cluster_id": "{prodClusterId}",
       "mode": "STAGING"
     }'
   ```

3. **Deploy to staging and validate:**
   - Run health checks
   - Test with production-like data (anonymized if PII)
   - Load test if the app will serve many users
   - Security scan

### 7B.2 Promote to Production

If the staging review passes:

1. **Clone the staging environment to production:**
   ```bash
   curl -s -X POST "https://api.qovery.com/environment/{stagingEnvId}/clone" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "prod-{app-name}",
       "cluster_id": "{prodClusterId}",
       "mode": "PRODUCTION"
     }'
   ```

2. **Upgrade resources for production:**
   - Switch database from container mode to managed (e.g., RDS):
     Delete the container database and create a managed one
   - Increase CPU/memory for the application
   - Configure autoscaling if needed
   - Set up a custom domain
   - Enable monitoring and alerts

3. **Set up CI/CD:**
   - Configure auto-deploy from the application's git branch
   - Set up the review/approval process for future changes

IMPORTANT: The builder should NOT have direct access to the production environment. Only the platform team (Admin/DevOps role) can manage production resources.

---

