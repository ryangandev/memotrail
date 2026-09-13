# Synthetic HEIC fixture

`synthetic.heic.base64` encodes a 120 by 80 solid green image created specifically for MemoTrail's codec regression tests.
It contains no personal photograph or third-party content.
The input was generated with Sharp and encoded using macOS `sips -s format heic`.
Keep this real HEVC fixture so portable deployment does not accidentally depend on a local libvips HEIC codec.
