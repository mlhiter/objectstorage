import { afterEach, describe, expect, it, vi } from 'vitest';

const appConfig = {
  cloud: {
    domain: 'cloud.example.com',
    port: 443
  },
  objectStorage: {
    resources: {
      hostingPodCpuMilliCores: 200,
      hostingPodMemoryMiB: 128
    },
    components: {
      monitoring: {
        url: 'http://monitor.example.com'
      },
      billing: {
        url: '',
        secret: ''
      },
      appLaunchpad: {
        url: 'http://applaunchpad.example.com'
      },
      objectStorage: {
        internalEndpoint: 'object-storage.example.svc:80',
        externalEndpoint: 'objectstorageapi.example.com'
      }
    },
    realName: {
      appTokenJwtKey: ''
    },
    hosting: {
      appNamePrefix: 'static-host',
      networkProtocol: 'HTTP',
      networkPort: 80
    }
  }
};

vi.mock('@/config', () => ({
  Config: () => appConfig
}));

describe('getClientAppConfigServer', () => {
  const envName = 'OBJECT_STORAGE_QUOTA_CHECK_ENABLED';
  const originalValue = process.env[envName];

  afterEach(() => {
    if (originalValue === undefined) {
      delete process.env[envName];
    } else {
      process.env[envName] = originalValue;
    }
  });

  it('disables quota guard by default', async () => {
    delete process.env[envName];
    const { getClientAppConfigServer } = await import('@/server/getClientAppConfig');

    expect(getClientAppConfigServer().objectStorage.quotaGuard.enabled).toBe(false);
  });

  it('enables quota guard when the runtime environment variable is true', async () => {
    process.env[envName] = 'true';
    const { getClientAppConfigServer } = await import('@/server/getClientAppConfig');

    expect(getClientAppConfigServer().objectStorage.quotaGuard.enabled).toBe(true);
  });
});
