"use client";
import { Button } from "@/components/button";
import type { PhotoLocationDraft } from "@/lib/media/photo-location";

export function PhotoLocationEditor({
  value,
  onChange,
  disabled,
}: {
  value: PhotoLocationDraft;
  onChange: (value: PhotoLocationDraft | null) => void;
  disabled: boolean;
}) {
  return (
    <fieldset disabled={disabled}>
      <legend>Photo Location to add when you save</legend>
      <p>
        The photo&apos;s GPS position will be saved for this Entry after you
        confirm. No address or personal Location name is inferred.
      </p>
      <p>
        {value.latitude.toFixed(5)}, {value.longitude.toFixed(5)}
      </p>
      <Button variant="secondary" type="button" onClick={() => onChange(null)}>
        Remove Location from draft
      </Button>
    </fieldset>
  );
}
