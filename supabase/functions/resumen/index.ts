// Nuestra Fiscal API todavía no expone bajas ni resúmenes diarios. La función se
// conserva como límite explícito para que ningún despliegue antiguo vuelva a usar
// silenciosamente un PSE o una simulación.
import { corsHeaders, json } from '../_shared/cors.ts'

Deno.serve((req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  return json({
    error:
      'Bajas y resúmenes diarios aún no están implementados en Emmisa Fiscal API. No se envió información a terceros ni a SUNAT.',
  }, 501)
})
