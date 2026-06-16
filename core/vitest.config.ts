import { defineConfig } from 'vitest/config'

// Keep the package's tests self-contained: don't inherit the repo-root
// vite.config.ts (that's the React lab's). The core ships no runtime deps.
export default defineConfig({
  root: __dirname,
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
  },
})
