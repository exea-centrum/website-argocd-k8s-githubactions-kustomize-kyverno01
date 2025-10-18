# website-argocd-k8s-githubactions-kustomize-kyverno01

website argocd k8s githubactions kustomize kyverno

# przygotowałem kompletny, praktyczny szkielet repozytorium i konfiguracje które od razu możesz użyć. Zrealizowane elementy:

prosty frontend (Node + static) + Dockerfile

Kustomize (base + manifests/production) z namespace davtro

Deployment, Service, Ingress

ArgoCD Application (ArgoCD pobiera manifesty z Twojego repo i deployuje do microk8s)

GitHub Actions workflow, który buduje obraz, pushuje do GHCR i aktualizuje kustomization.yaml (tag obrazu = git SHA), więc ArgoCD wykryje zmianę i wdroży

przykładowa polityka Kyverno (wyszczególniona jako „kiverno” w Twoim opisie — użyłem Kyverno)

integracja z Vault w formie adnotacji Vault Agent Injector (przykład) — link do Terraform Cloud workspace zostawiłeś, więc zostawiam wskazówki które sekret-y ustawić oraz przykładowe adnotacje

zmienne środowiskowe / secrety które musisz ustawić w GitHub Secrets

Poniżej znajdziesz strukturę projektu i pełne pliki do wklejenia.

Struktura repozytorium (proponowana)

```bash
.
├─ Dockerfile
├─ package.json
├─ src/
│ └─ index.html
├─ manifests/
│ ├─ base/
│ │ ├─ deployment.yaml
│ │ ├─ service.yaml
│ │ ├─ ingress.yaml
│ │ └─ kustomization.yaml
│ └─ production/
│ └─ kustomization.yaml
└─ .github/
└─ workflows/
└─ ci.yml
└─ argocd/
└─ application.yaml
└─ policies/
└─ kyverno-no-latest-tag.yaml

```

1. Prosty frontend — pliki

package.json

```bash
{
"name": "website-simple-argocd-k8s-github-kustomize",
"version": "1.0.0",
"private": true,
"scripts": {
"build": "cp -r src/\* dist/ || true"
},
"dependencies": {}
}
```

#### src/index.html

```bash
<!doctype html>
<html>
  <head>
    <meta charset="utf-8"/>
    <title>Davtro Website</title>
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
      <h1>Davtro — demo site</h1>
      <p>Deployed with ArgoCD → microk8s. Image hosted on GHCR.</p>
    </div>
  </body>
</html>
```

Dockerfile

```consol
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm install --no-audit --no-fund || true
COPY src ./src
RUN mkdir -p dist && npm run build

FROM nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

```

2. Kustomize — manifests/base

manifests/base/deployment.yaml

```bash
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
        vault.hashicorp.com/role: "davtrokyverno01-role"
        vault.hashicorp.com/agent-inject-secret-site-creds: "kv/data/davtrokyverno01/site"
        vault.hashicorp.com/agent-inject-template-site-creds: |
          {{- with secret "kv/data/davtrokyverno01/site" -}}
          export SITE_API_KEY="{{ .Data.data.api_key }}"
          {{- end -}}
    spec:
      imagePullSecrets:
        - name: ghcr-secret   # 👈 sekret z danymi do GHCR (utworzony wcześniej)
      containers:
        - name: website
          image: ghcr.io/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno01:latest
          ports:
            - containerPort: 80
```

manifests/base/service.yaml

```bash
apiVersion: v1
kind: Service
metadata:
name: website
spec:
selector:
app: website
type: ClusterIP
ports: - name: http
port: 80
targetPort: 80

manifests/base/ingress.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
name: website-ingress
annotations:
kubernetes.io/ingress.class: "nginx" # dostosuj do twojego ingress controller
spec:
rules: - host: website.davtro.example # zmień na swój host / DNS
http:
paths: - path: /
pathType: Prefix
backend:
service:
name: website
port:
number: 80

manifests/base/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:

- deployment.yaml
- service.yaml
- ingress.yaml

namespace: davtro

images:

- name: ghcr.io/EXAMPLE_OWNER/website-simple-argocd-k8s-github-kustomize
  newName: ghcr.io/EXAMPLE_OWNER/website-simple-argocd-k8s-github-kustomize
  newTag: latest

manifests/production/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:

- ../base

# production-specific patches/overlays (jeśli potrzebujesz)

# tutaj kept simple — GitHub Action będzie aktualizować images.newTag

UWAGA: w images.newName użyj ghcr.io/<GITHUB_ORG_OR_USER>/website-simple-argocd-k8s-github-kustomize. Później GitHub Actions nadpisze newTag na SHA.

3. ArgoCD Application — argocd/application.yaml

(Trzeba to applyować do ArgoCD cluster config / ArgoCD repo; poniżej przykład manifestu Application.)

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
name: website-davtro
namespace: argocd
spec:
project: default
source:
repoURL: 'https://github.com/exea-centrum/website-argocd-k8s-github-kustomize.git' # <-- Twój repo
targetRevision: HEAD
path: manifests/production
destination:
server: 'https://kubernetes.default.svc'
namespace: davtro
syncPolicy:
automated:
prune: true
selfHeal: true
syncOptions: - CreateNamespace=true

ArgoCD będzie monitorować repo i ścieżkę manifests/production i wdrażać do namespace davtro. CreateNamespace=true spowoduje utworzenie ns jeśli brak.

4. GitHub Actions — .github/workflows/ci.yml

Ten workflow:

buduje obraz

taguje jako ghcr.io/<OWNER>/website-simple-argocd-k8s-github-kustomize:${{ github.sha }}

pushuje obraz na GHCR

aktualizuje manifests/base/kustomization.yaml (ustawia images[0].newTag na SHA) i commit → push do repo (ArgoCD wykryje zmianę i zdeployuje)

name: CI - build & update kustomize

on:
push:
branches: [ "main", "master" ]
workflow_dispatch:

env:
IMAGE_NAME: website-simple-argocd-k8s-github-kustomize
KUSTOMIZE_BASE: manifests/base/kustomization.yaml
KUSTOMIZE_PATH: ./manifests/production
KUSTOMIZE_IMAGE_ID: website-simple-argocd-k8s-github-kustomize

jobs:
build-and-push:
runs-on: ubuntu-latest
steps: - name: Checkout
uses: actions/checkout@v4
with:
fetch-depth: 0

      - name: Set up QEMU (for multi-arch, optional)
        uses: docker/setup-qemu-action@v2

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GHCR_PAT }}

      - name: Build and push image
        id: build
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          file: ./Dockerfile

      - name: Update kustomize image tag in manifests/base/kustomization.yaml
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          SHA=${{ github.sha }}
          IMAGE_FULL="ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${SHA}"
          echo "Updating ${KUSTOMIZE_BASE} to tag ${SHA}"
          # Use yq if available; fallback to sed update
          if command -v yq >/dev/null 2>&1; then
            yq -i '.images[0].newTag = "'$SHA'"' $KUSTOMIZE_BASE
            yq -i '.images[0].newName = "ghcr.io/'${{ github.repository_owner }}'/'${{ env.IMAGE_NAME }}'"' $KUSTOMIZE_BASE
          else
            # naive sed updates (works with provided format)
            sed -i 's|newName: .*|newName: ghcr.io/'${{ github.repository_owner }}'/'${{ env.IMAGE_NAME }}'|' $KUSTOMIZE_BASE || true
            sed -i 's|newTag: .*|newTag: '"$SHA"'|' $KUSTOMIZE_BASE || true
          fi
          git add $KUSTOMIZE_BASE
          git commit -m "ci: set image tag to $SHA [ci skip]" || echo "no changes to commit"
          git push origin HEAD:${{ github.ref_name }}

      - name: Create GitHub repo status comment
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const sha = process.env.GITHUB_SHA;
            await github.repos.createCommitComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              commit_sha: sha,
              body: `Built and pushed image to GHCR: ghcr.io/${context.repo.owner}/${process.env.IMAGE_NAME}:${sha}`
            })

Ważne sekrety GitHub (Settings → Secrets):

GHCR_PAT — token z uprawnieniami write:packages (Personal Access Token) lub GITHUB_TOKEN ma ograniczenia dla GHCR w niektórych organizacjach; jeżeli GITHUB_TOKEN wystarcza, można go użyć zamiast PAT.

(opcjonalnie) VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID — zależnie od integracji Vault

5. Kyverno policy (kiverno) — policies/kyverno-no-latest-tag.yaml

Przykład reguły Kyverno: odrzuca użycie :latest lub brak tagu.

apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
name: disallow-latest-image-tag
spec:
validationFailureAction: enforce
rules: - name: deny-latest-tag
match:
resources:
kinds: - Pod - Deployment - DaemonSet - StatefulSet
validate:
message: "Image tag must not be 'latest' and must include a specific tag."
pattern:
spec:
containers: - image: "!*:*latest\*"

Zalecam zainstalować Kyverno w klastrze microk8s (microk8s enable kyverno jeśli dostępne lub Helm chart).
```

6. Vault integration (przykład)

W deployment.yaml dodałem adnotacje vault.hashicorp.com/... — to wymaga zainstalowanego Vault Agent Injector i skonfigurowanego backendu sekretnów (kv). Przykładowe kroki:

W Vault utwórz secret: kv/data/davtro/site z polem api_key.

Stwórz role davtro-role w Vault, powiąż z service account w Kubernetes (lub użyj Kubernetes auth).

Upewnij się, że Injector (Vault K8s) ma odpowiednie uprawnienia i działa.

Jeżeli chcesz użyć Terraform Cloud workspace https://app.terraform.io/app/davtro/workspaces/github-actions-terraform do provisioningu, możesz w nim trzymać konfigurację Vault (policies, roles). Nie zmieniam tego tu wprost, ale workflow CI może eksportować zmienne środowiskowe z Terraform outputs — jeżeli chcesz, mogę przygotować terraform plan do automatyzacji tej części.

7. Instrukcje wdrożenia krok po kroku

W repozytorium (pod manifests/base/kustomization.yaml) zamień EXAMPLE_OWNER na Twój GitHub owner (np. exea-centrum albo Twój user).

Ustaw GitHub Secret GHCR_PAT (token z write:packages) w repo.

W ArgoCD stwórz Application (np. apply argocd/application.yaml) albo dodaj repo do ArgoCD UI i utwórz application wskazując path: manifests/production.

Zainstaluj/upewnij się, że w microk8s działają:

Ingress controller (np. nginx-ingress)

ArgoCD (już masz)

Vault + Vault Agent Injector (jeśli chcesz używać Vault)

Kyverno (opcjonalnie)

Wypchnij kod na main. GitHub Actions zbuduje obraz i zaktualizuje kustomization.yaml. ArgoCD wykryje commit i wykona sync (lub jeśli masz automatyczny sync to zrobi to automatycznie).

Skonfiguruj DNS wskazujący host (w ingress.yaml website.davtro.example).

8. Dodatkowe zalecenia / uwagi bezpieczeństwa

Nie używaj :latest — workflow używa SHA tagu co jest bezpieczniejsze i kompatybilne z Kyverno policy.

Przechowuj hasła/klucze w Vault — nie w manifests.

RBAC: gdy konfigurujesz Vault Role → zrób to minimalnych uprawnień.

ArgoCD repo access: jeśli repo jest prywatne, zarejestruj credential do ArgoCD (SSH key / token).

GHCR auth: jeżeli obraz ma być prywatny, ArgoCD musi mieć pull-secret lub node/pullSecret skonfigurowane (Secret typu docker-registry w davtro ns).

Jeżeli chcesz, mogę od razu:

wygenerować i wkleić kompletne pliki w formie gotowych plików (mogę utworzyć canvas / pojedynczy bundle) — jeśli chcesz, mogę też przygotować dodatkny terraform plan do utworzenia Vault role + policy i Github Action workspace integracji,

albo dostosować hosty, ownera GHCR, oraz sposób aktualizacji kustomize (np. użyć kustomize edit set image zamiast sed/yq).

Daj znać, którą z opcji preferujesz — mogę natychmiast wkleić pełne pliki (wszystko gotowe do kopiowania).

# 🔹 Opcja 1 — włącz uprawnienia zapisu dla GITHUB_TOKEN

To najczystsze rozwiązanie.

Wejdź do repo:
👉 Settings → Actions → General → Workflow permissions

Zaznacz:
✅ Read and write permissions

Zapisz ustawienia.

Uruchom ponownie workflow (możesz zrobić git commit --allow-empty -m "retry" i push, żeby go wymusić).

To wystarczy — github-actions[bot] wtedy będzie mógł git push.

🔹 Opcja 2 — użyj personalnego tokena (PAT)

Jeśli nie chcesz zmieniać globalnych uprawnień, możesz użyć sekreta z Twoim PAT-em.

Utwórz PAT z zakresem:

repo

workflow

write:packages

W repo GitHub → Settings → Secrets → Actions

utwórz sekret o nazwie GHCR_PAT (można użyć tego samego co do GHCR).

W workflow zamień:

Upewnij się, że istnieje sekret w namespace davtrokyverno01

Utwórz go w microk8s:

```bash
microk8s kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=exea-centrum \
  --docker-password=<twój_PAT_z_uprawnieniami_read:packages> \
  --namespace davtrokyverno01
```
