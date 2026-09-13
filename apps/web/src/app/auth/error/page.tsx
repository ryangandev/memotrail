import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import styles from "./page.module.css";

export default function AuthErrorPage() {
  return (
    <main className={styles.shell}>
      <section className={styles.card}>
        <BrandMark className={styles.mark} />
        <p>Authentication</p>
        <h1>Sign-in did not finish.</h1>
        <span>
          Your private archive was not opened. Return to MemoTrail and try
          Google Sign-In again.
        </span>
        <Link href="/">Return to MemoTrail</Link>
      </section>
    </main>
  );
}
