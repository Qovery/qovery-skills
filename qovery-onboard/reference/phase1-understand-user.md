## PHASE 1: Understand the User

Before doing anything, UNDERSTAND who the user is. Ask questions conversationally — NOT as a wall of text. Group related questions together. Adapt follow-up questions based on their answers. Skip questions that are already answered by context.

**Shortcut:** If the user provided a Qovery Console URL, they already have an account. Extract the organization ID (and any other IDs) from the URL using the URL Detection rules above. Use these to query what's already set up (clusters, projects, environments) and skip questions about resources that already exist. Focus the onboarding conversation on what's NOT yet configured.

### Group 1: Who Are You?

1. **What's your role?**
   - **Developer / Full-stack engineer** — wants to deploy apps, doesn't care about infrastructure details
   - **DevOps / Platform engineer** — wants to understand and control infrastructure, set guardrails for the team
   - **CTO / Tech lead** — wants strategic overview, delegates execution to team
   - **Founder / Bootstrapper** — wants maximum speed, zero friction, iterate later
   - **Non-technical** (product manager, designer, "Vercel Engineer") — just wants the app URL, doesn't want to see infrastructure

   Based on the answer, adjust your communication:
   - For developers/founders/non-technical: hide complexity, use simple language, make decisions for them
   - For DevOps/platform engineers: show technical details, explain tradeoffs, offer more configuration options
   - For CTOs: provide strategic overview, focus on cost/security/reliability tradeoffs

2. **What's your experience level with cloud infrastructure?**
   - **None** — "I've never deployed to the cloud before"
     → Maximize hand-holding. Explain concepts in one sentence when they come up. Make ALL decisions for the user. Hide Kubernetes entirely.
   - **Basic** — "I've used Vercel/Heroku/Railway but not Kubernetes"
     → Familiar with deployment concepts (apps, databases, env vars) but not K8s specifics. Explain K8s concepts only when relevant.
   - **Intermediate** — "I know Docker, have some AWS/GCP experience"
     → Can understand technical choices. Wants guidance on best practices, not hand-holding.
   - **Advanced** — "I manage Kubernetes clusters daily"
     → Skip basics. Focus on Qovery-specific setup. Offer BYOK path.

3. **Do you know what Kubernetes is?**
   - If **NO**: "Kubernetes is the technology that runs your apps reliably in the cloud. Qovery manages it entirely for you — you don't need to learn it or even think about it. You'll just deploy your applications and Qovery handles everything underneath."
   - If **YES**: "Great! Do you already have a Kubernetes cluster you'd like to use, or should Qovery create and manage one for you?"

### Group 2: What Do You Have?

4. **Do you already have a cloud provider account?** (AWS, GCP, Azure, Scaleway)
   - If **NO**: "No problem — I'll help you choose the right cloud provider and set one up." (Phase 2 handles provider selection)
   - If **YES**: Which one? Do you have admin access to create IAM roles and resources?

5. **Do you already have a Kubernetes cluster?**
   - If **NO**: "Qovery will create and manage one for you — that's the easiest path and I recommend it." → Managed cluster path
   - If **YES**: "You can install Qovery on your existing cluster. This is called BYOK (Bring Your Own Kubernetes)." → Phase 4 (BYOK path)
     - What K8s distribution? (EKS, GKE, AKS, self-managed, Rancher, k3s, etc.)
     - What version?
     - Do you have kubectl access with cluster-admin permissions?

6. **What applications do you want to deploy?**
   - Web applications (frontend + backend)
   - APIs / microservices
   - Databases (PostgreSQL, MySQL, MongoDB, Redis)
   - Background workers / message queues
   - ML/AI workloads (GPU required?)
   - Scheduled jobs (cron)
   - Terraform modules / cloud resources (S3, Lambda, RDS Aurora, etc.)
   - Helm charts
   - "I'm not sure yet, just exploring"

7. **Are you migrating from another platform?**
   - Heroku → Phase 5.1 (detailed migration guide)
   - Vercel / Netlify → Phase 5.2
   - Render / Railway / Fly.io → Phase 5.3
   - Manual Kubernetes → Phase 5.4
   - No migration — starting fresh

### Group 3: What Do You Need?

8. **What's your primary goal with Qovery?**
   - Quick prototyping / testing (speed over everything, iterate later)
   - Production deployment for a startup (reliable, cost-conscious)
   - Enterprise deployment (compliance, RBAC, multi-cluster, audit trails)
   - Migration from another platform
   - Internal developer platform (self-service for dev teams, guardrails for platform team)

9. **Industry and compliance requirements?**
   - No specific compliance needs
   - Healthcare (HIPAA)
   - Finance (PCI-DSS, SOC2)
   - Government (FedRAMP, ITAR)
   - EU data residency (GDPR)
   - General SOC2 / ISO 27001
   - "I'm not sure" → Ask if they handle sensitive data (health records, payment info, personal data of EU citizens)

10. **Any specific constraints?**
    - Data must stay in a specific region (EU-only, US-only, specific country)
    - Must use a specific cloud provider (company policy)
    - Budget constraints — approximate monthly budget? ($50-100 for prototyping, $200-500 for startup, $1000+ for production, enterprise budget)
    - Must use private networking (no public endpoints by default)
    - Must integrate with existing CI/CD (GitHub Actions, GitLab CI, etc.)
    - Team size: solo, small team (2-10), medium (10-50), large (50+)

11. **Do you have team members to invite?**
    - If yes: how many, and what roles? (developers, DevOps, viewers, billing managers)
    - Will they need different access levels? (e.g., devs can deploy to staging but not production)

---

