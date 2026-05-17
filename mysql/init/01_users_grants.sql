-- ============================================================================
-- Quasar · MySQL · Inicialización de usuarios y permisos
-- ----------------------------------------------------------------------------
-- Este script se ejecuta automáticamente UNA SOLA VEZ, cuando MySQL arranca
-- por primera vez (volumen vacío).
--
-- La BD "events" ya fue creada por MYSQL_DATABASE en docker-compose.yml.
-- Aquí creamos los 4 usuarios de aplicación con permisos diferenciados.
--
-- NOTA: Los grants actuales son a nivel de BD completa (provisional).
-- Cuando Faiber defina las tablas, refinamos a nivel de tabla específica.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Users (Laravel) — Portal público
-- Acceso completo a la BD por ahora (lectura/escritura del catálogo, perfiles,
-- favoritos, PQRS). Es el monolito que más interactúa con la BD.
-- ----------------------------------------------------------------------------
CREATE USER 'users_app'@'%' IDENTIFIED BY 'cambiame_users';
GRANT SELECT, INSERT, UPDATE, DELETE ON events.* TO 'users_app'@'%';

-- ----------------------------------------------------------------------------
-- Admin (ASP.NET) — Backoffice del teatro
-- Acceso completo: gestiona eventos, empleados, PQRS, métricas.
-- ----------------------------------------------------------------------------
CREATE USER 'admin_app'@'%' IDENTIFIED BY 'cambiame_admin';
GRANT SELECT, INSERT, UPDATE, DELETE ON events.* TO 'admin_app'@'%';

-- ----------------------------------------------------------------------------
-- Tickets (ASP.NET) — Taquilla física
-- Acceso completo por ahora. En el refinamiento posterior se limitará a:
--   - Lectura de events, users
--   - Escritura en sales, tickets
-- ----------------------------------------------------------------------------
CREATE USER 'tickets_app'@'%' IDENTIFIED BY 'cambiame_tickets';
GRANT SELECT, INSERT, UPDATE, DELETE ON events.* TO 'tickets_app'@'%';

-- ----------------------------------------------------------------------------
-- Access (ASP.NET) — Control de acceso (escaneo de QR)
-- Acceso completo por ahora. En el refinamiento posterior se limitará a:
--   - Lectura de tickets, events
--   - Escritura en scans
--   - UPDATE solo en columna "used" de tickets
-- ----------------------------------------------------------------------------
CREATE USER 'access_app'@'%' IDENTIFIED BY 'cambiame_access';
GRANT SELECT, INSERT, UPDATE, DELETE ON events.* TO 'access_app'@'%';

-- Aplicar todos los cambios de permisos
FLUSH PRIVILEGES;

--Para reaplicar el script tendrías que:
--compose down -v          # ⚠️ -v borra los volúmenes
--docker compose up -d