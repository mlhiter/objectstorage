import { describe, expect, it } from 'vitest';
import { isWorkspaceQuotaUnsupportedError } from '@/utils/quotaGuard';

describe('isWorkspaceQuotaUnsupportedError', () => {
  it('detects the Desktop bridge error for missing quota API support', () => {
    expect(
      isWorkspaceQuotaUnsupportedError({
        masterOrigin: 'https://192.168.13.209.nip.io',
        messageId: 'c51ed119-f75b-4dc3-a517-1c83b9595407',
        success: false,
        message: 'function is not declare',
        data: {}
      })
    ).toBe(true);
  });

  it('ignores ordinary business or quota errors', () => {
    expect(isWorkspaceQuotaUnsupportedError(new Error('function is not declare'))).toBe(false);
    expect(isWorkspaceQuotaUnsupportedError({ success: false, message: 'quota exceeded' })).toBe(false);
    expect(isWorkspaceQuotaUnsupportedError({ success: true, message: 'function is not declare' })).toBe(
      false
    );
  });
});
