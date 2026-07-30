# Guía de Emmisa App para empezar desde cero

Esta guía explica la aplicación como si fuera tu primer proyecto de
programación. No necesitas conocer Vue, Supabase ni APIs para comenzar. Lee
primero las secciones 1 a 7 y usa las demás cuando necesites cambiar algo.

## 1. ¿Qué es Emmisa?

Emmisa es la aplicación con pantallas que usa una persona para trabajar. Desde
ella puede registrar empresas, productos, clientes, ventas, compras, caja,
inventario y comprobantes.

La app tiene una parte visible y varias partes que trabajan detrás:

```text
Persona
  ↓ usa
Emmisa App (pantallas)
  ↓ guarda y consulta
Supabase (usuarios y datos)
  ↓ para emitir comprobantes
Edge Function (puente seguro)
  ↓ usa una clave privada
Fiscal API → SUNAT
```

La app no debe comunicarse directamente con Fiscal API desde el navegador. El
navegador puede ser inspeccionado por cualquier persona; por eso la clave
privada se queda en el servidor.

### Palabras importantes, explicadas fácilmente

| Palabra | Qué significa aquí |
|---|---|
| Frontend | La parte visible: pantallas, botones y formularios. |
| Backend | La parte que trabaja detrás y guarda información. |
| Supabase | Un servicio en Internet que ofrece usuarios, base de datos y funciones. |
| Auth | La parte que registra usuarios y permite iniciar sesión. |
| Base de datos | El lugar donde se guardan empresas, productos y ventas. |
| RLS | Una regla que evita que una empresa vea los datos de otra. |
| RPC | Una acción guardada en la base de datos, como registrar una venta. |
| Edge Function | Un pequeño programa que corre en Supabase, no en el navegador. |
| Secret | Un dato privado, como una contraseña o API key. |
| Migración | Un archivo que crea o cambia tablas de la base de datos. |
| Ruta | La dirección de una pantalla, por ejemplo `/productos`. |
| Módulo | Un grupo de pantallas y funciones de un tema, como caja o inventario. |

## 2. Qué necesitas instalar

- **Node.js LTS:** permite abrir y compilar la aplicación.
- **Git:** permite descargar el código y guardar cambios.
- **Un proyecto de Supabase:** allí vivirán los usuarios y los datos.
- **Acceso a Fiscal API:** solo si vas a probar emisión de comprobantes.
- **Supabase CLI:** ayuda a publicar migraciones y Edge Functions desde la
  terminal.

Se recomienda Node.js 22 para que la app y la API usen versiones parecidas.

## 3. Abrir la app por primera vez

Abre una terminal dentro de la carpeta `app` y ejecuta:

```bash
npm ci
```

Este comando instala las librerías que el proyecto necesita.

Crea un archivo llamado `.env` con estas dos líneas:

```dotenv
VITE_SUPABASE_URL=https://TU_PROYECTO.supabase.co
VITE_SUPABASE_ANON_KEY=TU_ANON_KEY
```

Estas dos variables indican a qué proyecto de Supabase debe conectarse la
app. La `anon key` está diseñada para usarse en el navegador, pero debe estar
protegida por las reglas RLS.

Nunca pongas aquí:

- `service_role key`;
- `FISCAL_API_KEY`;
- contraseñas SOL;
- archivos PFX;
- cualquier otra clave privada.

Las variables que empiezan por `VITE_` pueden terminar dentro del navegador.
Por eso solo deben contener datos que se puedan mostrar públicamente.

Ahora enciende la app:

```bash
npm run dev
```

La terminal mostrará una dirección parecida a `http://localhost:5173`. Ábrela
en el navegador.

## 4. Preparar Supabase

Supabase es el lugar donde la app guarda usuarios y datos. Las instrucciones
para crear sus tablas están en `supabase/migrations`.

Debes aplicar los archivos en orden, desde `0001_init.sql` hasta
`0047_fiscal_api.sql`. Puedes hacerlo con Supabase CLI o copiando cada archivo
en el SQL Editor de Supabase.

No saltes archivos. Un archivo puede necesitar algo que creó el anterior.

Estas migraciones crean, entre otras cosas:

- usuarios y empresas;
- productos, servicios, clientes y proveedores;
- ventas, compras, caja e inventario;
- roles y permisos;
- comprobantes y estados de SUNAT;
- funciones RPC;
- espacios para imágenes;
- conexión con Fiscal API.

La app usa el cliente de Supabase para leer y guardar datos sencillos. Para
acciones importantes, como registrar una venta, llama a funciones RPC que ya
viven en la base de datos. Así las reglas importantes no dependen solo de la
pantalla.

### Cómo saber si la seguridad está funcionando

RLS es la regla que separa los datos de cada empresa. Por ejemplo, una empresa
no debería poder ver los productos de otra.

Si una pantalla aparece vacía, revisa en este orden:

1. ¿Iniciaste sesión?
2. ¿Seleccionaste una empresa?
3. ¿La tabla tiene datos?
4. ¿El usuario tiene permiso?
5. ¿La política RLS permite esa consulta?

## 5. Recorrido de una persona que usa la app

1. Entra a `/register` y crea una cuenta.
2. Confirma su correo si Supabase lo solicita.
3. Entra por `/login`.
4. Si todavía no tiene empresa, la app la lleva a `/onboarding`.
5. Crea o selecciona una empresa.
6. Registra productos, clientes y series.
7. Abre `/emitir` y crea una venta.
8. Revisa el resultado en `/comprobantes`.

Las páginas de login, registro, verificación, recuperación de contraseña y
los documentos legales se pueden abrir sin iniciar sesión. Las demás necesitan
una sesión.

La lista completa de rutas está en `src/router/index.ts`.

## 6. Qué hace cada función de Supabase

Una **Edge Function** es un programa pequeño que se ejecuta en Supabase. Sirve
para hacer tareas que no deben hacerse directamente desde el navegador.

| Función | Para qué sirve |
|---|---|
| `emitir` | Envía un comprobante a Fiscal API. |
| `fiscal-artifact` | Descarga el XML, PDF, ZIP o CDR. |
| `enviar-comprobante` | Envía el comprobante por correo. |
| `lookup` | Consulta datos de RUC o DNI mediante un servicio externo. |
| `resumen` | Prepara procesos relacionados con resúmenes SUNAT. |
| `sire` | Trabaja con el módulo SIRE. |
| `tipo-cambio` | Consulta el tipo de cambio. |

La clave de Fiscal API nunca debe estar en Vue. Vive como secret dentro de las
Edge Functions.

## 7. Conectar la app con Fiscal API

La conexión necesita configurarse en dos lugares: Fiscal API y Supabase.

### Primero, en Fiscal API

1. Enciende la API y su worker.
2. Crea un tenant, que es la empresa que usará la conexión.
3. Crea una API key con estos permisos: `issuers:read`, `issuers:write`,
   `documents:read` y `documents:write`.
4. Crea el emisor usando el mismo RUC de la empresa en Emmisa.
5. Crea una serie.
6. Guarda el certificado PFX y las credenciales SOL en el ambiente correcto.

### Después, en Supabase

1. Aplica la migración `0047_fiscal_api.sql`.
2. Guarda la dirección de Fiscal API y su API key como secrets:

```bash
supabase secrets set \
  FISCAL_API_URL=https://fiscal.tudominio.pe \
  FISCAL_API_KEY=kfa_xxxxxxxxx
```

3. Publica las funciones que necesites:

```bash
supabase functions deploy emitir
supabase functions deploy fiscal-artifact
supabase functions deploy enviar-comprobante
supabase functions deploy resumen
```

4. Relaciona la empresa de Emmisa con el `issuerId` de Fiscal API. Esa relación
   se guarda en `fiscal_integrations` y debe hacerse desde un backend o con
   permisos de administrador, no desde la pantalla pública.

La función `emitir` revisa nuevamente que el RUC de la empresa y el RUC del
emisor sean iguales. Si no coinciden, detiene la emisión para evitar errores.

## 8. Qué ocurre cuando se emite una venta

Cuando alguien pulsa el botón para emitir, ocurre esto:

1. La pantalla guarda la venta en Supabase.
2. La app manda el ID de esa venta a la función `emitir`.
3. La función revisa que el usuario pueda ver esa venta.
4. Revisa la empresa, la suscripción, la serie y los datos fiscales.
5. Llama a Fiscal API usando la clave privada.
6. Fiscal API deja el trabajo en una cola.
7. El worker genera XML, firma, ZIP, CDR y PDF.
8. La app guarda el resultado y lo muestra en pantalla.

Hay tres estados que suelen confundirse:

| Estado | Explicación |
|---|---|
| `processingStatus` | Dice si Fiscal API todavía está trabajando. |
| `sunatStatus` | Dice qué respondió SUNAT. |
| `estado_sunat` | Es la versión resumida que guarda Emmisa. |

Si aparece `simulated`, Fiscal API está usando `mock`. Eso sirve para probar,
pero no significa que SUNAT haya aceptado la factura.

## 9. Dónde buscar cada cosa en el código

| Ubicación | Qué encontrarás |
|---|---|
| `src/pages` | Pantallas completas de la app. |
| `src/components` | Piezas reutilizables, como botones o tablas. |
| `src/layouts` | Estructura común de las pantallas. |
| `src/router` | Rutas y reglas para permitir o bloquear acceso. |
| `src/stores` | Información compartida, como usuario y empresa actual. |
| `src/modules/*/*.api.ts` | Consultas a Supabase de cada módulo. |
| `src/lib` | Ayudas para fechas, PDF, QR, validaciones y exportaciones. |
| `src/types` | Descripciones de los datos que usa TypeScript. |
| `supabase/migrations` | Cambios de tablas, permisos y funciones SQL. |
| `supabase/functions` | Programas que corren en el servidor. |
| `public` | Logos, imágenes y archivos que se pueden mostrar. |

Los módulos principales son productos, servicios, categorías, marcas, series,
clientes, emisión, comprobantes, inventario, proveedores, compras, caja,
reportes, configuración, equipo, revendedor, cuentas por cobrar, POS,
cotizaciones, notas de crédito y SIRE.

Si quieres cambiar una pantalla, empieza en `src/pages`. Si quieres cambiar la
forma en que se guardan datos, revisa su archivo `*.api.ts`. Si necesitas una
tabla, permiso o regla nueva, crea una nueva migración.

## 10. Comandos de trabajo

Ejecuta estos comandos desde la carpeta `app`:

```bash
npm run dev        # abre la app para trabajar localmente
npm run typecheck  # busca errores en los tipos
npm run test       # ejecuta pruebas automáticas
npm run build      # comprueba si se puede construir la app para publicar
npm run lint       # revisa el estilo del código
npm run format     # ordena el formato de Vue y TypeScript
```

Una prueba automática es una revisión que el proyecto hace solo. Antes de
subir un cambio importante, ejecuta:

```bash
npm run typecheck
npm run test
npm run build
```

## 11. Reglas sencillas para trabajar seguro

- Nunca llames a Fiscal API directamente desde una pantalla Vue.
- Nunca pongas secretos con el prefijo `VITE_`.
- Nunca subas `.env` al repositorio.
- No borres productos o comprobantes que ya tengan historial; usa una baja
  lógica para ocultarlos sin perder su historia.
- No cambies una migración que ya se aplicó. Crea una nueva.
- En cada consulta, respeta la empresa seleccionada.
- Revisa los importes y cantidades antes de enviarlos a SUNAT.
- Si agregas una pantalla privada, asegúrate de que el router pida sesión.
- Prueba cambios de emisión primero en beta o mock.

## 12. Problemas comunes

- **Falta una variable:** revisa el archivo `.env`, confirma que el nombre
  empiece por `VITE_` y reinicia `npm run dev`.
- **No aparecen datos:** revisa sesión, empresa seleccionada, permisos y RLS.
- **No se puede emitir:** revisa la integración fiscal, suscripción, serie y
  RUC.
- **La emisión queda pendiente:** revisa que el worker de Fiscal API esté
  encendido.
- **Aparece `simulated`:** Fiscal API está en modo `mock`; no es aceptación de
  SUNAT.
- **Una Edge Function falla:** revisa sus secrets, imports y logs con
  `supabase functions logs NOMBRE_DE_FUNCION`.

## 13. Qué funciona y qué necesita más trabajo

La integración principal funciona para factura `01`, venta interna y
afectaciones `10`, `20` y `30`.

La app tiene pantallas para más casos, pero tener una pantalla no significa que
Fiscal API ya pueda enviarlos directamente a SUNAT. Antes de activar boletas,
notas, bajas, resúmenes, ISC, ICBPER o exportaciones, revisa el alcance de
Fiscal API y prueba el caso en beta.

## 14. Documentos relacionados

- `README.md`: resumen y primeros pasos.
- `supabase/functions/emitir/index.ts`: entrada del proceso de emisión.
- `supabase/functions/_shared/fiscal-api.ts`: comunicación con Fiscal API.
- `src/modules/documents/documents.api.ts`: acciones de comprobantes.
- `src/router/index.ts`: rutas y permisos de entrada.
- [Guía sencilla de Fiscal API](https://github.com/juliots04/Emmisa-Sunat-API/blob/main/docs/GUIA_JUNIOR.md): explicación del backend fiscal.
