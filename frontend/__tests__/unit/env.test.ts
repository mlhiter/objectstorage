import { afterEach, describe, expect, it } from 'vitest';
import { getEnvBoolean } from '@/server/env';

describe('getEnvBoolean', () => {
  const envName = 'OBJECT_STORAGE_QUOTA_CHECK_ENABLED';
  const originalValue = process.env[envName];

  afterEach(() => {
    if (originalValue === undefined) {
      delete process.env[envName];
    } else {
      process.env[envName] = originalValue;
    }
  });

  it('uses the provided default when the variable is not set', () => {
    delete process.env[envName];

    expect(getEnvBoolean(envName)).toBe(false);
    expect(getEnvBoolean(envName, true)).toBe(true);
  });

  it.each(['1', 'true', 'TRUE', 'yes', 'on'])('treats %s as true', (value) => {
    process.env[envName] = value;

    expect(getEnvBoolean(envName)).toBe(true);
  });

  it.each(['0', 'false', 'no', 'off', ''])('treats %s as false', (value) => {
    process.env[envName] = value;

    expect(getEnvBoolean(envName, true)).toBe(false);
  });
});
