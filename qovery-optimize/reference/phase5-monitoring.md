## PHASE 5: Ongoing Monitoring & Follow-Up

### 5.1 Offer Kubecost Deployment

If Kubecost is not already installed on the cluster:

> "Kubecost provides real-time cost visibility per pod, namespace, and deployment. It shows exactly how much each service costs and identifies optimization opportunities automatically. Would you like me to deploy it on your cluster?"

If the user agrees, deploy Kubecost via Qovery Helm chart:

1. Add the Kubecost Helm repository to the organization:
   - Repository name: `kubecost`
   - URL: `https://kubecost.github.io/cost-analyzer/`

2. Create a Helm service in the environment:
   - Chart: `cost-analyzer`
   - Version: `1.108.0` (or latest)
   - Allow cluster-wide resources: yes
   - Port: 9090 (HTTP, publicly accessible for dashboard access)

3. After deployment, provide the Kubecost dashboard URL to the user.

### 5.2 Cloud Provider Cost Dashboard

For precise billing data beyond estimates:

> "For exact billing data from your cloud provider, you can check:
> - **AWS**: Cost Explorer at https://console.aws.amazon.com/cost-management/
> - **GCP**: Billing at https://console.cloud.google.com/billing
> - **Azure**: Cost Management at https://portal.azure.com/#blade/Microsoft_Azure_CostManagement
> - **Scaleway**: Billing at https://console.scaleway.com/billing
>
> These dashboards show actual charges including data transfer, API calls, and I/O that aren't estimatable from configuration alone."

### 5.3 Offer Qovery Support Review

> "Would you like to share this optimization report with Qovery's support team for a professional review? They can:
> - Validate the recommendations against your specific Qovery plan and pricing
> - Suggest cloud provider-specific optimizations (Reserved Instances, Savings Plans, EDPs)
> - Review your cluster configuration (Karpenter settings, instance type selection)
> - Provide guidance on Qovery Enterprise features for cost management
> - Help with advanced optimizations (KEDA autoscaling, multi-cluster strategies)
>
> You can reach them at:
> - **Email:** support@qovery.com (attach the report from `.qovery/reports/`)
> - **Qovery Console:** In-app chat support
> - **Community Forum:** https://discuss.qovery.com
>
> Sharing the report in `.qovery/reports/` gives them full context for a faster, more targeted review."

### 5.4 Save Report & Schedule Follow-Up

1. **Save both reports:**
   ```bash
   # Already saved during Phase 3:
   .qovery/reports/YYYY-MM-DD-cost-optimization.md   # Full report
   .qovery/reports/YYYY-MM-DD-cost-optimization.csv   # Spreadsheet data
   ```

2. **Offer to commit to git:**
   ```bash
   git add .qovery/reports/
   git commit -m "docs: add cost optimization report YYYY-MM-DD"
   ```

3. **Recommend follow-up schedule:**
   > "I recommend re-running this optimization analysis:
   > - **Monthly** for steady workloads (track drift and new opportunities)
   > - **After traffic pattern changes** (new feature launch, marketing campaign, seasonal event)
   > - **After infrastructure changes** (new services, cluster upgrades, provider migrations)
   > - **Post-seasonal peak** (1 week after Black Friday, etc.) to right-size back down
   > - **Quarterly** at minimum for any business"

---

