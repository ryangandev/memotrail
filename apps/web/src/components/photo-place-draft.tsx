"use client";
import { Button } from "@/components/button";
import type { PhotoPlaceDraft } from "@/lib/media/photo-place";
export function PhotoPlaceEditor({
  value,
  onChange,
  disabled,
}: {
  value: PhotoPlaceDraft;
  onChange: (value: PhotoPlaceDraft | null) => void;
  disabled: boolean;
}) {
  return (
    <fieldset disabled={disabled}>
      <legend>Photo Location to add when you save</legend>
      <p>
        The photo&apos;s GPS position will be saved for this Entry after you
        confirm. No address or personal Location name is inferred.
      </p>
      {value.kind === "new" ? (
        <p>
          {value.latitude?.toFixed(5)}, {value.longitude?.toFixed(5)}
        </p>
      ) : (
        <p>This Entry&apos;s current Location is unchanged.</p>
      )}
      <Button variant="secondary" type="button" onClick={() => onChange(null)}>
        Remove Location from draft
      </Button>
    </fieldset>
  );
}
