import styles from "./brand-mark.module.css";

type BrandMarkProps = {
  className?: string;
  motion?: "counter-rotation";
  collapsed?: boolean;
};

export function BrandMark({
  className,
  motion,
  collapsed = false,
}: BrandMarkProps) {
  return (
    <svg
      aria-hidden="true"
      className={[styles.mark, className, motion && styles.counterRotation]
        .filter(Boolean)
        .join(" ")}
      data-collapsed={motion ? collapsed : undefined}
      focusable="false"
      shapeRendering="geometricPrecision"
      viewBox="0 0 64 64"
    >
      <g fill="none" strokeLinecap="round">
        <path
          data-brand-part="outer-ring"
          d="M27 13.3A19.4 19.4 0 1 0 51.1 35.4"
          strokeWidth="7"
        />
        <path
          data-brand-part="accent"
          d="M38.6 13.8A19.4 19.4 0 0 1 50.2 25.4"
          strokeWidth="7"
        />
        <path
          data-brand-part="inner-ring"
          d="M29 20.8A11.6 11.6 0 1 0 41.5 38.6"
          strokeWidth="4.25"
        />
      </g>
    </svg>
  );
}
