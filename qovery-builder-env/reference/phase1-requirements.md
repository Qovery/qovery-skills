## PHASE 1: Understand the Builder Use Case

Before setting up anything, understand who the builders are, what they need, and what the platform requirements are. Ask questions conversationally — NOT as a wall of text.

### 1.1 Authenticate

Run `qovery api /organization` to confirm the CLI is authenticated. If it succeeds, use `qovery api` for every API call in this skill (no token needs to be extracted). If it fails, fall back to the token / JWT / login tiers documented in the auth reference loaded with this skill.

### 1.2 Understand Who Will Build

Ask the platform engineer about the builders:

1. **Who are the builders?** — Which teams will use the builder environments?
   - Sales (building internal tools, dashboards, CRM extensions)
   - Finance (building analytics tools, reporting dashboards)
   - Operations (building automation workflows, monitoring tools)
   - Marketing (building landing pages, campaign tools)
   - Product (building prototypes, internal tools)
   - Everyone (company-wide "All Builders" initiative)

2. **How many builders?** — This determines the provisioning strategy:
   - 1-5: Manual provisioning is fine
   - 5-20: Semi-automated (script-assisted)
   - 20+: Fully automated with bulk provisioning

3. **What will they build?** — This determines the template contents:
   - Internal tools (dashboards, CRUD apps, workflows)
   - Customer-facing prototypes
   - Data analysis tools
   - Automation scripts
   - API integrations

4. **What's their technical level?** — This determines the IDE choice:
   - **Zero coding experience** -> visual builder (Lovable-like, Bolt.new)
   - **Some scripting / HTML-CSS** -> VS Code with Copilot (guided, visual)
   - **Comfortable with code** -> Claude Code / OpenCode (terminal, powerful)

5. **What data do they need access to?** — This determines security requirements:
   - Public data only -> minimal restrictions
   - Internal CRM/sales data -> needs access controls
   - Customer PII / financial data -> needs strict RBAC + audit + compliance
   - Production databases -> read-only replicas recommended

### 1.3 Understand Platform Requirements

Ask about infrastructure and compliance:

1. **SSO provider?** — Google Workspace, Okta, Azure AD, OneLogin, or none
2. **Compliance requirements?** — SOC2, ISO 27001, HIPAA, HDS, GDPR, or none
   - Qovery is SOC2 Type II certified out of the box and working on ISO 27001 and HDS
3. **Cloud provider?** — AWS, GCP, Azure, or Scaleway
   - If they don't have a Qovery cluster yet -> reference the qovery-onboard skill
4. **Existing Qovery setup?** — Already have org/cluster/projects, or starting from scratch?
5. **Budget constraints?** — Any per-builder cost limits? Total budget for the builder program?

6. **Isolation level?** — How should builder environments be isolated from each other?
   > 1. **Shared project** — all builder environments live in one Qovery project. Simpler to manage. Builders can see each other's environment names (but not access them, thanks to RBAC). Good for small teams with no sensitive data.
   > 2. **Project-per-builder** (recommended for security) — each builder gets their own Qovery project containing their environment. Full isolation — builders cannot see each other's environments at all. Better for sensitive data, compliance, or larger organizations.

7. **Environment TTL (time-to-live)?** — How long should each builder environment stay alive?
   > Builder environments should be temporary to avoid wasting resources. Choose a default TTL:
   > - **8 hours** — environment stops after a workday
   > - **24 hours** — environment stops after a day
   > - **48 hours** — environment stops after two days
   > - **1 week** — environment stops after a week
   > - **Custom** — specify a duration or a specific date
   > - **No TTL** — environments stay alive until manually stopped (not recommended)
   >
   > After stopping, should the environment be **automatically deleted** after an additional period?
   > - Yes, delete after {N days} of being stopped
   > - No, keep it stopped indefinitely (can be restarted later)

8. **Deployment targets?** — Internal only, or some apps may go to production?
   - If production is possible -> enable Phase 7B (Production Graduation)

### 1.4 Choose the Builder Experience

Based on the technical level from 1.2, present the AI tool options:

**Tier 1: Visual Builder (Zero-Code)**
Best for: Sales, marketing, finance with no coding experience.
- Browser-based visual interface (Lovable-like, Bolt.new, v0)
- Drag-and-drop UI building
- AI describes-and-builds approach
- Deployed as a web application container in the builder's environment

**Tier 2: VS Code + Copilot (Low-Code)**
Best for: Product managers, analysts, technically curious non-engineers.
- VS Code in the browser (code-server or OpenVSCode Server)
- GitHub Copilot for AI-assisted coding
- Familiar IDE interface with file explorer, terminal, extensions
- Qovery CLI + skills pre-installed for one-command deployment

**Tier 3: Terminal + Claude Code / OpenCode (Code-Comfortable)**
Best for: Technical PMs, data scientists, engineers from other teams.
- Full terminal environment with AI coding agents
- Claude Code or OpenCode for conversational coding
- Maximum power and flexibility
- Web terminal via ttyd or similar

Ask:
> "Based on your builders' profiles, which experience(s) do you want to offer? You can choose multiple — each builder will get the tier that matches their level."

---

