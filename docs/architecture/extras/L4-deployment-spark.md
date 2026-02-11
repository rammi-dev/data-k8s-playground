<!-- Included in: levels/L4-deployment-spark.md (deployment boundary, via extras/) -->

## Przegląd

Spark wykorzystuje model zarządzany przez operatora. **Spark Operator** monitoruje CRD `SparkApplication` i `ScheduledSparkApplication`. Pody **Driver** i **Executor** są tworzone dynamicznie dla każdego zadania — bez trwałych StatefulSetów. Zadania są przesyłane przez Airflow (przez K8s API) lub interaktywnie z JupyterHub (przez Spark Connect).

## Kluczowe uwagi operacyjne

- Brak trwałych podów — wszystkie pody driver/executor są efemeryczne dla każdego zadania
- Dostęp do Open Catalog (Polaris) Dremio w celu uzyskania metadanych Iceberg przez REST API + OAuth2
- Odczyt/zapis danych Iceberg Parquet na MinIO przez s3a://
- History Server (opcjonalny) udostępnia Web UI z logami ukończonych zadań

*TODO: Dodać tabele obiektów Kubernetes, szczegóły CRD, sieci i bezpieczeństwa*
