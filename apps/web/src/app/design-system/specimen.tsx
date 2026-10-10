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

export function kebab(value: string) {
  return value.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
}

export function capitalize(value: string) {
  return `${value[0].toUpperCase()}${value.slice(1)}`;
}
