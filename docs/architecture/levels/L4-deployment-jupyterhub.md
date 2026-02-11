<!-- Wygenerowano automatycznie z workspace.dsl + extras/ — NIE EDYTUJ RĘCZNIE -->
<!-- Właściwości DSL są generowane automatycznie; zawartość extras/ jest utrzymywana ręcznie -->
<!-- Regeneracja: ./scripts/generate-diagrams.sh -->

# L4 - Wdrożenie: JupyterHub

> Granica kontenera dla JupyterHub w ramach dlh-prd namespace.

<!-- Included in: levels/L4-deployment-jupyterhub.md (deployment boundary, via extras/) -->

## Przegląd

JupyterHub działa jako Deployment **Hub** (zarządzanie użytkownikami, orkiestracja spawnerów) oraz Deployment **Proxy** (routing HTTP). **Pody notebooków użytkowników** są tworzone dynamicznie dla każdego użytkownika przez KubeSpawner — każdy użytkownik otrzymuje izolowany pod z preinstalowanymi jądrami (Python 3, PySpark, Dremio SQL). Wewnętrzna baza danych Hub Database oraz Image Puller to infrastruktura ukryta na poziomie L2, ale wdrożona tutaj na poziomie L4.

## Kluczowe uwagi operacyjne

- Pody notebooków użytkowników są efemeryczne — tworzone przy logowaniu, usuwane przy wylogowaniu/przekroczeniu limitu czasu
- KubeSpawner zarządza limitami zasobów per użytkownik i wyborem profili
- Uwierzytelnianie przez Keycloak OAuthenticator (planowane)
- Jądra łączą się z Dremio (Flight SQL), Spark (Spark Connect) i MinIO (boto3/s3fs)

*TODO: Dodać tabele obiektów Kubernetes, specyfikacje jąder, szczegóły sieci i bezpieczeństwa*

## Monitorowanie

| Punkt końcowy | Wartość |
|---------------|--------|
| Metrics | /hub/metrics (Prometheus, if enabled) |
| Logs | stdout → external log collector |

## Jednostki uruchomieniowe

### hub

**Typ:** Deployment (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### proxy

**Typ:** Deployment (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### user-notebook

**Typ:** Pod (dynamic, per user)

*TODO: Dodaj szczegóły wdrożenia*
