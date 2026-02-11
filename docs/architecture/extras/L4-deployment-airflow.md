<!-- Included in: levels/L4-deployment-airflow.md (deployment boundary, via extras/) -->

## Przegląd

Airflow działa jako kilka Deploymentów i StatefulSetów. **Webserver** udostępnia interfejs DAG UI oraz API. **Scheduler** parsuje DAGi, wyzwala zadania i zarządza zależnościami. **Triggerer** obsługuje asynchroniczne operatory z odroczeniem (deferrable). Zadania są wykonywane przez **KubernetesExecutor** — każde zadanie działa we własnym efemerycznym podzie. Wewnętrzne **PostgreSQL** (metadane) i **Redis** (broker Celery) to infrastruktura ukryta na poziomie L2, ale wdrożona tutaj na poziomie L4.

## Kluczowe uwagi operacyjne

- KubernetesExecutor: każde zadanie otrzymuje własny pod z izolacją zasobów
- PostgreSQL i Redis są wewnętrzne dla Airflow — nie są współdzielone z innymi kontenerami
- Zdalne logowanie do S3 (do ustalenia)
- Uwierzytelnianie przez Keycloak OIDC (planowane)

*TODO: Dodać tabele obiektów Kubernetes, mechanizm synchronizacji DAG, szczegóły sieci i bezpieczeństwa*
