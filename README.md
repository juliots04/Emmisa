# Konversa · App (facturador)

Frontend + capa de datos del facturador. **Vue 3 + Vite + TypeScript + Quasar + Pinia + Supabase.**

El motor SUNAT usa un **adaptador**: hoy corre un **mock** (emite sin conexión real) y luego se cambia por APISUNAT / Nubefact en un solo archivo.

## Requisitos
- Node 18+ (tienes 24 ✅)
- Un proyecto en Supabase (ya configurado en `.env`)

## Arrancar
```bash
cd app
npm install
# 1) Crea las tablas: pega app/supabase/migrations/0001_init.sql en el SQL Editor de Supabase
# 2) Revisa que .env tenga VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY
npm run dev
```
Abre http://localhost:5173 → regístrate → crea tu empresa → emite un comprobante (simulado).

## Scripts
- `npm run dev` — servidor de desarrollo
- `npm run build` — typecheck + build de producción
- `npm run typecheck` — solo chequeo de tipos
- `npm run test` — tests (Vitest)
- `npm run lint` / `npm run format`

## Estructura
```
src/
  lib/            cliente Supabase + validación de env
  types/          tipos del dominio (reflejan la BD)
  stores/         Pinia: auth, company (empresa actual)
  router/         rutas + guard de sesión
  layouts/        AppLayout (shell con navegación)
  pages/          Login, Dashboard, Products, Customers, Emit, Documents
  modules/
    sunat/        adaptador del motor (provider + mock + tax) ← cambia el proveedor aquí
    products/     products.api.ts
    customers/    customers.api.ts
    documents/    documents.api.ts (emitir + listar)
```

## Cambiar el mock por el proveedor real
Edita `src/modules/sunat/index.ts`:
```ts
// export const emisor = new MockProvider()
export const emisor = new ApisunatProvider(/* credenciales desde el backend */)
```
La emisión real (firma + envío a SUNAT) debe hacerse en una **Edge Function** (con el token secreto), no en el navegador.

## Seguridad
- El aislamiento multiempresa lo garantiza **RLS** en la base de datos.
- Los secretos van en `.env` (ya en `.gitignore`), nunca en el código ni en git.
