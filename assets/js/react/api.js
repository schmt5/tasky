function getCSRFToken() {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute("content") : "";
}

async function request(url, options = {}) {
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
    "x-csrf-token": getCSRFToken(),
    ...options.headers,
  };

  const response = await fetch(url, { ...options, headers });

  // An expired session surfaces as a redirect to the login page (fetch
  // follows it, yielding HTML with status 200) or as a bare 401/403.
  // Retrying can never succeed — mark the error permanent so autosave
  // stops and asks the user to reload instead of looping forever.
  const isJson = (response.headers.get("content-type") || "").includes("json");

  if (
    response.redirected ||
    [401, 403].includes(response.status) ||
    (response.ok && !isJson)
  ) {
    const error = new Error("Sitzung abgelaufen – bitte Seite neu laden.");
    error.status = response.status;
    error.permanent = true;
    throw error;
  }

  if (!response.ok) {
    const errorBody = await response.text();
    let message;
    try {
      const parsed = JSON.parse(errorBody);
      message = parsed.error || parsed.message || response.statusText;
    } catch {
      message = response.statusText;
    }
    const error = new Error(message);
    error.status = response.status;
    throw error;
  }

  return response.json();
}

// `opts` is forwarded to fetch — used for `keepalive: true` on unload-time
// flushes so the last save survives the tab closing.
export function saveExamContent(examId, content, opts = {}) {
  return request(`/api/exams/${examId}/content`, {
    method: "PUT",
    body: JSON.stringify({ content }),
    ...opts,
  });
}

export function saveTaskContent(taskId, content, opts = {}) {
  return request(`/api/tasks/${taskId}/content`, {
    method: "PUT",
    body: JSON.stringify({ content }),
    ...opts,
  });
}

export function saveTaskAnswers(taskId, content, opts = {}) {
  return request(`/api/student/tasks/${taskId}/answers`, {
    method: "PUT",
    body: JSON.stringify({ content }),
    ...opts,
  });
}

export function saveExamSubmissionContent(token, content, opts = {}) {
  return request(`/api/guest/exam/${token}/content`, {
    method: "PUT",
    body: JSON.stringify({ content }),
    ...opts,
  });
}

export function saveExamSampleSolutionPart(examId, partId, nodes, opts = {}) {
  return request(`/api/exams/${examId}/sample-solution/parts/${partId}/content`, {
    method: "PUT",
    body: JSON.stringify({ nodes }),
    ...opts,
  });
}

export function saveExamCorrectionPart(examId, submissionId, partId, nodes, opts = {}) {
  return request(
    `/api/exams/${examId}/submissions/${submissionId}/parts/${partId}/content`,
    {
      method: "PUT",
      body: JSON.stringify({ nodes }),
      ...opts,
    },
  );
}

// Uploads an image file (multipart) and resolves to `{ url }`. Kept separate
// from `request` because it sends FormData, not JSON.
export async function uploadExamImage(examId, file) {
  return uploadImage(`/api/exams/${examId}/images`, file);
}

export async function uploadTaskImage(taskId, file) {
  return uploadImage(`/api/tasks/${taskId}/images`, file);
}

async function uploadImage(url, file) {
  const formData = new FormData();
  formData.append("image", file);

  const response = await fetch(url, {
    method: "POST",
    headers: { "x-csrf-token": getCSRFToken() },
    body: formData,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    let message;
    try {
      message = JSON.parse(errorBody).error || response.statusText;
    } catch {
      message = response.statusText;
    }
    throw new Error(message || "Bild-Upload fehlgeschlagen");
  }

  return response.json();
}
