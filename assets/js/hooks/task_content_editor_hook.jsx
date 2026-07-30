import { createReactHook } from "./create_react_hook";

export const TaskContentEditor = createReactHook({
  name: "TaskContentEditor",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) => api.saveTaskContent(dataset.taskId, doc, opts),
    uploadImage: (file) => api.uploadTaskImage(dataset.taskId, file),
    placeholder: "Beginne mit einer Überschrift …",
  }),
});
