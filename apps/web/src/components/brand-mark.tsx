type BrandMarkProps = {
  className?: string;
};

export function BrandMark({ className }: BrandMarkProps) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      focusable="false"
      shapeRendering="geometricPrecision"
      viewBox="0 0 64 64"
    >
      <g fill="none" strokeLinecap="round">
        <path
          data-brand-part="outer-ring"
          d="M27 13.3A19.4 19.4 0 1 0 51.1 35.4"
          stroke="#315E4F"
          strokeWidth="7"
        />
        <path
          data-brand-part="accent"
          d="M38.6 13.8A19.4 19.4 0 0 1 50.2 25.4"
          stroke="#A76346"
          strokeWidth="7"
        />
        <path
          data-brand-part="inner-ring"
          d="M29 20.8A11.6 11.6 0 1 0 41.5 38.6"
          stroke="#82AD98"
          strokeWidth="4.25"
        />
      </g>
    </svg>
  );
}
