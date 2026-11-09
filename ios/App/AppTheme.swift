import UIKit

/// White + aqua look for the main app, matching the SayKey icon.
/// The keyboard extension keeps its own `Lab` colors.
enum Theme {
    static let aqua = UIColor(red: 0.055, green: 0.647, blue: 0.776, alpha: 1)       // #0EA5C6
    static let aquaLight = UIColor(red: 0.133, green: 0.761, blue: 0.867, alpha: 1)  // #22C2DD
    static let aquaDeep = UIColor(red: 0.055, green: 0.455, blue: 0.565, alpha: 1)   // #0E7490
    static let aquaTint = UIColor(red: 0.902, green: 0.973, blue: 0.984, alpha: 1)   // #E6F8FB
    static let ink = UIColor(red: 0.059, green: 0.090, blue: 0.165, alpha: 1)        // #0F172A
    static let muted = UIColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1)      // #64748B
    static let field = UIColor(red: 0.957, green: 0.984, blue: 0.988, alpha: 1)      // #F4FBFC
    static let fieldBorder = UIColor(red: 0.812, green: 0.937, blue: 0.961, alpha: 1)// #CFEFF5

    static func label(_ text: String, size: CGFloat = 16, color: UIColor = ink) -> UILabel {
        Lab.label(text, size: size, color: color)
    }

    static func button(_ title: String, symbol: String? = nil, primary: Bool = false,
                       action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = primary ? aqua : aquaTint
        config.baseForegroundColor = primary ? .white : aquaDeep
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 16, weight: .semibold)
            return attributes
        }
        if let symbol = symbol { config.image = UIImage(systemName: symbol); config.imagePadding = 8 }
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        return button
    }

    static func primaryButton(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> UIButton {
        button(title, symbol: symbol, primary: true, action: action)
    }

    /// Header with the app icon, name and version badge.
    static func header(version: String) -> UIView {
        let icon = UIImageView(image: UIImage(named: "SayKeyLogo"))
        icon.contentMode = .scaleAspectFill
        icon.layer.cornerRadius = 15; icon.layer.cornerCurve = .continuous; icon.clipsToBounds = true
        let iconWrap = UIView()
        iconWrap.layer.shadowColor = aqua.cgColor; iconWrap.layer.shadowOpacity = 0.25
        iconWrap.layer.shadowRadius = 8; iconWrap.layer.shadowOffset = CGSize(width: 0, height: 4)
        iconWrap.addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 64), iconWrap.heightAnchor.constraint(equalToConstant: 64),
            icon.leadingAnchor.constraint(equalTo: iconWrap.leadingAnchor), icon.trailingAnchor.constraint(equalTo: iconWrap.trailingAnchor),
            icon.topAnchor.constraint(equalTo: iconWrap.topAnchor), icon.bottomAnchor.constraint(equalTo: iconWrap.bottomAnchor)
        ])
        let name = label("SayKey Lab", size: 26)
        name.font = .systemFont(ofSize: 26, weight: .bold)
        let badge = PaddedLabel()
        badge.text = "v\(version) · 内测版"
        badge.font = .systemFont(ofSize: 13, weight: .medium)
        badge.textColor = aquaDeep
        badge.backgroundColor = UIColor(red: 0.812, green: 0.957, blue: 0.980, alpha: 1)
        badge.layer.cornerRadius = 10; badge.clipsToBounds = true
        let badgeRow = UIStackView(arrangedSubviews: [badge, UIView()])
        let text = UIStackView(arrangedSubviews: [name, badgeRow])
        text.axis = .vertical; text.spacing = 4
        let row = UIStackView(arrangedSubviews: [iconWrap, text])
        row.axis = .horizontal; row.spacing = 14; row.alignment = .center
        return row
    }

    static func slogan(_ text: String) -> UILabel {
        let slogan = label(text, size: 28, color: aqua)
        slogan.font = .systemFont(ofSize: 28, weight: .heavy)
        return slogan
    }

    /// Adds a white rounded card with a numbered heading to `parent` and returns
    /// the card's inner stack so callers can append rows to it.
    static func section(_ number: Int, _ title: String, in parent: UIStackView) -> UIStackView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 20; card.layer.cornerCurve = .continuous
        card.layer.shadowColor = aqua.cgColor; card.layer.shadowOpacity = 0.10
        card.layer.shadowRadius = 10; card.layer.shadowOffset = CGSize(width: 0, height: 2)
        let badge = GradientView(colors: [UIColor(red: 0.357, green: 0.890, blue: 0.961, alpha: 1), aqua], horizontal: false)
        badge.layer.cornerRadius = 13; badge.clipsToBounds = true
        let digit = label("\(number)", size: 14, color: .white)
        digit.font = .systemFont(ofSize: 14, weight: .bold); digit.textAlignment = .center
        badge.addSubview(digit)
        digit.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 26), badge.heightAnchor.constraint(equalToConstant: 26),
            digit.centerXAnchor.constraint(equalTo: badge.centerXAnchor), digit.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        let heading = label(title, size: 19)
        heading.font = .systemFont(ofSize: 19, weight: .bold)
        let headRow = UIStackView(arrangedSubviews: [badge, heading])
        headRow.axis = .horizontal; headRow.spacing = 10; headRow.alignment = .center
        let inner = UIStackView(arrangedSubviews: [headRow])
        inner.axis = .vertical; inner.spacing = 12
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        parent.addArrangedSubview(card)
        return inner
    }

    static func style(_ field: UITextField) {
        field.borderStyle = .none
        field.backgroundColor = Theme.field
        field.textColor = ink
        field.layer.cornerRadius = 12; field.layer.borderWidth = 1.5
        field.layer.borderColor = fieldBorder.cgColor
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1)); field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1)); field.rightViewMode = .always
    }

    static func style(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = .white
        control.backgroundColor = UIColor(red: 0.933, green: 0.957, blue: 0.965, alpha: 1)
        control.setTitleTextAttributes([.foregroundColor: muted], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: aquaDeep, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
    }

    /// Soft white-to-aqua background with faint sound-wave arcs, like the icon.
    static func installBackground(in view: UIView) {
        let background = WaveBackgroundView()
        background.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(background, at: 0)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: view.topAnchor), background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor), background.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        view.backgroundColor = .white
    }
}

final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    init(colors: [UIColor], horizontal: Bool) {
        super.init(frame: .zero)
        let layer = self.layer as! CAGradientLayer
        layer.colors = colors.map(\.cgColor)
        layer.startPoint = horizontal ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0, y: 0)
        layer.endPoint = horizontal ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 1, y: 1)
    }
    required init?(coder: NSCoder) { nil }
}

final class PaddedLabel: UILabel {
    private let inset = UIEdgeInsets(top: 2, left: 9, bottom: 2, right: 9)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + inset.left + inset.right, height: size.height + inset.top + inset.bottom)
    }
}

final class WaveBackgroundView: UIView {
    private let gradient = CAGradientLayer()
    private let waves = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.colors = [UIColor.white.cgColor,
                           UIColor(red: 0.933, green: 0.984, blue: 0.992, alpha: 1).cgColor,
                           UIColor(red: 0.867, green: 0.961, blue: 0.980, alpha: 1).cgColor]
        gradient.locations = [0, 0.45, 1]
        layer.addSublayer(gradient)
        waves.fillColor = UIColor.clear.cgColor
        waves.strokeColor = Theme.aqua.withAlphaComponent(0.10).cgColor
        waves.lineWidth = 14; waves.lineCap = .round
        layer.addSublayer(waves)
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        let center = CGPoint(x: bounds.maxX - 150, y: 190)
        let path = UIBezierPath()
        for radius in [60.0, 120.0, 180.0] {
            path.move(to: CGPoint(x: center.x + radius * cos(-.pi / 4), y: center.y + radius * sin(-.pi / 4)))
            path.addArc(withCenter: center, radius: radius, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: true)
        }
        waves.path = path.cgPath
    }
}
