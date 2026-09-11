# References and acknowledgements

The read-only HID sensor/report pairing was verified against
[ResetPower26/LidSense](https://github.com/ResetPower26/LidSense/blob/main/LidSense/LidAngleReader.swift).
The initial spatial blur study was informed by
[chuspeeism/iphone-duo](https://github.com/chuspeeism/iphone-duo/blob/main/main.js).
The current implementation uses an original fixed-observer ray/plane projection
for the MacBook and Apple's Metal Performance Shaders Gaussian filters.

Both references are MIT licensed. The following notices apply to the corresponding derived portions:

Copyright (c) 2026 resetpower.moe

Copyright (c) 2026 jadon7

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Apple product/design references:

- https://www.apple.com/iphone-duo/
- https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
- https://developer.apple.com/documentation/screencapturekit

No Apple artwork, firmware, or private iOS animation code is included. This is an
independent approximation adapted to a MacBook, not a pixel-identical port of iOS.
