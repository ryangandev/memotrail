import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Timeline asks for a private birth date and starts the story there", async ({
  context,
  page,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `timeline-birth-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(...values.map(({ name, value }) => ({ name, value })));
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties!.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );

    await page.goto("/timeline");
    const prompt = page.getByRole("dialog", {
      name: "When did your story begin?",
    });
    await expect(prompt).toBeVisible();
    await expect(prompt).toHaveAttribute("data-hydrated", "true");
    await expect(prompt.getByLabel("Birth date", { exact: true })).toHaveValue(
      "",
    );
    await page.screenshot({
      path: "/private/tmp/memotrail-timeline-birth-prompt.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: "/private/tmp/memotrail-timeline-birth-prompt-mobile.png",
    });
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.emulateMedia({ colorScheme: "light" });
    await prompt.getByLabel("Birth date", { exact: true }).fill("1994-04-18");
    await prompt
      .getByRole("button", { name: "Start my Timeline", exact: true })
      .click();
    await expect(prompt).not.toBeVisible();
    await expect(
      page.getByTestId("timeline-axis").locator("span").first(),
    ).toHaveText("1994");
    await page.screenshot({
      path: "/private/tmp/memotrail-timeline-from-birth.png",
    });
    await expect
      .poll(
        async () =>
          (
            await client
              .from("profiles")
              .select("birth_date")
              .eq("user_id", owner)
              .single()
          ).data?.birth_date,
      )
      .toBe("1994-04-18");

    await page.goto("/settings");
    const setting = page.getByRole("textbox", {
      name: "Birth date",
      exact: true,
    });
    await expect(setting).toHaveValue("1994-04-18");
    await setting.fill("1995-05-19");
    await page
      .getByRole("button", { name: "Save birth date", exact: true })
      .click();
    await expect(page.getByRole("status")).toHaveText("Birth date saved.");

    await page.goto("/timeline");
    await expect(prompt).toHaveCount(0);
    await expect(
      page.getByTestId("timeline-axis").locator("span").first(),
    ).toHaveText("1995");
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
