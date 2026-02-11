<!-- Wygenerowano automatycznie z workspace.dsl — NIE EDYTUJ RĘCZNIE -->
<!-- Regeneracja: ./scripts/generate-diagrams.sh -->

# L3 - Komponenty: JupyterHub

> Wewnętrzne moduły logiczne JupyterHub: Hub Server, Proxy, Notebook Spawner i User Sessions. Baza danych huba i image puller to infrastruktura wewnętrzna (tylko L4).

<!-- Included in: levels/L3-components-jupyterhub.md (container, via !docs in workspace.dsl) -->

# JupyterHub

Wieloużytkownikowy serwer notebooków. Interaktywna eksploracja danych z jądrami PySpark i Dremio SQL.

## Przeznaczenie

Zapewnia analitykom danych interaktywne środowiska notebookowe. Każdy użytkownik otrzymuje izolowany pod z preinstalowanymi jądrami dla Python, PySpark i Dremio SQL.

## Komponenty L3

| Komponent | Odpowiedzialność |
|-----------|-----------------|
| Hub Server | Centralne zarządzanie użytkownikami, orkiestracja spawnerów, API administratora. Delegacja uwierzytelniania do Keycloak. |
| Proxy | Routing HTTP do huba i poszczególnych serwerów notebooków użytkowników (configurable-http-proxy) |
| Notebook Spawner (KubeSpawner) | Tworzenie podów notebookowych per użytkownik ze skonfigurowanymi limitami zasobów i specyfikacjami jąder |
| User Sessions | Serwer Jupyter per użytkownik: wykonywanie jąder, edycja plików, dostęp do terminala |

## Infrastruktura wewnętrzna (tylko L4)

Hub Database i Image Puller są wewnętrzne dla JupyterHub — nie są widoczne na poziomie L2.

## Kluczowe relacje

- **Dremio** — zapytania Flight SQL z notebooków
- **Spark** — jądro PySpark przez Spark Connect
- **MinIO** — bezpośredni dostęp do danych przez boto3/s3fs
- **Keycloak** — uwierzytelnianie użytkowników przez OAuthenticator

## Diagram architektury

![L3 - Komponenty: JupyterHub](svg/structurizr-L3_Components_JupyterHub.svg)

<details>
<summary>Źródło PlantUML</summary>

```plantuml
@startuml
title <size:18>L3 - Komponenty: JupyterHub</size>

set separator none
top to bottom direction
skinparam ranksep 60
skinparam nodesep 30
hide stereotype

<style>
  root {
    BackgroundColor: #ffffff;
    FontColor: #444444;
  }
  // Element,Component
  .Element-RWxlbWVudCxDb21wb25lbnQ= {
    BackgroundColor: #a5d8ff;
    LineColor: #7397b2;
    LineStyle: 0;
    LineThickness: 2;
    FontColor: #000000;
    FontSize: 16;
    HorizontalAlignment: center;
    Shadowing: 0;
    MaximumWidth: 700;
  }
  // Element,Container
  .Element-RWxlbWVudCxDb250YWluZXI= {
    BackgroundColor: #4dabf7;
    LineColor: #3577ac;
    LineStyle: 0;
    LineThickness: 2;
    FontColor: #ffffff;
    FontSize: 16;
    HorizontalAlignment: center;
    Shadowing: 0;
    MaximumWidth: 700;
  }
  // Element,Software System,External
  .Element-RWxlbWVudCxTb2Z0d2FyZSBTeXN0ZW0sRXh0ZXJuYWw= {
    BackgroundColor: #868e96;
    LineColor: #5d6369;
    LineStyle: 0;
    LineThickness: 2;
    FontColor: #ffffff;
    FontSize: 16;
    HorizontalAlignment: center;
    Shadowing: 0;
    MaximumWidth: 700;
  }
  // Relationship
  .Relationship-UmVsYXRpb25zaGlw {
    LineThickness: 2;
    LineStyle: 10-10;
    LineColor: #444444;
    FontColor: #444444;
    FontSize: 16;
  }
  // Data Lakehouse Platform
  .Boundary-RGF0YSBMYWtlaG91c2UgUGxhdGZvcm0= {
    BackgroundColor: #ffffff;
    LineColor: #114f87;
    LineStyle: 0;
    LineThickness: 2;
    FontColor: #ffffff;
    FontSize: 16;
    HorizontalAlignment: center;
    Shadowing: 0;
  }
  // JupyterHub
  .Boundary-SnVweXRlckh1Yg== {
    BackgroundColor: #ffffff;
    LineColor: #3577ac;
    LineStyle: 0;
    LineThickness: 2;
    FontColor: #ffffff;
    FontSize: 16;
    HorizontalAlignment: center;
    Shadowing: 0;
  }
</style>

rectangle "==MinIO\n<size:12>[Software System]</size>\n\nMagazyn obiektowy kompatybilny z S3 dla tabel Iceberg, danych rozproszonych i kopii zapasowych" <<Element-RWxlbWVudCxTb2Z0d2FyZSBTeXN0ZW0sRXh0ZXJuYWw=>> as MinIO
rectangle "==Keycloak (planned)\n<size:12>[Software System]</size>\n\nZewnętrzny współdzielony SSO / broker tożsamości (dostawca OIDC)" <<Element-RWxlbWVudCxTb2Z0d2FyZSBTeXN0ZW0sRXh0ZXJuYWw=>> as Keycloakplanned

rectangle "Data Lakehouse Platform\n<size:12>[Software System]</size>" <<Boundary-RGF0YSBMYWtlaG91c2UgUGxhdGZvcm0=>> {
  rectangle "JupyterHub\n<size:12>[Container: JupyterHub (placeholder)]</size>" <<Boundary-SnVweXRlckh1Yg==>> {
    rectangle "==Hub Server\n<size:12>[Component]</size>\n\nCentralne zarządzanie użytkownikami, orkiestracja spawnerów, API administratora. Delegacja uwierzytelniania do Keycloak." <<Element-RWxlbWVudCxDb21wb25lbnQ=>> as DataLakehousePlatform.JupyterHub.HubServer
    rectangle "==Proxy\n<size:12>[Component]</size>\n\nRouting HTTP do huba i poszczególnych serwerów notebooków użytkowników. configurable-http-proxy." <<Element-RWxlbWVudCxDb21wb25lbnQ=>> as DataLakehousePlatform.JupyterHub.Proxy
    rectangle "==Notebook Spawner (KubeSpawner)\n<size:12>[Component]</size>\n\nTworzy pody notebookowe per użytkownik ze skonfigurowanymi limitami zasobów. Zarządza specyfikacjami jąder i wyborem profili." <<Element-RWxlbWVudCxDb21wb25lbnQ=>> as DataLakehousePlatform.JupyterHub.NotebookSpawnerKubeSpawner
    rectangle "==User Sessions\n<size:12>[Component]</size>\n\nSerwer Jupyter per użytkownik: wykonywanie jąder, edycja plików, dostęp do terminala. Preinstalowane biblioteki per specyfikacja jądra." <<Element-RWxlbWVudCxDb21wb25lbnQ=>> as DataLakehousePlatform.JupyterHub.UserSessions
  }

  rectangle "==Dremio\n<size:12>[Container: Dremio EE 26.1]</size>\n\nSilnik zapytań SQL i platforma data lakehouse. Federowane zapytania do źródeł S3, JDBC. Zarządza tabelami Iceberg przez Open Catalog (Polaris). Udostępnia REST API, ODBC/JDBC, Arrow Flight SQL." <<Element-RWxlbWVudCxDb250YWluZXI=>> as DataLakehousePlatform.Dremio
  rectangle "==Apache Spark\n<size:12>[Container: Spark (placeholder)]</size>\n\nRozproszony silnik obliczeń wsadowych. ETL, transformacja danych, trenowanie ML. Odczytuje/zapisuje tabele Iceberg na MinIO." <<Element-RWxlbWVudCxDb250YWluZXI=>> as DataLakehousePlatform.ApacheSpark
}

DataLakehousePlatform.JupyterHub.UserSessions --> DataLakehousePlatform.Dremio <<Relationship-UmVsYXRpb25zaGlw>> : "Zapytania Flight SQL\n<size:12>[Arrow Flight SQL]</size>"
DataLakehousePlatform.JupyterHub.UserSessions --> DataLakehousePlatform.ApacheSpark <<Relationship-UmVsYXRpb25zaGlw>> : "Jądro PySpark\n<size:12>[Spark Connect]</size>"
DataLakehousePlatform.JupyterHub.UserSessions --> MinIO <<Relationship-UmVsYXRpb25zaGlw>> : "Bezpośredni dostęp do danych\n<size:12>[S3 API (boto3/s3fs)]</size>"
DataLakehousePlatform.JupyterHub.HubServer --> Keycloakplanned <<Relationship-UmVsYXRpb25zaGlw>> : "Uwierzytelnianie użytkowników\n<size:12>[OAuthenticator]</size>"
DataLakehousePlatform.JupyterHub.Proxy --> DataLakehousePlatform.JupyterHub.HubServer <<Relationship-UmVsYXRpb25zaGlw>> : "Routing do huba\n<size:12>[HTTP]</size>"
DataLakehousePlatform.JupyterHub.Proxy --> DataLakehousePlatform.JupyterHub.UserSessions <<Relationship-UmVsYXRpb25zaGlw>> : "Routing do notebooków\n<size:12>[HTTP]</size>"
DataLakehousePlatform.ApacheSpark --> DataLakehousePlatform.Dremio <<Relationship-UmVsYXRpb25zaGlw>> : "Dostęp do katalogu Iceberg (Polaris) przez OAuth2\n<size:12>[Iceberg REST API (:8181) + OAuth2 (:9047)]</size>"
DataLakehousePlatform.Dremio --> MinIO <<Relationship-UmVsYXRpb25zaGlw>> : "Przechowuje dane rozproszone, tabele Iceberg, refleksje, kopie zapasowe\n<size:12>[S3 API (STS planned)]</size>"
DataLakehousePlatform.ApacheSpark --> MinIO <<Relationship-UmVsYXRpb25zaGlw>> : "Odczytuje/zapisuje dane Iceberg Parquet\n<size:12>[S3 API (s3a://, STS planned)]</size>"

@enduml
```

</details>

## Systemy

### Keycloak (planned)

Zewnętrzny współdzielony SSO / broker tożsamości (dostawca OIDC)

| Właściwość | Wartość |
|------------|--------|
| Direct consumers | Dremio, Airflow, JupyterHub, Superset |
| Protocol | OIDC |
| Location | External / shared |

### MinIO

Magazyn obiektowy kompatybilny z S3 dla tabel Iceberg, danych rozproszonych i kopii zapasowych

| Właściwość | Wartość |
|------------|--------|
| STS (planned) | MinIO Security Token Service — temporary credentials via OIDC for Dremio, Spark, JupyterHub |
| Protocol | S3 API |
| Buckets | dremio, dremio-catalog |
| Location | External to OCP |

## Kontenery

### Apache Spark

**Technologia:** Spark (placeholder)

Rozproszony silnik obliczeń wsadowych. ETL, transformacja danych, trenowanie ML. Odczytuje/zapisuje tabele Iceberg na MinIO.

| Właściwość | Wartość |
|------------|--------|
| Status | Placeholder / TODO |
| Namespace | dlh-prd |

### Dremio

**Technologia:** Dremio EE 26.1

Silnik zapytań SQL i platforma data lakehouse. Federowane zapytania do źródeł S3, JDBC. Zarządza tabelami Iceberg przez Open Catalog (Polaris). Udostępnia REST API, ODBC/JDBC, Arrow Flight SQL.

| Właściwość | Wartość |
|------------|--------|
| Status | Deployed |
| Ports | Web UI :9047, ODBC/JDBC :31010, Arrow Flight :32010 |
| Namespace | dlh-prd |

## Komponenty

### Hub Server

Centralne zarządzanie użytkownikami, orkiestracja spawnerów, API administratora. Delegacja uwierzytelniania do Keycloak.

### Notebook Spawner (KubeSpawner)

Tworzy pody notebookowe per użytkownik ze skonfigurowanymi limitami zasobów. Zarządza specyfikacjami jąder i wyborem profili.

### Proxy

Routing HTTP do huba i poszczególnych serwerów notebooków użytkowników. configurable-http-proxy.

| Właściwość | Wartość |
|------------|--------|
| Ports | :80/443 (public), :8001 (API) |

### User Sessions

Serwer Jupyter per użytkownik: wykonywanie jąder, edycja plików, dostęp do terminala. Preinstalowane biblioteki per specyfikacja jądra.

| Właściwość | Wartość |
|------------|--------|
| Kernel: Dremio SQL | pyarrow, flight-sql-dbapi → Dremio Flight :32010 |
| Kernel: Python 3 | numpy, pandas, matplotlib, scikit-learn |
| Kernel: PySpark | pyspark, delta-spark, pyiceberg → Spark Connect |

## Relacje

| Od | Do | Opis | Technologia |
|----|-----|------|-------------|
| Apache Spark | Dremio | Dostęp do katalogu Iceberg (Polaris) przez OAuth2 | Iceberg REST API (:8181) + OAuth2 (:9047) |
| Apache Spark | MinIO | Odczytuje/zapisuje dane Iceberg Parquet | S3 API (s3a://, STS planned) |
| Dremio | MinIO | Przechowuje dane rozproszone, tabele Iceberg, refleksje, kopie zapasowe | S3 API (STS planned) |
| Hub Server | Keycloak (planned) | Uwierzytelnianie użytkowników | OAuthenticator |
| Proxy | User Sessions | Routing do notebooków | HTTP |
| Proxy | Hub Server | Routing do huba | HTTP |
| User Sessions | Dremio | Zapytania Flight SQL | Arrow Flight SQL |
| User Sessions | Apache Spark | Jądro PySpark | Spark Connect |
| User Sessions | MinIO | Bezpośredni dostęp do danych | S3 API (boto3/s3fs) |
