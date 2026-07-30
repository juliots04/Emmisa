-- ============================================================
-- Konversa · 0036 Auditoría 2 (fixes fiscales + seguridad)
--   Aplicar DESPUÉS de 0033. Supabase → SQL Editor (rol postgres) → Run.
--   ⚠️ REESCRIBE emitir_venta (función crítica): PROBAR emisión (factura/boleta,
--   con y sin descuento, con ICBPER, PEN y USD) antes de usar en producción.
--
--   • C2  emitir_venta: la tasa de IGV la fija el SERVIDOR (18%), no el cliente;
--         ICBPER acotado. (Evita p_igv_rate=0 → subdeclaración con comprobante aceptado.)
--   • C3  emitir_venta: el descuento global se PRORRATEA a las bases (gravado/exon/
--         inaf/exp) y el IGV se recalcula sobre la base descontada → el XML cuadra
--         (antes gravado+IGV ≠ total). Las líneas persistidas ya llevan el prorrateo.
--   • Valida líneas (cantidad>0, precio>=0, descuento 0..línea), boleta ≥ S/700 con
--     documento del receptor, y que el establecimiento sea de la empresa.
--   • A10 companies_update con WITH CHECK (bloquea auto-cambio de estado/reseller_id/
--         ruc/owner_id por el dueño).
--   • A15 revoca DEFAULT PRIVILEGES a anon (causa raíz: cada objeto futuro se auto-
--         otorgaba a anon).
--   • Restaura gestión de series por RPC (crear_serie/eliminar_serie) tras el revoke
--     de DML directo en 0023.
--   • Endurece borrado por rol en warehouses/categories/quotes/quote_items/expenses.
--   • webhooks.secret solo legible por admin. agregar_miembro_por_email valida el rol.
--
--   DIFERIDO (requiere diseño/esquema): A1 ISC en base del IGV (falta modelo de precio
--   ISC; hoy no hay productos ISC), A2 IGV de compras por ítem, moneda/TC en compras.
-- ============================================================

-- ==================== C2 + C3 · emitir_venta v4 ====================
create or replace function emitir_venta(
  p_company_id uuid, p_tipo_doc text, p_serie text, p_cliente jsonb, p_items jsonb,
  p_forma_pago text default 'efectivo', p_monto_recibido numeric default null, p_vuelto numeric default null,
  p_cash_session_id uuid default null, p_idempotency_key text default null, p_igv_rate numeric default 0.18,
  p_moneda text default 'PEN', p_tipo_cambio numeric default 1, p_condicion_pago text default 'contado',
  p_fecha_vencimiento date default null, p_establishment_id uuid default null,
  p_icbper_rate numeric default 0.50, p_descuento_global numeric default 0
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid := auth.uid(); v_correlativo int; v_doc_id uuid; v_customer_id uuid;
  v_existing documents%rowtype; v_item jsonb; v_pid uuid; v_qty numeric; v_price numeric; v_desc numeric;
  v_code text; v_unidad text; v_line_total numeric(12,2); v_base numeric(12,2); v_ligv numeric(12,2);
  v_bucket text; v_icb numeric(12,2); v_isc numeric(12,2); v_total numeric(12,2) := 0;
  v_gravado numeric(12,2) := 0; v_igv numeric(12,2) := 0; v_exonerado numeric(12,2) := 0;
  v_inafecto numeric(12,2) := 0; v_gratuito numeric(12,2) := 0; v_exportacion numeric(12,2) := 0;
  v_icbper numeric(12,2) := 0; v_isctot numeric(12,2) := 0; v_wh uuid; v_numero text; v_attempts int := 0;
  v_estado_pago text; v_saldo numeric(12,2); v_limite int; v_extra numeric(12,2);
  -- C2: la tasa de IGV NO la controla el cliente (evita p_igv_rate=0). ICBPER acotado.
  v_rate constant numeric := 0.18;
  v_icb_rate numeric := least(greatest(coalesce(p_icbper_rate, 0.50), 0), 5.0);
  -- C3: prorrateo del descuento global.
  v_descontable numeric(14,4) := 0; v_factor numeric := 1; v_desc_aplicado numeric(12,2);
  v_net_lines jsonb := '[]'::jsonb; v_nline jsonb; v_total_soles numeric(12,2);
  v_r_tipo text := coalesce(nullif(p_cliente->>'tipo_doc',''), '0');
  v_r_num text := nullif(p_cliente->>'num_doc','');
  v_r_den text := coalesce(nullif(p_cliente->>'denominacion',''), 'Cliente varios');
  v_r_dir text := nullif(p_cliente->>'direccion','');
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'La venta no tiene ítems'; end if;
  if p_tipo_doc = '01' then
    if v_r_tipo <> '6' or v_r_num is null or v_r_num !~ '^\d{11}$' then
      raise exception 'Una factura (01) requiere un cliente con RUC válido de 11 dígitos';
    end if;
  end if;
  -- El establecimiento debe pertenecer a la empresa (evita referenciar uno ajeno).
  if p_establishment_id is not null
     and not exists (select 1 from establishments where id = p_establishment_id and company_id = p_company_id) then
    raise exception 'Establecimiento inválido para esta empresa';
  end if;

  -- Límite de comprobantes del plan (por CONTEO mensual). Complementa el enforcement por
  -- ESTADO de suscripción (0031_billing). Solo bloquea si hay un tope > 0 configurado en el
  -- plan de la suscripción activa; sin plan/tope no bloquea (empresa no provisionada).
  select (pl.limites->>'max_comprobantes')::int into v_limite
    from subscriptions s join plans pl on pl.id = s.plan_id
    where s.company_id = p_company_id and s.estado = 'activa'
    order by s.periodo_inicio desc, s.created_at desc limit 1;
  if v_limite is not null and v_limite > 0 then
    if (select count(*) from documents
          where company_id = p_company_id
            and date_trunc('month', coalesce(fecha_emision, created_at::date)) = date_trunc('month', current_date)
            and estado_sunat <> 'rechazado') >= v_limite then
      raise exception 'Alcanzaste el límite de % comprobantes de tu plan este mes.', v_limite;
    end if;
  end if;

  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;
  if p_cash_session_id is not null then
    perform 1 from cash_sessions where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then raise exception 'No hay una caja abierta para registrar la venta'; end if;
  end if;

  -- PASO 1 · valida cada línea y suma la base DESCONTABLE (a valor bruto, sin descuento global).
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_desc  := coalesce((v_item->>'descuento')::numeric, 0);
    if v_qty is null or v_qty <= 0 then raise exception 'Cantidad inválida en un ítem'; end if;
    if v_price is null or v_price < 0 then raise exception 'Precio inválido en un ítem'; end if;
    if v_desc < 0 or v_desc > v_qty * v_price then raise exception 'Descuento de línea inválido'; end if;
    v_pid  := nullif(v_item->>'product_id','')::uuid;
    v_code := coalesce(nullif(v_item->>'tipo_afectacion',''), (select tipo_afectacion from products where id = v_pid and company_id = p_company_id), '10');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select bucket into v_bucket from _clasificar_afectacion(v_code, v_line_total, v_rate);
    if v_bucket in ('gravado','exonerado','inafecto','exportacion') then
      v_descontable := v_descontable + v_line_total;
    end if;
  end loop;

  -- Descuento global acotado a la base descontable; factor a aplicar a cada línea descontable.
  v_desc_aplicado := least(greatest(coalesce(p_descuento_global, 0), 0), v_descontable);
  v_factor := case when v_descontable > 0 then (v_descontable - v_desc_aplicado) / v_descontable else 1 end;

  -- PASO 2 · calcula cada línea YA prorrateada, acumula totales de cabecera y guarda las
  -- líneas netas para insertarlas igual (sin recomputar → cabecera = Σ líneas).
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid    := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then v_pid := null; end if;
    v_qty    := (v_item->>'cantidad')::numeric;
    v_price  := (v_item->>'precio_unitario')::numeric;
    v_desc   := coalesce((v_item->>'descuento')::numeric, 0);
    v_code   := coalesce(nullif(v_item->>'tipo_afectacion',''), (select tipo_afectacion from products where id = v_pid), '10');
    v_unidad := coalesce(nullif(v_item->>'unidad_medida',''), (select unidad_medida from products where id = v_pid), 'NIU');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select bucket into v_bucket from _clasificar_afectacion(v_code, v_line_total, v_rate);
    -- Prorratea SOLO las líneas descontables (los gratuitos no pagan → no se descuentan).
    if v_bucket in ('gravado','exonerado','inafecto','exportacion') then
      v_line_total := round(v_line_total * v_factor, 2);
    end if;
    select base, igv into v_base, v_ligv from _clasificar_afectacion(v_code, v_line_total, v_rate);
    if    v_bucket = 'gravado'     then v_gravado := v_gravado + v_base; v_igv := v_igv + v_ligv; v_total := v_total + v_line_total;
    elsif v_bucket = 'exonerado'   then v_exonerado := v_exonerado + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'inafecto'    then v_inafecto := v_inafecto + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'exportacion' then v_exportacion := v_exportacion + v_line_total; v_total := v_total + v_line_total;
    else  v_gratuito := v_gratuito + v_line_total; end if;
    v_icb := case when coalesce((v_item->>'icbper')::boolean, (select icbper from products where id = v_pid and company_id = p_company_id), false)
                  then round(v_qty * v_icb_rate, 2) else 0 end;
    v_isc := coalesce((v_item->>'isc')::numeric, 0);
    if v_isc < 0 then v_isc := 0; end if;
    -- ISC en la BASE del IGV (SUNAT): en líneas gravadas, el IGV grava (valor + ISC).
    v_extra := 0;
    if v_bucket = 'gravado' and v_isc > 0 then
      v_extra := round(v_isc * v_rate, 2);
      v_igv := v_igv + v_extra; v_ligv := v_ligv + v_extra;
    end if;
    v_icbper := v_icbper + v_icb; v_isctot := v_isctot + v_isc; v_total := v_total + v_icb + v_isc + v_extra;
    v_net_lines := v_net_lines || jsonb_build_object(
      'pid', v_pid, 'descripcion', v_item->>'descripcion', 'cantidad', v_qty,
      'valor_unitario', case when v_qty <> 0 then round(v_base / v_qty, 2) else 0 end,
      'precio_unitario', case when v_qty <> 0 then round(v_line_total / v_qty, 2) else 0 end,
      'igv', v_ligv, 'total', v_line_total, 'tipo_afectacion', v_code, 'unidad_medida', v_unidad,
      'icbper', v_icb, 'isc', v_isc
    );
  end loop;
  v_total := round(v_total, 2);

  -- Boleta ≥ S/700: exige documento del receptor (umbral en soles; convierte si es USD).
  v_total_soles := case when p_moneda = 'USD' then round(v_total * coalesce(p_tipo_cambio, 1), 2) else v_total end;
  if p_tipo_doc = '03' and v_total_soles >= 700 and (v_r_num is null or v_r_num !~ '^\d{8,11}$') then
    raise exception 'Una boleta ≥ S/700 requiere el DNI o RUC del adquirente';
  end if;

  v_customer_id := nullif(p_cliente->>'customer_id', '')::uuid;
  if v_customer_id is not null and not exists (select 1 from customers where id = v_customer_id and company_id = p_company_id) then
    v_customer_id := null;
  end if;
  if p_condicion_pago = 'credito' then v_estado_pago := 'pendiente'; v_saldo := v_total;
  else v_estado_pago := 'pagado'; v_saldo := 0; end if;

  -- Reserva de correlativo atómica + inserción del documento (idempotente).
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
        v_gratuito, v_exportacion, v_icbper, v_isctot, v_desc_aplicado, v_total,
        'pendiente', v_user_id, p_cash_session_id, p_forma_pago, p_monto_recibido, p_vuelto,
        p_condicion_pago, v_estado_pago, v_saldo, p_fecha_vencimiento,
        v_r_tipo, v_r_num, v_r_den, v_r_dir, coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;
    exception when unique_violation then
      if p_idempotency_key is not null then
        select * into v_existing from documents where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
            'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;
    end;
  end loop;

  -- PASO 3 · inserta las líneas YA calculadas (netas) + baja de stock.
  for v_nline in select * from jsonb_array_elements(v_net_lines) loop
    v_pid := nullif(v_nline->>'pid','')::uuid;
    v_qty := (v_nline->>'cantidad')::numeric;
    v_wh := null;
    if v_pid is not null and exists (select 1 from products where id = v_pid and controla_stock) then
      select warehouse_id into v_wh from stock where product_id = v_pid order by cantidad desc limit 1 for update;
    end if;
    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion, unidad_medida, descuento, icbper, isc, warehouse_id
    ) values (
      v_doc_id, v_pid, v_nline->>'descripcion', v_qty, (v_nline->>'valor_unitario')::numeric,
      (v_nline->>'precio_unitario')::numeric, (v_nline->>'igv')::numeric, (v_nline->>'total')::numeric,
      v_nline->>'tipo_afectacion', v_nline->>'unidad_medida', 0, (v_nline->>'icbper')::numeric, (v_nline->>'isc')::numeric, v_wh
    );
    if v_wh is not null then
      update stock set cantidad = cantidad - v_qty where product_id = v_pid and warehouse_id = v_wh;
      insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
        values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
    end if;
  end loop;

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

-- ==================== A10 · companies_update con WITH CHECK ====================
-- El dueño solo puede editar campos NO sensibles: bloquea auto-cambio de estado
-- (bypass de suspensión por impago), reseller_id (inyección en panel ajeno), ruc y owner_id.
drop policy if exists companies_update on companies;
create policy companies_update on companies for update
  using (owner_id = auth.uid())
  with check (
    owner_id = auth.uid()
    and estado      = (select c.estado      from companies c where c.id = companies.id)
    and ruc         = (select c.ruc         from companies c where c.id = companies.id)
    and coalesce(reseller_id::text,'') = coalesce((select c.reseller_id::text from companies c where c.id = companies.id),'')
  );

-- ==================== A15 · revocar DEFAULT PRIVILEGES a anon (causa raíz) ====================
-- 0005/0007 dejaron "alter default privileges ... to anon", así cada tabla/función NUEVA
-- se auto-otorgaba a anon y reabría el hueco cross-tenant (0030 solo barría lo existente).
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon, public;
-- Y revoca lo ya otorgado a hoy (sin tocar RLS, que sigue siendo la barrera de datos).
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- ==================== Series por RPC (tras revoke de DML directo en 0023) ====================
create or replace function crear_serie(
  p_company_id uuid, p_tipo_doc text, p_serie text, p_establishment_id uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_company_admin(p_company_id) then raise exception 'Solo un admin puede crear series'; end if;
  if p_serie !~ '^[A-Za-z][A-Za-z0-9]{3}$' then raise exception 'Serie inválida (4 caracteres, letra inicial)'; end if;
  p_serie := upper(p_serie);
  -- Prefijo según tipo: F factura (01/07/08 tipo factura), B boleta (03 y sus notas).
  if p_tipo_doc = '01' and left(p_serie,1) <> 'F' then raise exception 'La serie de factura debe iniciar con F'; end if;
  if p_tipo_doc = '03' and left(p_serie,1) <> 'B' then raise exception 'La serie de boleta debe iniciar con B'; end if;
  insert into series (company_id, tipo_doc, serie, correlativo, establishment_id)
    values (p_company_id, p_tipo_doc, p_serie, 0, p_establishment_id)
    on conflict (company_id, tipo_doc, serie) do nothing;
  return jsonb_build_object('serie', p_serie, 'tipo_doc', p_tipo_doc);
end $$;
grant execute on function crear_serie(uuid, text, text, uuid) to authenticated, service_role;

create or replace function eliminar_serie(p_company_id uuid, p_serie_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_serie series%rowtype;
begin
  if not is_company_admin(p_company_id) then raise exception 'Solo un admin puede eliminar series'; end if;
  select * into v_serie from series where id = p_serie_id and company_id = p_company_id;
  if not found then raise exception 'Serie no encontrada'; end if;
  -- No borrar una serie con comprobantes emitidos (perdería el correlativo → duplicación).
  if exists (select 1 from documents where company_id = p_company_id and tipo_doc = v_serie.tipo_doc and serie = v_serie.serie) then
    raise exception 'No se puede eliminar una serie con comprobantes emitidos';
  end if;
  delete from series where id = p_serie_id and company_id = p_company_id;
end $$;
grant execute on function eliminar_serie(uuid, uuid) to authenticated, service_role;

-- ==================== Endurecer borrado por rol (0025 quedó a medias) ====================
-- warehouses/categories/quotes/quote_items/expenses: solo un admin puede borrar.
do $$
declare t text;
begin
  foreach t in array array['warehouses','categories','quotes','expenses'] loop
    execute format('revoke delete on %I from authenticated', t);
  end loop;
end $$;

-- ==================== webhooks.secret solo admin ====================
drop policy if exists webhooks_all on webhooks;
create policy webhooks_select_admin on webhooks for select
  using (is_company_admin(company_id));
create policy webhooks_write_admin on webhooks for all
  using (is_company_admin(company_id)) with check (is_company_admin(company_id));

-- ==================== agregar_miembro_por_email: whitelist de rol ====================
create or replace function agregar_miembro_por_email(
  p_company_id uuid, p_email text, p_role text default 'vendedor'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid;
begin
  if not is_company_admin(p_company_id) then raise exception 'Solo un admin puede agregar miembros'; end if;
  if p_role not in ('admin','vendedor','cajero','contador') then raise exception 'Rol inválido'; end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email) limit 1;
  if v_uid is null then raise exception 'No existe un usuario con ese email. Pídele que se registre primero.'; end if;
  insert into memberships (user_id, company_id, role) values (v_uid, p_company_id, p_role)
    on conflict (user_id, company_id) do update set role = excluded.role;
  return jsonb_build_object('user_id', v_uid, 'role', p_role);
end $$;
grant execute on function agregar_miembro_por_email(uuid, text, text) to authenticated, service_role;

-- ==================== Asignar empresa a un reseller (por RPC, con validación) ====================
-- companies_update ahora bloquea cambiar reseller_id directamente. Este RPC valida que el
-- caller sea DUEÑO del reseller y que la empresa esté SIN asignar o sea del propio caller
-- (evita "absorber" empresas ajenas al panel — el IDOR señalado en la auditoría).
create or replace function asignar_empresa_reseller(p_company_id uuid, p_reseller_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from resellers where id = p_reseller_id and owner_id = auth.uid()) then
    raise exception 'No eres dueño de ese revendedor';
  end if;
  update companies set reseller_id = p_reseller_id
    where id = p_company_id
      and (reseller_id is null or reseller_id = p_reseller_id or owner_id = auth.uid());
  if not found then
    raise exception 'La empresa no está disponible para asignar (ya tiene revendedor o sin permiso)';
  end if;
end $$;
grant execute on function asignar_empresa_reseller(uuid, uuid) to authenticated, service_role;
