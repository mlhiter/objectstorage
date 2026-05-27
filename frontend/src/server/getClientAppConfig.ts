import { Config } from '@/config';
import { ClientAppConfig, ClientAppConfigSchema } from '@/types/config';
import { validateClientAppConfigOrThrow } from './clientAppConfig';
import { getEnvBoolean } from './env';

export function getClientAppConfigServer(): ClientAppConfig {
  const fullConfig = Config();
  return validateClientAppConfigOrThrow(ClientAppConfigSchema, {
    cloud: fullConfig.cloud,
    objectStorage: {
      resources: fullConfig.objectStorage.resources,
      components: {
        monitoring: fullConfig.objectStorage.components.monitoring,
        appLaunchpad: fullConfig.objectStorage.components.appLaunchpad
      },
      hosting: fullConfig.objectStorage.hosting,
      quotaGuard: {
        enabled: getEnvBoolean('OBJECT_STORAGE_QUOTA_CHECK_ENABLED')
      }
    }
  });
}
