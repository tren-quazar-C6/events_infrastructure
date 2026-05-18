# Guía de onboarding para devs

> Esta guía es para los 4 devs del equipo: **Jose, Verónica, Faiber, Luis Miguel**.
> Te explica cómo configurar tu entorno local para empezar a desarrollar.

---

## Tabla de contenido

- [Filosofía: tu PC ≠ el VPS](#filosofía-tu-pc--el-vps)
- [Lo que vas a montar en tu PC](#lo-que-vas-a-montar-en-tu-pc)
- [Pre-requisitos](#pre-requisitos)
- [Setup paso a paso](#setup-paso-a-paso)
- [Cómo conectas tu app a las BDs](#cómo-conectas-tu-app-a-las-bds)
- [Qué usuario MySQL te toca](#qué-usuario-mysql-te-toca)
- [Migraciones: el contrato compartido del schema](#migraciones-el-contrato-compartido-del-schema)
- [Reset de la BD local](#reset-de-la-bd-local)
- [Preguntas frecuentes](#preguntas-frecuentes)

---

## Filosofía: tu PC ≠ el VPS

**Cada dev trabaja contra su propia BD local. Nunca contra el VPS.**

El VPS es **producción**: solo recibe cambios vía CI/CD (`git push` → deploy automático). Si todos pegáramos nuestras pruebas locales al VPS, se rompería todo el tiempo.

```
TU PC (local)                      VPS (producción)
─────────────                      ────────────────
- Tu MySQL en Docker               - MySQL "real"
- Tu MongoDB en Docker             - MongoDB "real"
- Tu monolito conectado            - Apps deployadas vía CI/CD
- Datos de prueba                  - Datos reales (cuando lance el proyecto)
- Rompe lo que quieras             - INTOCABLE
```

**Resultado:** puedes experimentar, romper, resetear, lo que sea, sin afectar a nadie.

---

## Lo que vas a montar en tu PC

Cuando termines este setup tendrás:

- `events_infrastructure` clonado → levanta MySQL + MongoDB localmente
- Tu repo asignado clonado (`events_users`, `events_admin`, `events_tickets` o `events_access`)
- Tu app conectada a la BD local
- Todo funcionando en `http://localhost:<tu_puerto>`

---

## Pre-requisitos

Antes de empezar:

| Herramienta | Por qué | Cómo verificar |
|-------------|---------|----------------|
| **Git** | Clonar repos | `git --version` |
| **Docker Desktop** | Correr MySQL/Mongo | `docker --version` |
| **Docker Compose v2** | Orquestar el stack | `docker compose version` |
| **PHP 8.2+ y Composer** | Solo si tu repo es `events_users` (Laravel) | `php --version` y `composer --version` |
| **.NET SDK 8.0+** | Solo si tu repo es ASP.NET | `dotnet --version` |

Si alguno falla, instálalo antes de seguir.

---

## Setup paso a paso

### 1. Crear la carpeta contenedora

Vas a tener varios repos lado a lado. Crea una carpeta para todos:

```bash
# Windows (PowerShell)
mkdir C:\Users\TU_USUARIO\Documents\quasar
cd C:\Users\TU_USUARIO\Documents\quasar

# Mac/Linux
mkdir -p ~/quasar && cd ~/quasar
```

### 2. Clonar `events_infrastructure`

Este es el repo que levanta las bases de datos.

```bash
git clone https://github.com/tren-quazar-C6/events_infrastructure.git
cd events_infrastructure
```

### 3. Crear tu archivo `.env` local

```bash
# Windows
copy .env.example .env

# Mac/Linux
cp .env.example .env
```

**Importante:** Para desarrollo local, los valores placeholder del `.env.example` (`cambiame_users`, `cambiame_admin`, etc.) **son suficientes**. No necesitas passwords seguros en local porque tu MySQL solo es accesible desde tu PC.

**No pidas los passwords del VPS.** Esos son solo para producción y los gestiona Dev 4.

### 4. Levantar las BDs

```bash
docker compose up -d
```

Espera unos 30 segundos la primera vez (descarga las imágenes).

### 5. Verificar que arrancó bien

```bash
docker compose ps
```

Esperado:

```
NAME            STATUS                  PORTS
quasar_mongo    Up X seconds (healthy)  0.0.0.0:27017->27017/tcp
quasar_mysql    Up X seconds (healthy)  0.0.0.0:3306->3306/tcp
```

Si ambos están `healthy`, las BDs están listas.

### 6. Clonar tu repo asignado

```bash
cd ..   # Volver a ~/quasar

# Según tu rol, clona uno de estos:
git clone https://github.com/tren-quazar-C6/events_users.git      # Jose
git clone https://github.com/tren-quazar-C6/events_admin.git      # (asignar)
git clone https://github.com/tren-quazar-C6/events_tickets.git    # Faiber
git clone https://github.com/tren-quazar-C6/events_access.git     # (asignar)
```

### 7. Configurar tu monolito

Cada repo tiene su propia documentación. Sigue el README de tu repo asignado.

---

## Cómo conectas tu app a las BDs

Tu MySQL y MongoDB locales están expuestos en estos puertos de tu PC:

| BD | Host | Puerto | BD por defecto |
|----|------|--------|----------------|
| MySQL | `localhost` o `127.0.0.1` | `3306` | `events` |
| MongoDB | `localhost` o `127.0.0.1` | `27017` | `events_logs` |

### Ejemplo: Laravel (events_users)

En tu `.env` de Laravel (DENTRO del repo `events_users`):

```bash
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=events
DB_USERNAME=users_app
DB_PASSWORD=cambiame_users
```

El password es el mismo que está en el `.env` de `events_infrastructure`. **Son los placeholders locales, no los del VPS.**

### Ejemplo: ASP.NET (events_admin, tickets, access)

En tu `appsettings.Development.json`:

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

---

## Qué usuario MySQL te toca

Cada dev usa **su propio usuario MySQL**, no root. Esto es por seguridad: en producción cada app solo tiene permisos sobre lo que necesita.

| Dev | Repo | Usuario MySQL | Password (local) |
|-----|------|---------------|------------------|
| Jose | `events_users` | `users_app` | `cambiame_users` |
| (asignar) | `events_admin` | `admin_app` | `cambiame_admin` |
| Faiber | `events_tickets` | `tickets_app` | `cambiame_tickets` |
| (asignar) | `events_access` | `access_app` | `cambiame_access` |

**Todos pueden leer/escribir sobre la BD `events` completa por ahora.** Cuando definamos las tablas finales, los grants se refinarán por tabla.

---

## Migraciones: el contrato compartido del schema

Aunque cada dev tiene su BD local, **todos comparten la misma estructura de tablas**. Eso se logra con migraciones versionadas en Git.

### En Laravel (Jose)

```bash
# Crear una migración nueva
php artisan make:migration create_events_table

# Aplicar todas las migraciones a tu BD local
php artisan migrate

# Llenar con datos de prueba
php artisan db:seed

# Si quieres empezar desde cero
php artisan migrate:fresh --seed
```

Cuando creas una migración, **commitea el archivo** en `database/migrations/`. Los demás devs harán `git pull` y corren `php artisan migrate` para aplicarla.

### En ASP.NET con EF Core

```bash
# Crear una migración
dotnet ef migrations add NombreDescriptivo

# Aplicar a tu BD local
dotnet ef database update

# Empezar desde cero
dotnet ef database drop
dotnet ef database update
```

### ⚠️ Coordinación entre devs

Como **una sola BD MySQL** es compartida por los 4 monolitos, los 4 devs deben coordinar qué tablas crea cada uno para evitar:

- Conflictos de nombres
- Migraciones que se pisan
- Definiciones inconsistentes de una misma tabla

**Sugerencia:** mantener un documento (`docs/DATABASE_SCHEMA.md` en `events_infrastructure`) con la lista de tablas y quién las posee. Antes de crear una migración, revisar ese documento.

---

## Reset de la BD local

Si rompiste algo o quieres empezar de cero:

```bash
cd ~/quasar/events_infrastructure
docker compose down -v
docker compose up -d
```

El `-v` borra los volúmenes (los datos). Los usuarios y la BD `events` se vuelven a crear automáticamente desde los scripts de init.

Después, vuelve a correr las migraciones de tu monolito:

```bash
# Laravel
php artisan migrate:fresh --seed

# ASP.NET
dotnet ef database update
```

---

## Preguntas frecuentes

### ¿Puedo conectarme a la BD del VPS desde mi PC?

**Técnicamente sí, pero NO lo hagas.**

El VPS es producción. Si todos conectamos nuestros desarrollos ahí, se rompe constantemente. Trabaja contra tu BD local.

### ¿Necesito los passwords del VPS para algo?

**No.** Los passwords del VPS son solo para:
- El CI/CD que deploya las apps al VPS
- Dev 4 que administra el servidor

Tu app local **nunca** debe conectarse al VPS. Tu CI/CD se encarga de eso por ti.

### ¿Cómo veo lo que está pasando en MySQL/Mongo?

Recomiendo herramientas gráficas:

- **MySQL:** DBeaver, MySQL Workbench, TablePlus
- **MongoDB:** MongoDB Compass

Conectas con `localhost:3306` o `localhost:27017` y tus credenciales locales.

### ¿Qué pasa si cambio el .env de events_infrastructure?

El `.env` de tu PC es solo tuyo (está en `.gitignore`). Cámbialo lo que quieras.

Si quieres agregar una variable nueva al stack, agrégala también al `.env.example` y comméntala en el repo para que los demás devs la tengan.

### ¿Cómo despliego mi código al VPS?

No despliegas tú. **Haces `git push` y el CI/CD lo deploya automáticamente.**

Cada repo de monolito tiene su workflow de GitHub Actions configurado por Dev 4.

### Si tengo dudas técnicas sobre infra/Docker/CI/CD, ¿a quién pregunto?

A **Dev 4 (Luis Miguel)**. Es el responsable de toda la infraestructura.

### ¿Y si la BD del VPS está caída?

Avísale a Dev 4. Mientras tanto, tu desarrollo local no se ve afectado porque trabajas contra tu BD local.

---

## Resumen visual del flujo

```
┌─────────────────────────────────────────────────────────────┐
│ TU PC                                                        │
│                                                              │
│  ┌────────────────────┐      ┌────────────────────┐       │
│  │ events_infra (local)│      │ tu_repo (local)    │       │
│  │ - MySQL :3306       │◄─────│ - Tu app           │       │
│  │ - MongoDB :27017    │      │ - localhost:XXXX   │       │
│  └────────────────────┘      └────────────────────┘       │
│                                       │                      │
└───────────────────────────────────────┼──────────────────────┘
                                        │ git push
                                        ▼
┌─────────────────────────────────────────────────────────────┐
│ GITHUB                                                       │
│  Actions ejecuta el workflow                                │
└──────────────────────────────────┬──────────────────────────┘
                                   │ SSH al VPS
                                   ▼
┌─────────────────────────────────────────────────────────────┐
│ VPS (producción)                                             │
│  ┌────────────────────┐      ┌────────────────────┐       │
│  │ events_infra (VPS)  │      │ tu_repo (VPS)      │       │
│  │ - MySQL :3306       │◄─────│ - Tu app deployada │       │
│  │ - MongoDB :27017    │      │ - tu_subdominio    │       │
│  └────────────────────┘      └────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

**Si tienes dudas, pregunta. Mejor preguntar 5 veces que romper algo en producción.**