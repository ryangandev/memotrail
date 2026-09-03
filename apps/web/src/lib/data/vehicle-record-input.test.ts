import { describe, expect, it } from "vitest";
import {
  isVehicleEntryIdentity,
  parseVehicleEntryInput,
} from "./vehicle-record-input";

const entryId = "40000000-0000-4000-8000-000000000001";
const validInput = {
  body: " The electric road-trip years. ",
  collectionNames: [" Vehicles ", "vehicles", "Road trips"],
  color: " Midnight Silver ",
  datePrecision: "range",
  id: entryId,
  make: " Tesla ",
  model: " Model Y ",
  modelYear: 2021,
  occurredEnd: "2026-08-31T12:00:00-07:00",
  occurredLabel: " March 2020 to August 2026 ",
  occurredStart: "2020-03-12T08:00:00-04:00",
  occurredTimezone: " America/New_York ",
  revision: 2,
  tagNames: [" Electric ", "electric", "favorite"],
  title: " Bluebird EV ",
};

describe("parseVehicleEntryInput", () => {
  it("normalizes a complete Vehicle edit", () => {
    const parsed = parseVehicleEntryInput(validInput);

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data).toMatchObject({
        body: "The electric road-trip years.",
        collectionNames: ["Vehicles", "Road trips"],
        color: "Midnight Silver",
        make: "Tesla",
        model: "Model Y",
        occurredEnd: "2026-08-31T19:00:00.000Z",
        occurredStart: "2020-03-12T12:00:00.000Z",
        tagNames: ["Electric", "favorite"],
        title: "Bluebird EV",
      });
    }
  });

  it("accepts a current Vehicle with incomplete structured facts", () => {
    expect(
      parseVehicleEntryInput({
        ...validInput,
        color: null,
        id: null,
        make: null,
        model: null,
        modelYear: null,
        occurredEnd: null,
        revision: null,
      }),
    ).toMatchObject({ success: true });
  });

  it("requires a name, start date, and timezone", () => {
    expect(parseVehicleEntryInput({ ...validInput, title: " " })).toMatchObject(
      {
        success: false,
      },
    );
    expect(
      parseVehicleEntryInput({ ...validInput, occurredStart: "" }),
    ).toMatchObject({ success: false });
    expect(
      parseVehicleEntryInput({ ...validInput, occurredTimezone: "" }),
    ).toMatchObject({ success: false });
  });

  it("rejects reversed dates and unsupported precision", () => {
    expect(
      parseVehicleEntryInput({
        ...validInput,
        occurredEnd: "2019-01-01T00:00:00Z",
      }),
    ).toMatchObject({ success: false });
    expect(
      parseVehicleEntryInput({ ...validInput, datePrecision: "unknown" }),
    ).toMatchObject({ success: false });
  });

  it("validates model year, organization, and revision bounds", () => {
    expect(
      parseVehicleEntryInput({ ...validInput, modelYear: 1800 }),
    ).toMatchObject({ success: false });
    expect(
      parseVehicleEntryInput({
        ...validInput,
        tagNames: Array.from({ length: 51 }, (_, index) => `T${index}`),
      }),
    ).toMatchObject({ success: false });
    expect(isVehicleEntryIdentity(entryId, 2)).toBe(true);
    expect(isVehicleEntryIdentity(entryId, null)).toBe(false);
    expect(isVehicleEntryIdentity(null, null)).toBe(true);
  });

  it("rejects oversized structured facts", () => {
    expect(
      parseVehicleEntryInput({ ...validInput, make: "a".repeat(121) }),
    ).toMatchObject({ success: false });
    expect(
      parseVehicleEntryInput({ ...validInput, color: "a".repeat(81) }),
    ).toMatchObject({ success: false });
  });
});
