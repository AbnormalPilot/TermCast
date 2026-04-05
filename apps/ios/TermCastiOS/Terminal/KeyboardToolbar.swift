// apps/ios/TermCastiOS/Terminal/KeyboardToolbar.swift
import UIKit
import SwiftUI

final class KeyboardToolbarView: UIView {
    private weak var coordinator: TerminalView.Coordinator?
    private var ctrlPending = false

    init(coordinator: TerminalView.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        backgroundColor = UIColor.systemGray6
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        let buttons: [(String, Selector)] = [
            ("Ctrl", #selector(ctrl)),
            ("Esc",  #selector(esc)),
            ("Tab",  #selector(tab)),
            ("↑",    #selector(arrowUp)),
            ("↓",    #selector(arrowDown)),
            ("←",    #selector(arrowLeft)),
            ("→",    #selector(arrowRight)),
        ]

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        for (title, action) in buttons {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            btn.backgroundColor = .systemBackground
            btn.layer.cornerRadius = 6
            btn.addTarget(self, action: action, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
    }

    @objc private func ctrl() {
        ctrlPending = true
    }

    @objc private func esc()        { send(InputHandler.encode(special: .escape)) }
    @objc private func tab()        { send(InputHandler.encode(special: .tab)) }
    @objc private func arrowUp()    { send(InputHandler.encode(special: .arrowUp)) }
    @objc private func arrowDown()  { send(InputHandler.encode(special: .arrowDown)) }
    @objc private func arrowLeft()  { send(InputHandler.encode(special: .arrowLeft)) }
    @objc private func arrowRight() { send(InputHandler.encode(special: .arrowRight)) }

    private func send(_ data: Data) { coordinator?.send(data) }

    func handleKey(_ char: Character) -> Bool {
        guard ctrlPending else { return false }
        ctrlPending = false
        send(InputHandler.encode(ctrl: char))
        return true
    }
}
