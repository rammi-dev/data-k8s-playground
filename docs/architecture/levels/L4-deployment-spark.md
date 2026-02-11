<!-- Wygenerowano automatycznie z workspace.dsl + extras/ — NIE EDYTUJ RĘCZNIE -->
<!-- Właściwości DSL są generowane automatycznie; zawartość extras/ jest utrzymywana ręcznie -->
<!-- Regeneracja: ./scripts/generate-diagrams.sh -->

# L4 - Wdrożenie: Spark

> Granica kontenera dla Spark w ramach dlh-prd namespace.

<!-- Included in: levels/L4-deployment-spark.md (deployment boundary, via extras/) -->

## Przegląd

Spark wykorzystuje model zarządzany przez operatora. **Spark Operator** monitoruje CRD `SparkApplication` i `ScheduledSparkApplication`. Pody **Driver** i **Executor** są tworzone dynamicznie dla każdego zadania — bez trwałych StatefulSetów. Zadania są przesyłane przez Airflow (przez K8s API) lub interaktywnie z JupyterHub (przez Spark Connect).

## Kluczowe uwagi operacyjne

- Brak trwałych podów — wszystkie pody driver/executor są efemeryczne dla każdego zadania
- Dostęp do Open Catalog (Polaris) Dremio w celu uzyskania metadanych Iceberg przez REST API + OAuth2
- Odczyt/zapis danych Iceberg Parquet na MinIO przez s3a://
- History Server (opcjonalny) udostępnia Web UI z logami ukończonych zadań

*TODO: Dodać tabele obiektów Kubernetes, szczegóły CRD, sieci i bezpieczeństwa*

## Monitorowanie

| Punkt końcowy | Wartość |
|---------------|--------|
| Metrics | Spark UI :4040 (driver), Prometheus servlet (if enabled) |
| Logs | stdout → external log collector |

## Jednostki uruchomieniowe

### spark-driver

**Typ:** Pod (dynamic, per job)

*TODO: Dodaj szczegóły wdrożenia*

### spark-executor

**Typ:** Pod (dynamic, per job)

*TODO: Dodaj szczegóły wdrożenia*

### spark-operator

**Typ:** Deployment (1 replica)

*TODO: Dodaj szczegóły wdrożenia*
