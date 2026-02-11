<!-- Included in: levels/L3-components-airflow.md (container, via !docs in workspace.dsl) -->

# Apache Airflow

Silnik orkiestracji przepływów pracy. Planowanie DAG, monitorowanie potoków, wykonywanie zadań.

## Przeznaczenie

Planuje i monitoruje potoki ETL dla inżynierów danych. Przesyła kroki SQL do Dremio oraz zadania SparkApplication. Wykorzystuje KubernetesExecutor do izolacji podów na poziomie zadań.

## Komponenty L3

| Komponent | Odpowiedzialność |
|-----------|-----------------|
| Web UI | Wizualizacja DAG, przeglądarka logów zadań, zarządzanie wyzwalaczami, konfiguracja połączeń |
| Scheduler | Parsowanie DAG, wyzwalanie zadań, rozwiązywanie zależności, monitorowanie heartbeat |
| Triggerer | Asynchroniczne wyzwalacze sterowane zdarzeniami (operatory odraczalne), odpytywanie sensorów |
| Task Executor (KubernetesExecutor) | Wykonywanie podów per zadanie, automatyczne czyszczenie, izolacja zasobów |

## Infrastruktura wewnętrzna (tylko L4)

PostgreSQL (baza metadanych) i Redis (broker Celery) są wewnętrzne dla Apache Airflow — nie są widoczne na poziomie L2.

## Kluczowe relacje

- **Dremio** — wykonuje kroki SQL potoków przez JDBC/Flight SQL
- **Spark** — przesyła obiekty SparkApplication CR przez K8s API
- **MinIO** — artefakty potoków, zdalne logowanie
- **Keycloak** — uwierzytelnianie użytkowników przez OIDC
