-- ============================================================
-- Emmisa · SEED de datos de PRUEBA (volumen) — compatible con migraciones 0001..0015
-- Uso: Supabase → SQL Editor → pega TODO → Run  (corre como 'postgres', ignora RLS)
--   • ADITIVO (no borra). Corre 2 veces = duplica. Reset: bloque LIMPIEZA del final.
--   • Marca de prueba: documents.idempotency_key empieza en 'seed:'.
--   • Setea fecha_emision (lo que usan los reportes 0015) y afectacion/IGV correctos.
--   • Respeta ux_caja_abierta_por_usuario (0014): solo crea 1 caja abierta si no hay otra.
--
-- Empresa objetivo: por defecto la PRIMERA (edita el WHERE si tienes varias).
-- Volumen: cambia los `for i in 1..N loop`.
-- ============================================================
do $$
declare
  v_company  uuid;  v_user uuid;  v_wh uuid;  v_wh2 uuid;
  v_prod_id  uuid[] := '{}';  v_prod_px numeric[] := '{}';  v_prod_nm text[] := '{}';
  v_prod_ta  text[] := '{}';  v_prod_um text[] := '{}';
  v_cat_id   uuid[] := '{}';
  v_cust_id  uuid[] := '{}';  v_cust_nm text[] := '{}';  v_cust_doc text[] := '{}';  v_cust_td text[] := '{}';
  v_sup_id   uuid[] := '{}';  v_doc_id uuid[] := '{}';
  i int; j int; i2 int; ci int; nitems int; v_days int;
  v_pid uuid; v_px numeric; v_qty numeric; v_line numeric; v_grav numeric; v_igv numeric;
  v_ta text; v_um text;
  t_grav numeric; t_igv numeric; t_exon numeric; t_inaf numeric; t_tot numeric;
  v_did uuid; v_nc uuid;
  v_corr_b int := 0; v_corr_f int := 0; v_corr_nc int := 0;
  v_tipo text; v_serie text; v_corr int; v_date timestamptz;
  v_cid uuid; v_fp text; v_estado text; v_nm text; v_cs boolean;
  v_cond text; v_epago text; v_saldo numeric;
  v_sid uuid; v_mi numeric; v_ing numeric; v_ret numeric; v_diff numeric; v_has_open boolean;
  v_pid2 uuid; v_ptot numeric; v_qid uuid; v_qtot numeric;
  nombres   text[] := array['Juan','María','Carlos','Rosa','Luis','Ana','Jorge','Carmen','Pedro','Lucía','Miguel','Elena','José','Sofía','Raúl','Gloria','Víctor','Patricia','Diego','Nancy'];
  apellidos text[] := array['García','Rodríguez','Flores','Quispe','Mamani','Torres','Vargas','Rojas','Chávez','Díaz','Ramos','Castro','Sánchez','Huamán','Cruz','Gutiérrez','Vega','Ríos','Paredes','Espinoza'];
  empresas  text[] := array['Inversiones','Corporación','Comercial','Distribuidora','Servicios Generales','Importaciones','Negocios','Grupo','Constructora','Consorcio'];
  empresas2 text[] := array['del Perú','Andina','San Martín','Los Andes','El Sol','Pacífico','Global','Unión','Real','Total'];
  base_prod text[] := array['Arroz','Aceite','Azúcar','Fideos','Leche','Atún','Gaseosa','Agua','Jabón','Detergente','Shampoo','Galletas','Café','Harina','Sal','Yogur','Queso','Papel higiénico','Pilas','Foco LED'];
  marcas    text[] := array['Costeño','Primor','Gloria','Don Vittorio','San Fernando','Inca Kola','Cielo','Bolívar','Ariel','Field','Altomayo','Blanca Flor','Marina','Laive','Bonlé','Elite','Panasonic','Philips','Nicolini','Pura Vida'];
  presenta  text[] := array['500g','1kg','2kg','355ml','1L','620ml','x6','x12','pack','unidad'];
  formas    text[] := array['efectivo','efectivo','efectivo','yape','plin','tarjeta','transferencia'];
begin
  -- >>> elegir empresa (por defecto la primera)
  select c.id, c.owner_id into v_company, v_user
  from companies c
  --  where c.ruc = '20000000001'
  order by c.created_at limit 1;
  if v_company is null then raise exception 'No hay ninguna empresa. Haz el onboarding primero.'; end if;

  -- ===== Categorías, almacenes =====
  insert into categories (company_id, nombre)
  select v_company, x from unnest(array['Abarrotes','Bebidas','Limpieza','Cuidado personal','Snacks','Ferretería']) x;
  select array_agg(id) into v_cat_id from categories where company_id = v_company;

  insert into warehouses (company_id, nombre) values (v_company,'Almacén Principal') returning id into v_wh;
  insert into warehouses (company_id, nombre) values (v_company,'Tienda')            returning id into v_wh2;

  -- ===== Productos (120) + stock =====
  for i in 1..120 loop
    v_px := round((2 + random()*180)::numeric, 2);
    v_nm := base_prod[1+(i%20)] || ' ' || marcas[1+((i*7)%20)] || ' ' || presenta[1+((i*3)%10)];
    v_cs := (i % 12 <> 0);
    v_ta := case when i % 15 = 0 then '20' else '10' end;   -- 1 de 15 exonerado
    v_um := case when v_cs then 'NIU' else 'ZZ' end;
    insert into products (company_id, category_id, sku, nombre, tipo, unidad_medida, tipo_afectacion,
                          precio, costo, controla_stock, activo, barcode, incluye_igv, stock_minimo, moneda)
    values (v_company, v_cat_id[1+(i % array_length(v_cat_id,1))],
            'SKU-'||lpad(i::text,5,'0'), v_nm,
            case when v_cs then 'bien' else 'servicio' end, v_um, v_ta,
            v_px, round((v_px*(0.5+random()*0.3))::numeric,2), v_cs, (i % 40 <> 0),
            '77'||lpad((1000000+i)::text,11,'0'), true, (5+(random()*15)::int), 'PEN')
    returning id into v_pid;
    v_prod_id := array_append(v_prod_id, v_pid);
    v_prod_px := array_append(v_prod_px, v_px);
    v_prod_nm := array_append(v_prod_nm, v_nm);
    v_prod_ta := array_append(v_prod_ta, v_ta);
    v_prod_um := array_append(v_prod_um, v_um);
    if v_cs then
      insert into stock (product_id, warehouse_id, cantidad) values (v_pid, v_wh, (20+(random()*300)::int));
      insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
      values (v_company, v_pid, v_wh, 'ingreso', (20+(random()*300)::int), 'Stock inicial (seed)');
    end if;
  end loop;

  -- ===== Clientes (90) =====
  for i in 1..90 loop
    if i % 3 = 0 then
      v_nm := empresas[1+(i%10)]||' '||empresas2[1+((i*3)%10)]||' S.A.C.';
      insert into customers (company_id, tipo_doc, num_doc, denominacion, direccion, email)
      values (v_company,'6','20'||lpad(((random()*899999999)::bigint+100000000)::text,9,'0'),
              v_nm,'Av. Principal '||(100+i)||', Lima','ventas'||i||'@empresa.pe')
      returning id, tipo_doc, num_doc into v_cid, v_um, v_ta;
    else
      v_nm := nombres[1+(i%20)]||' '||apellidos[1+((i*3)%20)];
      insert into customers (company_id, tipo_doc, num_doc, denominacion, direccion, email)
      values (v_company,'1',lpad(((random()*89999999)::bigint+10000000)::text,8,'0'),
              v_nm,'Jr. Los Olivos '||(100+i),lower(nombres[1+(i%20)])||i||'@gmail.com')
      returning id, tipo_doc, num_doc into v_cid, v_um, v_ta;
    end if;
    v_cust_id  := array_append(v_cust_id, v_cid);
    v_cust_nm  := array_append(v_cust_nm, v_nm);
    v_cust_td  := array_append(v_cust_td, v_um);
    v_cust_doc := array_append(v_cust_doc, v_ta);
  end loop;

  -- ===== Proveedores (15) =====
  for i in 1..15 loop
    insert into suppliers (company_id, ruc, razon_social, contacto)
    values (v_company,'20'||lpad(((random()*899999999)::bigint+100000000)::text,9,'0'),
            'Distribuidora '||empresas2[1+(i%10)]||' S.A.C.',
            nombres[1+(i%20)]||' · 9'||lpad(((random()*89999999)::bigint+10000000)::text,8,'0'))
    returning id into v_cid;
    v_sup_id := array_append(v_sup_id, v_cid);
  end loop;

  -- ===== Comprobantes (500) + ítems (con afectación e IGV correctos) =====
  for i in 1..500 loop
    if random() < 0.25 then
      v_tipo:='01'; v_serie:='F001'; v_corr_f:=v_corr_f+1; v_corr:=v_corr_f;
    else
      v_tipo:='03'; v_serie:='B001'; v_corr_b:=v_corr_b+1; v_corr:=v_corr_b;
    end if;
    ci := 1 + floor(random()*array_length(v_cust_id,1))::int;
    v_days := floor(power(random(), 1.8) * 100)::int;              -- sesgo hacia días recientes
    v_date := now() - make_interval(days => v_days, secs => (random()*86400)::int);
    v_fp := formas[1+floor(random()*array_length(formas,1))::int];
    v_estado := case when random()<0.9 then 'aceptado' when random()<0.5 then 'pendiente' else 'anulado' end;
    v_cond := case when random()<0.2 then 'credito' else 'contado' end;

    insert into documents (company_id, customer_id, tipo_doc, serie, correlativo, moneda,
                           total_gravado, total_igv, total_exonerado, total_inafecto, total,
                           estado_sunat, forma_pago, user_id, idempotency_key, created_at, fecha_emision,
                           receptor_tipo_doc, receptor_num_doc, receptor_denominacion, condicion_pago,
                           estado_pago, saldo)
    values (v_company, v_cust_id[ci], v_tipo, v_serie, v_corr, 'PEN',
            0,0,0,0,0, v_estado, v_fp, v_user, 'seed:'||gen_random_uuid()::text, v_date, v_date::date,
            v_cust_td[ci], v_cust_doc[ci], v_cust_nm[ci], v_cond, 'pagado', 0)
    returning id into v_did;

    nitems := 1 + floor(random()*4)::int;
    t_grav:=0; t_igv:=0; t_exon:=0; t_inaf:=0; t_tot:=0;
    for j in 1..nitems loop
      i2 := 1 + floor(random()*array_length(v_prod_id,1))::int;
      v_qty := 1 + floor(random()*8)::int;
      v_px  := v_prod_px[i2];
      v_ta  := v_prod_ta[i2];
      v_line := round(v_qty*v_px, 2);
      if v_ta = '10' then
        v_grav := round(v_line/1.18, 2); v_igv := v_line - v_grav;
        t_grav := t_grav + v_grav; t_igv := t_igv + v_igv;
        insert into document_items (document_id, product_id, descripcion, cantidad, valor_unitario,
                                    precio_unitario, igv, total, tipo_afectacion, unidad_medida)
        values (v_did, v_prod_id[i2], v_prod_nm[i2], v_qty, round(v_grav/v_qty,2), v_px, v_igv, v_line, '10', v_prod_um[i2]);
      else  -- exonerado (20) / inafecto (30): sin IGV
        if v_ta='20' then t_exon := t_exon + v_line; else t_inaf := t_inaf + v_line; end if;
        insert into document_items (document_id, product_id, descripcion, cantidad, valor_unitario,
                                    precio_unitario, igv, total, tipo_afectacion, unidad_medida)
        values (v_did, v_prod_id[i2], v_prod_nm[i2], v_qty, v_px, v_px, 0, v_line, v_ta, v_prod_um[i2]);
      end if;
      t_tot := t_tot + v_line;
    end loop;

    -- estado de pago (CxC): crédito puede quedar pendiente o parcial
    if v_cond='credito' and v_estado='aceptado' then
      if random()<0.5 then v_epago:='pendiente'; v_saldo:=t_tot;
      else v_epago:='parcial'; v_saldo:=round(t_tot*0.5,2); end if;
    else
      v_epago:='pagado'; v_saldo:=0;
    end if;

    update documents set total_gravado=t_grav, total_igv=t_igv, total_exonerado=t_exon,
      total_inafecto=t_inaf, total=t_tot, estado_pago=v_epago, saldo=v_saldo where id=v_did;

    -- abono parcial (payments) para los que quedaron 'parcial'
    if v_epago='parcial' then
      insert into payments (company_id, tipo, document_id, medio, monto, fecha)
      values (v_company,'cobro', v_did, v_fp, t_tot - v_saldo, v_date::date);
    end if;

    if v_tipo='01' and v_estado='aceptado' then v_doc_id := array_append(v_doc_id, v_did); end if;
  end loop;

  insert into series (company_id, tipo_doc, serie, correlativo)
  values (v_company,'03','B001',v_corr_b), (v_company,'01','F001',v_corr_f)
  on conflict (company_id, tipo_doc, serie) do update set correlativo=greatest(series.correlativo, excluded.correlativo);

  -- ===== Notas de crédito (hasta 15) sobre facturas =====
  if array_length(v_doc_id,1) is not null then
    for i in 1..least(15, array_length(v_doc_id,1)) loop
      v_corr_nc := v_corr_nc + 1;
      v_did := v_doc_id[1+floor(random()*array_length(v_doc_id,1))::int];
      insert into documents (company_id, customer_id, tipo_doc, serie, correlativo, moneda,
                             total_gravado, total_igv, total, estado_sunat, ref_document_id, forma_pago,
                             user_id, idempotency_key, created_at, fecha_emision,
                             receptor_tipo_doc, receptor_num_doc, receptor_denominacion,
                             motivo_codigo, motivo_desc, estado_pago)
      select company_id, customer_id, '07','FC01', v_corr_nc, 'PEN',
             round(total_gravado*0.5,2), round(total_igv*0.5,2), round(total*0.5,2),
             'aceptado', id, forma_pago, v_user, 'seed:'||gen_random_uuid()::text,
             created_at + interval '1 day', (created_at + interval '1 day')::date,
             receptor_tipo_doc, receptor_num_doc, receptor_denominacion,
             '07','Devolución total o parcial de bienes','pagado'
      from documents where id = v_did
      returning id, total_gravado, total_igv, total into v_nc, v_grav, v_igv, v_line;
      insert into document_items (document_id, product_id, descripcion, cantidad, valor_unitario, precio_unitario, igv, total, tipo_afectacion, unidad_medida)
      values (v_nc, null, 'Nota de crédito por devolución / ajuste', 1, v_grav, v_line, v_igv, v_line, '10','NIU');
    end loop;
    insert into series (company_id, tipo_doc, serie, correlativo)
    values (v_company,'07','FC01',v_corr_nc)
    on conflict (company_id, tipo_doc, serie) do update set correlativo=greatest(series.correlativo, excluded.correlativo);
  end if;

  -- ===== Caja: 24 cerradas + 1 abierta (si no hay otra abierta del usuario) =====
  select exists(select 1 from cash_sessions where company_id=v_company and user_id=v_user and estado='abierta') into v_has_open;
  for i in 1..25 loop
    v_mi := (100+(random()*400)::int);
    v_date := now() - make_interval(days => (random()*60)::int);
    if i=1 and not v_has_open then
      insert into cash_sessions (company_id, user_id, monto_inicial, estado, abierto_en)
      values (v_company, v_user, v_mi, 'abierta', now()-interval '3 hours') returning id into v_sid;
    else
      insert into cash_sessions (company_id, user_id, monto_inicial, estado, abierto_en, cerrado_en)
      values (v_company, v_user, v_mi, 'cerrada', v_date, v_date+interval '8 hours') returning id into v_sid;
    end if;
    v_ing:=0; v_ret:=0;
    for j in 1..(3+floor(random()*8)::int) loop
      if random()<0.75 then
        v_line := round((20+random()*400)::numeric,2);
        insert into cash_movements (cash_session_id, tipo, monto, motivo, created_at)
        values (v_sid,'ingreso',v_line,'Venta en efectivo', v_date+(j||' hours')::interval);
        v_ing := v_ing + v_line;
      else
        v_line := round((10+random()*100)::numeric,2);
        insert into cash_movements (cash_session_id, tipo, monto, motivo, created_at)
        values (v_sid,'retiro',v_line,(array['Compra de insumos','Pago delivery','Adelanto','Gasto menor'])[1+floor(random()*4)::int], v_date+(j||' hours')::interval);
        v_ret := v_ret + v_line;
      end if;
    end loop;
    if not (i=1 and not v_has_open) then
      v_diff := round((random()*10-5)::numeric,2);
      update cash_sessions set monto_final=round(v_mi+v_ing-v_ret,2)+v_diff, diferencia=v_diff where id=v_sid;
    end if;
  end loop;

  -- ===== Compras (40) + ítems (con total_gravado/igv) =====
  for i in 1..40 loop
    v_date := now() - make_interval(days => (random()*180)::int);
    insert into purchases (company_id, supplier_id, tipo_doc, serie_numero, fecha, total,
                           total_gravado, total_igv, moneda, condicion_pago, estado_pago, warehouse_id)
    values (v_company, v_sup_id[1+floor(random()*array_length(v_sup_id,1))::int], '01',
            'F'||lpad((1+(random()*3)::int)::text,3,'0')||'-'||lpad((1+(random()*99999)::int)::text,8,'0'),
            v_date::date, 0, 0, 0, 'PEN', 'contado', 'pagado', v_wh)
    returning id into v_pid2;
    v_ptot:=0;
    for j in 1..(1+floor(random()*4)::int) loop
      i2 := 1+floor(random()*array_length(v_prod_id,1))::int;
      v_qty := 5+floor(random()*50)::int;
      v_line := round(v_qty*v_prod_px[i2]*0.6, 2);
      insert into purchase_items (purchase_id, product_id, descripcion, cantidad, costo, total)
      values (v_pid2, v_prod_id[i2], v_prod_nm[i2], v_qty, round(v_prod_px[i2]*0.6,2), v_line);
      v_ptot := v_ptot + v_line;
    end loop;
    update purchases set total=v_ptot, total_gravado=round(v_ptot/1.18,2), total_igv=round(v_ptot-v_ptot/1.18,2) where id=v_pid2;
  end loop;

  -- ===== Gastos (30) =====
  for i in 1..30 loop
    insert into expenses (company_id, concepto, monto, fecha, categoria)
    values (v_company,(array['Alquiler local','Recibo de luz','Recibo de agua','Internet','Sueldos','Movilidad','Publicidad','Mantenimiento','Útiles de oficina','Impuestos'])[1+(i%10)],
            round((50+random()*1500)::numeric,2),(now()-make_interval(days=>(random()*180)::int))::date,
            (array['Servicios','Planilla','Operativo','Marketing','Administrativo'])[1+(i%5)]);
  end loop;

  -- ===== Cotizaciones (30) + ítems =====
  for i in 1..30 loop
    ci := 1+floor(random()*array_length(v_cust_id,1))::int;
    insert into quotes (company_id, customer_id, cliente_nombre, fecha, moneda, total, estado)
    values (v_company, v_cust_id[ci], v_cust_nm[ci], (now()-make_interval(days=>(random()*90)::int))::date, 'PEN', 0,
            (array['vigente','aprobada','rechazada','vencida'])[1+floor(random()*4)::int])
    returning id into v_qid;
    v_qtot:=0;
    for j in 1..(1+floor(random()*5)::int) loop
      i2 := 1+floor(random()*array_length(v_prod_id,1))::int;
      v_qty := 1+floor(random()*10)::int;
      v_line := round(v_qty*v_prod_px[i2],2);
      insert into quote_items (quote_id, descripcion, cantidad, precio_unitario, total)
      values (v_qid, v_prod_nm[i2], v_qty, v_prod_px[i2], v_line);
      v_qtot := v_qtot + v_line;
    end loop;
    update quotes set total=v_qtot where id=v_qid;
  end loop;

  raise notice 'SEED OK · empresa=% · 120 prod, 90 clientes, 15 prov, % comprobantes (% B + % F), % NC, 25 cajas, 40 compras, 30 gastos, 30 cotizaciones',
    v_company, (v_corr_b+v_corr_f), v_corr_b, v_corr_f, v_corr_nc;
end $$;


-- ============================================================
-- LIMPIEZA (opcional) · ⚠️ DESTRUCTIVO: borra TODOS los datos de la empresa.
-- ============================================================
-- do $$
-- declare v_company uuid;
-- begin
--   select id into v_company from companies order by created_at limit 1;
--   delete from payments        where company_id = v_company;
--   delete from document_items  where document_id in (select id from documents where company_id = v_company);
--   delete from documents       where company_id = v_company;
--   delete from quote_items     where quote_id in (select id from quotes where company_id = v_company);
--   delete from quotes          where company_id = v_company;
--   delete from purchase_items  where purchase_id in (select id from purchases where company_id = v_company);
--   delete from purchases       where company_id = v_company;
--   delete from expenses        where company_id = v_company;
--   delete from cash_movements  where cash_session_id in (select id from cash_sessions where company_id = v_company);
--   delete from cash_sessions   where company_id = v_company;
--   delete from inventory_movements where company_id = v_company;
--   delete from stock           where product_id in (select id from products where company_id = v_company);
--   delete from products        where company_id = v_company;
--   delete from customers       where company_id = v_company;
--   delete from suppliers       where company_id = v_company;
--   delete from warehouses      where company_id = v_company;
--   delete from categories      where company_id = v_company;
--   delete from series          where company_id = v_company;
--   delete from audit_events    where company_id = v_company;
-- end $$;
