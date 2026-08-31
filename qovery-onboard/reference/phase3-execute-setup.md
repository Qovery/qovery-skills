## PHASE 3: Execute the Setup

After user confirmation, execute step by step. Show progress with Qovery Console links at EVERY step.

### 3.1 Account & Organization

If the user doesn't have a Qovery account:

> "First, let's create your Qovery account. Go to https://console.qovery.com and sign up. It's free to start — no credit card required."

Wait for confirmation, then:

> "Great! You should now have an organization. Let me verify..."

```bash
# Verify organization
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq '.results[] | {id, name}'
```

### 3.2 Cloud Provider Credentials

Guide through credential setup with simple explanations adapted to the user's experience level.

**For AWS (STS Assume Role — recommended):**

For non-technical users:
> "I need to connect Qovery to your AWS account so it can create infrastructure for you. This is done through a secure role (like giving Qovery a specific key to your AWS house). It takes about 2 minutes."

For technical users:
> "We'll create an IAM role via CloudFormation that grants Qovery the permissions it needs to manage EKS, EC2, RDS, and related services."

Steps:
1. Open the CloudFormation quick-create link:
   ```
   https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https%3A%2F%2Fcloudformation-qovery-role-creation.s3.amazonaws.com%2Ftemplate.json&stackName=qovery-role-creation
   ```
2. Check "I acknowledge that AWS CloudFormation might create IAM resources"
3. Click "Create stack"
4. Wait ~1 minute for `CREATE_COMPLETE`
5. Copy the Role ARN from the Outputs tab

Save credentials:
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/aws/credentials" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type": "AWS_ROLE", "name": "aws-production", "role_arn": "arn:aws:iam::XXXXXXXXXXXX:role/qovery-role"}'
```

IMPORTANT: The `type` field (`AWS_ROLE` or `AWS_STATIC`) is required. Without it, the API parses the body as static credentials and fails with a misleading `access_key_id is required` error — that does not mean role/ARN credentials are unsupported.

> "Cloud credentials saved. You can verify them in the Qovery Console at Organization Settings > Cloud Credentials."

**For GCP:**
1. Open Google Cloud Shell
2. Run: `curl https://hub.qovery.com/files/create_credentials_gcp.sh | bash -s -- PROJECT_ID qovery_role qovery-service-account`
3. Download `key.json`
4. Upload to Qovery via API or Console

**For Azure:**
1. Get Tenant ID and Subscription ID from Azure Portal
2. Open Azure Cloud Shell (Bash mode)
3. Run the credential creation script from Qovery Console
4. Credentials auto-linked

**For Scaleway:**
1. Get Access Key, Secret Key, Organization ID, Project ID from Scaleway Console
2. Save in Qovery Console or API

### 3.3 Cluster Creation

> "Now I'll create your Kubernetes cluster. This is the infrastructure that will run your applications. It takes about 15-20 minutes — I'll show you the progress."

Recommend the Qovery Console for first-time cluster creation (visual, progress indicators):

> "I recommend creating the cluster through the Qovery Console for your first setup — it has a nice visual interface that shows progress. Go to https://console.qovery.com > Clusters > Create Cluster."

Guide through the Console options:
1. Select cloud provider (the one from Phase 2)
2. Choose "Qovery Managed"
3. Name: e.g., `production` or `main`
4. Region: the one from Phase 2
5. Credentials: the ones just created
6. Production cluster: ON for production workloads
7. Instance types: configure per recommendation
8. Click "Create and Deploy"

Or create via API if the user prefers:
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/cluster" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "region": "us-east-1",
    "cloud_provider": "AWS",
    "cloud_provider_credentials": {"credentials": {"id": "{credId}"}},
    "kubernetes": "MANAGED",
    "production": true,
    "disk_size": 50,
    "instance_type": "T3A_LARGE",
    "min_running_nodes": 3,
    "max_running_nodes": 10
  }'

# Deploy the cluster
curl -s -X POST "https://api.qovery.com/cluster/{clusterId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Show progress:
> "Cluster creation started. You can monitor it at: https://console.qovery.com/clusters/{id}"
> "This takes about 15-20 minutes. While we wait, let's set up your project and environments."

### 3.4 Project & Environments (While Cluster Creates)

Use the waiting time productively:

```bash
# Create project
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-project", "description": "Main project"}'
```

> "Project 'my-project' created. View it here: https://console.qovery.com/projects/{id}"

Wait for cluster to be ready, then create environments:

```bash
# Development environment
curl -s -X POST "https://api.qovery.com/project/{projId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "development", "mode": "DEVELOPMENT", "cluster": "{clusterId}"}'

# Staging environment
curl -s -X POST "https://api.qovery.com/project/{projId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "staging", "mode": "STAGING", "cluster": "{clusterId}"}'

# Production environment
curl -s -X POST "https://api.qovery.com/project/{projId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "production", "mode": "PRODUCTION", "cluster": "{clusterId}"}'
```

> "Environments created:
>   - development: https://console.qovery.com/environments/{devId}
>   - staging: https://console.qovery.com/environments/{stagingId}
>   - production: https://console.qovery.com/environments/{prodId}"

### 3.5 Deployment Rules (Cost Optimization)

Set up deployment rules to auto-stop non-production environments:

> "I'm setting up deployment rules to automatically stop your dev and staging environments outside business hours. This will save approximately 60-70% on non-production infrastructure costs."

Guide through Console: Project Settings > Deployment Rules, or explain the deployment rule configuration:

```
Rule 1 (highest priority): prod-* → Never stop
Rule 2: staging-* → Mon-Fri 8am-10pm, stop weekends
Rule 3: dev-* → Mon-Fri 8am-8pm, stop weekends
Rule 4 (catch-all): * → Stop after 2h idle
```

> "Deployment rules configured. Your dev and staging environments will automatically stop outside business hours and on weekends."

### 3.6 Git Provider Connection

> "To deploy applications from your Git repositories, Qovery needs read access to your code. Let's connect your Git provider."

Guide through: Console > Organization Settings > Git Repository Access

- **GitHub**: Install the Qovery GitHub App
- **GitLab**: Generate a personal access token with `api` and `read_repository` scopes
- **Bitbucket**: Set up an app password with repository read permissions

> "Git provider connected. Qovery can now access your repositories."

### 3.7 Team Member Invitations

If the user mentioned team members in Phase 1:

> "Let's invite your team members. I'll send them email invitations with the appropriate roles."

```bash
# Invite a team member
curl -s -X POST "https://api.qovery.com/organization/{orgId}/member/invite" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "developer@company.com", "role_id": null, "role": "DEVOPS"}'
```

Available default roles:

| Role | Best For | Can Deploy | Can Manage Infra | Can Manage Billing |
|---|---|---|---|---|
| **ADMIN** | Co-founders, tech leads | Yes | Yes | Yes |
| **DEVOPS** | Engineers, developers | Yes | Yes (clusters, registries) | No |
| **BILLING_MANAGER** | Finance team | No | No | Yes |
| **VIEWER** | Product managers, stakeholders | No (read-only) | No | No |

For enterprise teams that need more granularity:
> "For more fine-grained access control (e.g., developers can deploy to staging but not production), you can create custom roles in the Qovery Console: Organization Settings > Custom Roles. This lets you set permissions per cluster and per project/environment type."

> "Team invitations sent! They'll receive an email to join your Qovery organization."

### 3.8 Install the Full Qovery Skill Suite

At the end of onboarding:

> "Your Qovery setup is complete! Let me install the full suite of Qovery skills so your AI agent can help you with deploying, troubleshooting, cost optimization, and deployment speed going forward."

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash
```

---

