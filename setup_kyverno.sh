#!/usr/bin/env bash
set -e

# ================================
# Davtro Website - ArgoCD + GHCR + Kustomize setup
# ================================

# Konfiguracja
REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno01"
NAMESPACE="davtrokyverno01"
IMAGE_NAME="website-argocd-k8s-githubactions-kustomize-kyverno01"

echo "📦 Tworzenie projektu ${REPO_NAME}..."
mkdir -p ${REPO_NAME}/src \
         ${REPO_NAME}/manifests/base \
         ${REPO_NAME}/manifests/production \
         ${REPO_NAME}/.github/workflows \
         ${REPO_NAME}/argocd \
         ${REPO_NAME}/policies

cd ${REPO_NAME}

# ================================
# 1) package.json
# ================================
cat > package.json <<'EOF'
{
  "name": "website-argocd-k8s-githubactions-kustomize-kyverno01",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "cp -r src/* dist/ || true"
  },
  "dependencies": {}
}
EOF

# ================================
# 2) Prosty index.html
# ================================
cat > src/index.html <<'EOF'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8"/>
    <title>Davtro Website - Kyverno 01</title>
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <style>
      body{font-family:system-ui,Arial,Helvetica,sans-serif;margin:0;padding:4rem;text-align:center;background:#f5f7fb}
      h1{color:#223}
      p{color:#444}
      .card{background:white;padding:2rem;border-radius:12px;box-shadow:0 6px 18px rgba(20,30,50,0.08);display:inline-block}
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Davtro — Kyverno 01</h1>
      <p>Automatyczne wdrożenie z ArgoCD + GitHub Actions + Kustomize + Kyverno + Vault.</p>
    </div>
  </body>
</html>
EOF

# ================================
# 3) Dockerfile
# ================================
cat > Dockerfile <<'EOF'
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm ci --no-audit --no-fund || true
COPY src ./src
RUN npm run build

FROM nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

# ================================
# 4) Manifests base
# ================================
cat > manifests/base/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website
spec:
  replicas: 1
  selector:
    matchLabels:
      app: website
  template:
    metadata:
      labels:
        app: website
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "${NAMESPACE}-role"
        vault.hashicorp.com/agent-inject-secret-site-creds: "kv/data/${NAMESPACE}/site"
        vault.hashicorp.com/agent-inject-template-site-creds: |
          {{- with secret "kv/data/${NAMESPACE}/site" -}}
          export SITE_API_KEY="{{ .Data.data.api_key }}"
          {{- end -}}
    spec:
      containers:
        - name: website
          image: ghcr.io/${REPO_OWNER}/${IMAGE_NAME}:latest
          ports:
            - containerPort: 80
EOF

cat > manifests/base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: website
spec:
  selector:
    app: website
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF

cat > manifests/base/ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: website-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: ${NAMESPACE}.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: website
                port:
                  number: 80
EOF

cat > manifests/base/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml

namespace: ${NAMESPACE}

images:
  - name: ghcr.io/${REPO_OWNER}/${IMAGE_NAME}
    newName: ghcr.io/${REPO_OWNER}/${IMAGE_NAME}
    newTag: latest
EOF

cat > manifests/production/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../base
EOF

# ================================
# 5) ArgoCD Application
# ================================
cat > argocd/application.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${NAMESPACE}-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/${REPO_OWNER}/${REPO_NAME}.git'
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# ================================
# 6) GitHub Actions workflow
# ================================
cat > .github/workflows/ci.yml <<EOF
name: CI - build & update kustomize

on:
  push:
    branches: [ "main", "master" ]
  workflow_dispatch:

env:
  IMAGE_NAME: ${IMAGE_NAME}
  KUSTOMIZE_BASE: manifests/base/kustomization.yaml

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v2
      - uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: \${{ github.repository_owner }}
          password: \${{ secrets.GHCR_PAT }}

      - name: Build and push image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: ghcr.io/\${{ github.repository_owner }}/${IMAGE_NAME}:\${{ github.sha }}

      - name: Update Kustomize image tag
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          sed -i "s|newTag: .*|newTag: \${{ github.sha }}|" \${KUSTOMIZE_BASE}
          git add \${KUSTOMIZE_BASE}
          git commit -m "ci: update image tag to \${{ github.sha }}" || echo "No changes"
          git push
EOF

# ================================
# 7) Kyverno Policy
# ================================
cat > policies/kyverno-no-latest-tag.yaml <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-image-tag
spec:
  validationFailureAction: enforce
  rules:
    - name: deny-latest-tag
      match:
        resources:
          kinds:
            - Pod
            - Deployment
      validate:
        message: "Image tag must not be 'latest'."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
EOF

# ================================
# Finish
# ================================
echo "✅ Projekt ${REPO_NAME} został wygenerowany."
echo
echo "➡ Instrukcje:"
echo "1. cd ${REPO_NAME}"
echo "2. git init && git remote add origin git@github.com:${REPO_OWNER}/${REPO_NAME}.git"
echo "3. git add . && git commit -m 'init project'"
echo "4. git push -u origin main"
echo "5. W ArgoCD: apply argocd/application.yaml"
echo
echo "💡 Ustaw sekreta GHCR_PAT w GitHub → Settings → Secrets → Actions   "
