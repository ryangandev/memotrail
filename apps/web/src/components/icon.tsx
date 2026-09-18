export const iconNames = [
  "archive",
  "bold",
  "bulletList",
  "calendar",
  "car",
  "check",
  "chevron",
  "close",
  "clock",
  "code",
  "codeBlock",
  "inbox",
  "home",
  "italic",
  "link",
  "map",
  "mic",
  "more",
  "photo",
  "person",
  "plus",
  "quote",
  "refresh",
  "search",
  "settings",
  "sparkle",
  "star",
  "stop",
  "strike",
  "target",
  "tag",
  "timeline",
  "trash",
  "underline",
  "orderedList",
] as const;

export type IconName = (typeof iconNames)[number];

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
  bold: (
    <>
      <path d="M7 4h6a4 4 0 0 1 0 8H7V4Z" />
      <path d="M7 12h7a4 4 0 0 1 0 8H7v-8Z" />
    </>
  ),
  bulletList: (
    <>
      <circle cx="5" cy="7" fill="currentColor" r="1" stroke="none" />
      <circle cx="5" cy="12" fill="currentColor" r="1" stroke="none" />
      <circle cx="5" cy="17" fill="currentColor" r="1" stroke="none" />
      <path d="M9 7h10M9 12h10M9 17h10" />
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
  close: <path d="m7 7 10 10M17 7 7 17" />,
  clock: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3 2" />
    </>
  ),
  code: <path d="m8 8-4 4 4 4M16 8l4 4-4 4M14 5l-4 14" />,
  codeBlock: (
    <>
      <rect height="18" rx="2" width="20" x="2" y="3" />
      <path d="m9 8-4 4 4 4M15 8l4 4-4 4" />
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
  italic: <path d="M10 4h8M6 20h8M14 4l-4 16" />,
  link: (
    <>
      <path d="m9.5 14.5-1 1a4 4 0 0 1-5.7-5.7l3-3a4 4 0 0 1 5.7 0" />
      <path d="m14.5 9.5 1-1a4 4 0 0 1 5.7 5.7l-3 3a4 4 0 0 1-5.7 0M8.5 12h7" />
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
  person: (
    <>
      <circle cx="12" cy="8" r="4" />
      <path d="M4.5 20a7.5 7.5 0 0 1 15 0" />
    </>
  ),
  plus: <path d="M12 5v14M5 12h14" />,
  quote: (
    <>
      <path d="M5 10h5v5H5v-4a5 5 0 0 1 5-5" />
      <path d="M14 10h5v5h-5v-4a5 5 0 0 1 5-5" />
    </>
  ),
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
  settings: (
    <>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z" />
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
  strike: (
    <path d="M5 12h14M16.5 7.5A4.5 4.5 0 0 0 12 5c-2.2 0-4 1.2-4 3 0 1 .6 1.7 1.6 2.2M8 16c.8 1.8 2.4 3 4.6 3 2.4 0 4.4-1.3 4.4-3.3 0-.7-.2-1.2-.6-1.7" />
  ),
  target: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="4.5" />
      <circle cx="12" cy="12" fill="currentColor" r="1" stroke="none" />
    </>
  ),
  tag: (
    <>
      <path d="M4 4h7.5L20 12.5 12.5 20 4 11.5V4Z" />
      <circle cx="8.2" cy="8.2" r="1.25" />
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
  underline: (
    <>
      <path d="M7 4v7a5 5 0 0 0 10 0V4M5 20h14" />
    </>
  ),
  orderedList: (
    <>
      <path d="M10 7h10M10 12h10M10 17h10M4 5h1v4M4 11h2l-2 3h2M4 16h2l-1.5 1.5A1 1 0 0 1 6 19H4" />
    </>
  ),
};
