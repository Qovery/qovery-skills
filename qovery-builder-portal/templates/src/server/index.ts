- Import express, passport, path
- Import sessionMiddleware from routes/auth
- Import all route modules (auth, environments, templates, me)
- Import auth middleware
- Configure: express.json(), sessionMiddleware, passport.initialize(), passport.session()
- Mount routes:
  /auth → auth routes (no auth middleware)
  /api/environments → environments routes (auth middleware required)
  /api/templates → templates routes (auth middleware required)
  /api/me → me routes (auth middleware required)
- In production: serve the built frontend from dist/client as static files
- SPA fallback: serve index.html for all non-API routes
- Listen on PORT (default 3000)
