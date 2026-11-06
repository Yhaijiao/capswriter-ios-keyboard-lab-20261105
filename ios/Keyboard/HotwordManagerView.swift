import UIKit

/// File selection and browsing stay inside the extension. Editing uses the
/// keyboard's own text target, never the host document.
final class HotwordManagerView: UIView {
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?
    var onReload: (() -> Void)?
    var onEdit: ((HotwordFile) -> Void)?
    private let picker = Lab.button("正在读取词库…", symbol: "chevron.down") {}
    private let note = Lab.label("", size: 12, color: Lab.muted)
    private let text = UITextView()
    private let edit = Lab.button("编辑 hot.txt", symbol: "square.and.pencil") {}
    private var files: [HotwordFile] = []
    private var selectedID = "hot"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Lab.background
        accessibilityViewIsModal = true
        accessibilityIdentifier = "hotword-manager"
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
        let title = Lab.label("热词", size: 18); title.font = .boldSystemFont(ofSize: 18)
        let settings = compactButton("", symbol: "gearshape") { [weak self] in self?.onSettings?() }
        settings.accessibilityLabel = "连接设置"
        settings.accessibilityIdentifier = "hotword-connection-settings"
        let close = compactButton("关闭") { [weak self] in self?.onClose?() }
        close.accessibilityIdentifier = "hotword-manager-close"
        let header = UIStackView(arrangedSubviews: [title, UIView(), settings, close]); header.spacing = 6
        header.heightAnchor.constraint(equalToConstant: 30).isActive = true
        settings.widthAnchor.constraint(equalToConstant: 36).isActive = true
        close.widthAnchor.constraint(equalToConstant: 55).isActive = true
        stack.addArrangedSubview(header)
        picker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        picker.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
        picker.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var output = input; output.font = .systemFont(ofSize: 14); return output
        }
        picker.showsMenuAsPrimaryAction = true; picker.isEnabled = false
        picker.accessibilityIdentifier = "hotword-file-picker"
        stack.addArrangedSubview(picker)
        note.numberOfLines = 2
        note.heightAnchor.constraint(equalToConstant: 30).isActive = true
        note.accessibilityIdentifier = "hotword-manager-status"
        stack.addArrangedSubview(note)
        text.isEditable = false; text.isSelectable = true
        text.backgroundColor = Lab.surface; text.textColor = .white
        text.font = .systemFont(ofSize: 14)
        text.layer.cornerRadius = 10
        text.textContainerInset = UIEdgeInsets(top: 8, left: 7, bottom: 8, right: 7)
        text.accessibilityIdentifier = "hotword-file-content"
        stack.addArrangedSubview(text)
        let reload = compactButton("重新加载", symbol: "arrow.clockwise") { [weak self] in self?.onReload?() }
        reload.accessibilityIdentifier = "hotword-manager-reload"
        edit.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
        edit.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var output = input; output.font = .systemFont(ofSize: 14); return output
        }
        edit.addAction(UIAction { [weak self] _ in
            guard let self = self, let file = self.files.first(where: { $0.id == self.selectedID }), file.writable else { return }
            self.onEdit?(file)
        }, for: .touchUpInside)
        edit.isEnabled = false; edit.accessibilityIdentifier = "hotword-edit"
        let actions = UIStackView(arrangedSubviews: [reload, edit]); actions.spacing = 6; actions.distribution = .fillEqually
        actions.heightAnchor.constraint(equalToConstant: 32).isActive = true
        stack.addArrangedSubview(actions)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(files: [HotwordFile], selectedID: String = "hot", message: String? = nil) {
        self.files = files
        self.selectedID = files.contains(where: { $0.id == selectedID }) ? selectedID : (files.first?.id ?? "hot")
        picker.menu = UIMenu(children: files.map { file in
            UIAction(title: file.name, state: file.id == self.selectedID ? .on : .off) { [weak self] _ in
                guard let self = self else { return }; self.show(files: self.files, selectedID: file.id)
            }
        })
        picker.isEnabled = !files.isEmpty
        guard let file = files.first(where: { $0.id == self.selectedID }) else {
            showError("服务未返回热词文件，请升级电脑桥接后重试。"); return
        }
        picker.configuration?.title = file.name
        text.text = file.text; text.setContentOffset(.zero, animated: false)
        edit.isEnabled = file.writable
        edit.configuration?.title = file.writable ? "编辑 " + file.name : "当前文件只读"
        let readOnly = file.id == "hot" ? "电脑端尚未启用手机写回，当前可查看词库。" : "此文件只读。个人词条可在 hot.txt 中添加。"
        note.text = message ?? (file.writable ? "每行一个词，或：正确词 | 误识别。\n保存后更新电脑热词，下次识别生效。" : readOnly)
    }

    func showLoading() {
        files = []; picker.menu = nil; picker.isEnabled = false; edit.isEnabled = false
        picker.configuration?.title = "正在读取词库…"
        text.text = ""; note.text = "正在连接已配对的识别服务…"
    }

    func showError(_ message: String) {
        files = []; picker.menu = nil; picker.isEnabled = false; edit.isEnabled = false
        picker.configuration?.title = "读取失败"
        text.text = message
        note.text = "检查右上角连接设置，或点击重新加载。"
    }

    private func compactButton(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> UIButton {
        let button = Lab.button(title, symbol: symbol, action: action)
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var output = input; output.font = .systemFont(ofSize: 14); return output
        }
        return button
    }
}
