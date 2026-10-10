import type { CSSProperties } from "react";
import type tokenCatalog from "@/generated/design-tokens.json";
import { Icon, iconNames } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { iconSizes, pageFrameVariants } from "@/generated/design-system";
import styles from "./page.module.css";
import controls from "./controls-gallery.module.css";
import { capitalize, kebab, Specimen, SpecimenCase } from "./specimen";

export type TokenSet = typeof tokenCatalog;

type Leaf = string | number;

const themes = ["light", "dark"] as const;

// Materials whose tint is dark in both themes carry inverse ink.
const inverseMaterials = new Set([
  "inverseChip",
  "mediaControl",
  "dialogScrim",
  "sheetScrim",
  "paletteScrim",
]);

/** Flattens nested token groups into dotted names, such as `map.canvas`. */
function leaves(group: object, prefix = ""): [string, Leaf][] {
  return Object.entries(group).flatMap(([key, value]) =>
    value !== null && typeof value === "object"
      ? leaves(value, `${prefix}${key}.`)
      : [[`${prefix}${key}`, value as Leaf] as [string, Leaf]],
  );
}

function cssVar(group: string, name: string) {
  return `var(--mt-${group}-${name.split(".").map(kebab).join("-")})`;
}

/** "ringOffsetInsetDeep" reads as "Inset deep". */
function offsetLabel(name: string) {
  return name
    .slice("ringOffset".length)
    .replace(/(?!^)[A-Z]/g, (letter) => ` ${letter.toLowerCase()}`);
}

function typeStyle(role: string): CSSProperties {
  const variable = (property: string) =>
    `var(--mt-type-${kebab(role)}-${property})`;
  return {
    fontFamily: variable("font-family"),
    fontSize: variable("font-size"),
    fontWeight: variable("font-weight"),
    letterSpacing: variable("letter-spacing"),
    lineHeight: variable("line-height"),
    textTransform: variable("text-transform") as CSSProperties["textTransform"],
  };
}

export function FoundationTokens({ tokens }: { tokens: TokenSet }) {
  const descriptions: Record<string, string | undefined> = tokens.descriptions;
  const colors = {
    light: leaves(tokens.color.light),
    dark: leaves(tokens.color.dark),
  };
  const durations = Object.entries(tokens.motion).filter(
    (entry): entry is [string, number] => typeof entry[1] === "number",
  );
  const stateColors = leaves(tokens.state.light).filter(
    ([, value]) => typeof value === "string",
  );
  const darkState = new Map(leaves(tokens.state.dark));
  const opacities = (["disabled", "muted"] as const).flatMap((kind) =>
    Object.entries(tokens.state.light[kind].opacity).map(([name, value]) => ({
      kind,
      name,
      value,
    })),
  );
  const focusOffsets = Object.entries(tokens.state.light.focus).filter(
    (entry): entry is [string, number] =>
      entry[0].startsWith("ringOffset") && typeof entry[1] === "number",
  );
  const materials = Object.entries(tokens.material.light);

  return (
    <>
      <Specimen
        description={`${colors.light.length} semantic colors with matched light and dark names. Hover a swatch for its purpose.`}
        id="colors"
        title="Colors"
      >
        <div className={styles.themeGrid}>
          {themes.map((theme) => (
            <div className={styles.themePreview} data-theme={theme} key={theme}>
              <h3>{capitalize(theme)}</h3>
              <div className={styles.colorGrid}>
                {colors[theme].map(([name, value]) => (
                  <div
                    className={styles.colorToken}
                    data-color={name}
                    key={name}
                    title={descriptions[`color.${name}`]}
                  >
                    <span
                      aria-hidden="true"
                      style={{ background: cssVar("color", name) }}
                    />
                    <strong>{name}</strong>
                    <code>{value}</code>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </Specimen>

      <Specimen
        api="--mt-type-<role>-*"
        description={`${Object.keys(tokens.type).length} text roles. Each role sets every font property together, so a style never mixes a size with the wrong weight or tracking.`}
        id="typography"
        title="Typography"
      >
        <div className={styles.typeList}>
          {Object.entries(tokens.type).map(([name, role]) => (
            <div className={styles.typeRow} data-type-role={name} key={name}>
              <p style={typeStyle(name)}>A life in progress</p>
              <div>
                <code>
                  {name} ·{" "}
                  {"fluidFontSize" in role
                    ? role.fluidFontSize
                    : `${role.fontSize}px`}{" "}
                  · {role.fontWeight} · {role.lineHeight}
                </code>
                <small>{descriptions[`type.${name}`]}</small>
              </div>
            </div>
          ))}
        </div>
      </Specimen>

      <div className={styles.foundationGrid}>
        <Specimen title="Spacing">
          <div className={styles.scaleList}>
            {Object.entries(tokens.space).map(([name, value]) => (
              <div className={styles.scaleRow} key={name}>
                <code>space.{name}</code>
                <span
                  aria-hidden="true"
                  style={{ width: cssVar("space", name) }}
                />
                <small>{value}px</small>
              </div>
            ))}
          </div>
        </Specimen>

        <Specimen title="Radius">
          <div className={styles.radiusGrid}>
            {Object.entries(tokens.radius).map(([name, value]) => (
              <div key={name}>
                <span
                  aria-hidden="true"
                  style={{ borderRadius: cssVar("radius", name) }}
                />
                <code>{name}</code>
                <small>{value}px</small>
              </div>
            ))}
          </div>
        </Specimen>

        <Specimen title="Shadow">
          <div className={styles.shadowGrid}>
            {Object.entries(tokens.shadow).map(([name, value]) => (
              <div key={name}>
                <span style={{ boxShadow: cssVar("shadow", name) }} />
                <code>{name}</code>
                <small>{value}</small>
              </div>
            ))}
          </div>
        </Specimen>

        <Specimen title="Motion">
          <div className={styles.motionList}>
            {durations.map(([name, value]) => (
              <div key={name}>
                <code>{name}</code>
                <span style={{ animationDuration: `${value}ms` }} />
                <small>{value}ms</small>
              </div>
            ))}
          </div>
          <div className={styles.easingList} id="easing">
            {Object.entries(tokens.motion.easing).map(([name, value]) => (
              <div key={name} title={descriptions[`motion.easing.${name}`]}>
                <code>easing.{name}</code>
                <span
                  aria-hidden="true"
                  style={{
                    animationTimingFunction: cssVar("motion-easing", name),
                  }}
                />
                <small>{value}</small>
              </div>
            ))}
          </div>
        </Specimen>
      </div>

      <Specimen
        description="Web spacing in em, so it follows the size of the text it sits in."
        id="text-space"
        title="Text spacing"
      >
        <div className={styles.layerList}>
          {Object.entries(tokens.textSpace).map(([name, value]) => (
            <div key={name}>
              <code>{name}</code>
              <strong>{value}</strong>
              <small>{descriptions[`textSpace.${name}`]}</small>
            </div>
          ))}
        </div>
      </Specimen>

      <Specimen
        description="Heights of controls and fields, the minimum hit target, icon glyph sizes, and stroke widths."
        id="size"
        title="Size"
      >
        <div className={styles.sizeSpecimen}>
          <div className={styles.sizeBoxes}>
            {(["control", "field"] as const).flatMap((group) =>
              Object.entries(tokens.size[group]).map(([name, value]) => (
                <div key={`${group}.${name}`}>
                  <span
                    aria-hidden="true"
                    data-size-group={group}
                    style={{ height: cssVar("size", `${group}.${name}`) }}
                  />
                  <code>
                    {group}.{name}
                  </code>
                  <small>{value}px</small>
                </div>
              )),
            )}
            <div title={descriptions["size.hitTarget"]}>
              <span
                aria-hidden="true"
                data-size-group="hitTarget"
                style={{
                  height: "var(--mt-size-hit-target)",
                  width: "var(--mt-size-hit-target)",
                }}
              />
              <code>hitTarget</code>
              <small>{tokens.size.hitTarget}px</small>
            </div>
          </div>
          <div className={styles.iconSizes}>
            {Object.entries(iconSizes).map(([name, value]) => (
              <div key={name}>
                <Icon name="star" size={value} />
                <code>icon.{name}</code>
              </div>
            ))}
          </div>
          <div className={styles.strokeList}>
            {Object.entries(tokens.size.stroke).map(([name, value]) => (
              <div key={name} title={descriptions[`size.stroke.${name}`]}>
                <code>stroke.{name}</code>
                <span
                  aria-hidden="true"
                  style={{ height: cssVar("size-stroke", name) }}
                />
                <small>{value}px</small>
              </div>
            ))}
          </div>
        </div>
      </Specimen>

      <Specimen
        description="Focus, hover, selected, disabled, and muted treatments. Swatches follow the gallery theme; values list light then dark."
        id="state"
        title="State"
      >
        <div className={styles.stateSpecimen}>
          <div className={styles.focusSamples}>
            {focusOffsets.map(([name, value]) => (
              <span
                data-focus-sample="ring"
                data-focus-offset={name}
                key={name}
                style={{ outlineOffset: cssVar("state-focus", name) }}
                title={descriptions[`state.focus.${name}`]}
              >
                {name === "ringOffset" ? "Focus ring" : offsetLabel(name)}{" "}
                <small>{value}px</small>
              </span>
            ))}
            <span data-focus-sample="halo">Focus halo</span>
          </div>
          <div className={styles.colorGrid}>
            {stateColors.map(([name, value]) => (
              <div
                className={styles.colorToken}
                data-state={name}
                key={name}
                title={descriptions[`state.${name}`]}
              >
                <span
                  aria-hidden="true"
                  style={{ background: cssVar("state", name) }}
                />
                <strong>{name}</strong>
                <code>
                  {value} / {darkState.get(name)}
                </code>
              </div>
            ))}
          </div>
          <div className={styles.opacityList}>
            {opacities.map(({ kind, name, value }) => (
              <div
                key={`${kind}.${name}`}
                title={descriptions[`state.${kind}.opacity.${name}`]}
              >
                <span
                  aria-hidden="true"
                  data-opacity={`${kind}.${name}`}
                  style={{
                    opacity: cssVar(`state-${kind}-opacity`, name),
                  }}
                >
                  {capitalize(kind)}
                </span>
                <code>{name}</code>
                <small>{value}</small>
              </div>
            ))}
          </div>
        </div>
      </Specimen>

      <div className={styles.foundationGrid}>
        <Specimen
          description="Each level pairs a surface with its shadow. Overlay adds the scrim behind it."
          id="elevation"
          title="Elevation"
        >
          <div className={styles.elevationGrid}>
            {Object.entries(tokens.elevation.light).map(([name, level]) => (
              <div
                data-elevation={name}
                key={name}
                style={
                  "scrim" in level
                    ? { background: cssVar("elevation", `${name}.scrim`) }
                    : undefined
                }
              >
                <span
                  style={{
                    background: cssVar("elevation", `${name}.surface`),
                    boxShadow:
                      "shadow" in level
                        ? cssVar("elevation", `${name}.shadow`)
                        : "none",
                  }}
                >
                  <code>{name}</code>
                </span>
              </div>
            ))}
          </div>
        </Specimen>

        <Specimen
          description="Translucent tints with their backdrop filter, shown over a busy backdrop."
          id="material"
          title="Material"
        >
          <div className={styles.materialBackdrop}>
            {materials.map(([name, material]) => (
              <div
                data-inverse={inverseMaterials.has(name) || undefined}
                data-material={name}
                key={name}
                style={{
                  backdropFilter: cssVar("material", `${name}.backdropFilter`),
                  background: cssVar("material", `${name}.tint`),
                  borderColor:
                    "border" in material
                      ? cssVar("material", `${name}.border`)
                      : "transparent",
                  boxShadow:
                    "shadow" in material
                      ? cssVar("material", `${name}.shadow`)
                      : undefined,
                }}
              >
                <code>{name}</code>
                <small>blur {material.blur}px</small>
              </div>
            ))}
          </div>
        </Specimen>
      </div>
    </>
  );
}

export function IconTokens({ tokens }: { tokens: TokenSet }) {
  const nativeOnly = Object.entries(tokens.icon).filter(
    ([, icon]) => !icon.platforms.includes("web"),
  );
  return (
    <>
      <Specimen
        api="name · size: a size.icon value, 18 by default"
        description="Icons are aria-hidden and take the color of the text around them, so the label beside them names the action."
        title="Icon"
      >
        <div className={styles.specimenCases}>
          <SpecimenCase id="icon-set">
            <div className={`${styles.iconGrid} ${controls.iconSet}`}>
              {iconNames.map((name) => {
                const icon = tokens.icon[name];
                return (
                  <div
                    data-icon={name}
                    key={name}
                    title={`${icon.description} SF Symbol: ${icon.sfSymbol}`}
                  >
                    <Icon name={name} size={20} />
                    <code>{name}</code>
                    {icon.platforms.includes("ios") ? null : (
                      <small>Web only</small>
                    )}
                  </div>
                );
              })}
            </div>
          </SpecimenCase>
          <SpecimenCase id="icon-sizes">
            <div className={controls.iconRow}>
              {([14, 16, 18, 24] as const).map((size) => (
                <div key={size}>
                  <Icon name="calendar" size={size} />
                  <code>{size}</code>
                </div>
              ))}
            </div>
          </SpecimenCase>
          <SpecimenCase id="icon-color">
            <div className={controls.iconColors}>
              {(
                [
                  ["ink", "timeline", "Timeline"],
                  ["muted", "archive", "Library"],
                  ["accent", "plus", "Add entry"],
                  ["warm", "refresh", "Retry sync"],
                ] as const
              ).map(([color, icon, label]) => (
                <span data-color={color} key={color}>
                  <Icon name={icon} size={18} />
                  {label}
                </span>
              ))}
            </div>
          </SpecimenCase>
        </div>
      </Specimen>
      <Specimen
        description="These names draw only on iOS, as the SF Symbol shown. Web has no glyph for them yet."
        id="native-icons"
        title="iOS-only icons"
      >
        <div className={styles.nativeIconList}>
          {nativeOnly.map(([name, icon]) => (
            <div key={name} title={icon.description}>
              <code>{name}</code>
              <small>{icon.sfSymbol}</small>
            </div>
          ))}
        </div>
      </Specimen>
    </>
  );
}

export function LayoutTokens({ tokens }: { tokens: TokenSet }) {
  const descriptions: Record<string, string | undefined> = tokens.descriptions;
  const { breakpoint, container, inset, layer, pageGutter, pageWidth } =
    tokens.layout;
  return (
    <>
      <Specimen
        api="variant: compact | standard | wide | canvas · className · div props"
        description="The centered column that holds a page. Phones use the full width inside the page gutters; wider windows center the page at its variant width. This gallery uses canvas."
        id="page-frame"
        title="PageFrame"
      >
        <SpecimenCase id="page-frame-widths">
          <div className={styles.pageFrameTrack}>
            <div>
              {pageFrameVariants.map((variant) => (
                <PageFrame
                  className={styles.pageFrameSample}
                  data-page-width={variant}
                  key={variant}
                  variant={variant}
                >
                  <strong>{variant}</strong>
                  <span>
                    {pageWidth[variant]}px ·{" "}
                    {descriptions[`layout.pageWidth.${variant}`]}
                  </span>
                </PageFrame>
              ))}
            </div>
          </div>
        </SpecimenCase>
      </Specimen>
      <div className={styles.foundationGrid}>
        <Specimen
          description="Horizontal page padding at each window class."
          id="page-gutters"
          title="Page gutters"
        >
          <div className={styles.scaleList}>
            {Object.entries(pageGutter).map(([name, value]) => (
              <div
                className={styles.scaleRow}
                key={name}
                title={descriptions[`layout.pageGutter.${name}`]}
              >
                <code>{name}</code>
                <span
                  aria-hidden="true"
                  style={{ width: cssVar("layout-page-gutter", name) }}
                />
                <small>{value}px</small>
              </div>
            ))}
          </div>
        </Specimen>

        <Specimen
          description="Viewport widths where Web layouts change. CSS cannot read variables in media queries, so Web lint holds every media query to max-width at one of these values or min-width one pixel above it, and every container query to a container value."
          id="breakpoints"
          title="Breakpoints and containers"
        >
          <div className={styles.chipList}>
            {Object.values(breakpoint).map((value) => (
              <code data-breakpoint={value} key={value}>
                {value}px
              </code>
            ))}
          </div>
          <p className={styles.chipListLabel}>Container queries</p>
          <div className={styles.chipList}>
            {Object.values(container).map((value) => (
              <code key={value}>{value}px</code>
            ))}
          </div>
        </Specimen>
      </div>
      <Specimen
        description="Room Web keeps around floating controls and overlays."
        id="insets"
        title="Insets"
      >
        <div className={styles.layerList}>
          {Object.entries(inset).map(([name, value]) => (
            <div key={name}>
              <code>{name}</code>
              <strong>{value}px</strong>
              <small>{descriptions[`layout.inset.${name}`]}</small>
            </div>
          ))}
        </div>
      </Specimen>
      <Specimen
        description="Web stacking order, from local layering inside a component to overlays above the map."
        id="layers"
        title="Layers"
      >
        <div className={styles.layerList}>
          {Object.entries(layer).map(([name, value]) => (
            <div key={name}>
              <code>{name}</code>
              <strong>{value}</strong>
              {descriptions[`layout.layer.${name}`] ? (
                <small>{descriptions[`layout.layer.${name}`]}</small>
              ) : null}
            </div>
          ))}
        </div>
      </Specimen>
    </>
  );
}
