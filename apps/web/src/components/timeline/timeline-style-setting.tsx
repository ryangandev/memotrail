"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveTimelineStyle } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { Icon } from "@/components/icon";
import settingsFieldsStyles from "@/components/settings-fields.module.css";
import { timelineStyles, type TimelineStyle } from "@/lib/timeline-style";
import styles from "./timeline-style-setting.module.css";

const labels: Record<TimelineStyle, string> = {
  classic: "Classic",
  vertical: "Vertical Spine",
  "sticky-year": "Sticky Year",
};

export function TimelineStyleSetting({
  initialStyle,
}: {
  initialStyle: TimelineStyle;
}) {
  const router = useRouter();
  const [style, setStyle] = useState(initialStyle);
  const [isPending, startTransition] = useTransition();

  function choose(next: TimelineStyle) {
    if (next === style) return;
    const previous = style;
    setStyle(next);
    startTransition(async () => {
      try {
        const result = await saveTimelineStyle(next);
        if (result.status === "error") {
          setStyle(previous);
          notify.error(result.message);
          return;
        }
        router.refresh();
        notify.success("Timeline style saved.");
      } catch {
        setStyle(previous);
        notify.error("MemoTrail could not save your Timeline style.");
      }
    });
  }

  return (
    <div className={styles.row}>
      <span className={settingsFieldsStyles.preferenceIcon}>
        <Icon name="timeline" size={20} />
      </span>
      <div className={styles.copy}>
        <strong>Timeline style</strong>
        <p>Choose how your Timeline reads in this browser.</p>
      </div>
      <fieldset
        aria-busy={isPending}
        className={styles.options}
        disabled={isPending}
      >
        <legend>Timeline style</legend>
        {timelineStyles.map((option) => (
          <label key={option}>
            <input
              checked={style === option}
              name="timeline-style"
              onChange={() => choose(option)}
              type="radio"
              value={option}
            />
            <span>{labels[option]}</span>
          </label>
        ))}
      </fieldset>
    </div>
  );
}
