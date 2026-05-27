import { useCallback } from 'react';
import { useQuotaGuarded, type QuotaGuardedOptions } from '@labring/sealos-shared-sdk';
import { useClientAppConfig } from './useClientAppConfig';

type QuotaGuardedCallback = () => void | Promise<void>;

export function useObjectStorageQuotaGuarded(
  options: QuotaGuardedOptions,
  callback: QuotaGuardedCallback
) {
  const appConfig = useClientAppConfig();
  const guardedCallback = useQuotaGuarded(options, callback);
  const quotaGuardEnabled = appConfig.objectStorage.quotaGuard.enabled;

  return useCallback(async () => {
    if (quotaGuardEnabled) {
      await guardedCallback();
      return;
    }

    await Promise.resolve().then(() => callback());
  }, [callback, guardedCallback, quotaGuardEnabled]);
}
