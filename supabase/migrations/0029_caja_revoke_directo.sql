-- ============================================================
-- Emmisa · 0029 Cierre del arqueo forjable — revoca escritura DIRECTA a caja
--   Cierra el hueco: cash_sessions/cash_movements eran escribibles por la Data API
--   (el arqueo se podía forjar). Tras 0028 existen los RPCs abrir_caja/cerrar_caja/
--   mov_caja (SECURITY DEFINER, recomputan el arqueo). Aquí se revoca el INSERT/UPDATE/
--   DELETE directo, dejando solo SELECT (lectura vía RLS).
--
--   ⚠️ APLICAR SOLO DESPUÉS de desplegar el FRONTEND nuevo (cash.api.ts que usa los RPCs).
--      Si se aplica con el front viejo (que inserta/actualiza directo), Caja dejará de
--      funcionar hasta el deploy. Idempotente.
-- ============================================================

revoke insert, update, delete on cash_sessions  from anon, authenticated;
revoke insert, update, delete on cash_movements from anon, authenticated;
