import styles from "./page.module.css";

export default function Home() {
  return (
    <main className={styles.page}>
      <p className={styles.eyebrow}>Phase 1 foundation</p>
      <h1>MemoTrail</h1>
      <p className={styles.description}>
        A private record of a life in progress.
      </p>
    </main>
  );
}
