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
