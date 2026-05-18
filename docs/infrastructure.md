# events_infrastructure

Repositorio central de infraestructura del proyecto **Quasar** (Tickify).
Define el stack compartido (MySQL, MongoDB) y la orquestación Docker para
los 4 monolitos del sistema. También es el punto único donde viven los
archivos de configuración del entorno y los scripts de inicialización
de bases de datos.

---

## Tabla de contenido

- [Visión general](#visión-general)
- [Arquitectura](#arquitectura)
- [Stack tecnológico](#stack-tecnológico)
- [Estructura del repo](#estructura-del-repo)
- [Setup local](#setup-local)
- [Variables de entorno](#variables-de-entorno)
- [Despliegue en VPS](#despliegue-en-vps)
- [CI/CD](#cicd)
- [Comandos útiles](#comandos-útiles)
- [Troubleshooting](#troubleshooting)

---

## Visión general

Quasar es un sistema distribuido en 4 monolitos que sirven a 4 portales:

| Portal | Repo | Stack | Subdominio |
|--------|------|-------|------------|
| Users (público) | `events_users` | Laravel MVC | `quasar.andrescortes.dev` |
| Admin (backoffice) | `events_admin` | ASP.NET Core MVC | `admin.quasar.andrescortes.dev` |
| Tickets (taquilla) | `events_tickets` | ASP.NET Core MVC | `tickets.quasar.andrescortes.dev` |
| Access (escaneo QR) | `events_access` | ASP.NET Core MVC | `access.quasar.andrescortes.dev` |

Este repo (`events_infrastructure`) **no contiene código de negocio**.
Su responsabilidad es:

- Levantar las bases de datos compartidas (MySQL, MongoDB).
- Definir la red Docker común a todos los monolitos (`quasar_network`).
- Mantener los scripts de inicialización de las BDs.
- Servir como punto de entrada del CI/CD que actualiza la infra del VPS.

---

## Arquitectura

```
┌──────────────────────────────────────────────────────────────┐
│                         INTERNET                              │
└──────────────────────┬───────────────────────────────────────┘
                       │ DNS → 204.168.211.73
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                    VPS (Ubuntu 24.04)                         │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Nginx del sistema (puerto 80)                       │    │
│  │  /etc/nginx/sites-enabled/quasar.conf                │    │
│  │                                                       │    │
│  │  quasar.andrescortes.dev          → 127.0.0.1:8100  │    │
│  │  admin.quasar.andrescortes.dev    → 127.0.0.1:8101  │    │
│  │  tickets.quasar.andrescortes.dev  → 127.0.0.1:8102  │    │
│  │  access.quasar.andrescortes.dev   → 127.0.0.1:8103  │    │
│  └─────────────────────────────────────────────────────┘    │
│                            │                                  │
│                            ▼                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Docker network: quasar_network                      │    │
│  │                                                       │    │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐    │    │
│  │  │ users  │  │ admin  │  │tickets │  │ access │    │    │
│  │  │ :8000  │  │ :8080  │  │ :8080  │  │ :8080  │    │    │
│  │  └───┬────┘  └───┬────┘  └───┬────┘  └───┬────┘    │    │
│  │      │           │           │           │          │    │
│  │      └───────────┴───────────┴───────────┘          │    │
│  │                  │                                    │    │
│  │           ┌──────┴──────┐                            │    │
│  │           ▼             ▼                            │    │
│  │      ┌────────┐    ┌────────┐                       │    │
│  │      │ mysql  │    │ mongo  │                       │    │
│  │      │ :3306  │    │:27017  │                       │    │
│  │      └────────┘    └────────┘                       │    │
│  │           │             │                            │    │
│  │           ▼             ▼                            │    │
│  │      events DB    events_logs DB                    │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### Decisiones arquitectónicas

| Decisión | Razón |
|----------|-------|
| 1 sola BD MySQL (`events`) compartida | Las apps necesitan consultas relacionales entre módulos (sales, tickets, users). Separarlas obligaría a llamadas HTTP entre monolitos. |
| 4 usuarios MySQL con grants distintos | Aislamiento de permisos. Si una app se compromete, no puede tocar tablas que no le corresponden. |
| MongoDB para auditoría y logs | Escritura masiva y consultas analíticas son más eficientes en NoSQL. Separa logs operativos del modelo transaccional. |
| Nginx del sistema, no Nginx en Docker | El VPS es compartido entre varios equipos del curso. El Nginx del sistema enruta todos los proyectos. |
| Docker Compose, no Docker Swarm | Un solo VPS. Swarm aporta valor con múltiples nodos; con 1 nodo es overhead. `restart: unless-stopped` cubre la necesidad de auto-recuperación. |
| MVC server-side (Blade/Razor) | Simplifica la PWA: un solo artefacto por monolito en lugar de backend + frontend separados. Cumple el requisito del profe (Laravel + ASP.NET) sin agregar React/Vue. |

---

## Stack tecnológico

| Componente | Versión | Rol |
|-----------|---------|-----|
| MySQL | 8 | BD relacional principal (BD: `events`) |
| MongoDB | 7 | Logs y auditoría (BD: `events_logs`) |
| Nginx | del sistema (Ubuntu) | Reverse proxy de los 4 subdominios |
| Docker | 24+ | Orquestación |
| Docker Compose | v2 (`docker compose`) | Definición del stack |
| GitHub Actions | — | CI/CD |

---

## Estructura del repo

```
events_infrastructure/
├── docker-compose.yml          # Orquestación del stack
├── .env.example                # Plantilla de variables (sube a Git)
├── .env                        # Variables reales (NO sube a Git)
├── .gitignore
├── README.md
│
├── mysql/
│   └── init/
│       └── 01_users_grants.sh  # Crea los 4 usuarios y sus grants
│
├── mongo/
│   └── init/
│       └── 01_init.js          # Crea usuario logs_app, colecciones e índices
│
├── nginx/
│   ├── nginx.conf              # Plantilla (ya no se usa: usamos Nginx del VPS)
│   └── conf.d/                 # Plantillas de subdominios (referencia)
│
└── .github/
    └── workflows/
        └── deploy.yml          # CI/CD: push → git pull en VPS
```

---

## Setup local

Requisitos previos:

- Docker Desktop con WSL2 (Windows) o Docker Engine (Linux/Mac)
- Git

### Pasos

1. **Clonar el repo:**

```bash
   git clone https://github.com/tren-quazar-C6/events_infrastructure.git
   cd events_infrastructure
```

2. **Crear el archivo `.env` a partir de la plantilla:**

```bash
   cp .env.example .env
```

   Para desarrollo local, los valores placeholder (`cambiame_*`) son aceptables.
   **No uses esos valores en el VPS.**

3. **Levantar el stack:**

```bash
   docker compose up -d
```

4. **Verificar:**

```bash
   docker compose ps
```

   Debes ver `quasar_mysql` y `quasar_mongo` en `Up (healthy)`.

5. **Probar conexión a MySQL:**

```bash
   docker exec -it quasar_mysql mysql -u users_app -p
   # Pega la password de MYSQL_USERS_PASSWORD del .env
   SHOW DATABASES;
```

   Debe listar la BD `events`.

6. **Probar conexión a MongoDB:**

```bash
   docker exec -it quasar_mongo mongosh \
     -u logs_app -p <PASSWORD> \
     --authenticationDatabase events_logs
```

---

## Variables de entorno

El archivo `.env` define las credenciales y configuración del stack.
**Nunca se sube a Git** (está en `.gitignore`).

### Categorías de variables

| Categoría | Variables | Uso |
|-----------|-----------|-----|
| App general | `APP_NAME`, `TZ` | Nombre y zona horaria |
| MySQL — admin | `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_HOST`, `MYSQL_PORT` | Conexión y administración |
| MySQL — apps | `MYSQL_{USERS\|ADMIN\|TICKETS\|ACCESS}_USER` + `_PASSWORD` | Un par por cada monolito |
| MongoDB | `MONGO_ROOT_USER/PASSWORD`, `MONGO_USER/PASSWORD`, `MONGO_DB` | Root + usuario de app |
| Nginx | `NGINX_HTTP_PORT`, `NGINX_HTTPS_PORT` | (Solo si se usa Nginx en Docker — actualmente no) |

### Generar passwords seguros

En el VPS:

```bash
openssl rand -hex 24
```

Genera un string aleatorio de 48 caracteres hex. Úsalo para cada
`*_PASSWORD` del `.env` de producción.

---

## Despliegue en VPS

El VPS ya está configurado. Esta sección documenta cómo se hizo
(referencia para troubleshooting o setup en otro VPS).

### Pre-requisitos del VPS

- Ubuntu 22.04 o 24.04
- Docker + Docker Compose instalados
- Nginx del sistema instalado (`apt install nginx`)
- Acceso SSH con la `deploy_key` del proyecto en `~/.ssh/authorized_keys`

### Pasos de setup inicial (ya ejecutados)

1. **Clonar el repo en `/opt/quasar/events_infrastructure`:**

```bash
   mkdir -p /opt/quasar
   cd /opt/quasar
   git clone https://github.com/tren-quazar-C6/events_infrastructure.git
   cd events_infrastructure
```

2. **Crear el `.env` con passwords reales** (no usar los placeholders):

```bash
   nano .env
```

3. **Levantar el stack:**

```bash
   docker compose up -d
```

4. **Configurar Nginx del sistema** para enrutar los 4 subdominios:

   Crear `/etc/nginx/sites-available/quasar.conf` con un `server { ... }`
   por cada subdominio, apuntando a `127.0.0.1:8100..8103`.

   Habilitar y recargar:

```bash
   ln -s /etc/nginx/sites-available/quasar.conf /etc/nginx/sites-enabled/
   nginx -t                   # validar sintaxis
   systemctl reload nginx     # aplicar sin downtime
```

### Mapeo de puertos

| Servicio | Puerto del contenedor | Puerto en el host del VPS |
|----------|----------------------|---------------------------|
| MySQL | 3306 | 3306 |
| MongoDB | 27017 | 27017 |
| events_users (Laravel) | 8000 | 8100 |
| events_admin (ASP.NET) | 8080 | 8101 |
| events_tickets (ASP.NET) | 8080 | 8102 |
| events_access (ASP.NET) | 8080 | 8103 |

---

## CI/CD

Cada `git push` a `main` dispara un workflow de GitHub Actions
(`.github/workflows/deploy.yml`) que:

1. Se conecta al VPS por SSH usando la `deploy_key` del proyecto.
2. Hace `git pull` del repo en `/opt/quasar/events_infrastructure`.
3. Ejecuta `docker compose up -d` para aplicar cambios.

### Secrets requeridos en el repo

| Secret | Valor |
|--------|-------|
| `SSH_KEY` | Contenido completo de la llave privada del proyecto (`deploy_key`) |
| `VPS_HOST` | IP del VPS: `204.168.211.73` |
| `TOKEN` | (No usado por este repo, sí por los repos de monolitos para GHCR) |

### Limitaciones del CI/CD

- **No reinicia Nginx del sistema.** Si modificas un archivo de Nginx
  en `/etc/nginx/sites-available/quasar.conf`, debes hacer
  `systemctl reload nginx` manualmente en el VPS. Esto es intencional:
  el Nginx del sistema es compartido con otros proyectos del curso.

- **No corre migraciones de BD.** Las migraciones son responsabilidad
  de cada monolito.

---

## Comandos útiles

### En local o VPS

```bash
# Estado del stack
docker compose ps

# Logs en vivo
docker compose logs -f mysql
docker compose logs -f mongo

# Reiniciar un servicio
docker compose restart mysql

# Detener todo (preserva datos)
docker compose down

# Detener todo Y BORRAR datos (cuidado)
docker compose down -v

# Levantar después de cambios
docker compose up -d

# Forzar rebuild de imágenes
docker compose up -d --build
```

### Acceso directo a las BDs

```bash
# MySQL como root
docker exec -it quasar_mysql mysql -u root -p

# MySQL como usuario de app
docker exec -it quasar_mysql mysql -u users_app -p

# MongoDB como app
docker exec -it quasar_mongo mongosh \
  -u logs_app -p \
  --authenticationDatabase events_logs
```

### Validar Nginx del sistema (solo VPS)

```bash
nginx -t                  # valida sintaxis
systemctl status nginx    # estado del servicio
systemctl reload nginx    # recarga sin downtime
journalctl -u nginx -n 50 # últimas 50 líneas del log
```

---

## Troubleshooting

### MySQL en `Restarting` constante

Ver logs:

```bash
docker compose logs mysql
```

Causas comunes:

- **Variables vacías:** confirma que las variables del `.env` están bien
  declaradas en `docker-compose.yml` en `environment:` del servicio mysql.
- **Script de init falló:** revisa el log; si hay un error SQL,
  ejecuta `docker compose down -v` y vuelve a levantar para reintentar.

### "Address already in use" (puerto 80)

En el VPS, el puerto 80 está tomado por el **Nginx del sistema**.
No levantamos Nginx en Docker para evitar el choque.

### CI/CD falla con "could not read Username for https://github.com"

El repo debe estar en modo **Public** en GitHub, o el remote del
repo clonado en el VPS debe usar SSH con una Deploy Key.

Para cambiar a SSH:

```bash
cd /opt/quasar/events_infrastructure
git remote set-url origin git@github.com:tren-quazar-C6/events_infrastructure.git
```

### MongoDB no creó el usuario `logs_app`

El script `01_init.js` solo se ejecuta la **primera vez** que MongoDB
arranca con un volumen vacío. Si modificaste el script después,
para reaplicarlo:

```bash
docker compose down -v   # ⚠️ borra los datos
docker compose up -d
```

### El healthcheck de MySQL/Mongo no pasa a "healthy"

Espera 30-60 segundos. La primera vez tarda más porque inicializa el
volumen. Si después de 2 minutos sigue en `starting`, revisa logs.

---

## Roles del equipo

| Dev | Nombre | Responsabilidad |
|-----|--------|-----------------|
| Dev 1 | Jose | DB schema + backend `events_users` (Laravel) |
| Dev 2 | Verónica | Vistas y UI del portal Users |
| Dev 3 | Faiber | `events_tickets` + integración Wompi + n8n |
| Dev 4 | Luis Miguel | Infraestructura, Docker, Nginx, CI/CD (este repo) |

---

## Próximos pasos del setup

- [x] Fase A: Base de datos en VPS
- [x] Fase B: Nginx del sistema configurado
- [x] Fase C: CI/CD de `events_infrastructure`
- [ ] Fase D: Dockerfile + CI/CD de `events_admin`
- [ ] Fase E: Replicar a `events_tickets` y `events_access`
- [ ] Fase F: Dockerfile + CI/CD de `events_users` (Laravel)
- [ ] Fase G: HTTPS con Certbot

---

**Mantenedor:** Luis Miguel (Dev 4) · Quasar / Tren Quazar C6