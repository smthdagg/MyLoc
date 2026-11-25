# Third-Party Licenses & Notices

MyLoc is an independent implementation. The following third-party open-source libraries are used:

---

## 1. `idevice`
- **Repository**: https://github.com/jkcoxson/idevice
- **Crate**: https://crates.io/crates/idevice
- **Author**: Jackson Coxson (`jkcoxson`)
- **License**: MIT License

```text
MIT License

Copyright (c) Jackson Coxson

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
```

---

## 2. External App Interoperability (No Code Included)
- **LocalDevVPN**: MyLoc does **not** include, link, or redistribute any code or assets from LocalDevVPN or StosVPN. It only checks local TCP reachability on `10.7.0.1:49152` and optionally opens the external app via URL scheme when the user triggers it.

---

## 3. Transitive Rust Dependencies
Transitive dependencies of `idevice` (such as `tokio`, `plist`, `rustls`, etc.) are declared in `Rust/myloc-engine/Cargo.lock` and retain their respective MIT / Apache-2.0 / BSD licenses.
