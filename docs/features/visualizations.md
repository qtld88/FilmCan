# Visualizations

Real-time transfer status.

---

## Before Transfer

- Source size and file count
- Destination free space
- Size indicators

---

## During Transfer

- Progress bars per destination
- Speed and estimated time
- Current file

---

## Blue vs Green Bars

- **Green**: copy progress
- **Blue**: verification progress (may stay empty if verification is off)

**Behavior**
- During copy, the green bar advances.
- If verification is enabled, the blue bar advances as files are verified.
- A destination is fully done when the copy bar is complete (and the verification bar too, if verification is enabled).

---

## Status Colors

- **Green**: active or done
- **Orange**: paused
- **Gray**: pending
- **Red**: error
