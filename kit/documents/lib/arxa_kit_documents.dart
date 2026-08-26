/// arxa_kit_documents — a deliberately API-first kit for document workflows.
///
/// The working paths today are picking an existing document
/// ([ArxaKitDocumentPickerService] over `file_selector`) and PDF page counting /
/// rendering ([ArxaKitPdfrxPdfService] over `pdfrx`/PDFium, all six platforms).
/// Scanning ([ArxaKitDocumentScanService]) and OCR ([ArxaKitOcrService]) remain full
/// stub ports — final typed signatures, `UnimplementedError` bodies — to be
/// backed natively in phase 2 (VisionKit / Vision on iOS, ML Kit on Android).
///
/// This package depends on no other kit (not `arxa_kit`, `stacked`, or
/// `stacked_services`) — pure ports over native plugins.
library;

// Working path
export 'src/arxa_kit_picked_document.dart';
export 'src/arxa_kit_document_picker_service.dart';

// Stub ports (phase 2)
export 'src/arxa_kit_document_scan_service.dart';
export 'src/arxa_kit_ocr_service.dart';
export 'src/arxa_kit_pdf_service.dart';

// PDF rendering (pdfrx / PDFium — all platforms incl. web)
export 'src/arxa_kit_pdfrx_pdf_service.dart';

// Interactive PDF viewing (pdfrx PdfViewer)
export 'src/arxa_kit_pdf_viewer.dart';
