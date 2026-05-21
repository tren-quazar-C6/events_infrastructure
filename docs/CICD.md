# CICD.md

> Documentación del pipeline de CI/CD del proyecto **Quasar (Tickify)**.
> Responsable original: Dev 4 — Luis Miguel
> Última actualización: Mayo 2026

---

## Tabla de contenido

- [Visión general](#visión-general)
- [Cómo funciona el flujo completo](#cómo-funciona-el-flujo-completo)
- [Lo que hace posible el CI/CD](#lo-que-hace-posible-el-cicd)
- [Secrets de GitHub](#secrets-de-github)
- [Pipeline de los monolitos ASP.NET](#pipeline-de-los-monolitos-aspnet)
- [Pipeline de los monolitos Laravel](#pipeline-de-los-monolitos-laravel)
- [Pipeline de events_infrastructure](#pipeline-de-events_infrastructure)
- [Versionado semántico SemVer 2.0.0](#versionado-semántico-semver-200)
- [Cómo hacer un deploy manual](#cómo-hacer-un-deploy-manual)
- [Cómo hacer un rollback](#cómo-hacer-un-rollback)
- [Qué pasa si falla el pipeline](#qué-pasa-si-falla-el-pipeline)

---

## Visión general

Cada repositorio tiene su propio pipeline de GitHub Actions. Cuando un dev hace `git push` a `main`, el pipeline automáticamente:

1. Buildea la imagen Docker
2. La sube a GitHub Container Registry (GHCR)
3. SSH al VPS y actualiza el container

```
git push origin main
      ↓
GitHub detecta push en rama main
      ↓
GitHub Actions inicia un runner (Ubuntu en la nube de GitHub)
      ↓
Job 1: build-and-push
   - Descarga el código
   - docker build (usando el Dockerfile del repo)
   - docker push a GHCR
      ↓ (solo si Job 1 pasó ✅)
Job 2: deploy
   - SSH al VPS
   - docker compose pull <servicio>
   - docker compose up -d --no-deps <servicio>
      ↓
Container nuevo corriendo en el VPS
      ↓
Nginx enruta el dominio al nuevo container
      ↓
Usuario accede y ve los cambios
```

**Tiempo total:** 3-5 minutos desde el push hasta que el cambio está en producción.

---

## Cómo funciona el flujo completo

### Paso 1: git push

```bash
cd events_admin
git add .
git commit -m "feat: botón rojo en dashboard"
git push origin main
```

El código sube a `https://github.com/tren-quazar-C6/events_admin`. GitHub detecta el push a `main` y activa el workflow.

---

### Paso 2: Job 1 — build-and-push

El runner de GitHub ejecuta estos pasos:

**`actions/checkout@v4`**
Clona el repo en el runner para tener acceso al código y al Dockerfile.

**`docker/setup-buildx-action@v3`**
Prepara Docker para buildear imágenes multi-arquitectura.

**`actions/cache@v4`**
Cachea los layers de Docker de compilaciones anteriores. La primera vez tarda 5-10 min, las siguientes 2-3 min porque reutiliza lo que no cambió. Cada repo tiene su propia clave de cache:

| Repo | Cache key |
|------|-----------|
| events_admin | `buildx-admin` |
| events_tickets | `buildx-tickets` |
| events_access | `buildx-access` |
| events_users | `buildx-users` |
| events_api_admin | `buildx-api-admin` |
| events_api_tickets | `buildx-api-tickets` |
| events_api_access | `buildx-api-access` |

**`docker/login-action@v3` con `GITHUB_TOKEN`**
Se autentica contra GHCR usando el token temporal que GitHub inyecta automáticamente en cada workflow. Este token es distinto al `TOKEN` secret que configuramos.

**Build and push**
```bash
IMAGE=ghcr.io/tren-quazar-c6/events_admin   # siempre lowercase

docker build -f Dockerfile \
  -t $IMAGE:latest \
  -t $IMAGE:<sha_del_commit> \
  .

docker push $IMAGE:latest
docker push $IMAGE:<sha_del_commit>

# Si es un tag v1.2.3, también pushea:
docker push $IMAGE:1.2.3
docker push $IMAGE:1.2
docker push $IMAGE:1
```

---

### Paso 3: Job 2 — deploy

**Solo corre si Job 1 terminó con ✅.** Si Job 1 falla, el VPS no se toca y el container viejo sigue corriendo.

```bash
# En el VPS (ejecutado vía SSH por appleboy/ssh-action):

set -e   # abort si cualquier comando falla

# Autenticarse en GHCR con el PAT (TOKEN secret)
echo "$TOKEN" | docker login ghcr.io -u $GITHUB_ACTOR --password-stdin

# Ir al compose centralizado
cd /opt/quasar/events_infrastructure

# Bajar la imagen nueva
docker compose pull admin

# Levantar el container sin tocar los demás
docker compose up -d --no-deps admin
# ↑ --no-deps es crítico: sin él, recrearía MySQL y Mongo también

# Limpiar imágenes viejas para no llenar el disco
docker image prune -f

# Verificar que quedó corriendo
docker compose ps admin
```

---

## Lo que hace posible el CI/CD

Son 5 piezas. Si falta una, el CI/CD no funciona.

### 1. El Dockerfile

Sin él no hay imagen que buildear. Cada repo tiene el suyo en la raíz.

**ASP.NET (events_admin, events_tickets, events_access, events_api_*):**
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY *.csproj ./
RUN dotnet restore
COPY . ./
RUN dotnet publish -c Release -o /out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /out ./
EXPOSE 8080
ENTRYPOINT ["dotnet", "events_admin.dll"]
# ⚠️ Nunca poner comentarios en la línea del ENTRYPOINT
```

**Laravel (events_users):**
El Dockerfile de Laravel usa `php artisan serve` como entrypoint, expone el puerto 8000.

### 2. El docker-compose.yml en events_infrastructure

Define cómo cada container se conecta a MySQL, MongoDB y a la red interna. Sin el bloque del servicio en el compose, el deploy falla con `no such service`.

Si se agrega un nuevo repo, primero hay que agregar su bloque al compose en `events_infrastructure` y hacer push, ANTES de hacer push del nuevo repo.

### 3. Los 3 secrets de GitHub

Deben estar configurados en **cada repo** en `Settings → Secrets → Actions`:

| Secret | Valor | Para qué |
|--------|-------|---------|
| `SSH_KEY` | Llave privada del proyecto (`deploy_key`) | Conectarse al VPS por SSH |
| `VPS_HOST` | `204.168.211.73` | Saber a qué IP conectarse |
| `TOKEN` | PAT de GHCR | Que el VPS pueda hacer `docker pull` |

### 4. La llave pública en el VPS

La contraparte de `SSH_KEY` (la llave pública) está en `~/.ssh/authorized_keys` del VPS. Permite que GitHub Actions se conecte por SSH sin password.

```bash
# Verificar que está configurada
cat ~/.ssh/authorized_keys
```

### 5. El Nginx del VPS

Mapea el dominio al puerto del container. Sin el `server` block del subdominio en `/etc/nginx/sites-available/quasar.conf`, el container corre pero nadie puede accederlo desde internet.

---

## Secrets de GitHub

Los 3 secrets deben estar en los 8 repos de monolitos y APIs. El repo `events_infrastructure` solo necesita `SSH_KEY` y `VPS_HOST`.

### Cómo verificar que están configurados

En GitHub: `Repo → Settings → Secrets and variables → Actions`

Deben aparecer:
- `SSH_KEY` ✓
- `TOKEN` ✓
- `VPS_HOST` ✓

### La llave SSH del proyecto

La llave privada (`deploy_key`) vive en:

```
C:\Users\User\Documents\quasar\secrets\deploy_key      ← privada (en tu PC)
C:\Users\User\Documents\quasar\secrets\deploy_key.pub  ← pública
```

La pública está en:
- `~/.ssh/authorized_keys` del VPS
- Como secret `SSH_KEY` (la privada) en los repos de GitHub

**NUNCA subir la llave privada a Git.**

### El PAT de GHCR (TOKEN)

Es un Personal Access Token generado en GitHub con permisos `write:packages` + `read:packages`. Permite:
- Al workflow (Job 1): subir imágenes a GHCR con `GITHUB_TOKEN` (auto-inyectado, no necesita el PAT)
- Al VPS (Job 2): bajar imágenes de GHCR con el PAT

Si el PAT expira, los deploys van a fallar con `unauthorized` al hacer `docker pull`.

---

## Pipeline de los monolitos ASP.NET

Aplica a: `events_admin`, `events_tickets`, `events_access`, `events_api_admin`, `events_api_tickets`, `events_api_access`.

Archivo: `.github/workflows/pipeline-dotnet.yml`

Las únicas diferencias entre los 6 pipelines:

| Repo | Cache key | Servicio en compose | Mensaje en logs |
|------|-----------|---------------------|----------------|
| events_admin | `buildx-admin` | `admin` | events_admin |
| events_tickets | `buildx-tickets` | `tickets` | events_tickets |
| events_access | `buildx-access` | `access` | events_access |
| events_api_admin | `buildx-api-admin` | `api-admin` | events_api_admin |
| events_api_tickets | `buildx-api-tickets` | `api-tickets` | events_api_tickets |
| events_api_access | `buildx-api-access` | `api-access` | events_api_access |

Todo lo demás es idéntico porque usa variables dinámicas de GitHub (`${{ github.repository }}` se resuelve automáticamente al nombre del repo).

---

## Pipeline de los monolitos Laravel

Aplica a: `events_users`, `events_api_users`.

Archivo: `.github/workflows/pipeline-laravel.yml`

El Job 2 (deploy) es idéntico al de ASP.NET. El Job 1 usa imágenes PHP en lugar de .NET. Las variables de cache y servicio cambian igual que en ASP.NET.

---

## Pipeline de events_infrastructure

Archivo: `.github/workflows/deploy.yml`

Este pipeline es diferente. No buildea ninguna imagen. Solo hace:

1. SSH al VPS
2. `git pull origin main` — baja los cambios del repo (docker-compose.yml, scripts, etc.)
3. `docker compose up -d` — aplica los cambios al stack

```yaml
script: |
  set -e
  cd /opt/quasar/events_infrastructure
  git pull origin main
  docker compose up -d
  docker compose ps
  echo "✓ Deploy completado"
```

**Cuándo se dispara:** cada push a `main` del repo `events_infrastructure`.

**Qué puede tocar:** TODOS los servicios del stack. Si el push incluye cambios al compose que agregan un nuevo servicio, intentará levantarlo. Si la imagen no existe en GHCR, fallará ese servicio pero los demás siguen intactos.

**Limitación importante:** este pipeline NO modifica Nginx del sistema. Los cambios de Nginx son siempre manuales en el VPS.

---

## Versionado semántico SemVer 2.0.0

### Por qué SemVer

Sin SemVer, las imágenes en GHCR se ven así:
```
events_admin:latest
events_admin:abc123def456   ← SHA del commit, no dice nada
```

Con SemVer:
```
events_admin:latest
events_admin:1.0.0
events_admin:1.0
events_admin:1
```

Comunica claramente el estado del proyecto y permite hacer rollbacks a versiones específicas.

### Convención de versiones

```
MAJOR.MINOR.PATCH

MAJOR → cambio que rompe compatibilidad (nueva estructura de API, cambio de schema)
MINOR → funcionalidad nueva sin romper nada (nuevo endpoint, nueva vista)
PATCH → corrección de bug (arreglo de error, ajuste visual)
```

### Cómo crear un release

```bash
# Asegurarse de estar en main con todo commiteado
git checkout main
git pull origin main

# Crear el tag con mensaje descriptivo
git tag v1.0.0 -m "Release v1.0.0: setup inicial"
git tag v1.1.0 -m "Release v1.1.0: agregar listado de eventos"
git tag v1.1.1 -m "Release v1.1.1: fix error en formulario de compra"

# Push del tag (dispara el workflow)
git push origin v1.0.0
```

### Qué genera el workflow al detectar un tag

El pipeline detecta `refs/tags/v1.0.0` y genera automáticamente:

```bash
docker push ghcr.io/tren-quazar-c6/events_admin:latest     # siempre
docker push ghcr.io/tren-quazar-c6/events_admin:abc123...  # siempre (SHA)
docker push ghcr.io/tren-quazar-c6/events_admin:1.0.0      # solo con tag
docker push ghcr.io/tren-quazar-c6/events_admin:1.0        # solo con tag
docker push ghcr.io/tren-quazar-c6/events_admin:1          # solo con tag
```

Los 3 tags semánticos apuntan a la misma imagen (mismo digest). Son alias.

### Cómo se ve en GHCR

Ve a `https://github.com/tren-quazar-C6/events_admin/pkgs/container/events_admin`

Verás los tags listados. Los de versión tienen íconos de "tag" y los SHA tienen formato hash.

### Cuándo NO necesitas un tag

Los pushes a `main` sin tag siguen funcionando: buildean con `:latest` y `:<sha>` solamente. Los tags son opcionales y se usan cuando el equipo decide que hay un release estable.

---

## Cómo hacer un deploy manual

Si el pipeline falló o necesitas forzar un redeploy sin cambios de código:

```bash
# Conectarse al VPS
ssh -i C:\Users\User\Documents\quasar\secrets\deploy_key root@204.168.211.73

cd /opt/quasar/events_infrastructure

# Autenticarse en GHCR
echo "TU_TOKEN_AQUI" | docker login ghcr.io -u TU_USUARIO --password-stdin

# Bajar la última imagen
docker compose pull admin

# Levantar el container
docker compose up -d --no-deps admin

# Verificar
docker compose ps admin
```

---

## Cómo hacer un rollback

Si un deploy rompe algo y necesitas volver a una versión anterior:

### Opción A: rollback vía Git (recomendado)

```bash
# En tu PC, en el repo afectado
git log --oneline -10   # ver commits recientes
git revert HEAD         # revertir el último commit
git push origin main    # el pipeline deploylará la versión revertida
```

### Opción B: rollback vía imagen con SHA específico

```bash
# En el VPS
cd /opt/quasar/events_infrastructure

# Editar temporalmente el compose para usar una versión específica
nano docker-compose.yml
# Cambiar:
#   image: ghcr.io/tren-quazar-c6/events_admin:latest
# Por:
#   image: ghcr.io/tren-quazar-c6/events_admin:abc123def456  ← SHA viejo

# Aplicar
docker compose up -d --no-deps admin

# Verificar
curl -I http://localhost:8101
```

Cuando el equipo arregle el bug, restaurar el compose a `:latest` y hacer nuevo push.

### Opción C: rollback a versión semántica específica

Si el equipo usa SemVer y necesita volver a `v1.0.0`:

```bash
# En el VPS
nano docker-compose.yml
# Cambiar:
#   image: ghcr.io/tren-quazar-c6/events_admin:latest
# Por:
#   image: ghcr.io/tren-quazar-c6/events_admin:1.0.0

docker compose up -d --no-deps admin
```

---

## Qué pasa si falla el pipeline

### Error: `no such service: X`

```
err: no such service: api-admin
```

El servicio no existe en el `docker-compose.yml` del VPS. Solución:

1. Agregar el bloque del servicio al `docker-compose.yml` en `events_infrastructure`
2. Commit + push a `events_infrastructure` primero
3. Re-run del pipeline fallido

### Error: `pull access denied` o `manifest not found`

```
Error response from daemon: pull access denied for ghcr.io/.../events_admin:latest
```

La imagen no existe en GHCR (Job 1 falló antes) o el TOKEN no tiene permisos. Verificar:

1. Que Job 1 terminó en verde
2. Que el secret `TOKEN` tiene scopes `read:packages` y `write:packages`
3. Que el TOKEN no expiró

### Error: `ssh: connect to host ... Connection refused`

```
ssh: connect to host 204.168.211.73 port 22: Connection refused
```

El VPS no está accesible. Verificar que el VPS está encendido y que el puerto 22 está abierto.

### Error: `ENTRYPOINT` con `command not found` (exit code 127)

```
quasar_api_admin    Restarting (127) 14 seconds ago
```

Exit code 127 = comando no encontrado. El Dockerfile tiene un comentario inline en el ENTRYPOINT:

```dockerfile
# MAL — el comentario rompe el comando:
ENTRYPOINT ["dotnet", "events_api_admin.dll"]   # ← cambia por cada API

# BIEN — sin comentario:
ENTRYPOINT ["dotnet", "events_api_admin.dll"]
```

Solución: borrar el comentario, hacer push, el pipeline rebuildeará la imagen.

### Error: `fatal: could not read Username for https://github.com`

El repo en el VPS está clonado con HTTPS y es privado, o algo falló con las credenciales de Git.

Solución: hacer el repo público en GitHub (ya hecho para este proyecto) o cambiar el remote a SSH.

```bash
# En el VPS
cd /opt/quasar/events_infrastructure
git remote -v
# Si dice https:// y el repo es privado:
git remote set-url origin git@github.com:tren-quazar-C6/events_infrastructure.git
```

### Pipeline verde pero container no actualizado

Puede pasar si `pull_policy: always` no está en el compose. Verificar:

```yaml
# En docker-compose.yml, cada servicio de monolito debe tener:
pull_policy: always
```

Sin esto, Docker usa la imagen cacheada localmente y nunca baja la nueva.

---

## Glosario rápido

| Término | Significado |
|---------|-------------|
| **Runner** | Máquina virtual Ubuntu en los servidores de GitHub que ejecuta el workflow |
| **GHCR** | GitHub Container Registry, donde se guardan las imágenes Docker |
| **PAT** | Personal Access Token, credencial de GitHub con permisos específicos |
| **Digest** | Hash único de una imagen Docker (`sha256:abc123...`) |
| **Tag** | Alias legible para un digest (`:latest`, `:1.0.0`, `:abc123`) |
| **`--no-deps`** | Flag de compose que recrea solo un servicio sin tocar sus dependencias |
| **`pull_policy: always`** | Instrucción de compose para siempre verificar si hay imagen más nueva |
| **SemVer** | Semantic Versioning. Formato `MAJOR.MINOR.PATCH` para versionar software |

---

**Responsable de esta documentación:** Dev 4 — Luis Miguel
**Organización GitHub:** `tren-quazar-C6`