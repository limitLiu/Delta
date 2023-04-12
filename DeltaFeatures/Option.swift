//
//  Option.swift
//  Delta
//
//  Created by Riley Testut on 4/7/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI
import Combine

public protocol AnyOption<Value>: AnyObject, Identifiable
{
    associatedtype Value: OptionValue
    associatedtype DetailView: View
    
    var name: LocalizedStringKey? { get }
    var key: String { get }
    var description: LocalizedStringKey? { get }
    
    var values: [Value]? { get }
    var detailView: () -> DetailView? { get }
    
    // TODO: Remove below
    var wrappedValue: Value { get }
}

extension AnyOption
{
    public var id: String { self.key }
}

// Don't expose `feature` property via AnyOption protocol.
internal protocol _AnyOption: AnyOption
{
    var key: String { get set }
    var feature: AnyFeature? { get set }
}

@propertyWrapper
public class Option<Value: OptionValue, DetailView: View>: _AnyOption
{
    // Nil name == hidden option.
    public let name: LocalizedStringKey?
    public let description: LocalizedStringKey?
    
    public let values: [Value]?
    public private(set) var detailView: () -> DetailView? = { nil }
    
    public internal(set) var key: String = ""
    internal weak var feature: AnyFeature?
    
    private let defaultValue: Value
    
    // Used for `NotificationUserInfoKey.name` value in .settingsDidChange notification.
    public var settingsKey: Settings.Name {
        guard let feature = self.feature else { return Settings.Name(rawValue: self.key) }
        
        let defaultsKey = feature.key + "_" + self.key
        return Settings.Name(rawValue: defaultsKey)
    }
    
    // Must be property in order for UI to update automatically.
    private var valueBinding: Binding<Value> {
        Binding(get: {
            self.wrappedValue
        }, set: {
            self.wrappedValue = $0
        })
    }
    
    /// @propertyWrapper
    public var projectedValue: Option<Value, DetailView> { self }
    
    public var wrappedValue: Value {
        get {
            do {
                let wrappedValue = try UserDefaults.standard.optionValue(forKey: self.settingsKey.rawValue, type: Value.self)
                return wrappedValue ?? self.defaultValue
            }
            catch {
                print("[ALTLog] Failed to read option value for key \(self.settingsKey.rawValue).", error)
                return self.defaultValue
            }
        }
        set {
            Task { @MainActor in
                // Delay to avoid "Publishing changes from within view updates is not allowed" runtime warning.
                self.feature?.objectWillChange.send()
            }
            
            do {
                try UserDefaults.standard.setOptionValue(newValue, forKey: self.settingsKey.rawValue)
                NotificationCenter.default.post(name: .settingsDidChange, object: nil, userInfo: [Settings.NotificationUserInfoKey.name: self.settingsKey, Settings.NotificationUserInfoKey.value: newValue])
            }
            catch {
                print("[ALTLog] Failed to set option value for key \(self.settingsKey.rawValue).", error)
            }
        }
    }
    
    private init(defaultValue: Value, name: LocalizedStringKey?, description: LocalizedStringKey?, values: [Value]?)
    {
        self.defaultValue = defaultValue
        
        self.name = name
        self.description = description
        self.values = values
        self.detailView = { nil }
    }
}

// Basic Option (no pre-set values or custom SwiftUI view)
public extension Option where DetailView == EmptyView
{
    // Non-optional property
    convenience init(wrappedValue: Value)
    {
        self.init(defaultValue: wrappedValue, name: nil, description: nil, values: nil)
    }
    
    // Optional Value, default = nil
    convenience init() where Value: OptionalProtocol
    {
        self.init(defaultValue: Value.none, name: nil, description: nil, values: nil)
    }
    
    // Optional Value, default = non-nil
    convenience init(wrappedValue: Value) where Value: OptionalProtocol
    {
        self.init(defaultValue: wrappedValue, name: nil, description: nil, values: nil)
    }
}

// "Toggle" Option (Bool properties with default Toggle UI)
public extension Option where Value == Bool, DetailView == OptionToggleView
{
    // Non-Optional
    convenience init(wrappedValue: Value, name: LocalizedStringKey, description: LocalizedStringKey? = nil)
    {
        self.init(defaultValue: wrappedValue, name: name, description: description, values: nil)
        
        self.detailView = { [weak self] () -> DetailView? in
            guard let self else { return nil }
            return OptionToggleView(name: name, selectedValue: self.valueBinding)
        }
    }
}

// "Picker" Options (pre-set options with default picker UI)
public extension Option where Value: LocalizedOptionValue, DetailView == OptionPickerView<Value>
{
    // Non-Optional Value
    convenience init(wrappedValue: Value, name: LocalizedStringKey, description: LocalizedStringKey? = nil, values: some Collection<Value>)
    {
        let values = Array(values)
        self.init(defaultValue: wrappedValue, name: name, description: description, values: values)
        
        self.detailView = { [weak self] () -> DetailView? in
            guard let self else { return nil }
            return OptionPickerView(name: name, options: values, selectedValue: self.valueBinding)
        }
    }
    
    // Optional Value, default = nil
    convenience init(name: LocalizedStringKey, description: LocalizedStringKey? = nil, values: some Collection<Value>) where Value: OptionalProtocol, Value.Wrapped: LocalizedOptionValue
    {
        let values = Array(values)
        self.init(defaultValue: Value.none, name: name, description: description, values: values)
        
        self.detailView = { [weak self] () -> DetailView? in
            guard let self else { return nil }
            return OptionPickerView(name: name, options: values.appendingNil(), selectedValue: self.valueBinding)
        }
    }
    
    // Optional Value, default = non-nil
    convenience init(wrappedValue: Value, name: LocalizedStringKey, description: LocalizedStringKey? = nil, values: some Collection<Value>) where Value: OptionalProtocol, Value.Wrapped: LocalizedOptionValue
    {
        let values = Array(values)
        self.init(defaultValue: wrappedValue, name: name, description: description, values: values)
        
        self.detailView = { [weak self] () -> DetailView? in
            guard let self else { return nil }
            return OptionPickerView(name: name, options: values.appendingNil(), selectedValue: self.valueBinding)
        }
    }
}

// "Custom SwiftUI" Options (provide custom SwiftUI views to configure option)
public extension Option where Value: LocalizedOptionValue
{
    // Non-Optional Value
    convenience init(wrappedValue: Value, name: LocalizedStringKey, description: LocalizedStringKey? = nil, @ViewBuilder detailView: @escaping (Binding<Value>) -> DetailView)
    {
        self.init(defaultValue: wrappedValue, name: name, description: description, values: nil)
        
        self.detailView = { [weak self] in
            guard let self else { return nil }
            
            let view = detailView(self.valueBinding)
            return view
        }
    }
    
    // Optional Value, default = nil
    convenience init(name: LocalizedStringKey, description: LocalizedStringKey? = nil, @ViewBuilder detailView: @escaping (Binding<Value>) -> DetailView) where Value: OptionalProtocol, Value.Wrapped: LocalizedOptionValue
    {
        self.init(defaultValue: Value.none, name: name, description: description, values: nil)
        
        self.detailView = { [weak self] in
            guard let self else { return nil }
            
            let view = detailView(self.valueBinding)
            return view
        }
    }
    
    // Optional Value, default = non-nil
    convenience init(wrappedValue: Value, name: LocalizedStringKey, description: LocalizedStringKey? = nil, @ViewBuilder detailView: @escaping (Binding<Value>) -> DetailView) where Value: OptionalProtocol, Value.Wrapped: LocalizedOptionValue
    {
        self.init(defaultValue: wrappedValue, name: name, description: description, values: nil)
        
        self.detailView = { [weak self] in
            guard let self else { return nil }
            
            let view = detailView(self.valueBinding)
            return view
        }
    }
}