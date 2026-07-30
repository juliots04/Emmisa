-- ============================================================
-- Emmisa · 0036 Reportes: netear notas de crédito (LOW de auditoría)
--   Las funciones de dashboard (reporte_resumen/ventas_por_dia/top_productos/
--   por_pago) sumaban SOLO ventas ('01','03') e ignoraban las NC ('07'). Con
--   devoluciones, las ventas se INFLABAN vs. el PLE (Registro de Ventas ya netea
--   la 07) y vs. el KPI "Facturado" de DocumentsPage (que también resta la 07).
--   Se incluye 07 en NEGATIVO y 08 (ND) en positivo para dejar los importes netos.
--   El conteo/ticket promedio sigue contando SOLO comprobantes de venta (01/03),
--   porque una nota no es "una venta más".
-- CREATE OR REPLACE conserva firmas y grants. Idempotente. Aplicar en cualquier momento.
-- ============================================================

-- (1) Resumen: importes netos, n/ticket sobre ventas puras
create or replace function reporte_resumen(p_company_id uuid, p_desde date default null, p_hasta date default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ventas',      coalesce(sum(total       * case when tipo_doc = '07' then -1 else 1 end), 0),
    'igv',         coalesce(sum(total_igv   * case when tipo_doc = '07' then -1 else 1 end), 0),
    'gravado',     coalesce(sum(total_gravado * case when tipo_doc = '07' then -1 else 1 end), 0),
    'n',           count(*) filter (where tipo_doc in ('01','03')),
    'ticket_prom', case when count(*) filter (where tipo_doc in ('01','03')) > 0
                     then round(coalesce(sum(total) filter (where tipo_doc in ('01','03')), 0)
                                / count(*) filter (where tipo_doc in ('01','03')), 2)
                     else 0 end)
  from documents
  where company_id = p_company_id
    and company_id in (select auth_company_ids())
    and tipo_doc in ('01','03','07','08') and estado_sunat = 'aceptado'
    and (p_desde is null or fecha_emision >= p_desde)
    and (p_hasta is null or fecha_emision <= p_hasta);
$$;

-- (2) Ventas por día: total neto por día, n solo de ventas
create or replace function reporte_ventas_por_dia(p_company_id uuid, p_dias integer default 30)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'total', total, 'n', n) order by dia), '[]'::jsonb)
  from (
    select fecha_emision as dia,
           sum(total * case when tipo_doc = '07' then -1 else 1 end) as total,
           count(*) filter (where tipo_doc in ('01','03')) as n
    from documents
    where company_id = p_company_id and company_id in (select auth_company_ids())
      and tipo_doc in ('01','03','07','08') and estado_sunat = 'aceptado'
      and fecha_emision >= current_date - (p_dias || ' days')::interval
    group by fecha_emision
  ) s;
$$;

-- (3) Top productos: cantidad/monto netos de devoluciones (NC descuenta)
create or replace function reporte_top_productos(p_company_id uuid, p_desde date default null, p_hasta date default null, p_limit integer default 10)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'descripcion', descripcion, 'cantidad', cantidad, 'monto', monto) order by cantidad desc), '[]'::jsonb)
  from (
    select di.descripcion,
           sum(di.cantidad * case when d.tipo_doc = '07' then -1 else 1 end) as cantidad,
           sum(di.total    * case when d.tipo_doc = '07' then -1 else 1 end) as monto
    from document_items di join documents d on d.id = di.document_id
    where d.company_id = p_company_id and d.company_id in (select auth_company_ids())
      and d.tipo_doc in ('01','03','07','08') and d.estado_sunat = 'aceptado'
      and (p_desde is null or d.fecha_emision >= p_desde)
      and (p_hasta is null or d.fecha_emision <= p_hasta)
    group by di.descripcion
    having sum(di.cantidad * case when d.tipo_doc = '07' then -1 else 1 end) > 0
    order by sum(di.cantidad * case when d.tipo_doc = '07' then -1 else 1 end) desc
    limit p_limit
  ) s;
$$;

-- (4) Por forma de pago: importe neto por medio
create or replace function reporte_por_pago(p_company_id uuid, p_desde date default null, p_hasta date default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(coalesce(forma_pago,'—'), total), '{}'::jsonb)
  from (
    select forma_pago, sum(total * case when tipo_doc = '07' then -1 else 1 end) total
    from documents
    where company_id = p_company_id and company_id in (select auth_company_ids())
      and tipo_doc in ('01','03','07','08') and estado_sunat = 'aceptado'
      and (p_desde is null or fecha_emision >= p_desde)
      and (p_hasta is null or fecha_emision <= p_hasta)
    group by forma_pago
  ) s;
$$;
