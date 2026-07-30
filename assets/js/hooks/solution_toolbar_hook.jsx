import { createReactHook } from "./create_react_hook";

// Mounts the single shared toolbar for the Musterlösung view. All React
// logic lives in SharedSolutionToolbar.
export const SolutionToolbar = createReactHook({
  name: "SolutionToolbar",
  loadComponent: () => import("../react/SharedSolutionToolbar"),
  mapProps: () => ({}),
});
