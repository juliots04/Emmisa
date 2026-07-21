-- ============================================================
-- Konversa · APLICAR TODO (migraciones 0010 → 0017) en un solo pegado
-- Supabase → SQL Editor → pega TODO → Run. Idempotente.
-- Orden importante: 0016 y 0017 endurecen lo de 0010-0015, van al final.
-- ============================================================

-- >>>>>>>>>>>>>>>>>>>> migrations/0010_plataforma.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Konversa · Capa SaaS / marca blanca (revendedor)
-- Añade el bloque de PLATAFORMA que faltaba por completo:
--   resellers, plans, subscriptions, subscription_payments,
--   brands, webhooks, audit_events, emisor_credentials.
-- Aísla por RLS igual que el resto. Idempotente (create if not exists).
-- Cómo usarlo: Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- ==================== REVENDEDOR (marca blanca) ====================
create table if not exists resellers (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  nombre      text not null,
  dominio     text,                                   -- subdominio/dominio propio
  branding    jsonb not null default '{}'::jsonb,     -- { logo_url, color_primario, color_secundario, nombre_comercial }
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Cada empresa emisora puede pertenecer a un revendedor.
alter table companies add column if not exists reseller_id uuid references resellers(id) on delete set null;
alter table companies add column if not exists config      jsonb not null default '{}'::jsonb;

-- ==================== PLANES / SUSCRIPCIONES ====================
create table if not exists plans (
  id           uuid primary key default gen_random_uuid(),
  reseller_id  uuid not null references resellers(id) on delete cascade,
  nombre       text not null,
  precio       numeric(12,2) not null default 0,
  moneda       text not null default 'PEN',
  periodicidad text not null default 'mensual',       -- mensual | anual
  limites      jsonb not null default '{}'::jsonb,     -- { max_comprobantes, max_empresas, max_usuarios }
  activo       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists subscriptions (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references companies(id) on delete cascade,
  plan_id        uuid references plans(id) on delete set null,
  estado         text not null default 'activa',       -- activa | vencida | suspendida | cancelada
  periodo_inicio date not null default current_date,
  periodo_fin    date,
  created_at     timestamptz not null default now()
);

create table if not exists subscription_payments (
  id              uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references subscriptions(id) on delete cascade,
  monto           numeric(12,2) not null default 0,
  medio           text,                                -- yape | transferencia | tarjeta | efectivo
  estado          text not null default 'pagado',      -- pagado | pendiente | fallido
  referencia      text,
  fecha           date not null default current_date,
  created_at      timestamptz not null default now()
);

-- ==================== MARCAS DE PRODUCTO ====================
create table if not exists brands (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  nombre      text not null,
  created_at  timestamptz not null default now()
);

-- ==================== WEBHOOKS ====================
create table if not exists webhooks (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  url         text not null,
  eventos     text[] not null default '{}',
  secret      text,
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ==================== AUDITORÍA ====================
create table if not exists audit_events (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid references companies(id) on delete set null,
  user_id     uuid references auth.users(id) on delete set null,
  accion      text not null,                           -- insert | update | delete | emitir | anular | login...
  entidad     text,
  entidad_id  uuid,
  payload     jsonb,
  created_at  timestamptz not null default now()
);

-- ==================== CREDENCIALES DEL EMISOR (SENSIBLE) ====================
-- Guarda el token del PSE/OSE (APISUNAT/Nubefact) por empresa.
-- RLS: los admin de la empresa pueden ESCRIBIR (upsert) pero NO LEER el token de vuelta.
-- Solo la Edge Function (service_role, que salta RLS) lo lee para emitir.
create table if not exists emisor_credentials (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  provider    text not null default 'apisunat',        -- apisunat | nubefact
  persona_id  text,                                    -- APISUNAT personaId
  token       text,                                    -- APISUNAT personaToken (secreto)
  extra       jsonb not null default '{}'::jsonb,      -- otros datos del proveedor
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, provider)
);

-- ==================== HELPERS DE RLS ====================
-- Revendedores que administra el usuario actual.
create or replace function auth_reseller_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select id from resellers where owner_id = auth.uid()
$$;

-- ¿El usuario actual es admin (rol 'admin') de esta empresa?
create or replace function is_company_admin(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships
    where user_id = auth.uid() and company_id = p_company_id and role = 'admin'
  )
$$;

-- Empresas cuyo revendedor administra el usuario actual (para el panel del reseller).
create or replace function auth_reseller_company_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select id from companies where reseller_id in (select auth_reseller_ids())
$$;

-- ==================== RLS ====================
alter table resellers             enable row level security;
alter table plans                 enable row level security;
alter table subscriptions         enable row level security;
alter table subscription_payments enable row level security;
alter table brands                enable row level security;
alter table webhooks              enable row level security;
alter table audit_events          enable row level security;
alter table emisor_credentials    enable row level security;

-- resellers: el dueño gestiona lo suyo.
drop policy if exists resellers_all on resellers;
create policy resellers_all on resellers for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- companies: además del owner/miembro (0007), el revendedor ve y gestiona sus empresas.
drop policy if exists companies_select_reseller on companies;
create policy companies_select_reseller on companies for select
  using (reseller_id in (select auth_reseller_ids()));
drop policy if exists companies_update_reseller on companies;
create policy companies_update_reseller on companies for update
  using (reseller_id in (select auth_reseller_ids()));

-- plans: el revendedor gestiona; los miembros de una empresa del revendedor pueden verlos.
drop policy if exists plans_reseller_all on plans;
create policy plans_reseller_all on plans for all
  using (reseller_id in (select auth_reseller_ids()))
  with check (reseller_id in (select auth_reseller_ids()));
drop policy if exists plans_member_select on plans;
create policy plans_member_select on plans for select
  using (reseller_id in (
    select reseller_id from companies where id in (select auth_company_ids())
  ));

-- subscriptions: miembros ven la de su empresa; el revendedor gestiona.
drop policy if exists subs_member_select on subscriptions;
create policy subs_member_select on subscriptions for select
  using (company_id in (select auth_company_ids())
      or company_id in (select auth_reseller_company_ids()));
drop policy if exists subs_reseller_all on subscriptions;
create policy subs_reseller_all on subscriptions for all
  using (company_id in (select auth_reseller_company_ids()))
  with check (company_id in (select auth_reseller_company_ids()));

-- subscription_payments: vía la suscripción (empresa del revendedor).
drop policy if exists subpays_all on subscription_payments;
create policy subpays_all on subscription_payments for all
  using (subscription_id in (
    select id from subscriptions where company_id in (
      select auth_reseller_company_ids() union select auth_company_ids())))
  with check (subscription_id in (
    select id from subscriptions where company_id in (select auth_reseller_company_ids())));

-- brands / webhooks: aislados por empresa (patrón estándar).
drop policy if exists brands_all on brands;
create policy brands_all on brands for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));
drop policy if exists webhooks_all on webhooks;
create policy webhooks_all on webhooks for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- audit_events: los miembros de la empresa pueden LEER; la escritura la hacen triggers (definer).
drop policy if exists audit_select on audit_events;
create policy audit_select on audit_events for select
  using (company_id in (select auth_company_ids()));

-- emisor_credentials: los admin ESCRIBEN sus credenciales; NADIE (authenticated) las LEE.
-- (sin policy de SELECT → la Data API no puede leer el token; solo service_role lo lee).
drop policy if exists emisorcred_insert on emisor_credentials;
create policy emisorcred_insert on emisor_credentials for insert
  with check (is_company_admin(company_id));
drop policy if exists emisorcred_update on emisor_credentials;
create policy emisorcred_update on emisor_credentials for update
  using (is_company_admin(company_id)) with check (is_company_admin(company_id));
drop policy if exists emisorcred_delete on emisor_credentials;
create policy emisorcred_delete on emisor_credentials for delete
  using (is_company_admin(company_id));

-- ==================== Helpers seguros de credenciales ====================
-- El frontend NO puede leer el token (sin policy SELECT). Estas funciones
-- (security definer) permiten guardar y consultar el ESTADO sin exponer el secreto.
create or replace function guardar_credenciales(
  p_company_id uuid, p_provider text, p_persona_id text, p_token text, p_extra jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_company_admin(p_company_id) then
    raise exception 'Solo un admin puede configurar las credenciales del emisor';
  end if;
  insert into emisor_credentials (company_id, provider, persona_id, token, extra, updated_at)
    values (p_company_id, coalesce(p_provider,'apisunat'), p_persona_id, p_token, coalesce(p_extra,'{}'::jsonb), now())
    on conflict (company_id, provider)
    do update set persona_id = excluded.persona_id, token = excluded.token,
                  extra = excluded.extra, activo = true, updated_at = now();
  return jsonb_build_object('ok', true, 'provider', coalesce(p_provider,'apisunat'));
end $$;
grant execute on function guardar_credenciales(uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function tiene_credenciales(p_company_id uuid, p_provider text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from emisor_credentials
    where company_id = p_company_id and activo
      and coalesce(token,'') <> ''
      and (p_provider is null or provider = p_provider)
      and company_id in (select auth_company_ids()));
$$;
grant execute on function tiene_credenciales(uuid, text) to authenticated, service_role;

-- ==================== GRANTS (Data API) ====================
-- Reaplica el patrón del proyecto para las tablas nuevas.
grant all privileges on all tables    in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
grant execute        on all functions in schema public to anon, authenticated, service_role;

-- Defensa extra: el token del emisor NO debe ser accesible por el rol anónimo.
revoke all on emisor_credentials from anon;

-- >>>>>>>>>>>>>>>>>>>> migrations/0011_comprobantes_campos.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Konversa · Campos de comprobante para cumplimiento SUNAT real
-- Añade a `documents` los totales por afectación, los datos del receptor
-- "varios" (que hoy se perdían), moneda/tipo de cambio, fecha de emisión,
-- hash/QR, ticket asíncrono y condición de pago (para cuentas por cobrar).
-- Crea la tabla `payments` (pagos y abonos) y extiende compras.
-- Idempotente. Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- ==================== documents ====================
alter table documents add column if not exists establishment_id     uuid references establishments(id) on delete set null;
-- Totales por tipo de afectación (SUNAT exige desglose)
alter table documents add column if not exists total_exonerado      numeric(12,2) not null default 0;
alter table documents add column if not exists total_inafecto       numeric(12,2) not null default 0;
alter table documents add column if not exists total_gratuito       numeric(12,2) not null default 0;
alter table documents add column if not exists total_icbper         numeric(12,2) not null default 0;
alter table documents add column if not exists total_isc            numeric(12,2) not null default 0;
alter table documents add column if not exists descuento_global     numeric(12,2) not null default 0;
-- Moneda / tipo de cambio
alter table documents add column if not exists tipo_cambio          numeric(12,3) not null default 1;
-- Fechas y firma
alter table documents add column if not exists fecha_emision        date not null default current_date;
alter table documents add column if not exists fecha_vencimiento    date;
alter table documents add column if not exists hash                 text;   -- digest de la firma
alter table documents add column if not exists codigo_qr            text;
alter table documents add column if not exists sunat_ticket         text;   -- ticket asíncrono (boletas/resúmenes)
alter table documents add column if not exists sunat_error          text;   -- observación/rechazo
-- Receptor "varios" persistido (antes solo se guardaba customer_id)
alter table documents add column if not exists receptor_tipo_doc    text;
alter table documents add column if not exists receptor_num_doc     text;
alter table documents add column if not exists receptor_denominacion text;
alter table documents add column if not exists receptor_direccion   text;
-- Condición de pago y cuentas por cobrar
alter table documents add column if not exists condicion_pago       text not null default 'contado'; -- contado | credito
alter table documents add column if not exists estado_pago          text not null default 'pagado';  -- pagado | pendiente | parcial
alter table documents add column if not exists saldo                numeric(12,2) not null default 0;
-- Notas: motivo (catálogo 09 NC / 10 ND)
alter table documents add column if not exists motivo_codigo        text;
alter table documents add column if not exists motivo_desc          text;

-- ==================== document_items ====================
alter table document_items add column if not exists tipo_afectacion text not null default '10'; -- 10 grav, 20 exon, 30 inaf, 21 gratuito
alter table document_items add column if not exists unidad_medida   text not null default 'NIU';
alter table document_items add column if not exists codigo_producto text;
alter table document_items add column if not exists descuento       numeric(12,2) not null default 0;

-- ==================== products (FK catálogo) ====================
alter table products add column if not exists category_id uuid references categories(id) on delete set null;
alter table products add column if not exists brand_id    uuid references brands(id)     on delete set null;

-- ==================== caja / compras: establecimiento y CxP ====================
alter table cash_sessions add column if not exists establishment_id uuid references establishments(id) on delete set null;
alter table cash_sessions add column if not exists terminal_id      text;

alter table purchases add column if not exists moneda            text not null default 'PEN';
alter table purchases add column if not exists total_gravado     numeric(12,2) not null default 0;
alter table purchases add column if not exists total_igv         numeric(12,2) not null default 0;
alter table purchases add column if not exists condicion_pago    text not null default 'contado';
alter table purchases add column if not exists estado_pago       text not null default 'pagado';
alter table purchases add column if not exists saldo             numeric(12,2) not null default 0;
alter table purchases add column if not exists fecha_vencimiento date;
alter table purchases add column if not exists afecta_inventario boolean not null default false;
alter table purchases add column if not exists warehouse_id      uuid references warehouses(id) on delete set null;

alter table purchase_items add column if not exists product_id uuid references products(id) on delete set null;

-- ==================== payments (pagos y abonos: CxC / CxP) ====================
-- Un registro por cada cobro (a un comprobante) o pago (a una compra).
create table if not exists payments (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  tipo             text not null default 'cobro',   -- cobro (CxC) | pago (CxP)
  document_id      uuid references documents(id) on delete cascade,
  purchase_id      uuid references purchases(id) on delete cascade,
  cash_session_id  uuid references cash_sessions(id) on delete set null,
  medio            text not null default 'efectivo',
  monto            numeric(12,2) not null default 0,
  referencia       text,
  fecha            date not null default current_date,
  created_at       timestamptz not null default now()
);

create index if not exists ix_payments_document on payments(document_id);
create index if not exists ix_payments_purchase on payments(purchase_id);
create index if not exists ix_documents_estado_pago on documents(company_id, estado_pago) where estado_pago <> 'pagado';

alter table payments enable row level security;
drop policy if exists payments_all on payments;
create policy payments_all on payments for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- ==================== GRANTS (Data API) ====================
grant all privileges on all tables    in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
grant execute        on all functions in schema public to anon, authenticated, service_role;

-- >>>>>>>>>>>>>>>>>>>> migrations/0012_emitir_venta_v2.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Konversa · emitir_venta v2 (reemplaza 0009)
-- Corrige de raíz:
--   • Correlativo que se "quemaba" en carreras de idempotencia
--     → lock advisory por (empresa, llave) serializa; ya no salta la numeración.
--   • IGV falso en exonerado/inafecto → respeta tipo_afectacion por ítem.
--   • Receptor "varios" que se perdía → se persiste en documents.receptor_*.
--   • Factura sin RUC válido → valida receptor vs tipo de comprobante.
--   • Kardex omitido si no había fila de stock → crea almacén/fila y SIEMPRE mueve kardex.
--   • Moneda fija PEN → moneda + tipo de cambio; condición de pago (contado/crédito → CxC).
-- Idempotente. Supabase → SQL Editor → pega TODO → Run
-- ============================================================

drop function if exists emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric);

create or replace function emitir_venta(
  p_company_id       uuid,
  p_tipo_doc         text,
  p_serie            text,
  p_cliente          jsonb,          -- { customer_id?, tipo_doc, num_doc?, denominacion, direccion? }
  p_items            jsonb,          -- [ { product_id?, descripcion, cantidad, precio_unitario, tipo_afectacion?, unidad_medida? } ]
  p_forma_pago       text    default 'efectivo',
  p_monto_recibido   numeric default null,
  p_vuelto           numeric default null,
  p_cash_session_id  uuid    default null,
  p_idempotency_key  text    default null,
  p_igv_rate         numeric default 0.18,
  p_moneda           text    default 'PEN',
  p_tipo_cambio      numeric default 1,
  p_condicion_pago   text    default 'contado',
  p_fecha_vencimiento date   default null,
  p_establishment_id uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_correlativo  int;
  v_doc_id       uuid;
  v_customer_id  uuid;
  v_existing     documents%rowtype;
  v_item         jsonb;
  v_pid          uuid;
  v_qty          numeric;
  v_afect        text;
  v_price        numeric;
  v_line_total   numeric(12,2);
  v_line_base    numeric(12,2);
  v_line_igv     numeric(12,2);
  v_total        numeric(12,2) := 0;
  v_gravado      numeric(12,2) := 0;
  v_igv          numeric(12,2) := 0;
  v_exonerado    numeric(12,2) := 0;
  v_inafecto     numeric(12,2) := 0;
  v_gratuito     numeric(12,2) := 0;
  v_wh           uuid;
  v_numero       text;
  v_attempts     int := 0;
  v_estado_pago  text;
  v_saldo        numeric(12,2);
  -- receptor
  v_r_tipo       text := coalesce(nullif(p_cliente->>'tipo_doc',''), '0');
  v_r_num        text := nullif(p_cliente->>'num_doc','');
  v_r_den        text := coalesce(nullif(p_cliente->>'denominacion',''), 'Cliente varios');
  v_r_dir        text := nullif(p_cliente->>'direccion','');
begin
  -- 0) Seguridad multiempresa
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene ítems';
  end if;

  -- 0.1) Validación receptor vs tipo de comprobante (SUNAT)
  --      Factura (01) exige RUC (tipo 6, 11 dígitos). ND/NC heredan del original en emitir_nota.
  if p_tipo_doc = '01' then
    if v_r_tipo <> '6' or v_r_num is null or v_r_num !~ '^\d{11}$' then
      raise exception 'Una factura (01) requiere un cliente con RUC válido de 11 dígitos';
    end if;
  end if;

  -- 0.2) Idempotencia con lock advisory por (empresa, llave):
  --      dos requests con la MISMA llave se serializan; el segundo encuentra el doc ya
  --      creado y retorna SIN consumir correlativo (no hay salto de numeración).
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object(
        'id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total_gravado', v_existing.total_gravado,
        'total_igv', v_existing.total_igv, 'total', v_existing.total,
        'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;

  -- 1) Caja abierta (flujo POS)
  if p_cash_session_id is not null then
    perform 1 from cash_sessions
      where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then
      raise exception 'No hay una caja abierta para registrar la venta';
    end if;
  end if;

  -- 2) Totales respetando el tipo de afectación por ítem
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid   := nullif(v_item->>'product_id','')::uuid;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_afect := coalesce(
      nullif(v_item->>'tipo_afectacion',''),
      (select tipo_afectacion from products where id = v_pid and company_id = p_company_id),
      '10');
    v_line_total := round(v_qty * v_price, 2);

    if v_afect = '10' then                                  -- gravado (precio incluye IGV)
      v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
      v_line_igv  := v_line_total - v_line_base;
      v_gravado   := v_gravado + v_line_base;
      v_igv       := v_igv + v_line_igv;
      v_total     := v_total + v_line_total;
    elsif v_afect = '20' then                               -- exonerado (sin IGV)
      v_exonerado := v_exonerado + v_line_total;
      v_total     := v_total + v_line_total;
    elsif v_afect = '30' then                               -- inafecto (sin IGV)
      v_inafecto  := v_inafecto + v_line_total;
      v_total     := v_total + v_line_total;
    elsif left(v_afect, 1) = '2' or left(v_afect, 1) = '3' then  -- gratuito (21,31..) no suma a pagar
      v_gratuito  := v_gratuito + v_line_total;
    else
      v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
      v_line_igv  := v_line_total - v_line_base;
      v_gravado   := v_gravado + v_line_base;
      v_igv       := v_igv + v_line_igv;
      v_total     := v_total + v_line_total;
    end if;
  end loop;

  -- Vínculo de cliente registrado (opcional). El receptor SIEMPRE se persiste aparte.
  v_customer_id := nullif(p_cliente->>'customer_id', '')::uuid;
  if v_customer_id is not null
     and not exists (select 1 from customers where id = v_customer_id and company_id = p_company_id) then
    v_customer_id := null;
  end if;

  -- Condición de pago → cuentas por cobrar
  if p_condicion_pago = 'credito' then
    v_estado_pago := 'pendiente';
    v_saldo := v_total;
  else
    v_estado_pago := 'pagado';
    v_saldo := 0;
  end if;

  -- 3) Reserva de correlativo + INSERT atómico, con reintento ante colisión de correlativo.
  loop
    v_attempts := v_attempts + 1;
    insert into series (company_id, tipo_doc, serie, correlativo, establishment_id)
      values (p_company_id, p_tipo_doc, p_serie, 0, p_establishment_id)
      on conflict (company_id, tipo_doc, serie) do nothing;
    update series set correlativo = correlativo + 1
      where company_id = p_company_id and tipo_doc = p_tipo_doc and serie = p_serie
      returning correlativo into v_correlativo;
    v_numero := p_serie || '-' || lpad(v_correlativo::text, 8, '0');

    begin
      insert into documents (
        company_id, establishment_id, customer_id, tipo_doc, serie, correlativo,
        moneda, tipo_cambio, total_gravado, total_igv, total_exonerado, total_inafecto,
        total_gratuito, total, estado_sunat, user_id, cash_session_id, forma_pago,
        monto_recibido, vuelto, condicion_pago, estado_pago, saldo, fecha_vencimiento,
        receptor_tipo_doc, receptor_num_doc, receptor_denominacion, receptor_direccion,
        idempotency_key
      ) values (
        p_company_id, p_establishment_id, v_customer_id, p_tipo_doc, p_serie, v_correlativo,
        p_moneda, p_tipo_cambio, v_gravado, v_igv, v_exonerado, v_inafecto,
        v_gratuito, v_total, 'pendiente', v_user_id, p_cash_session_id, p_forma_pago,
        p_monto_recibido, p_vuelto, p_condicion_pago, v_estado_pago, v_saldo, p_fecha_vencimiento,
        v_r_tipo, v_r_num, v_r_den, v_r_dir,
        coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;                                                 -- éxito
    exception when unique_violation then
      -- Si chocó por idempotencia (carrera muy rara pese al lock), devolver el existente.
      if p_idempotency_key is not null then
        select * into v_existing from documents
          where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object(
            'id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
            'tipo_doc', v_existing.tipo_doc, 'total_gravado', v_existing.total_gravado,
            'total_igv', v_existing.total_igv, 'total', v_existing.total,
            'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;                -- colisión de correlativo: reintenta
    end;
  end loop;

  -- 4) Ítems + kardex robusto
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null
       and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_afect := coalesce(
      nullif(v_item->>'tipo_afectacion',''),
      (select tipo_afectacion from products where id = v_pid), '10');
    v_line_total := round(v_qty * v_price, 2);
    if v_afect = '10' then
      v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
      v_line_igv  := v_line_total - v_line_base;
    else
      v_line_base := v_line_total;
      v_line_igv  := 0;
    end if;

    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion, unidad_medida
    ) values (
      v_doc_id, v_pid, v_item->>'descripcion', v_qty,
      case when v_qty <> 0 then round(v_line_base / v_qty, 2) else 0 end,
      v_price, v_line_igv, v_line_total, v_afect,
      coalesce(nullif(v_item->>'unidad_medida',''), 'NIU')
    );

    -- Kardex: si el producto controla stock, garantiza almacén + fila y SIEMPRE registra salida.
    if v_pid is not null
       and exists (select 1 from products where id = v_pid and controla_stock) then
      -- almacén con más stock; si no hay fila, cualquiera de la empresa; si no hay almacén, crea 'Principal'.
      select warehouse_id into v_wh from stock where product_id = v_pid
        order by cantidad desc limit 1 for update;
      if v_wh is null then
        select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
      end if;
      if v_wh is null then
        insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh;
      end if;
      insert into stock (product_id, warehouse_id, cantidad) values (v_pid, v_wh, 0)
        on conflict (product_id, warehouse_id) do nothing;
      update stock set cantidad = cantidad - v_qty where product_id = v_pid and warehouse_id = v_wh;
      insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
        values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
    end if;
  end loop;

  -- 5) Pago: ledger de pagos (para contado) + efectivo al arqueo de caja.
  if p_condicion_pago = 'contado' then
    insert into payments (company_id, tipo, document_id, cash_session_id, medio, monto, fecha)
      values (p_company_id, 'cobro', v_doc_id, p_cash_session_id, p_forma_pago, v_total, current_date);
    if p_cash_session_id is not null and p_forma_pago = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'ingreso', v_total, 'Venta ' || v_numero, v_doc_id);
    end if;
  end if;

  return jsonb_build_object(
    'id', v_doc_id, 'serie', p_serie, 'correlativo', v_correlativo, 'numero', v_numero,
    'tipo_doc', p_tipo_doc, 'total_gravado', v_gravado, 'total_igv', v_igv,
    'total_exonerado', v_exonerado, 'total_inafecto', v_inafecto, 'total_gratuito', v_gratuito,
    'total', v_total, 'estado_sunat', 'pendiente', 'reused', false
  );
end $$;

grant execute on function emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric, text, numeric, text, date, uuid)
  to authenticated, service_role;

-- >>>>>>>>>>>>>>>>>>>> migrations/0013_notas.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Konversa · Notas de crédito/débito y anulación (transaccional)
-- Reemplaza el correlativo "naive" (select max()+1) de creditnotes.api.ts
-- por una reserva atómica con lock, idempotencia y afectación por ítem.
-- Agrega anular_documento (base de la comunicación de baja RA).
-- Supabase → SQL Editor → pega TODO → Run
-- ============================================================

create or replace function emitir_nota(
  p_company_id      uuid,
  p_ref_document_id uuid,
  p_tipo_nota       text,           -- 07 nota de crédito | 08 nota de débito
  p_motivo_codigo   text,
  p_motivo_desc     text,
  p_items           jsonb   default null,  -- si null, copia el total del original en 1 línea
  p_idempotency_key text    default null,
  p_igv_rate        numeric default 0.18
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref          documents%rowtype;
  v_serie        text;
  v_correlativo  int;
  v_doc_id       uuid;
  v_existing     documents%rowtype;
  v_item         jsonb;
  v_qty          numeric;
  v_price        numeric;
  v_afect        text;
  v_line_total   numeric(12,2);
  v_line_base    numeric(12,2);
  v_line_igv     numeric(12,2);
  v_total        numeric(12,2) := 0;
  v_gravado      numeric(12,2) := 0;
  v_igv          numeric(12,2) := 0;
  v_exonerado    numeric(12,2) := 0;
  v_inafecto     numeric(12,2) := 0;
  v_attempts     int := 0;
  v_numero_ref   text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_tipo_nota not in ('07','08') then
    raise exception 'Tipo de nota inválido (use 07 o 08)';
  end if;

  select * into v_ref from documents
    where id = p_ref_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante original no encontrado'; end if;
  if v_ref.tipo_doc not in ('01','03') then
    raise exception 'Solo se emiten notas sobre facturas (01) o boletas (03)';
  end if;

  -- Serie de la nota según tipo de comprobante afectado
  if p_tipo_nota = '07' then
    v_serie := case when v_ref.tipo_doc = '01' then 'FC01' else 'BC01' end;
  else
    v_serie := case when v_ref.tipo_doc = '01' then 'FD01' else 'BD01' end;
  end if;
  v_numero_ref := v_ref.serie || '-' || lpad(v_ref.correlativo::text, 8, '0');

  -- Idempotencia (lock advisory por llave)
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie,
        'correlativo', v_existing.correlativo, 'tipo_doc', v_existing.tipo_doc,
        'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;

  -- Totales: por ítems (parcial) o copiando el original completo
  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for v_item in select * from jsonb_array_elements(p_items) loop
      v_qty   := (v_item->>'cantidad')::numeric;
      v_price := (v_item->>'precio_unitario')::numeric;
      v_afect := coalesce(nullif(v_item->>'tipo_afectacion',''), '10');
      v_line_total := round(v_qty * v_price, 2);
      if v_afect = '10' then
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
        v_line_igv  := v_line_total - v_line_base;
        v_gravado := v_gravado + v_line_base; v_igv := v_igv + v_line_igv;
      elsif v_afect = '20' then v_exonerado := v_exonerado + v_line_total;
      elsif v_afect = '30' then v_inafecto := v_inafecto + v_line_total;
      else
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
        v_gravado := v_gravado + v_line_base; v_igv := v_igv + (v_line_total - v_line_base);
      end if;
      v_total := v_total + v_line_total;
    end loop;
  else
    v_gravado   := v_ref.total_gravado;
    v_igv       := v_ref.total_igv;
    v_exonerado := coalesce(v_ref.total_exonerado, 0);
    v_inafecto  := coalesce(v_ref.total_inafecto, 0);
    v_total     := v_ref.total;
  end if;

  -- Reserva de correlativo + insert atómico (con reintento)
  loop
    v_attempts := v_attempts + 1;
    insert into series (company_id, tipo_doc, serie, correlativo)
      values (p_company_id, p_tipo_nota, v_serie, 0)
      on conflict (company_id, tipo_doc, serie) do nothing;
    update series set correlativo = correlativo + 1
      where company_id = p_company_id and tipo_doc = p_tipo_nota and serie = v_serie
      returning correlativo into v_correlativo;

    begin
      insert into documents (
        company_id, establishment_id, customer_id, tipo_doc, serie, correlativo,
        moneda, tipo_cambio, total_gravado, total_igv, total_exonerado, total_inafecto,
        total, estado_sunat, ref_document_id, motivo_codigo, motivo_desc,
        receptor_tipo_doc, receptor_num_doc, receptor_denominacion, receptor_direccion,
        idempotency_key
      ) values (
        p_company_id, v_ref.establishment_id, v_ref.customer_id, p_tipo_nota, v_serie, v_correlativo,
        v_ref.moneda, coalesce(v_ref.tipo_cambio,1), v_gravado, v_igv, v_exonerado, v_inafecto,
        v_total, 'pendiente', p_ref_document_id, p_motivo_codigo, p_motivo_desc,
        v_ref.receptor_tipo_doc, v_ref.receptor_num_doc, v_ref.receptor_denominacion, v_ref.receptor_direccion,
        coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;
    exception when unique_violation then
      if p_idempotency_key is not null then
        select * into v_existing from documents
          where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie,
            'correlativo', v_existing.correlativo, 'tipo_doc', v_existing.tipo_doc,
            'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;
    end;
  end loop;

  -- Ítems de la nota
  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for v_item in select * from jsonb_array_elements(p_items) loop
      v_qty   := (v_item->>'cantidad')::numeric;
      v_price := (v_item->>'precio_unitario')::numeric;
      v_afect := coalesce(nullif(v_item->>'tipo_afectacion',''), '10');
      v_line_total := round(v_qty * v_price, 2);
      if v_afect = '10' then
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
        v_line_igv  := v_line_total - v_line_base;
      else v_line_base := v_line_total; v_line_igv := 0; end if;
      insert into document_items (document_id, product_id, descripcion, cantidad,
        valor_unitario, precio_unitario, igv, total, tipo_afectacion, unidad_medida)
      values (v_doc_id, nullif(v_item->>'product_id','')::uuid, v_item->>'descripcion', v_qty,
        case when v_qty <> 0 then round(v_line_base / v_qty, 2) else 0 end,
        v_price, v_line_igv, v_line_total, v_afect, coalesce(nullif(v_item->>'unidad_medida',''),'NIU'));
    end loop;
  else
    insert into document_items (document_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion)
    values (v_doc_id,
      (case when p_tipo_nota='07' then 'Nota de crédito' else 'Nota de débito' end)
        || ' (' || coalesce(p_motivo_codigo,'') || ' · ' || coalesce(p_motivo_desc,'') || ') sobre ' || v_numero_ref,
      1, v_gravado, v_total, v_igv, v_total, '10');
  end if;

  return jsonb_build_object('id', v_doc_id, 'serie', v_serie, 'correlativo', v_correlativo,
    'tipo_doc', p_tipo_nota, 'total_gravado', v_gravado, 'total_igv', v_igv,
    'total', v_total, 'estado_sunat', 'pendiente', 'reused', false);
end $$;

grant execute on function emitir_nota(uuid, uuid, text, text, text, jsonb, text, numeric)
  to authenticated, service_role;

-- ==================== Anulación / baja ====================
-- Marca el comprobante como anulado y revierte el stock de sus ítems.
-- (La comunicación formal RA a SUNAT la dispara la Edge Function.)
create or replace function anular_documento(
  p_company_id uuid,
  p_document_id uuid,
  p_motivo text default 'Anulación'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc   documents%rowtype;
  v_it    record;
  v_wh    uuid;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat = 'anulado' then
    return jsonb_build_object('id', v_doc.id, 'estado_sunat', 'anulado', 'ya', true);
  end if;

  -- Revertir kardex (reingresar lo vendido)
  for v_it in select * from document_items where document_id = p_document_id and product_id is not null loop
    if exists (select 1 from products where id = v_it.product_id and controla_stock) then
      select warehouse_id into v_wh from stock where product_id = v_it.product_id order by cantidad desc limit 1;
      if v_wh is null then
        select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
      end if;
      if v_wh is not null then
        insert into stock (product_id, warehouse_id, cantidad) values (v_it.product_id, v_wh, 0)
          on conflict (product_id, warehouse_id) do nothing;
        update stock set cantidad = cantidad + v_it.cantidad where product_id = v_it.product_id and warehouse_id = v_wh;
        insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
          values (p_company_id, v_it.product_id, v_wh, 'ingreso', v_it.cantidad,
                  'Anulación ' || v_doc.serie || '-' || lpad(v_doc.correlativo::text,8,'0'));
      end if;
    end if;
  end loop;

  update documents set estado_sunat = 'anulado', sunat_error = p_motivo where id = p_document_id;
  return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'ya', false);
end $$;

grant execute on function anular_documento(uuid, uuid, text) to authenticated, service_role;

-- >>>>>>>>>>>>>>>>>>>> migrations/0014_integridad.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Konversa · Integridad operativa
--   • Una sola caja abierta por usuario (índice único parcial).
--   • Stock 100% atómico (RPC ajustar_stock) — reemplaza el read-modify-write.
--   • Compra transaccional que ingresa a inventario y arma CxP (registrar_compra).
--   • Abonos de cuentas por cobrar / pagar (registrar_abono).
--   • Gestión real de miembros (policies UPDATE/DELETE + alta por email).
--   • Auditoría automática (audit_events por trigger).
-- Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- ==================== 1) Caja: una abierta por usuario ====================
create unique index if not exists ux_caja_abierta_por_usuario
  on cash_sessions (company_id, user_id)
  where estado = 'abierta';

-- ==================== 2) Stock atómico ====================
create or replace function ajustar_stock(
  p_company_id   uuid,
  p_product_id   uuid,
  p_warehouse_id uuid,
  p_delta        numeric,
  p_tipo         text default 'ajuste',   -- ingreso | salida | ajuste
  p_motivo       text default null
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare v_wh uuid := p_warehouse_id; v_cant numeric;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if not exists (select 1 from products where id = p_product_id and company_id = p_company_id) then
    raise exception 'Producto no pertenece a la empresa';
  end if;
  if v_wh is null then
    select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
    if v_wh is null then
      insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh;
    end if;
  end if;
  insert into stock (product_id, warehouse_id, cantidad) values (p_product_id, v_wh, 0)
    on conflict (product_id, warehouse_id) do nothing;
  update stock set cantidad = cantidad + p_delta
    where product_id = p_product_id and warehouse_id = v_wh
    returning cantidad into v_cant;
  insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
    values (p_company_id, p_product_id, v_wh, p_tipo, abs(p_delta), coalesce(p_motivo, p_tipo));
  return v_cant;
end $$;
grant execute on function ajustar_stock(uuid, uuid, uuid, numeric, text, text) to authenticated, service_role;

-- Fija el stock a un valor absoluto (ajuste por conteo físico), atómico.
create or replace function fijar_stock(
  p_company_id uuid, p_product_id uuid, p_warehouse_id uuid, p_cantidad numeric, p_motivo text default 'Ajuste'
)
returns numeric
language plpgsql security definer set search_path = public as $$
declare v_wh uuid := p_warehouse_id;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if not exists (select 1 from products where id = p_product_id and company_id = p_company_id) then
    raise exception 'Producto no pertenece a la empresa';
  end if;
  if v_wh is null then
    select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
    if v_wh is null then
      insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh;
    end if;
  end if;
  insert into stock (product_id, warehouse_id, cantidad) values (p_product_id, v_wh, p_cantidad)
    on conflict (product_id, warehouse_id) do update set cantidad = excluded.cantidad;
  insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
    values (p_company_id, p_product_id, v_wh, 'ajuste', p_cantidad, coalesce(p_motivo,'Ajuste'));
  return p_cantidad;
end $$;
grant execute on function fijar_stock(uuid, uuid, uuid, numeric, text) to authenticated, service_role;

-- ==================== 3) Compra transaccional (→ inventario + CxP) ====================
create or replace function registrar_compra(
  p_company_id       uuid,
  p_supplier_id      uuid,
  p_tipo_doc         text,
  p_serie_numero     text,
  p_fecha            date,
  p_items            jsonb,           -- [ { product_id?, descripcion, cantidad, costo } ] (costo incluye IGV)
  p_moneda           text    default 'PEN',
  p_condicion_pago   text    default 'contado',
  p_fecha_vencimiento date   default null,
  p_afecta_inventario boolean default true,
  p_warehouse_id     uuid    default null,
  p_igv_rate         numeric default 0.18
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id       uuid;
  v_item     jsonb;
  v_total    numeric(12,2) := 0;
  v_gravado  numeric(12,2) := 0;
  v_igv      numeric(12,2) := 0;
  v_line     numeric(12,2);
  v_pid      uuid;
  v_qty      numeric;
  v_costo    numeric;
  v_saldo    numeric(12,2);
  v_estado   text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra no tiene ítems';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'cantidad')::numeric; v_costo := (v_item->>'costo')::numeric;
    v_line := round(v_qty * v_costo, 2);
    v_total := v_total + v_line;
  end loop;
  v_gravado := round(v_total / (1 + p_igv_rate), 2);
  v_igv := v_total - v_gravado;

  if p_condicion_pago = 'credito' then v_estado := 'pendiente'; v_saldo := v_total;
  else v_estado := 'pagado'; v_saldo := 0; end if;

  insert into purchases (company_id, supplier_id, tipo_doc, serie_numero, fecha, total,
    moneda, total_gravado, total_igv, condicion_pago, estado_pago, saldo, fecha_vencimiento,
    afecta_inventario, warehouse_id)
  values (p_company_id, p_supplier_id, p_tipo_doc, p_serie_numero, coalesce(p_fecha, current_date), v_total,
    p_moneda, v_gravado, v_igv, p_condicion_pago, v_estado, v_saldo, p_fecha_vencimiento,
    p_afecta_inventario, p_warehouse_id)
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty := (v_item->>'cantidad')::numeric; v_costo := (v_item->>'costo')::numeric;
    insert into purchase_items (purchase_id, product_id, descripcion, cantidad, costo, total)
      values (v_id, v_pid, v_item->>'descripcion', v_qty, v_costo, round(v_qty * v_costo, 2));

    if p_afecta_inventario and v_pid is not null
       and exists (select 1 from products where id = v_pid and controla_stock) then
      perform ajustar_stock(p_company_id, v_pid, p_warehouse_id, v_qty, 'ingreso',
        'Compra ' || coalesce(p_serie_numero, ''));
      -- actualiza costo del producto (simplificado; costo promedio móvil es Fase 2)
      update products set costo = round(v_costo / (1 + p_igv_rate), 2) where id = v_pid;
    end if;
  end loop;

  return jsonb_build_object('id', v_id, 'total', v_total, 'total_gravado', v_gravado,
    'total_igv', v_igv, 'saldo', v_saldo, 'estado_pago', v_estado);
end $$;
grant execute on function registrar_compra(uuid, uuid, text, text, date, jsonb, text, text, date, boolean, uuid, numeric)
  to authenticated, service_role;

-- ==================== 4) Abonos (CxC / CxP) ====================
create or replace function registrar_abono(
  p_company_id      uuid,
  p_monto           numeric,
  p_document_id     uuid    default null,   -- cobro (CxC)
  p_purchase_id     uuid    default null,   -- pago (CxP)
  p_medio           text    default 'efectivo',
  p_referencia      text    default null,
  p_cash_session_id uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saldo numeric(12,2);
  v_tipo  text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_monto is null or p_monto <= 0 then raise exception 'Monto inválido'; end if;

  if p_document_id is not null then
    v_tipo := 'cobro';
    update documents set saldo = greatest(saldo - p_monto, 0)
      where id = p_document_id and company_id = p_company_id
      returning saldo into v_saldo;
    if not found then raise exception 'Comprobante no encontrado'; end if;
    update documents set estado_pago = case when saldo <= 0 then 'pagado' else 'parcial' end
      where id = p_document_id;
    insert into payments (company_id, tipo, document_id, cash_session_id, medio, monto, referencia)
      values (p_company_id, 'cobro', p_document_id, p_cash_session_id, p_medio, p_monto, p_referencia);
    if p_cash_session_id is not null and p_medio = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'ingreso', p_monto, 'Abono CxC', p_document_id);
    end if;
  elsif p_purchase_id is not null then
    v_tipo := 'pago';
    update purchases set saldo = greatest(saldo - p_monto, 0)
      where id = p_purchase_id and company_id = p_company_id
      returning saldo into v_saldo;
    if not found then raise exception 'Compra no encontrada'; end if;
    update purchases set estado_pago = case when saldo <= 0 then 'pagado' else 'parcial' end
      where id = p_purchase_id;
    insert into payments (company_id, tipo, purchase_id, cash_session_id, medio, monto, referencia)
      values (p_company_id, 'pago', p_purchase_id, p_cash_session_id, p_medio, p_monto, p_referencia);
    if p_cash_session_id is not null and p_medio = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'retiro', p_monto, 'Pago CxP', null);
    end if;
  else
    raise exception 'Indica un comprobante (CxC) o una compra (CxP)';
  end if;

  return jsonb_build_object('tipo', v_tipo, 'saldo', v_saldo);
end $$;
grant execute on function registrar_abono(uuid, numeric, uuid, uuid, text, text, uuid) to authenticated, service_role;

-- ==================== 5) Gestión de miembros ====================
drop policy if exists memberships_update on memberships;
create policy memberships_update on memberships for update
  using (is_company_admin(company_id)) with check (is_company_admin(company_id));
drop policy if exists memberships_delete on memberships;
create policy memberships_delete on memberships for delete
  using (is_company_admin(company_id));
-- ver a los demás miembros de mis empresas (no solo a mí mismo)
drop policy if exists memberships_select_company on memberships;
create policy memberships_select_company on memberships for select
  using (company_id in (select auth_company_ids()));

-- Alta de miembro por email (el usuario debe existir en Auth). Solo admin de la empresa.
create or replace function agregar_miembro_por_email(
  p_company_id uuid, p_email text, p_role text default 'vendedor'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid;
begin
  if not is_company_admin(p_company_id) then
    raise exception 'Solo un admin puede agregar miembros';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email) limit 1;
  if v_uid is null then
    raise exception 'No existe un usuario con ese email. Pídele que se registre primero.';
  end if;
  insert into memberships (user_id, company_id, role) values (v_uid, p_company_id, p_role)
    on conflict (user_id, company_id) do update set role = excluded.role;
  return jsonb_build_object('user_id', v_uid, 'role', p_role);
end $$;
grant execute on function agregar_miembro_por_email(uuid, text, text) to authenticated, service_role;

-- ==================== 6) Auditoría automática ====================
create or replace function audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_cid uuid; v_eid uuid; v_payload jsonb;
begin
  if TG_OP = 'DELETE' then
    v_cid := (to_jsonb(OLD)->>'company_id')::uuid; v_eid := (to_jsonb(OLD)->>'id')::uuid;
    v_payload := to_jsonb(OLD);
  else
    v_cid := (to_jsonb(NEW)->>'company_id')::uuid; v_eid := (to_jsonb(NEW)->>'id')::uuid;
    v_payload := to_jsonb(NEW);
  end if;
  insert into audit_events (company_id, user_id, accion, entidad, entidad_id, payload)
    values (v_cid, auth.uid(), lower(TG_OP), TG_TABLE_NAME, v_eid, v_payload);
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end $$;

drop trigger if exists trg_audit_documents on documents;
create trigger trg_audit_documents after insert or update or delete on documents
  for each row execute function audit_row();
drop trigger if exists trg_audit_products on products;
create trigger trg_audit_products after insert or update or delete on products
  for each row execute function audit_row();
drop trigger if exists trg_audit_purchases on purchases;
create trigger trg_audit_purchases after insert or update or delete on purchases
  for each row execute function audit_row();

-- ==================== GRANTS ====================
grant all privileges on all tables    in schema public to anon, authenticated, service_role;
grant execute        on all functions in schema public to anon, authenticated, service_role;

-- >>>>>>>>>>>>>>>>>>>> migrations/0015_reportes.sql <<<<<<<<<<<<<<<<<<<<
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

-- >>>>>>>>>>>>>>>>>>>> migrations/0016_hardening.sql <<<<<<<<<<<<<<<<<<<<
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

-- >>>>>>>>>>>>>>>>>>>> migrations/0017_tributos.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Konversa · 0017 Correctitud tributaria (emitir_venta v3 + anular v2)
--   • Clasificación correcta de afectación (cat. 07): gravado 10, gravadas
--     gratuitas 11-17, exonerado 20/21, inafecto 30-36, EXPORTACIÓN 40 (0%).
--   • ICBPER (bolsas plásticas) e ISC (pass-through por ítem).
--   • Descuentos por ítem y global.
--   • anular_documento v2: revierte stock + caja + cuenta por cobrar (y NO
--     reingresa stock de notas).
-- Aplicar DESPUÉS de 0016. Supabase → SQL Editor → Run
-- ============================================================

-- Columnas nuevas
alter table documents add column if not exists total_exportacion numeric(12,2) not null default 0;
alter table products  add column if not exists icbper boolean not null default false;

-- ==================== Helper: clasificar una línea por afectación ====================
create or replace function _clasificar_afectacion(p_code text, p_line_total numeric, p_igv_rate numeric)
returns table(base numeric, igv numeric, bucket text)
language plpgsql immutable as $$
begin
  if p_code = '10' then                                   -- gravado onerosa
    base := round(p_line_total / (1 + p_igv_rate), 2); igv := p_line_total - base; bucket := 'gravado';
  elsif p_code in ('11','12','13','14','15','16','17') then   -- gravadas gratuitas (bonificación, retiro…)
    base := round(p_line_total / (1 + p_igv_rate), 2); igv := p_line_total - base; bucket := 'gratuito';
  elsif p_code = '20' then base := p_line_total; igv := 0; bucket := 'exonerado';
  elsif p_code = '21' then base := p_line_total; igv := 0; bucket := 'gratuito';   -- exonerado gratuito
  elsif p_code = '30' then base := p_line_total; igv := 0; bucket := 'inafecto';
  elsif p_code in ('31','32','33','34','35','36') then base := p_line_total; igv := 0; bucket := 'gratuito'; -- inafecto gratuito
  elsif p_code = '40' then base := p_line_total; igv := 0; bucket := 'exportacion';  -- exportación 0%
  else base := round(p_line_total / (1 + p_igv_rate), 2); igv := p_line_total - base; bucket := 'gravado';
  end if;
  return next;
end $$;
grant execute on function _clasificar_afectacion(text, numeric, numeric) to authenticated, service_role;

-- ==================== emitir_venta v3 ====================
drop function if exists emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric, text, numeric, text, date, uuid);

create or replace function emitir_venta(
  p_company_id       uuid,
  p_tipo_doc         text,
  p_serie            text,
  p_cliente          jsonb,
  p_items            jsonb,          -- [ { product_id?, descripcion, cantidad, precio_unitario, tipo_afectacion?, unidad_medida?, descuento?, icbper?, isc? } ]
  p_forma_pago       text    default 'efectivo',
  p_monto_recibido   numeric default null,
  p_vuelto           numeric default null,
  p_cash_session_id  uuid    default null,
  p_idempotency_key  text    default null,
  p_igv_rate         numeric default 0.18,
  p_moneda           text    default 'PEN',
  p_tipo_cambio      numeric default 1,
  p_condicion_pago   text    default 'contado',
  p_fecha_vencimiento date   default null,
  p_establishment_id uuid    default null,
  p_icbper_rate      numeric default 0.50,
  p_descuento_global numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_correlativo  int;
  v_doc_id       uuid;
  v_customer_id  uuid;
  v_existing     documents%rowtype;
  v_item         jsonb;
  v_pid          uuid;
  v_qty          numeric;
  v_price        numeric;
  v_desc         numeric;
  v_code         text;
  v_line_total   numeric(12,2);
  v_base         numeric(12,2);
  v_ligv         numeric(12,2);
  v_bucket       text;
  v_icb          numeric(12,2);
  v_isc          numeric(12,2);
  v_total        numeric(12,2) := 0;
  v_gravado      numeric(12,2) := 0;
  v_igv          numeric(12,2) := 0;
  v_exonerado    numeric(12,2) := 0;
  v_inafecto     numeric(12,2) := 0;
  v_gratuito     numeric(12,2) := 0;
  v_exportacion  numeric(12,2) := 0;
  v_icbper       numeric(12,2) := 0;
  v_isctot       numeric(12,2) := 0;
  v_wh           uuid;
  v_numero       text;
  v_attempts     int := 0;
  v_estado_pago  text;
  v_saldo        numeric(12,2);
  v_r_tipo       text := coalesce(nullif(p_cliente->>'tipo_doc',''), '0');
  v_r_num        text := nullif(p_cliente->>'num_doc','');
  v_r_den        text := coalesce(nullif(p_cliente->>'denominacion',''), 'Cliente varios');
  v_r_dir        text := nullif(p_cliente->>'direccion','');
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene ítems';
  end if;
  if p_tipo_doc = '01' then
    if v_r_tipo <> '6' or v_r_num is null or v_r_num !~ '^\d{11}$' then
      raise exception 'Una factura (01) requiere un cliente con RUC válido de 11 dígitos';
    end if;
  end if;

  -- Idempotencia (lock advisory por llave → sin salto de correlativo)
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;

  if p_cash_session_id is not null then
    perform 1 from cash_sessions where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then raise exception 'No hay una caja abierta para registrar la venta'; end if;
  end if;

  -- Totales por afectación (con descuento por ítem, ICBPER e ISC)
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid   := nullif(v_item->>'product_id','')::uuid;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_desc  := coalesce((v_item->>'descuento')::numeric, 0);
    v_code  := coalesce(nullif(v_item->>'tipo_afectacion',''),
                        (select tipo_afectacion from products where id = v_pid and company_id = p_company_id), '10');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select base, igv, bucket into v_base, v_ligv, v_bucket from _clasificar_afectacion(v_code, v_line_total, p_igv_rate);

    if v_bucket = 'gravado' then
      v_gravado := v_gravado + v_base; v_igv := v_igv + v_ligv; v_total := v_total + v_line_total;
    elsif v_bucket = 'exonerado' then v_exonerado := v_exonerado + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'inafecto'  then v_inafecto  := v_inafecto  + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'exportacion' then v_exportacion := v_exportacion + v_line_total; v_total := v_total + v_line_total;
    else v_gratuito := v_gratuito + v_line_total;  -- gratuito: no suma a pagar
    end if;

    -- ICBPER (bolsa plástica) e ISC (monto por ítem) suman al total a pagar
    v_icb := case when coalesce((v_item->>'icbper')::boolean, (select icbper from products where id = v_pid), false)
                  then round(v_qty * p_icbper_rate, 2) else 0 end;
    v_isc := coalesce((v_item->>'isc')::numeric, 0);
    v_icbper := v_icbper + v_icb;
    v_isctot := v_isctot + v_isc;
    v_total  := v_total + v_icb + v_isc;
  end loop;

  v_total := round(v_total - coalesce(p_descuento_global, 0), 2);

  v_customer_id := nullif(p_cliente->>'customer_id', '')::uuid;
  if v_customer_id is not null
     and not exists (select 1 from customers where id = v_customer_id and company_id = p_company_id) then
    v_customer_id := null;
  end if;

  if p_condicion_pago = 'credito' then v_estado_pago := 'pendiente'; v_saldo := v_total;
  else v_estado_pago := 'pagado'; v_saldo := 0; end if;

  -- Reserva de correlativo + insert atómico
  loop
    v_attempts := v_attempts + 1;
    insert into series (company_id, tipo_doc, serie, correlativo, establishment_id)
      values (p_company_id, p_tipo_doc, p_serie, 0, p_establishment_id)
      on conflict (company_id, tipo_doc, serie) do nothing;
    update series set correlativo = correlativo + 1
      where company_id = p_company_id and tipo_doc = p_tipo_doc and serie = p_serie
      returning correlativo into v_correlativo;
    v_numero := p_serie || '-' || lpad(v_correlativo::text, 8, '0');

    begin
      insert into documents (
        company_id, establishment_id, customer_id, tipo_doc, serie, correlativo,
        moneda, tipo_cambio, total_gravado, total_igv, total_exonerado, total_inafecto,
        total_gratuito, total_exportacion, total_icbper, total_isc, descuento_global, total,
        estado_sunat, user_id, cash_session_id, forma_pago, monto_recibido, vuelto,
        condicion_pago, estado_pago, saldo, fecha_vencimiento,
        receptor_tipo_doc, receptor_num_doc, receptor_denominacion, receptor_direccion, idempotency_key
      ) values (
        p_company_id, p_establishment_id, v_customer_id, p_tipo_doc, p_serie, v_correlativo,
        p_moneda, p_tipo_cambio, v_gravado, v_igv, v_exonerado, v_inafecto,
        v_gratuito, v_exportacion, v_icbper, v_isctot, coalesce(p_descuento_global,0), v_total,
        'pendiente', v_user_id, p_cash_session_id, p_forma_pago, p_monto_recibido, p_vuelto,
        p_condicion_pago, v_estado_pago, v_saldo, p_fecha_vencimiento,
        v_r_tipo, v_r_num, v_r_den, v_r_dir, coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;
    exception when unique_violation then
      if p_idempotency_key is not null then
        select * into v_existing from documents
          where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
            'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;
    end;
  end loop;

  -- Ítems + kardex
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_desc  := coalesce((v_item->>'descuento')::numeric, 0);
    v_code  := coalesce(nullif(v_item->>'tipo_afectacion',''),
                        (select tipo_afectacion from products where id = v_pid), '10');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select base, igv, bucket into v_base, v_ligv, v_bucket from _clasificar_afectacion(v_code, v_line_total, p_igv_rate);

    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion, unidad_medida, descuento
    ) values (
      v_doc_id, v_pid, v_item->>'descripcion', v_qty,
      case when v_qty <> 0 then round(v_base / v_qty, 2) else 0 end,
      v_price, v_ligv, v_line_total, v_code,
      coalesce(nullif(v_item->>'unidad_medida',''), 'NIU'), v_desc
    );

    if v_pid is not null and exists (select 1 from products where id = v_pid and controla_stock) then
      select warehouse_id into v_wh from stock where product_id = v_pid order by cantidad desc limit 1 for update;
      if v_wh is null then select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1; end if;
      if v_wh is null then insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh; end if;
      insert into stock (product_id, warehouse_id, cantidad) values (v_pid, v_wh, 0) on conflict (product_id, warehouse_id) do nothing;
      update stock set cantidad = cantidad - v_qty where product_id = v_pid and warehouse_id = v_wh;
      insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
        values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
    end if;
  end loop;

  -- Pago: ledger + efectivo a caja (solo contado con monto > 0; una venta 100% gratuita no cobra)
  if p_condicion_pago = 'contado' and v_total > 0 then
    insert into payments (company_id, tipo, document_id, cash_session_id, medio, monto, fecha)
      values (p_company_id, 'cobro', v_doc_id, p_cash_session_id, p_forma_pago, v_total, current_date);
    if p_cash_session_id is not null and p_forma_pago = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'ingreso', v_total, 'Venta ' || v_numero, v_doc_id);
    end if;
  end if;

  return jsonb_build_object('id', v_doc_id, 'serie', p_serie, 'correlativo', v_correlativo, 'numero', v_numero,
    'tipo_doc', p_tipo_doc, 'total_gravado', v_gravado, 'total_igv', v_igv, 'total_exonerado', v_exonerado,
    'total_inafecto', v_inafecto, 'total_exportacion', v_exportacion, 'total_gratuito', v_gratuito,
    'total_icbper', v_icbper, 'total_isc', v_isctot, 'total', v_total, 'estado_sunat', 'pendiente', 'reused', false);
end $$;
grant execute on function emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric, text, numeric, text, date, uuid, numeric, numeric)
  to authenticated, service_role;

-- ==================== anular_documento v2 (revierte stock + caja + CxC) ====================
create or replace function anular_documento(
  p_company_id uuid, p_document_id uuid, p_motivo text default 'Anulación'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_doc      documents%rowtype;
  v_it       record;
  v_wh       uuid;
  v_efectivo numeric(12,2);
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat = 'anulado' then
    return jsonb_build_object('id', v_doc.id, 'estado_sunat', 'anulado', 'ya', true);
  end if;

  -- 1) Stock: solo se revierte para VENTAS (01/03); las notas no descontaron stock.
  if v_doc.tipo_doc in ('01','03') then
    for v_it in select * from document_items where document_id = p_document_id and product_id is not null loop
      if exists (select 1 from products where id = v_it.product_id and controla_stock) then
        select warehouse_id into v_wh from stock where product_id = v_it.product_id order by cantidad desc limit 1;
        if v_wh is null then select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1; end if;
        if v_wh is not null then
          insert into stock (product_id, warehouse_id, cantidad) values (v_it.product_id, v_wh, 0)
            on conflict (product_id, warehouse_id) do nothing;
          update stock set cantidad = cantidad + v_it.cantidad where product_id = v_it.product_id and warehouse_id = v_wh;
          insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
            values (p_company_id, v_it.product_id, v_wh, 'ingreso', v_it.cantidad,
                    'Anulación ' || v_doc.serie || '-' || lpad(v_doc.correlativo::text,8,'0'));
        end if;
      end if;
    end loop;
  end if;

  -- 2) Caja: si hubo efectivo ingresado por este doc, se registra el retiro compensatorio.
  select coalesce(sum(monto),0) into v_efectivo from cash_movements
    where document_id = p_document_id and tipo = 'ingreso';
  if v_efectivo > 0 and v_doc.cash_session_id is not null then
    insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
      values (v_doc.cash_session_id, 'retiro', v_efectivo, 'Anulación ' || v_doc.serie, p_document_id);
  end if;

  -- 3) Cuentas por cobrar: se elimina el saldo y los cobros de este doc.
  delete from payments where document_id = p_document_id;
  update documents set estado_sunat = 'anulado', sunat_error = p_motivo, estado_pago = 'pagado', saldo = 0
    where id = p_document_id;

  return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'ya', false);
end $$;
grant execute on function anular_documento(uuid, uuid, text) to authenticated, service_role;
