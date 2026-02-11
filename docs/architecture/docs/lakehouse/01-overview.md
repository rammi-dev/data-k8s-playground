<!-- Included in: levels/L1-system-context.md (softwareSystem, via !docs in workspace.dsl) -->

# Platforma Data Lakehouse

Zintegrowana platforma analityczna wdrożona na OpenShift, zbudowana wokół otwartych formatów danych (Apache Iceberg na MinIO).

## Możliwości

- **Zunifikowany dostęp SQL** — Dremio zapewnia federacyjne zapytania do źródeł S3 i JDBC
- **Rozproszone obliczenia wsadowe** — Apache Spark do ETL, transformacji i obciążeń ML
- **Orkiestracja przepływów pracy** — Apache Airflow planuje i monitoruje potoki danych
- **Interaktywne notebooki** — JupyterHub z jądrami PySpark i Dremio SQL
- **Dashboardy BI** — Apache Superset i Power BI (zewnętrzny) do raportowania

## Kluczowe decyzje projektowe

- **Pojedyncza przestrzeń nazw** (`dlh-prd`) dla wszystkich komponentów platformy
- **MongoDB promowane do kontenera L2** — niezależny cykl życia, operator, strategia backupu
- **Monitoring jest zewnętrzny** — każda granica kontenera dokumentuje własne endpointy metryk/logów
- **Uwierzytelnianie** — Keycloak OIDC (planowane); Dremio aktualnie korzysta bezpośrednio z LDAP/AD
- **Przechowywanie danych** — tabele Apache Iceberg na MinIO (magazyn obiektowy kompatybilny z S3)
