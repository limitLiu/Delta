//
//  ExperimentalFeatureView.swift
//  Delta
//
//  Created by Riley Testut on 4/10/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI

import DeltaFeatures

struct ExperimentalFeatureView<Feature: AnyFeature>: View
{
    @ObservedObject
    var feature: Feature
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $feature.isEnabled.animation()) {
                    Text(feature.name)
                        .bold()
                }
            } footer: {
                if let description = feature.description
                {
                    Text(description)
                }
            }
            
            if feature.isEnabled
            {
                ForEach(feature.allOptions, id: \.key) { option in
                    if let optionView = optionView(option)
                    {
                        Section {
                            optionView
                        } footer: {
                            if let description = option.description
                            {
                                Text(description)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Cannot open existential if return type uses concrete type T in non-covariant position (e.g. Box<T>).
    // So instead we erase return type to AnyView.
    private func optionView<T: AnyOption>(_ option: T) -> AnyView?
    {
        guard let view = OptionRow(option: option) else { return nil }
        return AnyView(view)
    }
}

private struct OptionRow<Option: AnyOption, DetailView: View>: View where DetailView == Option.DetailView
{
    var name: LocalizedStringKey
    var value: any LocalizedOptionValue
    var detailView: DetailView
    
    @State
    private var displayInline: Bool = false
    
    init?(option: Option)
    {
        // Only show if option has a name, localizable value, and detailView.
        guard
            let name = option.name,
            let value = option.value as? any LocalizedOptionValue,
            let detailView = option.detailView()
        else { return nil }
        
        self.name = name
        self.value = value
        self.detailView = detailView
    }
    
    var body: some View {
        VStack {
            if displayInline
            {
                // Display entire view inline.
                detailView
            }
            else
            {
                let wrappedDetailView = Form {
                    detailView
                }

                NavigationLink(destination: wrappedDetailView) {
                    HStack {
                        Text(name)
                        Spacer()

                        value.localizedDescription
                            .foregroundColor(.secondary)
                    }
                }
                .overlay(
                    detailView
                        .hidden()
                        .frame(width: 0, height: 0)
                )
            }
        }
        .onPreferenceChange(DisplayInlineKey.self) { displayInline in
            self.displayInline = displayInline
        }
    }
}

struct ExperimentalFeatureView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExperimentalFeatureView(feature: ExperimentalFeatures.shared.variableFastForward)
        }
    }
}
