<!-- Wygenerowano automatycznie z workspace.dsl + extras/ — NIE EDYTUJ RĘCZNIE -->
<!-- Właściwości DSL są generowane automatycznie; zawartość extras/ jest utrzymywana ręcznie -->
<!-- Regeneracja: ./scripts/generate-diagrams.sh -->

# L4 - Wdrożenie: Superset

> Granica kontenera dla Superset w ramach dlh-prd namespace.

<!-- Included in: levels/L4-deployment-superset.md (deployment boundary, via extras/) -->

## Przegląd

Superset działa jako zestaw Deploymentów i StatefulSetów. Deployment **Web** obsługuje aplikację Flask (dashboardy, SQL Lab, REST API). **Celery Workers** obsługują wykonywanie zapytań w tle, generowanie miniatur i zaplanowane raporty. **Celery Beat** zarządza zadaniami okresowymi. Wewnętrzne **Redis** (broker Celery) i **PostgreSQL** (baza metadanych) to infrastruktura ukryta na poziomie L2, ale wdrożona tutaj na poziomie L4.

## Kluczowe uwagi operacyjne

- Redis i PostgreSQL są wewnętrzne dla Superset — nie są współdzielone z innymi kontenerami
- Uwierzytelnianie przez Keycloak OIDC (planowane)
- Odpytuje Dremio przez Arrow Flight SQL

*TODO: Dodać tabele obiektów Kubernetes, szczegóły sieci i bezpieczeństwa*

## Monitorowanie

| Punkt końcowy | Wartość |
|---------------|--------|
| Metrics | StatsD / Prometheus exporter (TBD) |
| Logs | stdout → external log collector |

## Jednostki uruchomieniowe

### superset-beat

**Typ:** Deployment (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### superset-postgresql

**Typ:** StatefulSet (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### superset-redis

**Typ:** StatefulSet (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### superset-web

**Typ:** Deployment (2 replicas)

*TODO: Dodaj szczegóły wdrożenia*

### superset-worker

**Typ:** Deployment (2 replicas)

*TODO: Dodaj szczegóły wdrożenia*
