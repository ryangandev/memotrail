export type IconName =
  | "archive"
  | "calendar"
  | "car"
  | "check"
  | "chevron"
  | "clock"
  | "inbox"
  | "home"
  | "map"
  | "mic"
  | "more"
  | "photo"
  | "plus"
  | "refresh"
  | "search"
  | "sparkle"
  | "star"
  | "stop"
  | "target"
  | "timeline"
  | "trash";

type IconProps = {
  name: IconName;
  size?: number;
};

export function Icon({ name, size = 18 }: IconProps) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height={size}
      viewBox="0 0 24 24"
      width={size}
    >
      <g
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.7"
      >
        {paths[name]}
      </g>
    </svg>
  );
}

const paths: Record<IconName, React.ReactNode> = {
  archive: (
    <>
      <path d="M4 8.5h16v11H4z" />
      <path d="M3 4.5h18v4H3zM9 13h6" />
    </>
  ),
  calendar: (
    <>
      <rect height="17" rx="2" width="18" x="3" y="4" />
      <path d="M8 2v4M16 2v4M3 9h18" />
    </>
  ),
  car: (
    <>
      <path d="m5 11 1.6-4.2A2 2 0 0 1 8.5 5.5h7a2 2 0 0 1 1.9 1.3L19 11" />
      <path d="M4 11h16a1 1 0 0 1 1 1v5H3v-5a1 1 0 0 1 1-1ZM6 17v2M18 17v2M6.5 14h1M16.5 14h1" />
    </>
  ),
  check: <path d="m5 12 4 4L19 6" />,
  chevron: <path d="m9 18 6-6-6-6" />,
  clock: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3 2" />
    </>
  ),
  inbox: (
    <>
      <path d="M4.5 5.5h15l1.5 9v4H3v-4l1.5-9Z" />
      <path d="M3 14.5h5l1.5 2h5l1.5-2h5" />
    </>
  ),
  home: (
    <>
      <path d="m3.5 10.5 8.5-7 8.5 7" />
      <path d="M5.5 9v11h13V9M9.5 20v-6h5v6" />
    </>
  ),
  map: (
    <>
      <path d="m3.5 6.5 5-2 7 2 5-2v13l-5 2-7-2-5 2v-13Z" />
      <path d="M8.5 4.5v13M15.5 6.5v13" />
    </>
  ),
  mic: (
    <>
      <rect height="12" rx="4" width="7" x="8.5" y="2.5" />
      <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M9 21h6" />
    </>
  ),
  more: (
    <>
      <circle cx="5" cy="12" fill="currentColor" r="1" stroke="none" />
      <circle cx="12" cy="12" fill="currentColor" r="1" stroke="none" />
      <circle cx="19" cy="12" fill="currentColor" r="1" stroke="none" />
    </>
  ),
  photo: (
    <>
      <rect height="16" rx="2" width="18" x="3" y="4" />
      <circle cx="8.5" cy="9" r="1.5" />
      <path d="m5.5 17 4-4 3 3 2-2 4 3" />
    </>
  ),
  plus: <path d="M12 5v14M5 12h14" />,
  refresh: (
    <>
      <path d="M19 8a7.5 7.5 0 0 0-12.6-2L4 8" />
      <path d="M4 4v4h4M5 16a7.5 7.5 0 0 0 12.6 2L20 16" />
      <path d="M20 20v-4h-4" />
    </>
  ),
  search: (
    <>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path d="m15.5 15.5 5 5" />
    </>
  ),
  sparkle: (
    <path d="M12 3c.7 4.4 3.2 6.9 7 7.5-3.8.6-6.3 3.1-7 7.5-.7-4.4-3.2-6.9-7-7.5 3.8-.6 6.3-3.1 7-7.5Z" />
  ),
  star: (
    <path d="m12 3 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9L12 3Z" />
  ),
  stop: (
    <rect
      fill="currentColor"
      height="10"
      rx="1.5"
      stroke="none"
      width="10"
      x="7"
      y="7"
    />
  ),
  target: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="4.5" />
      <circle cx="12" cy="12" fill="currentColor" r="1" stroke="none" />
    </>
  ),
  timeline: (
    <>
      <path d="M6 4v16" />
      <circle cx="6" cy="7" fill="currentColor" r="1.5" stroke="none" />
      <circle cx="6" cy="16" fill="currentColor" r="1.5" stroke="none" />
      <path d="M10 7h9M10 16h7" />
    </>
  ),
  trash: (
    <>
      <path d="M4 7h16M9 3h6l1 4H8l1-4ZM6.5 7l1 14h9l1-14M10 11v6M14 11v6" />
    </>
  ),
};
