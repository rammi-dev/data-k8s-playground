workspace "DataLakehouse" "Architektura C4 — Platforma Data Lakehouse na OpenShift. Platforma analityczna zbudowana wokół otwartych formatów danych (Apache Iceberg), zapewniająca zunifikowany dostęp SQL, obliczenia wsadowe, orkiestrację przepływów pracy, interaktywne notebooki i dashboardy BI." {

    !identifiers hierarchical

    model {
        # ===========================
        # L1 — Aktorzy (osoby)
        # ===========================

        dataEngineer = person "Data Engineer" "Projektuje i uruchamia potoki ETL, zarządza zbiorami danych i jakością danych"
        dataAnalyst = person "Data Analyst / BI User" "Odpytuje dane przez Dremio SQL, korzysta z notebooków Jupyter, tworzy dashboardy Superset, generuje raporty"
        dataScientist = person "Data Scientist" "Prowadzi eksperymenty w notebookach JupyterHub, wykorzystuje PySpark do zadań ML"
        biDeveloper = person "BI Developer" "Tworzy raporty i dashboardy korporacyjne w Power BI/Superset"
        platformAdmin = person "Platform Admin" "Zarządza klastrem OCP, wdraża komponenty, monitoruje stan systemu"

        # ===========================
        # L1 — Systemy zewnętrzne
        # ===========================

        minio = softwareSystem "MinIO" "Magazyn obiektowy kompatybilny z S3 dla tabel Iceberg, danych rozproszonych i kopii zapasowych" "External" {
            properties {
                "Location" "External to OCP"
                "Protocol" "S3 API"
                "Buckets" "dremio, dremio-catalog"
                "STS (planned)" "MinIO Security Token Service — temporary credentials via OIDC for Dremio, Spark, JupyterHub"
            }
        }
        minioLegacy = softwareSystem "MinIO (Legacy)" "Istniejący starszy magazyn obiektowy z danymi historycznymi. Dane są aktualnie kopiowane do MinIO przez zewnętrzną instancję Airflow." "External" {
            properties {
                "Location" "External to OCP"
                "Protocol" "S3 API"
                "Access" "Data copied to MinIO by External Airflow"
            }
        }
        kafkaLegacy = softwareSystem "Kafka (Legacy)" "Zewnętrzny streaming zdarzeń; publikuje powiadomienia o plikach z MinIO Legacy. OBECNIE NIEDOSTĘPNY z platformy Lakehouse — wymaga wdrożenia rozwiązania sieciowego/integracyjnego. Zależy od ostatecznej decyzji projektowej." "External" {
            properties {
                "Location" "External to OCP"
                "Protocol" "Kafka Protocol"
                "Purpose" "File notification events from MinIO Legacy"
                "Status" "NOT ACCESSIBLE — depending on final design decision"
                "Workaround" "External Airflow currently copies files from Legacy MinIO to MinIO"
            }
        }
        keycloak = softwareSystem "Keycloak (planned)" "Zewnętrzny współdzielony SSO / broker tożsamości (dostawca OIDC)" "External" {
            properties {
                "Location" "External / shared"
                "Protocol" "OIDC"
                "Direct consumers" "Dremio, Airflow, JupyterHub, Superset"
            }
        }
        ldap = softwareSystem "LDAP / Active Directory" "Katalog korporacyjny; Keycloak federuje do niego, niektóre komponenty łączą się bezpośrednio" "External" {
            properties {
                "Location" "External / corporate"
                "Ports" "389 (LDAP), 636 (LDAPS)"
                "Direct consumers" "Dremio, Keycloak"
            }
        }
        powerBI = softwareSystem "Power BI" "Korporacyjna platforma BI Microsoft (zewnętrzna, desktopy korporacyjne)" "External" {
            properties {
                "Location" "Desktop version"
                "Protocol" "ODBC/JDBC"
                "Connects to" "Dremio coordinator :31010"
            }
        }
        externalAirflow = softwareSystem "External Airflow (MSPD)" "Zewnętrzna instancja Airflow, która aktualnie kopiuje (planowane) pliki z Legacy MinIO do MinIO. Kafka Legacy wykorzystywana do synchronizacji plików z Airflow Legacy." "External" {
            properties {
                "Location" "External to OCP"
                "Purpose" "Interim data transfer from Legacy MinIO to MinIO"
                "Status" "Final mechanism not designed yet"
            }
        }
        externalDataSources = softwareSystem "External Data Sources" "Pliki z magazynu kompatybilnego z S3 (CSV/Parquet)" "External"
        gitops = softwareSystem "GitOps / CI-CD (planned)" "Potoki ArgoCD / Tekton do wdrożeń na OCP" "External"
        monitoring = softwareSystem "Monitoring Platform" "Zewnętrzny stos obserwowalności: zbieranie metryk, agregacja logów, dashboardy, alerty. Odpytuje endpointy /metrics i zbiera logi ze wszystkich kontenerów platformy." "External" {
            properties {
                "Location" "External to Data Lakehouse Platform"
                "Stack" "TBD: Prometheus + Grafana / ELK / EFK"
                "Protocol" "Prometheus scrape, log forwarding"
            }
        }

        # ===========================
        # L1/L2 — Platforma Data Lakehouse
        # ===========================

        lakehouse = softwareSystem "Data Lakehouse Platform" "Zintegrowana platforma analityczna wdrożona na OpenShift, zbudowana wokół otwartych formatów danych (Apache Iceberg na MinIO). Zapewnia zunifikowaną federację zapytań SQL (Dremio), rozproszone obliczenia wsadowe (Spark), orkiestrację przepływów pracy (Airflow), interaktywne notebooki (JupyterHub) i dashboardy BI (Superset/PowerBI). Wszystkie komponenty użytkownika uwierzytelniają się przez Keycloak OIDC (planowane); Dremio federuje użytkowników bezpośrednio z LDAP/AD (aktualnie używane do uwierzytelniania). Obserwowalność zapewniona przez zewnętrzną Platformę Monitorowania." {
            !docs docs/lakehouse

            # ---------------------------
            # L2 — Kontenery (logiczne jednostki wdrożeniowe)
            # ---------------------------

            dremio = container "Dremio" "Silnik zapytań SQL i platforma data lakehouse. Federowane zapytania do źródeł S3, JDBC. Zarządza tabelami Iceberg przez Open Catalog (Polaris). Udostępnia REST API, ODBC/JDBC, Arrow Flight SQL." "Dremio EE 26.1" {
                !docs docs/dremio
                properties {
                    "Status" "Deployed"
                    "Namespace" "dlh-prd"
                    "Ports" "Web UI :9047, ODBC/JDBC :31010, Arrow Flight :32010"
                }

                # ---------------------------
                # L3 — Komponenty Dremio
                # ---------------------------
                queryCoordinator = component "Query Coordinator" "Parsowanie SQL, planowanie i optymalizacja zapytań. Endpointy klienckie: Web UI, ODBC/JDBC, Arrow Flight SQL. Endpoint wymiany tokenów OAuth2 dla zewnętrznego dostępu do katalogu. Zarządza refleksjami i danymi akceleracji." {
                    properties {
                        "Ports" "Web UI :9047, ODBC/JDBC :31010, Arrow Flight :32010"
                        "OAuth2 token endpoint" ":9047/oauth/token (exchanges IdP JWT for Dremio access token)"
                        "Metrics" ":9010/metrics"
                        "Logs" "stdout (configurable via writeLogsToFile)"
                        "K8s workload" "StatefulSet dremio-master (1 replica)"
                        "CPU" "250m request / 2 limit"
                        "Memory" "4Gi request / 8Gi limit"
                    }
                }
                executionEngine = component "Execution Engine" "Rozproszone wykonywanie zapytań, przetwarzanie kolumnowe. Zapis na dysk (spill) dla dużych zapytań. Pamięć podręczna C3 dla lokalnego cachowania danych S3. Pule silników: Micro, Small, Medium, Large." {
                    properties {
                        "Metrics" ":9010/metrics"
                        "Logs" "stdout (configurable via writeLogsToFile)"
                        "K8s workload" "StatefulSet dremio-executor (0-N replicas, Engine Operator)"
                        "Health probe" "TCP :45678 (startup 10min, liveness 5min)"
                        "Engine: Micro" "1 pod, 4Gi memory"
                        "Engine: Small" "1 pod, 10Gi memory"
                        "Engine: Medium" "2 pods, 10Gi memory"
                        "Engine: Large" "2 pods, 12Gi memory"
                        "PVC: spill" "executor-volume 10-50Gi"
                        "PVC: C3 cache" "executor-c3 10-50Gi"
                    }
                }
                engineOperator = component "Engine Operator" "Obserwuje CRD silników, zarządza cyklem życia executorów. Skaluje pule silników w górę/w dół w zależności od obciążenia." {
                    properties {
                        "Metrics" ":8080/q/metrics"
                        "K8s workload" "Deployment (1 replica)"
                        "Note" "Engines created via Dremio UI, not Helm"
                    }
                }
                catalogServer = component "Catalog Server (Polaris)" "Wewnętrzne REST API Open Catalog / Polaris. Zarządza metadanymi tabel Iceberg (schematy, partycje, snapshoty). Przechowuje dane Iceberg w s3://dremio-catalog." {
                    properties {
                        "Port" ":9181 (internal)"
                        "Metrics" "/metrics"
                        "K8s workload" "Deployment (1 replica)"
                        "CPU" "200m request / 1 limit"
                        "Memory" "1Gi request / 2Gi limit"
                        "Storage bucket" "s3://dremio-catalog"
                        "S3 credentials" "Secret catalog-server-s3-storage-creds"
                    }
                }
                catalogServerExternal = component "Catalog Server External" "Zewnętrzne REST API Iceberg. Umożliwia klientom zewnętrznym (Spark) dostęp do katalogu Iceberg zarządzanego przez Dremio. Waliduje tokeny OAuth2 przez endpoint JWKS Koordynatora." {
                    properties {
                        "Port" ":8181 (Iceberg REST API)"
                        "Endpoint" ":8181/api/catalog"
                        "Authentication" "OAuth2 (validates tokens via Coordinator :9047/oauth/discovery/jwks.json)"
                        "K8s workload" "Deployment (1 replica)"
                        "K8s service" "dremio-client :8181 (LoadBalancer, shared with Coordinator)"
                    }
                }
                catalogServices = component "Catalog Services" "Wewnętrzny mikroserwis zarządzania katalogiem. Zarządzanie źródłami, odkrywanie zbiorów danych." {
                    properties {
                        "Metrics" "/q/metrics"
                        "K8s workload" "Deployment (1 replica)"
                        "CPU" "50m request / 500m limit"
                        "Memory" "256Mi request / 1Gi limit"
                    }
                }
            }

            mongodb = container "MongoDB" "Magazyn metadanych katalogu Dremio. Percona Server for MongoDB z cyklem życia zarządzanym przez operatora. Przechowuje metadane katalogu, dane użytkowników, profile zapytań." "Percona MongoDB 8.0" {
                !docs docs/mongodb
                properties {
                    "Status" "Deployed"
                    "Namespace" "dlh-prd"
                    "Port" ":27017/TCP"
                    "Metrics" ":9216/metrics (mongodb_exporter sidecar)"
                    "K8s workload" "StatefulSet mongodb-rs0 (3 replicas, Percona)"
                    "Operator" "Deployment mongodb-operator (1 replica)"
                    "Backup" "PBM daily full + PITR oplog to s3://dremio/catalog-backups/"
                    "CronJob" "dremio-catalog-backups (daily 00:00)"
                    "App user" "dremio (readWrite on dremio DB)"
                    "System users" "clusterAdmin, clusterMonitor, backup, userAdmin"
                    "Secrets" "dremio-mongodb-app-users, dremio-mongodb-system-users"
                }
            }

            superset = container "Apache Superset" "Platforma BI i wizualizacji danych. Dashboardy, SQL Lab, kreator wykresów, planowanie alertów/raportów. Zawiera Redis i PostgreSQL dla wewnętrznego stanu." "Superset (placeholder)" {
                !docs docs/superset
                properties {
                    "Status" "Placeholder / TODO"
                    "Namespace" "dlh-prd"
                }

                # ---------------------------
                # L3 — Komponenty Superset
                # ---------------------------
                supersetWebApp = component "Web Application" "Serwer aplikacji Flask, renderowanie dashboardów, SQL Lab, kreator wykresów. REST API dla dostępu programistycznego." {
                    properties {
                        "Port" ":8088"
                        "Logs" "stdout"
                    }
                }
                supersetCeleryWorkers = component "Celery Workers" "Wykonywanie zapytań w tle, generowanie miniatur, alerty, zaplanowane raporty." {
                    properties {
                        "Logs" "stdout"
                    }
                }
                supersetCeleryBeat = component "Celery Beat" "Okresowe planowanie zadań: rozgrzewanie pamięci podręcznej, dostarczanie raportów, czyszczenie." {
                    properties {
                        "Logs" "stdout"
                    }
                }
                # Redis, PostgreSQL i moduł inicjalizacyjny to infrastruktura wewnętrzna → tylko L4
            }

            spark = container "Apache Spark" "Rozproszony silnik obliczeń wsadowych. ETL, transformacja danych, trenowanie ML. Odczytuje/zapisuje tabele Iceberg na MinIO." "Spark (placeholder)" {
                !docs docs/spark
                properties {
                    "Status" "Placeholder / TODO"
                    "Namespace" "dlh-prd"
                }

                # ---------------------------
                # L3 — Komponenty Spark
                # ---------------------------
                sparkOperator = component "Spark Operator" "Obserwuje obiekty SparkApplication CR. Zarządza cyklem życia podów driver/executor, obsługuje ponawianie." {
                    properties {
                        "CRDs" "SparkApplication, ScheduledSparkApplication"
                    }
                }
                sparkDriver = component "Driver" "Orkiestracja zadań: planowanie DAG, dystrybucja zadań, koordynacja shuffle. Inicjalizacja SparkContext."
                sparkExecutors = component "Executors" "Workery przetwarzania danych: odczyty kolumnowe, transformacje, shuffle, agregacja. Dynamiczne skalowanie per zadanie."
                sparkHistoryServer = component "History Server" "Interfejs webowy dla logów ukończonych zadań. Odczytuje logi zdarzeń z S3. (Opcjonalny)" {
                    properties {
                        "Port" ":18080"
                    }
                }
            }

            airflow = container "Apache Airflow" "Orkiestracja przepływów pracy. Planowanie DAG, monitorowanie potoków, wykonywanie zadań. Zawiera PostgreSQL i Redis dla wewnętrznego stanu." "Airflow (placeholder)" {
                !docs docs/airflow
                properties {
                    "Status" "Placeholder / TODO"
                    "Namespace" "dlh-prd"
                }

                # ---------------------------
                # L3 — Komponenty Airflow
                # ---------------------------
                airflowWebUI = component "Web UI" "Wizualizacja DAG, przeglądarka logów zadań, zarządzanie wyzwalaczami. Konfiguracja połączeń i zmiennych." {
                    properties {
                        "Port" ":8080"
                        "Logs" "stdout"
                    }
                }
                airflowScheduler = component "Scheduler" "Parsowanie DAG, wyzwalanie zadań, rozwiązywanie zależności. Monitorowanie heartbeat, wykrywanie martwych zadań." {
                    properties {
                        "Logs" "stdout"
                    }
                }
                airflowTriggerer = component "Triggerer" "Asynchroniczne wyzwalacze sterowane zdarzeniami (operatory odraczalne). Odpytywanie sensorów bez blokowania slotów workerów." {
                    properties {
                        "Logs" "stdout"
                    }
                }
                airflowTaskExecutor = component "Task Executor (KubernetesExecutor)" "Wykonywanie podów per zadanie, automatyczne czyszczenie, izolacja zasobów. Każde zadanie działa we własnym podzie."
                # PostgreSQL, Redis, repozytorium DAG i zdalne logowanie to infrastruktura wewnętrzna → tylko L4
            }

            jupyterhub = container "JupyterHub" "Wieloużytkownikowy serwer notebooków. Interaktywna eksploracja danych z jądrami PySpark i Dremio SQL." "JupyterHub (placeholder)" {
                !docs docs/jupyterhub
                properties {
                    "Status" "Placeholder / TODO"
                    "Namespace" "dlh-prd"
                }

                # ---------------------------
                # L3 — Komponenty JupyterHub
                # ---------------------------
                hubServer = component "Hub Server" "Centralne zarządzanie użytkownikami, orkiestracja spawnerów, API administratora. Delegacja uwierzytelniania do Keycloak."
                hubProxy = component "Proxy" "Routing HTTP do huba i poszczególnych serwerów notebooków użytkowników. configurable-http-proxy." {
                    properties {
                        "Ports" ":80/443 (public), :8001 (API)"
                    }
                }
                hubSpawner = component "Notebook Spawner (KubeSpawner)" "Tworzy pody notebookowe per użytkownik ze skonfigurowanymi limitami zasobów. Zarządza specyfikacjami jąder i wyborem profili."
                hubUserSessions = component "User Sessions" "Serwer Jupyter per użytkownik: wykonywanie jąder, edycja plików, dostęp do terminala. Preinstalowane biblioteki per specyfikacja jądra." {
                    properties {
                        "Kernel: Python 3" "numpy, pandas, matplotlib, scikit-learn"
                        "Kernel: PySpark" "pyspark, delta-spark, pyiceberg → Spark Connect"
                        "Kernel: Dremio SQL" "pyarrow, flight-sql-dbapi → Dremio Flight :32010"
                    }
                }
                # Hub Database i Image Puller to infrastruktura wewnętrzna → tylko L4
            }

            # Stos monitorowania jest systemem zewnętrznym — patrz sekcja systemów zewnętrznych L1
        }

        # ===========================
        # L1 — Relacje (kontekst systemu)
        # ===========================

        dataEngineer -> lakehouse "Projektuje potoki ETL, zarządza zbiorami danych" "HTTPS"
        dataAnalyst -> lakehouse "Odpytuje dane, tworzy dashboardy" "HTTPS"
        dataScientist -> lakehouse "Uruchamia notebooki i eksperymenty" "HTTPS"
        biDeveloper -> powerBI "Tworzy raporty i dashboardy" "Desktop"
        platformAdmin -> lakehouse "Zarządza klastrem, monitoruje stan" "HTTPS"
        platformAdmin -> gitops "Zarządza wdrożeniami" "HTTPS"

        powerBI -> lakehouse "Odpytuje Dremio do raportów" "ODBC/JDBC"
        lakehouse -> minio "Przechowuje tabele Iceberg, dane rozproszone, kopie zapasowe" "S3 API"
        lakehouse -> keycloak "Uwierzytelnia użytkowników przez SSO" "OIDC"
        lakehouse -> ldap "Federuje użytkowników bezpośrednio" "LDAP/LDAPS"
        externalAirflow -> minioLegacy "Odczytuje historyczne pliki danych" "S3 API"
        externalAirflow -> minio "Kopiuje pliki do nowego magazynu" "S3 API"
        externalDataSources -> lakehouse "Dostarcza dane do zasilania" "S3 API"
        gitops -> lakehouse "Wdraża charty Helm na OCP" "K8s API"
        platformAdmin -> monitoring "Przegląda dashboardy, alerty" "HTTPS"
        monitoring -> lakehouse "Zbiera metryki i logi" "Prometheus/Log forwarding"

        # ===========================
        # L2 — Relacje (kontenery)
        # ===========================

        # Użytkownik → Kontener
        dataAnalyst -> lakehouse.dremio "Uruchamia zapytania SQL" "JDBC/ODBC/Flight SQL"
        dataAnalyst -> lakehouse.superset "Przegląda dashboardy" "HTTPS"
        dataEngineer -> lakehouse.airflow "Zarządza DAG-ami" "HTTPS"
        dataEngineer -> lakehouse.dremio "Zarządza źródłami, refleksjami" "HTTPS"
        dataScientist -> lakehouse.jupyterhub "Uruchamia notebooki" "HTTPS"
        dataScientist -> lakehouse.dremio "Zapytania z notebooków" "Flight SQL"
        powerBI -> lakehouse.dremio "Zapytania do raportów BI" "ODBC/JDBC"
        # platformAdmin -> monitoring zdefiniowane na L1

        # Kontener → Kontener
        lakehouse.dremio -> lakehouse.mongodb "Przechowuje metadane katalogu, dane użytkowników, profile zapytań" "MongoDB Protocol"
        lakehouse.superset -> lakehouse.dremio "Odpytuje dane do dashboardów" "Arrow Flight SQL"
        lakehouse.spark -> lakehouse.dremio "Dostęp do katalogu Iceberg (Polaris) przez OAuth2" "Iceberg REST API (:8181) + OAuth2 (:9047)"
        lakehouse.airflow -> lakehouse.dremio "Wykonuje kroki SQL potoków" "JDBC/Flight SQL"
        lakehouse.airflow -> lakehouse.spark "Przesyła obiekty SparkApplication CR" "K8s API"
        lakehouse.jupyterhub -> lakehouse.dremio "Zapytania z notebooków" "Arrow Flight SQL"
        lakehouse.jupyterhub -> lakehouse.spark "Uruchamia jądra PySpark" "Spark Connect"

        # Kontener → System zewnętrzny
        lakehouse.mongodb -> minio "Kopie zapasowe PBM do s3://dremio/catalog-backups/" "S3 API"
        lakehouse.dremio -> minio "Przechowuje dane rozproszone, tabele Iceberg, refleksje, kopie zapasowe" "S3 API (STS planned)"
        lakehouse.spark -> minio "Odczytuje/zapisuje dane Iceberg Parquet" "S3 API (s3a://, STS planned)"
        lakehouse.airflow -> minio "Artefakty potoków, zdalne logowanie" "S3 API"
        lakehouse.jupyterhub -> minio "Bezpośredni dostęp do danych z notebooków" "S3 API (STS planned)"
        lakehouse.superset -> keycloak "Uwierzytelnia użytkowników" "OIDC"
        lakehouse.airflow -> keycloak "Uwierzytelnia użytkowników" "OIDC"
        lakehouse.jupyterhub -> keycloak "Uwierzytelnia użytkowników" "OIDC"
        lakehouse.dremio -> ldap "Federuje użytkowników bezpośrednio" "LDAP/LDAPS"

        # Zewnętrzny Monitoring → Kontenery
        monitoring -> lakehouse.dremio "Zbiera metryki i logi" "Prometheus/Log forwarding"
        monitoring -> lakehouse.mongodb "Zbiera metryki i logi" "Prometheus/Log forwarding"
        monitoring -> lakehouse.spark "Zbiera metryki i logi" "Prometheus/Log forwarding"
        monitoring -> lakehouse.airflow "Zbiera metryki i logi" "Prometheus/Log forwarding"
        monitoring -> lakehouse.superset "Zbiera metryki i logi" "Prometheus/Log forwarding"
        monitoring -> lakehouse.jupyterhub "Zbiera metryki i logi" "Prometheus/Log forwarding"

        # ===========================
        # L3 — Relacje (komponenty Dremio)
        # ===========================

        # Komponent Dremio → MongoDB (cross-container, wyświetla MongoDB jako zewnętrzny element na diagramie L3)
        lakehouse.dremio.queryCoordinator -> lakehouse.mongodb "Odczytuje/zapisuje metadane" "MongoDB Protocol"
        lakehouse.dremio.catalogServer -> lakehouse.mongodb "Metadane Polaris" "MongoDB Protocol"
        lakehouse.dremio.catalogServices -> lakehouse.mongodb "Zarządzanie katalogiem" "MongoDB Protocol"
        lakehouse.dremio.engineOperator -> lakehouse.mongodb "Odczytuje konfigurację silników" "MongoDB Protocol"

        # Komponent Dremio → MinIO
        lakehouse.dremio.executionEngine -> minio "Odczytuje dane S3, pamięć podręczna C3" "S3 API"
        lakehouse.dremio.catalogServer -> minio "Przechowuje dane tabel Iceberg" "S3 API"

        # Wewnętrzne relacje komponentów Dremio
        lakehouse.dremio.catalogServerExternal -> lakehouse.dremio.queryCoordinator "Waliduje tokeny OAuth2 przez JWKS" "HTTP (:9047/oauth/discovery/jwks.json)"
        lakehouse.dremio.catalogServerExternal -> lakehouse.dremio.catalogServer "Przekazuje żądania katalogowe" "REST API (:9181)"
        lakehouse.spark -> lakehouse.dremio.catalogServerExternal "Dostęp do katalogu Iceberg przez OAuth2" "Iceberg REST API (:8181)"

        # ===========================
        # L3 — Relacje (komponenty Superset)
        # ===========================

        lakehouse.superset.supersetWebApp -> lakehouse.dremio "Odpytuje dane" "Arrow Flight SQL"
        lakehouse.superset.supersetWebApp -> keycloak "Uwierzytelnianie użytkowników" "OIDC"
        lakehouse.superset.supersetCeleryWorkers -> lakehouse.dremio "Wykonywanie zapytań w tle" "Arrow Flight SQL"

        # ===========================
        # L3 — Relacje (komponenty Spark)
        # ===========================

        lakehouse.spark.sparkDriver -> lakehouse.spark.sparkExecutors "Dystrybucja zadań" "RPC"
        lakehouse.spark.sparkDriver -> minio "Odczytuje/zapisuje tabele Iceberg" "S3 API (s3a://)"
        lakehouse.spark.sparkExecutors -> minio "Odczytuje/zapisuje dane" "S3 API (s3a://)"
        lakehouse.airflow -> lakehouse.spark.sparkOperator "Przesyła SparkApplication" "K8s API"
        lakehouse.jupyterhub -> lakehouse.spark.sparkDriver "Jądro PySpark" "Spark Connect"

        # ===========================
        # L3 — Relacje (komponenty Airflow)
        # ===========================

        lakehouse.airflow.airflowScheduler -> lakehouse.airflow.airflowTaskExecutor "Wyzwala zadania" "K8s API"
        lakehouse.airflow.airflowTaskExecutor -> lakehouse.dremio "Kroki SQL potoków" "JDBC/Flight SQL"
        lakehouse.airflow.airflowScheduler -> lakehouse.spark.sparkOperator "Przesyła SparkApplication" "K8s API"
        lakehouse.airflow.airflowTaskExecutor -> minio "Operacje na plikach" "S3 API"
        lakehouse.airflow.airflowWebUI -> keycloak "Uwierzytelnianie użytkowników" "OIDC"

        # ===========================
        # L3 — Relacje (komponenty JupyterHub)
        # ===========================

        lakehouse.jupyterhub.hubUserSessions -> lakehouse.dremio "Zapytania Flight SQL" "Arrow Flight SQL"
        lakehouse.jupyterhub.hubUserSessions -> lakehouse.spark.sparkDriver "Jądro PySpark" "Spark Connect"
        lakehouse.jupyterhub.hubUserSessions -> minio "Bezpośredni dostęp do danych" "S3 API (boto3/s3fs)"
        lakehouse.jupyterhub.hubServer -> keycloak "Uwierzytelnianie użytkowników" "OAuthenticator"
        lakehouse.jupyterhub.hubProxy -> lakehouse.jupyterhub.hubServer "Routing do huba" "HTTP"
        lakehouse.jupyterhub.hubProxy -> lakehouse.jupyterhub.hubUserSessions "Routing do notebooków" "HTTP"

        # Relacje monitorowania L3 usunięte — Monitoring jest teraz systemem zewnętrznym

        # ===========================
        # L4 — Wdrożenie (OpenShift)
        # ===========================

        deploymentEnvironment "OpenShift" {

            deploymentNode "dlh-prd namespace" "" "OpenShift Namespace" {

                # =========================================
                # Dremio Container Boundary
                # =========================================
                deploymentNode "Dremio" "" "Container Boundary" {
                    properties {
                        "Monitoring: Metrics" ":9010/metrics (Coordinator, Executors), :8080/q/metrics (Engine Operator), /metrics (Catalog Server), /q/metrics (Catalog Services)"
                        "Monitoring: Logs" "stdout → external log collector"
                        "Monitoring: Annotations" "metrics.dremio.com/scrape: true (niestandardowa, specyficzna dla Dremio)"
                        "Helm chart" "dremio/dremio 3.2.3 (Enterprise)"
                        "Image" "quay.io/dremio/dremio-ee:26.1"
                        "Secret: license" "dremio-license — klucz licencji Dremio EE"
                        "Secret: s3-catalog" "catalog-server-s3-storage-creds — klucze dostępu S3 dla bucketu Polaris dremio-catalog (z build.sh)"
                        "Secret: image-pull" "dremio-quay-secret — imagePullSecret dla quay.io/dremio"
                        "Networking" "dremio-client (LoadBalancer :9047/:31010/:32010), dremio-cluster-pod (headless :9999)"
                        "Service DNS" "dremio-client.<namespace>.svc.cluster.local"
                    }

                    deploymentNode "dremio-master" "" "StatefulSet (1 replica)" {
                        coordinatorInstance = containerInstance lakehouse.dremio
                        properties {
                            "Purpose" "Koordynator zapytań — parsowanie SQL, planowanie zapytań, połączenia klientów, Web UI, REST API. Pojedynczy master z wbudowaną elekcją ZK."
                            "Container: dremio-master-coordinator" "quay.io/dremio/dremio-ee:26.1"
                            "Ports" ":9047 (Web UI), :31010 (ODBC/JDBC), :32010 (Arrow Flight), :45678 (fabric), :45679 (conduit), :9010 (metrics)"
                            "Init containers" "start-only-one-dremio-master, wait-for-zookeeper-and-nats"
                            "ServiceAccount" "coordinator SA"
                            "PVC" "dremio-master-volume 10Gi (ceph-block) — /opt/dremio/data/ (RocksDB metadane, wyniki zapytań, klucze bezpieczeństwa)"
                            "Probes" "startup, readiness, liveness (HTTP :9047)"
                            "Resources" "requests: 250m/4Gi, limits: 2/8Gi"
                            "Labels" "external-client-access: true, role: dremio-cluster-pod"
                            "Annotations" "metrics.dremio.com/scrape: true, port: 9010"
                        }
                    }
                    deploymentNode "dremio-executor" "" "StatefulSet (0-N replicas, Engine Operator)" {
                        executorInstance = containerInstance lakehouse.dremio
                        properties {
                            "Purpose" "Silnik wykonawczy — rozproszone fragmenty zapytań. Zarządzany przez Engine Operator przez CRD Engine, NIE przez Helm. Silniki tworzone przez Dremio UI."
                            "Container: dremio-executor" "quay.io/dremio/dremio-ee:26.1"
                            "Ports" ":45678 (fabric), :45679 (conduit), :9010 (metrics)"
                            "Init containers" "wait-for-zookeeper"
                            "ServiceAccount" "executor SA"
                            "PVC: data" "executor-volume 10Gi (ceph-block) — /opt/dremio/data/ (zrzut na dysk, logi, wyniki)"
                            "PVC: c3" "executor-c3 10Gi (ceph-block) — /opt/dremio/cloudcache/c0/ (Columnar Cloud Cache — lokalna pamięć podręczna danych S3)"
                            "Probes" "TCP :45678 (startup: 30s delay, 60 retries; liveness: 30 retries)"
                            "Engine sizes" "Micro (1 pod, 4Gi), Small (1 pod, 10Gi), Medium (2 pods, 10Gi), Large (2 pods, 12Gi)"
                            "CPU capacities" "1C, 2C, 4C (domyślna: 1C)"
                            "Node tag" "-Dservices.node-tag=<engineName>"
                        }
                    }
                    deploymentNode "engine-operator" "" "Deployment (1 replica)" {
                        properties {
                            "Purpose" "Monitoruje CRD Engine (tworzone przez Dremio UI), uzgadnia StatefulSety executorów z konfiguracją rozmiaru/CPU/magazynu"
                            "Port" ":8080 (HTTP — health, metrics)"
                            "ServiceAccount" "engine-operator"
                            "Role" "engine-operator-role — zarządzanie CRD Engine, StatefulSetami, PVC, ConfigMapami, Podami, zdarzeniami"
                            "RoleBinding" "engine-operator-role-binding → SA engine-operator"
                            "Coordinator RBAC" "engine-coordinator-role + RoleBinding (coordinator SA zarządza CRD Engine)"
                            "ConfigMaps" "executor-statefulset-template (szablon podów executorów), engine-options (definicje rozmiarów)"
                            "CRD" "engines.private.dremio.com — CRD Engine dla dynamicznych pul executorów"
                        }
                    }
                    deploymentNode "catalog-server" "" "Deployment (1 replica)" {
                        properties {
                            "Purpose" "Wewnętrzny Polaris (Open Catalog) — Iceberg REST API dla koordynatora Dremio. Metadane katalogowe w MongoDB, dane tabel w S3."
                            "Ports" ":8181 (catalog-http), :9001 (catalog-mgmt), :40000 (catalog-grpc)"
                            "Init containers" "copy-run-scripts, wait-for-mongo"
                            "ServiceAccount" "catalog SA"
                            "Services" "catalog-server (ClusterIP :8181), catalog-server-mgmt (headless :9001), catalog-server-grpc (headless :40000)"
                            "S3 storage" "s3://dremio-catalog — Ceph RGW, pathStyleAccess, klucze statyczne (catalog-server-s3-storage-creds)"
                            "Resources" "requests: 200m/1Gi, limits: 1/2Gi"
                        }
                    }
                    deploymentNode "catalog-server-external" "" "Deployment (0 replicas, wyłączony POC)" {
                        properties {
                            "Purpose" "Zewnętrzny endpoint Polaris — eksponuje Iceberg REST API dla Spark i klientów zewnętrznych. Wyłączony w bieżącym wdrożeniu POC."
                            "Ports" ":8443 (cat-http-ext), :9002 (cat-mgmt-ext), :40000 (cat-grpc-ext)"
                            "TLS" "Opcjonalny TLS na porcie HTTP"
                            "OIDC" "Integracja z koordynatorem dla uwierzytelniania"
                            "Labels" "catalog-type: external, external-client-access: true"
                        }
                    }
                    deploymentNode "catalog-services" "" "Deployment (1 replica)" {
                        properties {
                            "Purpose" "Catalog Services — backend usług Open Catalog (Polaris): zarządzanie operacjami na tabelach Iceberg, metadanymi katalogowymi w MongoDB, komunikacja z catalog-server przez gRPC i koordynatorem przez NATS"
                            "Ports" ":grpc (catalog-grpc), :mgmt (catalog-mgmt)"
                            "Init containers" "copy-run-scripts, wait-for-mongo"
                            "ServiceAccount" "catalog-services SA"
                            "Service" "catalog-services (ClusterIP :grpc)"
                            "Resources" "requests: 50m/256Mi, limits: 500m/1Gi"
                        }
                    }
                    deploymentNode "zookeeper" "" "StatefulSet (3 repliki)" {
                        properties {
                            "Purpose" "Koordynacja rozproszona — wybór mastera, rejestracja executorów, członkostwo klastra."
                            "Ports" ":2181 (klient), :2888 (serwer), :3888 (wybór lidera), :7000 (metryki)"
                            "Services" "zk-hs (headless :2181/:2888/:3888), zk-cs (ClusterIP :2181)"
                            "PDB" "zk-pdb (maxUnavailable: 1)"
                            "ServiceAccount" "zookeeper SA"
                            "ConfigMap" "zookeeper-config (logback.xml)"
                            "PVC" "datadir-zk-* 10Gi (ceph-block) — /data/ (logi transakcji i migawki)"
                            "Probes" "readiness + liveness (kontrola ruok)"
                            "Resources" "requests: 100m/512Mi, limits: 500m/1Gi"
                        }
                    }
                    deploymentNode "nats" "" "StatefulSet (3 repliki)" {
                        properties {
                            "Purpose" "Wewnętrzna wymiana komunikatów — dystrybucja zdarzeń między koordynatorem, catalog-services i executorami. JetStream włączony dla trwałych strumieni wiadomości."
                            "Ports" ":4222 (klient), :6222 (klaster), :8222 (monitoring/HTTP)"
                            "Services" "nats (ClusterIP :4222), nats-headless (headless :4222/:6222/:8222)"
                            "PDB" "PodDisruptionBudget (maxUnavailable: 1)"
                            "ServiceAccount" "nats SA"
                            "PVC" "nats-js-* 2Gi (ceph-block) — /data/jetstream/ (trwałe przechowywanie wiadomości JetStream)"
                            "JetStream" "Włączony — trwałe przechowywanie wiadomości"
                            "Resources" "requests: 100m/512Mi, limits: 500m/1Gi"
                        }
                    }
                }

                # =========================================
                # MongoDB Container Boundary
                # =========================================
                deploymentNode "MongoDB" "" "Container Boundary" {
                    properties {
                        "Monitoring: Metrics" ":9216/metrics (mongodb_exporter sidecar — connections, opcounters, replication lag, WiredTiger cache)"
                        "Monitoring: Logs" "stdout → external log collector"
                        "Monitoring: Annotations" "metrics.dremio.com/scrape: true (Dremio-specific, not standard prometheus.io/scrape)"
                        "Helm chart" "Bundled as Dremio subchart — no separate installation needed"
                        "Operator version" "Percona MongoDB Operator v1.21.1"
                        "Secret: app-users" "dremio-mongodb-app-users — dremio user (readWrite on dremio DB), pre-created by build.sh, helm.sh/resource-policy: keep"
                        "Secret: system-users" "dremio-mongodb-system-users — clusterAdmin, clusterMonitor, backup, userAdmin (pre-created by build.sh)"
                        "Secret: backup" "dremio-mongodb-backup — S3 access keys for PBM"
                        "Networking" ":27017/TCP (MongoDB wire protocol), :9216/TCP (Prometheus metrics)"
                        "Service DNS" "dremio-mongodb-rs0.<namespace>.svc.cluster.local"
                    }

                    deploymentNode "mongodb-operator" "" "Deployment (1 replica)" {
                        properties {
                            "Purpose" "Watches PerconaServerMongoDB CRs, reconciles StatefulSet/Service/CronJob/PVC"
                            "Image" "percona/percona-server-mongodb-operator:1.21.1"
                            "CRDs" "PerconaServerMongoDB, PerconaServerMongoDBBackup, PerconaServerMongoDBRestore"
                            "ServiceAccount" "dremio-mongodb-operator"
                            "Role" "dremio-mongodb-operator — manage PSMDB CRDs, pods, services, PVCs, secrets, StatefulSets, CronJobs, PDBs, leases, events"
                            "RoleBinding" "dremio-mongodb-operator → SA dremio-mongodb-operator"
                        }
                    }
                    deploymentNode "mongodb-rs0" "" "StatefulSet (3 replicas, Percona)" {
                        mongodbInstance = containerInstance lakehouse.mongodb
                        properties {
                            "Purpose" "MongoDB replica set — stores Dremio catalog metadata, user data, query profiles. Managed by Percona Operator via PerconaServerMongoDB CR."
                            "CR" "PerconaServerMongoDB dremio-mongodb (rs0)"
                            "ServiceAccount" "dremio-mongodb"
                            "Database" "dremio (user: dremio, password from .env)"
                            "Container: mongod" ":27017 — WiredTiger storage engine, replica set member, oplog for replication and PITR"
                            "Container: pbm-agent" "Percona Backup for MongoDB agent — coordinates physical backups and PITR oplog streaming to S3, managed by PBM CLI via the operator"
                            "Container: mongodb_exporter" "percona/mongodb_exporter:0.47.1 — :9216/metrics — exposes connections, opcounters, replication lag, WiredTiger cache stats to Prometheus"
                            "Service" "dremio-mongodb-rs0 (headless, :27017)"
                            "PVC" "mongod-data-dremio-mongodb-rs0-* 10Gi (ceph-block)"
                            "TLS" "preferTLS (default, disable with mongodb.disableTls: true)"
                            "Security" "non-root UID 1001, seccomp RuntimeDefault, all capabilities dropped"
                        }
                    }
                    deploymentNode "mongodb-backup" "" "CronJob (daily 00:00)" {
                        properties {
                            "Purpose" "Automated daily full backup of all MongoDB data. Combined with continuous oplog streaming, enables point-in-time recovery to any second between backups — protecting against accidental deletes, bad writes, or data corruption."
                            "CronJob name" "dremio-catalog-backups"
                            "Type" "Physical backup (GA since v1.16.0) — copies raw WiredTiger data files for fast, consistent restore"
                            "Schedule" "0 0 * * * (daily 00:00 UTC)"
                            "Oplog" "MongoDB operations log — an ordered journal of every write (insert, update, delete) applied to the replica set. Used for replication between members and for PITR recovery."
                            "PITR" "Point-in-Time Recovery — restores to any specific second, not just the last full backup. PBM continuously streams oplog chunks to S3 every 10 minutes (oplogSpanMin: 10). On restore, PBM replays the full backup + oplog entries up to the target timestamp."
                            "PITR requirement" "At least one full backup must exist before oplog capture starts — the first oplog chunk anchors to the latest full backup"
                            "Storage" "s3://dremio/catalog-backups/ (<timestamp>/ for full backups, pbmPitr/ for oplog chunks)"
                            "Retention" "3 backups"
                            "Compression" "gzip level 1"
                            "Secret" "dremio-mongodb-backup (S3 access keys for PBM)"
                            "On-demand backup" "Create PerconaServerMongoDBBackup CR"
                            "Restore" "Create PerconaServerMongoDBRestore CR (supports PITR date or latest)"
                        }
                    }
                    deploymentNode "mongodb-pre-delete-hook" "" "Job (helm pre-delete)" {
                        properties {
                            "Job name" "delete-mongodbcluster"
                            "Purpose" "Deletes PerconaServerMongoDB CR before operator removal, with finalizer removal fallback"
                            "ServiceAccount" "dremio-mongodb-pre-delete"
                            "Role" "dremio-mongodb-pre-delete-role — get/delete/patch PSMDB CRDs"
                            "RoleBinding" "dremio-mongodb-pre-delete-rolebinding → SA dremio-mongodb-pre-delete"
                        }
                    }
                }

                # =========================================
                # Superset Container Boundary
                # =========================================
                deploymentNode "Superset" "" "Container Boundary" {
                    properties {
                        "Monitoring: Metrics" "StatsD / Prometheus exporter (TBD)"
                        "Monitoring: Logs" "stdout → external log collector"
                    }

                    deploymentNode "superset-web" "" "Deployment (2 replicas)" {
                        supersetInstance = containerInstance lakehouse.superset
                    }
                    deploymentNode "superset-worker" "" "Deployment (2 replicas)" {
                    }
                    deploymentNode "superset-beat" "" "Deployment (1 replica)" {
                    }
                    deploymentNode "superset-redis" "" "StatefulSet (1 replica)" {
                    }
                    deploymentNode "superset-postgresql" "" "StatefulSet (1 replica)" {
                    }
                }

                # =========================================
                # Spark Container Boundary
                # =========================================
                deploymentNode "Spark" "" "Container Boundary" {
                    properties {
                        "Monitoring: Metrics" "Spark UI :4040 (driver), Prometheus servlet (if enabled)"
                        "Monitoring: Logs" "stdout → external log collector"
                    }

                    deploymentNode "spark-operator" "" "Deployment (1 replica)" {
                        sparkInstance = containerInstance lakehouse.spark
                    }
                    deploymentNode "spark-driver" "" "Pod (dynamic, per job)" {
                    }
                    deploymentNode "spark-executor" "" "Pod (dynamic, per job)" {
                    }
                }

                # =========================================
                # Airflow Container Boundary
                # =========================================
                deploymentNode "Airflow" "" "Container Boundary" {
                    properties {
                        "Monitoring: Metrics" "StatsD → Prometheus exporter (TBD)"
                        "Monitoring: Logs" "stdout → external log collector, remote logging to S3 (TBD)"
                    }

                    deploymentNode "airflow-webserver" "" "Deployment (1 replica)" {
                        airflowInstance = containerInstance lakehouse.airflow
                    }
                    deploymentNode "airflow-scheduler" "" "Deployment (1 replica)" {
                    }
                    deploymentNode "airflow-triggerer" "" "Deployment (1 replica)" {
                    }
                    deploymentNode "airflow-postgresql" "" "StatefulSet (1 replica)" {
                    }
                    deploymentNode "airflow-redis" "" "StatefulSet (1 replica)" {
                    }
                }

                # =========================================
                # JupyterHub Container Boundary
                # =========================================
                deploymentNode "JupyterHub" "" "Container Boundary" {
                    properties {
                        "Monitoring: Metrics" "/hub/metrics (Prometheus, if enabled)"
                        "Monitoring: Logs" "stdout → external log collector"
                    }

                    deploymentNode "hub" "" "Deployment (1 replica)" {
                        jupyterhubInstance = containerInstance lakehouse.jupyterhub
                    }
                    deploymentNode "proxy" "" "Deployment (1 replica)" {
                    }
                    deploymentNode "user-notebook" "" "Pod (dynamic, per user)" {
                    }
                }
            }
        }
    }

    views {
        # ===========================
        # L1 — Widok kontekstu systemu
        # ===========================
        systemContext lakehouse "L1_SystemContext" {
            include *
            include biDeveloper
            include kafkaLegacy
            include minioLegacy
            include externalAirflow
            include monitoring
            autoLayout
            title "L1 - Kontekst systemu: Data Lakehouse Platform"
            description "Zintegrowana platforma analityczna wdrożona na OpenShift, zbudowana wokół otwartych formatów danych (Apache Iceberg na MinIO). Zapewnia zunifikowaną federację zapytań SQL (Dremio), rozproszone obliczenia wsadowe (Spark), orkiestrację przepływów pracy (Airflow), interaktywne notebooki (JupyterHub) i dashboardy BI (Superset/PowerBI). Obserwowalność zapewniona przez zewnętrzną Platformę Monitorowania. Wszystkie komponenty użytkownika uwierzytelniają się przez Keycloak OIDC (planowane); Dremio federuje użytkowników bezpośrednio z LDAP/AD (aktualnie używane do uwierzytelniania). Uwaga: Kafka (Legacy) jest OBECNIE NIEDOSTĘPNA — zewnętrzna instancja Airflow (MSPD) kopiuje (planowane) pliki z Legacy MinIO do MinIO. Ostateczny mechanizm nie został jeszcze zaprojektowany."
        }

        # ===========================
        # L2 — Widok kontenerów
        # ===========================
        container lakehouse "L2_Containers" {
            include *
            autoLayout
            title "L2 - Kontenery: Data Lakehouse Platform"
            description "Logiczne jednostki wdrożeniowe w ramach platformy Data Lakehouse."
        }

        # ===========================
        # L3 — Widoki komponentów
        # ===========================
        component lakehouse.dremio "L3_Components_Dremio" {
            include *
            autoLayout
            title "L3 - Komponenty: Dremio"
            description "Wewnętrzne moduły logiczne Dremio: Query Coordinator, Execution Engine, Engine Operator, Catalog Server (Polaris), Catalog Server External i Catalog Services."
        }

        component lakehouse.superset "L3_Components_Superset" {
            include *
            autoLayout
            title "L3 - Komponenty: Apache Superset"
            description "Wewnętrzne moduły logiczne Superset: Web Application, Celery Workers i Celery Beat. Redis, PostgreSQL i zadania inicjalizacyjne to infrastruktura wewnętrzna (tylko L4)."
        }

        component lakehouse.spark "L3_Components_Spark" {
            include *
            autoLayout
            title "L3 - Komponenty: Apache Spark"
            description "Wewnętrzne moduły logiczne Spark: Operator, Driver, Executors i History Server."
        }

        component lakehouse.airflow "L3_Components_Airflow" {
            include *
            autoLayout
            title "L3 - Komponenty: Apache Airflow"
            description "Wewnętrzne moduły logiczne Airflow: Web UI, Scheduler, Triggerer i Task Executor (KubernetesExecutor). PostgreSQL, Redis, synchronizacja DAG i zdalne logowanie to infrastruktura wewnętrzna (tylko L4)."
        }

        component lakehouse.jupyterhub "L3_Components_JupyterHub" {
            include *
            autoLayout
            title "L3 - Komponenty: JupyterHub"
            description "Wewnętrzne moduły logiczne JupyterHub: Hub Server, Proxy, Notebook Spawner i User Sessions. Baza danych huba i image puller to infrastruktura wewnętrzna (tylko L4)."
        }

        # Widok monitorowania L3 usunięty — Monitoring jest teraz systemem zewnętrznym

        # ===========================
        # L4 — Widok wdrożenia
        # ===========================
        deployment lakehouse "OpenShift" "L4_Deployment_OCP" {
            include *
            autoLayout
            title "L4 - Wdrożenie: OpenShift / Kubernetes"
            description "Sposób wdrożenia kontenerów Data Lakehouse w namespace dlh-prd OpenShift. Każdy kontener L2 odpowiada granicy wdrożeniowej zawierającej jednostki uruchomieniowe (StatefulSets, Deployments, CronJobs, dynamiczne Pody). Monitoring jest zewnętrzny — każda granica dokumentuje endpointy metryk i logów."
        }

        # ===========================
        # Style
        # ===========================
        styles {
            element "Person" {
                shape Person
                background #4dabf7
                color #ffffff
            }
            element "Software System" {
                background #1971c2
                color #ffffff
            }
            element "External" {
                background #868e96
                color #ffffff
            }
            element "Container" {
                background #4dabf7
                color #ffffff
            }
            element "Component" {
                background #a5d8ff
                color #000000
            }
            element "Deployment Node" {
                background #fff3bf
                color #000000
            }
        }
    }
}
