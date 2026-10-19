import { ButtonLink } from "@/components/button";
import { BrandMark } from "@/components/brand-mark";
import styles from "./page.module.css";

export default function AuthErrorPage() {
  return (
    <div className={styles.shell}>
      <header className={styles.header}>
        <BrandMark className={styles.mark} />
        <strong>MemoTrail</strong>
      </header>
      <main className={styles.main}>
        <h1>Sign-in did not finish.</h1>
        <p>
          Your Entries were not opened. Return to MemoTrail and try Google
          Sign-In again.
        </p>
        <ButtonLink className={styles.action} variant="primary" href="/">
          Return to MemoTrail
        </ButtonLink>
      </main>
    </div>
  );
}
