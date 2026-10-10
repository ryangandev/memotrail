import {
  componentSpecimens,
  type ComponentSpecimenId,
} from "@/generated/design-system";
import styles from "./page.module.css";

export function Specimen({
  api,
  children,
  description,
  id,
  title,
}: {
  api?: string;
  children: React.ReactNode;
  description?: string;
  id?: string;
  title: string;
}) {
  return (
    <article className={styles.specimen} id={id}>
      <header>
        <div>
          <h3>{title}</h3>
          {description ? <p>{description}</p> : null}
        </div>
        {api ? <code>{api}</code> : null}
      </header>
      <div className={styles.specimenBody}>{children}</div>
    </article>
  );
}

/**
 * One specimen from a component spec in packages/design-system/components. The id is typed from
 * the generated specimen list, and the e2e test finds every listed specimen by data-specimen.
 */
export function SpecimenCase({
  children,
  id,
}: {
  children: React.ReactNode;
  id: ComponentSpecimenId;
}) {
  const specimen = componentSpecimens.find((item) => item.id === id);
  return (
    <section
      aria-labelledby={`specimen-${id}`}
      className={styles.specimenCase}
      data-specimen={id}
    >
      <div className={styles.specimenCaseHeader}>
        <h4 id={`specimen-${id}`}>{id}</h4>
        <p>{specimen?.description}</p>
      </div>
      <div className={styles.specimenCaseBody}>{children}</div>
    </section>
  );
}

export function kebab(value: string) {
  return value.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
}

export function capitalize(value: string) {
  return `${value[0].toUpperCase()}${value.slice(1)}`;
}
