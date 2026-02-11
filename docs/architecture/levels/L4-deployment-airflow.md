<!-- Wygenerowano automatycznie z workspace.dsl + extras/ — NIE EDYTUJ RĘCZNIE -->
<!-- Właściwości DSL są generowane automatycznie; zawartość extras/ jest utrzymywana ręcznie -->
<!-- Regeneracja: ./scripts/generate-diagrams.sh -->

# L4 - Wdrożenie: Airflow

> Granica kontenera dla Airflow w ramach dlh-prd namespace.

<!-- Included in: levels/L4-deployment-airflow.md (deployment boundary, via extras/) -->

## Przegląd

Airflow działa jako kilka Deploymentów i StatefulSetów. **Webserver** udostępnia interfejs DAG UI oraz API. **Scheduler** parsuje DAGi, wyzwala zadania i zarządza zależnościami. **Triggerer** obsługuje asynchroniczne operatory z odroczeniem (deferrable). Zadania są wykonywane przez **KubernetesExecutor** — każde zadanie działa we własnym efemerycznym podzie. Wewnętrzne **PostgreSQL** (metadane) i **Redis** (broker Celery) to infrastruktura ukryta na poziomie L2, ale wdrożona tutaj na poziomie L4.

## Kluczowe uwagi operacyjne

- KubernetesExecutor: każde zadanie otrzymuje własny pod z izolacją zasobów
- PostgreSQL i Redis są wewnętrzne dla Airflow — nie są współdzielone z innymi kontenerami
- Zdalne logowanie do S3 (do ustalenia)
- Uwierzytelnianie przez Keycloak OIDC (planowane)

*TODO: Dodać tabele obiektów Kubernetes, mechanizm synchronizacji DAG, szczegóły sieci i bezpieczeństwa*

## Monitorowanie

| Punkt końcowy | Wartość |
|---------------|--------|
| Metrics | StatsD → Prometheus exporter (TBD) |
| Logs | stdout → external log collector, remote logging to S3 (TBD) |

## Jednostki uruchomieniowe

### airflow-postgresql

**Typ:** StatefulSet (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### airflow-redis

**Typ:** StatefulSet (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### airflow-scheduler

**Typ:** Deployment (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### airflow-triggerer

**Typ:** Deployment (1 replica)

*TODO: Dodaj szczegóły wdrożenia*

### airflow-webserver

**Typ:** Deployment (1 replica)

*TODO: Dodaj szczegóły wdrożenia*
