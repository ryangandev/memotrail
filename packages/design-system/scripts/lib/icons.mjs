import { platforms } from "./resolve.mjs";
import { aliasPath, isObject } from "./util.mjs";

// The icon manifest maps each semantic icon name to a Web line icon and an SF Symbol. DTCG has
// no icon type, so this file has its own small schema, validated here. Its cssImages section
// names Web icons drawn as CSS background images, where currentColor cannot reach, with the
// tokens that size and color them.

const elementAttributes = {
  path: new Set(["d", "fill", "stroke"]),
  circle: new Set(["cx", "cy", "r", "fill", "stroke"]),
  rect: new Set(["x", "y", "width", "height", "rx", "fill", "stroke"]),
};
const numericAttributes = new Set([
  "cx",
  "cy",
  "r",
  "x",
  "y",
  "width",
  "height",
  "rx",
]);
const paintValues = new Set(["currentColor", "none"]);
const iconKeys = new Set(["description", "platforms", "sfSymbol", "svg"]);
const imageKeys = ["color", "description", "icon", "size", "strokeWidth"];

export function validateIcons(manifest, webTokens) {
  const label = "icons.json";
  if (!isObject(manifest)) throw new Error(`${label} must be an object.`);
  for (const key of Object.keys(manifest)) {
    if (!["$description", "svg", "icons", "cssImages"].includes(key)) {
      throw new Error(`${label}: unknown property ${key}.`);
    }
  }

  const svg = manifest.svg;
  if (
    !isObject(svg) ||
    Object.keys(svg).sort().join(",") !== "strokeWidth,viewBox" ||
    !/^0 0 \d+ \d+$/.test(svg.viewBox)
  ) {
    throw new Error(
      `${label}: svg must be { viewBox: "0 0 width height", strokeWidth: "{dimension token}" }.`,
    );
  }
  const strokePath = aliasPath(svg.strokeWidth);
  const stroke = strokePath && webTokens.get(strokePath);
  if (!stroke || stroke.type !== "dimension") {
    throw new Error(
      `${label}: svg.strokeWidth must reference a Web dimension token, got ${JSON.stringify(svg.strokeWidth)}.`,
    );
  }

  if (!isObject(manifest.icons) || Object.keys(manifest.icons).length === 0) {
    throw new Error(`${label}: icons must name at least one icon.`);
  }
  const names = Object.keys(manifest.icons);
  const sorted = [...names].sort();
  if (names.join(",") !== sorted.join(",")) {
    const index = names.findIndex(
      (name, position) => name !== sorted[position],
    );
    throw new Error(
      `${label}: icons must be in alphabetical order; ${names[index]} is out of place.`,
    );
  }

  const icons = names.map((name) => {
    const icon = manifest.icons[name];
    const where = `${label}: icon ${name}`;
    if (!/^[a-z][A-Za-z0-9]*$/.test(name)) {
      throw new Error(`${where} must have a camelCase name.`);
    }
    if (!isObject(icon)) throw new Error(`${where} must be an object.`);
    for (const key of Object.keys(icon)) {
      if (!iconKeys.has(key))
        throw new Error(`${where} has unknown property ${key}.`);
    }
    if (typeof icon.description !== "string" || !icon.description.trim()) {
      throw new Error(`${where} needs a description.`);
    }

    const iconPlatforms = icon.platforms ?? platforms;
    if (
      !Array.isArray(iconPlatforms) ||
      iconPlatforms.length === 0 ||
      !iconPlatforms.every((platform) => platforms.includes(platform)) ||
      new Set(iconPlatforms).size !== iconPlatforms.length
    ) {
      throw new Error(
        `${where} platforms must list one or more of ${platforms.join(" and ")}.`,
      );
    }
    if (icon.platforms && iconPlatforms.length === platforms.length) {
      throw new Error(`${where} lists every platform; omit platforms instead.`);
    }

    const onWeb = iconPlatforms.includes("web");
    const onIos = iconPlatforms.includes("ios");
    if (onIos !== (icon.sfSymbol !== undefined)) {
      throw new Error(
        onIos
          ? `${where} is available on iOS but has no sfSymbol.`
          : `${where} has an sfSymbol but is not available on iOS.`,
      );
    }
    if (onWeb !== (icon.svg !== undefined)) {
      throw new Error(
        onWeb
          ? `${where} is available on Web but has no svg.`
          : `${where} has an svg but is not available on Web.`,
      );
    }
    if (onIos && !/^[a-z0-9]+(\.[a-z0-9]+)*$/.test(icon.sfSymbol)) {
      throw new Error(
        `${where} sfSymbol ${icon.sfSymbol} is not an SF Symbol name.`,
      );
    }
    if (onWeb) validateSvg(icon.svg, where);

    return {
      name,
      description: icon.description,
      platforms: platforms.filter((platform) =>
        iconPlatforms.includes(platform),
      ),
      sfSymbol: icon.sfSymbol ?? null,
      svg: icon.svg ?? null,
    };
  });

  return {
    viewBox: svg.viewBox,
    strokeWidth: stroke.value,
    icons,
    cssImages: validateCssImages(manifest.cssImages ?? {}, icons, webTokens),
  };
}

function validateCssImages(images, icons, webTokens) {
  if (!isObject(images))
    throw new Error("icons.json: cssImages must be an object.");
  return Object.entries(images)
    .filter(([name]) => name !== "$description")
    .map(([name, image]) => {
      const where = `icons.json: cssImages.${name}`;
      if (!/^[a-z][A-Za-z0-9]*$/.test(name)) {
        throw new Error(`${where} must have a camelCase name.`);
      }
      if (
        !isObject(image) ||
        Object.keys(image).sort().join(",") !== imageKeys.join(",")
      ) {
        throw new Error(`${where} must have exactly ${imageKeys.join(", ")}.`);
      }
      if (typeof image.description !== "string" || !image.description.trim()) {
        throw new Error(`${where} needs a description.`);
      }
      const icon = icons.find((candidate) => candidate.name === image.icon);
      if (!icon?.svg) {
        throw new Error(
          `${where} icon must name a Web icon, got ${image.icon}.`,
        );
      }
      const reference = (key, type) => {
        const path = aliasPath(image[key]);
        const token = path && webTokens.get(path);
        if (!token || token.type !== type) {
          throw new Error(
            `${where} ${key} must reference a Web ${type} token, got ${JSON.stringify(image[key])}.`,
          );
        }
        return path;
      };
      return {
        name,
        svg: icon.svg,
        color: reference("color", "color"),
        size: reference("size", "dimension"),
        strokeWidth: reference("strokeWidth", "dimension"),
      };
    });
}

function validateSvg(elements, where) {
  if (!Array.isArray(elements) || elements.length === 0) {
    throw new Error(`${where} svg must list one or more elements.`);
  }
  for (const element of elements) {
    if (
      !Array.isArray(element) ||
      element.length !== 2 ||
      !isObject(element[1])
    ) {
      throw new Error(`${where} svg elements must be [tag, attributes] pairs.`);
    }
    const [tag, attributes] = element;
    const allowed = elementAttributes[tag];
    if (!allowed) {
      throw new Error(
        `${where} uses <${tag}>; icons may use ${Object.keys(elementAttributes).join(", ")}.`,
      );
    }
    for (const [name, value] of Object.entries(attributes)) {
      if (!allowed.has(name)) {
        throw new Error(`${where} <${tag}> has unsupported attribute ${name}.`);
      }
      if (typeof value !== "string" || value === "") {
        throw new Error(
          `${where} <${tag}> ${name} must be a non-empty string.`,
        );
      }
      if (numericAttributes.has(name) && !Number.isFinite(Number(value))) {
        throw new Error(
          `${where} <${tag}> ${name} must be a number, got ${value}.`,
        );
      }
      if ((name === "fill" || name === "stroke") && !paintValues.has(value)) {
        throw new Error(
          `${where} <${tag}> ${name} must be currentColor or none, got ${value}.`,
        );
      }
      if (name === "d" && !/^[MmLlHhVvCcSsQqTtAaZz0-9.,\s-]+$/.test(value)) {
        throw new Error(`${where} <path> d has characters outside path data.`);
      }
    }
    const required = {
      path: ["d"],
      circle: ["cx", "cy", "r"],
      rect: ["width", "height"],
    };
    for (const name of required[tag]) {
      if (!(name in attributes)) {
        throw new Error(`${where} <${tag}> needs ${name}.`);
      }
    }
  }
}
