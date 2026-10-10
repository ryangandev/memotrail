import { createElement } from "react";
import {
  iconElements,
  iconStrokeWidth,
  iconViewBox,
  type IconName,
  type IconSize,
} from "@/generated/design-system";

// The icon vocabulary is generated from packages/design-system/icons.json, which also maps each
// name to the SF Symbol native iOS draws.
export {
  iconNames,
  type IconName,
  type IconSize,
} from "@/generated/design-system";

type IconProps = {
  name: IconName;
  /** A size.icon token, in px. */
  size?: IconSize;
};

export function Icon({ name, size = 18 }: IconProps) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height={size}
      viewBox={iconViewBox}
      width={size}
    >
      <g
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={iconStrokeWidth}
      >
        {iconElements[name].map(([tag, attributes], index) =>
          createElement(tag, { ...attributes, key: index }),
        )}
      </g>
    </svg>
  );
}
