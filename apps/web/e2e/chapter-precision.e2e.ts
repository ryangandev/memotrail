import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import {
  expectOccurrencePrecision,
  fillOccurrenceEnd,
  fillOccurrenceStart,
  occurrenceStartField,
  setDateDescription,
  setOccurrencePrecision,
  type DatePrecision,
} from "./helpers/occurrence";

for (const kind of ["home", "vehicle"] as const) {
  test(`${kind} editing preserves uncertain dates and original exact instants`, async ({
    page,
    context,
  }) => {
    const uiErrors: string[] = [];
    page.on("pageerror", (error) => uiErrors.push(error.message));
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
    const email = `chapter-precision-${randomUUID()}@memotrail.local`;
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
    });
    const owner = created.data.user!.id;
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
      await client.auth.verifyOtp({
        type: "magiclink",
        token_hash: link.data.properties!.hashed_token,
      });
      await context.addCookies(
        cookies.map((c) => ({
          ...c,
          domain: "127.0.0.1",
          path: "/",
          sameSite: "Lax",
          httpOnly: false,
        })),
      );

      const common = {
        p_title: "Precision chapter",
        p_body: "Original writing",
        p_tag_names: [],
        p_entry_id: null,
        p_expected_revision: null,
      };
      const dates = {
        p_occurred_start: "2026-11-01T09:30:00.123456Z",
        p_occurred_end: "2026-11-01T10:30:00.654321Z",
        p_date_precision: "exact",
        p_occurred_label: null,
        p_occurred_timezone: "America/Los_Angeles",
      };
      const configs = {
        home: {
          rpc: "save_home_entry_with_occurrence",
          path: "/homes",
          args: {
            ...common,
            ...dates,
            p_move_in_reason: "",
            p_move_out_reason: "A new chapter",
          },
        },
        vehicle: {
          rpc: "save_vehicle_entry_with_occurrence",
          path: "/vehicles",
          args: {
            ...common,
            ...dates,
            p_make: "Test",
            p_model: "Car",
            p_model_year: null,
            p_color: "",
          },
        },
      };
      const config = configs[kind];
      const saved = await client.rpc(config.rpc, config.args);
      expect(saved.error).toBeNull();
      const id = saved.data[0].entry_id;
      await page.goto(config.path + "/" + id);
      const editLabel = kind === "home" ? "Edit Home" : "Edit Vehicle";
      await page.getByRole("button", { name: editLabel }).click();
      let dialog = page.getByRole("main");
      await expectOccurrencePrecision(dialog, "exact");
      await dialog
        .getByRole("button", { name: "Save changes", exact: true })
        .click();
      await expect(page.getByRole("button", { name: editLabel })).toBeVisible();
      const entry = (
        await client
          .from("entries")
          .select("occurred_start,occurred_end,date_precision")
          .eq("id", id)
          .single()
      ).data!;
      expect(entry.occurred_start).toBe("2026-11-01T09:30:00.123456+00:00");
      expect(entry.occurred_end).toBe("2026-11-01T10:30:00.654321+00:00");
      const samples: [DatePrecision, string, string, string][] = [
        ["year", "2017", "2023", ""],
        ["month", "2017-07", "2023-06", ""],
        ["day", "2017-07-08", "2023-06-01", ""],
        ["day", "2017-07-08", "", ""],
        ["approximate", "", "", "During college"],
        ["unknown", "", "", ""],
      ];
      for (const [precision, start, end, label] of samples) {
        await page.getByRole("button", { name: editLabel }).click();
        await setOccurrencePrecision(dialog, precision);
        if (start) await fillOccurrenceStart(dialog, start);
        else await occurrenceStartField(dialog).fill("");
        if (end) await fillOccurrenceEnd(dialog, end);
        else
          await dialog
            .getByRole("checkbox", { name: "Present", exact: true })
            .check();
        await setDateDescription(dialog, label);
        if (kind === "home" && !end) {
          // Removing the end must not silently discard the existing reason.
          if (precision === "day") {
            await expect(dialog.getByLabel("Why you left")).toHaveValue(
              "A new chapter",
            );
            await dialog
              .getByRole("button", { name: "Save changes", exact: true })
              .click();
            await expect(dialog.getByRole("alert")).toContainText("move-out");
          }
          await dialog.getByLabel("Why you left").fill("");
        }
        await dialog
          .getByRole("button", { name: "Save changes", exact: true })
          .click();
        await expect(
          dialog.getByRole("button", { name: "Save changes" }),
          `${kind} editor should close after saving ${precision} precision`,
        ).not.toBeVisible({ timeout: 15_000 });
        // Two samples in a row can share a precision, so wait for the end too.
        await expect
          .poll(async () => {
            const { data } = await client
              .from("entries")
              .select("date_precision,occurred_end")
              .eq("id", id)
              .single();
            return [data?.date_precision, data?.occurred_end === null];
          })
          .toEqual([precision, !end]);
        const persisted = await client
          .from("entries")
          .select(
            "date_precision,occurred_start,occurred_end,occurred_label,body",
          )
          .eq("id", id)
          .single();
        expect(persisted.error).toBeNull();
        expect(persisted.data?.date_precision).toBe(precision);
        expect(persisted.data?.body).toBe("Original writing");
        expect(persisted.data?.occurred_start === null).toBe(!start);
        expect(persisted.data?.occurred_end === null).toBe(!end);
        expect(persisted.data?.occurred_label).toBe(label || null);
      }
      await page.goto(config.path);
      await expect(
        page.getByText("Duration unavailable", { exact: true }),
      ).toBeVisible();
      await page.goto(config.path + "/" + id);
      await page.getByRole("button", { name: editLabel }).click();
      await expectOccurrencePrecision(dialog, "unknown");
      await page.screenshot({
        caret: "initial",
        path: `/private/tmp/memotrail-${kind}-chapter-desktop.png`,
        fullPage: true,
      });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.emulateMedia({ colorScheme: "dark" });
      await page.screenshot({
        caret: "initial",
        path: `/private/tmp/memotrail-${kind}-chapter-mobile.png`,
        fullPage: true,
      });
      await dialog.getByRole("button", { name: "Cancel" }).click();
      await page.goto(config.path);
      await page
        .getByRole("button", {
          name: kind === "home" ? "Add Home" : "Add Vehicle",
          exact: true,
        })
        .click();
      dialog = page.getByRole("dialog");
      await expectOccurrencePrecision(dialog, "unknown");
      await dialog
        .getByRole("textbox", {
          name: kind === "home" ? "Home name" : "Name or nickname",
          exact: true,
        })
        .fill("Undated chapter");
      if (kind === "home")
        await dialog
          .getByRole("textbox", { name: "City", exact: true })
          .fill("San Jose");
      await dialog
        .getByRole("button", {
          name: kind === "home" ? "Add Home" : "Add Vehicle",
          exact: true,
        })
        .click();
      await expect(dialog).not.toBeVisible();
      const createdChapter = await client
        .from("entries")
        .select("date_precision,occurred_start")
        .eq("title", "Undated chapter")
        .single();
      expect(createdChapter.error).toBeNull();
      expect(createdChapter.data).toEqual({
        date_precision: "unknown",
        occurred_start: null,
      });
      await page.getByRole("button", { name: /Precision chapter/ }).click();
      await page.getByRole("button", { name: editLabel }).click();
      dialog = page.getByRole("main");
      const current = await client
        .from("entries")
        .select("revision")
        .eq("id", id)
        .single();
      const remote = await client.rpc(config.rpc, {
        ...config.args,
        p_title: "Other device edit",
        p_entry_id: id,
        p_expected_revision: current.data!.revision,
        p_occurred_start: null,
        p_occurred_end: null,
        p_date_precision: "unknown",
        ...(kind === "home" ? { p_move_out_reason: "" } : {}),
      });
      expect(remote.error).toBeNull();
      await dialog
        .getByRole("button", { name: "Save changes", exact: true })
        .click();
      await expect(dialog.getByRole("alert")).toContainText(
        "changed on another device",
      );
      expect(
        (await client.from("entries").select("title").eq("id", id).single())
          .data?.title,
      ).toBe("Other device edit");
      expect(uiErrors).toEqual([]);
    } finally {
      await admin.auth.admin.deleteUser(owner);
    }
  });
}
