# Stage 1: Install dependencies
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Stage 2: Build frontend
FROM deps AS frontend-build
COPY . .
RUN npm run build:client

# Stage 3: Build backend
FROM deps AS backend-build
COPY . .
RUN npm run build:server

# Stage 4: Production
FROM node:22-alpine AS production
WORKDIR /app

# Copy built assets
COPY --from=backend-build /app/dist/server ./dist/server
COPY --from=frontend-build /app/dist/client ./dist/client
COPY --from=deps /app/node_modules ./node_modules
COPY package.json .

# Copy the platform config if present (can also be mounted or set via env)
COPY builder-platform-config.yaml* ./

ARG QOVERY_SKILLS_VERSION=unknown
ENV NODE_ENV=production
ENV QOVERY_SKILLS_VERSION=$QOVERY_SKILLS_VERSION
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD wget -q --spider http://localhost:3000/api/templates || exit 1

CMD ["node", "dist/server/index.js"]
