# Brief 116: preserve the composed provider button's accessible action

## Continue 115, one confirmed regression
The director rendered the real Korean ProductionEntry chooser in your copy. The composition is now visually readable: Google ink #1f1f1f, Apple white, both14px, logos beside titles, no overlap, intact consent and calm lighting. Preserve that layout.

The readback also proves each native Button now has empty text, empty accessibility_name, and empty accessibility_labeled_by_nodes. The visible action moved to Group/Title without binding it to the actual actionable control. Brief115 explicitly required preserving logical action/accessibility/localization. Fix this narrowly before acceptance.

## Deliverable
Bind each real provider Button's accessible action to its visible localized title (for example the Godot accessibility_labeled_by_nodes path to Group/Title, or an equivalent correctly auto-translated accessible name). The installed engine exposes that property. Current primary Control docs describe it as paths to nodes which label this node: https://docs.godotengine.org/en/latest/classes/class_control.html#class-control-property-accessibility-labeled-by-nodes

Keep native text empty to prevent duplicate drawing. Preserve official assets,14px typography, composition, masks,44px touch target, mouse-transparent children, honest disabled capabilities and native keyboard/pressed/focus semantics. Do not add another visible label or new UI. No title/input/native/backend/version changes.

Test that the real actionable buttons resolve to the visible title with the right five-locale text, including a live locale switch. Add a focused negative: remove the action-label binding and show the assertion fails; restore exactly. Existing state/layout/loading/exported-locale/harness checks must remain clean. Update the packet's existing author note accurately. No unrelated changes.
