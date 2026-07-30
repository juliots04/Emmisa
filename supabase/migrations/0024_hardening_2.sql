-- ============================================================
-- Emmisa · 0024 Hardening 2 (complementos de la auditoría)
--   • C1 (real): revocar EXECUTE de PUBLIC en simular_emision — authenticated lo
--     heredaba por el grant por defecto de Postgres a PUBLIC (0023 solo revocó de
--     authenticated). Sin tocar los helpers de RLS.
--   • M12: el reporte de cuentas por cobrar solo cuenta comprobantes ACEPTADOS por
--     SUNAT (excluye rechazados/pendientes/anulados que no son cobrables reales).
--   Aplicar DESPUÉS de 0023. Idempotente.
-- ============================================================

-- C1: cierra definitivamente la forja por RPC.
revoke execute on function simular_emision(uuid) from public;

-- M12: cuentas por cobrar reales.
create or replace function reporte_cuentas_por_cobrar(p_company_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'numero', serie || '-' || lpad(correlativo::text,8,'0'),
      'cliente', receptor_denominacion, 'total', total, 'saldo', saldo,
      'vencimiento', fecha_vencimiento, 'estado_pago', estado_pago) order by fecha_vencimiento nulls last), '[]'::jsonb)
  from documents
  where company_id = p_company_id and company_id in (select auth_company_ids())
    and tipo_doc in ('01','03') and estado_pago <> 'pagado'
    and estado_sunat = 'aceptado';
$$;
