import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Search date filters include overlapping periods without inventing date precision", async ({
  page,
  context,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `search-precision-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local search fixture unavailable.");
  const ownerID = created.data.user.id,
    entryID = randomUUID();
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
    const signed = await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties.hashed_token,
    });
    expect(signed.error).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
        httpOnly: false,
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: ownerID,
          title: "Year-only memory",
          body: "",
          item_kind: "entry",
          item_subtype: "entry",
          date_precision: "year",
          occurred_start: "2017-01-01T12:00:00Z",
          occurred_timezone: "UTC",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entries").insert(
          [
            {
              title: "Month-only memory",
              date_precision: "month",
              occurred_start: "2017-07-01T12:00:00Z",
              occurred_end: null,
              item_kind: "entry",
              item_subtype: "entry",
            },
            {
              title: "Long period memory",
              date_precision: "range",
              occurred_start: "2016-01-01T12:00:00Z",
              occurred_end: "2019-02-03T12:00:00Z",
              item_kind: "entry",
              item_subtype: "entry",
            },
            {
              title: "College stage memory",
              date_precision: "year",
              occurred_start: "2015-01-01T12:00:00Z",
              occurred_end: "2020-01-01T12:00:00Z",
              item_kind: "entry",
              item_subtype: "period",
            },
            {
              title: "Unknown memory",
              date_precision: "unknown",
              occurred_start: null,
              occurred_end: null,
              item_kind: "entry",
              item_subtype: "entry",
            },
            {
              title: "Previous calendar day",
              date_precision: "exact",
              occurred_start: "2017-07-10T00:15:00Z",
              occurred_end: null,
              item_kind: "entry",
              item_subtype: "entry",
              occurred_timezone: "America/Los_Angeles",
            },
          ].map((row) => ({
            id: randomUUID(),
            owner_id: ownerID,
            body: "",
            occurred_timezone: "UTC",
            ...row,
          })),
        )
      ).error,
    ).toBeNull();
    await page.goto("/library");
    await page.getByText("Filters", { exact: true }).click();
    await page
      .getByRole("textbox", { name: "From", exact: true })
      .fill("2017-02-31");
    await expect
      .poll(() =>
        page
          .getByRole("textbox", { name: "From", exact: true })
          .evaluate((input: HTMLInputElement) => input.validity.valid),
      )
      .toBe(false);
    await page
      .getByRole("textbox", { name: "From", exact: true })
      .fill("2017-07-10");
    await page
      .getByRole("textbox", { name: "To", exact: true })
      .fill("2017-07-10");
    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(page).toHaveURL(/from=2017-07-10&to=2017-07-10/);
    await expect(
      page.getByRole("heading", { name: "Year-only memory", exact: true }),
    ).toBeVisible({ timeout: 5000 });
    const card = (title: string) =>
      page.locator("article").filter({
        has: page.getByRole("heading", { name: title, exact: true }),
      });
    await expect(card("Year-only memory").locator("time")).toHaveText("2017");
    await expect(card("Month-only memory").locator("time")).toHaveText(
      "Jul 2017",
    );
    await expect(card("Long period memory").locator("time")).toHaveText(
      "Jan 1, 2016 to Feb 3, 2019",
    );
    await expect(card("College stage memory").locator("time")).toHaveText(
      "2015 - 2020",
    );
    await expect(card("Unknown memory")).toHaveCount(0);
    await expect(card("Previous calendar day")).toHaveCount(0);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-search-precision-desktop.png",
      fullPage: true,
    });
    const bearer = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
      global: {
        headers: {
          Authorization: `Bearer ${signed.data.session!.access_token}`,
        },
      },
    });
    const native = await bearer.rpc("search_wiki_items", {
      p_date_from: "2017-07-10",
      p_date_to: "2017-07-10",
    });
    expect(native.error).toBeNull();
    expect(native.data).toHaveLength(4);
    expect(
      native.data.find((row: { entry_id: string }) => row.entry_id === entryID),
    ).toMatchObject({ date_precision: "year" });
    const evidence = await bearer.rpc("archive_wiki_search_evidence", {
      p_queries: [],
      p_date_from: "2017-07-10",
      p_date_to: "2017-07-10",
    });
    expect(evidence.error).toBeNull();
    expect(evidence.data.entries).toHaveLength(4);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-search-precision-mobile.png",
      fullPage: true,
    });
    await page.goto("/library?q=2017-01-01");
    await expect(card("Year-only memory")).toHaveCount(0);
    await page.goto("/library?q=2017-07-01");
    await expect(card("Month-only memory")).toHaveCount(0);
    await page.goto("/library?q=2019-02-03");
    await expect(card("Long period memory")).toBeVisible();
    await page.goto("/library?q=Unknown%20memory");
    await expect(card("Unknown memory").locator("time")).toHaveText(
      "Date unknown",
    );
  } finally {
    expect((await admin.auth.admin.deleteUser(ownerID)).error).toBeNull();
  }
});
