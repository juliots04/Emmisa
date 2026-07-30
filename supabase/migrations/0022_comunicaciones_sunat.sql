-- ============================================================
-- Emmisa · 0022 Comunicaciones SUNAT: Baja (RA) y Resumen de baja de boletas (RC)
--   Hasta ahora `anular_documento` solo anulaba LOCALMENTE (revertía stock/caja/CxC)
--   pero NO informaba a SUNAT, así que un comprobante ACEPTADO seguía "vivo" ante
--   SUNAT. Esto agrega el rastreo formal:
--     • Factura/Nota (01/07/08) aceptada  -> Comunicación de Baja (RA-YYYYMMDD-#)
--     • Boleta (03) aceptada              -> Resumen Diario con estado 3 (RC-YYYYMMDD-#)
--   La construcción del XML y el envío al PSE los hace la Edge Function `resumen`.
--   Aplicar DESPUÉS de 0021. Supabase → SQL Editor → Run (rol postgres). Idempotente.
-- ============================================================

create table if not exists sunat_comunicaciones (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id) on delete cascade,
  tipo            text not null check (tipo in ('RA', 'RC')),
  fecha_referencia date not null,     -- fecha de emisión de los comprobantes referenciados
  fecha_generacion date not null default current_date,
  correlativo     int  not null,
  identificador   text not null,      -- p.ej. RA-20260721-1
  estado          text not null default 'pendiente',  -- pendiente | aceptado | rechazado
  ticket          text,
  cdr             text,
  sunat_error     text,
  motivo          text,
  document_ids    uuid[] not null default '{}',
  created_at      timestamptz not null default now(),
  unique (company_id, tipo, fecha_generacion, correlativo)
);

alter table sunat_comunicaciones enable row level security;
drop policy if exists sunat_com_rw on sunat_comunicaciones;
create policy sunat_com_rw on sunat_comunicaciones for all to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

grant select on sunat_comunicaciones to authenticated;

-- Crea (o reutiliza) la comunicación SUNAT para dar de baja un comprobante aceptado.
-- Reserva un correlativo diario por tipo. Devuelve la fila para que la Edge Function
-- la construya y la envíe al PSE.
create or replace function crear_comunicacion(
  p_company_id  uuid,
  p_document_id uuid,
  p_motivo      text default 'Anulación de la operación'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc     documents%rowtype;
  v_tipo    text;
  v_corr    int;
  v_ident   text;
  v_id      uuid;
  v_exist   sunat_comunicaciones%rowtype;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;

  -- Tipo de comunicación según el comprobante.
  if v_doc.tipo_doc in ('01', '07', '08') then v_tipo := 'RA';
  elsif v_doc.tipo_doc = '03' then v_tipo := 'RC';
  else raise exception 'Este tipo de comprobante no se comunica por baja/resumen'; end if;

  -- Idempotencia: si ya hay una comunicación no rechazada para este doc, la reutiliza.
  select * into v_exist from sunat_comunicaciones
    where company_id = p_company_id and p_document_id = any(document_ids)
      and estado <> 'rechazado'
    order by created_at desc limit 1;
  if found then
    return jsonb_build_object('id', v_exist.id, 'identificador', v_exist.identificador,
      'tipo', v_exist.tipo, 'estado', v_exist.estado, 'reused', true);
  end if;

  -- Correlativo diario por tipo (lock para no saltar/duplicar).
  perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':com:' || v_tipo, 0));
  select coalesce(max(correlativo), 0) + 1 into v_corr from sunat_comunicaciones
    where company_id = p_company_id and tipo = v_tipo and fecha_generacion = current_date;
  v_ident := v_tipo || '-' || to_char(current_date, 'YYYYMMDD') || '-' || v_corr::text;

  insert into sunat_comunicaciones (company_id, tipo, fecha_referencia, correlativo, identificador, motivo, document_ids)
    values (p_company_id, v_tipo, v_doc.fecha_emision, v_corr, v_ident, p_motivo, array[p_document_id])
    returning id into v_id;

  return jsonb_build_object('id', v_id, 'identificador', v_ident, 'tipo', v_tipo, 'estado', 'pendiente', 'reused', false);
end $$;
grant execute on function crear_comunicacion(uuid, uuid, text) to authenticated, service_role;
