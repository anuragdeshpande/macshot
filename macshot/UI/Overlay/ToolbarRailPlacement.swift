import AppKit

struct ToolbarRailFrames {
    let annotations: NSRect
    let options: NSRect
    let actions: NSRect

    static func place(
        around selection: NSRect,
        inside bounds: NSRect,
        annotationSize: NSSize,
        optionsSize: NSSize,
        actionSize: NSSize,
        margin: CGFloat = 4,
        gap: CGFloat = 6
    ) -> ToolbarRailFrames {
        func clampedOrigin(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            max(lower, min(value, max(lower, upper)))
        }

        func xOrigin(for width: CGFloat, proposed: CGFloat) -> CGFloat {
            clampedOrigin(
                proposed,
                lower: bounds.minX + margin,
                upper: bounds.maxX - width - margin)
        }

        func yOrigin(for height: CGFloat, proposed: CGFloat) -> CGFloat {
            clampedOrigin(
                proposed,
                lower: bounds.minY + margin,
                upper: bounds.maxY - height - margin)
        }

        let groupWidth = optionsSize.width + (optionsSize.width > 0 ? gap : 0) + annotationSize.width
        let groupLeft = xOrigin(
            for: groupWidth,
            proposed: selection.minX - groupWidth - gap)
        let optionsX = groupLeft
        let annotationX = groupLeft + optionsSize.width + (optionsSize.width > 0 ? gap : 0)
        let annotationY = yOrigin(
            for: annotationSize.height,
            proposed: selection.midY - annotationSize.height / 2)
        let annotationFrame = NSRect(origin: NSPoint(x: annotationX, y: annotationY), size: annotationSize)

        let optionsY = yOrigin(
            for: optionsSize.height,
            proposed: annotationFrame.midY - optionsSize.height / 2)
        let optionsFrame = NSRect(origin: NSPoint(x: optionsX, y: optionsY), size: optionsSize)

        let actionX = xOrigin(
            for: actionSize.width,
            proposed: selection.maxX + gap)
        let actionY = yOrigin(
            for: actionSize.height,
            proposed: selection.midY - actionSize.height / 2)
        let actionFrame = NSRect(origin: NSPoint(x: actionX, y: actionY), size: actionSize)

        return ToolbarRailFrames(annotations: annotationFrame, options: optionsFrame, actions: actionFrame)
    }

    static func place(
        around selection: NSRect,
        on displays: [NSRect],
        annotationSize: NSSize,
        optionsSize: NSSize,
        actionSize: NSSize,
        margin: CGFloat = 4,
        gap: CGFloat = 6
    ) -> ToolbarRailFrames {
        precondition(!displays.isEmpty, "Toolbar placement requires at least one display.")

        func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
            let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
            let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
            return dx * dx + dy * dy
        }

        func displayIndex(nearest edgeX: CGFloat, onLeadingSide: Bool) -> Int {
            let edgePoint = NSPoint(x: edgeX, y: selection.midY)
            let width = onLeadingSide
                ? annotationSize.width + optionsSize.width + (optionsSize.width > 0 ? gap : 0)
                : actionSize.width
            let height = onLeadingSide ? max(annotationSize.height, optionsSize.height) : actionSize.height
            let fitting = displays.indices.filter {
                displays[$0].width >= width + 2 * margin && displays[$0].height >= height + 2 * margin
            }
            let available = fitting.isEmpty ? Array(displays.indices) : fitting
            let intersectingIndices = available.filter { displays[$0].intersects(selection) }
            let candidates = intersectingIndices.isEmpty ? available : intersectingIndices
            var bestIndex = candidates[0]

            func directionalPenalty(for display: NSRect) -> CGFloat {
                if onLeadingSide {
                    return max(0, display.maxX - edgeX)
                }
                return max(0, edgeX - display.minX)
            }

            for index in candidates.dropFirst() {
                let candidateDistance = distanceSquared(from: edgePoint, to: displays[index])
                let bestDistance = distanceSquared(from: edgePoint, to: displays[bestIndex])
                if candidateDistance < bestDistance {
                    bestIndex = index
                } else if candidateDistance == bestDistance {
                    let candidatePenalty = directionalPenalty(for: displays[index])
                    let bestPenalty = directionalPenalty(for: displays[bestIndex])
                    if candidatePenalty < bestPenalty {
                        bestIndex = index
                    }
                }
            }

            return bestIndex
        }

        func leadingFrames(on display: NSRect) -> ToolbarRailFrames {
            place(
                around: selection,
                inside: display,
                annotationSize: annotationSize,
                optionsSize: optionsSize,
                actionSize: .zero,
                margin: margin,
                gap: gap)
        }

        func trailingFrames(on display: NSRect) -> ToolbarRailFrames {
            place(
                around: selection,
                inside: display,
                annotationSize: .zero,
                optionsSize: .zero,
                actionSize: actionSize,
                margin: margin,
                gap: gap)
        }

        func leadingSpacingError(for frames: ToolbarRailFrames) -> CGFloat {
            let railMaxX = max(frames.annotations.maxX, frames.options.maxX)
            return abs((selection.minX - railMaxX) - gap)
        }

        func leadingMidpointOffset(for frames: ToolbarRailFrames) -> CGFloat {
            let railMidY = (frames.annotations.midY + frames.options.midY) / 2
            return abs(railMidY - selection.midY)
        }

        let leadingCandidates = displays.map(leadingFrames)
        let trailingCandidates = displays.map(trailingFrames)
        var bestLeadingIndex: Int?
        var bestLeadingScore = CGFloat.infinity
        var bestTrailingIndex: Int?
        var bestTrailingScore = CGFloat.infinity

        for index in displays.indices {
            let leading = leadingCandidates[index]
            let optionsFit = optionsSize.width <= 0 || optionsSize.height <= 0
                || displays[index].contains(leading.options)
            if displays[index].contains(leading.annotations) && optionsFit
                && leading.annotations.maxX <= selection.minX && leading.options.maxX <= selection.minX {
                let spacingError = leadingSpacingError(for: leading)
                let midpointOffset = leadingMidpointOffset(for: leading)
                let score = spacingError * spacingError + midpointOffset * midpointOffset
                if score < bestLeadingScore {
                    bestLeadingIndex = index
                    bestLeadingScore = score
                }
            }

            let trailing = trailingCandidates[index].actions
            if displays[index].contains(trailing) && trailing.minX >= selection.maxX {
                let spacingError = abs((trailing.minX - selection.maxX) - gap)
                let midpointOffset = abs(trailing.midY - selection.midY)
                let score = spacingError * spacingError + midpointOffset * midpointOffset
                if score < bestTrailingScore {
                    bestTrailingIndex = index
                    bestTrailingScore = score
                }
            }
        }

        let leadingIndex = bestLeadingIndex ?? displayIndex(nearest: selection.minX, onLeadingSide: true)
        let trailingIndex = bestTrailingIndex ?? displayIndex(nearest: selection.maxX, onLeadingSide: false)

        return ToolbarRailFrames(
            annotations: leadingCandidates[leadingIndex].annotations,
            options: leadingCandidates[leadingIndex].options,
            actions: trailingCandidates[trailingIndex].actions)
    }
}
