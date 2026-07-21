-- ============================================================
-- Konversa · Reportes server-side (agregación en SQL)
-- Arregla el subconteo silencioso: los reportes ya NO traen filas al
-- navegador (topadas por el límite de PostgREST) sino que agregan en Postgres.
-- Todas filtran por empresa del usuario (auth_company_ids) vía SECURITY DEFINER.
-- Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- Resumen de ventas del periodo (solo comprobantes aceptados; 01/03)
create or replace function reporte_resumen(
  p_company_id uuid, p_desde date default null, p_hasta date default null
)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ventas',      coalesce(sum(total), 0),
    'igv',         coalesce(sum(total_igv), 0),
    'gravado',     coalesce(sum(total_gravado), 0),
    'n',           count(*),
    'ticket_prom', case when count(*) > 0 then round(coalesce(sum(total),0) / count(*), 2) else 0 end)
  from documents
  where company_id = p_company_id
    and company_id in (select auth_company_ids())
    and tipo_doc in ('01','03') and estado_sunat = 'aceptado'
    and (p_desde is null or fecha_emision >= p_desde)
    and (p_hasta is null or fecha_emision <= p_hasta);
$$;

-- Ventas por día (últimos N días)
create or replace function reporte_ventas_por_dia(
  p_company_id uuid, p_dias int default 30
)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'total', total, 'n', n) order by dia), '[]'::jsonb)
  from (
    select fecha_emision as dia, sum(total) as total, count(*) as n
    from documents
    where company_id = p_company_id and company_id in (select auth_company_ids())
      and tipo_doc in ('01','03') and estado_sunat = 'aceptado'
      and fecha_emision >= current_date - (p_dias || ' days')::interval
    group by fecha_emision
  ) s;
$$;

-- Top productos por cantidad y monto
create or replace function reporte_top_productos(
  p_company_id uuid, p_desde date default null, p_hasta date default null, p_limit int default 10
)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'descripcion', descripcion, 'cantidad', cantidad, 'monto', monto) order by cantidad desc), '[]'::jsonb)
  from (
    select di.descripcion, sum(di.cantidad) as cantidad, sum(di.total) as monto
    from document_items di join documents d on d.id = di.document_id
    where d.company_id = p_company_id and d.company_id in (select auth_company_ids())
      and d.tipo_doc in ('01','03') and d.estado_sunat = 'aceptado'
      and (p_desde is null or d.fecha_emision >= p_desde)
      and (p_hasta is null or d.fecha_emision <= p_hasta)
    group by di.descripcion
    order by sum(di.cantidad) desc
    limit p_limit
  ) s;
$$;

-- Comprobantes por estado SUNAT
create or replace function reporte_por_estado(
  p_company_id uuid, p_desde date default null, p_hasta date default null
)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(estado_sunat, jsonb_build_object('n', n, 'total', total)), '{}'::jsonb)
  from (
    select estado_sunat, count(*) n, sum(total) total
    from documents
    where company_id = p_company_id and company_id in (select auth_company_ids())
      and (p_desde is null or fecha_emision >= p_desde)
      and (p_hasta is null or fecha_emision <= p_hasta)
    group by estado_sunat
  ) s;
$$;

-- Ventas por forma de pago
create or replace function reporte_por_pago(
  p_company_id uuid, p_desde date default null, p_hasta date default null
)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(coalesce(forma_pago,'—'), total), '{}'::jsonb)
  from (
    select forma_pago, sum(total) total
    from documents
    where company_id = p_company_id and company_id in (select auth_company_ids())
      and tipo_doc in ('01','03') and estado_sunat = 'aceptado'
      and (p_desde is null or fecha_emision >= p_desde)
      and (p_hasta is null or fecha_emision <= p_hasta)
    group by forma_pago
  ) s;
$$;

-- Cuentas por cobrar (saldos pendientes)
create or replace function reporte_cuentas_por_cobrar(p_company_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'numero', serie || '-' || lpad(correlativo::text,8,'0'),
      'cliente', receptor_denominacion, 'total', total, 'saldo', saldo,
      'vencimiento', fecha_vencimiento, 'estado_pago', estado_pago) order by fecha_vencimiento nulls last), '[]'::jsonb)
  from documents
  where company_id = p_company_id and company_id in (select auth_company_ids())
    and tipo_doc in ('01','03') and estado_pago <> 'pagado';
$$;

-- Productos bajo el stock mínimo
create or replace function reporte_stock_minimo(p_company_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'nombre', p.nombre, 'sku', p.sku,
      'stock', coalesce(s.total, 0), 'minimo', p.stock_minimo) order by coalesce(s.total,0)), '[]'::jsonb)
  from products p
  left join (select product_id, sum(cantidad) total from stock group by product_id) s on s.product_id = p.id
  where p.company_id = p_company_id and p.company_id in (select auth_company_ids())
    and p.controla_stock and coalesce(p.stock_minimo,0) > 0
    and coalesce(s.total,0) <= p.stock_minimo;
$$;

grant execute on all functions in schema public to anon, authenticated, service_role;
