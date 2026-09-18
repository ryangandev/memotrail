import { describe, expect, it, vi } from "vitest";
import { createPhotoUploadBatch } from "./upload";

const owner = "10000000-0000-4000-8000-000000000001";
const entry = "10000000-0000-4000-8000-000000000002";
describe("photo retry identity", () => {
  it("retains IDs and successful uploads after a lost registration response", async () => {
    const batch = createPhotoUploadBatch();
    const file = new File(["photo"], "a.png", { type: "image/png" });
    const upload = vi.fn().mockResolvedValue(true);
    const register = vi
      .fn()
      .mockRejectedValueOnce(Error("lost response"))
      .mockResolvedValue({ status: "saved" });
    expect(await batch(owner, entry, [file], { upload, register })).toEqual([
      file,
    ]);
    expect(await batch(owner, entry, [file], { upload, register })).toEqual([]);
    expect(upload).toHaveBeenCalledTimes(1);
    expect(register.mock.calls[0][0]).toEqual(register.mock.calls[1][0]);
  });
  it("reconciles a lost upload response or duplicate through registration", async () => {
    const batch = createPhotoUploadBatch();
    const file = new File(["photo"], "a.png", { type: "image/png" });
    const upload = vi
      .fn()
      .mockRejectedValueOnce(Error("lost upload"))
      .mockResolvedValue(false);
    const register = vi
      .fn()
      .mockResolvedValueOnce({ status: "error" })
      .mockResolvedValue({ status: "saved" });
    expect(await batch(owner, entry, [file], { upload, register })).toEqual([
      file,
    ]);
    expect(await batch(owner, entry, [file], { upload, register })).toEqual([]);
    expect(upload.mock.calls[0][0].objectPath).toBe(
      upload.mock.calls[1][0].objectPath,
    );
  });
  it("continues a batch after one failure and separates Entry and owner identities", async () => {
    const batch = createPhotoUploadBatch();
    const first = new File(["one"], "a.png", { type: "image/png" });
    const second = new File(["two"], "b.png", { type: "image/png" });
    const upload = vi.fn().mockResolvedValue(true);
    const register = vi
      .fn()
      .mockRejectedValueOnce(Error())
      .mockResolvedValue({ status: "saved" });
    expect(
      await batch(owner, entry, [first, second], { upload, register }),
    ).toEqual([first]);
    expect(register).toHaveBeenCalledTimes(2);
    await batch(owner, "10000000-0000-4000-8000-000000000003", [first], {
      upload,
      register,
    });
    await batch("10000000-0000-4000-8000-000000000004", entry, [first], {
      upload,
      register,
    });
    expect(
      new Set(register.mock.calls.map(([input]) => input.attachmentId)).size,
    ).toBe(4);
  });

  it("uploads with bounded concurrency and reports completed files", async () => {
    const batch = createPhotoUploadBatch();
    const files = Array.from(
      { length: 5 },
      (_, index) =>
        new File([`${index}`], `${index}.png`, { type: "image/png" }),
    );
    let active = 0;
    let peak = 0;
    const upload = vi.fn(async () => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
      return true;
    });
    const register = vi.fn().mockResolvedValue({ status: "saved" });
    const progress = vi.fn();

    expect(
      await batch(owner, entry, files, { upload, register }, progress),
    ).toEqual([]);
    expect(peak).toBe(3);
    expect(progress).toHaveBeenNthCalledWith(1, { completed: 0, total: 5 });
    expect(progress).toHaveBeenLastCalledWith({ completed: 5, total: 5 });
  });
});
