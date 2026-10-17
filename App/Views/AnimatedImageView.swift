// Hiển thị ảnh tĩnh hoặc ảnh GIF động mượt mà bằng UIImageView & CGImageSource.
// Tự động phân tách frame và tính thời gian lặp để hiển thị ảnh GIF chuyển động.

import SwiftUI
import UIKit
import ImageIO

final class ImageCacheManager {
    static let shared = ImageCacheManager()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024 // 64 MB
    }

    func layAnh(url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func luuAnh(_ img: UIImage, url: URL, dungLuong: Int = 0) {
        cache.setObject(img, forKey: url as NSURL, cost: dungLuong > 0 ? dungLuong : 1024 * 1024)
    }
}

struct AnimatedImageView: UIViewRepresentable {
    let url: URL?
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var boGoc: CGFloat = 10

    func makeUIView(context: Context) -> AnimatedUIImageViewWrapper {
        let wrapper = AnimatedUIImageViewWrapper()
        wrapper.imageView.contentMode = contentMode
        wrapper.boGoc = boGoc
        return wrapper
    }

    func updateUIView(_ uiView: AnimatedUIImageViewWrapper, context: Context) {
        uiView.imageView.contentMode = contentMode
        uiView.boGoc = boGoc
        uiView.capNhat(url: url)
    }
}

final class AnimatedUIImageViewWrapper: UIView {
    let imageView = UIImageView()
    let indicator = UIActivityIndicatorView(style: .medium)
    private var currentURL: URL?
    private var currentTask: Task<Void, Never>?

    var boGoc: CGFloat = 10 {
        didSet {
            layer.cornerRadius = boGoc
            imageView.layer.cornerRadius = boGoc
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        clipsToBounds = true
        layer.cornerRadius = boGoc

        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = boGoc
        imageView.translatesAutoresizingMaskIntoConstraints = false

        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true

        addSubview(imageView)
        addSubview(indicator)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func capNhat(url: URL?) {
        guard let url = url else {
            currentTask?.cancel()
            imageView.image = nil
            currentURL = nil
            indicator.stopAnimating()
            return
        }

        if currentURL == url, imageView.image != nil {
            return
        }

        currentURL = url
        currentTask?.cancel()

        if let cached = ImageCacheManager.shared.layAnh(url: url) {
            indicator.stopAnimating()
            imageView.image = cached
            if let count = cached.images?.count, count > 1 {
                imageView.startAnimating()
            }
            return
        }

        imageView.image = nil
        indicator.startAnimating()

        currentTask = Task { [weak self, url] in
            guard let self = self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                let decoded = Self.giaiMaAnh(data: data)

                if let decoded = decoded {
                    ImageCacheManager.shared.luuAnh(decoded, url: url, dungLuong: data.count)
                }

                await MainActor.run {
                    guard self.currentURL == url else { return }
                    self.indicator.stopAnimating()
                    self.imageView.image = decoded
                    if let count = decoded?.images?.count, count > 1 {
                        self.imageView.startAnimating()
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.currentURL == url else { return }
                    self.indicator.stopAnimating()
                }
            }
        }
    }

    static func giaiMaAnh(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let soLuong = CGImageSourceGetCount(source)
        if soLuong <= 1 {
            return UIImage(data: data)
        }

        var khungHinh: [UIImage] = []
        var tongThoiGian: TimeInterval = 0

        for i in 0..<soLuong {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            khungHinh.append(UIImage(cgImage: cg))

            var doTre: Double = 0.1
            if let thuocTinh = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] {
                if let gifProp = thuocTinh[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                    if let d = gifProp[kCGImagePropertyGIFUnclampedDelayTime] as? Double, d > 0 {
                        doTre = d
                    } else if let d = gifProp[kCGImagePropertyGIFDelayTime] as? Double, d > 0 {
                        doTre = d
                    }
                }
            }
            tongThoiGian += max(doTre, 0.02)
        }

        if khungHinh.isEmpty {
            return UIImage(data: data)
        }

        return UIImage.animatedImage(with: khungHinh, duration: tongThoiGian)
    }
}
