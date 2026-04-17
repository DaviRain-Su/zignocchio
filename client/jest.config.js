module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testTimeout: 120000,
  roots: ['<rootDir>/tests'],
  testMatch: ['**/*.test.ts'],
  transform: {
    '^.+\\.tsx?$': [
      'ts-jest',
      {
        tsconfig: '<rootDir>/tsconfig.json',
      },
    ],
  },
};
