<!-- Included in: levels/L3-components-dremio.md (container, via !docs in workspace.dsl) -->

# Dremio

Silnik zapytań SQL i platforma Data Lakehouse. Federacyjne zapytania do źródeł S3 i JDBC. Zarządza tabelami Iceberg poprzez Open Catalog (Polaris).

## Interfejsy

| Port | Protokół | Przeznaczenie |
|------|----------|---------------|
| 9047 | HTTPS | Interfejs webowy, REST API, endpoint tokenów OAuth2 |
| 31010 | TCP | Połączenia klientów ODBC/JDBC |
| 32010 | TCP | Arrow Flight SQL (wysokowydajny kolumnowy dostęp) |

## Komponenty L3

| Komponent | Odpowiedzialność |
|-----------|-----------------|
| Query Coordinator | Parsowanie SQL, planowanie, optymalizacja. Endpointy klientów. Wymiana tokenów OAuth2. |
| Execution Engine | Rozproszone wykonywanie zapytań, przetwarzanie kolumnowe, pamięć podręczna C3, zrzut na dysk. |
| Engine Operator | Skalowanie executorów sterowane przez CRD (pule silników Micro/Small/Medium/Large). |
| Catalog Server (Polaris) | Wewnętrzne REST API Iceberg. Zarządza schematami, partycjami, snapshotami. |
| Catalog Server External | Zewnętrzne REST API Iceberg dla Apache Spark. Walidacja tokenów OAuth2. |
| Catalog Services | Wewnętrzne zarządzanie katalogiem, zarządzanie źródłami, odkrywanie zbiorów danych. |

## Kluczowe relacje

- **MongoDB** — przechowuje metadane katalogu, dane użytkowników, profile zapytań
- **MinIO** — tabele Iceberg (`s3://dremio-catalog`), dane rozproszone, reflections, backupy
- **LDAP/AD** — federacja użytkowników (bezpośrednio, nie przez Keycloak)
- **Keycloak** — planowany do OIDC SSO
