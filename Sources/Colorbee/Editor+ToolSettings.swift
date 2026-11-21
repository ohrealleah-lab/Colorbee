import ColorbeeCore

extension Editor {
    /// Every carried tool setting at once (stage 34c). Reading it observes each one, so `ToolSettingsStore` hears of
    /// any change.
    var toolSettings: ToolSettings {
        get {
            ToolSettings(
                color1: color1, color2: color2, brush: brush, usesPressure: usesPressure, brushDiameter: brushDiameter,
                eraserSize: eraserSize, colorEraserTolerance: colorEraserTolerance, colorEraserMode: colorEraserMode,
                fillTolerance: fillTolerance, fillSamplesAllLayers: fillSamplesAllLayers, wandTolerance: wandTolerance,
                wandContiguous: wandContiguous, wandMode: wandMode, wandSamplesAllLayers: wandSamplesAllLayers,
                transparentSelection: transparentSelection, smoothResize: smoothResize, shapeKind: shapeKind,
                shapeLineWidth: shapeLineWidth, shapeOutline: shapeOutline, shapeFill: shapeFill, textStyle: textStyle,
                badgeStyle: badgeStyle, badgeDiameter: badgeDiameter, gradientMode: gradientMode,
                redactTreatment: redactTreatment, redactBrushSize: redactBrushSize, retouchKind: retouchKind,
                retouchSizes: retouchSizes, retouchSamplesAllLayers: retouchSamplesAllLayers,
                retouchStrength: retouchStrength, retouchHardness: retouchHardness, toneRange: toneRange,
                cloneAligned: cloneAligned, cloneMatchesTone: cloneMatchesTone, eyedropperSampleSize: eyedropperSampleSize
            )
        }
        set {
            color1 = newValue.color1
            color2 = newValue.color2
            brush = newValue.brush
            usesPressure = newValue.usesPressure
            brushDiameter = newValue.brushDiameter
            eraserSize = newValue.eraserSize
            colorEraserTolerance = newValue.colorEraserTolerance
            colorEraserMode = newValue.colorEraserMode
            fillTolerance = newValue.fillTolerance
            fillSamplesAllLayers = newValue.fillSamplesAllLayers
            wandTolerance = newValue.wandTolerance
            wandContiguous = newValue.wandContiguous
            wandMode = newValue.wandMode
            wandSamplesAllLayers = newValue.wandSamplesAllLayers
            transparentSelection = newValue.transparentSelection
            smoothResize = newValue.smoothResize
            shapeKind = newValue.shapeKind
            shapeLineWidth = newValue.shapeLineWidth
            shapeOutline = newValue.shapeOutline
            shapeFill = newValue.shapeFill
            textStyle = newValue.textStyle
            badgeStyle = newValue.badgeStyle
            badgeDiameter = newValue.badgeDiameter
            gradientMode = newValue.gradientMode
            redactTreatment = newValue.redactTreatment
            redactBrushSize = newValue.redactBrushSize
            retouchKind = newValue.retouchKind
            retouchSizes = newValue.retouchSizes
            retouchSamplesAllLayers = newValue.retouchSamplesAllLayers
            retouchStrength = newValue.retouchStrength
            retouchHardness = newValue.retouchHardness
            toneRange = newValue.toneRange
            cloneAligned = newValue.cloneAligned
            cloneMatchesTone = newValue.cloneMatchesTone
            eyedropperSampleSize = newValue.eyedropperSampleSize
        }
    }
}
