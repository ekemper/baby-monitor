# Simplify Server — Questions

All clarifying questions were resolved during the collaborative design session.

Key decisions made:
- **Camera:** USB webcam (not CSI) → ffmpeg with V4L2, not libcamera-vid
- **Platform:** Pi-only, no Mac dev support → no OpenCV fallback needed
- **Viewers:** iOS-only → delete React client entirely
- **Capture approach:** ffmpeg subprocess piping MJPEG with SOI/EOI frame splitting
