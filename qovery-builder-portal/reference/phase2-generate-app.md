# Phase 2 — Generate the portal application

Generate a complete, deployable web app under `builder-portal/`. Most files exist as ready-to-copy templates in `templates/` — the model copies them and adapts placeholders, instead of regenerating code from scratch.

## 2.1 Project structure

```
builder-portal/
├── package.json                          # template: templates/package.json
├── tsconfig.json
├── tsconfig.server.json
├── vite.config.ts
├── tailwind.config.ts
├── postcss.config.js
├── Dockerfile                            # template: templates/Dockerfile
├── .dockerignore
├── .env.example                          # template: templates/.env.example
├── index.html                            # Vite entry
├── src/
│   ├── client/                           # Vite + React + TanStack Router
│   │   ├── main.tsx                      # agent-generated (see 2.3)
│   │   ├── router.tsx                    # agent-generated (see 2.3)
│   │   ├── routes/
│   │   │   ├── __root.tsx                # agent-generated
│   │   │   ├── index.tsx                 # agent-generated (dashboard)
│   │   │   ├── new.tsx                   # agent-generated (create)
│   │   │   └── login.tsx                 # agent-generated
│   │   ├── components/
│   │   │   ├── EnvironmentCard.tsx       # template: templates/src/client/components/EnvironmentCard.tsx
│   │   │   ├── TemplateSelector.tsx      # agent-generated
│   │   │   ├── StatusBadge.tsx           # agent-generated
│   │   │   ├── TTLCountdown.tsx          # agent-generated
│   │   │   └── ServiceLinks.tsx          # agent-generated
│   │   ├── lib/
│   │   │   └── api.ts                    # template: templates/src/client/lib/api.ts
│   │   └── index.css                     # @tailwind base/components/utilities
│   ├── server/                           # Express + TypeScript
│   │   ├── index.ts                      # template: templates/src/server/index.ts
│   │   ├── routes/
│   │   │   ├── auth.ts                   # template: templates/src/server/routes/auth.ts
│   │   │   ├── environments.ts           # template: templates/src/server/routes/environments.ts
│   │   │   ├── templates.ts              # template: templates/src/server/routes/templates.ts
│   │   │   └── me.ts                     # template: templates/src/server/routes/me.ts
│   │   ├── services/
│   │   │   ├── qovery.ts                 # template: templates/src/server/services/qovery.ts
│   │   │   └── provisioner.ts            # template: templates/src/server/services/provisioner.ts
│   │   ├── middleware/
│   │   │   └── auth.ts                   # template: templates/src/server/middleware/auth.ts
│   │   └── config.ts                     # template: templates/src/server/config.ts
│   └── shared/
│       └── types.ts                      # template: templates/src/shared/types.ts
└── public/
    └── favicon.svg                       # agent-generated (use COMPANY_LOGO_URL or default)
```

## 2.2 Backend (use templates verbatim)

Every file marked `template:` in the tree above is a complete, working implementation. **Copy each template into `builder-portal/<same-relative-path>` without modification** — the templates already handle SSO, session validation, Qovery API calls, blueprint cloning, TTL lifecycle jobs, and per-builder isolation correctly.

```bash
# Example
mkdir -p builder-portal/src/server/services
cp templates/src/server/services/qovery.ts builder-portal/src/server/services/qovery.ts
cp templates/src/server/services/provisioner.ts builder-portal/src/server/services/provisioner.ts
# …repeat for every template
```

Backend files to generate (no template — write directly):

- `src/server/routes/templates.ts` (3 lines) — listed in template file but trivial
- `src/server/routes/me.ts` (3 lines) — same
- `src/server/middleware/auth.ts` (4 lines) — same

The three above are tiny enough to be written inline; their templates serve as reference.

## 2.3 Frontend (agent-generated from spec)

The frontend has more visual variation (branding, layout) and benefits from being generated to match the user's brand choices from Phase 1.3. Adapt styling to: company name, primary color, logo URL.

| File | Specification |
|------|--------------|
| `src/client/main.tsx` | React entry point: render `<RouterProvider>` from TanStack Router. Wrap in `<StrictMode>`. |
| `src/client/router.tsx` | TanStack Router setup: create router with route tree from `routes/`. Enable `defaultPreload: 'intent'`. |
| `src/client/routes/__root.tsx` | Root layout: header with company logo + name, user avatar + name (from `/api/me`), logout button. `<Outlet />` for child routes. Redirect to `/login` if not authenticated. |
| `src/client/routes/index.tsx` | Dashboard: fetch environments from API on mount. Show grid of `<EnvironmentCard>`. If empty, show friendly message + "Create your first workspace" button. Auto-refresh every 10 seconds. "Create New Workspace" button in top-right. |
| `src/client/routes/new.tsx` | Create page: fetch templates from API. Show `<TemplateSelector>` as a grid of cards. After selecting + clicking "Create", call `api.createEnvironment()`, show spinner, redirect to dashboard on success. Show error if at limit. |
| `src/client/routes/login.tsx` | Login page: company logo, company name, "Sign in with {SSO provider}" button. The button links to `/auth/login`. Clean, non-intimidating design. |
| `src/client/components/TemplateSelector.tsx` | Grid of template cards. Each shows icon, name, description. Clicking selects it (highlighted border). |
| `src/client/components/StatusBadge.tsx` | Colored badge: green for DEPLOYED, yellow for DEPLOYING/BUILDING, gray for STOPPED, red for ERROR. Small dot + text. |
| `src/client/components/ServiceLinks.tsx` | List of clickable links. Workspace link is styled as primary button ("Open Workspace"). Other service links are regular links with the service name. Each opens in a new tab. |
| `src/client/components/TTLCountdown.tsx` | Shows time remaining until TTL expiry. Format: "6h 23m remaining". Red when < 1h. |
| `src/client/index.css` | Tailwind imports: `@tailwind base; @tailwind components; @tailwind utilities;` |
| `index.html` | Standard Vite HTML entry: `<div id="root">`, `<script type="module" src="/src/client/main.tsx">`. Title: "{company_name} Builder Portal". |

`EnvironmentCard.tsx` and `lib/api.ts` are provided as templates — adapt the imports / styling to match the rest of the frontend.

## 2.4 Dockerfile

Use `templates/Dockerfile` as-is. It is a 4-stage build (deps / frontend / backend / production) that copies the platform config if present.

## 2.5 package.json + config

Use `templates/package.json` as-is. Generate the remaining config files directly:

- `vite.config.ts` — React plugin, dev proxy for `/api` and `/auth` to Express, output to `dist/client`
- `tailwind.config.ts` — extend primary color from env vars, content paths pointing to `src/client/**`
- `postcss.config.js` — Tailwind + Autoprefixer
- `tsconfig.json` — base TypeScript config
- `tsconfig.server.json` — target ES2022, outDir `dist/server`
- `.dockerignore` — `node_modules`, `dist`, `.env`, `.git`
