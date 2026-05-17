#!/bin/bash
# ============================================================================
# Quasar · MySQL · Inicialización de usuarios y permisos
# ----------------------------------------------------------------------------
# Este script se ejecuta automáticamente UNA SOLA VEZ, cuando MySQL arranca
# por primera vez (volumen vacío).
#
# Lee las variables de entorno definidas en .env y crea los 4 usuarios de
# aplicación con permisos sobre la BD "events".
#
# Ventaja sobre un .sql plano: los passwords nunca quedan hardcoded en el
# repo, solo viven en el archivo .env (que está en .gitignore).
# ============================================================================

set -e   # Salir al primer error

echo "→ Creando usuarios de aplicación en MySQL..."

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<EOF

-- ----------------------------------------------------------------------------
-- Users (Laravel) — Portal público
-- ----------------------------------------------------------------------------
CREATE USER '${MYSQL_USERS_USER}'@'%' IDENTIFIED BY '${MYSQL_USERS_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${MYSQL_DATABASE}.* TO '${MYSQL_USERS_USER}'@'%';

-- ----------------------------------------------------------------------------
-- Admin (ASP.NET) — Backoffice
-- ----------------------------------------------------------------------------
CREATE USER '${MYSQL_ADMIN_USER}'@'%' IDENTIFIED BY '${MYSQL_ADMIN_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${MYSQL_DATABASE}.* TO '${MYSQL_ADMIN_USER}'@'%';

-- ----------------------------------------------------------------------------
-- Tickets (ASP.NET) — Taquilla
-- ----------------------------------------------------------------------------
CREATE USER '${MYSQL_TICKETS_USER}'@'%' IDENTIFIED BY '${MYSQL_TICKETS_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${MYSQL_DATABASE}.* TO '${MYSQL_TICKETS_USER}'@'%';

-- ----------------------------------------------------------------------------
-- Access (ASP.NET) — Control de acceso
-- ----------------------------------------------------------------------------
CREATE USER '${MYSQL_ACCESS_USER}'@'%' IDENTIFIED BY '${MYSQL_ACCESS_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${MYSQL_DATABASE}.* TO '${MYSQL_ACCESS_USER}'@'%';

FLUSH PRIVILEGES;

EOF

echo "✓ Usuarios MySQL creados correctamente"