# Events Infrastructure

Sistema distribuido de gestión de eventos y tickets.

## Arquitectura

El sistema está compuesto por 4 aplicaciones PWA:

- User Module
- Admin Module
- Employee Sales Module
- Access Control Module

## Tecnologías

- Laravel
- ASP.NET
- PostgreSQL
- MongoDB

## Bases de datos

- PostgreSQL:
  Base transaccional principal

- MongoDB:
  Auditoría y logs

## Comunicación

Los módulos se comunican mediante APIs REST y comparten una base de datos relacional centralizada.
