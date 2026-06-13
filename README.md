# MD5 Hash

A lightweight macOS application for computing MD5 hashes of files. Simply drag and drop a file onto the app window to calculate its hash.

<img width="447" height="221" alt="Image" src="https://github.com/user-attachments/assets/539cd71e-c445-419d-902d-8330d38155f7" />

<img width="449" height="316" alt="Image" src="https://github.com/user-attachments/assets/48a8ebf6-f102-46de-ad1d-f19ce0b16d9a" />

## Features

- **Drag & Drop Interface** – Drop any file onto the window to compute its MD5 hash
- **Progress Tracking** – Real-time progress indicator for large files
- **One-Click Copy** – Copy the hash result to your clipboard with a single click
- **Memory Efficient** – Chunks file reads to handle large files without excessive memory use
- **Native macOS App** – Built with SwiftUI for a native experience

## Building from Source

### Requirements

- macOS 11.0 or later
- Swift toolchain (Xcode Command Line Tools)

### Build

```bash
./build.sh
```

The built app will be available as `MD5Hash.app` and can be run directly or moved to `/Applications`.

## Usage

1. Launch the MD5Hash app
2. Drag a file onto the window
3. The MD5 hash will be calculated and displayed
4. Click the result to copy it to your clipboard

## License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.
