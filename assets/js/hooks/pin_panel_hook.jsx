import { createReactHook } from "./create_react_hook";

// The "Pins" section of a question's card in the Musterlösung, bound to the
// part editor beside it through the solutionEditorStore (react/PinPanel.jsx).
export const PinPanel = createReactHook({
  name: "PinPanel",
  loadComponent: () => import("../react/PinPanel"),
  mapProps: (_hook, { dataset }) => ({ partId: dataset.partId }),
});
