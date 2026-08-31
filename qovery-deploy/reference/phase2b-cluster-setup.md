## PHASE 2B: Cluster Setup (New Accounts / No Existing Cluster)

SKIP this phase entirely if the user already has a running cluster in Qovery. Only follow this phase if:
- The user has a brand new Qovery account with no clusters, OR
- The user explicitly asks to create a new cluster

Cluster creation takes 15-30 minutes. The user needs to complete this before any services can be deployed.

### 2B.1 Choose a Cloud Provider

Ask the user which cloud provider they want to use:

| Provider | Kubernetes Service | Best For |
|----------|-------------------|----------|
| **AWS** (Recommended) | EKS with Karpenter | Most popular, widest feature support, cost optimization via Karpenter + Spot |
| **GCP** | GKE Autopilot | Fully managed nodes, pay-per-pod billing, zero node management |
| **Azure** | AKS | Microsoft ecosystem, Azure AD integration |
| **Scaleway** | Kapsule | European cloud, simple pricing, GDPR-friendly |

### 2B.2 Create Cloud Provider Credentials

Each cloud provider requires credentials so Qovery can manage infrastructure in the user's cloud account. Guide the user through the appropriate process:

#### AWS Credentials (STS Assume Role — Recommended)

This is the most secure method. It uses temporary credentials that auto-rotate.

1. **Open the CloudFormation quick-create link** in AWS Console:
   ```
   https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https%3A%2F%2Fcloudformation-qovery-role-creation.s3.amazonaws.com%2Ftemplate.json&stackName=qovery-role-creation
   ```
   This creates an IAM role with the permissions Qovery needs (EC2, EKS, IAM, ELB, S3, RDS, ElastiCache, CloudWatch, etc.).

2. **In AWS CloudFormation Console**:
   - Click Next (template is pre-filled)
   - Keep default stack name `qovery-role-creation`
   - Click Next twice (skip options and tags)
   - Check "I acknowledge that AWS CloudFormation might create IAM resources"
   - Click "Create stack"

3. **Wait ~1 minute** for status to change to `CREATE_COMPLETE`

4. **Copy the Role ARN** from the Outputs tab (looks like `arn:aws:iam::123456789012:role/qovery-role`)

5. **Save credentials in Qovery** via Console (Organization Settings > Cloud Credentials > Add) or via API:
   ```bash
   curl -s -X POST "https://api.qovery.com/organization/{orgId}/aws/credentials" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "AWS_ROLE",
       "name": "aws-production",
       "role_arn": "arn:aws:iam::123456789012:role/qovery-role"
     }'
   ```

   IMPORTANT: The `type` field (`AWS_ROLE` or `AWS_STATIC`) is required, and the ARN field is `role_arn`, not `assumed_role_arn`. Getting either wrong makes the API parse the body as static credentials and fail with a misleading `access_key_id is required` error — that does not mean role/ARN credentials are unsupported.

**AWS Credentials (Static Keys — Alternative)**

If the user cannot use STS Assume Role:

1. Create an IAM user `qovery` in AWS Console
2. Apply the Qovery IAM policy: download from `https://www.qovery.com/docs/files/qovery-iam-aws.json`
3. Create access keys for the user (Security Credentials > Create access key)
4. Save in Qovery:
   ```bash
   curl -s -X POST "https://api.qovery.com/organization/{orgId}/aws/credentials" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "AWS_STATIC",
       "name": "aws-production",
       "access_key_id": "AKIA...",
       "secret_access_key": "..."
     }'
   ```

#### GCP Credentials

1. **Get the GCP Project ID** from the Google Cloud Console project selector
2. **Open Google Cloud Shell** (terminal icon in top-right of Google Cloud Console)
3. **Run the Qovery credential creation script**:
   ```bash
   curl https://hub.qovery.com/files/create_credentials_gcp.sh | bash -s -- YOUR_PROJECT_ID qovery_role qovery-service-account
   ```
   This enables required APIs, creates a service account, assigns IAM roles, and generates a `key.json` file.
4. **Download `key.json`** from Cloud Shell (More menu > Download > enter `key.json`)
5. **Upload to Qovery Console** (Organization Settings > Cloud Credentials > Add GCP) or save via API:
   ```bash
   curl -s -X POST "https://api.qovery.com/organization/{orgId}/gcp/credentials" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "gcp-production",
       "gcp_credentials": "'"$(cat key.json | base64)"'"
     }'
   ```

IMPORTANT: The `key.json` file grants access to the GCP project. Never commit it to git.

#### Azure Credentials

1. **Get your Tenant ID**: Azure Portal > Azure Active Directory > Overview > copy Tenant ID
2. **Get your Subscription ID**: Azure Portal > Subscriptions > copy Subscription ID
3. **Open Azure Cloud Shell** (>_ icon in top navigation) — select **Bash** mode (not PowerShell)
4. **Go to Qovery Console** > Clusters > Create Cluster > Select Azure > Enter Tenant ID and Subscription ID
5. **Copy the generated command** from Qovery Console and run it in Azure Cloud Shell
   - This creates a service principal and assigns Contributor role
   - Credentials are automatically linked to your Qovery organization

#### Scaleway Credentials

1. **Get your Scaleway Access Key and Secret Key** from the Scaleway Console > IAM > API Keys
2. **Get your Organization ID and Project ID** from Scaleway Console
3. **Save in Qovery Console** (Organization Settings > Cloud Credentials > Add Scaleway) or via API

### 2B.3 Create the Cluster

After credentials are set up, create the cluster. There are three options:

#### Option A: Via Qovery Console (Recommended for first-time setup)

This is the easiest way to create your first cluster:

1. Go to https://console.qovery.com
2. Click **Clusters** in the left sidebar
3. Click **Create Cluster**
4. Select your cloud provider (AWS / GCP / Azure / Scaleway)
5. Choose **Qovery Managed** (recommended) or **Self-Managed (BYOK)** if you have an existing cluster
6. Configure:
   - **Cluster name**: e.g., `production` or `staging`
   - **Region**: Choose the region closest to your users
   - **Credentials**: Select the credentials you just created
   - **Production cluster**: Toggle ON if this is for production workloads
7. Configure resources (depends on provider):
   - **AWS**: Select instance types for Karpenter (recommend selecting 10-20 types across t3, m5, m6i families), enable Spot instances for cost savings, set disk size (minimum 20GB)
   - **GCP**: GKE Autopilot handles node provisioning automatically
   - **Azure**: Select VM sizes (e.g., Standard_D2ads_v5 for general purpose)
   - **Scaleway**: Select node type and count
8. Configure features (VPC, Static IP, etc.) — defaults are fine for most users
9. Click **Create and Deploy**
10. Wait 15-30 minutes for the cluster to be ready

#### Option B: Via Qovery API

```bash
# Step 1: Get your credentials ID
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/aws/credentials" | jq '.results[] | {id, name}'

# Step 2: Create the cluster
curl -s -X POST "https://api.qovery.com/organization/{orgId}/cluster" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "region": "us-east-1",
    "cloud_provider": "AWS",
    "cloud_provider_credentials": {
      "credentials": {
        "id": "{credentialsId}"
      }
    },
    "kubernetes": "MANAGED",
    "production": true,
    "disk_size": 50,
    "instance_type": "T3A_LARGE",
    "min_running_nodes": 3,
    "max_running_nodes": 10
  }' | jq '{id, name, status}'

# Step 3: Deploy (install) the cluster
curl -s -X POST "https://api.qovery.com/cluster/{clusterId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json"
```

Adapt `cloud_provider`, `region`, and `instance_type` for other providers:
- GCP: `"cloud_provider": "GCP"`, `"region": "us-central1"`
- Azure: `"cloud_provider": "AZURE"`, `"region": "eastus"`, `"instance_type": "STANDARD_D2ADS_V5"`
- Scaleway: `"cloud_provider": "SCW"`, `"region": "fr-par"`

#### Option C: Via Terraform Provider

```hcl
# AWS credentials
resource "qovery_aws_credentials" "my_aws_creds" {
  organization_id   = var.qovery_organization_id
  name              = "aws-production"
  access_key_id     = var.aws_access_key_id
  secret_access_key = var.aws_secret_access_key
}

# Cluster
resource "qovery_cluster" "production" {
  organization_id   = var.qovery_organization_id
  credentials_id    = qovery_aws_credentials.my_aws_creds.id
  name              = "production"
  cloud_provider    = "AWS"
  region            = "us-east-1"
  instance_type     = "T3A_LARGE"
  disk_size         = 50
  min_running_nodes = 3
  max_running_nodes = 10
}
```

For GCP:
```hcl
resource "qovery_gcp_credentials" "my_gcp_creds" {
  organization_id = var.qovery_organization_id
  name            = "gcp-production"
  credentials     = file("key.json")
}

resource "qovery_cluster" "production" {
  organization_id = var.qovery_organization_id
  credentials_id  = qovery_gcp_credentials.my_gcp_creds.id
  name            = "production"
  cloud_provider  = "GCP"
  region          = "us-central1"
}
```

For Azure:
```hcl
resource "qovery_azure_credentials" "my_azure_creds" {
  organization_id = var.qovery_organization_id
  name            = "azure-production"
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
}

resource "qovery_cluster" "production" {
  organization_id = var.qovery_organization_id
  credentials_id  = qovery_azure_credentials.my_azure_creds.id
  name            = "production"
  cloud_provider  = "AZURE"
  region          = "eastus"
  instance_type   = "STANDARD_D2ADS_V5"
}
```

For Scaleway:
```hcl
resource "qovery_scaleway_credentials" "my_scw_creds" {
  organization_id         = var.qovery_organization_id
  name                    = "scaleway-production"
  scaleway_access_key     = var.scaleway_access_key
  scaleway_secret_key     = var.scaleway_secret_key
  scaleway_project_id     = var.scaleway_project_id
  scaleway_organization_id = var.scaleway_organization_id
}

resource "qovery_cluster" "production" {
  organization_id = var.qovery_organization_id
  credentials_id  = qovery_scaleway_credentials.my_scw_creds.id
  name            = "production"
  cloud_provider  = "SCW"
  region          = "fr-par"
}
```

### 2B.4 Wait for Cluster to Be Ready

Cluster creation takes 15-30 minutes. Here's what happens during this time:

| Step | Time | What's Being Created |
|------|------|---------------------|
| 1. Networking | 3-5 min | VPC, subnets, security groups, NAT gateways |
| 2. Kubernetes Control Plane | 10-15 min | EKS/GKE/AKS master nodes |
| 3. Worker Nodes | 5-10 min | Compute instances for your workloads |
| 4. Qovery Components | 3-5 min | Ingress controller, cert-manager, monitoring |

Monitor the cluster status:

```bash
# Via CLI
qovery cluster list

# Via API (poll until status is DEPLOYED or READY)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {name, status, deployment_status}'
```

Once the cluster status shows **DEPLOYED** or **READY**, proceed to Phase 3.

IMPORTANT: Tell the user they can continue analyzing their codebase and preparing Dockerfiles (Phases 3-5) while waiting for the cluster. The cluster only needs to be ready before the final deployment step.

