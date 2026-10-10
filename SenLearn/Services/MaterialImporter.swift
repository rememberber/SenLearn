import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Decodes one page at a time so large camera images do not stay in memory together.
actor MaterialImporter {
    static let maximumFileBytes = 100 * 1_024 * 1_024
    static let maximumPDFPages = 100
    static let maximumPhotos = 30
    static let maximumImageDimension = 2_000

    enum ImportError: LocalizedError {
        case unsupportedFile
        case unreadableFile
        case fileTooLarge
        case encryptedPDF
        case emptyPDF
        case tooManyPages
        case invalidPDFPage(Int)
        case invalidImage(Int)
        case noPhotos
        case tooManyPhotos
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedFile: return "请选择 PDF、JPEG、PNG 或 HEIC 等图片文件。"
            case .unreadableFile: return "无法读取这个文件，请确认文件已下载到设备后重试。"
            case .fileTooLarge: return "材料大小不能超过 100 MB，请分批导入。"
            case .encryptedPDF: return "暂不支持加密的 PDF，请先导出不带密码的副本。"
            case .emptyPDF: return "这个 PDF 没有可阅读的页面。"
            case .tooManyPages: return "一次最多导入 100 页 PDF，请拆分后重试。"
            case .invalidPDFPage(let number): return "PDF 第 \(number) 页无法读取，请检查原文件。"
            case .invalidImage(let number): return "第 \(number) 张图片无法读取，请换一张图片重试。"
            case .noPhotos: return "请至少选择一张图片。"
            case .tooManyPhotos: return "一次最多导入 30 张图片，请分批追加。"
            case .encodingFailed: return "无法保存页面图片，请重试。"
            }
        }
    }

    func importFile(at url: URL) throws -> ImportedMaterial {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let data = try readBoundedFile(at: url)
        let title = url.deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)
        let isPDF = type?.conforms(to: .pdf) == true || data.starts(with: Data("%PDF-".utf8))
        if isPDF {
            return try importPDF(data: data, title: title)
        }
        guard type?.conforms(to: .image) == true || CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            throw ImportError.unsupportedFile
        }
        return try importPhotos([data], title: title)
    }

    func importPhotos(_ data: [Data], title: String) throws -> ImportedMaterial {
        guard !data.isEmpty else { throw ImportError.noPhotos }
        guard data.count <= Self.maximumPhotos else { throw ImportError.tooManyPhotos }
        var totalBytes = 0
        for item in data {
            guard item.count <= Self.maximumFileBytes - totalBytes else { throw ImportError.fileTooLarge }
            totalBytes += item.count
        }
        var pages: [ImportedPage] = []
        for (index, item) in data.enumerated() {
            try Task.checkCancellation()
            let page = try autoreleasepool { try makeImagePage(data: item, number: index + 1) }
            pages.append(page)
        }
        return ImportedMaterial(title: title.isEmpty ? "新阅读材料" : title, pages: pages)
    }

    private func readBoundedFile(at url: URL) throws -> Data {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile != false else { throw ImportError.unsupportedFile }
            if let size = values.fileSize, size > Self.maximumFileBytes { throw ImportError.fileTooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            while let chunk = try handle.read(upToCount: min(1_024 * 1_024, Self.maximumFileBytes - data.count + 1)), !chunk.isEmpty {
                try Task.checkCancellation()
                guard chunk.count <= Self.maximumFileBytes - data.count else { throw ImportError.fileTooLarge }
                data.append(chunk)
            }
            guard !data.isEmpty else { throw ImportError.unreadableFile }
            return data
        } catch let error as ImportError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImportError.unreadableFile
        }
    }

    private func makeImagePage(data: Data, number: Int) throws -> ImportedPage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImportError.invalidImage(number)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumImageDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width > 0, image.height > 0 else {
            throw ImportError.invalidImage(number)
        }
        // Flatten transparent pages onto white, matching the reading canvas and OCR input.
        let size = CGSize(width: image.width, height: image.height)
        let rendered = renderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return try encodedPage(rendered)
    }

    private func importPDF(data: Data, title: String) throws -> ImportedMaterial {
        guard let document = PDFDocument(data: data) else { throw ImportError.unreadableFile }
        guard !document.isEncrypted, !document.isLocked else { throw ImportError.encryptedPDF }
        guard document.pageCount > 0 else { throw ImportError.emptyPDF }
        guard document.pageCount <= Self.maximumPDFPages else { throw ImportError.tooManyPages }
        var pages: [ImportedPage] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let page = try autoreleasepool { () throws -> ImportedPage in
                guard let pdfPage = document.page(at: index), let reference = pdfPage.pageRef else {
                    throw ImportError.invalidPDFPage(index + 1)
                }
                let bounds = reference.getBoxRect(.cropBox)
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                    throw ImportError.invalidPDFPage(index + 1)
                }
                let isRotated = abs(reference.rotationAngle % 180) == 90
                let width = isRotated ? bounds.height : bounds.width
                let height = isRotated ? bounds.width : bounds.height
                let scale = CGFloat(Self.maximumImageDimension) / max(width, height)
                let size = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
                let image = renderer(size: size).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    let cg = context.cgContext
                    cg.translateBy(x: 0, y: size.height)
                    cg.scaleBy(x: 1, y: -1)
                    // CGPDFPage's transform only scales DOWN. Render in page units,
                    // then apply our pixel scale explicitly so small PDFs fill the image.
                    cg.scaleBy(x: size.width / width, y: size.height / height)
                    cg.concatenate(reference.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
                    cg.drawPDFPage(reference)
                }
                return try encodedPage(image)
            }
            pages.append(page)
        }
        return ImportedMaterial(title: title.isEmpty ? "新阅读材料" : title, pages: pages, originalData: data, originalExtension: "pdf")
    }

    private func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private func encodedPage(_ image: UIImage) throws -> ImportedPage {
        guard let data = image.jpegData(compressionQuality: 0.9), let cgImage = image.cgImage else {
            throw ImportError.encodingFailed
        }
        return ImportedPage(imageData: data, pixelWidth: cgImage.width, pixelHeight: cgImage.height)
    }
}
