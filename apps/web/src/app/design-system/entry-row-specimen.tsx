"use client";

import {
  EntryRow,
  EntryRowGroup,
  EntryRowList,
} from "@/components/entry-row";
import styles from "./entry-row-specimen.module.css";
import { loadedImage } from "./samples";
import { Specimen, SpecimenCase } from "./specimen";

// EntryRow is Web only, so these samples have no iOS twin.

function LibraryRows() {
  return (
    <>
      <EntryRowGroup headingLevel={3} label="October 2026">
        <EntryRow
          date="Oct 17"
          dateTime="2026-10-17"
          excerpt="Four interviews back to back. The last one felt like a conversation instead of a test."
          href="#entry-row"
          tags={["career", "nyc"]}
          title="Final round at the design studio"
        />
        <EntryRow
          date={null}
          dateTime="2026-10-15"
          excerpt="Walked the long way home and watched the light go orange over the river."
          href="#entry-row"
          title="Thursday, October 15, 2026"
        />
        <EntryRow
          date="Oct 14"
          dateTime="2026-10-14"
          excerpt="Dumplings from scratch. Took four hours and every pleat was uneven."
          href="#entry-row"
          isFirstTime
          tags={["cooking", "friends"]}
          thumbnail={{ alt: "The table set for twelve", src: loadedImage }}
          title="Cooking for twelve people"
        />
      </EntryRowGroup>
      <EntryRowGroup headingLevel={3} label="January 2026">
        <EntryRow
          date="Jan 2026 - now"
          dateTime="2026-01"
          excerpt="Leaving consulting and looking for work that makes things."
          href="#entry-row"
          isChapter
          title="2026 job search"
        />
      </EntryRowGroup>
      <EntryRowGroup headingLevel={3} label="September 2025">
        <EntryRow
          date="Fall 2025"
          dateTime="2025-09"
          excerpt="Bouldering twice a week, mostly falling."
          href="#entry-row"
          isFirstTime
          title="Learning to climb"
        />
      </EntryRowGroup>
    </>
  );
}

export function EntryRowSpecimen() {
  return (
    <Specimen
      api="href · title · date · dateTime · excerpt · tags · isChapter · isFirstTime · thumbnail · matchReasons · actions · variant: default | compact"
      description="One Entry in a ruled list. A list narrower than 620 px moves the date above the title, and an untitled Entry is titled by its date with no date line."
      id="entry-row"
      title="EntryRow"
    >
      <div className={styles.cases}>
        <SpecimenCase id="entry-row-default">
          <div className={styles.frames}>
            <div className={styles.frame} data-frame="wide">
              <LibraryRows />
            </div>
            <div className={styles.frame} data-frame="narrow">
              <LibraryRows />
            </div>
          </div>
        </SpecimenCase>
        <SpecimenCase id="entry-row-compact">
          <div className={styles.frames}>
            <div className={styles.frame} data-frame="wide">
              <EntryRowList label="Entries in this Chapter">
                <EntryRow
                  date="Oct 17"
                  dateTime="2026-10-17"
                  href="#entry-row"
                  title="Final round at the design studio"
                  variant="compact"
                />
                <EntryRow
                  date="Sep 30"
                  dateTime="2026-09-30"
                  href="#entry-row"
                  isFirstTime
                  title="First offer, turned down"
                  variant="compact"
                />
              </EntryRowList>
            </div>
            <div className={styles.frame} data-frame="wide">
              <EntryRowList label="Search results">
                <EntryRow
                  date="Jul 9, 2017"
                  dateTime="2017-07-09"
                  excerpt={
                    <>
                      …the old <mark>lantern</mark> on the porch still
                      worked after the storm…
                    </>
                  }
                  href="#entry-row"
                  matchReasons={["Title", "Body"]}
                  title="The lantern on the porch"
                />
              </EntryRowList>
            </div>
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}
