<!-- Included in: levels/L4-deployment-jupyterhub.md (deployment boundary, via extras/) -->

## Przegląd

JupyterHub działa jako Deployment **Hub** (zarządzanie użytkownikami, orkiestracja spawnerów) oraz Deployment **Proxy** (routing HTTP). **Pody notebooków użytkowników** są tworzone dynamicznie dla każdego użytkownika przez KubeSpawner — każdy użytkownik otrzymuje izolowany pod z preinstalowanymi jądrami (Python 3, PySpark, Dremio SQL). Wewnętrzna baza danych Hub Database oraz Image Puller to infrastruktura ukryta na poziomie L2, ale wdrożona tutaj na poziomie L4.

## Kluczowe uwagi operacyjne

- Pody notebooków użytkowników są efemeryczne — tworzone przy logowaniu, usuwane przy wylogowaniu/przekroczeniu limitu czasu
- KubeSpawner zarządza limitami zasobów per użytkownik i wyborem profili
- Uwierzytelnianie przez Keycloak OAuthenticator (planowane)
- Jądra łączą się z Dremio (Flight SQL), Spark (Spark Connect) i MinIO (boto3/s3fs)

*TODO: Dodać tabele obiektów Kubernetes, specyfikacje jąder, szczegóły sieci i bezpieczeństwa*
