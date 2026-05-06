## PHASE 3: Codebase Analysis & Dockerfile Creation

### 3.1 Check for Existing Dockerfile

Look for `Dockerfile` in the project root or in subdirectories for monorepos. If one exists and looks correct, use it. If it is missing or incomplete, create one using the templates below.

### 3.2 Create .dockerignore

If no `.dockerignore` exists, always create one. Adapt based on the detected language:

```dockerignore
# Common
.git
.gitignore
.env
.env.*
*.md
LICENSE
docker-compose*.yml
.dockerignore
Dockerfile

# Node.js
node_modules
npm-debug.log
.next
.nuxt
dist
coverage
.nyc_output

# Python
__pycache__
*.pyc
.venv
venv
.pytest_cache
.mypy_cache

# Go
vendor (if not using go mod vendor)

# Java
target
build
.gradle
.idea

# General
.vscode
.idea
*.swp
*.swo
```

### 3.3 Dockerfile Templates

Use the appropriate template based on the detected language/framework. All templates follow best practices: multi-stage builds, non-root user, minimal final image.

#### Node.js — Express / Fastify / NestJS (API server)

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build 2>/dev/null || true

FROM node:22-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist 2>/dev/null || true
COPY --from=builder /app/src ./src 2>/dev/null || true
COPY --from=builder /app/. ./ 2>/dev/null || true
USER appuser
EXPOSE 3000
CMD ["node", "src/index.js"]
```

IMPORTANT: Adapt the CMD to match the actual entry point found in `package.json` scripts (`start` or `main` field). Adjust the EXPOSE port to match the actual port the app listens on.

#### Next.js (SSR / Full-Stack)

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
USER appuser
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

IMPORTANT: Next.js standalone output must be enabled. Check `next.config.js` or `next.config.mjs` and add if missing:
```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
};
module.exports = nextConfig; // or: export default nextConfig;
```

#### React / Vite (SPA — Static Frontend)

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
# For React (CRA), use /app/build instead of /app/dist

# SPA routing support — serve index.html for all routes
RUN printf 'server {\n\
    listen 80;\n\
    server_name _;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
    location /assets {\n\
        expires 1y;\n\
        add_header Cache-Control "public, immutable";\n\
    }\n\
}\n' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

IMPORTANT: For Vite projects the build output is in `dist/`. For Create React App (CRA) projects it is in `build/`. Check `package.json` or the framework config to confirm.

#### Python — Flask

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
USER appuser
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "app:app"]
```

IMPORTANT: Adjust the `app:app` in the CMD to match the actual Flask application module and variable name (e.g., `wsgi:app`, `main:create_app()`). If gunicorn is not in requirements.txt, add it.

#### Python — Django

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
RUN python manage.py collectstatic --noinput 2>/dev/null || true
USER appuser
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "myproject.wsgi:application"]
```

IMPORTANT: Replace `myproject` with the actual Django project name (the directory containing `wsgi.py`). If gunicorn is not in requirements.txt, add it.

#### Python — FastAPI

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

IMPORTANT: Adjust `main:app` to match the actual module and FastAPI app variable. If uvicorn is not in requirements.txt, add it.

#### Go

```dockerfile
FROM golang:1.24-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/server .
USER appuser
EXPOSE 8080
CMD ["./server"]
```

IMPORTANT: If the main package is not in the root directory, adjust the build command (e.g., `go build -o /app/server ./cmd/server`). Check `go.mod` for the module path.

#### Java — Spring Boot (Maven)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY pom.xml .
COPY .mvn .mvn
COPY mvnw .
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B
COPY src ./src
RUN ./mvnw package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
USER appuser
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

#### Java — Spring Boot (Gradle)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY build.gradle* settings.gradle* gradlew ./
COPY gradle ./gradle
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon
COPY src ./src
RUN ./gradlew bootJar --no-daemon -x test

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
USER appuser
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

#### Ruby — Rails

```dockerfile
FROM ruby:3.3-slim AS builder
RUN apt-get update && apt-get install -y build-essential libpq-dev nodejs npm && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && bundle config set --local without 'development test' && bundle install
COPY . .
RUN SECRET_KEY_BASE=placeholder bundle exec rake assets:precompile 2>/dev/null || true

FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y libpq-dev && rm -rf /var/lib/apt/lists/*
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /app /app
USER appuser
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

#### PHP — Laravel

```dockerfile
FROM composer:2 AS deps
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

FROM php:8.3-fpm-alpine AS builder
RUN apk add --no-cache postgresql-dev && docker-php-ext-install pdo_pgsql
WORKDIR /app
COPY --from=deps /app/vendor ./vendor
COPY . .
RUN composer dump-autoload --optimize --no-dev

FROM php:8.3-fpm-alpine
RUN apk add --no-cache nginx postgresql-dev && docker-php-ext-install pdo_pgsql
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app /app
COPY nginx.conf /etc/nginx/http.d/default.conf
RUN chown -R appuser:appgroup /app/storage /app/bootstrap/cache
EXPOSE 80
CMD ["sh", "-c", "php-fpm -D && nginx -g 'daemon off;'"]
```

#### .NET

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder
WORKDIR /app
COPY *.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:9.0
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /app/publish .
USER appuser
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
CMD ["dotnet", "MyApp.dll"]
```

IMPORTANT: Replace `MyApp.dll` with the actual assembly name from your `.csproj` file (the `<AssemblyName>` property or project file name).

