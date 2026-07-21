-- ============================================================
-- Konversa · 0016 Hardening (candados de integridad a nivel BD)
-- Cierra el hueco "la validación vive solo en las RPC": agrega CHECK de dominio,
-- índices que faltaban, arregla la fuga de subscription_payments, e impide la
-- ESCRITURA DIRECTA por la API al "libro contable" (documents/ítems/stock/pagos/kardex)
-- para que esos objetos solo se muevan por las funciones transaccionales.
-- Idempotente. Aplicar DESPUÉS de 0010–0015. Supabase → SQL Editor → Run
-- ============================================================

-- ==================== 1) CHECK de dominio ====================
-- (drop-then-add = idempotente; las tablas están casi vacías, no rompe datos)

-- Montos y cantidades positivos
alter table payments        drop constraint if exists chk_payments_monto;
alter table payments        add  constraint chk_payments_monto        check (monto > 0);
alter table cash_movements  drop constraint if exists chk_cashmov_monto;
alter table cash_movements  add  constraint chk_cashmov_monto         check (monto > 0);
alter table document_items  drop constraint if exists chk_docitems_cantidad;
alter table document_items  add  constraint chk_docitems_cantidad     check (cantidad > 0);
alter table purchases       drop constraint if exists chk_purchases_montos;
alter table purchases       add  constraint chk_purchases_montos      check (total >= 0 and saldo >= 0);

-- Estados y tipos con dominio cerrado (un typo ya NO pasa silencioso)
alter table documents       drop constraint if exists chk_doc_estado_sunat;
alter table documents       add  constraint chk_doc_estado_sunat      check (estado_sunat in ('pendiente','aceptado','rechazado','anulado'));
alter table documents       drop constraint if exists chk_doc_estado_pago;
alter table documents       add  constraint chk_doc_estado_pago       check (estado_pago in ('pagado','pendiente','parcial'));
alter table documents       drop constraint if exists chk_doc_condicion;
alter table documents       add  constraint chk_doc_condicion         check (condicion_pago in ('contado','credito'));
alter table cash_sessions   drop constraint if exists chk_caja_estado;
alter table cash_sessions   add  constraint chk_caja_estado           check (estado in ('abierta','cerrada'));
alter table cash_movements  drop constraint if exists chk_cashmov_tipo;
alter table cash_movements  add  constraint chk_cashmov_tipo          check (tipo in ('ingreso','retiro'));
alter table inventory_movements drop constraint if exists chk_invmov_tipo;
alter table inventory_movements add  constraint chk_invmov_tipo       check (tipo in ('ingreso','salida','ajuste'));
alter table payments        drop constraint if exists chk_payments_tipo;
alter table payments        add  constraint chk_payments_tipo         check (tipo in ('cobro','pago'));
alter table memberships     drop constraint if exists chk_membership_role;
alter table memberships     add  constraint chk_membership_role       check (role in ('admin','cajero','vendedor','contador'));
alter table subscriptions   drop constraint if exists chk_sub_estado;
alter table subscriptions   add  constraint chk_sub_estado            check (estado in ('activa','vencida','suspendida','cancelada'));
alter table products        drop constraint if exists chk_prod_tipo;
alter table products        add  constraint chk_prod_tipo             check (tipo in ('bien','servicio'));

-- Un pago es de venta (CxC) O de compra (CxP), nunca ambos ni ninguno
alter table payments        drop constraint if exists chk_payments_xor;
alter table payments        add  constraint chk_payments_xor          check ((document_id is null) <> (purchase_id is null));

-- ==================== 2) Índices que faltaban ====================
create index if not exists ix_document_items_document on document_items(document_id);
create index if not exists ix_documents_reporte       on documents(company_id, fecha_emision, estado_sunat);
create index if not exists ix_documents_company_fecha  on documents(company_id, created_at desc);
create index if not exists ix_invmov_product          on inventory_movements(product_id);
create index if not exists ix_payments_company        on payments(company_id);

-- ==================== 3) Fuga de subscription_payments (H1) ====================
-- Antes: FOR ALL con USING que incluía auth_company_ids() → un cajero podía BORRAR
-- los pagos de suscripción (con los que TÚ cobras). Ahora: los miembros solo LEEN;
-- solo el dueño del revendedor escribe/borra.
drop policy if exists subpays_all    on subscription_payments;
drop policy if exists subpays_select on subscription_payments;
drop policy if exists subpays_write  on subscription_payments;
drop policy if exists subpays_update on subscription_payments;
drop policy if exists subpays_delete on subscription_payments;

create policy subpays_select on subscription_payments for select
  using (subscription_id in (
    select id from subscriptions where company_id in (
      select auth_reseller_company_ids() union select auth_company_ids())));
create policy subpays_write on subscription_payments for insert
  with check (subscription_id in (
    select id from subscriptions where company_id in (select auth_reseller_company_ids())));
create policy subpays_update on subscription_payments for update
  using (subscription_id in (
    select id from subscriptions where company_id in (select auth_reseller_company_ids())));
create policy subpays_delete on subscription_payments for delete
  using (subscription_id in (
    select id from subscriptions where company_id in (select auth_reseller_company_ids())));

-- ==================== 4) Cerrar la ESCRITURA DIRECTA al libro contable ====================
-- Estas tablas SOLO deben moverse por las funciones transaccionales (SECURITY DEFINER,
-- que corren como owner y conservan sus privilegios). Se revoca a los roles de la API
-- para que un miembro no pueda saltarse las RPC con un INSERT/UPDATE directo.
-- (Se conserva SELECT: leer sus propias filas sigue permitido por RLS.)
revoke insert, update, delete on document_items      from anon, authenticated;
revoke insert, update, delete on inventory_movements from anon, authenticated;
revoke insert, update, delete on stock               from anon, authenticated;
revoke insert, update, delete on payments            from anon, authenticated;
-- documents: nadie forja ni borra comprobantes por la API (los crean las RPC).
--   Se deja UPDATE porque el fallback local (sin Edge Function) actualiza el estado;
--   una vez desplegada la Edge Function puedes descomentar la línea de abajo.
revoke insert, delete on documents from anon, authenticated;
-- revoke update on documents from anon, authenticated;   -- activar tras desplegar la Edge Function
-- series: el correlativo solo lo mueve emitir_venta/emitir_nota (evita saltos manuales).
revoke update on series from anon, authenticated;

-- ==================== 5) audit_events sin borrado ====================
-- El log de auditoría debe ser inmutable desde la API (ya no tiene policy de escritura;
-- reforzamos revocando también a nivel de grant).
revoke insert, update, delete on audit_events from anon, authenticated;
