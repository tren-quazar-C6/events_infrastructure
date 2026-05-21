# ONBOARDING.md

> Guía de onboarding para devs del proyecto **Quasar (Tickify)**.
> Si eres nuevo en el proyecto o tomaste el rol de Dev 4, este documento es tu punto de partida.
> Responsable original: Dev 4 — Luis Miguel
> Última actualización: Mayo 2026

---

## Tabla de contenido

- [Contexto del proyecto](#contexto-del-proyecto)
- [Roles del equipo](#roles-del-equipo)
- [Regla fundamental: tu PC ≠ el VPS](#regla-fundamental-tu-pc--el-vps)
- [Pre-requisitos](#pre-requisitos)
- [Setup local paso a paso](#setup-local-paso-a-paso)
- [Cómo conecta tu app a las BDs](#cómo-conecta-tu-app-a-las-bds)
- [Qué usuario MySQL te toca](#qué-usuario-mysql-te-toca)
- [Migraciones y schema compartido](#migraciones-y-schema-compartido)
- [Cómo deployar tus cambios](#cómo-deployar-tus-cambios)
- [Cómo crear un release con SemVer](#cómo-crear-un-release-con-semver)
- [Si tomaste el rol de Dev 4](#si-tomaste-el-rol-de-dev-4)
- [Preguntas frecuentes](#preguntas-frecuentes)

---

## Contexto del proyecto

Quasar es un sistema de venta de boletas para teatro. Tiene 4 portales MVC server-side y 3 APIs REST, todos corriendo en un VPS compartido.

```
tren-quazar-C6/ (organización en GitHub)
├── events_infrastructure   ← orquestación central (Dev 4)
├── events_users            ← portal users (Laravel)
├── events_admin            ← portal admin (ASP.NET MVC)
├── events_tickets          ← portal tickets (ASP.NET MVC)
├── events_access           ← portal access (ASP.NET MVC)
├── events_api_admin        ← API admin (ASP.NET Web API)
├── events_api_tickets      ← API tickets (ASP.NET Web API)
└── events_api_access       ← API access (ASP.NET Web API)
```

**Una sola BD MySQL** llamada `events`, compartida por todos.
**Un MongoDB** llamado `events_logs`, solo para auditoría.

---

## Roles del equipo

| Dev | Nombre | Responsabilidad |
|-----|--------|-----------------|
| Dev 1 | Jose | DB schema + backend `events_users` (Laravel) |
| Dev 2 | Verónica | Vistas y UI del portal Users (Blade) |
| Dev 3 | Faiber | `events_tickets` + integración Wompi + n8n |
| Dev 4 | Luis Miguel | Infraestructura, Docker, Nginx, CI/CD (este repo) |

---

## Regla fundamental: tu PC ≠ el VPS

**Nunca trabajes contra la BD del VPS. Siempre usa tu BD local.**

```
TU PC (desarrollo local)         VPS (producción)
────────────────────────         ────────────────
- Tu MySQL en Docker             - MySQL de producción
- Tu MongoDB en Docker           - MongoDB de producción
- Tu monolito local              - Apps deployadas automáticamente
- Datos de prueba                - Datos reales
- Rompe lo que quieras           - INTOCABLE
```

El VPS solo recibe cambios vía CI/CD (git push → deploy automático). Nadie hace cambios directamente en el VPS excepto Dev 4 para tareas de infraestructura.

---

## Pre-requisitos

Antes de empezar verifica que tienes instalado:

| Herramienta | Verificar con | Para qué |
|-------------|--------------|---------|
| Git | `git --version` | Clonar repos |
| Docker Desktop | `docker --version` | Correr MySQL/MongoDB local |
| Docker Compose v2 | `docker compose version` | Orquestar el stack |
| PHP 8.4 + Composer | `php --version` y `composer --version` | Solo para `events_users` y `events_api_users` |
| .NET SDK 10.0 | `dotnet --version` | Para repos ASP.NET |

---

## Setup local paso a paso

### 1. Crear carpeta contenedora

```bash
# Windows (PowerShell)
mkdir C:\Users\TU_USUARIO\Documents\quasar
cd C:\Users\TU_USUARIO\Documents\quasar

# Mac/Linux
mkdir -p ~/quasar && cd ~/quasar
```

### 2. Clonar events_infrastructure

```bash
git clone https://github.com/tren-quazar-C6/events_infrastructure.git
cd events_infrastructure
```

### 3. Crear tu .env local

```bash
# Windows
copy .env.example .env

# Mac/Linux
cp .env.example .env
```

Para desarrollo local, los valores placeholder del `.env.example` (`cambiame_*`) son suficientes. **No uses ni pidas los passwords del VPS.**

### 4. Levantar las BDs locales

```bash
docker compose up -d
```

La primera vez descarga las imágenes (MySQL ~500MB, MongoDB ~700MB). Espera 2-3 minutos.

### 5. Verificar que están healthy

```bash
docker compose ps
```

Debes ver:

```
NAME            STATUS                  PORTS
quasar_mongo    Up X seconds (healthy)  0.0.0.0:27017->27017/tcp
quasar_mysql    Up X seconds (healthy)  0.0.0.0:3306->3306/tcp
```

Si alguno está en `starting` espera 30 segundos más. Si está en `Restarting`, hay un error — ver logs con `docker compose logs mysql`.

### 6. Clonar tu repo asignado

```bash
cd ..   # volver a ~/quasar

# Clona según tu rol:
git clone https://github.com/tren-quazar-C6/events_users.git      # Jose / Verónica
git clone https://github.com/tren-quazar-C6/events_admin.git      # según asignación
git clone https://github.com/tren-quazar-C6/events_tickets.git    # Faiber
git clone https://github.com/tren-quazar-C6/events_access.git     # según asignación
git clone https://github.com/tren-quazar-C6/events_api_admin.git
git clone https://github.com/tren-quazar-C6/events_api_tickets.git
git clone https://github.com/tren-quazar-C6/events_api_access.git
```

### 7. Configurar y levantar tu monolito

Sigue el README de tu repo específico. En general:

**Para Laravel:**
```bash
cd events_users
composer install
cp .env.example .env
php artisan key:generate
# Editar .env con los datos de conexión a tu MySQL local (ver sección más abajo)
php artisan migrate
npm install
npm run build
php artisan serve
```

**Para ASP.NET:**
```bash
cd events_admin
dotnet restore
# Editar appsettings.Development.json con los datos de conexión
dotnet ef database update
dotnet run
```

---

## Cómo conecta tu app a las BDs

Tu MySQL y MongoDB locales están en:

| BD | Host | Puerto | BD |
|----|------|--------|-----|
| MySQL | `127.0.0.1` | `3306` | `events` |
| MongoDB | `127.0.0.1` | `27017` | `events_logs` |

### En Laravel (.env de events_users)

```bash
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=events
DB_USERNAME=users_app
DB_PASSWORD=cambiame_users   # el valor de tu .env local de infrastructure
```

### En ASP.NET (appsettings.Development.json)

```json
{
  "ConnectionStrings": {
    "MySQL": "Server=127.0.0.1;Port=3306;Database=events;User=admin_app;Password=cambiame_admin;"
  },
  "MongoDB": {
    "ConnectionString": "mongodb://logs_app:cambiame_mongo@127.0.0.1:27017/events_logs?authSource=events_logs",
    "Database": "events_logs"
  }
}
```

**El password es el que está en el `.env` de `events_infrastructure` en tu PC, no el del VPS.**

---

## Qué usuario MySQL te toca

| Dev | Repo | Usuario MySQL | Password (local) |
|-----|------|---------------|------------------|
| Jose | `events_users` | `users_app` | `cambiame_users` |
| (asignado) | `events_admin` | `admin_app` | `cambiame_admin` |
| Faiber | `events_tickets` | `tickets_app` | `cambiame_tickets` |
| (asignado) | `events_access` | `access_app` | `cambiame_access` |
| (asignado) | `events_api_admin` | `admin_app` | `cambiame_admin` |
| (asignado) | `events_api_tickets` | `tickets_app` | `cambiame_tickets` |
| (asignado) | `events_api_access` | `access_app` | `cambiame_access` |

Todos los usuarios tienen acceso completo a la BD `events` localmente. En producción los grants se refinarán cuando el schema esté definido.

---

## Migraciones y schema compartido

Aunque cada dev tiene su BD local, todos comparten la misma estructura de tablas. Las migraciones versionadas en Git son el contrato compartido.

### En Laravel

```bash
# Aplicar todas las migraciones
php artisan migrate

# Llenar con datos de prueba
php artisan db:seed

# Empezar desde cero (⚠️ borra tus datos locales)
php artisan migrate:fresh --seed
```

Cuando crees una migración nueva, commitea el archivo en `database/migrations/`. Los demás hacen `git pull` y corren `php artisan migrate`.

### En ASP.NET con EF Core

```bash
# Aplicar migraciones
dotnet ef database update

# Crear migración nueva
dotnet ef migrations add NombreDescriptivo

# Empezar desde cero (⚠️ borra tus datos locales)
dotnet ef database drop
dotnet ef database update
```

### Coordinación importante

Los 4 monolitos comparten la misma BD `events`. Antes de crear tablas nuevas, revisar `docs/DATABASE_SCHEMA.md` en `events_infrastructure` para evitar conflictos de nombres.

### Reset de BD local

Si rompiste algo o quieres empezar desde cero:

```bash
cd ~/quasar/events_infrastructure
docker compose down -v   # ⚠️ borra los datos
docker compose up -d     # recrea BDs vacías

# Luego en tu monolito:
php artisan migrate:fresh --seed   # Laravel
# o
dotnet ef database update           # ASP.NET
```

---

## Cómo deployar tus cambios

Es simple: **haz push a main**. El CI/CD hace el resto.

```bash
git add .
git commit -m "feat: descripción de lo que hiciste"
git push origin main
```

Ve a `https://github.com/tren-quazar-C6/TU_REPO/actions` y verás el workflow corriendo. En 3-5 minutos tus cambios estarán en producción.

### Qué hace el CI/CD automáticamente

1. Descarga tu código en un runner de Ubuntu (cloud de GitHub)
2. Buildea la imagen Docker
3. La sube a GHCR con tags `:latest` y `:<sha>`
4. SSH al VPS
5. Baja la imagen nueva
6. Reemplaza el container sin tocar MySQL ni MongoDB
7. Limpia imágenes viejas

### Si el workflow falla

Ve al run fallido en GitHub Actions, haz click en el job rojo y lee el log. Los errores más comunes están en `CICD.md → Qué pasa si falla el pipeline`.

---

## Cómo crear un release con SemVer

Los pushes a `main` generan imágenes con `:latest` y `:<sha>`. Para generar versiones semánticas visibles en GHCR (`1.0.0`, `1.0`, `1`), usa tags de Git.

```bash
# Decidir el tipo de cambio:
# v1.0.0 → primer release
# v1.1.0 → funcionalidad nueva
# v1.0.1 → bug fix

# Crear y pushear el tag
git tag v1.0.0 -m "Release v1.0.0: descripción breve"
git push origin v1.0.0
```

El workflow detecta el tag y genera automáticamente los 3 tags semánticos en GHCR.

**Cuándo crear un tag:**

| Tipo | Cuándo | Ejemplo |
|------|--------|---------|
| `vX.0.0` | Cambio que rompe compatibilidad | Cambiar estructura de respuesta de la API |
| `vX.Y.0` | Funcionalidad nueva | Agregar endpoint de búsqueda |
| `vX.Y.Z` | Bug fix | Arreglar error 500 en login |

---

## Si tomaste el rol de Dev 4

Bienvenido al rol más crítico del proyecto. Aquí tienes todo lo que necesitas saber para continuar.

### Acceso al VPS

```bash
# Desde Windows (PowerShell)
ssh -i C:\Users\User\Documents\quasar\secrets\deploy_key root@204.168.211.73

# Desde Mac/Linux
ssh -i ~/quasar/secrets/deploy_key root@204.168.211.73
```

La llave `deploy_key` debe estar en la ruta indicada. Si no la tienes, pídela al Dev 4 anterior (Luis Miguel). **Nunca subas la llave privada a Git.**

### Directorio del proyecto en el VPS

```
/opt/quasar/events_infrastructure/
```

Ahí están el `docker-compose.yml`, el `.env` real (con passwords de producción), y los scripts de init.

### Tus responsabilidades como Dev 4

1. **Mantener el stack corriendo:** si un container falla, diagnosticar y arreglarlo
2. **Agregar servicios nuevos:** cuando el equipo cree un nuevo repo, agregar su bloque al compose
3. **Actualizar el .env del VPS:** cuando alguien agregue una variable nueva a `.env.example`, agregar el valor real al VPS
4. **Gestionar Nginx:** cuando hay nuevos subdominios, agregar los `server` blocks
5. **HTTPS:** cuando hay subdominios nuevos, correr `certbot --nginx` para emitir certificados
6. **Mantener documentación:** si algo cambia, actualizar los archivos en `docs/`

### Comandos de diagnóstico del VPS

```bash
# Estado de todos los containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Ver logs de un container
docker compose logs --tail=50 admin
docker compose logs -f api-admin   # en vivo

# Uso de disco
df -h
docker system df

# Reiniciar un container específico
cd /opt/quasar/events_infrastructure
docker compose restart admin

# Aplicar cambios del compose manualmente
cd /opt/quasar/events_infrastructure
git pull origin main
docker compose up -d

# Ver el .env de producción
cat /opt/quasar/events_infrastructure/.env

# Editar el .env de producción
nano /opt/quasar/events_infrastructure/.env

# Ver certificados HTTPS
certbot certificates

# Validar Nginx antes de recargar
nginx -t

# Recargar Nginx (sin downtime)
systemctl reload nginx
```

### Agregar un nuevo monolito o API al stack

**Orden obligatorio:** siempre infrastructure primero, después el repo del monolito.

1. Agregar bloque del servicio al `docker-compose.yml` local
2. Agregar variables al `.env.example`
3. Commit + push a `events_infrastructure` → el compose se actualiza en el VPS
4. (Opcional) Si hay nuevo subdominio: agregar server block en Nginx del VPS, `nginx -t`, `systemctl reload nginx`, `certbot --nginx`
5. Hacer push del nuevo repo → el pipeline buildea la imagen y deploya
6. Agregar el valor real de las variables nuevas al `.env` del VPS

### Passwords del VPS

Los passwords de producción están SOLO en el `.env` del VPS:

```bash
cat /opt/quasar/events_infrastructure/.env
```

Mantén una copia de respaldo en un gestor de passwords seguro (no en Slack, WhatsApp, ni Google Docs). Si el VPS explota y no tienes el `.env`, pierdes acceso a las BDs.

### Lo que está pendiente de implementar

- DNS para los subdominios de las 3 APIs (el profe los entrega cuando estén)
- Server blocks de Nginx para las APIs (cuando lleguen los DNS)
- HTTPS de las APIs vía Certbot (después de Nginx)
- Variables de `JWT_SECRET`, `WOMPI_*`, `N8N_*`, `SMTP_*` — agregar al `.env` del VPS cuando cada feature se implemente

---

## Preguntas frecuentes

### ¿Puedo conectarme a la BD del VPS desde mi PC?

Técnicamente sí (el puerto 3306 está expuesto). Pero **no lo hagas**. Es producción. Trabaja contra tu BD local.

### ¿Dónde están los passwords del VPS?

Solo Dev 4 los tiene. Si los necesitas para algo específico, habla con Dev 4 directamente. Nunca se comparten por chat.

### ¿Cómo sé si mi deploy llegó al VPS?

Ve a `https://github.com/tren-quazar-C6/TU_REPO/actions`. El workflow en verde con un check ✅ confirma que el deploy fue exitoso.

### ¿Qué pasa si rompí algo en el VPS?

Si tus cambios rompieron el container, el container viejo ya no existe. El nuevo está fallando. Solución:

1. Haz rollback de tu código en Git (`git revert HEAD`)
2. Push a main
3. El pipeline deploylará la versión anterior

### ¿Puedo hacer cambios directamente en el VPS?

Solo Dev 4 hace cambios en el VPS, y solo para tareas de infraestructura (Nginx, .env, diagnóstico). Nunca edites código de los monolitos directamente en el VPS.

### ¿Cómo desarrollo sin internet?

Las BDs locales son completamente independientes del VPS. Si no hay internet, igual puedes levantar `events_infrastructure` local y trabajar normalmente.

### El CI/CD está fallando, ¿qué hago?

1. Ve a GitHub Actions del repo y lee el log del job rojo
2. Si el error está en `build-and-push`: es un problema del Dockerfile o del código
3. Si el error está en `deploy`: es un problema de infraestructura → habla con Dev 4
4. Consulta `CICD.md → Qué pasa si falla el pipeline` para errores comunes

### ¿Cómo agrego una variable de entorno nueva?

1. Agregar la variable a `events_infrastructure/.env.example` con un valor placeholder
2. Commit + push a `events_infrastructure`
3. Avisar a Dev 4 para que agregue el valor real al `.env` del VPS
4. Usar la variable en tu código leyéndola del entorno (`Environment.GetEnvironmentVariable(...)` en .NET o `env('VARIABLE')` en Laravel)

### ¿Cómo funciona el DNS del dominio?

El dominio `andrescortes.dev` lo administra el profe (o el dueño del DNS). Los subdominios están configurados como registros A apuntando a `204.168.211.73`. Cuando el profe crea un nuevo subdominio, Dev 4 agrega el server block en Nginx y emite el certificado HTTPS.

### ¿Qué es GHCR?

GitHub Container Registry. Es donde se guardan las imágenes Docker del proyecto. Puedes verlas en:

```
https://github.com/orgs/tren-quazar-C6/packages
```

Cada repo tiene su propia imagen. Los tags incluyen `:latest`, el SHA del commit, y las versiones semánticas cuando se crea un release.

---

## Flujo completo de trabajo

```
┌─────────────────────────────────────────────────────────────────┐
│ TU PC                                                           │
│                                                                 │
│  ┌────────────────────┐    ┌────────────────────┐               │ 
│  │ events_infra local  │    │ tu_repo local       │             │
│  │ docker compose up   │◄───│ Tu app en local     │             │
│  │ - MySQL :3306       │    │ localhost:XXXX      │             │
│  │ - MongoDB :27017    │    │                     │             │
│  └────────────────────┘    └────────────────────┘               │
│                                      │                          │
└──────────────────────────────────────┼──────────────────────────┘
                                       │ git push origin main
                                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ GITHUB ACTIONS                                                  │
│  Job 1: docker build + push a GHCR                              │
│  Job 2: SSH al VPS → docker compose pull → up                   │
└──────────────────────────────┬──────────────────────────────────┘
                               │ SSH deploy
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ VPS 204.168.211.73 (producción)                                 │
│                                                                 │
│  Nginx ──► quasar.andrescortes.dev      ──► quasar_users:8100   │
│        ──► admin.quasar.andrescortes.dev──► quasar_admin:8101   │
│        ──► tickets.quasar...            ──► quasar_tickets:8102 │
│        ──► access.quasar...             ──► quasar_access:8103  │
│                                                                 │
│  quasar_mysql (3306) ◄── todos los containers                   │
│  quasar_mongo (27017) ◄── todos los containers (logs)           │
└─────────────────────────────────────────────────────────────────┘
```

---

**Si tienes dudas, pregunta antes de hacer algo en el VPS.**
**El VPS es compartido con otros equipos del curso.**

Responsable de esta documentación: Dev 4 — Luis Miguel  
Organización GitHub: `tren-quazar-C6`