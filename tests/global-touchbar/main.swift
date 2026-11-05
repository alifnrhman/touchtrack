import AppKit
import ObjectiveC
@_silgen_name("ytm_global_supported") func supported() -> Bool
// Capability-only probe: never presents a modal bar or changes user settings.
let modern = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
let legacy = NSSelectorFromString("presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:")
let dismissModern = NSSelectorFromString("dismissSystemModalTouchBar:")
let dismissLegacy = NSSelectorFromString("dismissSystemModalFunctionBar:")
let hasPresentation = class_getClassMethod(NSTouchBar.self, modern) != nil || class_getClassMethod(NSTouchBar.self, legacy) != nil
let hasDismiss = class_getClassMethod(NSTouchBar.self, dismissModern) != nil || class_getClassMethod(NSTouchBar.self, dismissLegacy) != nil
print("Presentation selector present: \(hasPresentation)")
print("Dismiss selector present: \(hasDismiss)")
print("Validated global bridge supported: \(supported())")
if supported() && (!hasPresentation || !hasDismiss) { fatalError("Invalid capability result") }
print("Capability probe passed without presentation")
