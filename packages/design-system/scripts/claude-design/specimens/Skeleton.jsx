import { Row, Stack } from "./runtime.jsx";

const { Skeleton } = MemoTrail;

export const specimens = {
  "skeleton-shapes": {
    title: "Line, block, circle, and a still placeholder",
    render: () => (
      <Row align="start">
        <Skeleton height={56} shape="circle" width={56} />
        <div style={{ width: 200 }}>
          <Stack gap="var(--mt-space-2)">
            <Skeleton shape="line" width="70%" />
            <Skeleton shape="line" />
            <Skeleton shape="line" width="45%" />
          </Stack>
        </div>
        <Skeleton height={96} width={140} />
        <Skeleton animated={false} height={96} width={96} />
      </Row>
    ),
  },
};
