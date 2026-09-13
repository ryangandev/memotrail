# Synthetic HEIC fixture

`synthetic.heic.base64` encodes a 120 by 80 solid green image created specifically for MemoTrail's codec regression tests.
It contains no personal photograph or third-party content.
The input was generated with Sharp and encoded using macOS `sips -s format heic`.
Keep this real HEVC fixture so portable deployment does not accidentally depend on a local libvips HEIC codec.

`camera-metadata.heic.base64` is a 32 by 24 solid green image encoded with macOS ImageIO for metadata regression tests.
Its synthetic camera timestamp is `2017:07:08 12:34:56`, and its synthetic GPS is `39.95, -75.1666666667`.
No personal photo was used.
