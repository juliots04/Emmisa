<template>
  <LegalLayout
    titulo="Términos y Condiciones del Servicio"
    actualizado="julio de 2026"
  >
    <p>
      Estos Términos y Condiciones regulan el uso de la plataforma de facturación electrónica
      Emmisa (en adelante, «el Servicio»). Al registrarte y usar el Servicio, aceptas estos
      términos en su totalidad.
    </p>

    <h2>1. Descripción del Servicio</h2>
    <p>
      El Servicio permite gestionar ventas, productos, inventario, clientes, caja y reportes. La
      emisión fiscal se realiza mediante Emmisa Fiscal API, conectada directamente con SUNAT. El
      alcance productivo de cada tipo de comprobante se informa dentro de la plataforma; una
      operación solo se considera emitida cuando existe una respuesta fiscal de SUNAT.
    </p>

    <h2>2. Cuenta y responsabilidad del usuario</h2>
    <ul>
      <li>Eres responsable de la veracidad de los datos de tu empresa (RUC, razón social) y de tus clientes.</li>
      <li>Eres responsable de custodiar tus credenciales de acceso y tu Clave SOL.</li>
      <li>El correcto cumplimiento tributario (afectaciones, tipos de comprobante, plazos) es tu responsabilidad como contribuyente.</li>
    </ul>

    <h2>3. Suscripción y pagos</h2>
    <p>
      El Servicio se ofrece bajo una suscripción periódica. La falta de pago puede suspender la
      capacidad de emitir nuevos comprobantes hasta regularizar la deuda. Los comprobantes ya
      emitidos y aceptados por SUNAT permanecen disponibles conforme a la ley.
    </p>

    <h2>4. Disponibilidad y límites</h2>
    <p>
      El Servicio depende de la disponibilidad de SUNAT y de la infraestructura contratada. No garantizamos disponibilidad
      ininterrumpida y no somos responsables por interrupciones ajenas a nuestro control.
    </p>

    <h2>5. Conservación de la información</h2>
    <p>
      Los comprobantes y registros se conservan conforme a los plazos exigidos por la normativa
      tributaria peruana (mínimo 5 años). Puedes exportar tu información en cualquier momento.
    </p>

    <h2>6. Limitación de responsabilidad</h2>
    <p>
      El Servicio se brinda «tal cual». En la máxima medida permitida por la ley, no seremos
      responsables por daños indirectos, lucro cesante ni por sanciones derivadas del uso indebido
      o de la información incorrecta ingresada por el usuario.
    </p>

    <h2>7. Terminación</h2>
    <p>
      Puedes cancelar tu suscripción en cualquier momento. Podremos suspender cuentas que incumplan
      estos términos o la normativa aplicable.
    </p>

    <h2>8. Contacto</h2>
    <p>
      Para consultas sobre estos términos, escríbenos al correo de soporte indicado en tu panel.
    </p>
  </LegalLayout>
</template>

<script setup lang="ts">
import LegalLayout from './LegalLayout.vue'
</script>
