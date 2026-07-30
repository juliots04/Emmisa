# Guía sencilla para continuar Emmisa App

Esta carpeta contiene el frontend de Emmisa, el sistema que usa la persona que
vende. La guía explica cómo levantarlo y cómo se conecta con Supabase y Fiscal
API.

## 1. ¿Qué hace la app?

Emmisa permite administrar empresas, productos, servicios, clientes,
proveedores, compras, inventario, caja, cotizaciones, comprobantes, reportes y
equipo. También tiene módulos de SIRE y configuración de revendedor.

La app no debe guardar secretos fiscales en el navegador. La clave que permite
hablar con Fiscal API vive únicamente en las Edge Functions de Supabase.

```text
Navegador Vue
    ↓ sesión del usuario + anon key pública
Supabase Auth / tablas / RPC
    ↓ solo en el servidor
Edge Function emitir
    ↓ FISCAL_API_KEY secreta
Emmisa Fiscal API → worker → SUNAT
```

## 2. Herramientas necesarias

- Node.js LTS; se recomienda Node.js 22.
- Git.
- Un proyecto de Supabase.
- Acceso al repositorio de `Emmisa-fiscal-api` si se probará emisión.
- Supabase CLI, solo para desplegar funciones y migraciones desde terminal.

## 3. Primera instalación

Desde esta carpeta:

```bash
npm ci
```

Crea `.env` con los datos públicos del proyecto Supabase:

```dotenv
VITE_SUPABASE_URL=https://TU_PROYECTO.supabase.co
VITE_SUPABASE_ANON_KEY=TU_ANON_KEY
```

La aplicación lee estas variables en `src/lib/env.ts`. Si falta una, el arranque
se detiene con un mensaje claro. La `anon key` puede estar en el frontend; nunca
pongas aquí la `service_role key`, una API key fiscal, PFX o contraseña.

Inicia el frontend:

```bash
npm run dev
```

Vite mostrará una dirección como `http://localhost:5173`.

## 4. Preparar Supabase

Las reglas y tablas de la aplicación están en `supabase/migrations`. Deben
aplicarse en orden, desde `0001_init.sql` hasta `0047_fiscal_api.sql`.

Puedes ejecutarlas con Supabase CLI después de vincular el proyecto, o abrir
cada archivo en el SQL Editor de Supabase. No saltes migraciones: cada archivo
puede depender de tablas o funciones creadas antes.

Las migraciones crean, entre otras cosas:

- usuarios y empresas;
- productos, servicios, clientes y proveedores;
- ventas, compras, caja e inventario;
- roles, permisos y políticas RLS;
- comprobantes y datos de integración fiscal;
- funciones RPC y buckets de imágenes.

RLS significa que Supabase filtra los datos por empresa y usuario. Si una
consulta devuelve vacío, revisa primero sesión, `company_id`, permisos y la
política RLS correspondiente.

## 5. Primer recorrido de usuario

1. Abre `/register` y crea una cuenta.
2. Confirma el correo si el proyecto lo exige.
3. Entra por `/login`.
4. Si no hay empresa, el router te lleva a `/onboarding`.
5. Crea o selecciona una empresa.
6. Configura productos, clientes y series.
7. Usa `/emitir` para crear una venta.
8. Revisa el resultado en `/comprobantes`.

Las rutas públicas son login, registro, verificación, recuperación de
contraseña y páginas legales. El resto necesita sesión. Esa decisión está en
`src/router/index.ts`.

## 6. Conectar con Fiscal API

Para una emisión real se necesitan dos lados configurados.

### En Fiscal API

1. Levanta la API y el worker.
2. Crea un tenant y una API key con `issuers:read`, `issuers:write`,
   `documents:read` y `documents:write`.
3. Crea el emisor con el mismo RUC de la empresa de Emmisa.
4. Crea la serie y registra PFX y credenciales SOL para `beta` o `production`.

### En Supabase

1. Aplica `supabase/migrations/0047_fiscal_api.sql`.
2. Guarda la URL y la API key como secrets de Edge Functions:

```bash
supabase secrets set \
  FISCAL_API_URL=https://fiscal.tudominio.pe \
  FISCAL_API_KEY=kfa_xxxxxxxxx
```

3. Despliega las funciones necesarias:

```bash
supabase functions deploy emitir
supabase functions deploy fiscal-artifact
supabase functions deploy enviar-comprobante
supabase functions deploy resumen
```

4. Relaciona la empresa local con el `issuerId` de Fiscal API. Esa relación se
   guarda en `fiscal_integrations` y debe hacerse con backend/service role.

La Edge Function `emitir` vuelve a comprobar que el RUC de empresa y emisor
coincidan. Si no coinciden, detiene la emisión.

## 7. Qué pasa al emitir

1. La pantalla crea la venta mediante una función RPC.
2. La app llama a la Edge Function `emitir` con el `documentId`.
3. La función verifica sesión, empresa, suscripción y datos de la venta.
4. La función consulta la integración fiscal y llama a Fiscal API.
5. Fiscal API encola el trabajo y el worker genera XML, firma, ZIP, CDR y PDF.
6. La Edge Function guarda el ID, estado y artefactos en `documents`.
7. La pantalla muestra aceptado, rechazado o pendiente.

No confundas estos valores:

- `processingStatus`: estado técnico del trabajo en Fiscal API.
- `sunatStatus`: resultado fiscal.
- `estado_sunat`: estado simplificado que muestra la app.

Si Fiscal API responde `simulated`, la app no lo marca como aceptado.

## 8. Dónde buscar cada cosa

| Ubicación | Uso |
|---|---|
| `src/pages` | Pantallas completas |
| `src/components` | Componentes reutilizables |
| `src/layouts` | Estructura general de la aplicación |
| `src/router` | Rutas y protección de sesión |
| `src/stores` | Estado compartido, sesión y empresa actual |
| `src/modules/*/*.api.ts` | Consultas Supabase y RPC por módulo |
| `src/lib` | Utilidades: fechas, PDF, QR, validaciones y tablas |
| `src/types` | Tipos TypeScript compartidos |
| `supabase/migrations` | Cambios de base de datos |
| `supabase/functions` | Código que corre en el servidor |
| `public` | Logos, imágenes y archivos públicos |

Para agregar una función simple de un módulo, normalmente se cambia su archivo
`*.api.ts`, el tipo necesario y la página. Para una regla de base de datos, se
crea una nueva migración y se actualizan las políticas RLS.

## 9. Comandos de trabajo

```bash
npm run dev        # servidor local
npm run typecheck  # revisa tipos
npm run test       # pruebas Vitest
npm run build      # compilación de producción
npm run lint       # revisa y corrige estilo ESLint
npm run format     # formatea Vue y TypeScript
```

Antes de subir un cambio importante ejecuta al menos:

```bash
npm run typecheck
npm run test
npm run build
```

## 10. Cómo trabajar sin romper otras partes

- No llames a Fiscal API directamente desde Vue: usa una Edge Function.
- No pongas secretos con prefijo `VITE_`; Vite los expone al navegador.
- No borres productos o comprobantes con historial fiscal; usa baja lógica.
- No cambies una migración ya aplicada; agrega otra.
- Mantén todas las consultas filtradas por la empresa actual.
- Usa `number` o `decimal` con cuidado; importes fiscales deben conservar sus
  decimales y no depender de cálculos imprecisos del navegador.
- Si agregas una ruta protegida, recuerda que el router debe exigir sesión.

## 11. Problemas comunes

- **Falta una variable de entorno:** revisa `.env`, reinicia Vite y verifica que
  el nombre empiece por `VITE_`.
- **No aparecen datos:** revisa que haya sesión, empresa seleccionada y RLS.
- **No se puede emitir:** revisa integración fiscal, suscripción, serie, RUC y
  logs de la Edge Function `emitir`.
- **La emisión queda pendiente:** revisa que el worker de Fiscal API esté
  funcionando.
- **Ves `simulado`:** Fiscal API está con `EMISSION_DRIVER=mock`; no es una
  aceptación de SUNAT.
- **Una Edge Function falla al desplegar:** revisa sus imports, secrets y los
  logs con `supabase functions logs NOMBRE_DE_FUNCION`.

## 12. Estado y pendientes

El flujo integrado principal cubre factura `01`, venta interna y afectaciones
`10`, `20` y `30`. La app contiene pantallas para más casos, pero una pantalla
no significa que la emisión directa a SUNAT ya esté soportada. Antes de activar
boletas, notas, bajas, resúmenes, ISC, ICBPER o exportaciones, revisa el alcance
de Fiscal API y prueba el caso en beta.

## 13. Documentos relacionados

- `README.md`: resumen y conexión rápida.
- `supabase/functions/emitir/index.ts`: entrada del flujo fiscal.
- `supabase/functions/_shared/fiscal-api.ts`: cliente HTTP de Fiscal API.
- `src/modules/documents/documents.api.ts`: operaciones de comprobantes.
- `src/router/index.ts`: rutas y guards.
- [Guía junior de Fiscal API](https://github.com/juliots04/Emmisa-Sunat-API/blob/main/docs/GUIA_JUNIOR.md): guía del backend fiscal.
