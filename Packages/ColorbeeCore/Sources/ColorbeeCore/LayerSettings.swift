import Foundation

/// Every setting a layer has besides its id, its kind, its pixels and its mask. Undo, Undo on Active Layer, History
/// Snapshots and copies carry a layer's settings as one of these, so a new setting added here (and to
/// `Layer.settings`) reaches all of them. The project file spells its fields out on its own: it's the file format.
public struct LayerSettings: Equatable {
    public var name: String
    public var nameFromWords = false
    public var isVisible = true
    public var opacity = 1.0
    public var blendMode = BlendMode.normal
    public var isLocked = false
    public var locksTransparency = false
    public var adjustment: Effect?
    public var clipsToLayerBelow = false
    public var groupID: LayerID?
    public var passesThrough = true
    public var maskEnabled = true
    public var text: TextLayer?

    public init(name: String) {
        self.name = name
    }
}

extension Layer {
    public var settings: LayerSettings {
        get {
            var settings = LayerSettings(name: name)
            settings.nameFromWords = nameFromWords
            settings.isVisible = isVisible
            settings.opacity = opacity
            settings.blendMode = blendMode
            settings.isLocked = isLocked
            settings.locksTransparency = locksTransparency
            settings.adjustment = adjustment
            settings.clipsToLayerBelow = clipsToLayerBelow
            settings.groupID = groupID
            settings.passesThrough = passesThrough
            settings.maskEnabled = maskEnabled
            settings.text = text
            return settings
        }
        set {
            // Any rename clears `nameFromWords`, so the name goes first.
            name = newValue.name
            nameFromWords = newValue.nameFromWords
            isVisible = newValue.isVisible
            opacity = newValue.opacity
            blendMode = newValue.blendMode
            isLocked = newValue.isLocked
            locksTransparency = newValue.locksTransparency
            adjustment = newValue.adjustment
            clipsToLayerBelow = newValue.clipsToLayerBelow
            groupID = newValue.groupID
            passesThrough = newValue.passesThrough
            maskEnabled = newValue.maskEnabled
            text = newValue.text
        }
    }
}
