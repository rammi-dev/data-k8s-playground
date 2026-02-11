<!-- Included in: levels/L3-components-superset.md (container, via !docs in workspace.dsl) -->

# Apache Superset

Platforma BI i wizualizacji danych. Dashboardy, SQL Lab, kreator wykresów, planowanie alertów/raportów.

## Przeznaczenie

Zapewnia samoobsługową analitykę i dashboardy dla analityków danych i programistów BI. Odpytuje dane z Dremio za pośrednictwem Arrow Flight SQL.

## Komponenty L3

| Komponent | Odpowiedzialność |
|-----------|-----------------|
| Web Application | Serwer aplikacji Flask, renderowanie dashboardów, SQL Lab, REST API |
| Celery Workers | Wykonywanie zapytań w tle, generowanie miniatur, alerty, zaplanowane raporty |
| Celery Beat | Okresowe planowanie zadań: rozgrzewanie pamięci podręcznej, dostarczanie raportów, czyszczenie |

## Infrastruktura wewnętrzna (tylko L4)

Redis (broker Celery) i PostgreSQL (baza metadanych) są wewnętrzne dla Superset — nie są widoczne na poziomie L2.

## Kluczowe relacje

- **Dremio** — odpytuje dane za pośrednictwem Arrow Flight SQL
- **Keycloak** — uwierzytelnianie użytkowników przez OIDC
