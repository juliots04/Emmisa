# Emmisa · Facturador

Para una explicación paso a paso pensada para nuevos integrantes, revisa
[la guía para juniors](docs/GUIA_JUNIOR.md). La guía cubre instalación,
Supabase, módulos, emisión y problemas comunes.

Facturador construido con Vue 3, Vite, TypeScript, Quasar, Pinia y Supabase.
La emisión no usa APISUNAT, Nubefact ni otro PSE: el backend consume
exclusivamente la instancia independiente de **Emmisa Fiscal API**, que firma y
envía directamente a SUNAT.

## Flujo seguro

```text
Vue + sesión Supabase
          |
          | JWT del usuario (sin secretos fiscales)
          v
Edge Function emitir
          |
          | HTTPS + X-API-Key + Idempotency-Key
          v
Emmisa Fiscal API -> PostgreSQL/worker -> SUNAT
          |
          +-- XML firmado / ZIP / CDR / PDF
```

La clave `FISCAL_API_KEY` nunca se declara con prefijo `VITE_`, nunca se guarda
en Local Storage y nunca se entrega al navegador. Solo vive en los secrets de
las Edge Functions.

## Estado funcional

- Factura `01`, venta interna, afectaciones `10`, `20` y `30`: integrada.
- Descarga autenticada de PDF, XML firmado, ZIP y CDR: integrada.
- Envío por correo: adjunta PDF, XML firmado y CDR sin publicar la API key.
- Boletas, notas, bajas, resúmenes, ICBPER, ISC, exportaciones y gratuitas:
  bloqueadas explícitamente hasta que Fiscal API implemente sus flujos SUNAT.
- No existe fallback simulado ni cambio silencioso a un proveedor externo.

## Desarrollo

```bash
npm ci
npm run dev
npm run test
npm run build
```

El frontend solo requiere:

```dotenv
VITE_SUPABASE_URL=https://<proyecto>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon-key>
```

## Conectar Fiscal API

1. Despliega `Emmisa-fiscal-api` detrás de HTTPS y crea una API key con los
   scopes `issuers:read`, `documents:read` y `documents:write`.
2. Registra en Fiscal API el emisor, su serie, certificado y credenciales SOL.
3. Aplica las migraciones de Supabase, incluida `0047_fiscal_api.sql`.
4. Guarda URL y clave solo como secrets:

```bash
supabase secrets set \
  FISCAL_API_URL=https://fiscal.tudominio.pe \
  FISCAL_API_KEY=kfa_xxxxxxxxx
```

5. Despliega las funciones:

```bash
supabase functions deploy emitir
supabase functions deploy fiscal-artifact
supabase functions deploy enviar-comprobante
supabase functions deploy resumen
```

6. Relaciona la empresa de Supabase con el emisor del mismo RUC. Desde el SQL
   Editor, usando los UUID reales:

```sql
insert into fiscal_integrations(company_id, issuer_id, environment, active)
values ('<company-id>', '<issuer-id-fiscal-api>', 'beta', true)
on conflict (company_id) do update
set issuer_id = excluded.issuer_id,
    environment = excluded.environment,
    active = true,
    updated_at = now();
```

La función de emisión vuelve a consultar el emisor y rechaza la operación si su
RUC no coincide con el RUC de `companies`.

## Producción

- Usa `environment='production'` solo después de una prueba beta aceptada.
- Configura `EMISSION_DRIVER=sunat` y `SUNAT_PRODUCTION_ENABLED=true` en Fiscal
  API; no en Vue.
- Publica únicamente HTTPS. PostgreSQL, worker y volúmenes no deben quedar
  expuestos a Internet.
- Respalda coordinadamente la base de datos y los artefactos fiscales.
- Rota la API key si se sospecha exposición y actualiza el secret de Supabase.
