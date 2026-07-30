// ============================================================
// Procesamiento CENTRALIZADO de imágenes antes de subirlas.
// Todo upload de imagen del sistema (productos, logo de empresa, categorías,
// marcas, servicios) pasa por aquí. Hace tres cosas:
//   1) Valida tipo (allowlist) y tamaño de entrada.
//   2) DECODIFICA la imagen (createImageBitmap): si el archivo NO es una imagen
//      real (corrupto, HTML/SVG/ejecutable renombrado, "polyglot"…) la decodificación
//      falla → se rechaza. Es la validación de contenido, no solo del MIME reportado.
//   3) Redimensiona (lado mayor ≤ maxDim) y re-codifica a WebP en un <canvas>. El
//      canvas descarta EXIF y cualquier payload embebido → el archivo resultante es
//      una imagen LIMPIA y liviana (formato web).
//
// OJO (honesto): esto corre en el CLIENTE. Mejora y sanea el flujo normal, pero NO
// es una garantía de seguridad: quien controla el navegador puede saltárselo y subir
// directo al Storage. La autorización real la dan las políticas RLS del bucket
// (solo authenticated, ruta de su propia empresa). Aquí NO se aceptan SVG (vector de
// XSS) y el contentType se fija a image/webp, así que el navegador lo trata como
// imagen (no lo ejecuta). GIF animado → se guarda su primer frame (imagen estática).
// ============================================================

const ALLOWED = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif'])
/** Tamaño MÁXIMO de entrada (antes de comprimir). */
const MAX_BYTES = 8 * 1024 * 1024
/** Lado mayor máximo (px) tras redimensionar. */
const MAX_DIM = 1280

export interface ProcessedImage {
  blob: Blob
  ext: string
  contentType: string
}

export interface ProcessOptions {
  /** Lado mayor máximo en px (por defecto 1280). */
  maxDim?: number
  /** Calidad WebP 0–1 (por defecto 0.82). */
  quality?: number
}

/**
 * Valida, sanea y comprime una imagen a WebP. Lanza un Error con mensaje claro si
 * el tipo/tamaño no son válidos o si el archivo no es una imagen real.
 */
export async function processImage(file: File, opts: ProcessOptions = {}): Promise<ProcessedImage> {
  const { maxDim = MAX_DIM, quality = 0.82 } = opts

  if (!ALLOWED.has(file.type)) {
    throw new Error('Formato no permitido. Usa PNG, JPG, WEBP o GIF.')
  }
  if (file.size > MAX_BYTES) {
    throw new Error('La imagen supera 8 MB.')
  }

  // Decodifica: si no es una imagen válida, esto lanza → se rechaza el archivo.
  let bitmap: ImageBitmap
  try {
    bitmap = await createImageBitmap(file)
  } catch {
    throw new Error('El archivo no es una imagen válida.')
  }

  try {
    const scale = Math.min(1, maxDim / Math.max(bitmap.width, bitmap.height))
    const w = Math.max(1, Math.round(bitmap.width * scale))
    const h = Math.max(1, Math.round(bitmap.height * scale))

    const canvas = document.createElement('canvas')
    canvas.width = w
    canvas.height = h
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('No se pudo procesar la imagen.')
    ctx.drawImage(bitmap, 0, 0, w, h)

    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, 'image/webp', quality),
    )
    if (!blob) throw new Error('No se pudo comprimir la imagen.')
    return { blob, ext: 'webp', contentType: 'image/webp' }
  } finally {
    bitmap.close()
  }
}
