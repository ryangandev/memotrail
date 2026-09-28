"use client";

import { useState } from "react";
import { Badge } from "@/components/badge";
import { BrandMark } from "@/components/brand-mark";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import styles from "./brand-motion-preview.module.css";

export function BrandMotionPreview() {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <div className={styles.preview}>
      <article
        aria-labelledby="brand-motion-counter"
        className={styles.study}
        data-brand-motion-study="counter"
        data-collapsed={collapsed}
      >
        <header className={styles.heading}>
          <h4 id="brand-motion-counter">Counter rotation</h4>
          <Badge size="micro" tone="neutral">
            320 ms
          </Badge>
        </header>
        <div className={styles.stage}>
          <div className={styles.magnified}>
            <BrandMark
              className={styles.mark}
              collapsed={collapsed}
              motion="counter-rotation"
            />
          </div>
          <div className={styles.rail}>
            <div className={styles.railHeader}>
              <BrandMark
                className={styles.railMark}
                collapsed={collapsed}
                motion="counter-rotation"
              />
              <span className={styles.wordmark}>MemoTrail</span>
            </div>
            <div className={styles.railItem}>
              <Icon name="dashboard" size={18} />
              <span>Dashboard</span>
            </div>
          </div>
        </div>
        <p className={styles.description}>
          The outer ring and warm accent turn together while the inner ring
          turns in the opposite direction. Shown at 64px and the 29px sidebar
          size.
        </p>
        <div className={styles.controls}>
          <Badge size="micro" tone="outline">
            {collapsed ? "Collapsed" : "Expanded"}
          </Badge>
          <Button
            aria-label={`${collapsed ? "Expand" : "Collapse"} Counter rotation preview`}
            onClick={() => setCollapsed((current) => !current)}
            size="small"
            variant="secondary"
          >
            <Icon
              name={collapsed ? "sidebarClosed" : "sidebarOpen"}
              size={16}
            />
            {collapsed ? "Expand" : "Collapse"}
          </Button>
        </div>
      </article>
      <p className={styles.reducedMotionNote}>
        Reduced motion is on. The preview changes state without rotation.
      </p>
    </div>
  );
}
