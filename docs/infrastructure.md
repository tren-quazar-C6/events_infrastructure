# INFRASTRUCTURE.md

> Documentación técnica completa de la infraestructura del proyecto **Quasar (Tickify)**.
> Responsable original: Dev 4 — Luis Miguel
> Última actualización: Mayo 2026

---

## Tabla de contenido

- [Visión general del proyecto](#visión-general-del-proyecto)
- [Arquitectura](#arquitectura)
- [Stack tecnológico](#stack-tecnológico)
- [Decisiones arquitectónicas](#decisiones-arquitectónicas)
- [Estructura de repositorios](#estructura-de-repositorios)
- [Bases de datos](#bases-de-datos)
- [Docker y orquestación](#docker-y-orquestación)
- [Nginx del sistema](#nginx-del-sistema)
- [Variables de entorno](#variables-de-entorno)
- [Estado actual del stack](#estado-actual-del-stack)
- [Mapa de puertos](#mapa-de-puertos)
- [Comandos esenciales en el VPS](#comandos-esenciales-en-el-vps)
- [Troubleshooting](#troubleshooting)

---

## Visión general del proyecto

Quasar (también llamado Tickify) es un sistema de venta y gestión de boletas para teatro, diseñado como reemplazo de TuBoleta. Está compuesto por 4 portales MVC server-side y 3 APIs REST, todos desplegados en un VPS compartido.

| Portal | Repo | Stack | Subdominio |
|--------|------|-------|------------|
| Users (público) | `events_users` | Laravel 13 + PHP 8.4 | `quasar.andrescortes.dev` |
| Admin (backoffice) | `events_admin` | ASP.NET Core 10 MVC | `admin.quasar.andrescortes.dev` |
| Tickets (taquilla) | `events_tickets` | ASP.NET Core 10 MVC | `tickets.quasar.andrescortes.dev` |
| Access (escaneo QR) | `events_access` | ASP.NET Core 10 MVC | `access.quasar.andrescortes.dev` |

| API | Repo | Stack | Subdominio |
|-----|------|-------|------------|
| API Admin | `events_api_admin` | ASP.NET Core 10 Web API | pendiente DNS |
| API Tickets | `events_api_tickets` | ASP.NET Core 10 Web API | pendiente DNS |
| API Access | `events_api_access` | ASP.NET Core 10 Web API | pendiente DNS |

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────┐
│                           INTERNET                                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │ DNS → 204.168.211.73
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      VPS Ubuntu 24.04                               │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │ 
│  │  Nginx del sistema (puerto 80/443)                           │   │
│  │  /etc/nginx/sites-enabled/quasar.conf                        │   │
│  │                                                              │   │
│  │  quasar.andrescortes.dev           → 127.0.0.1:8100          │   │
│  │  admin.quasar.andrescortes.dev     → 127.0.0.1:8101          │   │
│  │  tickets.quasar.andrescortes.dev   → 127.0.0.1:8102          │   │
│  │  access.quasar.andrescortes.dev    → 127.0.0.1:8103          │   │
│  │  (APIs: pendiente subdominios)     → 127.0.0.1:8105-8107     │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                               │                                     │
│                               ▼                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Docker network: quasar_network                              │   │
│  │                                                              │   │ 
│  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                      │   │
│  │  │users │  │admin │  │ticket│  │access│  Monolitos MVC       │   │
│  │  │:8000 │  │:8080 │  │:8080 │  │:8080 │                      │   │
│  │  └──────┘  └──────┘  └──────┘  └──────┘                      │   │
│  │                                                              │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                    │   │
│  │  │api-admin │  │api-ticket│  │api-access│  APIs REST         │   │
│  │  │:8080     │  │:8080     │  │:8080     │                    │   │
│  │  └──────────┘  └──────────┘  └──────────┘                    │   │
│  │                                                              │   │
│  │           ┌───────────────┐                                  │   │
│  │           │     mysql     │  ← BD events (compartida)        │   │
│  │           │     :3306     │                                  │   │
│  │           └───────────────┘                                  │   │
│  │           ┌───────────────┐                                  │   │
│  │           │     mongo     │  ← BD events_logs (auditoría)    │   │
│  │           │     :27017    │                                  │   │
│  │           └───────────────┘                                  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Stack tecnológico

| Componente | Versión | Rol |
|-----------|---------|-----|
| MySQL | 8 | BD relacional principal (BD: `events`) |
| MongoDB | 7 | Logs y auditoría (BD: `events_logs`) |
| Nginx | 1.24 (del sistema Ubuntu) | Reverse proxy de los subdominios |
| Docker | 24+ | Containerización |
| Docker Compose | v2 (`docker compose`) | Orquestación del stack |
| GitHub Actions | — | CI/CD automático |
| GHCR | — | Registry de imágenes Docker |
| Let's Encrypt | — | Certificados HTTPS |
| Certbot | 2.9.0 | Cliente Let's Encrypt |

---

## Decisiones arquitectónicas

Estas decisiones fueron tomadas en conjunto y están congeladas. No cambiar sin consenso del equipo.

| Decisión | Razón |
|----------|-------|
| **1 sola BD MySQL `events` compartida** | Los 4 monolitos necesitan datos relacionales entre módulos. Separarlos obligaría a llamadas HTTP entre servicios. |
| **4 usuarios MySQL distintos** | Aislamiento de permisos. Si una app se compromete, no puede tocar tablas de otras. |
| **MongoDB para logs y auditoría** | Escritura masiva y consultas analíticas son más eficientes en NoSQL. Separa logs del modelo transaccional. |
| **Nginx del sistema, no Nginx en Docker** | El VPS es compartido con otros equipos del curso. El Nginx del sistema enruta todos los proyectos. Meter Nginx en Docker generaría conflictos con los demás equipos. |
| **Docker Compose, no Docker Swarm** | Un solo VPS. Swarm es para múltiples nodos. `restart: unless-stopped` cubre la necesidad de auto-recuperación. |
| **MVC server-side (Blade/Razor)** | Un solo artefacto por monolito en lugar de backend + frontend separados. Simplifica la arquitectura de 8 containers a 7. |
| **3 APIs REST separadas** | Los monolitos MVC consumen las APIs para la lógica de negocio. Cada API comparte la misma BD MySQL pero con su usuario correspondiente. |
| **GHCR como registry de imágenes** | Integrado con GitHub, privado, sin costo extra en el plan del equipo. |
| **Repos públicos en GitHub** | Simplifica el `git pull` en el VPS sin necesidad de Deploy Keys SSH. Decisión tomada por pragmatismo en el contexto académico. |
| **Versionado semántico (SemVer 2.0.0)** | Cada imagen Docker se tagea con `vX.Y.Z` para visibilidad en GHCR y trazabilidad de cambios. |

---

## Estructura de repositorios

Todos los repos viven en la organización `tren-quazar-C6` en GitHub.

```
tren-quazar-C6/
├── events_infrastructure   ← ESTE repo. Orquestación central (Dev 4)
├── events_users            ← Portal Users (Laravel) + API Users
├── events_admin            ← Portal Admin (ASP.NET MVC)
├── events_tickets          ← Portal Tickets (ASP.NET MVC)
├── events_access           ← Portal Access (ASP.NET MVC)
├── events_api_admin        ← API Admin (ASP.NET Web API)
├── events_api_tickets      ← API Tickets (ASP.NET Web API)
└── events_api_access       ← API Access (ASP.NET Web API)
```

### Estructura de events_infrastructure

```
events_infrastructure/
├── docker-compose.yml          ← orquestación del stack completo
├── .env.example                ← plantilla de variables (en Git)
├── .env                        ← variables reales (NUNCA en Git)
├── .gitignore
├── README.md
│
├── mysql/
│   └── init/
│       └── 01_users_grants.sh  ← crea 4 usuarios MySQL con sus grants
│
├── mongo/
│   └── init/
│       └── 01_init.js          ← crea usuario logs_app + colecciones + índices
│
├── nginx/
│   └── nginx.conf              ← plantilla de referencia (NO se usa en el VPS)
│
├── docs/
│   ├── INFRASTRUCTURE.md       ← este archivo
│   ├── CICD.md                 ← documentación del CI/CD
│   └── ONBOARDING.md          ← guía para devs nuevos
│
└── .github/
    └── workflows/
        └── deploy.yml          ← CI/CD: push → git pull en VPS
```

---

## Bases de datos

### MySQL — BD `events`

Un solo servidor MySQL con una sola BD llamada `events`. Los 4 monolitos y las 3 APIs comparten esta BD, cada uno con su propio usuario.

#### Usuarios y permisos

| Usuario | Password (ver .env) | Usado por |
|---------|---------------------|-----------|
| `root` | `MYSQL_ROOT_PASSWORD` | Administración (solo Dev 4) |
| `users_app` | `MYSQL_USERS_PASSWORD` | events_users |
| `admin_app` | `MYSQL_ADMIN_PASSWORD` | events_admin + events_api_admin |
| `tickets_app` | `MYSQL_TICKETS_PASSWORD` | events_tickets + events_api_tickets |
| `access_app` | `MYSQL_ACCESS_PASSWORD` | events_access + events_api_access |

Todos los usuarios tienen `GRANT ALL PRIVILEGES ON events.*` provisionalmente. Cuando el equipo defina el schema final, refinar por tabla.

#### Script de inicialización

`mysql/init/01_users_grants.sh` se ejecuta **automáticamente** cuando MySQL arranca por primera vez con un volumen vacío. Crea los 4 usuarios leyendo las variables de entorno del `.env`. NO hardcodea passwords.

**Importante:** si el volumen ya existe, el script NO se vuelve a ejecutar. Para reinicializar desde cero (solo en desarrollo local):

```bash
docker compose down -v   # ⚠️ borra TODOS los datos
docker compose up -d
```

#### Conectarse a MySQL

```bash
# Como root
docker exec -it quasar_mysql mysql -u root -p
# Ingresar MYSQL_ROOT_PASSWORD del .env

# Como usuario de app
docker exec -it quasar_mysql mysql -u users_app -p
# Ingresar MYSQL_USERS_PASSWORD del .env

# Ver bases de datos
SHOW DATABASES;

# Ver usuarios creados
SELECT User, Host FROM mysql.user WHERE User LIKE '%_app';

# Ver grants de un usuario
SHOW GRANTS FOR 'users_app'@'%';
```

---

### MongoDB — BD `events_logs`

MongoDB se usa exclusivamente para auditoría y logs operativos. No contiene datos de negocio.

#### Usuarios

| Usuario | Rol | BD |
|---------|-----|-----|
| `root` | root (solo admin) | admin |
| `logs_app` | readWrite | events_logs |

#### Colecciones

| Colección | Propósito |
|-----------|-----------|
| `audit_logs` | Eventos de negocio: compra, escaneo, login, etc. |
| `app_logs` | Logs técnicos: errores, warnings, info de cada monolito |

#### Índices creados

En `audit_logs`: `timestamp` (desc), `event`, `user_id`, `portal`
En `app_logs`: `timestamp` (desc), `level`, `portal`

#### Conectarse a MongoDB

```bash
# Como usuario de app
docker exec -it quasar_mongo mongosh \
  -u logs_app -p \
  --authenticationDatabase events_logs

# Dentro de mongosh
use events_logs
show collections
db.audit_logs.find().limit(5).pretty()
db.app_logs.find({ level: "ERROR" }).sort({ timestamp: -1 }).limit(10)

# Salir
exit
```

#### Verificar que logs_app NO tiene acceso a admin

```javascript
// Dentro de mongosh como logs_app
use admin
db.adminCommand({ listDatabases: 1 })
// Debe dar error: not authorized — eso es correcto
```

---

## Docker y orquestación

### docker-compose.yml

El archivo `docker-compose.yml` en el repo define **todos los servicios del stack**. Es la fuente de verdad de la infraestructura.

Servicios definidos:

| Servicio | Container | Imagen | Puerto host → container |
|----------|-----------|--------|------------------------|
| `mysql` | `quasar_mysql` | `mysql:8` | 3306 → 3306 |
| `mongo` | `quasar_mongo` | `mongo:7` | 27017 → 27017 |
| `users` | `quasar_users` | GHCR `events_users:latest` | 8100 → 8000 |
| `admin` | `quasar_admin` | GHCR `events_admin:latest` | 8101 → 8080 |
| `tickets` | `quasar_tickets` | GHCR `events_tickets:latest` | 8102 → 8080 |
| `access` | `quasar_access` | GHCR `events_access:latest` | 8103 → 8080 |
| `api-users` | `quasar_api_users` | GHCR `events_api_users:latest` | 8104 → 8000 |
| `api-admin` | `quasar_api_admin` | GHCR `events_api_admin:latest` | 8105 → 8080 |
| `api-tickets` | `quasar_api_tickets` | GHCR `events_api_tickets:latest` | 8106 → 8080 |
| `api-access` | `quasar_api_access` | GHCR `events_api_access:latest` | 8107 → 8080 |

### Comandos Docker esenciales

```bash
# Ver todos los containers corriendo
docker ps

# Ver containers con estado y puertos
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Ver logs en vivo de un servicio
docker compose logs -f mysql
docker compose logs -f admin
docker compose logs -f api-admin

# Reiniciar un servicio específico
docker compose restart admin

# Levantar todo (o aplicar cambios del compose)
docker compose up -d

# Levantar solo un servicio sin tocar los demás
docker compose up -d --no-deps admin

# Forzar pull de nueva imagen y recrear container
docker compose pull admin
docker compose up -d --no-deps admin

# Detener todo (preserva datos)
docker compose down

# Detener todo Y borrar datos ⚠️ DESTRUCTIVO
docker compose down -v

# Ver uso de disco de imágenes
docker system df

# Limpiar imágenes sin usar
docker image prune -f
```

### Red interna Docker

Todos los containers están en la red `quasar_network`. Dentro de esta red, los containers se comunican por nombre de servicio, no por IP:

```
Container events_admin → se conecta a MySQL así:
  Server=mysql;Port=3306;...   ← "mysql" resuelve internamente

Container events_admin → se conecta a MongoDB así:
  mongodb://logs_app:pass@mongo:27017/...   ← "mongo" resuelve internamente
```

**Nunca usar `localhost` o `127.0.0.1` para conexiones entre containers.**

### pull_policy: always

Todos los servicios de monolitos tienen `pull_policy: always` en el compose. Esto significa que cada vez que se ejecuta `docker compose up -d`, Docker verifica si hay una imagen más nueva en GHCR. Es lo que hace que el deploy automático funcione sin reiniciar manualmente el container.

---

## Nginx del sistema

### Cómo está configurado

El VPS tiene un **Nginx instalado vía apt** (no en Docker). Es el Nginx del sistema Ubuntu. Este Nginx enruta el tráfico de todos los equipos del curso, no solo Quasar.

**El archivo de configuración de Quasar:**

```
/etc/nginx/sites-available/quasar.conf   ← archivo de configuración
/etc/nginx/sites-enabled/quasar.conf     ← symlink (habilitado)
```

**Importante:** este archivo NO está en Git porque el VPS es compartido. Cambios manuales en el VPS.

### Enrutamiento actual

| Dominio | Puerto VPS | Container |
|---------|-----------|-----------|
| `quasar.andrescortes.dev` | 8100 | quasar_users |
| `admin.quasar.andrescortes.dev` | 8101 | quasar_admin |
| `tickets.quasar.andrescortes.dev` | 8102 | quasar_tickets |
| `access.quasar.andrescortes.dev` | 8103 | quasar_access |
| APIs: pendiente DNS | 8105-8107 | quasar_api_* |

### Proceso para cambiar Nginx

**SIEMPRE seguir este orden:**

```bash
# 1. Editar el archivo
nano /etc/nginx/sites-available/quasar.conf

# 2. Validar sintaxis ANTES de recargar
nginx -t

# 3. Solo si nginx -t dice "test is successful":
systemctl reload nginx

# 4. Verificar estado
systemctl status nginx | head -10

# 5. Si algo falló, ver logs
journalctl -u nginx -n 50
```

**Nunca hacer `systemctl restart nginx` sin antes validar con `nginx -t`.** Un error de sintaxis reiniciando Nginx tumba todos los proyectos del VPS.

### HTTPS

HTTPS está configurado con Let's Encrypt vía Certbot. Los certificados expiran cada 90 días pero se renuevan automáticamente.

```bash
# Ver certificados activos
certbot certificates

# Verificar que el timer de renovación está activo
systemctl status certbot.timer

# Simular renovación (sin hacerla realmente)
certbot renew --dry-run

# Emitir certificado para nuevos subdominios
sudo certbot --nginx
# Elige los subdominios nuevos de la lista

# Verificar HTTPS de un dominio
curl -I https://admin.quasar.andrescortes.dev
```

### Agregar un nuevo subdominio

1. Verificar que el DNS apunta al VPS (`204.168.211.73`)
2. Agregar bloque `server` en `/etc/nginx/sites-available/quasar.conf`
3. `nginx -t`
4. `systemctl reload nginx`
5. `sudo certbot --nginx` y elegir el nuevo dominio
6. Verificar con `curl -I https://nuevo-dominio`

---

## Variables de entorno

### Regla fundamental

```
.env.example  → en Git, sin valores reales, documenta qué variables existen
.env          → NUNCA en Git, tiene los valores reales de producción
```

### .env del VPS

Ubicación: `/opt/quasar/events_infrastructure/.env`

Permisos correctos:

```bash
chmod 600 /opt/quasar/events_infrastructure/.env
ls -la /opt/quasar/events_infrastructure/.env
# Debe mostrar: -rw------- 1 root root
```

### Cómo ver el .env del VPS

```bash
cat /opt/quasar/events_infrastructure/.env
```

Para ver solo una variable específica:

```bash
grep MYSQL_USERS_PASSWORD /opt/quasar/events_infrastructure/.env
```

### Variables actuales del VPS

El `.env` del VPS contiene estas categorías:

| Categoría | Variables |
|-----------|-----------|
| App general | `APP_NAME`, `TZ` |
| MySQL admin | `MYSQL_ROOT_PASSWORD`, `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE` |
| MySQL apps | `MYSQL_{USERS,ADMIN,TICKETS,ACCESS}_USER` + `_PASSWORD` |
| MongoDB | `MONGO_HOST`, `MONGO_PORT`, `MONGO_ROOT_USER`, `MONGO_ROOT_PASSWORD`, `MONGO_DB`, `MONGO_USER`, `MONGO_PASSWORD` |
| Nginx | `NGINX_HTTP_PORT`, `NGINX_HTTPS_PORT` |
| Laravel Users | `USERS_APP_URL`, `USERS_APP_ENV`, `USERS_APP_DEBUG`, `USERS_APP_KEY`, `USERS_PORT` |
| ASP.NET MVC | `ADMIN_ASPNETCORE_ENVIRONMENT`, `TICKETS_ASPNETCORE_ENVIRONMENT`, `ACCESS_ASPNETCORE_ENVIRONMENT` |
| ASP.NET APIs | `API_ADMIN_ASPNETCORE_ENVIRONMENT`, `API_TICKETS_ASPNETCORE_ENVIRONMENT`, `API_ACCESS_ASPNETCORE_ENVIRONMENT` |

### Variables pendientes de agregar (cuando se implementen)

Ver `.env.example` para la lista completa. Pendientes más importantes:

- `JWT_SECRET` — cuando se implemente autenticación compartida
- `WOMPI_*` — cuando Faiber integre pagos
- `N8N_*` — cuando se monte n8n para correos
- `GOOGLE_CLIENT_*` — cuando se implemente login con Google
- `SMTP_*` — cuando se configure envío de correos

### Generar passwords seguros para el .env

```bash
openssl rand -hex 24   # genera 48 caracteres hex
```

---

## Estado actual del stack

Verificado el 20 de Mayo de 2026.

```bash
# Comando para verificar en el VPS:
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

| Container | Estado | Puerto |
|-----------|--------|--------|
| `quasar_mysql` | Up (healthy) | 3306 |
| `quasar_mongo` | Up (healthy) | 27017 |
| `quasar_users` | Up | 8100 |
| `quasar_admin` | Up | 8101 |
| `quasar_tickets` | Up | 8102 |
| `quasar_access` | Up | 8103 |
| `quasar_api_users` | Up | 8104 |
| `quasar_api_admin` | Up | 8105 |
| `quasar_api_tickets` | Up | 8106 |
| `quasar_api_access` | Up | 8107 |

### Dominios con HTTPS activo

```bash
# Verificar todos los dominios
curl -I https://quasar.andrescortes.dev
curl -I https://admin.quasar.andrescortes.dev
curl -I https://tickets.quasar.andrescortes.dev
curl -I https://access.quasar.andrescortes.dev
```

Todos deben responder `HTTP/2 200`.

### Pendiente

- DNS para los subdominios de las 3 APIs (pendiente del profe)
- Server blocks Nginx para las APIs
- HTTPS de las APIs vía Certbot

---

## Mapa de puertos

```
Puerto host  →  Container          →  Servicio
──────────────────────────────────────────────────
3306         →  quasar_mysql       →  MySQL
27017        →  quasar_mongo       →  MongoDB
8100         →  quasar_users       →  events_users (Laravel)
8101         →  quasar_admin       →  events_admin (ASP.NET MVC)
8102         →  quasar_tickets     →  events_tickets (ASP.NET MVC)
8103         →  quasar_access      →  events_access (ASP.NET MVC)
8104         →  quasar_api_users   →  events_api_users (Laravel API)
8105         →  quasar_api_admin   →  events_api_admin (ASP.NET API)
8106         →  quasar_api_tickets →  events_api_tickets (ASP.NET API)
8107         →  quasar_api_access  →  events_api_access (ASP.NET API)
```

Puerto interno de los containers:
- Laravel: `8000`
- ASP.NET: `8080`

---

## Comandos esenciales en el VPS

### Conexión al VPS

```bash
# Desde Windows (PowerShell)
ssh -i C:\Users\User\Documents\quasar\secrets\deploy_key root@204.168.211.73

# Desde Mac/Linux
ssh -i ~/quasar/secrets/deploy_key root@204.168.211.73
```

### Diagnóstico general

```bash
# Estado de todos los containers
docker ps

# Logs en vivo de un container específico
docker compose -f /opt/quasar/events_infrastructure/docker-compose.yml logs -f admin

# Ver uso de disco
df -h
docker system df

# Ver uso de memoria y CPU
htop
# o:
docker stats --no-stream

# Ver logs de Nginx
journalctl -u nginx -n 100
tail -f /var/log/nginx/error.log
```

### Ir al directorio del proyecto

```bash
cd /opt/quasar/events_infrastructure
```

### Aplicar cambios del compose manualmente

```bash
cd /opt/quasar/events_infrastructure
git pull origin main
docker compose up -d
```

### Restart de un container específico

```bash
cd /opt/quasar/events_infrastructure
docker compose restart admin
```

### Ver el .env del VPS

```bash
cat /opt/quasar/events_infrastructure/.env
```

### Editar el .env del VPS

```bash
nano /opt/quasar/events_infrastructure/.env
```

### Verificar HTTPS de todos los dominios

```bash
curl -I https://quasar.andrescortes.dev
curl -I https://admin.quasar.andrescortes.dev
curl -I https://tickets.quasar.andrescortes.dev
curl -I https://access.quasar.andrescortes.dev
```

### Ver certificados Let's Encrypt

```bash
certbot certificates
```

---

## Troubleshooting

### Container en estado `Restarting`

```bash
# Ver por qué falla
docker compose logs --tail=50 nombre_servicio
```

Causas comunes y soluciones:

| Causa | Solución |
|-------|---------|
| `command not found` en ENTRYPOINT | El Dockerfile tiene un comentario inline en la línea `ENTRYPOINT`. Borrar el comentario, rebuildar. |
| Variables de entorno vacías | Verificar que la variable existe en `.env` y está declarada en `environment:` del compose. |
| Puerto ocupado | Otro proceso usa el mismo puerto. `ss -tlnp \| grep 8101` para ver quién lo usa. |
| BD no disponible | El container de MySQL/Mongo no está healthy. Ver sus logs primero. |

### MySQL en `Restarting` o `Unhealthy`

```bash
docker compose logs mysql
```

Si dice `Access denied` en el healthcheck, el `MYSQL_ROOT_PASSWORD` en el `.env` no coincide con el password que MySQL tiene en su volumen.

Solución: si el volumen ya existe con otro password, hay que hacer `docker compose down -v` (borra datos) y volver a levantar.

### MongoDB no creó el usuario `logs_app`

El script `01_init.js` solo se ejecuta la primera vez (volumen vacío). Si el script falló silenciosamente, reinicializar:

```bash
docker compose down -v   # ⚠️ borra datos
docker compose up -d
```

### Nginx da 502 Bad Gateway

Significa que Nginx llega al VPS pero el container no responde. Pasos:

```bash
# 1. Verificar que el container está corriendo
docker ps | grep quasar_admin

# 2. Verificar que el puerto del host está activo
curl -I http://localhost:8101

# 3. Si el container no está corriendo, levantarlo
docker compose up -d --no-deps admin

# 4. Ver logs del container
docker compose logs --tail=50 admin
```

### Error `no such service: X` en el deploy

El servicio no existe en el `docker-compose.yml` del VPS. El compose del VPS puede estar desactualizado respecto al repo.

```bash
cd /opt/quasar/events_infrastructure
git pull origin main
docker compose up -d
```

### HTTPS muestra certificado inválido

```bash
# Ver qué certificados existen
certbot certificates

# Si el dominio no aparece, emitir nuevo certificado
sudo certbot --nginx
```

### CI/CD falla con `fatal: could not read Username`

El repo del VPS está clonado con HTTPS y es privado. Solución: hacer el repo público en GitHub (decisión ya tomada) o cambiar el remote a SSH con Deploy Key.

```bash
cd /opt/quasar/events_infrastructure
git remote -v
# Si dice https://github.com/... y el repo es privado, hay problema
```

### Ver si hay espacio en disco

```bash
df -h /
# Si / está al 80%+ de uso, limpiar imágenes Docker
docker image prune -a -f
```

---

**Responsable de esta documentación:** Dev 4 — Luis Miguel  
**Organización GitHub:** `tren-quazar-C6`  
**VPS:** `204.168.211.73` (Ubuntu 24.04)