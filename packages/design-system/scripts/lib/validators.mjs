import { aliasPath, hexString, isObject, isUnit } from "./util.mjs";

// Validators return normalized values: colors as 8-bit channels and alpha, lengths in px,
// durations in ms. `nested(value, type)` resolves a property that may itself be an alias, and
// `platform` names the output being resolved, because SwiftUI cannot draw every Web value.

const textCases = new Set(["none", "uppercase", "lowercase", "capitalize"]);
export { textCases };

const typographyProperties = {
  fontFamily: "fontFamily",
  fontSize: "dimension",
  fontWeight: "fontWeight",
  letterSpacing: "dimension",
  lineHeight: "number",
};

export const validators = {
  color(value, path) {
    if (!isObject(value) || value.colorSpace !== "srgb") {
      throw new Error(`{${path}} must be an sRGB color object.`);
    }
    for (const key of Object.keys(value)) {
      if (!["colorSpace", "components", "alpha", "hex"].includes(key)) {
        throw new Error(`{${path}} color has an unknown property ${key}.`);
      }
    }

    const { components, alpha = 1, hex } = value;
    if (
      !Array.isArray(components) ||
      components.length !== 3 ||
      !components.every((component) => isUnit(component))
    ) {
      throw new Error(`{${path}} needs three sRGB components from 0 to 1.`);
    }
    if (!isUnit(alpha)) throw new Error(`{${path}} alpha must be 0 to 1.`);

    const channels = components.map((component) => Math.round(component * 255));
    if (hex !== undefined && hex.toUpperCase() !== hexString(channels)) {
      throw new Error(
        `{${path}} hex ${hex} does not match its components (${hexString(channels)}).`,
      );
    }

    return { channels, alpha };
  },

  dimension(value, path) {
    if (!isObject(value) || !Number.isFinite(value.value)) {
      throw new Error(`{${path}} must be a dimension object.`);
    }
    if (value.unit !== "px") {
      throw new Error(
        `{${path}} uses ${value.unit}; Web and Swift outputs support px dimensions only.`,
      );
    }
    return value.value;
  },

  duration(value, path) {
    if (!isObject(value) || !Number.isFinite(value.value)) {
      throw new Error(`{${path}} must be a duration object.`);
    }
    if (value.unit === "ms") return value.value;
    if (value.unit === "s") return value.value * 1_000;
    throw new Error(`{${path}} duration unit must be ms or s.`);
  },

  number(value, path) {
    if (!Number.isFinite(value)) throw new Error(`{${path}} must be a number.`);
    return value;
  },

  fontWeight(value, path) {
    if (!Number.isInteger(value) || value < 1 || value > 1_000) {
      throw new Error(
        `{${path}} must be a numeric font weight from 1 to 1000.`,
      );
    }
    return value;
  },

  fontFamily(value, path) {
    const families = Array.isArray(value) ? value : [value];
    if (
      families.length === 0 ||
      !families.every((family) => typeof family === "string" && family)
    ) {
      throw new Error(`{${path}} must name one or more font families.`);
    }
    return families;
  },

  cubicBezier(value, path) {
    if (
      !Array.isArray(value) ||
      value.length !== 4 ||
      !value.every((number) => Number.isFinite(number))
    ) {
      throw new Error(`{${path}} must be four cubic Bézier control numbers.`);
    }
    if (!isUnit(value[0]) || !isUnit(value[2])) {
      throw new Error(
        `{${path}} control point x values must be from 0 to 1, got ${value[0]} and ${value[2]}.`,
      );
    }
    return value;
  },

  shadow(value, path, nested, { platform }) {
    const layers = (Array.isArray(value) ? value : [value]).flatMap((layer) =>
      aliasPath(layer) ? nested(layer, "shadow") : [layer],
    );
    if (layers.length === 0) throw new Error(`{${path}} has no shadow layers.`);

    return layers.map((layer) => {
      if ("channels" in layer) return layer;
      if (!isObject(layer)) {
        throw new Error(`{${path}} shadow layers must be objects.`);
      }
      for (const key of Object.keys(layer)) {
        if (
          !["color", "offsetX", "offsetY", "blur", "spread", "inset"].includes(
            key,
          )
        ) {
          throw new Error(
            `{${path}} shadow layer has an unknown property ${key}.`,
          );
        }
      }
      if (layer.inset !== undefined && typeof layer.inset !== "boolean") {
        throw new Error(`{${path}} shadow inset must be true or false.`);
      }

      const inset = layer.inset === true;
      const spread = nested(layer.spread, "dimension");
      if (platform === "ios" && inset) {
        throw new Error(
          `{${path}} inset shadows have no SwiftUI equivalent; mark the token Web-only.`,
        );
      }
      if (platform === "ios" && spread !== 0) {
        throw new Error(
          `{${path}} shadow spread has no SwiftUI equivalent; mark the token Web-only.`,
        );
      }

      const blur = nested(layer.blur, "dimension");
      if (blur < 0)
        throw new Error(`{${path}} shadow blur cannot be negative.`);

      return {
        ...nested(layer.color, "color"),
        x: nested(layer.offsetX, "dimension"),
        y: nested(layer.offsetY, "dimension"),
        blur,
        spread,
        inset,
      };
    });
  },

  typography(value, path, nested) {
    if (!isObject(value)) {
      throw new Error(`{${path}} must be a typography object.`);
    }
    const keys = Object.keys(value).sort();
    const expected = Object.keys(typographyProperties).sort();
    if (keys.join(",") !== expected.join(",")) {
      throw new Error(
        `{${path}} typography needs exactly ${expected.join(", ")}; got ${keys.join(", ")}.`,
      );
    }

    const resolved = { aliases: {} };
    for (const [property, type] of Object.entries(typographyProperties)) {
      resolved[property] = nested(value[property], type);
      const target = aliasPath(value[property]);
      if (target) resolved.aliases[property] = target;
    }
    if (resolved.fontSize <= 0) {
      throw new Error(`{${path}} font size must be positive.`);
    }
    if (resolved.lineHeight <= 0) {
      throw new Error(`{${path}} line height must be a positive multiplier.`);
    }
    return resolved;
  },
};
