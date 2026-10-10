const { FocusedDetailUnavailable } = MemoTrail;

export const specimens = {
  "focused-detail-unavailable-default": {
    title: "A record that moved to Trash",
    render: () => (
      <FocusedDetailUnavailable back="#homes" backLabel="Homes" label="Home" />
    ),
  },
};
