/**
 * Node module-resolution hook: injects `with { type: 'json' }` import
 * attributes for .json modules so the LIVE engine sources (pricing.js uses
 * Vite-style attribute-less JSON imports) load unmodified under plain Node.
 *
 * Registered by test/golden-master.test.js via node:module register().
 */
export async function resolve(specifier, context, nextResolve) {
  const result = await nextResolve(specifier, context);
  if (result.url && result.url.endsWith('.json')) {
    return { ...result, importAttributes: { type: 'json' } };
  }
  return result;
}
