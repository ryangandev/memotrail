import { Row } from "./runtime.jsx";

const { BrandMark } = MemoTrail;

export const specimens = {
  "brand-mark-sizes": {
    title: "The mark at 32, 48, and 72px",
    render: () => (
      <Row>
        {[32, 48, 72].map((size) => (
          <span
            key={size}
            style={{ display: "block", width: size, height: size }}
          >
            <BrandMark />
          </span>
        ))}
      </Row>
    ),
  },
};
