import styles from "./tag-chip.module.css";

/** A noninteractive tag label, safe to compose inside links and buttons. */
export function TagChip({ name }: { name: string }) {
  return (
    <span className={styles.chip} data-ui-tag-chip title={`#${name}`}>
      <span className={styles.label}>#{name}</span>
    </span>
  );
}
