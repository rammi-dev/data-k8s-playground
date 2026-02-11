<!-- Included in: no L3 view (black box container); available in JSON export only -->

# MongoDB

Magazyn metadanych katalogu Dremio. Percona Server for MongoDB z cyklem życia zarządzanym przez operatora.

## Przeznaczenie

Przechowuje metadane katalogu, dane użytkowników i profile zapytań dla Dremio. Promowany do osobnego kontenera L2, ponieważ posiada własnego operatora, strategię backupu (PBM) oraz niezależną domenę awarii.

## Kluczowe fakty

- **Technologia**: Percona Server for MongoDB 8.0
- **Operator**: Percona MongoDB Operator v1.21.1
- **Replica set**: 3 członków (`rs0`)
- **Backup**: codzienne backupy fizyczne PBM + ciągły PITR oplog do S3
- **Konsument**: wyłącznie Dremio (nie jest współdzielony między kontenerami)

## L3 — Czarna skrzynka

MongoDB nie posiada widoku komponentów L3. Służy jednemu, dobrze zdefiniowanemu celowi — przechowywaniu danych. Rozbijanie go na „WiredTiger" i „Replikację" nie wnosi żadnej wartości architektonicznej.

Zobacz [L4 MongoDB Deployment](../levels/L4-deployment-mongodb.md), aby uzyskać pełne szczegóły operacyjne.
