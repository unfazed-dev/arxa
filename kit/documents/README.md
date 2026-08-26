# arxa_kit_documents

A deliberately **API-first** kit for document workflows. It defines the typed
ports now so app code can be written against them, and backs them natively
later.

Phase: **1 — ports + fakes**, with two working paths (document picking, PDF
page counting/rendering via `pdfrx`).

## Scope

### Working paths

- `ArxaKitDocumentPickerService` — `pickDocument({extensions})` /
  `pickDocuments({extensions})`. Backed by `file_selector`
  (`FileSelectorArxaKitDocumentPickerService`).
- `ArxaKitPickedDocument` — `name` / `path` / `mimeType` / lazy `readBytes()`.
  `file_selector`'s `XFile` never crosses the seam.
- `ArxaKitPdfService` — `pageCount` / `renderPage` backed by **`pdfrx`**
  (`ArxaKitPdfrxPdfService`, PDFium: iOS/Android/macOS/Windows/Linux/Web).
  `createFromImages` stays stubbed — pdfrx renders, it does not assemble.
- `ArxaKitPdfViewer` — interactive viewing (scroll/zoom/selection) over pdfrx's
  `PdfViewer`; `.data` / `.asset` / `.file` / `.network` constructors.

### Stub ports (phase 2 — native-first)

Mission name → class:

- `DocumentScanService` → **`ArxaKitDocumentScanService`** (`scan({pageLimit})` →
  `ArxaKitScannedDocument`/`ArxaKitScannedPage`).
- `OcrService` → **`ArxaKitOcrService`** (`recognizeText(bytes)` → `ArxaKitOcrResult`/
  `ArxaKitOcrBlock`).

Each ships an `Unimplemented…` concrete class whose methods throw
`UnimplementedError` and carry `// TODO(arxa_kit_documents)` tags naming the
target native API.

## Native-first plan

- **Scan** — VisionKit `VNDocumentCameraViewController` / DocKit on iOS; ML Kit
  Document Scanner on Android.
- **OCR** — Vision `VNRecognizeTextRequest` on iOS; ML Kit Text Recognition on
  Android.
- **PDF** — superseded: rendering went to `pdfrx` (PDFium) instead of
  PDFKit / `PdfRenderer` — one code path covering all six platforms incl. web.
  PDF *assembly* (`createFromImages`) remains open (candidate: `package:pdf`).

Backing package (working path) verified pub.dev 2026-07-14: `file_selector`
**^1.1.0**.

## Testing

`package:arxa_kit_documents/arxa_kit_testing.dart` exports fakes for all four ports —
`FakeArxaKitDocumentPickerService`, `FakeArxaKitDocumentScanService`,
`FakeArxaKitOcrService`, `FakeArxaKitPdfService`. Each supports a `failWith` error to
exercise **failure states**; the picker/scan fakes return `null` to simulate a
**user cancel**.

## Non-goals

No path dependency on `arxa_kit_permissions` (or any kit). The camera /
photo-library permission dependency for scanning is wired by the downstream
reconciliation pass.
