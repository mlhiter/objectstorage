import { useCallback } from 'react';
import { useQuotaGuarded, type QuotaGuardedOptions } from '@labring/sealos-shared-sdk';
import { isWorkspaceQuotaUnsupportedError } from '@/utils/quotaGuard';

type QuotaGuardedCallback = () => void | Promise<void>;
type WorkspaceQuotaSupport = 'unknown' | 'supported' | 'unsupported';

let workspaceQuotaSupport: WorkspaceQuotaSupport = 'unknown';

export function useObjectStorageQuotaGuarded(
  options: QuotaGuardedOptions,
  callback: QuotaGuardedCallback
) {
  const guardedCallback = useQuotaGuarded(options, callback);

  return useCallback(async () => {
    if (workspaceQuotaSupport === 'unsupported') {
      await Promise.resolve().then(() => callback());
      return;
    }

    try {
      await guardedCallback();
      workspaceQuotaSupport = 'supported';
      return;
    } catch (error) {
      if (isWorkspaceQuotaUnsupportedError(error)) {
        workspaceQuotaSupport = 'unsupported';
        await Promise.resolve().then(() => callback());
        return;
      }

      throw error;
    }
  }, [callback, guardedCallback]);
}
