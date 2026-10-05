import { expect, type Locator } from "@playwright/test";

/**
 * Clicks a control that syncs waiting captures, such as Retry now, unless an
 * automatic retry already settled them and removed it. Pending captures are
 * retried on their own while the browser is online, so the control can
 * disappear between the moment MemoTrail becomes reachable and the click.
 */
export async function clickUnlessSynced(control: Locator) {
  await expect(async () => {
    if ((await control.count()) > 0) await control.click({ timeout: 1_000 });
  }).toPass({ timeout: 30_000 });
}
