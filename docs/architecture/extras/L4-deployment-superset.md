<!-- Included in: levels/L4-deployment-superset.md (deployment boundary, via extras/) -->

## Przegląd

Superset działa jako zestaw Deploymentów i StatefulSetów. Deployment **Web** obsługuje aplikację Flask (dashboardy, SQL Lab, REST API). **Celery Workers** obsługują wykonywanie zapytań w tle, generowanie miniatur i zaplanowane raporty. **Celery Beat** zarządza zadaniami okresowymi. Wewnętrzne **Redis** (broker Celery) i **PostgreSQL** (baza metadanych) to infrastruktura ukryta na poziomie L2, ale wdrożona tutaj na poziomie L4.

## Kluczowe uwagi operacyjne

- Redis i PostgreSQL są wewnętrzne dla Superset — nie są współdzielone z innymi kontenerami
- Uwierzytelnianie przez Keycloak OIDC (planowane)
- Odpytuje Dremio przez Arrow Flight SQL

*TODO: Dodać tabele obiektów Kubernetes, szczegóły sieci i bezpieczeństwa*
