// ============================================================================
// Quasar · MongoDB · Inicialización
// ----------------------------------------------------------------------------
// Este script se ejecuta automáticamente UNA SOLA VEZ, cuando MongoDB arranca
// por primera vez (volumen vacío).
//
// Aquí hacemos 3 cosas:
//   1. Cambiar a la base "events_logs"
//   2. Crear un usuario de aplicación con permisos solo sobre esa BD
//   3. Crear las colecciones e índices iniciales
//
// El usuario root (creado por las variables MONGO_INITDB_ROOT_*) NO debe
// usarse por las apps. Solo para tareas de administración.
// ============================================================================

// Cambiar al contexto de la BD de logs
db = db.getSiblingDB(process.env.MONGO_INITDB_DATABASE);

// ----------------------------------------------------------------------------
// Crear usuario de aplicación
// Lee credenciales desde variables de entorno definidas en docker-compose.yml
// ----------------------------------------------------------------------------
db.createUser({
  user: process.env.MONGO_APP_USER,
  pwd: process.env.MONGO_APP_PASSWORD,
  roles: [
    { role: 'readWrite', db: process.env.MONGO_INITDB_DATABASE }
  ]
});

// ----------------------------------------------------------------------------
// Colección: audit_logs
// Eventos de negocio importantes (compras, escaneos, cambios de estado, etc.)
// ----------------------------------------------------------------------------
db.createCollection('audit_logs');

db.audit_logs.createIndex({ timestamp: -1 });
db.audit_logs.createIndex({ event: 1, timestamp: -1 });
db.audit_logs.createIndex({ user_id: 1, timestamp: -1 });
db.audit_logs.createIndex({ portal: 1, timestamp: -1 });

// ----------------------------------------------------------------------------
// Colección: app_logs
// Logs técnicos de las apps (errores, warnings, info)
// ----------------------------------------------------------------------------
db.createCollection('app_logs');

db.app_logs.createIndex({ timestamp: -1 });
db.app_logs.createIndex({ level: 1, timestamp: -1 });
db.app_logs.createIndex({ portal: 1, level: 1, timestamp: -1 });
db.app_logs.createIndex({ request_id: 1 });

print('✓ Quasar MongoDB inicializado correctamente');