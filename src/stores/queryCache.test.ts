import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { cachedQuery, invalidateQueryCache } from './queryCache'

describe('queryCache', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('reutiliza una lectura hasta que se invalida', async () => {
    const loader = vi.fn().mockResolvedValue([{ id: 1 }])

    await expect(cachedQuery(['products', 'company-1'], ['products'], loader)).resolves.toEqual([
      { id: 1 },
    ])
    await expect(cachedQuery(['products', 'company-1'], ['products'], loader)).resolves.toEqual([
      { id: 1 },
    ])
    expect(loader).toHaveBeenCalledTimes(1)

    invalidateQueryCache('products')
    await cachedQuery(['products', 'company-1'], ['products'], loader)
    expect(loader).toHaveBeenCalledTimes(2)
  })

  it('deduplica solicitudes simultáneas', async () => {
    let resolve!: (value: string[]) => void
    const loader = vi.fn(
      () =>
        new Promise<string[]>((done) => {
          resolve = done
        }),
    )

    const first = cachedQuery(['customers', 'company-1'], ['customers'], loader)
    const second = cachedQuery(['customers', 'company-1'], ['customers'], loader)
    resolve(['ok'])

    await expect(Promise.all([first, second])).resolves.toEqual([['ok'], ['ok']])
    expect(loader).toHaveBeenCalledTimes(1)
  })

  it('separa empresas y permite forzar una actualización', async () => {
    const loader = vi
      .fn()
      .mockResolvedValueOnce(['a'])
      .mockResolvedValueOnce(['b'])
      .mockResolvedValueOnce(['fresh'])

    await cachedQuery(['products', 'company-a'], ['products'], loader)
    await cachedQuery(['products', 'company-b'], ['products'], loader)
    await expect(
      cachedQuery(['products', 'company-a'], ['products'], loader, { force: true }),
    ).resolves.toEqual(['fresh'])

    expect(loader).toHaveBeenCalledTimes(3)
  })

  it('no vuelve a guardar una respuesta invalidada mientras estaba en vuelo', async () => {
    let resolveFirst!: (value: string[]) => void
    const firstLoader = vi.fn(
      () =>
        new Promise<string[]>((done) => {
          resolveFirst = done
        }),
    )
    const first = cachedQuery(['products'], ['products'], firstLoader)
    invalidateQueryCache('products')
    resolveFirst(['stale'])
    await first

    const freshLoader = vi.fn().mockResolvedValue(['fresh'])
    await expect(cachedQuery(['products'], ['products'], freshLoader)).resolves.toEqual(['fresh'])
    expect(freshLoader).toHaveBeenCalledOnce()
  })
})
