const UNSUPPORTED_FUNCTION_MESSAGE = 'function is not declare';

export function isWorkspaceQuotaUnsupportedError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;

  const payload = error as {
    success?: unknown;
    message?: unknown;
    masterOrigin?: unknown;
    messageId?: unknown;
  };

  return (
    payload.success === false &&
    payload.message === UNSUPPORTED_FUNCTION_MESSAGE &&
    typeof payload.masterOrigin === 'string' &&
    typeof payload.messageId === 'string'
  );
}
