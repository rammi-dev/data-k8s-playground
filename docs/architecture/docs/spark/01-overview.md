<!-- Included in: levels/L3-components-spark.md (container, via !docs in workspace.dsl) -->

# Apache Spark

Rozproszony silnik obliczeń wsadowych. ETL, transformacja danych, trenowanie modeli ML.

## Przeznaczenie

Odczytuje i zapisuje tabele Iceberg na MinIO. Uzyskuje dostęp do Open Catalog (Polaris) Dremio w celu pobrania metadanych Iceberg. Zadania są przesyłane przez Apache Airflow lub interaktywnie z notebooków JupyterHub.

## Komponenty L3

| Komponent | Odpowiedzialność |
|-----------|-----------------|
| Spark Operator | Obserwuje obiekty SparkApplication CR, zarządza cyklem życia podów driver/executor |
| Driver | Orkiestracja zadań: planowanie DAG, dystrybucja zadań, koordynacja shuffle |
| Executors | Workery przetwarzania danych: odczyty kolumnowe, transformacje, agregacja. Dynamiczne skalowanie. |
| History Server | Interfejs webowy dla logów ukończonych zadań. Odczytuje logi zdarzeń z S3. (Opcjonalny) |

## Kluczowe relacje

- **MinIO** — odczyt/zapis danych Iceberg Parquet przez S3 API (s3a://)
- **Dremio** — dostęp do katalogu Iceberg (Polaris) przez REST API + OAuth2
- **Airflow** — przesyła obiekty SparkApplication CR przez K8s API
- **JupyterHub** — jądro PySpark przez Spark Connect
