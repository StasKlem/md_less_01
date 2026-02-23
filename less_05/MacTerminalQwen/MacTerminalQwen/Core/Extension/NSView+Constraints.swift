//
//  NSView+Constraints.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Extension для упрощения работы с Auto Layout программно.
extension NSView {
    
    // MARK: - Anchor Helpers
    
    /// Активировать ограничения для привязки к супервью
    @discardableResult
    func anchor(
        top: NSLayoutYAxisAnchor? = nil,
        leading: NSLayoutXAxisAnchor? = nil,
        bottom: NSLayoutYAxisAnchor? = nil,
        trailing: NSLayoutXAxisAnchor? = nil,
        padding: CGFloat = 0,
        size: CGSize? = nil
    ) -> [NSLayoutConstraint] {
        
        translatesAutoresizingMaskIntoConstraints = false
        
        var constraints: [NSLayoutConstraint] = []
        
        if let top = top {
            constraints.append(topAnchor.constraint(equalTo: top, constant: padding))
        }
        
        if let leading = leading {
            constraints.append(leadingAnchor.constraint(equalTo: leading, constant: padding))
        }
        
        if let bottom = bottom {
            constraints.append(bottomAnchor.constraint(equalTo: bottom, constant: -padding))
        }
        
        if let trailing = trailing {
            constraints.append(trailingAnchor.constraint(equalTo: trailing, constant: -padding))
        }
        
        if let size = size {
            constraints.append(widthAnchor.constraint(equalToConstant: size.width))
            constraints.append(heightAnchor.constraint(equalToConstant: size.height))
        }
        
        NSLayoutConstraint.activate(constraints)
        return constraints
    }
    
    /// Привязать все края к супервью
    @discardableResult
    func fillSuperview(padding: CGFloat = 0) -> [NSLayoutConstraint] {
        guard let superview = superview else {
            assertionFailure("fillSuperview called but superview is nil")
            return []
        }
        return anchor(
            top: superview.topAnchor,
            leading: superview.leadingAnchor,
            bottom: superview.bottomAnchor,
            trailing: superview.trailingAnchor,
            padding: padding
        )
    }
    
    /// Центрировать в супервью с опциональным размером
    @discardableResult
    func centerInSuperview(size: CGSize? = nil) -> [NSLayoutConstraint] {
        guard let superview = superview else {
            assertionFailure("centerInSuperview called but superview is nil")
            return []
        }
        
        translatesAutoresizingMaskIntoConstraints = false
        
        var constraints: [NSLayoutConstraint] = [
            centerXAnchor.constraint(equalTo: superview.centerXAnchor),
            centerYAnchor.constraint(equalTo: superview.centerYAnchor)
        ]
        
        if let size = size {
            constraints.append(widthAnchor.constraint(equalToConstant: size.width))
            constraints.append(heightAnchor.constraint(equalToConstant: size.height))
        }
        
        NSLayoutConstraint.activate(constraints)
        return constraints
    }
}

// MARK: - NSLayoutConstraint Helpers

/// Создать ограничение с приоритетом
func constraint(
    _ item1: Any,
    attribute1: NSLayoutConstraint.Attribute,
    relatedBy: NSLayoutConstraint.Relation = .equal,
    to item2: Any? = nil,
    attribute2: NSLayoutConstraint.Attribute? = nil,
    constant: CGFloat = 0,
    priority: NSLayoutConstraint.Priority = .required
) -> NSLayoutConstraint {
    
    let constraint = NSLayoutConstraint(
        item: item1,
        attribute: attribute1,
        relatedBy: relatedBy,
        toItem: item2,
        attribute: attribute2 ?? .notAnAttribute,
        multiplier: 1.0,
        constant: constant
    )
    constraint.priority = priority
    return constraint
}

// MARK: - NSView Factory Helpers

extension NSView {
    /// Создать spacer с фиксированной шириной
    static func spacer(width: CGFloat = 0, height: CGFloat = 0) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        if width > 0 {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        if height > 0 {
            view.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
        return view
    }
    
    /// Создать горизонтальный divider
    static func horizontalDivider(color: NSColor = .separatorColor, height: CGFloat = 1) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
    
    /// Создать вертикальный divider
    static func verticalDivider(color: NSColor = .separatorColor, width: CGFloat = 1) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }
}
