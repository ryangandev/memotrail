export const e2ePort = Number(process.env.MEMOTRAIL_E2E_PORT || "3100");
if (!Number.isInteger(e2ePort) || e2ePort < 1 || e2ePort > 65535)
  throw new Error("MEMOTRAIL_E2E_PORT must be a port from 1 to 65535.");
export const e2eURL = `http://127.0.0.1:${e2ePort}`;
