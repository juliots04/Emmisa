-- ============================================================
-- Emmisa · 0018 Emisión segura (cierra el hueco de forjar comprobantes)
--   PROBLEMA (auditoría): con `update on documents` permitido a la API, un
--   usuario autenticado podía alterar estado_sunat/total/hash/cdr y "forjar"
--   comprobantes aceptados sin pasar por SUNAT; y el fallback del cliente
--   marcaba cualquier error como 'aceptado'.
--   SOLUCIÓN:
--     1) Revocar UPDATE directo sobre documents (solo lo mueven la Edge Function
--        con service_role, o la RPC segura de abajo).
--     2) simular_emision(): simulación server-side que SOLO aplica a empresas SIN
--        emisor real configurado (no se puede usar para falsear una empresa que
--        factura de verdad). Mantiene el modo "prueba" sin desplegar nada.
-- Aplicar DESPUÉS de 0017. Supabase → SQL Editor → Run. Idempotente.
-- ============================================================

-- 1) Nadie edita comprobantes por la Data API.
revoke update on documents from anon, authenticated;

-- 2) Simulación de emisión SEGURA (reemplaza el fallback del navegador).
create or replace function simular_emision(p_document_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_doc    documents%rowtype;
  v_ruc    text;
  v_num    text;
  v_nombre text;
  v_estado text;
  v_hash   text;
  v_ticket text;
  v_cdr    text;
  v_qr     text;
begin
  select * into v_doc from documents where id = p_document_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;

  -- Blindaje anti-forja: si la empresa tiene un emisor (PSE) real configurado,
  -- NO se simula; debe emitir de verdad por la Edge Function.
  if exists (select 1 from emisor_credentials where company_id = v_doc.company_id and activo) then
    raise exception 'Esta empresa tiene un emisor real configurado: usa el motor de emisión, no la simulación';
  end if;

  select ruc into v_ruc from companies where id = v_doc.company_id;
  v_num    := v_doc.serie || '-' || lpad(v_doc.correlativo::text, 8, '0');
  v_nombre := case v_doc.tipo_doc when '01' then 'Factura' when '03' then 'Boleta'
                 when '07' then 'Nota de Crédito' when '08' then 'Nota de Débito' else 'Comprobante' end;
  v_hash   := left(replace(encode(convert_to(v_num || v_doc.total::text, 'UTF8'), 'base64'), E'\n', ''), 27) || '=';
  v_ticket := 'SIM-' || v_doc.serie || '-' || lpad(v_doc.correlativo::text, 8, '0');

  -- Escenarios de prueba por nº de doc del receptor:
  --   termina en 99 -> rechazado · 88 -> pendiente (al reintentar -> aceptado) · resto -> aceptado
  if coalesce(v_doc.receptor_num_doc, '') ~ '99$' then
    v_estado := 'rechazado';
  elsif coalesce(v_doc.receptor_num_doc, '') ~ '88$' and v_doc.sunat_ticket is null then
    v_estado := 'pendiente';
  else
    v_estado := 'aceptado';
  end if;

  if v_estado = 'rechazado' then
    update documents set estado_sunat = 'rechazado',
      sunat_error = 'Error 2335: el comprobante fue rechazado por SUNAT (SIMULADO)',
      hash = v_hash, sunat_ticket = v_ticket
      where id = p_document_id;
  elsif v_estado = 'pendiente' then
    update documents set estado_sunat = 'pendiente', sunat_ticket = v_ticket
      where id = p_document_id;
  else
    v_cdr := 'La ' || v_nombre || ' numero ' || v_num || ', ha sido aceptada';
    v_qr  := concat_ws('|', v_ruc, v_doc.tipo_doc, v_doc.serie, v_doc.correlativo,
                       round(v_doc.total_igv, 2), round(v_doc.total, 2), v_doc.fecha_emision,
                       coalesce(v_doc.receptor_tipo_doc, '-'), coalesce(v_doc.receptor_num_doc, '-'), v_hash);
    update documents set estado_sunat = 'aceptado', cdr = v_cdr, hash = v_hash,
      sunat_ticket = v_ticket, codigo_qr = v_qr, sunat_error = null
      where id = p_document_id;
  end if;

  return jsonb_build_object(
    'estado', v_estado, 'hash', v_hash, 'ticket', v_ticket,
    'cdr', case when v_estado = 'aceptado' then v_cdr else null end,
    'mensaje', v_nombre || ' ' || v_num || ' — ' || upper(v_estado) || ' (SIMULADO)',
    'simulado', true);
end $$;
grant execute on function simular_emision(uuid) to authenticated, service_role;

-- Pendientes (siguiente migración, requieren revisar flujos de caja):
--   • revoke insert,update,delete on cash_movements, cash_sessions (vía RPC)
--   • cerrar insert/delete de series
--   • companies_update con trigger que impida cambiar owner_id/reseller_id/estado
--   • reducir grants a anon (revoke all ... from anon)
