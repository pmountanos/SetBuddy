/**
 * Data and domain code is plain TypeScript, so its tests run in Node against a real SQLite (better-sqlite3).
 * The Babel presets are given here rather than in a babel.config.js so Metro keeps Expo's own default config.
 */
module.exports = {
  testEnvironment: 'node',
  testMatch: ['<rootDir>/src/**/__tests__/**/*.test.ts'],
  moduleNameMapper: { '^@/(.*)$': '<rootDir>/src/$1' },
  transform: {
    '^.+\\.ts$': [
      'babel-jest',
      { configFile: false, presets: [['@babel/preset-env', { targets: { node: 'current' } }], '@babel/preset-typescript'] },
    ],
  },
};
